# 2.3 Política de acceso de la empresa

## 1. El problema: un switch que solo mira direcciones MAC no alcanza

El punto de partida fue el switch de la parte 2.2, que reenvía tramas mirando únicamente la dirección MAC destino. El enunciado pide ahora que los invitados solo puedan hablar con el gateway, resolver los ARP indispensables y navegar por HTTP y HTTPS hacia srv1. Todo lo demás que inicien tiene que descartarse.

Lo primero que notamos es que con la información de Ethernet esta política es imposible de expresar. Cuando un invitado se comunica con cualquier equipo fuera de su subred, la trama sale dirigida a la MAC del gateway, no a la del destino final. Un pedido web a srv1 y un ping a una PC de administración salen del invitado con exactamente la misma MAC destino, y para el switch de la 2.2 son indistinguibles. Lo que los diferencia está más adentro del paquete: la dirección IP destino, que siempre identifica al destino final aunque el paquete pase por el router, el protocolo de transporte y el puerto. Por eso el switch tuvo que "mirar más allá" de Ethernet, que es justamente la sobrecarga de funcionalidad que plantea el enunciado.

## 2. El diseño de la política

Tradujimos la política a una **lista blanca** de cuatro reglas. Un paquete de un invitado se deja pasar si es:

- un ARP dirigido al gateway;
- un paquete IP dirigido al gateway, de cualquier protocolo;
- una conexión TCP a srv1 en el puerto 80;
- una conexión TCP a srv1 en el puerto 443.

Si no coincide con ninguna de las cuatro, se descarta. Elegimos una lista blanca y no una lista de prohibiciones porque es el criterio más seguro: un error u olvido en la configuración tiene como consecuencia que algo deje de funcionar, no que se abra un agujero.

La regla de ARP merecía una decisión explícita. La opción más simple era permitir cualquier ARP. Pero así un invitado podría preguntar por la dirección física de otro invitado, y eso ya es comunicarse con alguien que no es el gateway. Por eso solo permitimos los ARP cuya dirección IP buscada es la del gateway. Esa misma regla cubre las dos direcciones de la conversación. Cuando el invitado pregunta "¿quién tiene la IP del gateway?", la IP buscada es la del gateway. Y cuando es el gateway el que pregunta por el invitado, la respuesta del invitado va dirigida al gateway, así que también coincide.

Una consecuencia de la política que conviene aclarar es que los invitados no tienen acceso a un servidor DNS. Acceden a srv1 por su dirección IP, que es lo que el enunciado permite.

La política se aplica solo al tráfico que **entra** al switch de invitados por los puertos de los invitados. El puerto que conecta con el gateway queda fuera a propósito: por ahí llegan las respuestas de srv1, que tienen como origen el puerto 80 y como destino al invitado, y no coinciden con ninguna regla. Si la política se aplicara también a ese puerto, el invitado podría pedir la página pero nunca recibiría la respuesta.

## 3. La implementación en P4

### Leer más encabezados

El parser de la 2.2 solo extraía Ethernet. Lo ampliamos para que, según el tipo indicado en Ethernet, continúe leyendo un encabezado ARP o uno IPv4, y en este último caso, si el protocolo es TCP, también el encabezado TCP. UDP no aparece en ninguna regla, así que no hizo falta parsearlo. El deparser tiene que volver a emitir todos los encabezados extraídos; si faltara alguno, el paquete saldría del switch mutilado.

No todos los paquetes tienen todos los encabezados: un ping no tiene TCP y un ARP no tiene IP. Para que la tabla de la política siempre tenga con qué comparar, el parser copia los datos relevantes a variables propias del programa (metadata). La IP destino se toma del encabezado IPv4 o, si el paquete es ARP, de la dirección buscada. El protocolo y el puerto destino quedan en cero cuando el encabezado correspondiente no existe. Así una sola columna de "IP destino" sirve tanto para ARP como para IP, y ninguna regla lee un campo inexistente.

Al revisar el programa encontramos un caso que corregimos. El parser asumía que el encabezado IP siempre mide 20 bytes y que todo paquete TCP trae su encabezado al principio. Eso no se cumple si el paquete IP lleva opciones o si es un fragmento que no es el primero. En esos casos, lo que el switch tomaba como "puerto destino" no era el puerto real. Ahora el parser solo interpreta TCP cuando el encabezado IP tiene su largo normal y el paquete no es un fragmento posterior. Si no se cumple, el paquete queda sin puerto y la lista blanca lo descarta. Para el tráfico normal no cambia nada. Llevamos la misma corrección a las partes 2.4 y 3, que usan el mismo programa.

### Dos tablas nuevas

La primera tabla, de rol de puerto, responde a una sola pregunta: ¿este paquete entró por un puerto de invitado? Si la respuesta es sí, lo marca como tráfico de invitado.

La segunda tabla es la lista blanca. Compara cuatro campos (tipo de Ethernet, IP destino, protocolo y puerto destino) usando coincidencia ternaria. Esto permite que cada regla indique para cada campo un valor exacto o un comodín: "cualquier protocolo, cualquier puerto" en la regla del gateway, o "TCP, puerto 80" en la de HTTP. Con coincidencia exacta no podríamos expresar esos comodines. Las reglas ternarias llevan una prioridad, pero como las nuestras no se solapan, el orden no altera el resultado. La acción por defecto de la tabla es descartar.

### El orden importa

Dentro del switch, el paquete recorre tres pasos: primero se determina si viene de un invitado, después, solo en ese caso, se consulta la lista blanca, y por último se aplica el reenvío por MAC de la 2.2. El reenvío **solo** se ejecuta si la política no descartó el paquete. Esto no es un detalle estético. En P4 la acción de descartar no elimina el paquete en el momento, sino que lo marca para descarte. Si después se ejecutara la acción de reenvío, ésta sobrescribiría el puerto de salida y el paquete "descartado" saldría igual.

### Mismo programa, distinta configuración

Los cuatro switches ejecutan exactamente el mismo programa P4. Lo único que cambia es la configuración que carga el plano de control: solo el switch de invitados tiene entradas en las dos tablas nuevas. En los switches de ADMIN, DESARROLLO y servidores esas tablas están vacías, ningún puerto queda marcado como de invitado y su comportamiento es idéntico al de la 2.2. Verificamos con un volcado de las tablas del switch de invitados que las tres entradas de rol de puerto y las cuatro reglas estaban cargadas como esperábamos.

### Contadores

Para cuantificar las decisiones agregamos dos contadores, y necesitamos los dos. El primero tiene dos posiciones, permitidos y descartados, y se incrementa según la acción que tomó la lista blanca. El segundo está asociado directamente a la tabla y lleva una cuenta por regla, lo que muestra cuál de las cuatro reglas dejó pasar cada paquete. La razón de tener ambos es que el contador asociado a la tabla solo cuenta coincidencias con reglas. Los paquetes que no coinciden con nada caen en la acción por defecto y ese contador no los registra. Sin el primero, los descartes serían invisibles.

## 4. Pruebas y resultados

Armamos un plan de pruebas automatizado: un script que, para cada prueba, pone los contadores en cero, vacía las cachés ARP, captura tráfico donde corresponde, genera el tráfico y guarda los contadores. Las 50 verificaciones del plan dieron el resultado esperado.

### Lo permitido funciona

Desde un invitado, la página de srv1 se descargó tanto por HTTP como por HTTPS, y cada una quedó registrada en su propia regla. El ping al gateway respondió normalmente, apoyado en la regla de ARP y en la de IP hacia el gateway.

### Lo prohibido se descarta

El ping del invitado a srv1 no tuvo respuesta. Tampoco la tuvieron un ping a una PC de administración ni un intento de conexión a srv1 en un puerto distinto de 80 y 443. En todos los casos el contador de descartados subió exactamente en la cantidad de paquetes enviados.

Especialmente ilustrativo es el caso de un invitado intentando hacerle ping a otro. En la 2.2 esta misma prueba funcionaba. Ahora falla en el primer paso: el invitado pregunta por ARP quién tiene la IP de su compañero, esa pregunta no está dirigida al gateway y el switch la descarta. El otro invitado nunca recibe nada.

### ADMIN y DESARROLLO no se ven afectados

Desde una PC de administración y una de desarrollo comprobamos ping, HTTP y HTTPS hacia srv1, y conectividad entre ambas subredes. Todo funcionó, y los contadores de política de sus switches quedaron en cero, porque ahí la lista blanca ni siquiera se evalúa.

### Requisito 1: un paquete permitido y uno bloqueado

Para mostrar que dos paquetes que entran al switch tienen destinos distintos, capturamos simultáneamente en las dos interfaces del switch de invitados que intervienen: la que da al invitado y la que da al gateway. En ese momento el invitado pidió la página de srv1 y luego le hizo ping tres veces.

El pedido de conexión TCP (el SYN) aparece en las dos capturas, con el mismo número de secuencia: entró y salió. Los tres pedidos de eco del ping aparecen en la interfaz del invitado y no aparecen en la del gateway: entraron al switch y murieron ahí. Los dos paquetes llevan la misma MAC destino, la del gateway, y el switch los distinguió por su contenido de capas superiores.

### Requisito 2: los contadores

En esa misma prueba los contadores registraron 15 paquetes permitidos y 3 descartados. Los 3 descartados son los pedidos de eco, de 98 bytes cada uno, tal como en la captura. Los 15 permitidos se reparten en 2 ARP y 13 paquetes TCP:

- los 2 ARP son la pregunta del invitado por el gateway y su respuesta cuando el gateway le preguntó a él;
- los 13 TCP son todos los que el invitado envió durante una única descarga: el inicio de la conexión, la confirmación que completa el saludo de tres vías, el pedido de la página, una confirmación por cada uno de los ocho segmentos en que llegó la página, y los dos paquetes del cierre.

La cuenta cierra por los dos lados. El contador de entrada del puerto del invitado registró 18 paquetes, exactamente la suma de permitidos y descartados, así que ningún paquete del invitado escapó a la política. Las respuestas de srv1 no aparecen en estos contadores porque entran por el puerto del gateway, donde la política no se aplica.

Los contadores también revelaron algo que no buscábamos. El ARP con el que el invitado pregunta por el gateway es un broadcast. La política lo permite, y a partir de ahí el reenvío de la 2.2 lo distribuye a todos los puertos, incluidos los de los otros dos invitados, que recibieron una copia cada uno. No pueden contestarle ni comunicarse con él, pero se enteran de que existe. Lo retomamos en las mejoras.

## 5. La limitación de ser stateless (requisito 3)

El switch decide cada paquete de forma aislada, mirando solo sus campos, sin recordar nada de los anteriores. El enunciado, en cambio, habla de bloquear el tráfico **iniciado** desde los invitados, y "quién inició" es una propiedad de la conversación, no de un paquete suelto. Un paquete no dice si es el primero de una conversación nueva o la respuesta a una que empezó otro. Esta diferencia aparece en tres situaciones que reprodujimos.

**Situación A: la política es más estricta de lo pedido.** Una PC de administración le hace ping a un invitado. El enunciado no prohíbe esto, porque no lo inició el invitado. Sin embargo, el ping falla. Capturando en el invitado se ve que recibió los tres pedidos y envió las tres respuestas. Capturando del lado del gateway se ve que ninguna respuesta salió del switch, y el contador de descartados marca exactamente tres. La respuesta no coincide con ninguna regla, y el switch no puede saber que es la respuesta a algo que pidió otro.

**Situación B: la política es más permisiva de lo pedido.** Ahora es srv1 el que abre una conexión hacia un invitado, usando como puerto de origen el 80. El invitado responde aceptando la conexión, y esa respuesta va dirigida a srv1 en el puerto 80: coincide con la regla de HTTP y pasa. Lo confirmamos en la captura del lado del gateway y en srv1, que recibió la aceptación. El enunciado pedía que el invitado pudiera acceder a srv1, no que srv1 pudiera abrirle conexiones al invitado.

**Situación C: pasa tráfico TCP que no pertenece a ninguna conexión.** El invitado envía a srv1, al puerto 80, paquetes de confirmación sueltos, sin haber abierto ninguna conexión. El switch los deja pasar porque coinciden con la regla de HTTP, y srv1 responde con un reinicio de conexión, lo que prueba que los recibió. Esta posibilidad tiene consecuencias prácticas: es la base de técnicas de escaneo que deducen cómo está configurado un servidor a partir de cómo responde a paquetes anómalos, y permitiría inundar al servidor con paquetes que igual tiene que procesar.

Las tres situaciones tienen la misma causa: el switch no recuerda quién inició cada conversación. En un caso eso lo vuelve más estricto de lo pedido y en los otros dos más permisivo. La solución es un firewall **con estado**. En P4 se puede construir usando registros que persisten entre paquetes. Cuando un invitado abre una conexión hacia un destino permitido, el switch anota esa conversación. Desde el otro lado deja pasar solo lo que pertenezca a una conversación anotada, y desde el invitado solo permite paquetes que no sean de inicio si la conversación ya existe. Otra alternativa es delegar esa memoria en un controlador externo que instale reglas por conexión.

## 6. Otras mejoras posibles

Además del firewall con estado, las pruebas dejaron a la vista dos mejoras sencillas:

- **Aislar los broadcasts de los invitados.** Hoy el ARP de un invitado hacia el gateway llega también a los otros invitados. Bastaría con que los broadcasts que entran por un puerto de invitado se replicaran solo hacia el puerto del gateway, usando un grupo de replicación propio.
- **Validar también la MAC destino.** Hoy la lista blanca no verifica que un paquete permitido vaya efectivamente dirigido al gateway. Un invitado podría armar un paquete con IP destino permitida y MAC destino de otro invitado, y el switch lo entregaría. El receptor lo descartaría, porque la IP no es suya, pero exigir que el tráfico de invitados vaya a la MAC del gateway o sea broadcast cerraría ese camino.

Las capturas, los contadores de cada prueba y el script que permite reproducir todo el plan están en el directorio de la parte 2.3.
