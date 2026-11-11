#!/bin/bash
# Helper de pruebas de la Parte 2.3: corre DENTRO de cada equipo (via /shared/t.sh).
# Lo invoca pruebas_2.3.sh con "kathara exec <equipo> -- bash /shared/t.sh <modo> <args>".
#
# Modos en hosts:
#   ping IP [N]              -> N pings (3 por defecto); OK si vuelve al menos uno
#   flush                    -> vacia la cache ARP
#   curl URL                 -> GET con curl (https sin validar certificado); OK si responde HTTP
#   tcp IP PUERTO            -> intenta abrir una conexion TCP (3 s); OK si se establece
#   listen PUERTO            -> deja un proceso escuchando en ese puerto TCP (30 s)
#   hping_syn80 IP PUERTO    -> (srv1) 2 SYN con puerto origen 80 hacia IP:PUERTO  [situacion B]
#   hping_ack IP PUERTO      -> (guest) 2 ACK sueltos hacia IP:PUERTO              [situacion C]
# Modos en hosts y switches:
#   capstart ARCHIVO [IF]    -> tcpdump en IF (eth0 por defecto) en segundo plano -> /shared/ARCHIVO
#   capstop                  -> detiene los tcpdump (el pcap queda bien cerrado)
#   resumenpcap ARCHIVO      -> imprime el pcap decodificado
#   pcapcount ARCHIVO TIPO   -> cantidad de paquetes del pcap de ese tipo:
#                               syn | echo | echoreply | synack_guest1
# Modos en switches P4:
#   p4ready                  -> OK si el switch BMv2 responde
#   reset                    -> pone en cero todos los contadores
#   cnts NPUERTOS NMAC NACL  -> lee todos los contadores (NACL = reglas de guest_acl, 0 si no tiene)
#   estado                   -> table_dump de port_role, guest_acl y mac_fwd

CLI=simple_switch_CLI
modo="$1"; shift
rc=0

# Normaliza la salida de counter_read a "NOMBRE[i] pkts=N bytes=M" (igual que en la 2.2).
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
    ping)      ping -c "${2:-3}" -W 1 "$1" 2>&1; rc=$? ;;
    flush)     ip neigh flush all ;;
    curl)      out=$(curl -k -s -o /dev/null -w "%{http_code}" --connect-timeout 3 -m 6 "$1" 2>&1)
               echo "curl $1 -> HTTP $out"
               [ "$out" != "000" ] && [ -n "$out" ] || rc=1 ;;
    tcp)       if timeout 3 bash -c "exec 3<>/dev/tcp/$1/$2" 2>/dev/null; then
                   echo "conexion TCP a $1:$2 establecida"
               else echo "conexion TCP a $1:$2 sin respuesta"; rc=1; fi ;;
    listen)    pkill -f "nc -l" 2>/dev/null
               setsid nohup timeout 30 bash -c "nc -l -p $1 || nc -l $1" > /dev/null 2>&1 < /dev/null &
               sleep 1; echo "escuchando en TCP $1" ;;
    hping_syn80) hping3 -S -s 80 -k -p "$2" -c 2 "$1" 2>&1 ;;
    hping_ack)   hping3 -A -s 31337 -k -p "$2" -c 2 "$1" 2>&1 ;;

    # ---------------- capturas ----------------
    capstart)  rm -f "/shared/$1"
               setsid nohup timeout 120 tcpdump -i "${2:-eth0}" -n -e -U -w "/shared/$1" \
                   > /dev/null 2>&1 < /dev/null &
               sleep 1 ;;
    capstop)   pkill -INT tcpdump; sleep 1; true ;;
    resumenpcap) tcpdump -r "/shared/$1" -n -e -v 2>/dev/null ;;
    pcapcount) case "$2" in   # filtros con nombre: evita pasar espacios por kathara exec
                   syn)           f='tcp[tcpflags] == tcp-syn' ;;
                   echo)          f='icmp[icmptype] == icmp-echo' ;;
                   echoreply)     f='icmp[icmptype] == icmp-echoreply' ;;
                   synack_guest1) f='src host 10.77.0.2 and tcp[tcpflags] & (tcp-syn|tcp-ack) == (tcp-syn|tcp-ack)' ;;
                   *)             f="$2" ;;
               esac
               tcpdump -r "/shared/$1" -n "$f" 2>/dev/null | wc -l ;;

    # ---------------- switches P4 ----------------
    p4ready)   $CLI <<< "help" > /dev/null 2>&1; rc=$? ;;
    reset)     printf "counter_reset %s\n" MyIngress.port_in_cnt MyIngress.unknown_drop_cnt \
                   MyIngress.mac_fwd_cnt MyEgress.port_out_cnt \
                   MyIngress.guest_policy_cnt MyIngress.guest_acl_cnt | $CLI > /dev/null 2>&1 ;;
    cnts)      np="$1"; nm="$2"; na="$3"
               {
                   for ((i = 1; i <= np; i++)); do echo "counter_read MyIngress.port_in_cnt $i"; done
                   for ((i = 1; i <= np; i++)); do echo "counter_read MyEgress.port_out_cnt $i"; done
                   for ((i = 0; i < nm; i++)); do echo "counter_read MyIngress.mac_fwd_cnt $i"; done
                   echo "counter_read MyIngress.unknown_drop_cnt 0"
                   echo "counter_read MyIngress.guest_policy_cnt 0"
                   echo "counter_read MyIngress.guest_policy_cnt 1"
                   for ((i = 0; i < na; i++)); do echo "counter_read MyIngress.guest_acl_cnt $i"; done
               } | $CLI 2>&1 | norm_cnt ;;
    estado)    printf "table_dump MyIngress.port_role\ntable_dump MyIngress.guest_acl\ntable_dump MyIngress.mac_fwd\n" \
                   | $CLI 2>&1 ;;

    *)         echo "modo desconocido: $modo"; rc=2 ;;
esac

if [ $rc -eq 0 ]; then echo "RESULTADO=OK"; else echo "RESULTADO=FALLA"; fi
