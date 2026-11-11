# Revisión del Obligatorio 2: hallazgos

Revisión de solo lectura del repo contra la letra (`Obligatorio2_2026.pdf`), hecha el 11/11/2026. No se editó ningún archivo ni se levantó ningún lab.
La entrega vence el viernes 13/11/2026 a las 23:59.

> **Para Claude Code:** este archivo es una lista de pendientes, no instrucciones para ejecutar sin preguntar.
> - Antes de cambiar algo, verificá el hallazgo en el código o en la evidencia. Algunos salieron de revisiones automáticas y no se verificaron a mano; están marcados con *(sin verificar)*.
> - No levantes labs ni edites archivos sin que lo pida quien te está usando.
> - La letra permite un uso **moderado** de IA y exige declararlo. No redactes informes completos: ayudá a revisar, explicar y señalar.
> - Este archivo no va en el `.tar.gz` de entrega.

Leyenda:
- **ERROR**: algo está mal.
- **FALTA**: algo que pide la letra no está.
- **MENOR**: prolijidad.

---

## 1. Bloquea la entrega

- [ ] **FALTA:** no hay `Obligatorio2Grupo77.pdf`. Solo hay cuatro informes sueltos: `parte1.5/informe_1.5.md`, `parte2.2/informe_2.2.md`, `parte2.3/informe_2.3.md` y `parte3/informe_3.md`.
- [ ] **FALTA:** no hay informes de **1.1, 1.2, 1.3, 1.4, 2.1 ni 2.4**. Ver la sección 3.
- [ ] **FALTA:** no hay ninguna figura (png, svg ni drawio). La letra pide topologías anotadas en 1.1, 1.4 y 2.1.
- [ ] **FALTA:** no está la declaración de uso de IA.
- [ ] **FALTA:** no hay `README.txt` en la raíz. Tiene que explicar cómo levantar cada escenario (1.1 a 3) desde cero y qué pcap o script corresponde a cada experimento. Hoy el único README es `parte3/README.txt`.
- [ ] **FALTA:** no está el `obligatorio2Grupo77.tar.gz`.

## 2. Errores técnicos (por prioridad)

### 2.1 Los servidores de A se superponen con la DMZ de B en las partes 2.1 a 2.4 (ERROR)
- En la Parte 2, los servidores de A usan `203.0.113.32/27`, con rcla en .33 y srv1 en .34.
- La DMZ de B de la Parte 1 es `203.0.113.32/28`, con rclb en .33 y srvb en .34.
- Las redes se superponen y las IPs coinciden, así que se rompe la "consistencia con Parte 1".
- **Parte 3 ya lo corrigió** con `203.0.113.96/27` y srv1 en .98 (verificado). También está justificado en `parte3/informe_3.md:9`.
- Hay que elegir una de dos opciones:
  - **(a)** Corregirlo en 2.1 a 2.4 y regenerar los resultados de 2.2 y 2.3. Los lugares a cambiar son:
    - `parte2.1`: `rcla.startup:4`, `srv1.startup:11-12`
    - `parte2.2`: `rcla.startup:10`, `srv1.startup:12-13`, `pruebas_2.2.sh:146`, `resultados/P4c_*`
    - `parte2.3`: `rcla.startup:10`, `srv1.startup:12-13`, `p4sw3/commands.txt:15-16`, `pruebas_2.3.sh:29`, `resultados/*`
    - `parte2.4`: `rcla.startup:10`, `srv1.startup:12-13`, `p4sw3/commands.txt:15-16`
  - **(b)** Documentar en los informes de la Parte 2 que el problema se detectó y se corrigió en la Parte 3.

### 2.2 Parte 1.2: `redistribute static` mete 8.8.8.0/24 en OSPF (ERROR) *(sin verificar)*
- Está en `parte1.2/r1/etc/frr/frr.conf:31` y en `r6/etc/frr/frr.conf:28`.
- La letra dice que OSPF anuncia solo las redes internas del ISP y los prefijos públicos de los clientes.
- Hay que usar `default-information originate` o justificar la decisión en el informe.

### 2.3 Parte 1.3: los instantes de falla no coinciden en las corridas 1 y 2 (ERROR) *(sin verificar)*
- **Corrida 1:** `falla_run1.txt` marca 1793213684.65. Sin embargo, los LSU de los pcaps y el único ping perdido (seq 656) están cerca de …630.62, unos 54 s antes.
- **Corrida 2:** no se pierde ningún ping cerca del instante registrado (…963.36).
- **Corridas 3 a 6:** sí cierran, con un solo paquete perdido y una caída de unos 18 a 20 ms.
- **Acción:** repetir las corridas 1 y 2, o descartarlas explicando por qué. La letra pide al menos 5 corridas.
- Los pcaps se llaman `falla_r4_r5`/`falla_r2_r5` por el enlace donde se capturó, no por el que falló, que fue r2–r4 (verificado en `rutas_despues_r2`). Hay que aclararlo en el informe. Además, ambos pcaps cubren solo la corrida 1.

### 2.4 Parte 1.4: las evidencias son de corridas distintas (ERROR) *(sin verificar)*
- `alta_run1.txt` es del 28/10, mientras que `r1_monitor_run1.txt` y los pcaps son del 29/10.
- Hay una sola corrida y no hay un timestamp explícito del momento del alta.
- Los ~5,0 s solo se pueden sacar cruzando el DBD de r5–r7 en el pcap (15:14:23.256, en hora local UTC-3) con el monitor de r1 (18:14:28.275, en UTC).
- **Acción:** hacer una corrida limpia que registre el instante del alta.

### 2.5 Parte 3: los resultados commiteados no salieron del script actual (ERROR)
- `parte3/resultados/resumen.txt:40-42` muestra los contadores P4 como `? -> ?`.
- Faltan las líneas de port security (`pruebas.sh:129-130`) y no existe `evidencia_p4.txt`, aunque `leer_cnt` siempre lo escribe.
- Por eso `informe_3.md:29`, que dice que port security bloquea a pc_admin4, no tiene respaldo.
- No hay ningún pcap `p3_*`, aunque `README.txt:27` los menciona.
- **Acción:** correr `./pruebas.sh --pcap` en parte3 y commitear la salida.

### 2.6 Parte 2.4: la evidencia de spoofing es débil (FALTA)
- En `p24_sw3_eth1_guest1.pcap`, guest1 envía con la MAC `02:00:00:03:00:02` entre 19:55:56 y 19:56:01.
- `p24_sw3_eth0_rcla.pcap` empieza recién a las 19:56:29, así que no prueba que esas tramas se descartaron.
- No hay carpeta `resultados/`, ni contadores `portsec_viol_cnt`, ni script de pruebas.
- **Acción:** capturar las dos interfaces al mismo tiempo, leer los contadores antes y después, y agregar un caso legítimo como control.

## 3. Contenido que falta en los informes

| Parte | Qué falta |
|---|---|
| 1.1 | Tabla de numeración, explicación de rutas estáticas y NAT, figura |
| 1.2 | LSDB, FIB y `show ip ospf neighbor` de ≥2 routers con comparación; análisis de caminos A↔B y A↔Internet; justificación de costos (todos valen 10) |
| 1.3 | Tabla con mín/máx/promedio, explicación de la variabilidad, secuencia de mensajes OSPF, respuesta a la pregunta 1.3 |
| 1.4 | Qué se configuró a mano y qué se aprendió por OSPF (la estática de `rint.startup:13` es la parte manual); por qué r1 aprende primero solo por r7, ya que r6–r8 se forma después; figura actualizada |
| 2.1 | Tabla de numeración (VLSM), figura, dominios de broadcast y colisión, por qué los pcaps de ARP están vacíos o sin respuesta (el switch todavía es el esqueleto) |
| 2.2 | Mostrar `commands.txt` y enlazar cada afirmación con su pcap o resultado |
| 2.4 | Regla exacta, cómo se verificó, relación con los conceptos de capa 2, que se mantiene la ACL de 2.3 |

## 4. Menores

**Parte 3**
- `pruebas.sh:112`: todo lo que no tenga `RESULTADO=OK` cuenta como FALLA. Si `kathara exec` falla, los casos negativos (03, 06, 12 y 17 a 20) "pasan" igual. Habría que exigir que la salida contenga `RESULTADO=`.
- Casos que faltan en la matriz: pcc→8.8.8.8, srvb y srvb2→Internet, pcb2↔pcb3 (el informe dice que "los tres PCs se alcanzan entre sí"), dev→srv1, guest2 y guest3.
- Afirmaciones de `informe_3.md` sin evidencia:
  - Línea 25: "los contadores de NAT aumentan". Hay una sola foto, tomada después de las pruebas.
  - Línea 27: "cada servidor ve la IP de NAT como origen". No hay logs ni capturas.
  - Línea 31: "la solicitud llega a destino".
- `informe_3.md:7` dice que rcla y rclb anuncian por OSPF, pero no corren OSPF. Los que redistribuyen las estáticas son r3 y r5.
- `r1.startup` arranca frr en un orden distinto al de los demás routers. Funciona, pero es inconsistente.

**Parte 2**
- 2.3: la ACL no valida la IP origen, así que un invitado puede falsificarla. El informe solo menciona la MAC destino (`informe_2.3.md:106`).
- 2.3: `p23_sw3_eth{0,1}_*` tiene el mismo tamaño que `p23_r1_*`. No está claro para qué sirve `p23_guest1_stateless.pcap`.
- 2.1: `switch.p4` está copiado 4 veces (en `p4swN/`), mientras que las otras partes usan `shared/`.

**Parte 1**
- 1.1, `rint.startup:10`: el comentario dice "se entregan a r1", pero la línea 12 manda a r6.
- 1.1, `r3.startup:14` y `r5.startup:14`: rutas estáticas a redes ya conectadas que dan "File exists" al arrancar.
- 1.1: es un lab solo con rutas estáticas, pero tiene `ospfd=yes` y arranca frr con un `frr.conf` placeholder.
- 1.2: en `shared/` están las pruebas p2 a p6 y `nat_*.pcap`, copiados sin cambios de 1.1.
- 1.2: `ospf_arranque_r1_r2.pcap` dura unas 15 h y tiene más de 2000 Hellos. Conviene recortarlo.
- 1.3: `ping_run1.txt` pesa 1,7 MB y `ping_run6.txt` 684 KB.
- 1.5: la captura del §5 tiene un solo punto (r1, cualquier interfaz).

**Repo y entrega**
- Hay 58 `.DS_Store` versionados y no hay `.gitignore`.
- `parte1/` está vacía: solo tiene un `shared/` vacío.
- Todos los `lab.conf` tienen `LAB_NAME="redes-ob2-parte1"`.
- Hay pcaps de 24 B (solo cabecera), por ejemplo `parte2.1/shared/arp_admin2.pcap` y `parte2.2/shared/p22_p6_admin2.pcap`. El informe tiene que decir que están vacíos a propósito.

## 5. Qué está bien (no tocar)

- **1.1:** no hay direcciones superpuestas. Los enlaces del ISP son /30. Las rutas estáticas de r1 a r6 están completas. Los dos SNAT están bien y aparecen en `nat_lan.pcap` y `nat_isp.pcap`.
- **1.2:** ninguna LAN privada de clientes se filtra a OSPF. El pcap de arranque tiene DBD, LSR, LSU y LSAck.
- **1.3:** la falla fue efectivamente en r2–r4. Hay 6 corridas y tablas antes y después para r1, r2 y r4.
- **1.4:** hay 3 enlaces nuevos (r5–r7, r7–r8 y r6–r8), no se renumeró nada y la LAN 203.0.113.64/28 está como pasiva en r8.
- **1.5:** está completa. Los costos de los configs coinciden con el informe, y las rutas y traceroutes coinciden con el objetivo (métrica 30 y 60, en ambos sentidos).
- **2.1:** el VLSM es correcto: INV 10.77.0.0/23, DEV 10.77.2.0/25 y ADMIN 10.77.2.128/26.
- **2.2:** el P4 es correcto y pasan 46/46 pruebas.
- **2.3:** pasan 50/50 pruebas. El caso de reenviar después de descartar está evitado y el análisis stateless es correcto.
- **2.4:** la lógica de port_security es correcta: la clave es (ingress_port, srcAddr) y se aplica antes de la ACL.
- **3:** no hay solapamiento público. OSPF solo anuncia lo permitido y hay 24 adyacencias Full. El NAT de rcla y rclb está bien. La ACL apunta a .98. El resumen marca 31/31.

## 6. Preguntas al profesor

**Respondidas**

| Pregunta | Respuesta del profesor | Acción |
|---|---|---|
| ADMIN no puede hacer ping a un invitado: la ACL stateless descarta el echo-reply (§2.3, pág. 9-10) | "Está bien, documentarlo" | No cambiar la ACL. En el informe de 2.3 (punto 3, limitación stateless), explicar que el echo-reply entra por un puerto de invitado con destino 10.77.2.x, no coincide con ninguna regla y cae en `acl_deny`. Mencionarlo en el informe de la Parte 3 como comportamiento esperado. |
| Invitados sin Internet ni DNS. ¿"Comunicarse con el gateway" es solo como destino? (§2.3 pág. 9; problema pág. 4; Parte 3 pág. 11) | "Correcto" (vale la lectura literal) | La ACL actual está bien. Aclararlo en el informe de la Parte 3. Opcional: agregar el caso negativo invitado→8.8.8.8 = FALLA. |
| Loopbacks /32 en r1 y r6 para el tráfico "entre r1 y r6" (§1.5, pág. 7) | "Es una buena práctica, documentarlo" | Justificar en `informe_1.5.md`: la /32 no depende de una interfaz física y sigue siendo alcanzable si cae un enlace. |

**Sin consultar todavía**
- ¿Qué IP de rcla cuenta como "gateway"?
- ¿Hay que emular el servidor web extra de la Parte 3?

## 7. Orden sugerido

1. Decidir qué hacer con la superposición de 2.1 a 2.4: opción (a) u opción (b).
2. Volver a correr la Parte 3 con `--pcap` y commitear la salida.
3. Repetir las corridas 1 y 2 de la 1.3 y hacer una corrida limpia de la 1.4.
4. Sacar la evidencia de 1.2: LSDB, FIB y vecinos de al menos 2 routers.
5. Escribir los informes que faltan y hacer las figuras.
6. Escribir el README de la raíz y la declaración de IA.
7. Armar el PDF y el tar, sin `.DS_Store` y sin este archivo.
