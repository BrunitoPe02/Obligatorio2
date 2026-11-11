#!/bin/bash
# Helper de pruebas de la Parte 2.2: corre DENTRO de cada equipo (via /shared/t.sh).
# Lo invoca pruebas_2.2.sh con "kathara exec <equipo> -- bash /shared/t.sh <modo> <args>".
#
# Modos en hosts:
#   ping IP                -> 4 pings; OK si vuelve al menos uno
#   flush                  -> vacia la cache ARP (ip neigh flush all)
#   neigh                  -> muestra la cache ARP
#   arpfija IP MAC         -> entrada ARP estatica (para forzar unicast a una MAC inexistente)
#   arpborrar IP           -> borra esa entrada
#   capstart ARCHIVO [in]  -> tcpdump en eth0 en segundo plano (max 120 s) -> /shared/ARCHIVO
#                             con "in" solo captura lo recibido (tcpdump -Q in)
#   capstop                -> detiene los tcpdump (SIGINT, el pcap queda bien cerrado)
#   resumenpcap ARCHIVO    -> imprime el pcap decodificado
# Modos en switches P4:
#   p4ready                -> OK si el switch BMv2 responde
#   reset                  -> pone en cero todos los contadores
#   cnts NPUERTOS NREGLAS  -> lee todos los contadores en una sola llamada
#   estado                 -> table_dump de mac_fwd + mc_dump
#   alta_admin4            -> registra pc_admin4 en p4sw1 (tabla + grupo multicast)
#   baja_admin4            -> deshace alta_admin4 (deja p4sw1 como en commands.txt)

CLI=simple_switch_CLI
modo="$1"; shift
rc=0

# Normaliza la salida de counter_read a "NOMBRE[i] pkts=N bytes=M".
# BMv2 imprime "BmCounterValue(packets=N, bytes=M)", "(M bytes, N pkts)" o
# "(M bytes, N packets)" segun la version (la imagen kathara/p4 usa la ultima).
norm_cnt() {
    grep -E "BmCounterValue|pkts|packets\)" | while read -r linea; do
        nombre=$(echo "$linea" | grep -oE "[A-Za-z_.]+\[[0-9]+\]" | head -1)
        p=$(echo "$linea" | grep -oE "packets=[0-9]+|[0-9]+ pkts|[0-9]+ packets" | grep -oE "[0-9]+")
        b=$(echo "$linea" | grep -oE "bytes=[0-9]+|[0-9]+ bytes" | grep -oE "[0-9]+")
        echo "$nombre pkts=$p bytes=$b"
    done
}

case "$modo" in
    # ---------------- hosts ----------------
    ping)      ping -c 4 -W 1 "$1" 2>&1; rc=$? ;;
    flush)     ip neigh flush all ;;
    neigh)     ip neigh show ;;
    arpfija)   ip neigh replace "$1" lladdr "$2" dev eth0 nud permanent; ip neigh show "$1" ;;
    arpborrar) ip neigh del "$1" dev eth0 2>/dev/null; true ;;
    capstart)  dir=""; [ "${2:-}" = "in" ] && dir="-Q in"
               rm -f "/shared/$1"
               setsid nohup timeout 120 tcpdump -i eth0 -n -e -U $dir -w "/shared/$1" \
                   > /dev/null 2>&1 < /dev/null &
               sleep 1 ;;
    capstop)   pkill -INT tcpdump; sleep 1; true ;;
    resumenpcap) tcpdump -r "/shared/$1" -n -e -v 2>/dev/null ;;

    # ---------------- switches P4 ----------------
    p4ready)   $CLI <<< "help" > /dev/null 2>&1; rc=$? ;;
    reset)     printf "counter_reset %s\n" MyIngress.port_in_cnt MyIngress.unknown_drop_cnt \
                   MyIngress.mac_fwd_cnt MyEgress.port_out_cnt | $CLI > /dev/null 2>&1 ;;
    cnts)      np="$1"; nr="$2"
               {
                   for ((i = 1; i <= np; i++)); do echo "counter_read MyIngress.port_in_cnt $i"; done
                   for ((i = 1; i <= np; i++)); do echo "counter_read MyEgress.port_out_cnt $i"; done
                   for ((i = 0; i < nr; i++)); do echo "counter_read MyIngress.mac_fwd_cnt $i"; done
                   echo "counter_read MyIngress.unknown_drop_cnt 0"
               } | $CLI 2>&1 | norm_cnt ;;
    estado)    printf "table_dump MyIngress.mac_fwd\nmc_dump\n" | $CLI 2>&1 ;;
    alta_admin4)
               printf "%s\n" \
                   "table_add MyIngress.mac_fwd MyIngress.forward 02:00:00:01:00:04 => 5" \
                   "mc_node_update 0 1 2 3 4 5" | $CLI 2>&1 | grep -iE "handle|error|success|update" ;;
    baja_admin4)
               hex=$(echo "table_dump MyIngress.mac_fwd" | $CLI 2>&1 \
                     | grep -B3 "020000010004" | grep -oE "entry 0x[0-9a-fA-F]+" | grep -oE "[0-9a-fA-F]+$")
               if [ -n "$hex" ]; then
                   echo "table_delete MyIngress.mac_fwd $((16#$hex))" | $CLI > /dev/null 2>&1
                   echo "entrada de pc_admin4 (handle $((16#$hex))) eliminada"
               fi
               echo "mc_node_update 0 1 2 3 4" | $CLI > /dev/null 2>&1 ;;

    *)         echo "modo desconocido: $modo"; rc=2 ;;
esac

if [ $rc -eq 0 ]; then echo "RESULTADO=OK"; else echo "RESULTADO=FALLA"; fi
