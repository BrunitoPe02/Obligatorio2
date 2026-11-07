Obligatorio 2 - Parte 3: Integracion
=====================================

Laboratorio que integra:
  - Backbone de RioNet con OSPF y el POP r7/r8 (Parte 1.5, costos de ingenieria de caminos)
  - Cliente A: rcla + 4 switches P4 con forwarding L2, politica de invitados y port security (Parte 2.4)
  - Cliente B: 3 PCs en LAN_B (NAT) + 2 servidores web publicos en DMZ_B
  - Cliente C: LAN publica en r8

Requisitos: la VM del curso (Kathara con las imagenes kathara/base, kathara/frr y kathara/p4).

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
  ./pruebas.sh            # matriz de pruebas + evidencia (OSPF, traceroute, NAT, contadores P4)
  ./pruebas.sh --pcap     # ademas guarda capturas shared/p3_*.pcap (NAT en rcla y politica en p4sw3)
Resultados en resultados/resumen.txt (esperado vs observado) y resultados/evidencia_*.txt.
El script usa el helper shared/t.sh, que corre dentro de cada equipo.

Plan de direccionamiento publico (203.0.113.0/24)
--------------------------------------------------
  203.0.113.0/27    Cliente A - IP de NAT 203.0.113.1 (lo de rcla)
  203.0.113.32/28   Cliente B - DMZ: rclb .33, srvB .34, srvb2 .35
  203.0.113.64/28   Cliente C - LAN_C: r8 .65, pcC .66
  203.0.113.96/27   Cliente A - servidores: rcla .97, srv1 .98
  (libres: .48/28, .80/28, .128/25)

Cambios respecto de las Partes 1.5 y 2.4
----------------------------------------
  - srv1 pasa de 203.0.113.34/27 a 203.0.113.98/27 (chocaba con la DMZ de B).
    Se actualizo: srv1.startup, rcla.startup, r3 frr.conf (ruta estatica),
    rint.startup (ruta de vuelta) y p4sw3/commands.txt (guest_acl 80/443).
  - rcla: eth0-eth3 iguales a la Parte 2; el enlace a r3 se agrega como eth4.
    NAT: -s 10.77.0.0/16 -o eth4 -> 203.0.113.1. Se elimina LAN_A/pca1.
  - Cliente B: se agregan pcb2 (10.77.0.11), pcb3 (10.77.0.12) y srvb2 (203.0.113.35).
  - Las paginas web de srv1, srvB y srvb2 muestran su nombre para identificar quien responde.

Detener
-------
  kathara lclean
