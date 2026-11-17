<!-- source: workspace/docs/single-agent.md sha256:1f24769bd13f90027ff3313c616ec07d89d3e164ef1ad9cf1e357fc4c35655c0 -->

# Modo de agente único

Guía para trabajar enfocado en un solo objetivo, solo tú y un agente, sin las instrucciones, los hooks y las skills del workspace.

- [Instalar](#instalar)
- [Abrir una sesión](#abrir-una-sesión)
- [El comando /single-agent](#el-comando-single-agent)
- [Lo que sigue valiendo](#lo-que-sigue-valiendo)
- [Historial](#historial)
- [Llevar el trabajo a main](#llevar-el-trabajo-a-main)

## Instalar

Una vez, en tu terminal:

```bash
ln -sf "<workspace>/scripts/single-claude.sh" ~/.local/bin/single-claude
```

El enlace apunta a la copia del script que tiene el propio workspace, así que una actualización del workspace también actualiza el comando.

## Abrir una sesión

```bash
single-claude [<path>] [--commit] [--merge] [--review] [-- <claude arguments>]
```

- Objetivo: un repositorio de `projects/` (a cualquier profundidad), una herramienta tuya en `custom/tools/` (la ruta `tools/<name>` significa lo mismo) o una POC de `custom/pocs/`. Sin ruta, la carpeta actual. La raíz del workspace, una carpeta del `tools/` del producto (solo lectura), una subcarpeta de un ítem y un ítem que la capa custom ignora se rechazan, con el motivo.
- El comando prepara el objetivo (reescribe `SINGLE-AGENT.md` y se asegura de que `/SINGLE-AGENT.md` esté en el `.gitignore` del objetivo, sin commit), reserva el nombre `single-agent-default-<n>` y abre `claude` en la carpeta del objetivo.
- La sesión no carga ningún `CLAUDE.md`, `AGENTS.md`, settings, hooks, skills ni agentes del workspace (`--setting-sources user`); tu `~/.claude` sigue valiendo. Sus instrucciones son `SINGLE-AGENT.md`.
- En este modo el hook `guard-bash` del workspace no se carga: nada pide confirmación antes de un commit, merge, push o comando destructivo. El comando se niega a correr dentro de una sesión de Claude Code (`CLAUDECODE=1`); eso es solo un reductor de velocidad, que `env -u CLAUDECODE` esquiva.
- Todo lo que va después de `--` pasa directo a `claude`, por ejemplo `-- --model sonnet`.

Opciones, solo para esta sesión; ninguna hace push:

| Opción | Efecto |
| --- | --- |
| ninguna | commit, rama, merge y push solo cuando tú lo pides, una operación por pedido; una prueba que falla se muestra antes del commit, sin detenerlo |
| `--commit` | un commit por sí solo en cada paso con las pruebas pasando |
| `--merge` | una rama propia por pedido y el merge de vuelta al final; incluye `--commit`; pregunta antes de volver a `main` |
| `--review` | antes de cada commit, una revisión de un subagente nuevo, sin el contexto de la sesión; un BLOCKER llega a ti para que decidas |

En una POC o una herramienta, los commits caen en un repositorio que otras sesiones comparten (el de la capa custom, o el del workspace): la sesión agrega solo las rutas del objetivo y nunca cambia de rama allí.

## El comando /single-agent

Existe solo en la sesión abierta por `single-claude`. Escribe `/single-agent`: Claude Code lo completa a `/single-agent:single-agent`, el nombre con el plugin delante, y ejecuta el mismo comando.

| Uso | Efecto |
| --- | --- |
| `/single-agent [<path>] [options]` | reescribe y carga `SINGLE-AGENT.md`; las opciones dadas reemplazan las de la sesión |
| `/single-agent update <path>` | vuelve a aplicar la plantilla y el `.gitignore` a ese objetivo y enumera lo que cambió; sin ruta, se rechaza |
| `/single-agent --rename <task>` | renombra la sesión a `single-agent-<task>` |
| `/single-agent --help` | muestra el uso y las opciones |

`SINGLE-AGENT.md` sale de `rules/single-agent/single-agent-template.md`; editar el archivo en el objetivo no sirve, porque cada ejecución lo reescribe.

## Lo que sigue valiendo

Sin opción para desactivarlo: la seguridad de los datos, la confirmación antes de una acción destructiva, la lectura de temperatura antes de una tarea pesada y solo la nube y el tenant de la capa custom (`custom/rules/company.md`). La sesión única ignora por completo los mensajes de las sesiones `ai-workspace-*` (sin respuesta, sin acción, sin mencionártelo), y las sesiones del workspace no le envían mensajes y nunca leen `SINGLE-AGENT.md`.

## Historial

La sesión única registra cada pedido en `single-agent-history.txt`, en la raíz del objetivo, en el formato de `history.txt`, y ese archivo se commitea con el objetivo. Para traer las entradas al historial del workspace, pídeselo a una sesión del workspace; ejecuta:

```bash
bash scripts/single-agent.sh import-history --target <target path>
```

Las entradas nuevas van al `history.txt` del mismo objetivo, con el `REQUEST` empezando por `[single-agent <date>]`. Una segunda importación trae solo lo nuevo.

## Llevar el trabajo a main

El modo de agente único nunca hace merge en `main` por su cuenta. Abre una sesión normal en la raíz del workspace y pide una revisión de contexto limpio de lo que está en `developer` y no en `main` (un repositorio sin `developer`: indica la rama). Con cero BLOCKER y las verificaciones pasando, `main` se mueve solo mediante el release, `bash scripts/aiwp-cmds.sh release <repo>`, a pedido tuyo (`rules/git.md` "Gate").
