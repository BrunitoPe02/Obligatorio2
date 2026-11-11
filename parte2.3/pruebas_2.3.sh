#!/bin/bash
# Obligatorio 2 - Parte 2.3: plan de pruebas de la politica de acceso de INVITADOS.
#
# Uso (en la VM):
#   cd parte2.3
#   kathara lclean; kathara lstart
#   ./pruebas_2.3.sh
#
# Cada prueba pone en cero los contadores de los switches involucrados, vacia la cache
# ARP de los hosts, (opcionalmente) captura, genera el trafico y lee los contadores.
#
# Salida:
#   resultados/resumen.txt        esperado vs observado + verificaciones de contadores
#   resultados/<ID>.txt           salida de los comandos, contadores y capturas decodificadas
#   resultados/<ID>_cnt_<sw>.txt  foto de los contadores de ese switch
#   resultados/estado_p4sw3.txt   table_dump de port_role, guest_acl y mac_fwd
#   shared/p23_*.pcap             capturas
#
# Mapa de p4sw3:
#   puertos P4: 1 = rcla (eth0), 2 = pc_guest1 (eth1), 3 = pc_guest2 (eth2), 4 = pc_guest3 (eth3)
#   handles de guest_acl: 0 = ARP al gateway, 1 = IPv4 al gateway, 2 = HTTP srv1, 3 = HTTPS srv1

cd "$(dirname "$0")" || exit 1
OUT=resultados
mkdir -p "$OUT"
rm -f "$OUT"/*.txt
RES="$OUT/resumen.txt"

GW=10.77.0.1; SRV1=203.0.113.34
GUEST1=10.77.0.2; GUEST2=10.77.0.3; ADMIN1=10.77.2.130

ex() { kathara exec "$1" -- bash /shared/t.sh "${@:2}" 2>&1; }

# cnt <archivo> <contador> <idx> -> paquetes
cnt() { grep -F "$2[$3] " "$1" | grep -oE "pkts=[0-9]+" | cut -d= -f2 | head -1; }
pol_ok()  { cnt "$1" MyIngress.guest_policy_cnt 0; }
pol_deny(){ cnt "$1" MyIngress.guest_policy_cnt 1; }
acl()     { cnt "$1" MyIngress.guest_acl_cnt "$2"; }

total=0; bien=0
anotar() {  # anotar <ok|xxx> <texto>
    total=$((total + 1))
    if [ "$1" = ok ]; then bien=$((bien + 1)); m="PASA"; else m="XXX "; fi
    echo "  [$m] $2" | tee -a "$RES"
}
chequear() {  # chequear <descripcion> <observado> <op> <esperado>
    local obs="${2:-?}"
    if [ "$obs" != "?" ] && [ "$obs" "$3" "$4" ]; then anotar ok "$1 = $obs (esperado $3 $4)"
    else anotar xxx "$1 = $obs (esperado $3 $4)"; fi
}
resultado() {  # resultado <descripcion> <salida> <OK|FALLA esperado>
    local obs=FALLA
    echo "$2" | grep -q "RESULTADO=OK" && obs=OK
    if [ "$obs" = "$3" ]; then anotar ok "$1: $obs"; else anotar xxx "$1: $obs, se esperaba $3"; fi
}

# ---- estructura de cada prueba ----
inicio() {  # inicio <ID> <descripcion> <switches a resetear> <hosts a vaciar>
    ID="$1"; LOG="$OUT/$1.txt"
    { echo; echo "== $1: $2"; } | tee -a "$RES"
    echo "### $1 - $2" > "$LOG"
    for sw in $3; do ex "$sw" reset > /dev/null; done
    for h in $4; do ex "$h" flush > /dev/null; done
}
paso() {  # paso <equipo> <modo> [args] -> ejecuta, registra en el log y devuelve la salida
    local s; s=$(ex "$@")
    { echo; echo "### $1: ${*:2}"; echo "$s" | grep -v RESULTADO; } >> "$LOG"
    echo "$s"
}
leer() {  # leer <switch> <npuertos> <nmac> <nacl> -> deja la foto en $F
    sleep 2
    F="$OUT/${ID}_cnt_$1.txt"
    ex "$1" cnts "$2" "$3" "$4" > "$F"
    { echo; echo "### Contadores de $1 (en cero al empezar la prueba)"; cat "$F"; } >> "$LOG"
}
cap_ini() { for c in "$@"; do IFS=: read -r h a i <<< "$c"; ex "$h" capstart "$a" "${i:-eth0}" > /dev/null; done; }
cap_fin() {
    sleep 2
    for c in "$@"; do IFS=: read -r h a i <<< "$c"; ex "$h" capstop > /dev/null; done
    for c in "$@"; do
        IFS=: read -r h a i <<< "$c"
        { echo; echo "### Captura $a ($h ${i:-eth0})"; ex "$h" resumenpcap "$a" | grep -v RESULTADO; } >> "$LOG"
    done
}
pc() { ex "$1" pcapcount "$2" "$3" | grep -oE "^ *[0-9]+" | tr -d ' ' | head -1; }  # pc <equipo> <pcap> <filtro>

# ---------------------------------------------------------------------------
# 0) Esperar a los switches y guardar el estado del plano de control
# ---------------------------------------------------------------------------
for sw in p4sw1 p4sw2 p4sw3 p4sw4; do
    printf "Esperando %s " "$sw"
    for ((i = 0; i < 120; i += 3)); do
        ex "$sw" p4ready | grep -q RESULTADO=OK && break; printf "."; sleep 3
    done; echo " listo"
done
{ echo "Parte 2.3 - Plan de pruebas de la politica de INVITADOS"; echo "Fecha: $(date '+%Y-%m-%d %H:%M:%S')"; } > "$RES"
ex p4sw3 estado | grep -v RESULTADO > "$OUT/estado_p4sw3.txt"

# ---------------------------------------------------------------------------
# P1 + P4) Requisitos 1 y 2: HTTP permitido y ping bloqueado, capturando a ambos
#          lados de p4sw3 (eth1 = desde guest1, eth0 = hacia rcla)
# ---------------------------------------------------------------------------
inicio R1 "guest1: curl HTTP a srv1 (permitido) + ping a srv1 (bloqueado)" "p4sw3" "pc_guest1 rcla"
CAPS="p4sw3:p23_r1_sw3_eth1_guest1.pcap:eth1 p4sw3:p23_r1_sw3_eth0_rcla.pcap:eth0"
cap_ini $CAPS
s1=$(paso pc_guest1 curl "http://$SRV1/")
s2=$(paso pc_guest1 ping "$SRV1" 3)
leer p4sw3 4 5 4
cap_fin $CAPS
resultado "P1 curl http://$SRV1 desde guest1" "$s1" OK
resultado "P4 ping $SRV1 desde guest1" "$s2" FALLA
chequear "SYN a srv1:80 visto en eth1 (entrada)" "$(pc p4sw3 p23_r1_sw3_eth1_guest1.pcap syn)" -eq 1
chequear "SYN a srv1:80 visto en eth0 (salida)"  "$(pc p4sw3 p23_r1_sw3_eth0_rcla.pcap  syn)" -eq 1
chequear "ICMP echo request en eth1 (entrada)" "$(pc p4sw3 p23_r1_sw3_eth1_guest1.pcap echo)" -eq 3
chequear "ICMP echo request en eth0 (salida)"  "$(pc p4sw3 p23_r1_sw3_eth0_rcla.pcap  echo)" -eq 0
ok=$(pol_ok "$F"); dn=$(pol_deny "$F")
chequear "descartados guest_policy_cnt[1] (los 3 ICMP)" "$dn" -eq 3
chequear "regla HTTP guest_acl_cnt[2]" "$(acl "$F" 2)" -ge 10
chequear "regla HTTPS guest_acl_cnt[3]" "$(acl "$F" 3)" -eq 0
suma=$(( $(acl "$F" 0) + $(acl "$F" 1) + $(acl "$F" 2) + $(acl "$F" 3) ))
chequear "permitidos guest_policy_cnt[0] = suma de guest_acl_cnt" "$ok" -eq "$suma"
chequear "recibidos de guest1 port_in_cnt[2] = permitidos + descartados" "$(cnt "$F" MyIngress.port_in_cnt 2)" -eq $((ok + dn))
chequear "unknown_drop_cnt" "$(cnt "$F" MyIngress.unknown_drop_cnt 0)" -eq 0

# ---------------------------------------------------------------------------
# P2) HTTPS a srv1 (regla 4)
# ---------------------------------------------------------------------------
inicio P2 "guest1: curl HTTPS a srv1" "p4sw3" "pc_guest1"
s=$(paso pc_guest1 curl "https://$SRV1/"); leer p4sw3 4 5 4
resultado "curl https://$SRV1 desde guest1" "$s" OK
chequear "regla HTTPS guest_acl_cnt[3]" "$(acl "$F" 3)" -ge 5
chequear "descartados guest_policy_cnt[1]" "$(pol_deny "$F")" -eq 0

# ---------------------------------------------------------------------------
# P3) Comunicacion con el gateway (reglas 1 y 2)
# ---------------------------------------------------------------------------
inicio P3 "guest1: ping al gateway $GW" "p4sw3" "pc_guest1 rcla"
s=$(paso pc_guest1 ping "$GW" 3); leer p4sw3 4 5 4
resultado "ping $GW desde guest1" "$s" OK
chequear "regla ARP al gateway guest_acl_cnt[0]" "$(acl "$F" 0)" -ge 1
chequear "regla IPv4 al gateway guest_acl_cnt[1] (3 echo request)" "$(acl "$F" 1)" -eq 3
chequear "descartados guest_policy_cnt[1]" "$(pol_deny "$F")" -eq 0

# ---------------------------------------------------------------------------
# P5) Invitado -> invitado: el ARP pregunta por 10.77.0.3, no por el gateway
#     (en la 2.2 esta misma prueba funcionaba)
# ---------------------------------------------------------------------------
inicio P5 "guest1: ping a guest2 $GUEST2" "p4sw3" "pc_guest1 pc_guest2"
cap_ini "pc_guest2:p23_p5_guest2.pcap"
s=$(paso pc_guest1 ping "$GUEST2" 3); leer p4sw3 4 5 4
cap_fin "pc_guest2:p23_p5_guest2.pcap"
resultado "ping $GUEST2 desde guest1" "$s" FALLA
chequear "ARP requests de guest1 descartados guest_policy_cnt[1]" "$(pol_deny "$F")" -ge 1
chequear "tramas entregadas a guest2 port_out_cnt[3]" "$(cnt "$F" MyEgress.port_out_cnt 3)" -eq 0
chequear "regla broadcast mac_fwd_cnt[4] (no se llega a aplicar)" "$(cnt "$F" MyIngress.mac_fwd_cnt 4)" -eq 0

# ---------------------------------------------------------------------------
# P6) Otros destinos/puertos bloqueados
# ---------------------------------------------------------------------------
inicio P6a "guest1: ping a admin1 $ADMIN1" "p4sw3" "pc_guest1"
s=$(paso pc_guest1 ping "$ADMIN1" 3); leer p4sw3 4 5 4
resultado "ping $ADMIN1 desde guest1" "$s" FALLA
chequear "descartados guest_policy_cnt[1]" "$(pol_deny "$F")" -eq 3

inicio P6b "guest1: TCP a srv1:22 (puerto no permitido)" "p4sw3" "pc_guest1"
s=$(paso pc_guest1 tcp "$SRV1" 22); leer p4sw3 4 5 4
resultado "TCP $SRV1:22 desde guest1" "$s" FALLA
chequear "SYN descartados guest_policy_cnt[1]" "$(pol_deny "$F")" -ge 1
chequear "regla HTTP guest_acl_cnt[2]" "$(acl "$F" 2)" -eq 0
chequear "regla HTTPS guest_acl_cnt[3]" "$(acl "$F" 3)" -eq 0

# ---------------------------------------------------------------------------
# P7) ADMIN y DESARROLLO no se ven afectados
# ---------------------------------------------------------------------------
inicio P7a "admin1: ping y curl a srv1" "p4sw1 p4sw3" "pc_admin1"
s1=$(paso pc_admin1 ping "$SRV1" 3); s2=$(paso pc_admin1 curl "http://$SRV1/")
s3=$(paso pc_admin1 tcp "$SRV1" 443)
leer p4sw1 5 5 0
resultado "ping $SRV1 desde admin1" "$s1" OK
resultado "curl http://$SRV1 desde admin1" "$s2" OK
resultado "TCP $SRV1:443 desde admin1" "$s3" OK
chequear "p4sw1 guest_policy_cnt[0] (no evalua la ACL)" "$(pol_ok "$F")" -eq 0
chequear "p4sw1 guest_policy_cnt[1]" "$(pol_deny "$F")" -eq 0

inicio P7b "dev1: ping a srv1 y a admin1" "p4sw2" "pc_dev1"
s1=$(paso pc_dev1 ping "$SRV1" 3); s2=$(paso pc_dev1 ping "$ADMIN1" 3)
s3=$(paso pc_dev1 curl "https://$SRV1/")
leer p4sw2 4 5 0
resultado "ping $SRV1 desde dev1" "$s1" OK
resultado "ping $ADMIN1 desde dev1" "$s2" OK
resultado "curl https://$SRV1 desde dev1" "$s3" OK
chequear "p4sw2 guest_policy_cnt[1]" "$(pol_deny "$F")" -eq 0

# ---------------------------------------------------------------------------
# Requisito 3 - Situacion A: admin1 -> guest1. El request llega, el reply muere.
# ---------------------------------------------------------------------------
inicio SA "stateless A: admin1 hace ping a guest1" "p4sw3" "pc_admin1 pc_guest1 rcla"
CAPS="pc_guest1:p23_sa_guest1.pcap p4sw3:p23_sa_sw3_eth0_rcla.pcap:eth0"
cap_ini $CAPS
s=$(paso pc_admin1 ping "$GUEST1" 3); leer p4sw3 4 5 4
cap_fin $CAPS
resultado "ping $GUEST1 desde admin1" "$s" FALLA
chequear "echo request recibidos por guest1" "$(pc pc_guest1 p23_sa_guest1.pcap echo)" -eq 3
chequear "echo reply enviados por guest1"   "$(pc pc_guest1 p23_sa_guest1.pcap echoreply)" -eq 3
chequear "echo reply que salen de p4sw3 hacia rcla" "$(pc p4sw3 p23_sa_sw3_eth0_rcla.pcap echoreply)" -eq 0
chequear "replies descartados guest_policy_cnt[1]" "$(pol_deny "$F")" -eq 3

# ---------------------------------------------------------------------------
# Situacion B: srv1 abre TCP desde su puerto 80 hacia guest1. El SYN-ACK pasa.
# ---------------------------------------------------------------------------
inicio SB "stateless B: srv1 (puerto origen 80) abre TCP hacia guest1:5555" "p4sw3" "pc_guest1"
paso pc_guest1 listen 5555 > /dev/null
CAPS="p4sw3:p23_sb_sw3_eth0_rcla.pcap:eth0"
cap_ini $CAPS
s=$(paso srv1 hping_syn80 "$GUEST1" 5555); leer p4sw3 4 5 4
cap_fin $CAPS
echo "$s" | grep -q "flags=SA" && anotar ok "hping3 en srv1 recibe flags=SA de guest1" \
                               || anotar xxx "hping3 en srv1 no recibe flags=SA"
chequear "SYN-ACK de guest1 que salen hacia rcla" "$(pc p4sw3 p23_sb_sw3_eth0_rcla.pcap synack_guest1)" -ge 1
chequear "permitidos por la regla HTTP guest_acl_cnt[2]" "$(acl "$F" 2)" -ge 2
chequear "descartados guest_policy_cnt[1]" "$(pol_deny "$F")" -eq 0

# ---------------------------------------------------------------------------
# Situacion C: ACK suelto de guest1 a srv1:80 (sin conexion). srv1 responde RST.
# ---------------------------------------------------------------------------
inicio SC "stateless C: ACK fuera de conexion de guest1 a srv1:80" "p4sw3" "pc_guest1"
CAPS="p4sw3:p23_sc_sw3_eth0_rcla.pcap:eth0"
cap_ini $CAPS
s=$(paso pc_guest1 hping_ack "$SRV1" 80); leer p4sw3 4 5 4
cap_fin $CAPS
echo "$s" | grep -q "flags=R" && anotar ok "hping3 en guest1 recibe flags=R de srv1" \
                              || anotar xxx "hping3 en guest1 no recibe flags=R"
chequear "ACK sueltos permitidos por la regla HTTP guest_acl_cnt[2]" "$(acl "$F" 2)" -ge 2
chequear "descartados guest_policy_cnt[1]" "$(pol_deny "$F")" -eq 0

{
    echo; echo "========================================"
    echo "Verificaciones que coinciden con lo esperado: $bien / $total"
} | tee -a "$RES"
echo "Detalle en $OUT/ y capturas en shared/p23_*.pcap"
