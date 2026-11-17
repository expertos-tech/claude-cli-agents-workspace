<!-- source: workspace/tools/container-console-docker-ce/docs/api.md sha256:1b973a49e35ebec110e74d073d205c9d07585072ed781f5cffc2446767464394 -->

# Contrato de la API de `container-console-docker-ce`

- [Convenciones](#convenciones)
- [Errores](#errores)
- [Jobs](#jobs)
- [Rutas REST](#rutas-rest)
- [WebSocket: reglas comunes](#websocket-reglas-comunes)
- [Tópicos en vivo](#tópicos-en-vivo)
- [Logs](#logs)
- [Terminal](#terminal)
- [Lo que el front-end debe respetar](#lo-que-el-front-end-debe-respetar)

Referencia para quien escribe la pantalla. Fuente de las rutas: `internal/httpapi/`.

## Convenciones

- Base: `http://127.0.0.1:27850` o `http://localhost:27850`. Use URLs relativas y arme la URL del WebSocket a partir de `location.host`.
- Sin inicio de sesión. El acceso está protegido por `Host` y `Origin`, descritos abajo.
- Todo cuerpo y toda respuesta son JSON con campos en `camelCase`. Horarios de los jobs: RFC 3339 en UTC.
- GET nunca cambia el estado. Toda mutación se convierte en un [job](#jobs) y no retiene la petición HTTP. Las dos excepciones están indicadas en las rutas de Compose.
- Las listas no tienen ruta REST: llegan por los [tópicos](#tópicos-en-vivo). REST es solo para detalles y comandos.

Reglas aplicadas a todas las rutas, en este orden:

| Regla | Rechazo |
| --- | --- |
| `Host` exactamente igual a `127.0.0.1:<puerto>` o `localhost:<puerto>` | 403 `forbidden` |
| `http.CrossOriginProtection`: `Sec-Fetch-Site` u `Origin` de otro sitio en un método que cambia el estado | 403 `forbidden` |
| POST con `Content-Type: application/json`, **incluso sin cuerpo** | 403 `forbidden` |
| Cuerpo de hasta 1 MiB | 413 `body_too_large` |
| Campo desconocido, JSON mal formado o datos después del JSON | 422 `invalid_body` |

Todo rechazo de seguridad es igual, a propósito: el motivo solo va al log del servicio. Un cuerpo vacío equivale a `{}`, así que un `confirm` ausente es `false`.

Formatos aceptados:

| Valor | Formato |
| --- | --- |
| Id o nombre de contenedor, volumen y red | `^[a-zA-Z0-9][a-zA-Z0-9_.-]*$`, hasta 255 caracteres |
| Referencia de imagen | `^[a-zA-Z0-9][a-zA-Z0-9._:/@-]*$`, hasta 512 caracteres |
| Proyecto Compose | `^[a-z0-9][a-z0-9_-]*$` |
| Ruta de Compose | Absoluta, sin `..`, `.yaml` o `.yml`, un archivo regular dentro de `$HOME`, comprobado después de resolver enlaces |
| Namespace y service | DNS-1123 label |
| Pod y deployment | DNS-1123 subdomain |

Encabezados de toda respuesta: `Content-Security-Policy`, `X-Content-Type-Options: nosniff`, `Referrer-Policy: no-referrer` y `Cross-Origin-Resource-Policy: same-origin`.

## Errores

Una única forma en REST:

```json
{ "error": { "code": "environment_not_on", "message": "the docker daemon is not on", "params": { "state": "off" } } }
```

- `code`: estable, es la clave del diccionario de traducción.
- `message`: técnico, en inglés. Cuando el error viene de una CLI, es el stderr recibido, que la pantalla muestra sin traducir.
- `params`: valores con nombre para la frase traducida, cuando los hay.
- `exitCode`: código de salida de la CLI, cuando lo hay.

| Estado | Significado | Códigos |
| --- | --- | --- |
| 403 | Rechazo de seguridad, ver [Convenciones](#convenciones) | `forbidden` |
| 404 | El destino no existe | `container_not_found`, `volume_not_found`, `network_not_found`, `kubernetes_resource_not_found`, `kubernetes_kind_unknown`, `compose_project_not_found`, `job_not_found`, `route_not_found` |
| 409 | El estado actual rechaza la acción | `environment_not_on` (con `params.state`), `kubernetes_unavailable` (con el error de `kubectl` en `message`), `file_picker_busy`, `compose_files_unknown` |
| 413 | Cuerpo por encima del límite | `body_too_large` |
| 422 | Entrada rechazada; nada se ejecutó | `invalid_body`, `confirmation_required`, `invalid_docker_name`, `invalid_image_reference`, `invalid_compose_project`, `compose_path_invalid`, `compose_file_invalid`, `invalid_kubernetes_name`, `replicas_required`, `replicas_out_of_range` (`params.max`), `yaml_empty` |
| 502 | La CLI falló en una consulta | `command_failed`, `command_timeout`, `binary_not_found`, `action_failed` |

Una ruta con el método equivocado recibe el 405 predeterminado de Go, en texto.

Códigos que solo existen en el WebSocket. Llegan en una trama `error` después del upgrade (ver [WebSocket: reglas comunes](#websocket-reglas-comunes)), con la misma forma de `code`, `message` y `params`, y la clase del error entre paréntesis:

| Código | Cuándo | Cierre |
| --- | --- | --- |
| `topic_not_found` (no encontrado) | `/ws/live/{topic}` con un tópico que no existe | 1000 |
| `too_many_terminals` (conflicto, `params.max`) | Una nueva terminal después del límite de terminales simultáneas | 1013 |
| `invalid_terminal_size` (entrada inválida) | `cols` o `rows` en la URL, o en una trama `resize`, fuera de 1 a 1000 | 1000 en la URL; 1008 en la trama |
| `invalid_terminal_frame` (entrada inválida) | Una trama de texto que no es `resize` | 1008 |

Los errores REST (`environment_not_on`, `container_not_found` y los demás de la tabla anterior) también pueden llegar en una trama `error`, por ejemplo al abrir logs o una terminal con Docker apagado.

## Jobs

Flujo de toda mutación:

1. La pantalla envía el POST.
2. El servicio valida formato, confirmación y estado. Una falla aquí devuelve un error y nada se ejecuta.
3. El servicio devuelve `202` con `{ "job": <Job> }` en el estado `running`.
4. El tópico `jobs` trae cada cambio: nuevas líneas de salida y el final.
5. Al terminar, `environment`, `docker` y `kubernetes` se actualizan de inmediato. La fila en la pantalla solo cambia con ese snapshot, nunca de forma optimista.

```json
{
  "id": "J4PZ3Q8W2M6XK1VBN7TRY5HGCD",
  "kind": "container.stop",
  "target": "b2958c286bef",
  "status": "failed",
  "output": ["..."],
  "error": { "code": "command_failed", "message": "Error response from daemon: ...", "exitCode": 1 },
  "startedAt": "2026-11-16T22:15:00Z",
  "finishedAt": "2026-11-16T22:15:02Z"
}
```

- `status`: `running`, `succeeded` o `failed`. `error` y `finishedAt` solo aparecen cuando corresponden.
- `output`: últimas 200 líneas. El servicio guarda en memoria los jobs en ejecución y los últimos 50 terminados, y pierde todo al reiniciarse.
- `error.code`: `command_failed`, `command_timeout`, `binary_not_found` o el código de dominio. `error.message` es el error recibido, que se muestra tal como llegó.

| `kind` | `target` |
| --- | --- |
| `container.start`, `container.stop`, `container.restart`, `container.remove` | Id o nombre |
| `image.pull`, `image.remove` | Referencia |
| `volume.create`, `volume.remove`, `network.create`, `network.remove` | Id o nombre |
| `compose.up`, `compose.stop`, `compose.remove` | Nombre del proyecto |
| `kubernetes.remove`, `kubernetes.scale` | `<kind>/<namespace>/<nombre>`, o `namespaces/<nombre>` |
| `kubernetes.apply` | Vacío |
| `docker.cleanup` | `volumes` cuando incluye volúmenes, vacío sin ellos |

## Rutas REST

`job` en la columna de respuesta significa `202 { "job": <Job> }`. Toda eliminación exige `"confirm": true`, comprobado en el servidor. Sin él: 422 `confirmation_required`.

### Servicio

| Ruta | Cuerpo | Respuesta |
| --- | --- | --- |
| `GET /healthz` | Ninguno | `200 { "status": "ok" }` |
| `GET /api/jobs/{id}` | Ninguno | `200 { "job": <Job> }` |

### Entorno

Sin ruta REST: el entorno es de solo lectura y llega por el tópico [`environment`](#environment). Controlar docker-ce requiere root, y la consola nunca enciende ni apaga el daemon.

### Contenedores

| Ruta | Cuerpo | Respuesta |
| --- | --- | --- |
| `GET /api/containers/{id}` | Ninguno | `200` con el objeto de `docker inspect` |
| `GET /api/containers/{id}/stats` | Ninguno | `200 { "cpuPercent", "memoryUsage", "memoryPercent", "networkIO", "blockIO", "pids" }`, textos tal como los imprime la CLI |
| `POST /api/containers/{id}/start` | `{}` | job |
| `POST /api/containers/{id}/stop` | `{}` | job |
| `POST /api/containers/{id}/restart` | `{}` | job |
| `POST /api/containers/{id}/remove` | `{ "confirm": true }` | job. Usa `docker rm --force`, y el diálogo debe decirlo |

`stats` tarda cerca de 1 s. Consúltelo cada 2 s solo mientras los detalles estén abiertos.

### Imágenes

| Ruta | Cuerpo | Respuesta |
| --- | --- | --- |
| `POST /api/images/pull` | `{ "reference": "alpine:3.20" }` | job, con las líneas de progreso en `output` |
| `POST /api/images/remove` | `{ "reference": "<campo reference de la lista>", "confirm": true }` | job. Sin `--force`: una imagen en uso devuelve el error en el job |

La referencia va en el cuerpo porque contiene `/`.

### Volúmenes y redes

| Ruta | Cuerpo | Respuesta |
| --- | --- | --- |
| `POST /api/volumes` | `{ "name": "data" }` | job |
| `GET /api/volumes/{id}` | Ninguno | `200` con el objeto de `docker volume inspect` |
| `POST /api/volumes/{id}/remove` | `{ "confirm": true }` | job |
| `POST /api/networks` | `{ "name": "my-network" }` | job |
| `GET /api/networks/{id}` | Ninguno | `200` con el objeto de `docker network inspect` |
| `POST /api/networks/{id}/remove` | `{ "confirm": true }` | job |

Las eliminaciones no usan `--force`: un recurso en uso devuelve el error en el job.

### Limpieza

| Ruta | Cuerpo | Respuesta |
| --- | --- | --- |
| `GET /api/cleanup` | Ninguno | `200` con `{ containers, images, networks, volumes, buildCache }`: cada lista con `{ id, name, detail? }`, y `buildCache` tal como lo imprime `docker system df` |
| `POST /api/cleanup` | `{ "confirm": true, "volumes": false }` | job `docker.cleanup` |

Un contenedor activo está `running`, `paused`, `restarting` o `removing`; un contenedor de un pod de Kubernetes cuenta como activo. El resumen lista los contenedores que no están activos y las imágenes, redes (salvo `bridge`, `host` y `none`) y volúmenes que ningún contenedor activo usa. El job ejecuta, en orden: `docker container prune --force --filter label!=io.kubernetes.pod.namespace`, `docker image prune --all --force`, `docker network prune --force`, `docker volume prune --all --force` (solo con `"volumes": true`) y `docker builder prune --all --force`, cada paso con el plazo de `CONSOLE_TIMEOUT_DOCKER_PULL`. Cada paso actúa sobre el estado del daemon en el momento en que se ejecuta.

### Compose

| Ruta | Cuerpo | Respuesta |
| --- | --- | --- |
| `POST /api/compose/file-dialog` | `{}` | `200 { "path": "/home/.../compose.yaml", "canceled": false }`. Cancelado: `path` vacío y `canceled: true`. No es un job |
| `POST /api/compose/projects` | `{ "path": "<ruta absoluta>" }` | `201 { "project": <Project> }`. No es un job y funciona con Docker apagado |
| `POST /api/compose/projects/{name}/up` | `{}` | job |
| `POST /api/compose/projects/{name}/stop` | `{}` | job |
| `POST /api/compose/projects/{name}/remove` | `{ "confirm": true, "removeVolumes": false }` | job. Ejecuta `down`, con `--volumes` solo si está marcado, y lo quita de la lista |

- `file-dialog` abre `zenity --file-selection` y solo devuelve la ruta. Una sesión sin display devuelve 502 `command_failed`, con el error recibido, y no una cancelación. Para agregar el proyecto, envíelo a `POST /api/compose/projects`. Queda abierto hasta 5 min; un segundo pedido recibe 409 `file_picker_busy`. La pantalla también ofrece un campo de ruta, para cuando el diálogo no se abre.
- El nombre del proyecto viene del propio Compose. Un archivo que Compose rechaza: 422 `compose_file_invalid`, con el error en `message`.
- Las acciones usan los archivos que conoce el servicio, y el navegador nunca envía una ruta en ellas. Un proyecto con un archivo fuera de `$HOME` recibe 422 `compose_path_invalid`.

### Kubernetes

`{kind}` es `pods`, `deployments` o `services`. Sin un clúster accesible, toda ruta de esta sección recibe 409 `kubernetes_unavailable`.

| Ruta | Cuerpo | Respuesta |
| --- | --- | --- |
| `GET /api/kubernetes/namespaces/{name}` | Ninguno | `200` con el JSON de `kubectl get` |
| `GET /api/kubernetes/{kind}/{namespace}/{name}` | Ninguno | `200` con el JSON de `kubectl get` |
| `POST /api/kubernetes/namespaces/{name}/remove` | `{ "confirm": true }` | job |
| `POST /api/kubernetes/{kind}/{namespace}/{name}/remove` | `{ "confirm": true }` | job |
| `POST /api/kubernetes/deployments/{namespace}/{name}/scale` | `{ "replicas": 3 }`, de 0 a 1000 | job |
| `POST /api/kubernetes/apply` | `{ "yaml": "<texto>" }` | job |

`apply` ejecuta `kubectl apply --dry-run=server --validate=strict -f -` y, solo si tiene éxito, `kubectl apply -f -`. Un YAML inválido termina el job en `failed`, con el error en `error.message`, y nada cambia. Límite conocido: un archivo que crea un namespace y recursos dentro de él se rechaza en el ensayo; la recomendación es aplicar el namespace primero.

## WebSocket: reglas comunes

- `Origin` es obligatorio y debe ser exactamente `http://127.0.0.1:<puerto>` o `http://localhost:<puerto>`. Incorrecto o ausente: 403 antes del upgrade. No hay excepción para un servidor de desarrollo.
- Todo lo que no es seguridad se rechaza después del upgrade, con una trama de error, porque el navegador no lee el cuerpo de un upgrade rechazado.
- Las tramas de control son texto, con JSON:

```json
{ "type": "error", "code": "environment_not_on", "message": "the environment is not on", "params": { "state": "off" } }
```

| `type` | Dónde | Significado |
| --- | --- | --- |
| `snapshot` | Tópicos | Snapshot completo, ver [Tópicos en vivo](#tópicos-en-vivo) |
| `error` | Todos | Los mismos `code`, `message`, `exitCode` y `params` de REST. La conexión se cierra a continuación |
| `end` | Logs | El stream terminó normalmente |
| `exit` | Terminal | El proceso terminó. Trae `exitCode` |

Cierre: 1000 normal, 1001 servicio terminando, 1008 trama inválida del cliente, 1009 trama de más de 64 KiB, 1013 límite de terminales.

Cada escritura tiene un plazo de 5 s: un cliente demasiado lento pierde la conexión. Compresión desactivada.

## Tópicos en vivo

`GET /ws/live/{topic}`, con `topic` igual a `environment`, `docker`, `kubernetes` o `jobs`. Un tópico que no existe: trama `error` con `topic_not_found`.

- Cada trama es el snapshot completo, sin diff: `{ "type": "snapshot", "topic": "docker", "data": { ... } }`.
- La primera llega apenas se suscribe, y las siguientes en cada cambio de contenido. Un cliente lento se salta las intermedias.
- El cliente no envía nada: un mensaje recibido cierra la conexión.
- Sin suscriptores, el observador del tópico se detiene. El cliente se reconecta solo, esperando hasta 2 s, y muestra la franja mientras se reconecta.

| Tópico | Se dispara en |
| --- | --- |
| `environment` | Cada 1 s y al final de un job. Cada lectura ejecuta `docker info` |
| `docker` | Un evento relevante de `docker events`, con debounce de 150 ms; cada 5 s; al final de un job |
| `kubernetes` | Cada 1 s y al final de un job |
| `jobs` | Cada cambio de job |

### `environment`

```json
{
  "state": "on",
  "serverVersion": "28.4.0",
  "cpus": 8,
  "memoryBytes": 16448081920,
  "storageDriver": "overlay2",
  "operatingSystem": "Ubuntu 24.04.3 LTS",
  "osType": "linux",
  "architecture": "x86_64"
}
```

- `state`: `on`, `off` o `unknown`. `off` significa que nada responde en el socket. `unknown` significa otra falla, como permiso denegado o un binario ausente.
- `reason`, solo cuando el estado no es `on`: el error recibido.
- Los demás campos solo existen con el estado `on`. Memoria en bytes.

### `docker`

```json
{
  "available": true,
  "composeProjects": [{ "name": "observability", "state": "running", "status": "running(1)", "configFiles": ["/home/.../compose.yaml"] }],
  "containers": [{ "id": "b295...", "name": "observability-otel-lgtm-1", "image": "grafana/otel-lgtm:0.39.0", "command": "\"bash ...\"", "state": "running", "status": "Up 5 minutes (healthy)", "health": "healthy", "ports": "127.0.0.1:3000->3000/tcp", "createdAt": "2026-11-16 18:34:13 -0300 -03", "composeProject": "observability" }],
  "images": [{ "id": "sha256:...", "repository": "alpine", "tag": "3.20", "reference": "alpine:3.20", "size": "7.8MB", "createdAt": "..." }],
  "volumes": [{ "name": "data", "driver": "local", "scope": "local", "mountpoint": "/var/lib/docker/volumes/data/_data", "composeProject": "observability" }],
  "networks": [{ "id": "48b4...", "name": "bridge", "driver": "bridge", "scope": "local", "internal": false, "createdAt": "..." }]
}
```

- `available: false`: listas vacías, `reason` con el error recibido y `reasonCode` igual a `environment_not_on` o `docker_error`. La pantalla muestra las acciones deshabilitadas, con el motivo.
- Los contenedores de pods, con la etiqueta `io.kubernetes.pod.namespace`, no aparecen: tienen su propia pantalla.
- `composeProjects` aparece incluso con Docker apagado, con `state` igual a `unknown`. Valores de `state`: `running`, `exited`, `down` o `unknown`.
- `composeProject` existe en contenedores, volúmenes y redes. Viene de la etiqueta `com.docker.compose.project` del recurso e indica a qué proyecto Compose pertenece. Un recurso sin la etiqueta no tiene el campo (en el ejemplo, la red `bridge`).
- Los campos vacíos `health`, `composeProject`, `reason` y `reasonCode` se omiten.

### `kubernetes`

```json
{
  "available": true,
  "namespaces": [{ "name": "default", "status": "Active", "createdAt": "2026-11-16T21:00:00Z" }],
  "pods": [{ "namespace": "default", "name": "web-1", "status": "Running", "ready": "1/1", "restarts": 0, "ip": "10.42.0.9", "containers": ["web"], "createdAt": "..." }],
  "deployments": [{ "namespace": "default", "name": "web", "replicas": 2, "ready": 2, "updated": 2, "available": 2, "createdAt": "..." }],
  "services": [{ "namespace": "default", "name": "web", "type": "NodePort", "clusterIP": "10.43.0.5", "ports": ["80:30080/TCP"], "createdAt": "..." }]
}
```

`available: false`: listas vacías, `reason` con el error recibido y `reasonCode` igual a `kubernetes_unavailable`, sin un clúster accesible en el contexto actual del kubeconfig o en `CONSOLE_KUBE_CONTEXT`. La pantalla muestra el error y el tópico sigue intentando. El tópico no depende del tópico `environment`.

### `jobs`

`{ "jobs": [<Job>, ...] }`, del más nuevo al más antiguo.

## Logs

- `GET /ws/logs/containers/{id}`
- `GET /ws/logs/pods/{namespace}/{name}?container=<opcional>`

Solo del servidor al cliente:

- Trama **binaria**: bytes crudos de stdout y stderr, con ANSI, empezando por las últimas 500 líneas.
- Trama de texto: `end` o `error`, seguida del cierre.

El cliente no envía nada. Cerrar el WebSocket termina el proceso en el host.

## Terminal

- `GET /ws/terminal/containers/{id}?cols=80&rows=24`
- `GET /ws/terminal/pods/{namespace}/{name}?container=<opcional>&cols=80&rows=24`

`cols` y `rows` son opcionales, de 1 a 1000; el valor predeterminado es 80 por 24. Hasta 8 terminales simultáneas: por encima de eso, `error` con `too_many_terminals` y cierre 1013. El servicio intenta `bash` y recurre a `sh`; una imagen sin shell muestra el error en la propia terminal y termina con `exit`.

| Dirección | Trama | Contenido |
| --- | --- | --- |
| Cliente a servidor | Binaria | Teclas, en bytes |
| Cliente a servidor | Texto | `{ "type": "resize", "cols": 120, "rows": 40 }` |
| Servidor a cliente | Binaria | Salida del PTY |
| Servidor a cliente | Texto | `{ "type": "exit", "exitCode": 0 }` o `error`, seguido del cierre |

Un texto distinto de `resize`, o un tamaño fuera del límite, termina con `error` (`invalid_terminal_frame` o `invalid_terminal_size`) y cierre 1008. Cerrar el WebSocket termina el proceso en el host. El contenido de la terminal nunca va al log del servicio.

## Lo que el front-end debe respetar

- Enviar `Content-Type: application/json` en todo POST, incluso con cuerpo vacío. Sin él la respuesta es 403.
- `vite.config.ts`: `build.outDir` igual a `../internal/webui/dist`, `build.emptyOutDir` igual a `false` (el `Makefile` limpia la carpeta conservando `placeholder.html`) y `build.assetsInlineLimit` igual a `0`, porque la CSP rechaza `data:`.
- CSP: `default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; connect-src 'self' ws://127.0.0.1:<puerto> ws://localhost:<puerto>; frame-ancestors 'none'; base-uri 'none'; form-action 'none'`. Sin script inline, recurso externo ni `<form action>`. Use `onSubmit` con `preventDefault`.
- Rutas de la pantalla por hash. El servicio solo entrega archivos de `dist/`, y `/assets/` tiene caché larga.
- `package.json` necesita los scripts `build` y `check`, que llama el `Makefile`.
- xterm: en los logs, active `convertEol`, porque la salida solo tiene `\n`, y `disableStdin`. En la terminal, envíe cada entrada en tramas de hasta 64 KiB, también al pegar: por encima de eso el servidor cierra con 1009.
- Después de una acción, espere el snapshot en lugar de cambiar la fila por su cuenta. Una falla aparece por el `error` del job, y la fila sigue mostrando el estado real.
