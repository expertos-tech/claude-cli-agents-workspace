<!-- source: docs/hooks.md sha256:b844f1efc10b1173a4294a37da67faad60d98b8463803b5f5d402b87dfc9b07e -->

# Hooks

[English](../../../docs/hooks.md) · [Português (Brasil)](../../pt-BR/docs/hooks.md) · Español

## Hooks que se ejecutan en tu máquina

El workspace ejecuta estos hooks en toda sesión abierta en un workspace (`workspace/rules/agents/settings.json`). Son
scripts de `workspace/scripts/`; cada uno imprime su referencia completa con `--help`. Lo que no cubren sigue el modo de
permisos de Claude Code que elegiste.

| Hook | Cuándo | Qué hace |
| --- | --- | --- |
| `guard-bash.sh` | Antes de cada comando Bash | Rechaza escrituras git en `projects/` y en el core fuera del gate, cambios de Terraform fuera de `aiwp-cmds.sh apply`, `git push --no-verify`, un commit en `custom/` que lleve un `.env` o un secreto, `chmod`, `chown` o `git init` sobre rutas del core, y `aiwp update`, `rollback`, `repair`, `forget` y la apertura dentro de una sesión (cambian las reglas de la sesión abierta o inician `claude` dentro de ella). Pregunta antes de borrar una base de datos o un volumen de Docker, antes de un release, un apply o de descartar un clon, y antes de una configuración git que puede ejecutar un comando. Es un reductor de velocidad con tu confirmación detrás, no una sandbox |
| `guard-subagent-model.sh` | Antes de cada llamada a un subagente | Rechaza forks y modelos fuera de la lista permitida, pregunta antes de un subagente en Fable y define el modelo en una llamada que lo heredaría |
| `setup-claude.sh` | Inicio de sesión | Monta `.claude/`, ignorada por git, a partir de las reglas, skills y agentes del producto más tu capa custom |
| `release-notice.sh` | Inicio de sesión | Ejecuta `aiwp check` (una respuesta por día, tiempo límite corto, silencioso sin red) y, cuando hay una release más reciente, hace que Claude avise para cerrar la sesión y ejecutar `aiwp update` en una terminal. Nunca actualiza nada |
| `prompt-log.py` | Inicio de sesión | Registra tus prompts, a partir de las transcripciones de las sesiones, en `custom/prompts/log/`, por proyecto y por semana, y muestra un resumen del último día. Nunca hace push |
| `session-title.py` | Cada prompt que envías | Da a la sesión el nombre del proyecto en `/prompt` (`my-app-1`, `my-app-2`...) y avisa a la sesión cuando un proyecto que mencionas no está normalizado o está por detrás de la versión del workspace |
| `aiwp-cmds.sh _stop-check` | Cuando Claude termina una respuesta | Impide que la respuesta termine con un commit que solo está en tu máquina, en un clon de trabajo |

Los escaneos de secretos usan gitleaks en Docker. Ningún hook envía datos a ninguna parte: las únicas llamadas de red
son las del propio git, a tus remotos y a las etiquetas de este repositorio.
