#!/bin/bash
# Obligatorio 2 - Parte 2.2: plan de pruebas del switch P4 (forwarding L2).
#
# Uso (en la VM):
#   cd parte2.2
#   kathara lclean; kathara lstart
#   ./pruebas_2.2.sh
#
# Cada prueba: vacia la cache ARP de los hosts involucrados, pone en cero los contadores
# del switch, captura en los hosts indicados, hace el ping y lee los contadores.
# Las pruebas son independientes entre si (en particular la Reflexion a y b, cuyo
# resultado depende de que la cache ARP este vacia).
#
# Salida:
#   resultados/resumen.txt         tabla esperado vs observado + verificaciones de contadores
#   resultados/<ID>_*.txt          salida del ping, contadores del switch y pcaps decodificados
#   resultados/estado_switches.txt table_dump + mc_dump de los 4 switches
#   shared/p22_*.pcap              capturas
#
# Mapa de p4sw1 (puertos P4 / handles de mac_fwd):
#   puerto 1 = rcla, 2 = pc_admin1, 3 = pc_admin2, 4 = pc_admin3, 5 = pc_admin4 (no registrado)
#   handle 0 = rcla, 1 = admin1, 2 = admin2, 3 = admin3, 4 = broadcast, 5 = admin4 (solo tras alta)

cd "$(dirname "$0")" || exit 1
OUT=resultados
mkdir -p "$OUT"
rm -f "$OUT"/*.txt
RES="$OUT/resumen.txt"

ex() { kathara exec "$1" -- bash /shared/t.sh "${@:2}" 2>&1; }

# cnt <archivo> <contador> <idx> -> paquetes (de la foto de contadores guardada en el archivo)
cnt() { grep -F "$2[$3] " "$1" | grep -oE "pkts=[0-9]+" | cut -d= -f2 | head -1; }

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

# prueba <ID> <desc> <switch> <npuertos> <nreglas> <origen> <ip destino> <OK|FALLA> <hosts a vaciar> <capturas>
#   <capturas> = lista "host:archivo" o "host:archivo:in", separada por espacios
# Deja la foto de contadores en $OUT/<ID>_contadores.txt (variable global F).
prueba() {
    local id="$1" desc="$2" sw="$3" np="$4" nr="$5" org="$6" dst="$7" esp="$8" hosts="$9" caps="${10}"
    local log="$OUT/${id}_${org}_a_${dst}.txt"
    F="$OUT/${id}_contadores.txt"
    { echo; echo "== $id: $desc"; } | tee -a "$RES"

    for h in $hosts; do ex "$h" flush > /dev/null; done
    ex "$sw" reset > /dev/null
    for c in $caps; do IFS=: read -r h a d <<< "$c"; ex "$h" capstart "$a" $d > /dev/null; done

    salida=$(ex "$org" ping "$dst")
    sleep 2   # dejar que llegue trafico tardio (ARP de confirmacion, etc.)

    for c in $caps; do IFS=: read -r h a d <<< "$c"; ex "$h" capstop > /dev/null; done
    ex "$sw" cnts "$np" "$nr" > "$F"

    {
        echo "### $id - $desc"; echo "### $org -> $dst"; echo
        echo "$salida"; echo
        echo "### Contadores de $sw (puestos en cero antes de la prueba)"; cat "$F"
        for c in $caps; do
            IFS=: read -r h a d <<< "$c"
            echo; echo "### Captura $a en $h ${d:+(solo entrante)}"; ex "$h" resumenpcap "$a" | grep -v RESULTADO
        done
    } > "$log"

    if echo "$salida" | grep -q "RESULTADO=OK"; then obs=OK; else obs=FALLA; fi
    perdida=$(echo "$salida" | grep -oE "[0-9]+% packet loss")
    if [ "$obs" = "$esp" ]; then anotar ok "ping $org -> $dst: $obs ($perdida)"
    else anotar xxx "ping $org -> $dst: $obs ($perdida), se esperaba $esp"; fi
}

# ---------------------------------------------------------------------------
# 0) Esperar a los switches y dejar p4sw1 como en commands.txt
# ---------------------------------------------------------------------------
for sw in p4sw1 p4sw2 p4sw3 p4sw4; do
    printf "Esperando %s " "$sw"
    for ((i = 0; i < 120; i += 3)); do
        ex "$sw" p4ready | grep -q RESULTADO=OK && break; printf "."; sleep 3
    done; echo " listo"
done
ex p4sw1 baja_admin4 > /dev/null   # por si quedo de una corrida anterior

{ echo "Parte 2.2 - Plan de pruebas del switch P4"; echo "Fecha: $(date '+%Y-%m-%d %H:%M:%S')"; } > "$RES"

for sw in p4sw1 p4sw2 p4sw3 p4sw4; do
    { echo "=================== $sw"; ex "$sw" estado; } >> "$OUT/estado_switches.txt"
done

# ---------------------------------------------------------------------------
# P1) Red de 3 hosts en p4sw1: conectividad entre todos los pares
# ---------------------------------------------------------------------------
prueba P1a "ADMIN: pc_admin1 -> pc_admin2 (unicast + ARP)" p4sw1 5 5 \
    pc_admin1 10.77.2.131 OK "pc_admin1 pc_admin2" "pc_admin2:p22_p1a_admin2.pcap"
chequear "unknown_drop_cnt" "$(cnt $F MyIngress.unknown_drop_cnt 0)" -eq 0
chequear "regla broadcast (mac_fwd_cnt[4])" "$(cnt $F MyIngress.mac_fwd_cnt 4)" -ge 1

prueba P1b "ADMIN: pc_admin1 -> pc_admin3" p4sw1 5 5 \
    pc_admin1 10.77.2.132 OK "pc_admin1 pc_admin3" "pc_admin3:p22_p1b_admin3.pcap"
chequear "unknown_drop_cnt" "$(cnt $F MyIngress.unknown_drop_cnt 0)" -eq 0

prueba P1c "ADMIN: pc_admin2 -> pc_admin3" p4sw1 5 5 \
    pc_admin2 10.77.2.132 OK "pc_admin2 pc_admin3" "pc_admin3:p22_p1c_admin3.pcap"
chequear "unknown_drop_cnt" "$(cnt $F MyIngress.unknown_drop_cnt 0)" -eq 0

# ---------------------------------------------------------------------------
# P2) El broadcast no vuelve por el puerto de entrada.
#     Ping a una IP libre de ADMIN: pc_admin1 solo emite ARP requests (nadie responde),
#     asi que todo lo que el switch hace es replicar broadcasts originados en el puerto 2.
# ---------------------------------------------------------------------------
prueba P2 "Broadcast: copia al puerto de entrada descartada (ARP a IP libre)" p4sw1 5 5 \
    pc_admin1 10.77.2.150 FALLA "pc_admin1" "pc_admin1:p22_p2_admin1_entrante.pcap:in pc_admin2:p22_p2_admin2.pcap"
nb=$(cnt $F MyIngress.mac_fwd_cnt 4)
chequear "ARP requests de admin1 (port_in_cnt[2])" "$(cnt $F MyIngress.port_in_cnt 2)" -ge 1
chequear "copias devueltas a admin1 (port_out_cnt[2])" "$(cnt $F MyEgress.port_out_cnt 2)" -eq 0
chequear "copias a rcla (port_out_cnt[1])" "$(cnt $F MyEgress.port_out_cnt 1)" -eq "${nb:-0}"
chequear "copias a admin2 (port_out_cnt[3])" "$(cnt $F MyEgress.port_out_cnt 3)" -eq "${nb:-0}"
chequear "copias a admin3 (port_out_cnt[4])" "$(cnt $F MyEgress.port_out_cnt 4)" -eq "${nb:-0}"
chequear "copias a admin4 no registrado (port_out_cnt[5])" "$(cnt $F MyEgress.port_out_cnt 5)" -eq 0

# ---------------------------------------------------------------------------
# P3) Gateway y P4) los otros tres switches
# ---------------------------------------------------------------------------
prueba P3 "ADMIN: pc_admin1 -> gateway rcla eth0" p4sw1 5 5 \
    pc_admin1 10.77.2.129 OK "pc_admin1" ""
chequear "regla rcla (mac_fwd_cnt[0])" "$(cnt $F MyIngress.mac_fwd_cnt 0)" -ge 4

prueba P4a "DESARROLLO (p4sw2): pc_dev1 -> pc_dev2" p4sw2 4 5 \
    pc_dev1 10.77.2.3 OK "pc_dev1 pc_dev2" ""
chequear "unknown_drop_cnt" "$(cnt $F MyIngress.unknown_drop_cnt 0)" -eq 0

prueba P4b "INVITADOS (p4sw3): pc_guest1 -> pc_guest2" p4sw3 4 5 \
    pc_guest1 10.77.0.3 OK "pc_guest1 pc_guest2" ""
chequear "unknown_drop_cnt" "$(cnt $F MyIngress.unknown_drop_cnt 0)" -eq 0

prueba P4c "SERVIDORES (p4sw4): srv1 -> gateway rcla eth3" p4sw4 2 3 \
    srv1 203.0.113.33 OK "srv1" ""
chequear "unknown_drop_cnt" "$(cnt $F MyIngress.unknown_drop_cnt 0)" -eq 0

# ---------------------------------------------------------------------------
# P5) Entre subredes: ADMIN -> DESARROLLO (pasa por p4sw1, rcla y p4sw2)
# ---------------------------------------------------------------------------
prueba P5 "Entre subredes: pc_admin1 -> pc_dev1 (via rcla)" p4sw1 5 5 \
    pc_admin1 10.77.2.2 OK "pc_admin1 pc_dev1" "pc_admin1:p22_p5_admin1.pcap pc_dev1:p22_p5_dev1.pcap"
grep -q "ttl 63" "$OUT"/P5_*.txt && anotar ok "pc_dev1 recibe con TTL 63 (un salto L3 en rcla)" \
                                || anotar xxx "no se encontro TTL 63 en la captura de pc_dev1"

# ---------------------------------------------------------------------------
# P6) Unicast desconocido aislado: MAC destino inexistente (entrada ARP estatica)
# ---------------------------------------------------------------------------
ex pc_admin1 flush > /dev/null
ex pc_admin1 arpfija 10.77.2.140 02:00:00:01:00:99 > /dev/null
prueba P6 "Unicast desconocido: pc_admin1 -> MAC 02:00:00:01:00:99 (no instalada)" p4sw1 5 5 \
    pc_admin1 10.77.2.140 FALLA "" "pc_admin2:p22_p6_admin2.pcap"
ex pc_admin1 arpborrar 10.77.2.140 > /dev/null
chequear "unknown_drop_cnt (uno por echo request)" "$(cnt $F MyIngress.unknown_drop_cnt 0)" -eq 4
chequear "regla broadcast (sin ARP)" "$(cnt $F MyIngress.mac_fwd_cnt 4)" -eq 0
for p in 1 3 4 5; do
    chequear "tramas enviadas por el puerto $p" "$(cnt $F MyEgress.port_out_cnt $p)" -eq 0
done

# ---------------------------------------------------------------------------
# Reflexion 2.2 - host nuevo (pc_admin4, puerto 5) sin tocar el plano de control
# a) y b) por separado, con cache ARP vacia en ambos hosts
# ---------------------------------------------------------------------------
prueba R_a "Reflexion a) host registrado -> host nuevo: pc_admin1 -> pc_admin4" p4sw1 5 5 \
    pc_admin1 10.77.2.133 FALLA "pc_admin1 pc_admin4" "pc_admin1:p22_ra_admin1.pcap pc_admin4:p22_ra_admin4.pcap"
grep -q "Unreachable" "$OUT"/R_a_*.txt && anotar ok "ping informa Destination Host Unreachable (ARP sin respuesta)" \
                                       || anotar xxx "no aparece Destination Host Unreachable"
chequear "regla broadcast (ARP requests replicados)" "$(cnt $F MyIngress.mac_fwd_cnt 4)" -ge 1
chequear "tramas entregadas a pc_admin4 (port_out_cnt[5])" "$(cnt $F MyEgress.port_out_cnt 5)" -eq 0
chequear "unknown_drop_cnt (admin1 nunca llega a mandar unicast)" "$(cnt $F MyIngress.unknown_drop_cnt 0)" -eq 0

prueba R_b "Reflexion b) host nuevo -> host registrado: pc_admin4 -> pc_admin1" p4sw1 5 5 \
    pc_admin4 10.77.2.130 FALLA "pc_admin1 pc_admin4" "pc_admin1:p22_rb_admin1.pcap pc_admin4:p22_rb_admin4.pcap"
chequear "ARP requests de admin4 recibidos (port_in_cnt[5])" "$(cnt $F MyIngress.port_in_cnt 5)" -ge 1
chequear "copias del broadcast entregadas a admin1 (port_out_cnt[2])" "$(cnt $F MyEgress.port_out_cnt 2)" -ge 1
chequear "replies de admin1 descartados (unknown_drop_cnt)" "$(cnt $F MyIngress.unknown_drop_cnt 0)" -ge 1
chequear "tramas entregadas a pc_admin4 (port_out_cnt[5])" "$(cnt $F MyEgress.port_out_cnt 5)" -eq 0

# ---------------------------------------------------------------------------
# Reflexion - recuperacion solo desde el plano de control (sin recompilar)
# ---------------------------------------------------------------------------
{ echo; echo "== R_c: alta de pc_admin4 en p4sw1 (table_add + mc_node_update)"; } | tee -a "$RES"
ex p4sw1 alta_admin4 | grep -v RESULTADO | sed 's/^/  /' | tee -a "$RES"
{ echo "=================== p4sw1 despues de alta_admin4"; ex p4sw1 estado; } >> "$OUT/estado_switches.txt"

prueba R_c1 "Recuperacion: pc_admin1 -> pc_admin4" p4sw1 5 6 \
    pc_admin1 10.77.2.133 OK "pc_admin1 pc_admin4" "pc_admin4:p22_rc_admin4.pcap"
chequear "regla nueva de admin4 (mac_fwd_cnt[5])" "$(cnt $F MyIngress.mac_fwd_cnt 5)" -ge 4
chequear "unknown_drop_cnt" "$(cnt $F MyIngress.unknown_drop_cnt 0)" -eq 0

prueba R_c2 "Recuperacion: pc_admin4 -> pc_admin1" p4sw1 5 6 \
    pc_admin4 10.77.2.130 OK "pc_admin1 pc_admin4" ""
chequear "unknown_drop_cnt" "$(cnt $F MyIngress.unknown_drop_cnt 0)" -eq 0

ex p4sw1 baja_admin4 > /dev/null   # dejar p4sw1 como en commands.txt

{
    echo; echo "========================================"
    echo "Verificaciones que coinciden con lo esperado: $bien / $total"
} | tee -a "$RES"
echo "Detalle en $OUT/ y capturas en shared/p22_*.pcap"
