#!/bin/bash
# Helper de pruebas: corre DENTRO de cada equipo (via /shared/t.sh).
# Lo invoca pruebas.sh con "kathara exec <equipo> -- bash /shared/t.sh <modo> <args>".
# Los argumentos son siempre palabras simples, para no pelear con comillas en kathara exec.
#
# Modos:
#   ping IP              -> 3 pings; OK si vuelve al menos uno
#   http IP | https IP   -> curl a la raiz (https acepta el certificado autofirmado)
#   route PREFIJO        -> OK si la ruta esta instalada en el kernel
#   p4ready              -> OK si el switch BMv2 responde
#   p4cnt CONTADOR IDX   -> lee un contador de MyIngress
#   ospfnei | ospfroute  -> vtysh: vecinos OSPF / tabla de ruteo
#   trace IP             -> traceroute numerico
#   nat                  -> reglas y contadores de la tabla nat
#   capstart IF ARCHIVO  -> tcpdump en segundo plano 150 s, guarda en /shared/ARCHIVO

modo="$1"; shift
rc=0
case "$modo" in
    ping)      ping -c 3 -W 1 "$1" 2>&1; rc=$? ;;
    http)      curl -s --max-time 4 "http://$1/" 2>&1; rc=$? ;;
    https)     curl -sk --max-time 4 "https://$1/" 2>&1; rc=$? ;;
    route)     out=$(ip route show "$1"); echo "$out"; [ -n "$out" ]; rc=$? ;;
    p4ready)   simple_switch_CLI <<< "help" > /dev/null 2>&1; rc=$? ;;
    p4cnt)     # BMv2 imprime "BmCounterValue(packets=N, ...)" o "(B bytes, N pkts)" segun la version
               out=$(echo "counter_read MyIngress.$1 $2" | simple_switch_CLI 2>&1)
               echo "$out" | grep -i "$1"
               n=$(echo "$out" | grep -oE "packets=[0-9]+|[0-9]+ pkts" | grep -oE "[0-9]+" | head -1)
               echo "PAQUETES=$n"; [ -n "$n" ]; rc=$? ;;
    ospfnei)   vtysh -c "show ip ospf neighbor" ;;
    ospfroute) vtysh -c "show ip route" ;;
    trace)     traceroute -n -w 1 -q 1 "$1" 2>&1 ;;
    nat)       iptables -t nat -L POSTROUTING -n -v ;;
    capstart)  setsid nohup timeout 150 tcpdump -i "$1" -w "/shared/$2" > /dev/null 2>&1 < /dev/null &
               sleep 1 ;;
    *)         echo "modo desconocido: $modo"; rc=2 ;;
esac

if [ $rc -eq 0 ]; then echo "RESULTADO=OK"; else echo "RESULTADO=FALLA"; fi
