<!-- source: workspace/scripts/README.md sha256:f8d70c963263f286cbd565fae8e11ebbc15afb75362da6a96a5c5bed1a66a41f -->

# scripts/

Catálogo de los scripts del workspace. Reglas: `rules/scripts.md`. Revisa esta lista antes de escribir un comando largo.
Se ejecutan como `bash scripts/<name>.sh`. Cada script imprime su referencia completa con `--help`: esta página solo dice qué existe.

En un workspace instalado, los scripts nunca escriben en el core: su salida va a `custom/`, `projects/`, `tmp/`, `.history/` o la carpeta de salida de una herramienta (`bash scripts/aiwp.sh _writable` las lista).

## Validación

| Script | Hace | Ejemplo |
| --- | --- | --- |
| `validate.sh` | Ejecuta en Docker las herramientas de validación de `docker/compose.yaml` e imprime PASS/FAIL por verificación: `secrets`, `vuln`, `iac`, `shell`, `dockerfile`, `markdown`, `mermaid`, `terraform`, `python`, `typescript`, `coverage` (y `cost`). La verificación `secrets` también falla cuando git rastrea un `.env` o un `local.settings.json`. Compose lee `custom/env/docker.env` (si no, los valores por defecto de `docker/.env.example`) y monta el workspace de solo lectura | `bash scripts/validate.sh --path projects/billing --only secrets,markdown` |
| `aiwp-cmds.sh` | Área de trabajo: `open` abre un clon de un proyecto (o de `custom/`, para una POC) en `tmp/work/<work>/`, en la rama del pedido, con push en cada commit tras un escaneo de secretos de los commits; `run`, `status`, `push`, `close`; `up` publica en el Docker local con una etiqueta de rollback antes, `rollback` vuelve a ella. Su `_stop-check` es el hook `Stop` | `bash scripts/aiwp-cmds.sh --help` |
| `aiwp-gate.sh` | Los únicos caminos hacia `projects/`, llamados mediante `aiwp-cmds.sh`: `gate` (fase 1: base actualizada, pruebas completas, `validate.sh`, archivos de entorno y secretos, la auditoría de lo que sale de la base; fase 2 `--merge`: fast-forward del sha verificado; una rama de normalización se juzga por lo que añade), `release` (`developer` a `main`; un pull request cuando `main` está protegida), `apply` (plan de Terraform desde `main`, luego apply de ese plan) y los pasos de `/normalize-projects`: `developer`, `checkpoint` (los tags anotados, enviados) y `bring` (`--from`) | `bash scripts/aiwp-gate.sh --help` |
| `check-workspace.sh` | Gate del repositorio del producto, una herramienta de mantenimiento (en un workspace instalado imprime una línea y sale con 2), para el checkout que lo contiene (solo la carpeta del producto, cuando está en una subcarpeta de su repo git): números de decisión únicos, ningún término de la lista de términos (`AIWP_TERMS_FILE`, si no `custom/core-terms.txt`) en el repo, todo documento traducido (`i18n`, solo cuando la raíz del repositorio tiene `i18n/`), `rules/agents/settings.json` válido, archivos de POC que se parsean, `validate.sh` sobre los archivos cambiados, y las suites de scripts cuyas entradas cambiaron | `bash scripts/check-workspace.sh` |
| `check-ledger.sh` | Biblioteca cargada por los dos scripts anteriores: registra cada PASS bajo un hash de sus entradas, de modo que una verificación corre una vez por estado del código (`CACHED <check>`). No se ejecuta a mano | — |
| `heavy-run.sh` | Ejecuta una tarea pesada de CPU o GPU (gráficos, renderizado 3D): de inmediato por debajo de 88 °C, si no cuando la más caliente entre CPU y GPU marca 85 °C o menos; sin cola (`rules/machine-load.md`). Salida 75: sigue caliente después de 30 minutos, no se ejecutó nada | `bash scripts/heavy-run.sh -- <render command>` |
| `performance/measure.py` | Mide el workspace a partir de las transcripciones de sesión (proceso, validación y gate, preguntas, contexto, tiempo hasta la primera edición) y escribe `custom/performance/<date>-<name>.md`, comparado con el informe anterior y los cinco últimos. Solo corre con el stack de observabilidad levantado | `python3 -I -B scripts/performance/measure.py --name <name>` |
| `prompt-log.py` | Registra cada prompt humano a partir de las transcripciones de sesión (la raíz del workspace más las carpetas de `custom/prompts/log/sources.json`) en `custom/prompts/log/<project>/<year>-W<week>.md`, con los commits del agente y los merges del gate que siguieron, y resúmenes por día y por semana armados con esos datos. Solo agrega: una transcripción expirada conserva sus registros. `--context` es un hook `SessionStart` (imprime el último día con actividad, nunca hace fallar la sesión); `--commit` escanea los archivos cambiados con gitleaks en Docker, quita lo que encuentra y hace commit de ellos en `custom/`, nunca hace push | `python3 -I -B scripts/prompt-log.py sync --commit` |
| `sonar.sh` | Stack opcional de SonarQube (`up`, `down`, `status`, `scan`), solo cuando la persona lo pide. Lee `custom/env/docker-sonar.env`; el scan monta la carpeta de solo lectura y mantiene `.scannerwork` en el `/tmp` del contenedor | `bash scripts/sonar.sh scan --key billing --path projects/billing` |

## Hooks

Conectados en `rules/agents/settings.json`. Cada uno lee el JSON del hook por stdin.

| Script | Hace |
| --- | --- |
| `guard-bash.sh` (+ `guard-bash.py`) | `PreToolUse` en `Bash`. Rechaza escrituras git en `projects/` y en el core, cambios de Terraform, `push --no-verify` y un commit en `custom/` que lleve un secreto. En un workspace instalado, también rechaza `chmod`, `chown`, `chgrp`, `git init` y `git clone` que lleguen al core de solo lectura (se siguen enlaces, globs, `-R`, `find`, `xargs`, `sudo` y `bash -c`; las rutas escribibles vienen de `aiwp.sh _writable`, y si eso falla pregunta), y `aiwp update`, `rollback`, `repair`, `forget` y la apertura (`aiwp` solo, `aiwp -- ...`) dentro de una sesión. Pregunta antes de borrar una base de datos y antes de `aiwp-cmds.sh release`, `checkpoint`, `developer --create`, `gate --untested`, `apply --apply` y `close --discard`. Lee la línea como la agrupa un shell; su `--help` lo enumera todo y lo que no ve. Un error interno pregunta, nunca pasa en silencio |
| `release-notice.sh` | `SessionStart`: en un workspace instalado, ejecuta `aiwp.sh check --quiet` (una respuesta por día, tiempo acotado, seguro sin red) y, cuando hay una release más reciente, agrega al contexto de la sesión que Claude avise que cierres la sesión y ejecutes `aiwp update` en una terminal. Solo detecta; en otro caso, silencioso |
| `guard-subagent-model.sh` (+ `guard-subagent-model.py`) | `PreToolUse` en `Agent`. Niega un fork y un modelo fuera de la lista permitida, pregunta en Fable, fija `opus` en una llamada que heredaría. Una falla bloquea la llamada |

## Configuración y repos

| Script | Hace | Ejemplo |
| --- | --- | --- |
| `aiwp.sh` | El comando `aiwp` (`~/.local/bin/aiwp` apunta a la copia en la carpeta de datos): `new` crea un workspace (el core de solo lectura, un manifiesto, `custom/`) y lo registra en `workspaces.json` de la carpeta de datos; sin comando abre el workspace (comprobación de release que solo avisa cuando hay una, `setup-claude.sh`, `claude`); `list` y `forget` muestran y editan el registro; `update` lista los workspaces registrados y actualiza todos, los elegidos, una carpeta (`<carpeta>`) o cada uno (`--all`, `--force`), solo por comando y en una terminal; `rollback`, `repair`, `check`, `version`. En una sesión rechaza `update`, `rollback`, `repair`, `forget` y la apertura. Las carpetas escribibles de un workspace instalado están listadas una vez, al inicio del script; `aiwp.sh _writable` las imprime para `guard-bash` | `aiwp new ~/my-workspace` |
| `setup-claude.sh` | Crea o sincroniza la `.claude/` ignorada por git a partir de `rules/agents/`, `rules/skills/` y las `rules/*.md` que llevan un front matter `paths:`, más cada `custom/rules/*.md` como `.claude/rules/custom-*.md` y las rutas de `custom/claude-md-excludes.txt` en `claudeMdExcludes`; instala la alerta de Fable una vez; cuando falta `custom/`, pide su repo git (`--custom-repo <url>`). Un hook `SessionStart` lo ejecuta con `--quiet`; `--check` solo informa | `bash scripts/setup-claude.sh --check` |
| `session-title.py` | Hook `UserPromptSubmit`: en `/prompt <file>`, nombra la sesión `<project>-<n>` a partir de la línea `**Project:**` del archivo, con `<n>` uno más que el mayor de ese proyecto entre las sesiones en curso del workspace. En cada mensaje que nombra un proyecto de `projects/` o una POC (nombre de carpeta, ruta, línea `**Project:**`), añade su estado al contexto cuando no tiene marcador o está desactualizado, para que Claude avise y pida ejecutar `/normalize-projects`; nunca bloquea, con tiempo acotado, silencioso ante errores | — (hook) |
| `aiwp-project-state.sh` | Imprime si cada proyecto y POC es un proyecto del workspace: el marcador en la línea 1 de su `README.md` (de `developer`, leído con `git show`) frente a `VERSION` y `migrations/`: sin marcador, al día, desactualizado con las migraciones pendientes, o el repositorio propio del workspace. Solo lectura; lo usan el hook, `aiwp-cmds.sh open`, el gate y `/normalize-projects` | `bash scripts/aiwp-project-state.sh billing-api` |
| `init-repo.sh` | Crea un proyecto en `projects/` como repo git independiente, o una POC (`custom/pocs/`) o una herramienta tuya (`custom/tools/`) en la capa custom, con el README de un proyecto o POC empezando por el marcador de la versión del workspace; nunca escribe en el core. Nunca sobrescribe | `bash scripts/init-repo.sh --type project --name billing-api` |
| `sync-env.sh` | Crea o completa el `.env` rellenado a partir del `.env.example` de una carpeta, imprimiendo solo los nombres de las claves: `custom/env/<name>.env` (modo 600) para `docker`, `docker/sonar` y `tools/<name>`, agregando `env/` a `custom/.gitignore` cuando falta; `<dir>/.env` para un proyecto o clon. Detrás de `/local-env` | `bash scripts/sync-env.sh --path docker` |
| `lib/env.sh` | Biblioteca: dónde vive el `.env` rellenado de una carpeta del core y qué archivo lee compose con `--env-file`. La cargan `sync-env.sh`, `sonar.sh` y `validate.sh` | — |
| `lib/projects.sh` | Biblioteca: la estructura de `projects/` (qué carpeta es un repo). La cargan `init-repo.sh`, `history.sh`, `aiwp-project-state.sh` y `aiwp-gate.sh` | — |

## Opcionales

| Script | Hace |
| --- | --- |
| `history.sh` | Agrega una entrada al `history.txt` de un proyecto, de una herramienta tuya (`custom/tools/<name>`) o de una POC, o muestra las últimas (`add`, `flush`, `show`); nunca en el core. Ninguna regla pide entradas de historial; `single-agent.sh import-history` lo usa para traer las entradas de una sesión de agente único a su objetivo |
| `single-claude.sh` | Lo ejecuta la persona, desde una terminal: abre Claude en un proyecto, una herramienta tuya o una carpeta de POC sin las instrucciones, los hooks y las skills del workspace (guía en `docs/single-agent.md`) |
| `single-agent.sh` | Soporte de ese modo: validación del objetivo, el `SINGLE-AGENT.md` generado, sus nombres de sesión, `import-history` |

## Pruebas

Cada suite corre sola, sobre carpetas desechables: `bash scripts/tests/<name>/test-<name>.sh`. Las pruebas de Python (`scripts/tests/test_*.py`) corren bajo el gate de cobertura: `bash scripts/validate.sh --only coverage`.

| Suite | Cubre |
| --- | --- |
| `tests/check-workspace/` | `check-workspace.sh`, el ledger, y el manejo de argumentos y la verificación de secretos rastreados de `validate.sh` |
| `tests/aiwp-cmds/` | `aiwp-cmds.sh`: clones, push automático, rechazos de pre-push, hook Stop, close, up y rollback |
| `tests/aiwp-gate/` | `aiwp-gate.sh`: ambas fases del gate, base que se movió, conflictos, la auditoría, release (una `main` protegida y su pull request), apply, y los pasos de la normalización contra remotos bare locales: `developer`, los tags de checkpoint, `bring`, el gate que juzga lo que añade la rama |
| `tests/guard-bash/`, `tests/test_guard_bash.py` | `guard-bash.sh` y `guard-bash.py` |
| `tests/guard-subagent-model/`, `tests/test_guard_subagent_model.py` | `guard-subagent-model.sh` y `guard-subagent-model.py` |
| `tests/setup-claude/` | `setup-claude.sh` |
| `tests/aiwp/` | `aiwp.sh`, el `install.sh` de la raíz y `release-notice.sh`, sin red, sobre un repositorio de fixture con dos releases |
| `tests/sync-env/` | `sync-env.sh` y `lib/env.sh` |
| `tests/heavy-run/` | `heavy-run.sh` |
| `tests/single-agent/` | `single-agent.sh` y `single-claude.sh` |
| `tests/test-projects-layout.sh` | `init-repo.sh` (el marcador incluido), `history.sh`, `lib/projects.sh` |
| `tests/aiwp-project-state/` | `aiwp-project-state.sh`: sin marcador, igual, más antiguo con y sin una migración más nueva, README sin marcador, POC, el repositorio propio del workspace |

Una suite nueva se agrega a `SUITES` y `suite_inputs` de `check-workspace.sh`.
