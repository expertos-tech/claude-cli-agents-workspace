<!-- source: workspace/tools/README.md sha256:00dd8dc067c2bac16b1bb13fd18682f03d625c0fb16076389693887c49c017fd -->

# tools

Herramientas de soporte para entornos locales, parte del núcleo del workspace. Una carpeta por herramienta. Una herramienta con interfaz de usuario muestra la identidad del proyecto, Claude CLI Agents Workspace: el nombre y el logo o el ícono de `assets/` de la raíz, nunca la identidad de una empresa. En un workspace instalado esta carpeta es de solo lectura: tus propias herramientas viven en la capa custom, en `custom/tools/<name>/` (`bash scripts/init-repo.sh --type tool`), y las POCs en `custom/pocs/`. Una herramienta que admite configuración tiene un `.env.example` al lado; el archivo rellenado es `custom/env/<name>.env` (`/local-env tools/<name>`), que se pasa a compose con `--env-file`.

| Ítem | Tipo | Objetivo |
| --- | --- | --- |
| observability | herramienta | Grafana local y receptor OTLP para la telemetría de Claude Code y los dashboards de los proyectos |
| container-console-docker-ce | herramienta | Consola local en el navegador para observar docker-ce y gestionar contenedores, Compose y Kubernetes, abierta desde un atajo de GNOME |
| container-console-colima | herramienta | Gemela de container-console-docker-ce para macOS: consola local en el navegador para controlar Colima y gestionar contenedores, Compose y Kubernetes, abierta desde un ícono del Dock |
| claude-usage | herramienta | Informe local del uso de Claude Code por día, sesión y modelo, leído de los logs en `~/.claude/projects` |
| fable-alert | herramienta | Alerta visual (fondo de la terminal y banner) cuando la sesión de Claude Code corre en Fable, con una status line y un registrador de inicio |
| login-simulator | herramienta | Login local en lugar de Auth0: usuarios ficticios fijos, login con un clic, sin internet, siempre activo en Docker |
| azurite-console | herramienta | Página para ver y operar el Azurite local: blobs, colas, tablas y el log de acceso, con su propio compose |
| safe-browsing-simulator | herramienta | Google Safe Browsing local (Lookup v4): URLs peligrosas y una caída leídas de un archivo, sin internet y sin clave real |

## Puertos del host

Un puerto aparece una sola vez. Proyecto: el convencional cuando está libre, si no otro libre por debajo de 20000. Herramienta: el convencional; si no tiene, desde 20000 hacia arriba. POC y `docker/`: desde 20000 hacia arriba.

| Puerto | Dueño | Tipo | Uso |
| --- | --- | --- | --- |
| 3000 | `tools/observability` | herramienta | Grafana |
| 4317, 4318 | `tools/observability` | herramienta | OTLP gRPC y HTTP |
| 17850 | `tools/container-console-colima` | herramienta | servicio (`CONSOLE_LISTEN`); macOS, agente launchd |
| 27850 | `tools/container-console-docker-ce` | herramienta | servicio (`CONSOLE_LISTEN`); Linux y WSL, `systemd --user` |
| 28080 | `tools/login-simulator` | herramienta | simulador de login en lugar de Auth0; fotos generadas en `172.31.250.10:8080`, red `login-simulator` con la subred fija `172.31.250.0/24` |
| 25174 | `tools/azurite-console` | herramienta | Vite en desarrollo |
| 28090 | `tools/safe-browsing-simulator` | herramienta | simulador de Google Safe Browsing (Lookup v4); red `safe-browsing-simulator` |
| 28091 | `tools/azurite-console` | herramienta | consola |
| 29000 | `docker/sonar` | `docker/` | SonarQube |
| 30000–30002 | `tools/azurite-console` | herramienta | Azurite (blob, queue, table) |

Los puertos de los proyectos están en la capa custom, en `custom/projects.md`.
