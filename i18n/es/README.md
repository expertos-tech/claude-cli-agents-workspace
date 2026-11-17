<!-- source: README.md sha256:d8e456251d94fe8bb9e4f03432f0654800646781daf87f54bade67093ea44d05 -->

# Claude CLI Agents Workspace

<p align="center"><img src="../../workspace/assets/logo.png" alt="Claude CLI Agents Workspace" width="320"></p>

<p align="center"><a href="../../README.md">English</a> · <a href="../pt-BR/README.md">Português (Brasil)</a> · Español</p>

Un workspace para **Claude Code CLI**. Tú dices **qué** quieres, y Claude decide **cómo**, trabajando en un clon
aislado donde todo está permitido. Las verificaciones pesadas y las preguntas para ti quedan en un solo lugar: el gate
que lleva el trabajo a la rama base del proyecto.

> **Hecho para la CLI.** Los hooks, los permisos, las skills y los nombres de sesión se diseñaron y probaron en Claude
> Code de terminal (`claude`). La app de Claude (escritorio o web) y las extensiones de IDE probablemente puedan abrir
> el workspace, pero pueden tratar los hooks, los permisos y los comandos de otra forma; allí, lo que describe esta
> página no está garantizado.

## Qué obtienes

- **Reglas** para el agente: una página que vale en toda sesión (`AGENTS.md`) y reglas por tema (git, seguridad,
  calidad, documentación, frontend, infraestructura, modelos, revisión), que se leen cuando el tema aparece.
- **Skills**: comandos de barra para el flujo diario (`/merge`, `/commit`, `/push`, `/validate`, `/draft-prompt`,
  `/prompt`, `/pilot`, `/local-env`, `/normalize-projects`).
- **Agentes**: subagentes para requisitos, arquitectura, implementación, pruebas, revisión, verificación,
  infraestructura, scripts, documentación e investigación, cada uno con su modelo y su effort.
- **Hooks** que retienen solo lo que nunca debe ocurrir sin ti: escrituras git fuera del gate, cambios en la nube,
  borrado de bases de datos, secretos en un commit.
  [Hooks que se ejecutan en tu máquina](#hooks-que-se-ejecutan-en-tu-máquina) los enumera todos.
- **Un gate de merge**: el trabajo ocurre en un clon dentro de `tmp/work/`, y `/merge` lo lleva a la rama `developer`
  del proyecto después de la suite de pruebas completa, las validaciones, un escaneo de secretos y una revisión contra
  tu pedido.
- **Una capa custom**: tu propio repositorio git privado en `custom/`, para tu empresa, tu nube, tu identidad visual,
  la lista de proyectos, los pedidos y las lecciones. Nunca entra en este repositorio.
- **Herramientas**: un Grafana local para la telemetría de Claude Code, una consola de contenedores (Docker CE en
  Linux, Colima en macOS), simuladores de login y de Safe Browsing, una consola de Azurite, un informe de uso y una
  alerta de modelo. Cada una tiene su README en `workspace/tools/`.

## Requisitos

- **Linux o macOS.** En **Windows, solo mediante WSL2**: instala una distribución Linux (Ubuntu, por ejemplo) y haz todo
  desde dentro de ella, con la misma estructura que en Linux. El workspace, los proyectos, Docker y `claude` viven en el
  sistema de archivos de WSL (`~/...`), nunca en `/mnt/c`. No hay versión nativa para Windows.
- `git`, `bash`, `python3` y Docker.
- Claude Code CLI instalado y con la sesión iniciada: `claude` abre una sesión.
- **Opcional, pero importante: el stack de observabilidad** (`workspace/tools/observability/`, un Grafana local en
  <http://localhost:3000>). Muestra lo que cuesta cada sesión en tokens, tiempo y modelo; sin medición no hay forma de
  saber si un cambio en las reglas mejoró o empeoró el trabajo.
- **Recomendado: [Claude in Chrome](https://claude.com/chrome)**, la extensión que permite a Claude abrir páginas en tu
  Chrome, hacer clic, leer la consola y tomar capturas de pantalla, para validar diseños y flujos de pantalla por sí
  mismo (`/pilot auto`). No funciona dentro de WSL: en Windows, esas pruebas quedan a tu cargo (`/pilot manual`).

## Inicio rápido

### 1. Instala y crea el workspace

```bash
curl -fsSL https://raw.githubusercontent.com/expertos-tech/claude-cli-agents-workspace/main/install.sh | bash
```

`curl | bash` ejecuta lo que el script contenga en ese momento. Para leerlo antes de ejecutarlo:

```bash
curl -fsSL -o install.sh https://raw.githubusercontent.com/expertos-tech/claude-cli-agents-workspace/main/install.sh
less install.sh
bash install.sh
```

El instalador comprueba los requisitos y dice lo que falta, sin instalar nada por su cuenta. Clona el repositorio en tu
carpeta de datos local, en la etiqueta de la release más reciente, pone el comando `aiwp` en `~/.local/bin` y después
crea tu workspace con `aiwp new` y lo añade al registro de workspaces. No necesita permisos de administrador ni `sudo`.

Pregunta dónde va el workspace, en la terminal (funciona con `curl | bash`), según la carpeta en la que se ejecuta:

- **Una carpeta vacía:** `1) Install here` o `2) Give another path`.
- **Una carpeta con contenido:** solo la ruta, de una carpeta nueva o vacía. Una mala respuesta se vuelve a preguntar.

Después `aiwp new` pide la URL de tu repositorio custom: crea un repositorio privado vacío en tu servidor git e indica
su URL. Un repositorio vacío recibe un esqueleto y un primer commit; una respuesta vacía crea un repositorio local.

Para saltarte las preguntas, indica la carpeta:

```bash
curl -fsSL https://raw.githubusercontent.com/expertos-tech/claude-cli-agents-workspace/main/install.sh | bash -s -- ~/my-workspace
AIWP_WORKSPACE=~/my-workspace bash install.sh
```

El argumento gana a `AIWP_WORKSPACE`. Sin terminal y sin carpeta, el instalador instala solo la carpeta de datos e
imprime cómo crear un workspace después (`aiwp new <carpeta>`). Volver a ejecutar el instalador actualiza la carpeta de
datos y nunca un workspace: eso lo hace `aiwp update`. Cuando la carpeta de datos ya está instalada, la pregunta
también ofrece solo actualizarla (`3)`, o una ruta vacía).

### 2. Crea otro workspace

```bash
aiwp new ~/other-workspace
```

Cada workspace es una copia del producto en su propia carpeta, y todos comparten la instalación de la carpeta de datos.

### 3. Ábrelo

```bash
cd ~/my-workspace && aiwp
```

`aiwp` comprueba si hay una release nueva y, cuando la hay, avisa y manda ejecutar `aiwp update`; nunca actualiza.
Después inicia `claude` en la versión actual del workspace. Abre siempre la
sesión en la raíz del workspace, incluso para trabajar en un solo proyecto: ahí es donde valen las reglas y los hooks.
Se recomienda el auto mode de Claude Code: el workspace le deja el juicio sobre lo que es destructivo y guarda en los
hooks solo lo que nunca debe ocurrir.

### 4. Trae un proyecto y pide

```bash
git clone <url de tu proyecto> projects/my-app
git -C projects/my-app switch developer
```

Después, en la sesión:

```text
en my-app, crea un endpoint GET /health que responda 200 con la versión de la aplicación
```

Claude pregunta solo lo que impide empezar, abre un clon en `tmp/work/<fecha>-<asunto>/my-app/`, te dice la ruta y
trabaja solo allí, con pruebas. Cada commit va al remoto después de un escaneo de secretos. Cuando termine:

```text
/merge <fecha>-<asunto>/my-app
```

El gate trae la `developer` actualizada, ejecuta la suite completa y las validaciones, busca secretos, muestra lo que
sale de la base y pide una revisión contra tu pedido. Solo se te pregunta si aparece algo que el pedido no explica.
Para pedidos más grandes, escribe el pedido con `/draft-prompt` y ejecútalo con `/prompt`. La guía completa está en
[workspace/docs/usage.md](workspace/docs/usage.md).

## Comandos

| Comando | Hace |
| --- | --- |
| `aiwp` | Abre el workspace de la carpeta actual: comprueba si hay una release nueva y solo avisa, luego inicia `claude` con los argumentos que pases después de `--` |
| `aiwp new <carpeta>` | Crea un workspace nuevo: copia el producto, pide tu repositorio custom, monta `.claude/` y lo añade al registro |
| `aiwp list` | Lista los workspaces registrados con la versión y el estado de cada uno |
| `aiwp forget <carpeta>` | Quita un workspace del registro; nunca toca la carpeta |
| `aiwp update` | Lista los workspaces registrados y pregunta: actualizar todos, elegir cuáles o cancelar |
| `aiwp update --all` | Actualiza todos los workspaces registrados sin preguntar; los fijados quedan como están |
| `aiwp update <carpeta>` | Actualiza solo ese workspace |
| `aiwp rollback` | Vuelve a la versión de la copia de seguridad más reciente y fija el workspace en ella |
| `aiwp repair` | Restaura los archivos del core que difieren del manifiesto o tienen el permiso equivocado |
| `aiwp check` | Dice en una línea si existe una release más nueva, sin actualizar nada |
| `aiwp version` | Muestra la versión instalada y la del workspace |

## Cómo funcionan las actualizaciones

Hay tres lugares:

| Lugar | Qué es |
| --- | --- |
| Este repositorio | Donde se desarrolla el workspace. Las releases son etiquetas `vX.Y.Z` |
| Tu carpeta de datos local: `${XDG_DATA_HOME:-~/.local/share}/claude-cli-agents-workspace` en Linux y WSL, `~/Library/Application Support/claude-cli-agents-workspace` en macOS | El repositorio completo, clonado por el instalador. `aiwp` lo lleva a la etiqueta de la release más reciente. Nadie lo edita |
| Cada workspace que creas | Una copia solo de `workspace/`, más tus `custom/`, `projects/` y `tmp/` |

La carpeta de datos guarda `workspaces.json`, el registro de todos los workspaces instalados (ruta, versión, creado,
actualizado). `aiwp new` registra un workspace, y la primera ejecución de `aiwp` en uno que no está registrado lo añade.
`aiwp list` muestra cada uno con su estado: al día, actualización disponible, core cambiado, carpeta ausente, fijado o
interrumpido a la mitad.

- **Comprobación:** `aiwp` busca una etiqueta nueva (`git ls-remote --tags`) como mucho una vez al día, con un límite de
  5 s. Sin red, sigue. Cuando hay una release nueva imprime "A new workspace version X was detected (this workspace:
  Y). Run `aiwp update` to update; opening this workspace on Y." y abre en la versión actual. Abrir nunca actualiza. En
  una sesión, el hook de inicio de sesión da el mismo aviso: cierra la sesión y ejecuta `aiwp update` en una terminal.
- **Actualizar, solo por comando, en una terminal, sin sesión abierta:** `aiwp update` lista todos los workspaces
  registrados y pregunta `[1] Update all` (el predeterminado), `[2] Choose which` (por número) o `[3] Cancel`. Lleva la
  carpeta de datos a la release más reciente una vez, después actualiza cada workspace elegido y termina con una tabla
  resumen. Un workspace con el core cambiado, o con la carpeta ausente, se omite y se informa; los demás siguen.
  `aiwp update <carpeta>` actualiza solo ese; `aiwp update --all` actualiza todos sin preguntar y deja como están los
  workspaces fijados (tras un `aiwp rollback`); elegir uno fijado por número o por carpeta lo actualiza y quita la
  fijación. Sin terminal, hace falta `--all` o una carpeta. Antes de reemplazar un workspace donde `claude` se está
  ejecutando, `aiwp update` nombra el proceso y pregunta; con `--all` omite ese workspace, salvo que añadas `--force`.
  El código de salida es 1 cuando se omitió un workspace por core cambiado, por un `claude` en ejecución o por un error.
- **Nunca dentro de una sesión:** desde una sesión de Claude Code (su herramienta Bash, un hook) `aiwp` rechaza
  `update`, `rollback`, `repair`, `forget`, la apertura y un `new` sobre una carpeta registrada, y `guard-bash` también
  los rechaza: cambian las reglas de la sesión abierta. `aiwp list`, `check`, `version` y `--help` funcionan en
  cualquier lugar. Un comando desconocido es un error de uso: los argumentos para `claude` van después de `--`.
- **Core de solo lectura:** los archivos del producto en un workspace son de solo lectura (carpetas y ejecutables 555,
  archivos 444), y el workspace no tiene `.git`: `custom/` y cada proyecto son los repositorios. Para eliminar un
  workspace, devuelve antes el permiso de escritura: `chmod -R u+w <carpeta> && rm -rf <carpeta>` (haz push de
  `custom/` y de tus proyectos antes). Solo se pueden escribir `custom/`, `projects/`, `tmp/`, `.claude/`,
  `.history/` y una lista cerrada de salidas generadas por las herramientas (los datos de Grafana, `node_modules`, las
  páginas compiladas y los binarios de las consolas).
- **Manifiesto:** cada workspace guarda la versión y el hash de cada archivo que recibió. Una actualización reemplaza
  solo lo que cambió la release nueva, borra lo que ella eliminó y omite el workspace si un archivo del core difiere del
  manifiesto (la actualización lo muestra en el resumen); `aiwp repair` lo restaura.
- **Copia de seguridad:** los archivos se reemplazan por renombrado, después de una copia de seguridad en
  `.aiwp/backup/<versión>/` (se guardan las 3 últimas), con un diario. Si una actualización se interrumpe a la mitad,
  `aiwp` se niega a abrir el workspace hasta que `aiwp repair` (o `aiwp update`) lo restaure. `aiwp rollback` vuelve a
  la versión de la copia de seguridad más reciente.
- **Solo se instala `workspace/`**, mediante una lista de inclusión. Nada más de este repositorio llega a tu
  workspace.

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

## La capa custom

`custom/` es **tu** repositorio git privado, separado del producto, y el único lugar para lo que es tuyo: nombre y
grafía de la empresa, nube y tenant, identidad visual, la lista de tus proyectos, los pedidos escritos, las lecciones,
los `.env` completados (`custom/env/`, siempre ignorados por git) y el registro de prompts. El workspace funciona sin
ella y pregunta, cuando lo necesita, la nube, la identidad visual y la carpeta de cada proyecto. Nunca entra en un pull
request a este repositorio.

## Estructura del repositorio

| Ruta | Qué es |
| --- | --- |
| `workspace/` | El producto: `AGENTS.md`, `rules/`, `scripts/`, `tools/`, `docker/`, `docs/`, `assets/`, `templates/`, `VERSION`, `CHANGELOG.md`. Es lo que se instala |
| `CLAUDE.md`, `.claude/` | El mantenimiento del repositorio, en su raíz: el proceso, las reglas, las skills y los agentes de quien mantiene el producto, y la configuración que deja las reglas del producto fuera de esa sesión |
| `tests/` | La suite del repositorio (`check.sh`) y la instalación de prueba |
| `maintainers/` | El trabajo de quien mantiene el proyecto, a la vista: backlog, planes, pedidos y revisiones |
| `i18n/` | Las traducciones de los documentos y READMEs (`pt-BR`, `es`), con la misma estructura que el repositorio |
| `install.sh` | El instalador |
| `tmp/` | Borrador ignorado por git: instalaciones de prueba y notas privadas |

## Participa

Este workspace nació del uso diario: de equivocarse, medir y simplificar. Mejora con cada persona que lo usa en un
proyecto real.

¿Encontraste una forma mejor de hacer algo? ¿Corregiste un defecto? ¿Escribiste un hook que ahorra preguntas, una regla
más clara, una herramienta útil? **Compártelo.** Haz un fork del repositorio, haz tu cambio y envía un pull request.

- **Bug o idea:** abre un issue con lo que pasó, lo que esperabas y cómo reproducirlo.
- **Cambio:** un fork, una rama y un pull request pequeño y enfocado, que diga el porqué y no solo el qué.
- **Mantén desde la raíz del repositorio:** clona este repositorio y abre `claude` en su raíz. El `CLAUDE.md` y la
  `.claude/` de la raíz dan a esa sesión el proceso de mantenimiento (plan, pedido, etapas, pruebas, revisión) y dejan
  las reglas del producto fuera de ella, porque allí son el código que se edita.
- **Antes de enviar:** `bash tests/check.sh --all` debe pasar. Ejecuta el lint, el escaneo de secretos, las
  suites de los scripts y la comprobación que mantiene los datos de empresa fuera del repositorio.
- **Traducciones:** un cambio en un documento en inglés actualiza sus traducciones en `i18n/pt-BR/` y `i18n/es/` en el
  mismo commit.
- **Lo tuyo se queda contigo:** empresa, proyectos, identidad visual y pedidos se quedan en tu capa custom, nunca en el
  pull request.
- **Regla nueva:** prefiere un hook o un script probado a más texto, y di lo que el cambio añade o quita de cada sesión
  (un paso, una pregunta, texto cargado).

## Licencia

[MIT](../../LICENSE).
