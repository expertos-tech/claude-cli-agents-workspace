<!-- source: workspace/tools/container-console-docker-ce/docs/manual-tests.md sha256:08b2532fac27e443b159023a10afa985bf2d77fc2de90cb763105ed94071992e -->

# Pruebas manuales de `container-console-docker-ce`

- [Cómo usar](#cómo-usar)
- [Cobertura](#cobertura)
- [Preparación](#preparación)
- [Linux: instalación, acceso directo y unit](#linux-instalación-acceso-directo-y-unit)
- [Reinicio de la máquina](#reinicio-de-la-máquina)
- [Acceso solo desde la propia máquina](#acceso-solo-desde-la-propia-máquina)
- [Entorno apagado](#entorno-apagado)
- [Entorno de solo lectura](#entorno-de-solo-lectura)
- [Control del daemon fuera de la API](#control-del-daemon-fuera-de-la-api)
- [Contenedores](#contenedores)
- [Imágenes, volúmenes, redes y Compose](#imágenes-volúmenes-redes-y-compose)
- [Kubernetes](#kubernetes)
- [YAML inválido](#yaml-inválido)
- [Cancelar una eliminación](#cancelar-una-eliminación)
- [Error recibido y estado real](#error-recibido-y-estado-real)
- [Cambio en hasta 2 s](#cambio-en-hasta-2-s)
- [Diseño e identidad](#diseño-e-identidad)
- [Tema](#tema)
- [Idioma](#idioma)

Guía de verificación, que usted ejecuta en un navegador real y en esta máquina. La herramienta no tiene pruebas automatizadas: se verifica compilando (`make check`) y con estos pasos. Cualquier ítem puede fallar: anote lo que vio y repórtelo.

## Cómo usar

- Cada bloque tiene pasos numerados y el resultado esperado. Un ítem pasa solo si el resultado es el descrito.
- Siga este orden: preparación, Linux, entorno apagado, entorno de solo lectura y el resto. Las pantallas dependen de que Docker esté encendido, salvo el bloque de entorno apagado.
- Los recursos de prueba llevan el prefijo `cc-` para que pueda limpiarlos al final. No use el Grafana (`observability`) para probar: recibe la telemetría real.
- Los textos de la interfaz citados abajo son los de inglés, el idioma predeterminado (la interfaz no tiene español). Un navegador cuyo idioma empieza con `pt` muestra la pantalla en portugués de Brasil.

## Cobertura

Los requisitos de la pantalla y de la instalación:

| Requisito | Dónde comprobarlo |
| --- | --- |
| Estado y datos del daemon, solo lectura | [Entorno de solo lectura](#entorno-de-solo-lectura) |
| La consola no controla el daemon | [Control del daemon fuera de la API](#control-del-daemon-fuera-de-la-api) |
| Contenedores, logs en vivo y terminal | [Contenedores](#contenedores) |
| Imágenes, volúmenes, redes y Compose | [Imágenes, volúmenes, redes y Compose](#imágenes-volúmenes-redes-y-compose) |
| Kubernetes, logs y terminal en el pod | [Kubernetes](#kubernetes) |
| Un YAML inválido no cambia nada | [YAML inválido](#yaml-inválido) |
| Cancelar una eliminación no envía nada | [Cancelar una eliminación](#cancelar-una-eliminación) |
| La pantalla funciona con Docker apagado | [Entorno apagado](#entorno-apagado) |
| Servicio y Grafana después del inicio de sesión | [Linux](#linux-instalación-acceso-directo-y-unit) (servicio al iniciar sesión) y [reinicio de la máquina](#reinicio-de-la-máquina) |
| Acceso solo desde esta máquina | [Acceso solo desde la propia máquina](#acceso-solo-desde-la-propia-máquina) |
| Error recibido y estado real | [Error recibido y estado real](#error-recibido-y-estado-real) |
| Cambio en hasta 2 s | [Cambio en hasta 2 s](#cambio-en-hasta-2-s) |
| Acceso directo en el escritorio | [Linux](#linux-instalación-acceso-directo-y-unit) |
| Identidad visual (`rules/frontend.md`) | [Diseño e identidad](#diseño-e-identidad) |
| Tema que sigue al sistema, con la elección de la persona | [Tema](#tema) |
| Inglés por defecto, portugués de Brasil para navegadores `pt` | [Idioma](#idioma) |

## Preparación

1. En `tools/container-console-docker-ce`, con Node 24 en el `PATH`: `make install`. Esto también instala la unit y el acceso directo, que comprueban las pruebas de Linux.
2. Sin la unit, para probar solo la pantalla: `make build`, ejecute `.data/bin/container-console-docker-ce` y abra <http://127.0.0.1:27850/>. Con la unit instalada, basta con abrir la dirección.
3. Con Docker encendido, cree los recursos de prueba:
   - `docker run -d --name cc-test busybox sleep 3600`
   - Un archivo `~/cc-test/compose.yaml`:

     ```yaml
     services:
       busybox:
         image: busybox
         command: ["sleep", "3600"]
     ```

4. El panel "Actions" queda debajo del contenido. Ahí aparecen el progreso, el éxito y los errores de toda acción.

## Linux: instalación, acceso directo y unit

Cubren el acceso directo, la unit y el inicio del servicio al iniciar sesión. Ejecútelas en la carpeta `tools/container-console-docker-ce`, en la sesión gráfica de su usuario.

| # | Pasos | Resultado esperado |
| --- | --- | --- |
| 1 | `make install` | Imprime `installed container-console-docker-ce.service and <ruta del acceso directo>`. `Container Console` aparece en el menú de aplicaciones, con el ícono de Claude CLI Agents Workspace sin distorsión |
| 2 | `curl -s http://127.0.0.1:27850/healthz` | Responde `{"status":"ok"}` |
| 3 | Haga clic en el acceso directo | El navegador predeterminado abre <http://127.0.0.1:27850/> |
| 4 | Ejecute `make install` de nuevo | Termina sin error, con un solo acceso directo en el menú |
| 5 | `systemctl --user stop container-console-docker-ce.service` y luego haga clic en el acceso directo | El servicio vuelve a arrancar, y la pantalla abre |
| 6 | `systemctl --user kill --signal=SIGKILL container-console-docker-ce.service` | systemd vuelve a arrancar el servicio: `/healthz` responde en unos 2 s |
| 7 | Cierre la sesión y vuelva a entrar | `/healthz` responde sin que usted abra una terminal |
| 8 | `bash linux/uninstall-console.sh` | Desaparecen el acceso directo, la unit y el binario. Docker, los contenedores y `~/.local/state/container-console-docker-ce` se mantienen |

Reinstale con `make install` antes de los bloques siguientes.

## Reinicio de la máquina

| # | Pasos | Resultado esperado |
| --- | --- | --- |
| 1 | Reinicie la máquina y entre en la sesión gráfica | `/healthz` responde en hasta 1 minuto, sin que usted abra una terminal |
| 2 | Abra <http://127.0.0.1:27850/> | Insignia "On" en la barra superior |
| 3 | Abra <http://localhost:3000> | Grafana saludable en el puerto 3000, sin que usted haya arrancado nada |

## Acceso solo desde la propia máquina

| # | Pasos | Resultado esperado |
| --- | --- | --- |
| 1 | `hostname -I` (la primera IP de la interfaz de red activa), luego `curl --max-time 3 http://<ip>:27850/healthz` | Conexión rechazada (curl sale con el error 7). Sin red activa, márquelo como **no verificado**, nunca como aprobado |
| 2 | `curl -s -o /dev/null -w '%{http_code}\n' -H 'Host: attacker.example' http://127.0.0.1:27850/healthz` | `403` |
| 3 | `curl -s -o /dev/null -w '%{http_code}\n' -X POST -H 'Content-Type: application/json' -H 'Origin: http://attacker.example' -H 'Sec-Fetch-Site: cross-site' -d '{"confirm":false}' http://127.0.0.1:27850/api/volumes/cc-x/remove` | `403` (sin la protección sería `422`, porque falta la confirmación) |
| 4 | `curl -s -o /dev/null -w '%{http_code}\n' -H 'Connection: Upgrade' -H 'Upgrade: websocket' -H 'Sec-WebSocket-Version: 13' -H "Sec-WebSocket-Key: $(openssl rand -base64 16)" http://127.0.0.1:27850/ws/live/docker` | `403`, porque falta `Origin` |
| 5 | Ejecute `CONSOLE_LISTEN=0.0.0.0:27850 .data/bin/container-console-docker-ce` | Sale con el error `CONSOLE_LISTEN: host must be 127.0.0.1` |

## Entorno apagado

Detenga Docker con `sudo systemctl stop docker.socket docker.service`. Solo `docker.service` no alcanza: `docker.socket` reactiva el daemon en la siguiente lectura de la consola.

| # | Pasos | Resultado esperado |
| --- | --- | --- |
| 1 | Abra `#/overview` | La página abre. Insignia "Off" en la barra superior y en la tarjeta. Una frase explica qué queda no disponible. Los conteos de Docker dicen "Unavailable" |
| 2 | Abra `#/environment` | La frase dice que Docker está apagado, y `sudo systemctl start docker` aparece como texto. Ningún botón para encender o apagar. Tarjeta "What is unavailable with Docker off" con Docker y Compose |
| 3 | Abra `#/containers`, `#/images`, `#/volumes`, `#/networks` | Un aviso explica el motivo, con un enlace al entorno. Los campos y botones de crear y descargar aparecen deshabilitados, no ocultos |
| 4 | Abra `#/compose` | Los proyectos conocidos siguen en la lista, con el estado "Unknown". Start, Stop y Remove deshabilitados. Agregar un archivo sigue habilitado |
| 5 | Con un clúster accesible, abra `#/kubernetes` | La lista sigue funcionando: Kubernetes no depende del estado de Docker en esta consola |
| 6 | Ejecute `sudo systemctl start docker` en la terminal | Sin recargar, la insignia pasa a "On" y las listas vuelven |

## Entorno de solo lectura

| # | Pasos | Resultado esperado |
| --- | --- | --- |
| 1 | Con Docker encendido, abra `#/environment` | Insignia "On", con versión, CPUs, memoria, driver de almacenamiento, sistema operativo y arquitectura iguales a los de `docker info` |
| 2 | Busque acciones en la pantalla | No hay botón, campo ni diálogo: la pantalla solo muestra |
| 3 | Abra `#/overview` | Tarjeta "Docker" con estado, versión, CPUs y memoria, y el enlace "See the environment" |
| 4 | Ejecute el servicio con `CONSOLE_DOCKER_HOST` apuntando a un socket que usted no puede leer | Insignia "Unknown", con el error recibido en la pantalla |

## Control del daemon fuera de la API

| # | Pasos | Resultado esperado |
| --- | --- | --- |
| 1 | `curl -s -o /dev/null -w '%{http_code}\n' -X POST -H 'Content-Type: application/json' -d '{}' http://127.0.0.1:27850/api/environment/start`; repita con `stop`, `resources`, `kubernetes/start` y `kubernetes/stop` | `404` en todas |
| 2 | Abra `#/kubernetes` | No hay botón para encender ni apagar Kubernetes |

## Contenedores

| # | Pasos | Resultado esperado |
| --- | --- | --- |
| 1 | Abra `#/containers` | `cc-test` aparece, con una insignia de estado (ícono y texto). Los contenedores de pods no aparecen |
| 2 | En la fila, haga clic en "Stop" | Job en el panel. La insignia solo cambia cuando cambia el estado real: "Stopped" |
| 3 | Haga clic en "Start", luego en "Restart" | El estado acompaña cada acción, volviendo a "Running" |
| 4 | Haga clic en el nombre del contenedor | Se abren los detalles, con id completo, imagen, comando, redes y montajes. "See all details as JSON" abre el inspect |
| 5 | Mire "Resource usage" | CPU, memoria, red, disco y procesos cambian cada 2 s. Al salir de la pantalla, las consultas a `/stats` se detienen (pestaña Network del navegador) |
| 6 | Pestaña "Logs", con `docker run -d --name cc-log busybox sh -c 'while true; do date; sleep 1; done'` | Las líneas nuevas aparecen en vivo, sin escalones en el margen. Tab sale del área de logs |
| 7 | Pestaña "Terminal" de `cc-test`; ejecute `echo hello` y `ls` | El comando se ejecuta dentro del contenedor. Redimensionar la ventana ajusta la terminal (`stty size` cambia) |
| 8 | En la terminal, pegue un texto de más de 64 KiB | La conexión no se cae y el texto completo llega al shell |
| 9 | En la terminal, presione Shift+Esc y luego Tab | El foco sale de la terminal y pasa al siguiente control |
| 10 | Ejecute `exit` | La insignia muestra que el proceso terminó con el código recibido. "Connect again" abre otro shell |
| 11 | En "Remove", lea el diálogo y confirme | El diálogo menciona `docker rm --force`. El contenedor desaparece de la lista |
| 12 | Ejecute `docker tag busybox example.local/a/very/long/image/name/for/testing:1` y `docker run -d --name cc-long example.local/a/very/long/image/name/for/testing:1 sleep 600`; en `#/containers`, pase el puntero sobre la columna Image | El nombre termina en `...` en una sola línea, y el navegador muestra el nombre completo junto al puntero. En los detalles del contenedor el nombre aparece completo |

## Imágenes, volúmenes, redes y Compose

| # | Pasos | Resultado esperado |
| --- | --- | --- |
| 1 | En `#/images`, descargue `alpine:3.20` | Líneas de progreso en el panel Actions. La imagen aparece en la lista al terminar |
| 2 | Escriba `-rf` en la referencia y haga clic en "Pull" | Error de formato debajo del campo. No se envía nada |
| 3 | Elimine `alpine:3.20` | Diálogo, luego la imagen desaparece |
| 4 | Elimine la imagen de un contenedor existente | El error de Docker aparece en el panel, y la imagen sigue en la lista |
| 5 | En `#/volumes`, cree `cc-volume`, abra los detalles y elimínelo | Aparece, el JSON del inspect se abre y desaparece después de confirmar |
| 6 | En `#/networks`, cree `cc-network`, abra los detalles y elimínela | Igual que el volumen |
| 7 | Elimine la red `bridge` | Aparece el error de Docker, y la red sigue en la lista |
| 8 | En `#/compose`, haga clic en "Choose file" y elija `~/cc-test/compose.yaml` | Se abre el diálogo de `zenity`, filtrando YAML. El proyecto aparece en la lista |
| 9 | Haga clic en el botón otra vez y cancele en el diálogo | Nada cambia, sin error |
| 10 | Escriba `/tmp/x.txt` en el campo de ruta | Error de formato debajo del campo |
| 11 | Escriba `/etc/compose.yaml` | Rechazo del servicio, con el motivo, en el panel Actions |
| 12 | Escriba la ruta de `~/cc-test/compose.yaml` y agréguelo | Funciona igual que el diálogo |
| 13 | Haga clic en "Start", luego en "Stop" | El estado pasa a "Running" y después a "Stopped" |
| 14 | Cree un volumen en el proyecto, haga clic en "Remove" y confirme con la opción desmarcada | El proyecto sale de la lista, y el volumen se mantiene (`docker volume ls`) |
| 15 | Agréguelo de nuevo, levántelo, elimínelo con "Also remove the volumes of the project, which deletes their data" marcado | El volumen desaparece. Al reabrir el diálogo, la opción aparece desmarcada |

## Kubernetes

Necesita un clúster accesible en el contexto actual del kubeconfig o en `CONSOLE_KUBE_CONTEXT`. Prepare con `kubectl create deployment cc-web --image=nginx:alpine` y `kubectl expose deployment cc-web --port=80`.

| # | Pasos | Resultado esperado |
| --- | --- | --- |
| 1 | Abra las pestañas Namespaces, Pods, Deployments y Services | Tablas reales, con el recurso de prueba. El filtro de namespace funciona |
| 2 | Abra los detalles de cada tipo | Datos de la lista y JSON completo |
| 3 | En Deployments, haga clic en "Scale", ingrese 3 | El diálogo abre con el valor actual. Después, "3 of 3 ready" |
| 4 | Ingrese 1001 | Error debajo del campo. No se envía nada |
| 5 | Abra un pod, pestaña Logs | Líneas en vivo |
| 6 | Pestaña Terminal; ejecute `hostname` | Muestra el nombre del pod |
| 7 | Elimine el pod | El diálogo avisa que el deployment crea otro. Aparece un pod nuevo |
| 8 | Elimine el service, el deployment y un namespace de prueba | Cada uno desaparece después de confirmar |
| 9 | Apunte el contexto a un clúster caído (`CONSOLE_KUBE_CONTEXT`, o `kubectl config use-context`) y abra la pantalla | Aviso "No Kubernetes cluster answers", con el error recibido. Pestaña "Apply YAML" con campo y botón deshabilitados. La pantalla sigue intentando |
| 10 | Vuelva al contexto del clúster en funcionamiento | La lista vuelve sin recargar |

Si `kubectl` dice que el contexto no existe, la causa es la descrita en [operación](operations.md#fallas-comunes), no un defecto de la pantalla.

## YAML inválido

| # | Pasos | Resultado esperado |
| --- | --- | --- |
| 1 | En "Apply YAML", haga clic en "Apply" con el campo vacío | "The YAML is empty." debajo del campo |
| 2 | Pegue un Deployment con un campo que no existe en `spec` | El job falla, con el error de `kubectl` en el panel. El texto sigue en el campo. Nada cambia en el clúster (`kubectl get`) |
| 3 | Pegue un recurso válido y otro inválido en el mismo archivo | La misma falla, y el válido tampoco se crea |
| 4 | Pegue un YAML válido | El recurso aparece en la lista |

## Cancelar una eliminación

Para contenedor, imagen, volumen, red, proyecto Compose, namespace, pod, deployment y service:

| # | Pasos | Resultado esperado |
| --- | --- | --- |
| 1 | Haga clic en "Remove" | El diálogo abre con el foco en "Cancel" |
| 2 | Intente sacar el foco del diálogo con Tab | El foco no sale de él |
| 3 | Haga clic en "Cancel" | El diálogo se cierra, el foco vuelve al botón y el recurso se mantiene. En la pestaña Network, ningún POST |
| 4 | Repita y presione Esc | El mismo resultado |

## Error recibido y estado real

| # | Pasos | Resultado esperado |
| --- | --- | --- |
| 1 | En otra terminal, `docker rm -f cc-test` y, antes de que la lista se actualice, haga clic en "Stop" en la pantalla; o detenga el contenedor dos veces | El error recibido aparece sin traducir bajo "Error received", con el código de salida. La fila muestra el estado real |
| 2 | Elimine una imagen en uso | El mismo comportamiento, con la fila todavía en la lista |
| 3 | Haga clic en "Dismiss" en el error | La entrada desaparece, el foco queda en el panel. Recargar no trae el error de vuelta |
| 4 | Provoque un error y recargue sin descartarlo | El error sigue en el panel |
| 5 | Detenga el servicio con la pantalla abierta | La franja "The live connection to the service dropped" aparece en hasta 2 s. Un clic en cualquier acción muestra "Could not reach the service" |
| 6 | Arranque el servicio de nuevo | La franja desaparece en hasta 2 s, y los datos vuelven sin recargar |

## Cambio en hasta 2 s

| # | Pasos | Resultado esperado |
| --- | --- | --- |
| 1 | Cree 30 contenedores: `for i in $(seq 30); do docker run -d --name cc-$i busybox sleep 3600; done` | Los 30 aparecen en la lista |
| 2 | `docker stop -t 0 cc-7` desde la terminal, con la pantalla abierta | La fila cambia a "Stopped" en hasta 2 s |
| 3 | Haga clic en "Start" en la fila de `cc-7` | La fila cambia a "Running" en hasta 2 s después del final del job |
| 4 | Con 30 pods, repita borrando un pod desde la terminal | La lista de pods cambia en hasta 2 s |

Limpieza: `docker rm -f $(docker ps -aq --filter name=cc-)`, y borre el namespace, los recursos de Kubernetes y `~/cc-test`.

## Diseño e identidad

En 320, 390, 768, 1024 y 1280 px, en las pantallas de contenedores, entorno, Compose y pods (`rules/frontend.md`):

| # | Comprobar | Resultado esperado |
| --- | --- | --- |
| 1 | Desplazamiento horizontal de la página | Nunca aparece. Una tabla ancha se desplaza solo dentro de su tarjeta |
| 2 | Tablas por debajo de unos 1024 px | Las columnas secundarias pasan a la primera celda, con una etiqueta. Nombre, estado y acciones siempre visibles |
| 3 | Tablas en 320 px | Cada fila se vuelve un bloque: nombre, datos apilados, estado y botones, sin cortar texto |
| 4 | Menú por debajo de 1024 px | El botón de menú abre el cajón `<dialog>` sobre `ink`. Esc lo cierra, y el foco vuelve al botón |
| 5 | Barra superior y menú | Fondo `ink`, el ícono del proyecto y, al lado, `Claude CLI Agents Workspace` con `Container Console` debajo, sin distorsión. El favicon es el mismo ícono. El ícono es decorativo (texto alternativo vacío): el nombre de al lado es lo que lee el lector de pantalla |
| 6 | Títulos y texto | Títulos en Poppins 700, sin punto final azul y sin texto encima del título. El resto en Roboto. Esquinas de 5 px en botones, campos e insignias, y 20 px en tarjetas |
| 7 | Foco con Tab en todas las pantallas | Anillo `#0076a3` en claro, `#24bee6` en oscuro y sobre `ink`. El primer Tab muestra "Skip to content" |
| 8 | Estado | Siempre ícono y texto |
| 9 | Ids y rutas largas | Monoespaciados, cortando solo después de `.`, `/` o `-`. Un tramo sin esos signos se desplaza en su propia caja |
| 10 | Interruptor "Animate data changes", en el menú | Apagado, las barras de CPU y memoria de los detalles de un contenedor cambian sin transición, y la elección persiste. Lo mismo con la reducción de animaciones del sistema |
| 11 | Consola del navegador en todas las pantallas | Ninguna violación de CSP, ningún error de fuente o imagen |
| 12 | Celular o simulador táctil | Campos de 16 px, sin zoom al enfocar. Botones de al menos 40 px |

## Tema

La apariencia de GNOME cambia en Configuración > Apariencia. Empiece sin una elección guardada: en la consola del navegador, ejecute `localStorage.removeItem("container-console-docker-ce.theme")` y recargue.

| # | Pasos | Resultado esperado |
| --- | --- | --- |
| 1 | Sin elección guardada, con el sistema en Claro | Fondo `#f8f9fc`, tarjetas blancas. El campo `Theme`, en el menú lateral, muestra "Follow the system" |
| 2 | Con la pantalla abierta, cambie el sistema a Oscuro | Sin recargar, el fondo pasa a `#303841` y las tarjetas a `#343f4b`. La barra superior y el menú siguen en `ink` |
| 3 | Vuelva el sistema a Claro | La pantalla vuelve a claro sin recargar |
| 4 | Con el sistema en Claro, elija "Dark" | La pantalla se oscurece de inmediato |
| 5 | Recargue la página | Sigue oscura, sin un destello claro antes |
| 6 | Cambie el sistema a Oscuro y luego a Claro | La pantalla queda oscura en ambos casos: la elección gana sobre el sistema |
| 7 | Con el sistema en Oscuro, elija "Light" y recargue | Sigue clara, sin un destello oscuro antes |
| 8 | Cambie el sistema a Claro y de nuevo a Oscuro | La pantalla queda clara en ambos casos |
| 9 | Elija "Follow the system", recargue y cambie el sistema | La elección persiste, y la pantalla vuelve a seguir al sistema |
| 10 | Solo con teclado: Tab hasta `Theme`, flechas y Enter para cambiar | El anillo de foco aparece en el campo, y el tema cambia |
| 11 | Por debajo de 1024 px, cambie el tema en el cajón del menú y amplíe la ventana a 1024 px o más | El tema cambia con el cajón abierto, y el campo del menú lateral muestra la misma elección |
| 12 | En oscuro, recorra contenedores, entorno, Compose y pods | Texto legible en tarjetas, tablas, avisos y bloques de código. Estado siempre con ícono y texto, y el ícono legible dentro de la insignia |
| 13 | En oscuro, botones, enlaces y pestañas | Botón primario `#0076a3` con borde `#24bee6`. Enlaces y pestaña actual en `#24bee6`. Botón deshabilitado distinguible. Anillo de foco visible en todas las superficies |
| 14 | En oscuro, abra un diálogo de confirmación y pase el mouse por filas de tabla | El diálogo se destaca del fondo oscurecido. La fila cambia de fondo, con texto legible |
| 15 | En oscuro, mire las barras de CPU y memoria en los detalles de un contenedor y fuerce un error en un campo | Barra visible sobre la pista. Ícono de error legible sobre la tarjeta |
| 16 | En ambos temas, abra los logs y la terminal de un contenedor | Fondo oscuro y texto claro, iguales en ambos temas. El texto seleccionado sigue legible |
| 17 | Con la terminal abierta, cambie el tema | La terminal no cambia de color, y la conexión sigue abierta |
| 18 | Consola y pestaña de red del navegador, en ambos temas | Ninguna violación de CSP. `/theme-init.js` responde 200 |

## Idioma

| # | Pasos | Resultado esperado |
| --- | --- | --- |
| 1 | Con el idioma del navegador en inglés (o cualquier idioma que no empiece con `pt`), abra la consola | Todo el texto está en inglés: menú, títulos, botones, avisos y las descripciones de los jobs en el panel Actions |
| 2 | Cambie el idioma del navegador a portugués (`pt` o `pt-BR`) y recargue | Todo el texto está en portugués de Brasil, por ejemplo "Ligado" en la barra superior y "Seguir o sistema" en el campo `Tema`. Números y fechas usan el formato brasileño |
| 3 | En ambos idiomas, provoque un error de CLI (por ejemplo, elimine la red `bridge`) | La frase del código de error se traduce, y el error recibido aparece tal como llegó, sin traducir |

Fuera de estas listas y no verificados: lectores de pantalla, navegadores distintos del que usted use y colores forzados.
