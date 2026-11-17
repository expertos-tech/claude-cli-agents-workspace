<!-- source: workspace/tools/container-console-docker-ce/docs/operations.md sha256:50c3b74822fa515306ba895949da38ee8c4a27312073935b0b7bc3966bd7ee98 -->

# Operación de `container-console-docker-ce`

- [Instalar, actualizar y eliminar](#instalar-actualizar-y-eliminar)
- [La unit y el acceso directo](#la-unit-y-el-acceso-directo)
- [Configuración](#configuración)
- [Archivos y logs](#archivos-y-logs)
- [Monitoreo](#monitoreo)
- [Fallas comunes](#fallas-comunes)

Guía para quien opera la herramienta, que es la misma persona que la usa. Herramienta local: sin nube, sin servidor, sin costo de infraestructura. Sin alertas.

## Instalar, actualizar y eliminar

| Tarea | Comando, en la carpeta `tools/container-console-docker-ce` |
| --- | --- |
| Instalar o actualizar la consola | `make install`, con Node 24 en el `PATH` (repetirlo es seguro) |
| Solo compilar, sin instalar | `make build` y `.data/bin/container-console-docker-ce` |
| Verificar la compilación | `make check` |
| Eliminar la consola | `bash linux/uninstall-console.sh` |

El instalador se niega a sobrescribir una unit o un acceso directo con el mismo nombre que él no escribió, reconocidos por el comentario `Installed by container-console-docker-ce`. El desinstalador deshace solo lo que escribió el instalador y no toca Docker, los contenedores, el log, la lista de proyectos Compose ni `~/.config/container-console-docker-ce/env`.

## La unit y el acceso directo

| Pieza | Cuándo se ejecuta | Qué hace |
| --- | --- | --- |
| `container-console-docker-ce.service` (`systemd --user`) | Desde el inicio de la sesión gráfica en adelante (`WantedBy=graphical-session.target`, `Restart=on-failure`) | Mantiene el servicio en `127.0.0.1:27850`. Si el proceso falla, systemd lo vuelve a arrancar |
| `container-console-docker-ce.desktop` | Al hacer clic en el acceso directo | Ejecuta `systemctl --user start container-console-docker-ce.service` y abre la dirección con `xdg-open` |

- La unit parte de la sesión gráfica porque el diálogo de archivo necesita `DISPLAY` o `WAYLAND_DISPLAY`, que la sesión exporta al gestor del usuario.
- `KillMode=process`: reiniciar el servicio no envía señales a las CLIs en curso. El registro del job se pierde, y una CLI que todavía escriba salida puede terminar con el pipe cerrado. Después de reiniciar, compruebe el estado real en la lista.
- Docker no depende de la consola: `dockerd` arranca con el sistema, y Grafana vuelve solo con él, por la política `restart: unless-stopped` de `tools/observability`.

## Configuración

El servicio lee variables `CONSOLE_*` al iniciar. Un valor inválido impide el inicio y se lista en la salida de error. Todas tienen un valor predeterminado; la instalación no define ninguna.

Para probar una variable, detenga la unit con `systemctl --user stop container-console-docker-ce.service` y ejecute el binario a mano (`CONSOLE_MAX_TERMINALS=2 .data/bin/container-console-docker-ce`). Para fijar una variable, escriba `VARIABLE=valor`, una por línea, en `~/.config/container-console-docker-ce/env`, y ejecute `systemctl --user restart container-console-docker-ce.service`.

Red, contexto y rutas:

| Variable | Predeterminado | Nota |
| --- | --- | --- |
| `CONSOLE_LISTEN` | `127.0.0.1:27850` | El host solo puede ser `127.0.0.1`; otra dirección impide el inicio |
| `CONSOLE_DOCKER_HOST` | `unix:///var/run/docker.sock` | Debe empezar con `unix://` |
| `CONSOLE_KUBE_CONTEXT` | Vacío | Vacío no pasa `--context`, y vale el contexto actual del kubeconfig |
| `CONSOLE_STATE_DIR` | `$XDG_STATE_HOME/container-console-docker-ce`, o `~/.local/state/container-console-docker-ce` | Lista de proyectos Compose |
| `CONSOLE_LOG_FILE` | `console.log` en `CONSOLE_STATE_DIR` | Se trunca en cada inicio |
| `CONSOLE_PATH_PREPEND` | Vacío | Carpetas que van delante del `PATH` heredado |
| `CONSOLE_DOCKER_BIN`, `CONSOLE_KUBECTL_BIN`, `CONSOLE_ZENITY_BIN` | Nombre simple (`docker`, `kubectl`, `zenity`) | Nombre simple o ruta absoluta |

Plazos (una duración, como `90s` o `5m`):

| Variable | Predeterminado |
| --- | --- |
| `CONSOLE_TIMEOUT_READ` | `5s` (consultas) |
| `CONSOLE_TIMEOUT_DOCKER_ACTION` | `90s` |
| `CONSOLE_TIMEOUT_DOCKER_PULL` | `30m` |
| `CONSOLE_TIMEOUT_COMPOSE_ACTION` | `15m` |
| `CONSOLE_TIMEOUT_KUBE_ACTION` | `2m` |
| `CONSOLE_TIMEOUT_FILE_PICKER` | `5m` |
| `CONSOLE_TIMEOUT_PROCESS_WAIT` | `5s` |
| `CONSOLE_TIMEOUT_HTTP_HEADER` | `5s` |
| `CONSOLE_TIMEOUT_HTTP_READ` | `30s` |
| `CONSOLE_TIMEOUT_HTTP_IDLE` | `60s` |
| `CONSOLE_TIMEOUT_WS_WRITE` | `5s` |
| `CONSOLE_TIMEOUT_SHUTDOWN` | `10s` |

Ritmo de los tópicos en vivo y límites:

| Variable | Predeterminado |
| --- | --- |
| `CONSOLE_INTERVAL_ENVIRONMENT`, `CONSOLE_INTERVAL_KUBERNETES` | `1s` |
| `CONSOLE_INTERVAL_DOCKER_SYNC` | `5s` |
| `CONSOLE_INTERVAL_DOCKER_DEBOUNCE` | `150ms` |
| `CONSOLE_INTERVAL_EVENTS_RETRY` | `2s` |
| `CONSOLE_MAX_BODY_BYTES` | `1048576` (1 MiB) |
| `CONSOLE_MAX_HEADER_BYTES` | `65536` |
| `CONSOLE_WS_READ_BYTES` | `65536` |
| `CONSOLE_MAX_TERMINALS` | `8` |
| `CONSOLE_JOBS_KEPT` | `50` |
| `CONSOLE_JOB_OUTPUT_LINES` | `200` |
| `CONSOLE_REPLICAS_MAXIMUM` | `1000` |

## Archivos y logs

| Qué | Dónde |
| --- | --- |
| Log del servicio (JSON, sin contenido de terminal ni logs de contenedores) | `~/.local/state/container-console-docker-ce/console.log` |
| Errores de inicio del servicio, como un puerto ocupado | `journalctl --user -u container-console-docker-ce.service` |
| Binario instalado | `~/.local/bin/container-console-docker-ce` |
| Proyectos Compose conocidos (nombre y ruta) | `~/.local/state/container-console-docker-ce/compose-projects.json` |
| Unit | `~/.config/systemd/user/container-console-docker-ce.service` |
| Variables opcionales | `~/.config/container-console-docker-ce/env` |
| Acceso directo | `~/.local/share/applications/container-console-docker-ce.desktop` |
| Ícono, copia sin cambios de `web/public/favicon.png` | `~/.local/share/container-console-docker-ce/favicon.png` |
| Datos de Grafana | `tools/observability/.data/` (bind mount) |

## Monitoreo

- Salud del servicio: `curl -s http://127.0.0.1:27850/healthz` devuelve `{"status":"ok"}`.
- Unit: `systemctl --user status container-console-docker-ce.service`.
- Docker: `systemctl status docker` y `docker info`.
- Kubernetes: `kubectl config current-context` y `kubectl get --raw /version`.
- Grafana: <http://localhost:3000>.

## Fallas comunes

| Síntoma | Causa probable | Qué hacer |
| --- | --- | --- |
| El acceso directo abre el navegador, pero la página no carga | La unit no arrancó: puerto ocupado o error al iniciar | Lea `journalctl --user -u container-console-docker-ce.service`. Si la unit no existe, ejecute `make install` |
| La pantalla muestra el entorno como apagado | `dockerd` no responde en el socket | Ejecute `sudo systemctl start docker`. La consola nunca ejecuta ese comando, porque requiere root |
| La pantalla muestra el entorno como desconocido, con `permission denied` | El usuario no está en el grupo `docker`, o la sesión es anterior a su ingreso en él | `sudo usermod -aG docker $USER` y vuelva a iniciar sesión |
| La pantalla muestra el entorno como desconocido, con un binario ausente como motivo | `docker` no está en el `PATH` de la unit | Ajuste `CONSOLE_PATH_PREPEND` o `CONSOLE_DOCKER_BIN` |
| Acciones de Docker no disponibles con Docker encendido | Un socket distinto del configurado | Compruebe `CONSOLE_DOCKER_HOST` y la salida de `docker context ls` |
| Docker vuelve solo después de `sudo systemctl stop docker` | `docker.socket` sigue activo, y la lectura de `docker info` de la consola reactiva el daemon | Para mantenerlo detenido: `sudo systemctl stop docker.socket docker.service` |
| Kubernetes no disponible | Ningún clúster responde en el contexto usado | Compruebe `kubectl config current-context` y `CONSOLE_KUBE_CONTEXT`. La pantalla muestra el error y sigue intentando |
| `kubectl` dice que el contexto no existe | `CONSOLE_KUBE_CONTEXT` apunta a un nombre fuera del kubeconfig, o la unit lee otro kubeconfig | `kubectl config get-contexts`. Un `KUBECONFIG` no predeterminado va en `~/.config/container-console-docker-ce/env` |
| "Choose file" falla con `Failed to open display` | La unit arrancó sin las variables de la sesión gráfica | En una terminal de la sesión: `systemctl --user import-environment DISPLAY WAYLAND_DISPLAY` y `systemctl --user restart container-console-docker-ce.service`. El campo de ruta sigue funcionando |
| "Choose file" falla con un binario ausente | `zenity` no está instalado | Instale el paquete `zenity` o ajuste `CONSOLE_ZENITY_BIN`. El campo de ruta sigue funcionando |
| `docker pull` falla con `docker-credential-*: executable file not found` | `credsStore` en `~/.docker/config.json` apunta a un programa que no existe en esta máquina | Quite la clave o apúntela a un auxiliar instalado |
| Puerto 3000, 4317 o 4318 ocupado al arrancar Grafana | Otra stack usa el puerto | Detenga la otra stack |
| El acceso directo no aparece en el menú después de `make install` | El menú todavía no leyó la carpeta de accesos directos | `update-desktop-database ~/.local/share/applications` y, si persiste, vuelva a iniciar sesión |
