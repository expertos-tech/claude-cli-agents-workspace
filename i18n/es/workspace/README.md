<!-- source: workspace/README.md sha256:adeb8d96e6e07cacc2c0ed7f71b4ffca2b10f97d74c003c270ddec8b60af3765 -->

# Claude CLI Agents Workspace

<p align="center"><img src="../../../workspace/assets/logo.png" alt="Claude CLI Agents Workspace" width="320"></p>

Un workspace para desarrollar con la **Claude Code CLI**: tú dices **qué** quieres, y Claude decide **cómo**, trabajando en un clon aislado donde todo está permitido. Las verificaciones pesadas y las preguntas para ti quedan en un solo lugar: el gate que lleva el trabajo a la base del proyecto.

> **Hecho para la CLI.** Los hooks, los permisos, las skills y los nombres de sesión se diseñaron y probaron en Claude Code de terminal (`claude`). La app de Claude (escritorio o web) y las extensiones de IDE probablemente puedan abrir el workspace, pero pueden tratar los hooks, los permisos y los comandos de otra forma; allí, lo que describe este README no está garantizado.

## Participa

Este workspace nació del uso diario: equivocarse, medir y simplificar. Mejora con cada persona que lo usa en un proyecto real.

¿Encontraste una forma mejor de hacer algo? ¿Corregiste un bug? ¿Escribiste un hook que ahorra preguntas, una regla más clara, una herramienta útil? **Compártelo** como pull request al repositorio del producto (su README explica cómo).

- **Bug o idea:** abre un issue con lo que pasó, lo que esperabas y cómo reproducirlo.
- **Lo tuyo se queda contigo:** empresa, proyectos, identidad visual y pedidos viven en tu capa custom (`custom/`), nunca en un pull request.
- **Una regla nueva:** prefiere un hook o un script probado a más texto, y di qué agrega o quita el cambio en cada sesión (un paso, una pregunta, texto cargado).

## Inicio rápido

De cero al primer trabajo con merge, en seis pasos.

**Lo que necesitas:**

- **Linux.** En Windows, solo mediante **WSL2**: instala una distribución Linux (Ubuntu, por ejemplo) y haz todo dentro de ella, con la misma estructura que en Linux. El workspace, los proyectos, Docker y `claude` viven en el sistema de archivos de WSL (`~/...`), nunca en `/mnt/c`. No hay versión nativa para Windows.
- La Claude Code CLI instalada y con sesión iniciada: `claude` abre una sesión.
- `git`, Docker Engine (28 o posterior para la copia Docker de una tarea), `bash` y `python3`.
- **Opcional, pero muy importante: el stack de observabilidad** (`tools/observability/`, un Grafana local en <http://localhost:3000>). El workspace funciona sin él, pero es lo que muestra cuánto cuesta cada sesión, en tokens, tiempo y modelo, y `scripts/performance/measure.py` solo mide con él levantado. Sin medir, no hay forma de saber si un cambio en las reglas mejoró o empeoró el trabajo. Con tu sesión abierta (paso 4), ejecuta `/run-tools` y marca Observability, luego sigue su README para activar la telemetría de Claude Code.
- **Recomendado: [Claude in Chrome](https://claude.com/chrome)**, la extensión que permite a Claude abrir páginas en tu Chrome, hacer clic, leer la consola y tomar capturas de pantalla. Con ella, Claude revisa layouts y flujos de pantalla por su cuenta, como lo haría una persona a mano (`/pilot auto`). Instala la extensión en Chrome y conéctala a la sesión con `/chrome` ([cómo usarla](https://code.claude.com/docs/en/chrome)). No funciona en WSL: en Windows, esas pruebas quedan contigo (`/pilot manual`).

### 1. Crea tu workspace

El instalador del repositorio del producto (su README) instala el comando `aiwp` y crea tu workspace: pregunta la carpeta, que debe ser nueva o estar vacía (o la recibe como argumento o en `AIWP_WORKSPACE`). Para crear otro:

```bash
aiwp new ~/my-workspace
cd ~/my-workspace
```

El núcleo del workspace es de solo lectura, y la raíz del workspace no es un repositorio git: `custom/` y cada proyecto son los repositorios. Todo workspace está en el registro de la carpeta de datos (`aiwp list`; `aiwp forget <carpeta>` quita una entrada y nunca toca la carpeta). Las releases nuevas llegan solo por comando: `aiwp update`, en una terminal sin sesión abierta, lista los workspaces registrados y pregunta si actualiza todos, elige cuáles o cancela; reemplaza solo los archivos del núcleo que cambiaron, y tu `custom/`, `projects/` y `tmp/` nunca se tocan. `aiwp` solo avisa cuando hay una release nueva. Cuando una sesión empieza y hay una release nueva, Claude avisa; cierra la sesión y ejecuta `aiwp update` en una terminal (Claude nunca lo ejecuta: cambia las reglas de la sesión abierta).

Para eliminar un workspace, devuelve antes el permiso de escritura, ya que el núcleo es de solo lectura: `chmod -R u+w <folder> && rm -rf <folder>`. Tu capa custom y tus proyectos se van con él: haz push antes.

### 2. Conecta tu capa custom

La capa custom es un **repositorio privado tuyo** que guarda lo que no pertenece a nadie más: tu empresa, la nube y el tenant, la identidad visual, la lista de tus proyectos, los pedidos (pendientes, en qa, publicados), las lecciones, tus propias herramientas (`custom/tools/`) y los archivos `.env` rellenados (`custom/env/`, nunca se commitean). Crea un repositorio vacío en tu servidor git: `aiwp new` te pide su URL (o la recibe con `--custom <url>`) y lo clona en `custom/`; un repositorio vacío recibe un esqueleto y un primer commit.

¿Solo quieres probarlo? Deja la URL vacía: `aiwp new` crea un repositorio local con el esqueleto, y puedes darle un remoto después (`git -C custom remote add origin <url>`). Lo que va en la capa está en `rules/rules.md`, sección "Custom layer".

### 3. Trae un proyecto

Un proyecto que ya existe, en la sesión (paso 4): `/normalize-projects --from <url of your project or its folder> --name my-app`. Clona el proyecto en `projects/my-app` y lo normaliza (cómo funciona: [docs/usage.md](docs/usage.md), "Proyectos"). Un proyecto que clonas a mano, o una POC que mueves a `custom/pocs/`, también sirve: la sesión avisa que aún no es un proyecto del workspace y pide normalizarlo.

`developer` es la base de trabajo; la normalización la crea cuando el remoto no la tiene, después de preguntar. Un proyecto nuevo: `bash scripts/init-repo.sh --type project --name my-app`, ya marcado como proyecto del workspace.

### 4. Abre la sesión en la raíz

```bash
aiwp
```

`aiwp` comprueba si hay una release nueva (nunca actualiza), ejecuta `scripts/setup-claude.sh` e inicia `claude`; los argumentos para `claude` van después de `--`.

Siempre en la raíz del workspace, incluso para trabajar en un proyecto: ahí es donde se aplican las reglas y los hooks. Recomendado: el modo auto de Claude Code. El workspace le deja el juicio de qué es destructivo y mantiene en hooks solo lo que nunca debe ocurrir. Claude responde en tu idioma preferido, que se pregunta al crear el workspace (el ajuste `language` de Claude Code), o, si no hay, en el idioma en que escribes.

### 5. Pide

```text
en my-app, crea un endpoint GET /health que responda 200 con la versión de la aplicación
```

Claude pregunta solo lo que le impide empezar y abre un clon en `tmp/work/<date>-<subject>/my-app/`. Indica la ruta y trabaja solo allí, con pruebas. Cada commit va al remoto por sí solo, tras un escaneo de secretos.

### 6. Llévalo a la base

```text
/merge <date>-<subject>/my-app
```

Sin argumento, `/merge` lleva el clon de esta sesión. El gate actualiza `developer`, ejecuta toda la suite y las validaciones, busca secretos, muestra lo que sale de la base y pide una revisión contra tu pedido. Solo te pregunta si aparece algo que el pedido no explica. Luego `developer` avanza exactamente al commit que pasó. `/merge` también escribe la versión del `CHANGELOG.md` del proyecto antes del gate.

**Siguiente:** para pedidos más grandes, arma el pedido con `/draft-request` y ejecútalo con `/request`; la sesión recibe el nombre del proyecto, numerado (`my-app-1`, `my-app-2`...). La guía completa está en [docs/usage.md](docs/usage.md).

## Cómo funciona

1. **Una pregunta o lectura:** Claude responde; no se abre nada.
2. **Un cambio en un proyecto o en una POC:** un clon en `tmp/work/` (`bash scripts/aiwp-cmds.sh open`). Dentro de él Claude trabaja sin preguntar (commit, rebase, reset, la copia Docker de la propia tarea), y la rama siempre está en el remoto: un hook no deja que la respuesta termine con un commit solo en la máquina.
3. **Base:** `/merge`, escrito solo por ti, pasa por el gate, en dos fases (verificación, revisión contra el pedido, merge del commit verificado). Una tarea termina con su copia Docker publicada y un cuadro de cierre: direcciones, qué probar, y `/merge` o `close --discard`.
4. **Olas:** en un plan por pasos, cada paso cierra con un commit, un pedido de continuación en `custom/requests/` y un cuadro de lo hecho y lo que falta. El siguiente paso empieza en una sesión nueva.

## Lo que nunca ocurre sin ti

- **`projects/` se queda en `developer` y solo cambia mediante el gate.** Un hook rechaza cualquier escritura git en `projects/` o en el núcleo fuera de él.
- **`main` y la nube solo a pedido tuyo.** `main` se mueve solo con `/merge --main <project>`, una nueva versión con tag, o con `/merge --hotfix`, un patch corregido desde `main`, y Terraform aplica solo con `bash scripts/aiwp-cmds.sh apply`, desde `main` y con el plan confirmado.
- **Borrar una base de datos pide tu confirmación**: un volumen de Docker, `DROP`, `dropdb` y similares.
- **La copia Docker de una tarea es libre:** `bash scripts/aiwp-cmds.sh up <work>/<clone>` la publica en su propio grupo `agent_`, en los puertos 61000-65535, nunca sobre el stack final. El stack final solo cambia con `/docker-deploy`, que antes etiqueta las imágenes reemplazadas; `rollback <repo>` vuelve a ellas.
- **Un secreto no sale de la máquina:** el escaneo corre antes de cada push y de nuevo en el gate.
- **La sesión no cambia el workspace:** reglas, scripts, hooks y herramientas son de solo lectura y solo cambian con una nueva versión. `guard-bash` rechaza un `chmod`, `chown` o `git init` que alcance el núcleo, y `aiwp update`, `rollback`, `repair`, `forget` y la apertura dentro de una sesión.
- **El resto sigue el modo de permisos de Claude Code.**

Los hooks: `scripts/guard-bash.sh` (git, Terraform, bases de datos, secretos, el núcleo de solo lectura; `--help` lo enumera todo), `scripts/release-notice.sh` (al inicio de una sesión, avisa cuando hay una release nueva), `scripts/guard-subagent-model.sh` (el modelo de cada subagente), el hook `Stop` de `scripts/aiwp-cmds.sh` (commits que no están en el remoto), `scripts/session-title.py` (el nombre de la sesión, y el aviso sobre un proyecto nombrado en el mensaje que no tiene marcador o está desactualizado) y `scripts/prompt-log.py` (el registro de prompts; al inicio de una sesión, el resumen del último día). El diseño: [docs/decisions/0001-base-design.md](../../../workspace/docs/decisions/0001-base-design.md).

## Comandos

| Comando | Hace |
| --- | --- |
| `/merge [<work>/<clone>]` | Lleva el trabajo de un clon (sin argumento: el de esta sesión) a `developer` del proyecto, mediante el gate, escribiendo el `CHANGELOG.md` |
| `/merge --main <project> [instructions]` | El release: un clon de release, la verificación completa, la revisión final (las tres preguntas sobre todo desde el último tag), el `CHANGELOG.md` fechado, el gate hacia `developer`, luego `main` y el tag `vX.Y.Z` |
| `/merge --hotfix <project> <description>` | Un error en producción: la corrección desde `main`, el gate y una revisión contra `main`, tu OK, la versión de patch `vX.Y.(Z+1)` (con tag cuando indiques publicar), luego `main` mezclada en `developer` |
| `/docker-deploy [developer\|main] [<repo>]` | Actualiza el stack Docker local final desde `developer` o `main`, con tags de rollback y sin borrar ningún volumen; solo a pedido tuyo |
| `/commit [--all] [--repo <dir>]` | Un commit por cambio lógico, en un clon o en `custom/` |
| `/push [--repo custom \| <work>/<clone>]` | Hace push de `custom/`, o vuelve a hacer push de un clon cuyo push automático falló |
| `/validate [folder] [--only <checks>] [--sonar]` | Ejecuta las validaciones en Docker y, opcionalmente, SonarQube |
| `/draft-request [ideas \| file]` | Convierte tus ideas en un pedido del tamaño adecuado (ajuste, funcionalidad o sistema), con el effort de cada paso; pregunta solo lo que bloquea y lo guarda en `custom/requests/` |
| `/request [name \| path]` | Ejecuta un pedido escrito, da a la sesión el nombre del proyecto, numerado; `/merge` lo mueve a qa, y el release a done |
| `/rules [exclude <name> \| include <name> \| add <subject> \| replace <rule> \| lessons]` | Muestra las reglas, skills y agentes que carga una sesión y de dónde viene cada uno; apaga o enciende los del núcleo, reemplaza una regla del núcleo o agrega la tuya, en `custom/rules-config.json` y `custom/my-rules/` (el núcleo obligatorio siempre carga); `lessons` propone reglas propias a partir de las lecciones etiquetadas |
| `/pilot [auto\|manual]` | Muestra o cambia quién ejecuta las pruebas que una persona haría a mano: Claude (`auto`, por defecto) o tú (`manual`) |
| `/local-env [folder]` | Crea o completa el `.env` rellenado a partir de `.env.example`, sin mostrar valores: para `docker/`, `docker/sonar/` y una herramienta de `tools/`, en `custom/env/<name>.env` |
| `/run-tools [--down [tool...]]` | Casillas con las herramientas locales de esta máquina (observabilidad, los simuladores, la consola de Azurite, la consola de contenedores de esta máquina); inicia las que marques, en un solo grupo compose, tras decir qué le falta a cada una; `--down` las detiene |
| `/normalize-projects [<project>... \| --from <url \| folder> [--name <path>]]` | Lista el estado de cada proyecto y POC; o analiza uno (cuatro analistas, un plan que apruebas, el idioma de su documentación) y lo migra en una rama probada, con tags de checkpoint, a `developer` y `main` |

El área de trabajo tiene su propio comando: `bash scripts/aiwp-cmds.sh --help` (`open`, `run`, `status`, `push`, `close`, `up`, `down`, `deploy`, `rollback`, `gate`, `release`, `apply`, y `developer`, `checkpoint`, `bring` para la normalización). Los comandos propios de Claude Code siguen valiendo: `/rewind`, `/rename`, `/usage`.

## Proyecto de prompts

Para escribir pedidos fuera de la sesión de desarrollo, crea un proyecto en Claude solo para eso: pega en sus instrucciones todo lo que está debajo del marcador `<!-- paste below -->` de `rules/request-writing.md` y conecta la carpeta del workspace como referencia. `/draft-request` sigue el mismo archivo dentro del workspace.

## Entorno local

- Validación en Docker: `bash scripts/validate.sh --help`. SonarQube, opcional: `bash scripts/sonar.sh --help`.
- Medir el rendimiento del workspace: `python3 -I -B scripts/performance/measure.py --name <name>` (con la observabilidad levantada) escribe `custom/performance/<date>-<name>.md`, comparado con la medición anterior y las cinco últimas.
- Las tareas pesadas de CPU o GPU (gráficos, renderizado 3D) pasan por `bash scripts/heavy-run.sh`, que espera a que la máquina se enfríe; las pruebas y los builds corren directamente.
- Herramientas en `tools/`: el Grafana local para la telemetría de Claude Code (`tools/observability/`, en <http://localhost:3000>), las consolas de contenedores, los simuladores de login y de Safe Browsing, la consola de Azurite, el informe de uso y la alerta de Fable. Cada una tiene su README ([tools/README.md](tools/README.md)); `/run-tools` las inicia, las de contenedores en un solo proyecto compose, `claude-cli-agents-tools`. Las que admiten configuración leen `custom/env/<name>.env` (`/local-env tools/<name>`) y `custom/config/<name>/`. Tus propias herramientas viven en `custom/tools/` (`bash scripts/init-repo.sh --type tool`).

## Estructura

- `AGENTS.md`: el punto de entrada de Claude (cargado por `CLAUDE.md`). Lo que vale en toda sesión, en una página.
- `rules/`: reglas por tema, los subagentes (`rules/agents/`), los comandos (`rules/skills/`) y la configuración de hooks y permisos (`rules/agents/settings.json`).
- `scripts/`: el área de trabajo, el gate, los hooks, la validación y la creación de repositorios (catálogo en [scripts/README.md](scripts/README.md)).
- `docker/`: herramientas de validación en contenedores.
- `docs/`: guía de uso, visión general y registros de decisiones.
- `assets/`: el logo del proyecto (`logo.png`, `logo-white.png`) y el ícono recortado de él (`icon.png`).
- `tools/`: las herramientas locales del producto, parte del núcleo.
- `templates/`: los formularios que copias y completas: un pedido funcional (`templates/request.md`), cuyo tamaño menor, un ajuste, también guarda una idea.
- `VERSION` y `CHANGELOG.md`: la versión instalada y lo que cambió cada versión.
- `projects/`: un repositorio git independiente por proyecto, nunca parte del núcleo.
- `custom/`: tu capa custom, un repositorio git propio, con tus herramientas en `custom/tools/` y los archivos `.env` rellenados en `custom/env/` (ignorados por git). Las mediciones de rendimiento viven en `custom/performance/`. El registro de prompts, por proyecto y por semana, vive fuera de ella, en `logs/prompts/` en la raíz del workspace, nunca versionado (`scripts/prompt-log.py`).
- `tmp/work/`: los clones de trabajo, uno por pedido, fuera de git.
