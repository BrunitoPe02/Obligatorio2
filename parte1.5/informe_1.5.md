# Parte 1.5 – Ingeniería de caminos

Todos los archivos citados están en `parte1.5/shared/`. El lab `parte1.5` parte de la topología de la Parte 1.4 (incluye r7, r8 y LAN_C); solo se cambiaron los costos OSPF y se agregaron dos loopbacks.

## 1. Objetivo declarado

Para el tráfico entre r1 y r6, en ausencia de fallas:

- **Camino principal:** r1 → r2 → r4 → r6
- **Camino de respaldo:** r1 → r3 → r5 → r6

Los dos caminos son **disjuntos** (no comparten ningún enlace ni router intermedio), de modo que una falla en cualquier enlace del principal no afecta al respaldo. Además se busca que el ruteo sea **simétrico**: el tráfico de r6 hacia r1 debe usar los mismos caminos en sentido inverso.

## 2. Configuración

### 2.1 Criterio de costos

En OSPF el costo de un camino es la suma de los costos de las **interfaces de salida** de cada router que atraviesa. Por ejemplo, de r1 a r6 por el principal se suman r1 eth1 + r2 eth2 + r4 eth2; de r6 a r1 se suman las otras puntas de los mismos enlaces (r6 eth1 + r4 eth0 + r2 eth0). Por eso cada enlace se configuró con **el mismo costo en ambas puntas**: si no, ida y vuelta podrían tomar caminos distintos.

Se usaron tres niveles de costo:

| Rol | Enlaces | Costo (ambas puntas) | Costo total r1 ↔ r6 |
|---|---|---|---|
| Principal | r1–r2, r2–r4, r4–r6 | 10 | 30 |
| Respaldo | r1–r3, r3–r5, r5–r6 | 20 | 60 |
| Resto | r2–r3, r2–r5, r4–r5, r5–r7, r7–r8, r6–r8 | 100 | – |

- El principal (30) es estrictamente menor que el respaldo (60): no hay empate y por lo tanto no hay ECMP.
- Los enlaces "transversales" y los de r7/r8 en 100 hacen que, falle donde falle el principal, el desvío vaya por el respaldo completo y no por un camino mixto.

### 2.2 Verificación del diseño ante cada falla posible del principal

| Enlace caído | Mejor alternativa fuera del respaldo | Costo | Respaldo | Gana |
|---|---|---|---|---|
| r1–r2 | r1 → r3 → r2 → r4 → r6 | 20+100+10+10 = 140 | 60 | Respaldo |
| r2–r4 | r1 → r2 → r5 → r6 | 10+100+20 = 130 | 60 | Respaldo |
| r4–r6 | r1 → r2 → r5 → r6 | 10+100+20 = 130 | 60 | Respaldo |

También se descartó el camino por r7 y r8 (r1 → r3 → r5 → r7 → r8 → r6 = 20+20+100+100+100 = 340).

### 2.3 Costos por interfaz

| Router | eth0 | eth1 | eth2 | eth3 | eth5 |
|---|---|---|---|---|---|
| r1 | (rint, sin OSPF) | 10 → r2 | 20 → r3 | | |
| r2 | 10 → r1 | 100 → r3 | 10 → r4 | 100 → r5 | |
| r3 | 20 → r1 | 100 → r2 | 20 → r5 | (rclA, sin OSPF) | |
| r4 | 10 → r2 | 100 → r5 | 10 → r6 | | |
| r5 | 100 → r2 | 20 → r3 | 100 → r4 | 20 → r6 | 100 → r7 |
| r6 | (rint, sin OSPF) | 10 → r4 | 20 → r5 | 100 → r8 | |
| r7 | 100 → r5 | 100 → r8 | | | |
| r8 | 100 → r6 | 100 → r7 | (LAN_C, sin OSPF) | | |

Se configura en cada `rX/etc/frr/frr.conf` con `ip ospf cost N` dentro de la interfaz. Ejemplo (r2):

```
interface eth0
 ip ospf cost 10
interface eth1
 ip ospf cost 100
interface eth2
 ip ospf cost 10
interface eth3
 ip ospf cost 100
```

`costos.txt` contiene la salida de `show ip ospf interface` de los 8 routers y confirma que los costos aplicados coinciden con la tabla.

### 2.4 Loopbacks como extremos de la prueba

Para medir "el tráfico entre r1 y r6" no sirve usar una IP de enlace como destino. Por ejemplo, 172.16.77.38 pertenece a la red r4–r6 y 172.16.77.49 a la red r6–r8: OSPF rutea hacia el **prefijo** del enlace, que está conectado a dos routers, y puede entrar a él por el otro extremo (r4 u r8) sin pasar por r6. Con la falla aplicada, el camino a 172.16.77.48/30 por r8 llegaría a ser más barato que el respaldo, y el traceroute no mostraría ninguno de los dos caminos declarados.

Por eso se agregó en r1 y en r6 una loopback /32, anunciada en OSPF:

| Router | Loopback |
|---|---|
| r1 | 10.255.255.1/32 |
| r6 | 10.255.255.6/32 |

```
interface lo
 ip address 10.255.255.6/32
!
router ospf
 network 10.255.255.6/32 area 0.0.0.0
```

Una /32 en `lo` existe solo dentro de ese router y no depende de ningún enlace, así que todo camino hacia ella termina en r6 y sigue siendo alcanzable aunque caiga una interfaz. Los traceroutes se hacen con la loopback como origen (`-s`) para que también las respuestas vayan a la loopback del otro extremo y no a una red de enlace. El costo OSPF de la loopback es 0 (`Network Type LOOPBACK, Cost: 0`), por lo que no altera las sumas.

## 3. Procedimiento

1. `kathara lstart` del lab `parte1.5` y espera de la convergencia (vecinos en `Full`).
2. Costos aplicados: `show ip ospf interface` en los 8 routers → `costos.txt`.
3. **Antes de la falla:** `show ip route` hacia la loopback remota en r1 y r6, y `traceroute -n -s <loopback local> <loopback remota>` en ambos sentidos → `antes_falla.txt`.
4. Inicio de la captura en r1: `tcpdump -i any -U -w /shared/falla_r2_r4.pcap ip proto 89` (solo OSPF; se captura en todas las interfaces de r1 para ver los LSAs que llegan por r2 y por r3).
5. **Falla** en el principal, enlace r2–r4: en r2, `ip link set eth2 down`.
6. **Después de la falla:** mismos comandos que en el paso 3 → `despues_falla.txt`.
7. **Restauración:** en r2, `ip link set eth2 up`; tras la reconvergencia, mismos comandos → `restauracion.txt`.
8. Fin de la captura.

## 4. Resultados

### 4.1 Resumen

| Momento | Ruta en r1 a 10.255.255.6 | Ruta en r6 a 10.255.255.1 | Traceroute r1 → r6 | Traceroute r6 → r1 |
|---|---|---|---|---|
| Antes de la falla | métrica **30**, vía 172.16.77.10 (r2) eth1 | métrica **30**, vía 172.16.77.37 (r4) eth1 | .10 (r2) → .22 (r4) → r6 | .37 (r4) → .21 (r2) → r1 |
| r2–r4 caído | métrica **60**, vía 172.16.77.14 (r3) eth2 | métrica **60**, vía 172.16.77.41 (r5) eth2 | .14 (r3) → .30 (r5) → r6 | .41 (r5) → .29 (r3) → r1 |
| Restaurado | métrica **30**, vía 172.16.77.10 (r2) eth1 | métrica **30**, vía 172.16.77.37 (r4) eth1 | .10 (r2) → .22 (r4) → r6 | .37 (r4) → .21 (r2) → r1 |

En los tres momentos las rutas tienen **un único siguiente salto** (no hay ECMP), las métricas son exactamente las calculadas en el diseño (30 y 60) y el camino de vuelta es el inverso del de ida.

### 4.2 Antes de la falla (`antes_falla.txt`)

```
Routing entry for 10.255.255.6/32
  Known via "ospf", distance 110, metric 30, best
  * 172.16.77.10, via eth1, weight 1

traceroute to 10.255.255.6 (10.255.255.6), 30 hops max, 60 byte packets
 1  172.16.77.10  1.005 ms  1.121 ms  1.244 ms
 2  172.16.77.22  1.783 ms  3.912 ms  4.024 ms
 3  10.255.255.6  4.427 ms  4.661 ms  4.925 ms
```

### 4.3 Después de la falla (`despues_falla.txt`)

```
Routing entry for 10.255.255.6/32
  Known via "ospf", distance 110, metric 60, best
  * 172.16.77.14, via eth2, weight 1

traceroute to 10.255.255.6 (10.255.255.6), 30 hops max, 60 byte packets
 1  172.16.77.14  2.663 ms  2.571 ms  2.555 ms
 2  172.16.77.30  3.091 ms  3.103 ms  3.581 ms
 3  10.255.255.6  4.082 ms  4.418 ms  4.838 ms
```

El tráfico pasa por el respaldo completo (r3 y r5), y no por ninguno de los caminos mixtos de la sección 2.2.

### 4.4 Después de restaurar (`restauracion.txt`)

Al volver a levantar el enlace, la ruta vuelve sola al principal (métrica 30, vía r2) sin ninguna intervención adicional: OSPF siempre elige el camino de menor costo disponible, así que el principal se recupera apenas el enlace vuelve a estar en la topología.

## 5. Secuencia de mensajes OSPF (`falla_r2_r4.pcap`)

Captura en r1 (interfaces eth1 hacia r2 y eth2 hacia r3). 172.16.77.10 es r2, 172.16.77.14 es r3, y 172.16.77.9 / .13 son r1. Se omiten los Hellos periódicos (cada 10 s).

**Falla**

| Hora | Origen → Destino | Mensaje | Contenido / significado |
|---|---|---|---|
| **18:26:28.808** | r2 (.10) → 224.0.0.5 | **LS-Update**, 5 LSAs | Router-LSA de 2.2.2.2 (seq 0x8000000f, 10 y 11) que lista solo los enlaces hacia r1 (costo 10), r3 (100) y r5 (100): **ya no incluye el enlace a r4**. Además, un Network-LSA 172.16.77.21 con age 3600 (MaxAge), que retira (*flush*) el LSA de red del segmento r2–r4. |
| 18:26:28.809 | r1 (.13) → 224.0.0.5 | LS-Update | r1 reinunda el Router-LSA nuevo de r2 hacia r3. |
| 18:26:28.809 | r3 (.14) → 224.0.0.5 | LS-Update | r3 inunda el mismo LSA hacia r1: las dos copias se cruzan (inundación confiable por todos los caminos). |
| 18:26:28.810 | r1 → r2, r1 → r3 | LS-Ack | Acuses de recibo. |
| 18:26:33.817 | r2 → r1, r3 → r1, r1 → r3 | LS-Update + LS-Ack | Retransmisión de la última versión (0x80000011) al vencer el temporizador de retransmisión (5 s). |
| **18:27:01.867** | r2 / r3 / r1 (reinundación) | **LS-Update**, 2 LSAs, originados por r4 | Expira el Dead interval de r2 en r4 (40 s desde el último Hello recibido). r4 publica un Router-LSA (seq 0x8000000c) donde 172.16.77.20/30 pasa a ser **Stub Network**, y retira (MaxAge) su Network-LSA 172.16.77.22. |

**Restauración**

| Hora | Origen → Destino | Mensaje | Contenido / significado |
|---|---|---|---|
| **18:27:13.193** | r2 (.10) → 224.0.0.5 | LS-Update | Router-LSA de r2 (seq 0x80000012): con eth2 de nuevo arriba, r2 anuncia 172.16.77.20/30 como **Stub Network**, porque todavía no tiene adyacencia con r4. |
| **18:27:20.558** | r2 (.10) → 224.0.0.5 | LS-Update | Router-LSA de r2 (seq 0x80000014): la adyacencia con r4 llegó a `Full` y 172.16.77.20/30 vuelve a ser una red de **tránsito** (vecino DR 172.16.77.22). |
| 18:27:20.560 | r2 → 224.0.0.5 (y reinundado por r3 y r1) | LS-Update, 2 LSAs, originados por r4 | Router-LSA de r4 (seq 0x8000000d) con el enlace de tránsito hacia r2 y Network-LSA 172.16.77.22 (seq 0x80000002) con r4 como DR. |
| 18:27:25.558 | r2 → r1, r1/r3 | LS-Update | Retransmisión del LSA 0x80000014. |

### Cómo se llega a cada ruta

1. **Detección:** r2 detecta la caída en el acto porque es su propia interfaz.
2. **Inundación:** r2 genera un Router-LSA sin el enlace a r4. En la captura llega a r1 a las 18:26:28.808 y en menos de 2 ms también llega por r3.
3. **Cálculo:** cada router corre SPF. Como r2 ya no anuncia el segmento r2–r4, el chequeo bidireccional de OSPF descarta ese enlace en **todos** los routers, aunque r4 todavía no detectó la caída (su eth0 sigue `UP` y r2 sigue en `Full` hasta las 18:27:01). Sin ese enlace, el camino más barato entre r1 y r6 es el respaldo (60), tal como estaba previsto en la sección 2.2.
4. **Restauración:** al levantar eth2, r2 anuncia primero la red como stub, que no sirve como tránsito. Recién cuando la adyacencia con r4 llega a `Full` (unos 7 s después, el tiempo de intercambio de Hellos y de bases de datos), r2 y r4 anuncian el enlace como tránsito, el SPF vuelve a encontrar el principal (30) y la ruta regresa a él.

## 6. Efectos colaterales de los costos

Los costos son por interfaz, no por flujo, así que el cambio afecta a **todo** el tráfico del backbone, no solo al que va de r1 a r6. Por ejemplo, según los costos configurados:

- r2 → r5: el enlace directo cuesta 100, pero r2 → r1 → r3 → r5 cuesta 10+20+20 = 50. El tráfico de r2 hacia r5 (y hacia el Cliente B) da la vuelta por r1 y r3.
- r4 → r5: el enlace directo cuesta 100, pero r4 → r6 → r5 cuesta 10+20 = 30.
- En la práctica, los enlaces de costo 100 quedan solo como último recurso.

Esto es esperable en ingeniería de tráfico con costos IGP: para dirigir un flujo concreto se cambia la vista de la topología de toda el área. Si se quisiera controlar caminos por flujo sin afectar al resto, haría falta otra herramienta (por ejemplo, ruteo por política o MPLS-TE).

## 7. Archivos entregados (`parte1.5/shared/`)

| Archivo | Contenido |
|---|---|
| `costos.txt` | `show ip ospf interface` (costo de cada interfaz) en los 8 routers |
| `antes_falla.txt` | Rutas en r1 y r6 hacia la loopback remota y traceroutes en ambos sentidos, con el principal activo |
| `despues_falla.txt` | Lo mismo con el enlace r2–r4 caído |
| `restauracion.txt` | Lo mismo después de volver a levantar el enlace |
| `falla_r2_r4.pcap` | Captura OSPF en r1 durante la falla y la restauración |
