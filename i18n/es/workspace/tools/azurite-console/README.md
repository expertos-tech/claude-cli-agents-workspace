<!-- source: workspace/tools/azurite-console/README.md sha256:05b950e383fec8306721c9fcacb730ba400f5b4ae23c48aec098ec6d4fe9df18 -->

# azurite-console

- [Qué es](#qué-es)
- [Cómo ejecutarlo](#cómo-ejecutarlo)
- [Cómo funciona](#cómo-funciona)
- [La página](#la-página)
- [API](#api)
- [Estructura](#estructura)
- [Cómo probarlo](#cómo-probarlo)
- [Dependencias](#dependencias)

## Qué es

Una página para ver y operar un Azurite local: contenedores y blobs, colas y mensajes, tablas y entidades, y el log de acceso del contenedor. Muestra lo que escribieron los servicios (archivos, documentos JSON, mensajes de cola) y permite borrar, reenviar, mover y editar sin `az storage` ni `docker logs`.

Un pequeño programa en Go sobre el SDK de Azure, con una página React y sin biblioteca de UI, que opera los tres servicios de Azurite de forma segura: solo la cuenta local, confirmación antes de borrar, ETag y recibo de mensaje respetados.

## Cómo ejecutarlo

Todo desde la raíz del workspace. `compose.yaml` inicia Azurite y la consola, con el nombre de proyecto `azurite-console`. La clave de la cuenta viene de `AZURITE_ACCOUNT_KEY`, en el entorno o en `custom/env/azurite-console.env`, la copia rellenada del `.env.example` de esta carpeta en la capa custom (ignorada por git allí, modo 600), que compose lee con `--env-file`. No se escribe ningún `.env` en esta carpeta. La clave es tuya: Azurite usa la misma clave a través de `AZURITE_ACCOUNTS`. Compose se niega a arrancar sin ella. `DOCKER_SOCKET_GID` es el grupo propietario del socket de Docker, para el panel del log de acceso; sin él, el contenedor se une al grupo 0, y el panel explica el motivo cuando no puede leer.

Una vez, crea el archivo y rellena ambos valores sin imprimirlos (`/local-env tools/azurite-console` en una sesión lo crea con valores vacíos para que los rellenes en un editor):

```bash
mkdir -p custom/env && chmod 700 custom/env
(umask 077; printf 'AZURITE_ACCOUNT_KEY=%s\nDOCKER_SOCKET_GID=%s\n' "$(openssl rand -base64 48)" "$(stat -c %g /var/run/docker.sock)" > custom/env/azurite-console.env)
docker compose --env-file custom/env/azurite-console.env -f tools/azurite-console/compose.yaml up -d --build --wait
```

Abre `http://127.0.0.1:28091`. La imagen construye la página y compila el programa; después de cambiar el código, ejecuta el mismo `up -d --build --wait` de nuevo. Para detener y borrar los datos de este proyecto, `docker compose --env-file custom/env/azurite-console.env -f tools/azurite-console/compose.yaml down -v`.

Puertos, todos solo en `127.0.0.1`:

| Servicio | Host | Contenedor |
| --- | --- | --- |
| `azurite-console` | 28091 | 28091 |
| `azurite`, Blob | 30000 | 10000 |
| `azurite`, Queue | 30001 | 10001 |
| `azurite`, Table | 30002 | 10002 |

Azurite arranca con `--skipApiVersionCheck`, porque el SDK de Blob de `go.mod` envía una versión de API más nueva que la que conoce el Azurite de la imagen, que rechazaría toda llamada con `400 InvalidHeaderValue`.

Fuera de Compose, para desarrollar el programa, deja solo Azurite en ejecución, porque el servicio de la consola y `go run` usan el mismo puerto 28091. El valor predeterminado de `-azurite-port` ya es el puerto 30000 publicado por Compose:

```bash
docker compose --env-file ../../custom/env/azurite-console.env stop azurite-console
npm --prefix web ci
npm --prefix web run build
go run . -env-file ../../custom/env/azurite-console.env
```

Esto se ejecuta desde esta carpeta. `npm` escribe solo en `web/node_modules/` y `web/dist/`, las carpetas de salida escribibles de un workspace instalado.

Flags:

| Flag | Predeterminado | Qué hace |
| --- | --- | --- |
| `-addr` | `127.0.0.1:28091` | Dirección del servidor; solo se acepta loopback, salvo con `-container` |
| `-host` | `127.0.0.1` | Host de Azurite; solo loopback, `localhost` o `azurite` |
| `-azurite-port` | `30000` | Primero de los tres puertos consecutivos de Azurite: Blob, Queue y Table. Para un Azurite en los puertos predeterminados, `-azurite-port 10000` |
| `-web` | `web/dist` | Carpeta de la página construida |
| `-env-file` | ninguno | Archivo `KEY=VALUE` leído para `AZURITE_ACCOUNT_KEY` cuando el entorno no la tiene: `../../custom/env/azurite-console.env`. No se busca un `.env` en ninguna carpeta |
| `-max-upload` | 64 MiB | Cuerpo de solicitud más grande, cargas incluidas |
| `-container` | desactivado | Acepta cualquier dirección de escucha; se usa solo en Compose, que publica el puerto solo en `127.0.0.1` |
| `-healthcheck` | desactivado | Llama a `/healthz` de la instancia en `-addr` y sale con 0 si responde; es el healthcheck del contenedor, ya que el contenedor no tiene shell |

En Compose, la imagen se ejecuta con `-container -addr :28091 -host azurite -azurite-port 10000 -web /web`. Fuera de él, la clave viene de `AZURITE_ACCOUNT_KEY` en el entorno o, si falta, del archivo de `-env-file`. Sin el build, `/` muestra los comandos de build, y la API funciona igual.

Para trabajar en la página con recarga automática, `npm --prefix web run dev`: la página se abre en `http://127.0.0.1:25174`, y `/api` va al puerto 28091, sea el servicio de Compose o `go run`.

## Cómo funciona

```text
navegador --/api/...-->  azurite-console (Go, 127.0.0.1:28091)  --azblob/azqueue/aztables-->  Azurite (en Compose, azurite:10000-10002; fuera de él, 127.0.0.1:30000-30002)
                              |--docker logs (solo lectura)-->  contenedor azurite
```

- **Solo el Azurite local.** El programa construye la cadena de conexión con la cuenta `devstoreaccount1`, el host de `-host` y la clave; ningún flag acepta otra cadena de conexión. Fuera de Compose el servidor escucha solo en loopback; en Compose escucha en todas las interfaces del contenedor, y el puerto se publica solo en `127.0.0.1`. La clave nunca se muestra.
- **Socket de Docker.** En Compose, el contenedor monta `/var/run/docker.sock` y se une al grupo `DOCKER_SOCKET_GID`, propietario del socket, para que la CLI `docker` lea el log de `azurite`. El socket da acceso a toda la API de Docker; el programa solo lee (lista de contenedores, inspect y logs).
- **El navegador habla solo con el programa.** La firma de las llamadas a Storage queda en Go; la página no guarda ninguna credencial.
- **Errores.** Todo fallo es un problem document, en inglés por defecto y en portugués de Brasil con `Accept-Language: pt-BR`. Cuando Azurite responde, `detail` lleva su estado y su código (por ejemplo `409 ContainerAlreadyExists`). Los códigos: `console.not_found` (404), `console.conflict` (409), `console.precondition` (412, incluido un recibo de mensaje vencido, que Azurite responde como `400 PopReceiptMismatch`), `console.bad_request` (400), `console.unavailable` (503, Azurite caído; la conexión desiste después de 3 s) y `console.entity_invalid` (400).
- **Vista previa segura.** El contenido de un blob se sirve tal cual solo para PDF, JSON, texto, CSV e imágenes PNG, JPEG, GIF y WebP; cualquier otro tipo (HTML, SVG) va como texto, con `X-Content-Type-Options: nosniff`, de modo que nunca se ejecuta como una página de la consola.
- **Log de acceso.** El contenedor se encuentra por la etiqueta `com.docker.compose.service=azurite` y se lee con `docker logs --tail N --timestamps`. Cada línea se convierte en hora, llamador, servicio, método, recurso decodificado, estado y tamaño. El llamador es el servicio de Compose dueño de la IP; el gateway de la red aparece como `host` (un programa en la máquina). Las llamadas de la propia consola aparecen como `azurite-console` en Compose y como `host` con `go run`. El servicio sale de la forma de la solicitud y de los nombres de colas y tablas; una llamada sobre la propia cuenta, como listar contenedores o colas, aparece como `account`. Sin Docker o sin el contenedor, el panel explica el motivo y el resto de la página sigue funcionando.
- **Operaciones.** Las acciones que cambian algo (crear, borrar, enviar, recibir, guardar) quedan en una lista en memoria con las últimas 200: hora, acción, destino, estado, duración y código de error.
- **Logs y apagado.** Logs JSON en la salida estándar. Con SIGINT o SIGTERM, el servidor deja de aceptar solicitudes y espera hasta 8 s a las que están en curso.

## La página

Una página con cuatro pestañas. La pestaña y la selección viven en el hash de la URL (`#/blobs/events/2026/11/16/`, `#/queues/<queue>`, `#/tables/<table>`), de modo que una recarga conserva el lugar. La barra superior muestra Blob, Queue y Table activos o caídos, con la latencia, y se actualiza cada 5 segundos (se puede desactivar).

| Pestaña | Qué muestra y hace |
| --- | --- |
| Overview | Contadores de cada servicio (contenedores, blobs y tamaño; colas y mensajes; tablas y entidades, con los conteos que se detienen en 10 000 por contenedor y por tabla) y la versión de Azurite; los recursos con un enlace a su pestaña; los errores del log agrupados por servicio, recurso y estado, sin los 404 y 409 que forman parte del trabajo normal; el log de acceso con filtros por servicio, llamador, solo errores y texto; las operaciones de esta página |
| Blobs | Contenedores (crear, borrar, vaciar); navegación por carpetas con breadcrumb, filtro por prefijo y "load more"; detalle del blob con propiedades, metadatos y vista previa (JSON formateado, texto de hasta 256 KB, PDF, imagen); descarga; carga de varios archivos a la carpeta actual; borrado de los seleccionados y de una carpeta entera, con el conteo y el tamaño antes de la confirmación |
| Queues | Colas con el conteo aproximado (crear, borrar, limpiar); ver hasta 32 mensajes sin sacarlos de la cola, con JSON formateado, una opción para decodificar base64 y un resaltado para los mensajes recibidos 5 veces o más; recibir con un tiempo de visibilidad y, para cada uno recibido, borrar, devolver, editar el texto o mover a otra cola, con la cuenta regresiva hasta que vuelva; enviar con verificación de JSON, retraso y TTL |
| Tables | Tablas (crear, borrar); consulta con filtro OData, tamaño de página y navegación por continuación; cuadrícula con una columna por propiedad; editor de entidad en JSON con las anotaciones `@odata.type`, guardar como merge o replace con el ETag leído (un conflicto ofrece recargar), insertar, duplicar y borrar; las propiedades de texto que contienen JSON se muestran formateadas; borrado de las seleccionadas o de todo lo que devuelve el filtro, con el conteo antes; exportar la página como JSON |

Borrar o vaciar un contenedor, borrar o limpiar una cola, borrar una tabla y borrar todas las entidades piden escribir el nombre.

## API

| Grupo | Rutas |
| --- | --- |
| General | `GET /api/overview`, `GET /api/activity?tail=` (de 1 a 5000), `GET /api/operations` |
| Blob | `GET`/`POST /api/containers`, `DELETE /api/containers/{c}`, `POST /api/containers/{c}/empty`, `GET /api/containers/{c}/list?prefix=&marker=`, `GET /api/containers/{c}/usage?prefix=`, `DELETE /api/containers/{c}/prefix?prefix=`, `GET`/`PUT`/`DELETE /api/containers/{c}/blobs/{path}` (`GET` con `?props`, `?download` o `?max=`) |
| Queue | `GET`/`POST /api/queues`, `DELETE /api/queues/{q}`, `POST /api/queues/{q}/clear`, `GET /api/queues/{q}/peek?n=`, `POST /api/queues/{q}/receive`, `POST /api/queues/{q}/messages`, `PUT`/`DELETE /api/queues/{q}/messages/{id}`, `POST /api/queues/{q}/messages/{id}/move` |
| Table | `GET`/`POST /api/tables`, `DELETE /api/tables/{t}`, `GET /api/tables/{t}/entities?filter=&top=&next_pk=&next_rk=`, `GET /api/tables/{t}/entity?pk=&rk=`, `POST`/`PUT`/`DELETE /api/tables/{t}/entities`, `POST /api/tables/{t}/delete-by-filter` (con `dry_run` para solo contar) |

## Estructura

```text
main.go               flags, servidor con apagado ordenado, regla de loopback, plazo de conexión y healthcheck
compose.yaml          Azurite y la consola, con los puertos solo en 127.0.0.1
Dockerfile            imagen de la consola: página construida con Node, programa con Go, CLI docker y distroless nonroot
internal/azurite      cuenta local: clave (entorno o .env), cadena de conexión, regla de host local, puertos y los tres clientes
internal/storage      operaciones de Blob, Queue y Table en tipos propios; clasificación de errores de Azurite
internal/activity     lectura del log del contenedor mediante la CLI docker, parser del log de acceso, llamador por IP de Compose, operaciones en memoria
internal/httpjson     respuestas JSON, problem documents y catálogo de mensajes, solo biblioteca estándar
internal/api          rutas /api/, mensajes de la consola (locales en y pt-BR), página desde web/dist
web/                  página React (Vite y TypeScript), CSS propio, sin biblioteca de UI ni router
```

## Cómo probarlo

```bash
go test ./...
npm --prefix web run build
```

Las pruebas de Go se ejecutan sin red: la cuenta local (hosts y puertos aceptados y rechazados, cadena de conexión, búsqueda de la clave en el archivo de `-env-file`, nunca en un `.env` de las carpetas superiores), la clasificación de errores y la limpieza de la entidad antes de guardar, el parser del log con líneas reales del contenedor, el llamador por IP y las rutas con fakes (estado y código de Azurite en el problem, idioma del problem, método incorrecto, Azurite caído, ETag y modo, validaciones, conteo antes de borrar, una vista previa que nunca sirve HTML, overview con un servicio caído, página sin build). El build de la página verifica los tipos con `tsc`.

Sin Go ni Node en el host, ejecútalas en contenedores, como tu propio usuario, para que escriban solo donde tú puedes (en un workspace instalado, `web/node_modules/` y `web/dist/`):

```bash
docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp -v "$PWD":/src:ro -w /src golang:1.27.3-trixie go test ./...
docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp -v "$PWD/web":/app -w /app node:24.21.0-bookworm-slim sh -c 'npm ci && npm run build'
```

Con el Azurite de `compose.yaml` en ejecución, `AZURITE_CONSOLE_IT=1 AZURITE_CONSOLE_ENV_FILE=../../custom/env/azurite-console.env go test ./internal/storage/` también ejecuta las pruebas contra los puertos 30000 a 30002, que crean recursos `it-console-*` (tablas `itconsole*`) y los borran al final. La clave es la misma que la de Compose: en el entorno o en el archivo de `AZURITE_CONSOLE_ENV_FILE`.

## Dependencias

- El SDK de Azure para Go: `azblob`, `azqueue`, `aztables` y `azcore`. El resto del programa usa solo la biblioteca estándar.
- La imagen `mcr.microsoft.com/azure-storage/azurite:3.37.0`, fijada por tag y digest en `compose.yaml`.
- La CLI `docker`, solo para el log de acceso: en el `PATH` con `go run`; en la imagen, copiada de `docker:29.9.1-cli`.
- En la página: React y React DOM, con Vite, `@vitejs/plugin-react` y TypeScript en el build.
