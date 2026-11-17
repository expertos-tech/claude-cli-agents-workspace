# azurite-console

- [What it is](#what-it-is)
- [How to run](#how-to-run)
- [How it works](#how-it-works)
- [The page](#the-page)
- [API](#api)
- [Layout](#layout)
- [How to test](#how-to-test)
- [Dependencies](#dependencies)

## What it is

A page to see and operate a local Azurite: containers and blobs, queues and messages, tables and entities, and the container's access log. It shows what the services wrote (files, JSON documents, queue messages) and lets you delete, resend, move and edit without `az storage` or `docker logs`.

A small Go program on top of the Azure SDK, with a React page and no UI library, that operates the three Azurite services safely: only the local account, confirmation before deleting, ETag and message receipt honored.

## How to run

Everything from the workspace root. `compose.yaml` starts Azurite and the console, with the project name `azurite-console`. The account key comes from `AZURITE_ACCOUNT_KEY`, in the environment or in `custom/env/azurite-console.env`, the filled copy of this folder's `.env.example` in the custom layer (git-ignored there, mode 600), which compose reads with `--env-file`. No `.env` is written in this folder. The key is yours: Azurite uses the same key through `AZURITE_ACCOUNTS`. Compose refuses to start without it. `DOCKER_SOCKET_GID` is the group that owns the Docker socket, for the access log panel; without it, the container joins group 0, and the panel says why when it cannot read.

Once, create the file and fill both values without printing them (`/local-env tools/azurite-console` in a session creates it with empty values for you to fill in an editor):

```bash
mkdir -p custom/env && chmod 700 custom/env
(umask 077; printf 'AZURITE_ACCOUNT_KEY=%s\nDOCKER_SOCKET_GID=%s\n' "$(openssl rand -base64 48)" "$(stat -c %g /var/run/docker.sock)" > custom/env/azurite-console.env)
docker compose --env-file custom/env/azurite-console.env -f tools/azurite-console/compose.yaml up -d --build --wait
```

Open `http://127.0.0.1:28091`. The image builds the page and compiles the program; after changing the code, run the same `up -d --build --wait` again. To stop and delete this project's data, `docker compose --env-file custom/env/azurite-console.env -f tools/azurite-console/compose.yaml down -v`.

Ports, all only on `127.0.0.1`:

| Service | Host | Container |
| --- | --- | --- |
| `azurite-console` | 28091 | 28091 |
| `azurite`, Blob | 30000 | 10000 |
| `azurite`, Queue | 30001 | 10001 |
| `azurite`, Table | 30002 | 10002 |

Azurite starts with `--skipApiVersionCheck`, because the Blob SDK of `go.mod` sends an API version newer than the one the image's Azurite knows, which would refuse every call with `400 InvalidHeaderValue`.

Outside Compose, to develop the program, keep only Azurite up, because the console service and `go run` use the same port 28091. The default of `-azurite-port` is already port 30000 published by Compose:

```bash
docker compose --env-file ../../custom/env/azurite-console.env stop azurite-console
npm --prefix web ci
npm --prefix web run build
go run . -env-file ../../custom/env/azurite-console.env
```

This runs from this folder. `npm` writes only `web/node_modules/` and `web/dist/`, the writable output folders of an installed workspace.

Flags:

| Flag | Default | What it does |
| --- | --- | --- |
| `-addr` | `127.0.0.1:28091` | Server address; only loopback is accepted, unless `-container` |
| `-host` | `127.0.0.1` | Azurite host; only loopback, `localhost` or `azurite` |
| `-azurite-port` | `30000` | First of Azurite's three consecutive ports: Blob, Queue and Table. For an Azurite on the default ports, `-azurite-port 10000` |
| `-web` | `web/dist` | Folder of the built page |
| `-env-file` | none | `KEY=VALUE` file read for `AZURITE_ACCOUNT_KEY` when the environment lacks it: `../../custom/env/azurite-console.env`. No folder is searched for a `.env` |
| `-max-upload` | 64 MiB | Largest request body, uploads included |
| `-container` | off | Accepts any listen address; used only in Compose, which publishes the port only on `127.0.0.1` |
| `-healthcheck` | off | Calls `/healthz` of the instance at `-addr` and exits with 0 if it answers; it is the container's healthcheck, since the container has no shell |

In Compose, the image runs with `-container -addr :28091 -host azurite -azurite-port 10000 -web /web`. Outside it, the key comes from `AZURITE_ACCOUNT_KEY` in the environment or, if missing, from the file of `-env-file`. Without the build, `/` shows the build commands, and the API works the same way.

To work on the page with automatic reload, `npm --prefix web run dev`: the page opens at `http://127.0.0.1:25174`, and `/api` goes to port 28091, whether the Compose service or `go run`.

## How it works

```text
browser --/api/...-->  azurite-console (Go, 127.0.0.1:28091)  --azblob/azqueue/aztables-->  Azurite (in Compose, azurite:10000-10002; outside it, 127.0.0.1:30000-30002)
                              |--docker logs (read only)-->  azurite container
```

- **Only the local Azurite.** The program builds the connection string with the `devstoreaccount1` account, the host of `-host` and the key; no flag accepts another connection string. Outside Compose the server listens only on loopback; in Compose it listens on every interface of the container, and the port is published only on `127.0.0.1`. The key is never shown.
- **Docker socket.** In Compose, the container mounts `/var/run/docker.sock` and joins the `DOCKER_SOCKET_GID` group, owner of the socket, so that the `docker` CLI reads the `azurite` log. The socket gives access to the whole Docker API; the program only reads (container list, inspect and logs).
- **The browser talks only to the program.** The signing of the Storage calls stays in Go; the page holds no credential.
- **Errors.** Every failure is a problem document, in English by default and in Brazilian Portuguese with `Accept-Language: pt-BR`. When Azurite answers, `detail` carries its status and code (for example `409 ContainerAlreadyExists`). The codes: `console.not_found` (404), `console.conflict` (409), `console.precondition` (412, including an expired message receipt, which Azurite answers as `400 PopReceiptMismatch`), `console.bad_request` (400), `console.unavailable` (503, Azurite down; the connection gives up after 3 s) and `console.entity_invalid` (400).
- **Safe preview.** The content of a blob is served as it is only for PDF, JSON, text, CSV and PNG, JPEG, GIF and WebP images; any other type (HTML, SVG) goes as text, with `X-Content-Type-Options: nosniff`, so it never runs as a page of the console.
- **Access log.** The container is found by the label `com.docker.compose.service=azurite` and read with `docker logs --tail N --timestamps`. Each line becomes time, caller, service, method, decoded resource, status and size. The caller is the Compose service that owns the IP; the network gateway shows as `host` (a program on the machine). The console's own calls show as `azurite-console` in Compose and as `host` with `go run`. The service comes from the shape of the request and from the queue and table names; a call on the account itself, such as listing containers or queues, shows as `account`. Without Docker or without the container, the panel says why and the rest of the page goes on.
- **Operations.** The actions that change something (create, delete, send, receive, save) stay in an in-memory list with the last 200: time, action, target, status, duration and error code.
- **Logs and shutdown.** JSON logs on standard output. On SIGINT or SIGTERM, the server stops accepting requests and waits up to 8 s for the ones in flight.

## The page

A page with four tabs. The tab and the selection live in the URL hash (`#/blobs/events/2026/11/16/`, `#/queues/<queue>`, `#/tables/<table>`), so a reload keeps the place. The top bar shows Blob, Queue and Table up or down, with the latency, and refreshes every 5 seconds (it can be turned off).

| Tab | What it shows and does |
| --- | --- |
| Overview | Counters of each service (containers, blobs and size; queues and messages; tables and entities, with the counts stopping at 10,000 per container and per table) and the Azurite version; the resources with a link to their tab; the log errors grouped by service, resource and status, without the 404 and 409 that are part of normal work; the access log with filters by service, caller, errors only and text; the operations of this page |
| Blobs | Containers (create, delete, empty); folder navigation with a breadcrumb, prefix filter and "load more"; blob detail with properties, metadata and preview (formatted JSON, text up to 256 KB, PDF, image); download; upload of several files to the current folder; deletion of the selected ones and of a whole folder, with the count and size before the confirmation |
| Queues | Queues with the approximate count (create, delete, clear); peek up to 32 messages without taking them from the queue, with formatted JSON, an option to decode base64 and a highlight for messages received 5 times or more; receive with a visibility timeout and, for each one received, delete, return, edit the text or move to another queue, with the countdown until it comes back; send with a JSON check, delay and TTL |
| Tables | Tables (create, delete); query with an OData filter, page size and navigation by continuation; grid with one column per property; entity editor in JSON with the `@odata.type` annotations, save as merge or replace with the ETag read (a conflict offers a reload), insert, duplicate and delete; text properties that hold JSON are shown formatted; deletion of the selected ones or of everything the filter returns, with the count first; export the page as JSON |

Deleting or emptying a container, deleting or clearing a queue, deleting a table and deleting all entities ask you to type the name.

## API

| Group | Routes |
| --- | --- |
| General | `GET /api/overview`, `GET /api/activity?tail=` (1 to 5000), `GET /api/operations` |
| Blob | `GET`/`POST /api/containers`, `DELETE /api/containers/{c}`, `POST /api/containers/{c}/empty`, `GET /api/containers/{c}/list?prefix=&marker=`, `GET /api/containers/{c}/usage?prefix=`, `DELETE /api/containers/{c}/prefix?prefix=`, `GET`/`PUT`/`DELETE /api/containers/{c}/blobs/{path}` (`GET` with `?props`, `?download` or `?max=`) |
| Queue | `GET`/`POST /api/queues`, `DELETE /api/queues/{q}`, `POST /api/queues/{q}/clear`, `GET /api/queues/{q}/peek?n=`, `POST /api/queues/{q}/receive`, `POST /api/queues/{q}/messages`, `PUT`/`DELETE /api/queues/{q}/messages/{id}`, `POST /api/queues/{q}/messages/{id}/move` |
| Table | `GET`/`POST /api/tables`, `DELETE /api/tables/{t}`, `GET /api/tables/{t}/entities?filter=&top=&next_pk=&next_rk=`, `GET /api/tables/{t}/entity?pk=&rk=`, `POST`/`PUT`/`DELETE /api/tables/{t}/entities`, `POST /api/tables/{t}/delete-by-filter` (with `dry_run` to only count) |

## Layout

```text
main.go               flags, server with graceful shutdown, loopback rule, connection deadline and healthcheck
compose.yaml          Azurite and the console, with the ports only on 127.0.0.1
Dockerfile            console image: page built with Node, program with Go, docker CLI and distroless nonroot
internal/azurite      local account: key (environment or .env), connection string, local host rule, ports and the three clients
internal/storage      Blob, Queue and Table operations in its own types; classification of Azurite errors
internal/activity     reading of the container log through the docker CLI, access log parser, caller by Compose IP, in-memory operations
internal/httpjson     JSON responses, problem documents and message catalog, standard library only
internal/api          /api/ routes, console messages (locales en and pt-BR), page from web/dist
web/                  React page (Vite and TypeScript), own CSS, no UI library or router
```

## How to test

```bash
go test ./...
npm --prefix web run build
```

The Go tests run with no network: the local account (accepted and refused hosts and ports, connection string, key lookup in the file of `-env-file`, never in a `.env` up the folders), the error classification and the entity cleanup before saving, the log parser with real lines of the container, the caller by IP and the routes with fakes (Azurite status and code in the problem, problem language, wrong method, Azurite down, ETag and mode, validations, count before deleting, a preview that never serves HTML, overview with one service down, page without a build). The page build checks the types with `tsc`.

Without Go or Node on the host, run them in containers, as your own user, so they write only where you can (in an installed workspace, `web/node_modules/` and `web/dist/`):

```bash
docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp -v "$PWD":/src:ro -w /src golang:1.27.3-trixie go test ./...
docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp -v "$PWD/web":/app -w /app node:24.21.0-bookworm-slim sh -c 'npm ci && npm run build'
```

With the Azurite of `compose.yaml` up, `AZURITE_CONSOLE_IT=1 AZURITE_CONSOLE_ENV_FILE=../../custom/env/azurite-console.env go test ./internal/storage/` also runs the tests against ports 30000 to 30002, which create `it-console-*` resources (tables `itconsole*`) and delete them at the end. The key is the same as Compose's: in the environment or in the file of `AZURITE_CONSOLE_ENV_FILE`.

## Dependencies

- The Azure SDK for Go: `azblob`, `azqueue`, `aztables` and `azcore`. The rest of the program uses only the standard library.
- The image `mcr.microsoft.com/azure-storage/azurite:3.37.0`, pinned by tag and digest in `compose.yaml`.
- The `docker` CLI, only for the access log: in `PATH` with `go run`; in the image, copied from `docker:29.9.1-cli`.
- In the page: React and React DOM, with Vite, `@vitejs/plugin-react` and TypeScript in the build.
