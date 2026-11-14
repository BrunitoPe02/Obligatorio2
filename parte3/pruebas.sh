#!/bin/bash
# Obligatorio 2 - Parte 3: plan de pruebas automatizado.
#
# Uso (en la VM, con el lab ya levantado con "kathara lstart"):
#   cd parte3
#   ./pruebas.sh            # corre la matriz y junta evidencia
#   ./pruebas.sh --pcap     # ademas guarda capturas de NAT y de la politica P4 en shared/
#
# Salida: resultados/resumen.txt (tabla esperado vs observado),
#         resultados/NN_*.txt (salida de cada prueba) y resultados/evidencia_*.txt.

cd "$(dirname "$0")" || exit 1
OUT=resultados
mkdir -p "$OUT"
rm -f "$OUT"/*.txt   # cada corrida empieza limpia
PCAP=0; [ "${1:-}" = "--pcap" ] && PCAP=1

ex() {  # ex <equipo> <modo> [args...]  -> salida del helper dentro del equipo
    kathara exec "$1" -- bash /shared/t.sh "${@:2}" 2>&1
}

esperar() {  # esperar <descripcion> <segundos> <equipo> <modo> [args...]
    local desc="$1" max="$2"; shift 2
    printf "Esperando %s " "$desc"
    for ((i = 0; i < max; i += 3)); do
        if ex "$@" | grep -q "RESULTADO=OK"; then echo " listo (${i}s)"; return 0; fi
        printf "."; sleep 3
    done
    echo " NO respondio en ${max}s (sigo igual, revisar)"
}

leer_cnt() {  # leer_cnt <switch> <contador> <idx> -> numero de paquetes
    local salida
    salida=$(ex "$1" p4cnt "$2" "$3")
    { echo "=== $1 $2[$3]"; echo "$salida"; } >> "$OUT/evidencia_p4.txt"   # salida cruda, para depurar
    echo "$salida" | grep -o "PAQUETES=[0-9]*" | cut -d= -f2
}

# ---------------------------------------------------------------------------
# 0) Esperar a que el lab este listo
# ---------------------------------------------------------------------------
esperar "switches P4" 120 p4sw3 p4ready
esperar "switches P4" 60  p4sw1 p4ready
esperar "OSPF: r1 aprende 203.0.113.96/27" 120 r1 route 203.0.113.96/27
esperar "OSPF: r1 aprende 203.0.113.32/28" 60  r1 route 203.0.113.32/28

# ---------------------------------------------------------------------------
# 1) Matriz: id | origen | modo | destino | esperado | descripcion
# ---------------------------------------------------------------------------
PRUEBAS="
01|pc_admin1|ping|8.8.8.8|OK|A(ADMIN) a Internet con NAT
02|pc_dev1|ping|8.8.8.8|OK|A(DEV) a Internet con NAT
03|pc_guest1|ping|8.8.8.8|FALLA|Invitado a Internet: bloqueado por P4
04a|pcb1|ping|8.8.8.8|OK|B a Internet con NAT
04b|pcb2|ping|8.8.8.8|OK|B a Internet con NAT
04c|pcb3|ping|8.8.8.8|OK|B a Internet con NAT
05|srv1|ping|8.8.8.8|OK|srv1 a Internet sin NAT (ruta nueva en rint)
06|pcint|ping|10.77.2.130|FALLA|Privada de A inalcanzable desde Internet
07a|pcint|http|203.0.113.98|OK|Internet a srv1 HTTP
07b|pcint|https|203.0.113.98|OK|Internet a srv1 HTTPS
08a|pcint|http|203.0.113.34|OK|Internet a srvB
08b|pcint|http|203.0.113.35|OK|Internet a srvb2
09|pcb1|http|203.0.113.98|OK|Cliente B a servidor de A
10|pc_admin1|http|203.0.113.34|OK|Cliente A a servidor de B
11a|pcc|ping|203.0.113.65|OK|C interna: pcC a su gateway (rclC)
11b|pcc|ping|8.8.8.8|OK|C a Internet sin NAT (LAN publica)
11c|pcint|ping|203.0.113.66|OK|Internet a pcC (LAN publica, sin NAT)
11d|pcc|http|203.0.113.98|OK|C a servidor de A (srv1)
11e|pcc|http|203.0.113.34|OK|C a servidor de B (srvB)
11f|pc_admin1|ping|203.0.113.66|OK|A (con NAT) a pcC
11g|pcb1|ping|203.0.113.66|OK|B (con NAT) a pcC
11h|pc_guest1|ping|203.0.113.66|FALLA|Invitado de A a pcC: bloqueado por P4
11i|pcc|ping|10.77.2.130|FALLA|C a privada de A: sin ruta en el backbone
12|pc_admin1|ping|10.77.0.10|FALLA|Privada de B no alcanzable (solapamiento + NAT)
13|pc_admin1|ping|10.77.2.2|OK|ADMIN a DEV (ruteo en rcla)
14a|pc_admin1|ping|203.0.113.98|OK|ADMIN a srv1 ICMP
14b|pc_admin1|http|203.0.113.98|OK|ADMIN a srv1 HTTP
15|pc_guest1|ping|10.77.0.1|OK|Invitado al gateway
16a|pc_guest1|http|203.0.113.98|OK|Invitado a srv1:80
16b|pc_guest1|https|203.0.113.98|OK|Invitado a srv1:443
17|pc_guest1|ping|203.0.113.98|FALLA|Invitado a srv1 ICMP: bloqueado
18|pc_guest1|http|203.0.113.34|FALLA|Invitado a srvB: bloqueado
19|pc_admin1|ping|10.77.0.2|FALLA|ADMIN a invitado: reply descartado (stateless)
20|pc_admin4|ping|10.77.2.129|FALLA|pc_admin4 no registrado: port security
21a|pcb1|ping|10.77.0.11|OK|LAN B interna
21b|pcb1|ping|10.77.0.12|OK|LAN B interna
22a|pcb1|http|203.0.113.34|OK|LAN B a DMZ (srvB)
22b|pcb1|http|203.0.113.35|OK|LAN B a DMZ (srvb2)
"

# Contadores P4 de la politica de invitados ANTES
pol_ok_0=$(leer_cnt p4sw3 guest_policy_cnt 0)
pol_dr_0=$(leer_cnt p4sw3 guest_policy_cnt 1)
psec_0=$(leer_cnt p4sw1 portsec_viol_cnt 5)   # puerto 5 = eth4 = pc_admin4

if [ $PCAP -eq 1 ]; then
    echo "Iniciando capturas en shared/ (se cortan al terminar la matriz) ..."
    ex rcla  capstart eth0 p3_rcla_eth0_admin.pcap > /dev/null
    ex rcla  capstart eth4 p3_rcla_eth4_isp.pcap   > /dev/null
    ex p4sw3 capstart eth1 p3_sw3_eth1_guest1.pcap > /dev/null
    ex p4sw3 capstart eth0 p3_sw3_eth0_rcla.pcap   > /dev/null
fi

RES="$OUT/resumen.txt"
{
    echo "Parte 3 - Resultados de la matriz de pruebas"
    echo "Fecha: $(date '+%Y-%m-%d %H:%M:%S')"
    echo
    printf "%-4s %-10s %-6s %-14s %-9s %-9s %-5s %s\n" ID ORIGEN MODO DESTINO ESPERADO OBSERVADO "" DESCRIPCION
    printf '%.0s-' {1..110}; echo
} > "$RES"

total=0; bien=0; errores=0
while IFS='|' read -r id org modo dst esp desc; do
    [ -z "$id" ] && continue
    total=$((total + 1))
    salida=$(ex "$org" "$modo" "$dst")
    echo "$salida" > "$OUT/${id}_${org}_${modo}_${dst}.txt"
    # Tres resultados posibles. Si la salida no trae RESULTADO=, la prueba no llego
    # a ejecutarse (lab caido, equipo inexistente, error de kathara exec): es ERROR,
    # nunca FALLA, para que una prueba negativa no "pase" sin haber probado nada.
    if   echo "$salida" | grep -q "RESULTADO=OK";    then obs=OK
    elif echo "$salida" | grep -q "RESULTADO=FALLA"; then obs=FALLA
    else obs=ERROR; errores=$((errores + 1)); fi
    if   [ "$obs" = "ERROR" ]; then marca="ERR"
    elif [ "$obs" = "$esp" ];  then marca="PASA"; bien=$((bien + 1))
    else marca="XXX"; fi
    linea=$(printf "%-4s %-10s %-6s %-14s %-9s %-9s %-5s %s" "$id" "$org" "$modo" "$dst" "$esp" "$obs" "$marca" "$desc")
    echo "$linea"; echo "$linea" >> "$RES"
done <<< "$PRUEBAS"

if [ $PCAP -eq 1 ]; then
    ex rcla  capstop > /dev/null
    ex p4sw3 capstop > /dev/null
fi

pol_ok_1=$(leer_cnt p4sw3 guest_policy_cnt 0)
pol_dr_1=$(leer_cnt p4sw3 guest_policy_cnt 1)
psec_1=$(leer_cnt p4sw1 portsec_viol_cnt 5)

{
    echo
    echo "Coinciden con lo esperado: $bien / $total"
    echo "No se pudieron ejecutar (ERROR): $errores"
    echo
    echo "Contadores P4 de p4sw3 (guest_policy_cnt) durante las pruebas:"
    echo "  permitidos:  ${pol_ok_0:-?} -> ${pol_ok_1:-?}  (delta $(( ${pol_ok_1:-0} - ${pol_ok_0:-0} )))"
    echo "  descartados: ${pol_dr_0:-?} -> ${pol_dr_1:-?}  (delta $(( ${pol_dr_1:-0} - ${pol_dr_0:-0} )))"
    echo "Contador de port security en p4sw1 (violaciones en el puerto de pc_admin4):"
    echo "  violaciones: ${psec_0:-?} -> ${psec_1:-?}  (delta $(( ${psec_1:-0} - ${psec_0:-0} )))"
} | tee -a "$RES"

# ---------------------------------------------------------------------------
# 2) Evidencia: OSPF, caminos, NAT
# ---------------------------------------------------------------------------
echo; echo "Juntando evidencia..."
for r in r1 r2 r3 r4 r5 r6 r7 r8; do
    { echo "=== $r"; ex $r ospfnei; } >> "$OUT/evidencia_ospf_vecinos.txt"
done
for r in r1 r3 r5; do
    { echo "=== $r"; ex $r ospfroute; } >> "$OUT/evidencia_ospf_rutas.txt"
done
{ echo "=== pc_admin1 -> 8.8.8.8"; ex pc_admin1 trace 8.8.8.8
  echo "=== pcb1 -> 8.8.8.8";      ex pcb1 trace 8.8.8.8
  echo "=== pcint -> srv1";        ex pcint trace 203.0.113.98
  echo "=== pcint -> pcC";         ex pcint trace 203.0.113.66
} > "$OUT/evidencia_traceroute.txt"
{ echo "=== rcla"; ex rcla nat; echo "=== rclb"; ex rclb nat; } > "$OUT/evidencia_nat.txt"


echo "Listo. Ver $OUT/resumen.txt y $OUT/evidencia_*.txt"
[ $PCAP -eq 1 ] && echo "Capturas en shared/p3_*.pcap (cubren toda la matriz)"
