Obligatorio 2 - Parte 3: Integracion
=====================================

Laboratorio que integra:
  - Backbone de RioNet con OSPF y el POP r7/r8 (Parte 1.5, costos de ingenieria de caminos)
  - Cliente A: rcla + 4 switches P4 con forwarding L2, politica de invitados y port security (Parte 2.4)
  - Cliente B: 3 PCs en LAN_B (NAT) + 2 servidores web publicos en DMZ_B
  - Cliente C: router propio rclC (sin NAT) colgado de r8, LAN publica 203.0.113.64/28

Requisitos: la VM del curso (Kathara con las imagenes kathara/base, kathara/frr y kathara/p4).
Desde Windows (Docker Desktop + Git Bash) correr las pruebas con:
  MSYS_NO_PATHCONV=1 ./pruebas.sh
(evita que Git Bash convierta /shared/t.sh en una ruta de Windows).

Ejecucion desde cero
--------------------
  cd parte3
  kathara lclean        # por si quedo algo levantado
  kathara lstart

Los switches P4 compilan shared/switch.p4 y cargan su commands.txt al arrancar.
Esperar ~30-60 s a que OSPF converja antes de probar:
  kathara exec r1 -- vtysh -c "show ip ospf neighbor"
  kathara exec r1 -- vtysh -c "show ip route"

Pruebas automatizadas
---------------------
Con el lab levantado, desde parte3/:
  ./pruebas.sh            # matriz de 38 pruebas + evidencia (OSPF, traceroute, NAT, contadores P4)
  ./pruebas.sh --pcap     # ademas guarda capturas shared/p3_*.pcap (NAT en rcla y politica en p4sw3),
                          # que se cortan al terminar la matriz
Resultados en resultados/resumen.txt (esperado vs observado) y resultados/evidencia_*.txt.
Cada prueba da OK, FALLA o ERROR (no se pudo ejecutar); un ERROR nunca cuenta como acierto.
El resumen incluye los contadores P4 de la politica de invitados y de port security.
El script usa el helper shared/t.sh, que corre dentro de cada equipo.

Plan de direccionamiento publico (203.0.113.0/24)
--------------------------------------------------
  203.0.113.0/27    Cliente A - IP de NAT 203.0.113.1 (lo de rcla)
  203.0.113.32/28   Cliente B - DMZ: rclb .33, srvB .34, srvb2 .35
  203.0.113.64/28   Cliente C - LAN_C: rclC .65, pcC .66 (enlace r8-rclC 192.168.77.8/30)
  203.0.113.96/27   Cliente A - servidores: rcla .97, srv1 .98
  (libres: .48/28, .80/28, .128/25)

Cambios respecto de las Partes 1.5 y 2.4
----------------------------------------
  - srv1 usa 203.0.113.98/27, igual que en la Parte 2 (antes estaba en .34, que chocaba
    con la DMZ de B). Para integrarlo al backbone: ruta estatica en r3 (redistribuida
    por OSPF) y ruta de vuelta en rint.
  - Cliente C: igual que en las Partes 1.4/1.5, detras de su router rclC (sin NAT).
  - rcla: eth0-eth3 iguales a la Parte 2; el enlace a r3 se agrega como eth4.
    NAT: -s 10.77.0.0/16 -o eth4 -> 203.0.113.1. Se elimina LAN_A/pca1.
  - Cliente B: se agregan pcb2 (10.77.0.11), pcb3 (10.77.0.12) y srvb2 (203.0.113.35).
  - Las paginas web de srv1, srvB y srvb2 muestran su nombre para identificar quien responde.

Detener
-------
  kathara lclean
