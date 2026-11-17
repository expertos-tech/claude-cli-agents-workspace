<!-- source: workspace/tools/observability/README.md sha256:50445715b8204008e725a704879da77fe625fe0232028de397a4fe5fd3dea8f2 -->

# observability

- [Qué es](#qué-es)
- [Cómo ejecutarlo](#cómo-ejecutarlo)
- [Configurar Claude Code](#configurar-claude-code)
- [Cómo probarlo](#cómo-probarlo)
- [Cómo agregar dashboards](#cómo-agregar-dashboards)
- [Dashboard de Claude Code](#dashboard-de-claude-code)
- [Dónde quedan los datos](#dónde-quedan-los-datos)
- [Datos personales](#datos-personales)

## Qué es

El stack local de telemetría del workspace, con la imagen `grafana/otel-lgtm`: Grafana, Prometheus, Loki, Tempo y el receptor OTLP en un solo contenedor. Se ejecuta solo en la máquina local, sin login, accesible solo a través de `127.0.0.1`.

| Puerto | Uso |
| --- | --- |
| `3000` | Grafana: <http://localhost:3000> |
| `4317` | OTLP gRPC (la telemetría de Claude Code apunta aquí) |
| `4318` | OTLP HTTP |

## Cómo ejecutarlo

```bash
docker compose -f tools/observability/compose.yaml up -d
```

Para reiniciarlo a mano: `docker compose -f tools/observability/compose.yaml restart`.

Otro proyecto llega a `otel-lgtm:4317` a través de la red `observability`: con este stack ya en ejecución, su archivo compose declara `networks: {observability: {external: true}}` y cada servicio que envía telemetría lista `observability` en `networks`, junto con `default` si también se comunica con los demás servicios del proyecto.

Grafana sigue el tema del sistema operativo, incluso si cambia con la página abierta. Para fijar otro, usa Administration > General > Default preferences (`/org`), campo `Interface theme`: `System preference`, `Dark` o `Light`. La elección se aplica a toda la organización y queda en `.data/`. La paleta de comandos (`Search...` arriba, `Change theme`) solo ofrece `Dark` y `Light` y pierde la elección al recargar: el acceso es anónimo, sin perfil de usuario, y `/profile` redirige al login. Los colores fijos del dashboard tienen un contraste de al menos 3:1 en ambos temas.

La telemetría de Claude Code se configura en `~/.claude/settings.json`; las variables están en [Configurar Claude Code](#configurar-claude-code).

## Configurar Claude Code

El archivo `settings-telemetry.json` tiene el bloque `env` con las 11 variables que activan la telemetría y la apuntan a este stack:

| Variable | Valor | Qué hace |
| --- | --- | --- |
| `CLAUDE_CODE_ENABLE_TELEMETRY` | `1` | Activa la telemetría |
| `CLAUDE_CODE_ENHANCED_TELEMETRY_BETA` | `1` | Activa el tracing, que todavía está en beta |
| `OTEL_METRICS_EXPORTER` | `otlp` | Envía las métricas por OTLP |
| `OTEL_LOGS_EXPORTER` | `otlp` | Envía los eventos por OTLP |
| `OTEL_TRACES_EXPORTER` | `otlp` | Envía las trazas por OTLP |
| `OTEL_EXPORTER_OTLP_PROTOCOL` | `grpc` | Usa gRPC para las tres señales |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | `http://localhost:4317` | Dirección del receptor OTLP gRPC de este stack |
| `OTEL_RESOURCE_ATTRIBUTES` | `deployment.environment.name=dev` | Etiqueta todos los datos con el entorno |
| `OTEL_LOG_USER_PROMPTS` | `0` | No envía el texto del prompt; ya es el valor predeterminado, y el valor queda explícito |
| `OTEL_LOG_TOOL_DETAILS` | `1` | Envía los detalles de las herramientas: comandos Bash, nombres de servidores y herramientas MCP, nombres de skills, la entrada de cada herramienta y el texto completo del error. Queda activado porque conserva los nombres reales de agentes, skills, plugins y MCP en los contadores de costo y de tokens; sin él, esos nombres pasan a ser `custom` o `third-party` |
| `OTEL_EXPORTER_OTLP_METRICS_TEMPORALITY_PREFERENCE` | `cumulative` | Envía las métricas como contadores acumulativos |

No cambies `cumulative`: el valor predeterminado de Claude Code es `delta`, y Prometheus descarta las métricas `delta` sin aviso.

Para instalar, desde la raíz del workspace, haz una copia de seguridad de la configuración y fusiona el bloque con ella, sin borrar lo que existe:

```bash
cp ~/.claude/settings.json ~/.claude/settings.json.bak
jq -s '.[0] * .[1]' ~/.claude/settings.json.bak tools/observability/settings-telemetry.json > ~/.claude/settings.json
```

Las variables solo se aplican a las sesiones abiertas después del cambio.

El dashboard lee `ttft_ms` de los eventos `api_request` en Loki. La documentación oficial lista este campo solo en las trazas, pero los eventos `api_request` de Claude Code 2.1.309 también lo llevan.

### Comprobar que llegan los datos

Con el stack en ejecución y después de unos minutos de uso de Claude Code:

```bash
# Métricas en Prometheus
curl -s -G http://localhost:3000/api/datasources/proxy/uid/prometheus/api/v1/query \
  --data-urlencode 'query=sum by (model) (claude_code_token_usage_tokens_total)'

# Eventos en Loki
curl -s -G http://localhost:3000/api/datasources/proxy/uid/loki/loki/api/v1/query_range \
  --data-urlencode 'query={service_name="claude-code"} | event_name="api_request"' \
  --data-urlencode 'limit=5'
```

Si no llega nada, ejecuta una sesión con log de depuración, en una carpeta fuera del workspace, y busca las líneas de telemetría. El comando hace una llamada al modelo; borra `telemetry.log` después.

```bash
claude -p "answer only: ok" --debug-file telemetry.log
grep '\[3P telemetry\]' telemetry.log
```

### Desactivarla

```bash
cp ~/.claude/settings.json ~/.claude/settings.json.bak
jq '.env |= with_entries(select(.key | test("^(OTEL_|CLAUDE_CODE_ENABLE_TELEMETRY$|CLAUDE_CODE_ENHANCED_TELEMETRY_BETA$)") | not))' \
  ~/.claude/settings.json.bak > ~/.claude/settings.json
docker compose -f tools/observability/compose.yaml down
```

`down` no borra los datos (consulta [Dónde quedan los datos](#dónde-quedan-los-datos)).

### Límite de Cowork

Cowork no envía a este stack. Ejecuta el exportador dentro de su propia máquina virtual, y su telemetría solo se configura en la consola de administración de Anthropic, en los planes Team y Enterprise. La pestaña Code de la app de escritorio lee la misma configuración que la terminal y envía con normalidad.

## Cómo probarlo

```bash
bash tools/observability/tests/run-smoke.sh
```

Cada ejecución inicia su propio proyecto Compose (`observability-smoke-<pid>`), con su propia red, datos temporales en una carpeta dentro de `~`, proyectos ficticios y puertos libres de `127.0.0.1` elegidos por Docker, de modo que varias ejecuciones pueden ocurrir al mismo tiempo. Verifica los criterios a través de la API HTTP de Grafana, incluido que toda consulta del dashboard se acepta sin datos (`tests/check_dashboard_queries.py`) y lo que devuelven con telemetría ficticia de dos modelos (`tests/check_dashboard_behavior.py`), y elimina todo al final. Necesita `python3`. No toca el stack real, que puede estar en ejecución al mismo tiempo. Si falla, muestra las líneas de aprovisionamiento de Grafana y guarda el log completo en un archivo temporal. Usa `--verbose` para ver el progreso y los logs completos.

## Cómo agregar dashboards

| Dashboard de | Dónde poner el JSON | Carpeta en Grafana | Para que aparezca |
| --- | --- | --- | --- |
| Claude Code y el workspace | `dashboards/workspace/<name>.json` | `workspace` | En menos de 15 s, sin reiniciar |
| POC | `dashboards/workspace/<poc-name>.json` | `workspace` | En menos de 15 s, sin reiniciar |
| Proyecto | `projects/<name>/observability/dashboards/*.json` o `projects/<client>/<name>/observability/dashboards/*.json`, en el repositorio propio del proyecto | `<name>` | Primer JSON del proyecto: reinicia el contenedor. Después: en menos de 15 s, sin reiniciar |

- Ningún archivo de esta herramienta cambia al agregar un proyecto.
- Un proyecto sin `observability/dashboards/*.json` no crea ninguna carpeta en Grafana, y `<client>` nunca crea una. Una subcarpeta de un repositorio en `projects/<name>/` tampoco crea una: la primera carpeta con `.git` es siempre el proyecto. Los proyectos con el mismo `<name>` comparten la carpeta.
- Los dashboards son de solo lectura en Grafana: edita el JSON. Borrar el JSON borra el dashboard en menos de 15 s.
- Un proyecto eliminado pierde sus dashboards en el siguiente reinicio, pero su carpeta queda vacía en Grafana: bórrala a mano.
- Los dashboards incluidos en la imagen (RED Metrics y JVM) quedan fuera a propósito.

## Dashboard de Claude Code

El dashboard `Claude Code: usage` muestra costo, tokens, sesiones, herramientas, errores y latencia del período seleccionado, con un filtro por modelo. La descripción de cada panel dice qué mide y si el filtro se aplica.

Los colores de los modelos se repiten en cada panel que muestra modelos: para cambiar un color o agregar un modelo, edita `fieldConfig.overrides` de todos ellos en `dashboards/workspace/claude-code.json`; la prueba smoke falla si los mapas divergen.

Los totales vienen de los eventos `api_request` en Loki, porque cada evento tiene la hora exacta de la llamada. El contador de Prometheus no sirve para esto: `last_over_time` devuelve el total de toda la sesión, e `increase` pierde la primera muestra y extrapola.

Las líneas modificadas, los commits y el tiempo activo usan el contador, con un delta por sesión: el último valor del período menos el último anterior a él, con una sesión nueva que empieza en 0. Son aproximados (`approx.` en el título): subestiman una sesión reanudada, porque el contador se reinicia. El filtro de modelo se aplica a las líneas modificadas, pero no a los commits, el tiempo activo, los prompts ni las herramientas (`all models` en el título).

La lista de modelos del filtro es aproximada y viene de Prometheus, porque Grafana no lista como valor de variable un campo de evento que no es una etiqueta indexada en Loki. Muestra los modelos con un aumento en el contador o con un contador nuevo en el período, y el uso de los últimos 60 segundos puede no aparecer todavía.

## Dónde quedan los datos

En `tools/observability/.data/`, ignorado por git y por las verificaciones de `scripts/validate.sh`. Es un bind mount: `docker compose down -v` no borra los datos. Para reiniciar el stack desde cero, borra esta carpeta con el contenedor detenido.

| Señal | Retención | Origen |
| --- | --- | --- |
| Métricas (Prometheus) | 365 días | `PROMETHEUS_EXTRA_ARGS` en `compose.yaml` (predeterminado de la imagen: 15 días) |
| Trazas (Tempo) | 365 días | `TEMPO_EXTRA_ARGS` en `compose.yaml` (predeterminado de la imagen: 14 días) |
| Logs (Loki) | Sin límite | Predeterminado de la imagen; `LOKI_EXTRA_ARGS` en `compose.yaml` también quita el límite de 30 días por consulta |
| Perfiles (Pyroscope) | 31 días | Predeterminado de la imagen |

## Datos personales

El colector borra de la telemetría nueva, en las métricas, los logs y las trazas, en el elemento y en el recurso: `user.email`, `user.id`, `user.account_uuid`, `user.account_id`, `organization.id`, `process.owner` (y la variante `process_owner`), `tool_input`, `tool_parameters`, `full_command`, `file_path`, `bash_argv0`, `process.command_args` y `process.executable.*` (`grafana/otelcol-config.yaml`, una copia de la configuración de la imagen que debe rehacerse cuando se actualiza la imagen). `session.id` se mantiene, y el nombre de la herramienta sigue en `tool_name`.

El historial no se reescribe: los datos registrados antes de que se descartaran estos atributos los conservan hasta que expiran por la retención de la tabla de arriba, y en los logs no expiran.

Claude Code sigue ENVIANDO estos datos: el email y los ids de cuenta en todas las señales y, con `OTEL_LOG_TOOL_DETAILS=1`, la entrada y los parámetros de las herramientas. La protección está en el colector local, que los borra antes de escribir. Por eso, apuntar `OTEL_EXPORTER_OTLP_ENDPOINT` a un servidor compartido la elude: nada de lo anterior se eliminaría en el camino. Antes de hacerlo, revisa `OTEL_LOG_TOOL_DETAILS`. Lo que no está en la lista del colector queda registrado; `error`, el texto completo del error en `tool_result`, que puede llevar rutas con el login, también se borra, y los perfiles (Pyroscope) no pasan por esta limpieza. El texto del prompt no se envía con `OTEL_LOG_USER_PROMPTS=0`. Con el colector local, esta telemetría OTLP no sale de la máquina; la telemetría operativa de Anthropic es un flujo aparte, que estas variables no controlan.
