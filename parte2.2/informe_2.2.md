# 2.2 Reenvío Ethernet en P4

## 1. Qué construimos

El objetivo de esta parte fue que los switches P4 de la red del Cliente A se comporten como switches Ethernet: que entreguen cada trama al puerto donde está su destino, que difundan los broadcasts y que el plano de control decida cuáles son las asociaciones entre direcciones MAC y puertos. Escribimos un único programa P4 que ejecutan los cuatro switches. Lo que distingue a uno de otro es solamente la configuración que se le carga al arrancar.

El programa parte del esqueleto del curso, que ya reconocía el encabezado Ethernet. Para reenviar por capa 2 no hace falta leer nada más: la decisión depende solo de la dirección MAC destino.

## 2. Cómo decide el switch

El corazón del switch es una tabla de reenvío cuya clave es la MAC destino, comparada de forma exacta. Cada entrada indica qué hacer con las tramas dirigidas a esa dirección, y hay tres acciones posibles: enviarla por un puerto determinado, difundirla o descartarla.

El broadcast no tuvo que tratarse como un caso especial. La dirección de broadcast se carga en la tabla como una entrada más, cuya acción es difundir. Para difundir usamos el mecanismo de replicación de la arquitectura: la trama se asigna a un grupo multicast que contiene los puertos del switch, y el switch genera una copia por cada puerto del grupo. Así, el mismo mecanismo de tabla resuelve tanto el unicast como el broadcast.

Había un detalle que cuidar. El grupo multicast incluye todos los puertos, también aquel por el que entró la trama, y un switch nunca debe devolverle a un host su propio broadcast. Por eso, en la etapa de salida, descartamos cualquier copia cuyo puerto de salida coincida con el de entrada. El filtro tiene que estar en esa etapa porque recién ahí cada copia tiene su propio puerto asignado.

### Qué hacer con un destino desconocido

El enunciado pide definir y justificar qué pasa con una trama dirigida a una MAC que no está en la tabla. Un switch tradicional la inundaría por todos los puertos. Nosotros decidimos **descartarla**, por tres razones.

La primera es la coherencia. Un switch tradicional inunda el unicast desconocido solo mientras aprende dónde está el destino, y a partir de la primera respuesta deja de hacerlo. Nuestro switch no aprende, así que la inundación sería permanente: todo el tráfico hacia un host no registrado se repetiría siempre por todos los puertos.

La segunda es la seguridad. Con el descarte, el switch solo entrega tráfico a los equipos que el plano de control autorizó explícitamente. Es una lista blanca, y es la base sobre la que construimos la política de acceso de la 2.3 y el port security de la 2.4.

La tercera es la observabilidad. Cada trama descartada por esta razón queda registrada en un contador propio.

El costo es que un host nuevo no tiene conectividad hasta que alguien lo registra. Lo analizamos a fondo en la Reflexión.

### Contadores

Agregamos cuatro contadores para poder seguir cada decisión del switch: uno de tramas recibidas por cada puerto, uno de tramas efectivamente enviadas por cada puerto, uno por cada regla de la tabla y uno de tramas descartadas por destino desconocido. Comparando los tres primeros se puede reconstruir el recorrido de una trama: por dónde entró, qué regla usó y por dónde salió.

## 3. La configuración de cada switch

Como la tabla es estática, las direcciones MAC de los equipos tienen que ser predecibles. Por eso las fijamos en el arranque de cada host y de cada interfaz del gateway, con un esquema propio de direcciones administradas localmente en el que la dirección indica la subred y el número de host. Los switches no necesitan MAC propia: son transparentes y ninguna trama va dirigida a ellos.

Cada switch recibe al arrancar su propia configuración. Esta consiste en una entrada hacia el puerto del gateway para la MAC de la interfaz del router en esa subred, una entrada por cada host registrado, la entrada de broadcast y el grupo multicast con los puertos en uso. En todos los switches el primer puerto da al gateway y los siguientes a los hosts. Verificamos esta correspondencia en el registro del propio switch y comprobamos, volcando las tablas, que cada switch tenía cargado exactamente lo previsto.

Para la Reflexión agregamos un cuarto host a la red de administración. Está conectado físicamente al switch y su puerto existe, pero a propósito no lo registramos en el plano de control: no tiene entrada en la tabla ni pertenece al grupo multicast. Así modelamos la situación de "conectar un host nuevo sin tocar la configuración del switch".

## 4. Pruebas y resultados

Armamos un plan de pruebas automatizado. En cada prueba, el script vacía la caché ARP de los hosts involucrados, para que ninguna prueba dependa de la anterior, pone en cero los contadores, captura tráfico donde corresponde, hace el ping y guarda los contadores. Las 46 verificaciones del plan coincidieron con lo esperado.

### Una red de tres hosts

En la red de administración, con tres hosts registrados, todos los pares se comunicaron sin pérdidas y sin descartes. Analizamos en detalle la captura de uno de ellos.

La conversación empieza con un ARP request de broadcast: el primer host pregunta quién tiene la IP del segundo. La pregunta llega porque el switch la replicó con el grupo multicast. En ese pedido el campo de MAC buscada va en ceros, porque es justamente lo que se quiere averiguar. El segundo host responde con un ARP reply unicast, y a partir de ahí todo el intercambio es unicast entre direcciones conocidas: el switch entrega cada trama solo por el puerto que corresponde. Los paquetes llegan sin que se decremente su tiempo de vida, porque no hay ningún router en el camino.

Al final de la captura aparecen dos tramas ARP que el ping no generó. Son una verificación que hace Linux por su cuenta: cuando una entrada de la caché ARP envejece, el sistema confirma que el vecino sigue ahí con un ARP dirigido directamente a la MAC que ya conoce, y el switch lo trata como cualquier unicast.

Los contadores cerraron exactamente con la captura: cada una de las doce tramas quedó registrada en la regla que le correspondía, y la copia del broadcast que habría vuelto al emisor no salió. También encontramos una diferencia aparente de tamaños: las tramas ARP figuran más chicas en la captura del host que las envía que en el switch. Es porque tcpdump las ve antes de que se rellenen hasta el tamaño mínimo de Ethernet.

### El broadcast no vuelve a quien lo envió

Para observar el broadcast aislado, un host le hizo ping a una dirección libre de su subred. Como nadie responde, lo único que circula son sus ARP requests, y lo único que hace el switch es replicarlos. Cada request generó una copia hacia el gateway y hacia cada uno de los otros dos hosts registrados. La copia hacia el puerto de entrada fue descartada por el filtro de salida, y el host no registrado no recibió nada. Las capturas lo confirman: los otros hosts ven los requests y el emisor no recibe ninguno de vuelta.

### El gateway y los demás switches

El ping de un host de administración a su gateway funcionó y usó la regla de la MAC del router. Los otros tres switches, con el mismo programa y su propia configuración, también funcionaron: entre dos hosts de desarrollo, entre dos invitados y entre srv1 y su gateway.

### Entre subredes

El ping de un host de administración a uno de desarrollo también funcionó, pasando por los dos switches y por el router. Capturando en ambos extremos se ve el mismo paquete IP con dos encabezados Ethernet distintos. En la red de administración va desde el host hacia la MAC del gateway. En la red de desarrollo va desde la MAC del gateway hacia el host destino, y con el tiempo de vida decrementado en uno. Es la evidencia de cómo trabaja cada nivel: el router termina la trama en una subred y arma una nueva en la otra, mientras que los switches P4 no tocan ni las direcciones MAC ni el contenido. La demora fue algo mayor que dentro de una misma subred, porque cada paquete atraviesa dos switches y un router en cada sentido.

### El destino desconocido se descarta

Para probar el descarte de forma aislada, le cargamos a un host una entrada ARP fija que asocia una IP con una MAC inexistente. Como la dirección ya está "resuelta", el host no pregunta por ARP y manda directamente los cuatro pings. El switch descartó los cuatro, el contador de destino desconocido marcó exactamente cuatro, y ningún puerto emitió nada. Con una política de inundación, esas tramas habrían llegado a todos los demás hosts.

## 5. Plano de datos y plano de control (Pregunta 2.2)

El plano de datos es el programa P4. Define **cómo** se procesa cada trama: qué encabezados se reconocen, cómo es la tabla y con qué clave se busca, qué hacen las acciones de reenviar, difundir y descartar, el filtro que evita devolver el broadcast, y qué contadores existen y cuándo se incrementan. Esto es idéntico en los cuatro switches.

El plano de control define **con qué datos** se decide: qué MAC corresponde a qué puerto, la entrada de broadcast, qué puertos forman el grupo multicast, y la lectura y puesta en cero de los contadores. Esto cambia en cada switch. También es configuración de cada instancia la correspondencia entre interfaces y puertos, aunque se fije al lanzar el switch.

Un matiz interesante es la acción por defecto. El programa la declara como descarte, pero no la fija como inmodificable, así que el plano de control podría cambiarla a difusión en tiempo de ejecución sin recompilar. El programa establece el valor inicial y el conjunto de acciones posibles, y la elección concreta queda en manos del plano de control.

El plano de datos actúa sobre cada trama. El plano de control actúa al arrancar o cuando se quiere cambiar el comportamiento. Por eso un mismo programa sirve para los cuatro switches, y agregar un host solo requiere tocar la configuración, como se ve en la Reflexión.

**Si el switch aprendiera direcciones automáticamente**, el plano de datos tendría que cambiar en tres aspectos. Necesitaría una segunda tabla indexada por MAC de origen, para detectar direcciones nuevas y avisar al plano de control con el par "esta MAC está en este puerto". La acción por defecto pasaría a ser la inundación, porque mientras la tabla se completa no hay otra forma de que una trama llegue a destino y el destino conteste. Y las entradas deberían expirar, para que un host que se desconecta o cambia de puerto no deje información vieja. El plano de control dejaría de ser una configuración fija y pasaría a ser un controlador en ejecución que recibe esos avisos y actualiza las tablas. El switch se comportaría como uno tradicional, a costa de perder el control explícito sobre quién puede comunicarse con quién.

## 6. Reflexión: un host nuevo

Con la red de tres hosts funcionando, agregamos un cuarto host sin tocar la configuración del switch. **El host nuevo quedó sin conectividad en ninguno de los dos sentidos, pero por motivos distintos en cada uno.** Probamos cada sentido por separado, con las cachés ARP vacías. Esto era necesario porque, como se verá, uno de los hosts aprende la dirección del nuevo durante la segunda prueba, y eso habría cambiado el resultado de la primera.

### Desde un host registrado hacia el nuevo

El host registrado envía su ARP request de broadcast. El switch lo replica al grupo multicast, pero el puerto del host nuevo no está en el grupo. La pregunta nunca le llega: su captura está vacía. El host registrado insiste varias veces y finalmente el ping informa que el destino es inalcanzable, un mensaje que genera el propio emisor al no poder resolver la dirección. El contador de destino desconocido queda en cero, porque nunca llega a salir una trama unicast hacia el host nuevo.

### Desde el host nuevo hacia uno registrado

Aquí pasa algo más interesante. El ARP request del host nuevo **sí llega** al host registrado, porque el switch decide solo por la dirección destino y el broadcast está permitido sin importar de qué puerto venga. El grupo multicast define a quién se entrega un broadcast, no de dónde puede provenir. El host registrado contesta cada pedido, pero sus respuestas van dirigidas a la MAC del host nuevo, que no está en la tabla. El switch las descarta todas, y el contador de destino desconocido registró exactamente una por cada respuesta. El host nuevo nunca recibe contestación.

### La recuperación

Bastó con actuar sobre el plano de control, sin recompilar ni reiniciar nada: agregar una entrada en la tabla para la MAC del host nuevo y sumar su puerto al grupo multicast. Hacían falta las dos cosas porque cubren problemas distintos. La entrada de la tabla resuelve el unicast hacia el host nuevo, que era lo que fallaba en el segundo sentido. El grupo multicast hace que reciba los broadcasts, que era lo que fallaba en el primero. Con solo una de las dos, la conectividad seguiría rota en un sentido. Después del cambio, el ping funcionó en ambos sentidos sin ningún descarte.

### Qué nos enseña

El contraste con un switch tradicional es directo. Un switch tradicional aprende dónde está cada host mirando la MAC de origen de lo que recibe. Con el primer ARP del host nuevo habría aprendido en qué puerto está, y la respuesta habría llegado. También inundaría el tráfico hacia destinos desconocidos. Nuestro switch no hace ninguna de las dos cosas: la tabla solo la escribe el plano de control.

La experiencia también muestra que el dominio de broadcast no lo define solo el cableado. El host nuevo está físicamente en la red de administración, pero no recibe sus broadcasts ni el tráfico dirigido a él. En cambio, sus broadcasts sí llegan a los demás. El dominio efectivo lo determina la configuración del grupo multicast, y además resultó asimétrico.

Por último, se ve el costo de la configuración estática: el mismo dato, "este host está en este puerto", hay que mantenerlo coherente en dos lugares distintos, la tabla y el grupo multicast.

El resultado negativo no es una falla sino la consecuencia esperada de una lista blanca, y es la base de la política de acceso de la 2.3. El segundo sentido deja además una enseñanza: el switch filtra a quién se le entrega el tráfico, pero no controla quién lo origina. Un host no autorizado igual puede inyectar broadcasts en la red. Esa es exactamente la limitación que aborda el port security de la 2.4.

## 7. Limitaciones y mejoras posibles

El multicast que no es broadcast se descarta, porque no tiene entrada en la tabla. En esta red no genera problemas, porque los equipos no usan IPv6, pero con IPv6 habilitado el descubrimiento de vecinos dejaría de funcionar. Se resolvería con una regla que reconozca cualquier dirección de grupo y la difunda.

Toda alta, baja o movimiento de un host exige editar a mano la tabla y el grupo multicast, y mantenerlos coherentes entre sí. En una red más grande convendría un controlador que genere ambas configuraciones a partir de un único inventario.

Tampoco hay mecanismos de redundancia de capa 2, como spanning tree o VLANs. En esta topología en estrella, con un único camino entre cada par de equipos, no hacen falta. En una red con lazos, la replicación de broadcasts generaría tormentas.

Las capturas, los contadores de cada prueba, el volcado de las tablas y el script que reproduce el plan completo están en el directorio de la parte 2.2.
