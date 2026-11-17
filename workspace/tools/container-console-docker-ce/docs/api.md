# `container-console-docker-ce` API contract

- [Conventions](#conventions)
- [Errors](#errors)
- [Jobs](#jobs)
- [REST routes](#rest-routes)
- [WebSocket: common rules](#websocket-common-rules)
- [Live topics](#live-topics)
- [Logs](#logs)
- [Terminal](#terminal)
- [What the front-end must respect](#what-the-front-end-must-respect)

Reference for whoever writes the screen. Source of the routes: `internal/httpapi/`.

## Conventions

- Base: `http://127.0.0.1:27850` or `http://localhost:27850`. Use relative URLs and build the WebSocket URL from `location.host`.
- No login. Access is protected by `Host` and `Origin`, described below.
- Every body and every response is JSON with `camelCase` fields. Job times: RFC 3339 in UTC.
- GET never changes state. Every mutation becomes a [job](#jobs) and does not hold the HTTP request. The two exceptions are marked in the Compose routes.
- Lists have no REST route: they arrive through the [topics](#live-topics). REST is only for details and commands.

Rules applied to every route, in this order:

| Rule | Refusal |
| --- | --- |
| `Host` exactly equal to `127.0.0.1:<port>` or `localhost:<port>` | 403 `forbidden` |
| `http.CrossOriginProtection`: `Sec-Fetch-Site` or `Origin` of another site on a state-changing method | 403 `forbidden` |
| POST with `Content-Type: application/json`, **even without a body** | 403 `forbidden` |
| Body of up to 1 MiB | 413 `body_too_large` |
| Unknown field, malformed JSON or data after the JSON | 422 `invalid_body` |

Every security refusal looks the same, on purpose: the reason only goes to the service log. An empty body equals `{}`, so a missing `confirm` is `false`.

Accepted formats:

| Value | Format |
| --- | --- |
| Container, volume and network id or name | `^[a-zA-Z0-9][a-zA-Z0-9_.-]*$`, up to 255 characters |
| Image reference | `^[a-zA-Z0-9][a-zA-Z0-9._:/@-]*$`, up to 512 characters |
| Compose project | `^[a-z0-9][a-z0-9_-]*$` |
| Compose path | Absolute, without `..`, `.yaml` or `.yml`, a regular file inside `$HOME`, checked after resolving links |
| Namespace and service | DNS-1123 label |
| Pod and deployment | DNS-1123 subdomain |

Headers of every response: `Content-Security-Policy`, `X-Content-Type-Options: nosniff`, `Referrer-Policy: no-referrer` and `Cross-Origin-Resource-Policy: same-origin`.

## Errors

A single shape in REST:

```json
{ "error": { "code": "environment_not_on", "message": "the docker daemon is not on", "params": { "state": "off" } } }
```

- `code`: stable, it is the key of the translation dictionary.
- `message`: technical, in English. When the error comes from a CLI, it is the stderr received, which the screen shows untranslated.
- `params`: named values for the translated sentence, when there are any.
- `exitCode`: exit code of the CLI, when there is one.

| Status | Meaning | Codes |
| --- | --- | --- |
| 403 | Security refusal, see [Conventions](#conventions) | `forbidden` |
| 404 | Target does not exist | `container_not_found`, `volume_not_found`, `network_not_found`, `kubernetes_resource_not_found`, `kubernetes_kind_unknown`, `compose_project_not_found`, `job_not_found`, `route_not_found` |
| 409 | The current state refuses the action | `environment_not_on` (with `params.state`), `kubernetes_unavailable` (with the `kubectl` error in `message`), `file_picker_busy`, `compose_files_unknown` |
| 413 | Body above the limit | `body_too_large` |
| 422 | Input refused; nothing ran | `invalid_body`, `confirmation_required`, `invalid_docker_name`, `invalid_image_reference`, `invalid_compose_project`, `compose_path_invalid`, `compose_file_invalid`, `invalid_kubernetes_name`, `replicas_required`, `replicas_out_of_range` (`params.max`), `yaml_empty` |
| 502 | The CLI failed on a query | `command_failed`, `command_timeout`, `binary_not_found`, `action_failed` |

A route with the wrong method gets Go's default 405, as text.

Codes that exist only on the WebSocket. They arrive in an `error` frame after the upgrade (see [WebSocket: common rules](#websocket-common-rules)), with the same `code`, `message` and `params` shape, and the error class in parentheses:

| Code | When | Close |
| --- | --- | --- |
| `topic_not_found` (not found) | `/ws/live/{topic}` with a topic that does not exist | 1000 |
| `too_many_terminals` (conflict, `params.max`) | A new terminal past the limit of simultaneous terminals | 1013 |
| `invalid_terminal_size` (invalid input) | `cols` or `rows` in the URL, or in a `resize` frame, outside 1 to 1000 | 1000 in the URL; 1008 in the frame |
| `invalid_terminal_frame` (invalid input) | A text frame that is not `resize` | 1008 |

The REST errors (`environment_not_on`, `container_not_found` and the others in the table above) can also arrive in an `error` frame, for example when opening logs or a terminal with Docker off.

## Jobs

Flow of every mutation:

1. The screen sends the POST.
2. The service validates format, confirmation and state. A failure here returns an error and nothing runs.
3. The service returns `202` with `{ "job": <Job> }` in the `running` state.
4. The `jobs` topic carries each change: new output lines and the end.
5. When it ends, `environment`, `docker` and `kubernetes` are refreshed at once. The row on the screen only changes with that snapshot, never optimistically.

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

- `status`: `running`, `succeeded` or `failed`. `error` and `finishedAt` only appear when they apply.
- `output`: last 200 lines. The service keeps in memory the running jobs and the last 50 finished ones, and loses everything on restart.
- `error.code`: `command_failed`, `command_timeout`, `binary_not_found` or the domain code. `error.message` is the error received, to be shown as it came.

| `kind` | `target` |
| --- | --- |
| `container.start`, `container.stop`, `container.restart`, `container.remove` | Id or name |
| `image.pull`, `image.remove` | Reference |
| `volume.create`, `volume.remove`, `network.create`, `network.remove` | Id or name |
| `compose.up`, `compose.stop`, `compose.remove` | Project name |
| `kubernetes.remove`, `kubernetes.scale` | `<kind>/<namespace>/<name>`, or `namespaces/<name>` |
| `kubernetes.apply` | Empty |
| `docker.cleanup` | `volumes` when it includes volumes, empty without them |

## REST routes

`job` in the response column means `202 { "job": <Job> }`. Every removal requires `"confirm": true`, checked on the server. Without it: 422 `confirmation_required`.

### Service

| Route | Body | Response |
| --- | --- | --- |
| `GET /healthz` | None | `200 { "status": "ok" }` |
| `GET /api/jobs/{id}` | None | `200 { "job": <Job> }` |

### Environment

No REST route: the environment is read-only and arrives through the [`environment`](#environment) topic. Controlling docker-ce requires root, and the console never starts or stops the daemon.

### Containers

| Route | Body | Response |
| --- | --- | --- |
| `GET /api/containers/{id}` | None | `200` with the `docker inspect` object |
| `GET /api/containers/{id}/stats` | None | `200 { "cpuPercent", "memoryUsage", "memoryPercent", "networkIO", "blockIO", "pids" }`, as the CLI prints them |
| `POST /api/containers/{id}/start` | `{}` | job |
| `POST /api/containers/{id}/stop` | `{}` | job |
| `POST /api/containers/{id}/restart` | `{}` | job |
| `POST /api/containers/{id}/remove` | `{ "confirm": true }` | job. Uses `docker rm --force`, and the dialog must say so |

`stats` takes about 1 s. Query it every 2 s only while the details are open.

### Images

| Route | Body | Response |
| --- | --- | --- |
| `POST /api/images/pull` | `{ "reference": "alpine:3.20" }` | job, with the progress lines in `output` |
| `POST /api/images/remove` | `{ "reference": "<reference field from the list>", "confirm": true }` | job. Without `--force`: an image in use returns the error in the job |

The reference goes in the body because it contains `/`.

### Volumes and networks

| Route | Body | Response |
| --- | --- | --- |
| `POST /api/volumes` | `{ "name": "data" }` | job |
| `GET /api/volumes/{id}` | None | `200` with the `docker volume inspect` object |
| `POST /api/volumes/{id}/remove` | `{ "confirm": true }` | job |
| `POST /api/networks` | `{ "name": "my-network" }` | job |
| `GET /api/networks/{id}` | None | `200` with the `docker network inspect` object |
| `POST /api/networks/{id}/remove` | `{ "confirm": true }` | job |

Removals do not use `--force`: a resource in use returns the error in the job.

### Cleanup

| Route | Body | Response |
| --- | --- | --- |
| `GET /api/cleanup` | None | `200` with `{ containers, images, networks, volumes, buildCache }`: each list with `{ id, name, detail? }`, and `buildCache` as `docker system df` prints it |
| `POST /api/cleanup` | `{ "confirm": true, "volumes": false }` | `docker.cleanup` job |

An active container is `running`, `paused`, `restarting` or `removing`; a Kubernetes pod container counts as active. The summary lists the containers that are not active and the images, networks (except `bridge`, `host` and `none`) and volumes that no active container uses. The job runs, in order: `docker container prune --force --filter label!=io.kubernetes.pod.namespace`, `docker image prune --all --force`, `docker network prune --force`, `docker volume prune --all --force` (only with `"volumes": true`) and `docker builder prune --all --force`, each step with the `CONSOLE_TIMEOUT_DOCKER_PULL` deadline. Each step works on the state of the daemon when it runs.

### Compose

| Route | Body | Response |
| --- | --- | --- |
| `POST /api/compose/file-dialog` | `{}` | `200 { "path": "/home/.../compose.yaml", "canceled": false }`. Canceled: empty `path` and `canceled: true`. Not a job |
| `POST /api/compose/projects` | `{ "path": "<absolute path>" }` | `201 { "project": <Project> }`. Not a job, and it works with Docker off |
| `POST /api/compose/projects/{name}/up` | `{}` | job |
| `POST /api/compose/projects/{name}/stop` | `{}` | job |
| `POST /api/compose/projects/{name}/remove` | `{ "confirm": true, "removeVolumes": false }` | job. Runs `down`, with `--volumes` only when checked, and drops it from the list |

- `file-dialog` opens `zenity --file-selection` and only returns the path. A session without a display returns 502 `command_failed`, with the error received, not a cancel. To add the project, send it to `POST /api/compose/projects`. It stays open for up to 5 min; a second request gets 409 `file_picker_busy`. The screen also offers a path field, for when the dialog does not open.
- The project name comes from Compose itself. A file Compose refuses: 422 `compose_file_invalid`, with the error in `message`.
- The actions use the files the service knows, and the browser never sends a path in them. A project with a file outside `$HOME` gets 422 `compose_path_invalid`.

### Kubernetes

`{kind}` is `pods`, `deployments` or `services`. Without a reachable cluster, every route in this section gets 409 `kubernetes_unavailable`.

| Route | Body | Response |
| --- | --- | --- |
| `GET /api/kubernetes/namespaces/{name}` | None | `200` with the `kubectl get` JSON |
| `GET /api/kubernetes/{kind}/{namespace}/{name}` | None | `200` with the `kubectl get` JSON |
| `POST /api/kubernetes/namespaces/{name}/remove` | `{ "confirm": true }` | job |
| `POST /api/kubernetes/{kind}/{namespace}/{name}/remove` | `{ "confirm": true }` | job |
| `POST /api/kubernetes/deployments/{namespace}/{name}/scale` | `{ "replicas": 3 }`, from 0 to 1000 | job |
| `POST /api/kubernetes/apply` | `{ "yaml": "<text>" }` | job |

`apply` runs `kubectl apply --dry-run=server --validate=strict -f -` and, only on success, `kubectl apply -f -`. Invalid YAML ends the job as `failed`, with the error in `error.message`, and nothing changes. Known limit: a file that creates a namespace and resources inside it is refused in the dry run; the guidance is to apply the namespace first.

## WebSocket: common rules

- `Origin` is required and must be exactly `http://127.0.0.1:<port>` or `http://localhost:<port>`. Wrong or missing: 403 before the upgrade. There is no exception for a development server.
- Everything that is not security is refused after the upgrade, with an error frame, because the browser does not read the body of a refused upgrade.
- Control frames are text, with JSON:

```json
{ "type": "error", "code": "environment_not_on", "message": "the environment is not on", "params": { "state": "off" } }
```

| `type` | Where | Meaning |
| --- | --- | --- |
| `snapshot` | Topics | Full snapshot, see [Live topics](#live-topics) |
| `error` | All | Same `code`, `message`, `exitCode` and `params` as REST. The connection closes right after |
| `end` | Logs | The stream ended normally |
| `exit` | Terminal | The process ended. Carries `exitCode` |

Close codes: 1000 normal, 1001 service shutting down, 1008 invalid client frame, 1009 frame above 64 KiB, 1013 terminal limit.

Each write has a 5 s deadline: a client that is too slow loses the connection. Compression off.

## Live topics

`GET /ws/live/{topic}`, with `topic` equal to `environment`, `docker`, `kubernetes` or `jobs`. A topic that does not exist: `error` frame with `topic_not_found`.

- Each frame is the full snapshot, with no diff: `{ "type": "snapshot", "topic": "docker", "data": { ... } }`.
- The first one arrives right after subscribing, and the next ones on every content change. A slow client skips intermediate ones.
- The client sends nothing: a received message closes the connection.
- Without subscribers, the topic watcher stops. The client reconnects on its own, waiting up to 2 s, and shows the banner while it reconnects.

| Topic | Fires on |
| --- | --- |
| `environment` | Every 1 s and at the end of a job. Each read runs `docker info` |
| `docker` | A relevant `docker events` event, with a 150 ms debounce; every 5 s; at the end of a job |
| `kubernetes` | Every 1 s and at the end of a job |
| `jobs` | Every job change |

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

- `state`: `on`, `off` or `unknown`. `off` means nothing answers on the socket. `unknown` means another failure, such as permission denied or a missing binary.
- `reason`, only when the state is not `on`: the error received.
- The other fields only exist in the `on` state. Memory in bytes.

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

- `available: false`: empty lists, `reason` with the error received and `reasonCode` equal to `environment_not_on` or `docker_error`. The screen shows the actions disabled, with the reason.
- Pod containers, with the `io.kubernetes.pod.namespace` label, do not appear: they have their own screen.
- `composeProjects` appears even with Docker off, with `state` equal to `unknown`. `state` values: `running`, `exited`, `down` or `unknown`.
- `composeProject` exists on containers, volumes and networks. It comes from the resource's `com.docker.compose.project` label and tells which Compose project it belongs to. A resource without the label has no such field (in the example, the `bridge` network).
- Empty `health`, `composeProject`, `reason` and `reasonCode` fields are omitted.

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

`available: false`: empty lists, `reason` with the error received and `reasonCode` equal to `kubernetes_unavailable`, with no reachable cluster in the current kubeconfig context or in `CONSOLE_KUBE_CONTEXT`. The screen shows the error and the topic keeps trying. The topic does not depend on the `environment` topic.

### `jobs`

`{ "jobs": [<Job>, ...] }`, newest first.

## Logs

- `GET /ws/logs/containers/{id}`
- `GET /ws/logs/pods/{namespace}/{name}?container=<optional>`

Server to client only:

- **Binary** frame: raw stdout and stderr bytes, with ANSI, starting with the last 500 lines.
- Text frame: `end` or `error`, followed by the close.

The client sends nothing. Closing the WebSocket ends the process on the host.

## Terminal

- `GET /ws/terminal/containers/{id}?cols=80&rows=24`
- `GET /ws/terminal/pods/{namespace}/{name}?container=<optional>&cols=80&rows=24`

`cols` and `rows` are optional, from 1 to 1000; the default is 80 by 24. Up to 8 simultaneous terminals: above that, `error` with `too_many_terminals` and close 1013. The service tries `bash` and falls back to `sh`; an image without a shell shows the error in the terminal itself and ends with `exit`.

| Direction | Frame | Content |
| --- | --- | --- |
| Client to server | Binary | Keys, as bytes |
| Client to server | Text | `{ "type": "resize", "cols": 120, "rows": 40 }` |
| Server to client | Binary | PTY output |
| Server to client | Text | `{ "type": "exit", "exitCode": 0 }` or `error`, followed by the close |

Text other than `resize`, or a size outside the limit, ends with `error` (`invalid_terminal_frame` or `invalid_terminal_size`) and close 1008. Closing the WebSocket ends the process on the host. The terminal content never goes to the service log.

## What the front-end must respect

- Send `Content-Type: application/json` on every POST, even with an empty body. Without it the response is 403.
- `vite.config.ts`: `build.outDir` equal to `../internal/webui/dist`, `build.emptyOutDir` equal to `false` (the `Makefile` clears the folder keeping `placeholder.html`) and `build.assetsInlineLimit` equal to `0`, because the CSP refuses `data:`.
- CSP: `default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; connect-src 'self' ws://127.0.0.1:<port> ws://localhost:<port>; frame-ancestors 'none'; base-uri 'none'; form-action 'none'`. No inline script, external resource or `<form action>`. Use `onSubmit` with `preventDefault`.
- Screen routes by hash. The service only serves files from `dist/`, and `/assets/` has a long cache.
- `package.json` needs the `build` and `check` scripts, called by the `Makefile`.
- xterm: in logs, enable `convertEol`, because the output has only `\n`, and `disableStdin`. In the terminal, send each input in frames of up to 64 KiB, including when pasting: above that the server closes with 1009.
- After an action, wait for the snapshot instead of changing the row on your own. A failure shows up through the job's `error`, and the row keeps showing the real state.
