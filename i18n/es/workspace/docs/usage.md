<!-- source: workspace/docs/usage.md sha256:6438c5c43f9cb69a88d0447d3247a710fc93940bc2a8ff82baede21fdea88148 -->

# Usar el workspace

Guía de uso del día a día. El diseño y sus motivos están en [overview.md](overview.md) y en la [decisión 0001](../../../../workspace/docs/decisions/0001-base-design.md).

- [La idea en una frase](#la-idea-en-una-frase)
- [Antes de la primera sesión](#antes-de-la-primera-sesión)
- [Abrir una sesión](#abrir-una-sesión)
- [El registro y la actualización](#el-registro-y-la-actualización)
- [Hacer un pedido](#hacer-un-pedido)
- [Dónde ocurre el trabajo](#dónde-ocurre-el-trabajo)
- [Olas: checkpoint, merge y continuación](#olas-checkpoint-merge-y-continuación)
- [Lo que Claude te pregunta](#lo-que-claude-te-pregunta)
- [Comandos](#comandos)
- [Revisión](#revisión)
- [Pruebas que una persona haría a mano](#pruebas-que-una-persona-haría-a-mano)
- [Proyectos](#proyectos)
- [Varias sesiones a la vez](#varias-sesiones-a-la-vez)
- [Validar](#validar)
- [Cambiar el propio workspace](#cambiar-el-propio-workspace)
- [Cuando algo sale mal](#cuando-algo-sale-mal)
- [Dónde está cada cosa](#dónde-está-cada-cosa)

## La idea en una frase

Tú dices **qué** quieres; Claude decide **cómo** y lo hace en un clon aislado, donde todo está permitido. La verificación pesada y las preguntas quedan en un solo lugar: el gate que lleva el trabajo a la base.

## Antes de la primera sesión

Una vez por workspace:

| Paso | Comando |
| --- | --- |
| Crear el workspace: el core de solo lectura, la capa custom en `custom/` y la carpeta `.claude/` | lo hace el instalador (pregunta la carpeta); otro: `aiwp new <carpeta>` (pregunta la URL del repositorio de la capa custom, o `--custom <url>`; una respuesta vacía crea uno local) |
| Comprobar Docker, usado por las validaciones | `docker info` |
| Crear el `.env` rellenado de las herramientas de validación, `custom/env/docker.env` | `/local-env docker`, en una sesión; luego rellena los valores en un editor |
| Opcional, pero la única forma de medir las sesiones: levantar el stack de observabilidad (un Grafana local) | `/run-tools`, en una sesión, marcando Observability; luego su README activa la telemetría de Claude Code |

Desde entonces `.claude/` se mantiene actualizada sola: un hook de inicio de sesión ejecuta `setup-claude.sh`.

Para eliminar un workspace, devuelve antes el permiso de escritura, ya que el core es de solo lectura: `chmod -R u+w <folder> && rm -rf <folder>`. Haz push de `custom/` y de tus proyectos antes: se van con él.

## Abrir una sesión

```bash
cd <workspace> && aiwp
```

`aiwp` comprueba si hay una release nueva (como máximo una vez al día, límite de 5 s; sin red sigue adelante) y, cuando la hay, imprime "A new workspace version X was detected (this workspace: Y). Run `aiwp update` to update; opening this workspace on Y." Luego ejecuta `setup-claude.sh` e inicia `claude` en la versión actual, con los argumentos que pases después de `--` (`aiwp -- --resume`). Abrir nunca actualiza. Tras una actualización interrumpida, se niega a abrir hasta que `aiwp repair` (o `aiwp update`) restaure el workspace. `claude` solo también abre el workspace: cuando existe una release nueva, el inicio de la sesión lo dice, y Claude te indica cerrar la sesión y ejecutar `aiwp update` en una terminal.

**Nunca dentro de una sesión.** Desde una sesión de Claude Code (su herramienta Bash, un hook) `aiwp` rechaza `update`, `rollback`, `repair`, `forget`, la apertura y un `new` sobre una carpeta registrada, y `guard-bash` también los niega: cambian las reglas de la sesión abierta o inician `claude` dentro de ella. `aiwp list`, `check`, `version` y `--help` funcionan en cualquier lugar. Un comando desconocido es un error de uso; los argumentos para `claude` van después de `--`.

- **Siempre en la raíz del workspace**, incluso para trabajar en un proyecto: ahí es donde se aplican `AGENTS.md`, las reglas y los hooks.
- **Una sesión por pedido.** Cuando termina el asunto, usa `/clear` o abre otra sesión. Una sesión larga sale cara: cada paso vuelve a leer todo el contexto.
- **Effort:** `medium` sirve para el trabajo de alcance claro. Súbelo a `high` con `/effort high` cuando el cambio toca un hook, un permiso, un merge o seguridad, o para depurar una falla difícil. Para un solo paso difícil, escribe `ultrathink` en el prompt.
- **Nombre de la sesión:** `/request <file>` da a la sesión el nombre del proyecto, numerado (`billing-api-1`, `billing-api-2`...), a partir de la línea `**Project:**` del pedido: el número es el siguiente al mayor entre las sesiones abiertas de ese proyecto. Sin `/request`, Claude Code elige un título por su cuenta; `/rename <name>` lo cambia.
- **Idioma:** Claude responde en tu idioma preferido de comunicación, el que `aiwp new` preguntó al crear el workspace, incluso cuando ejecuta un archivo de pedido escrito en inglés. Es el ajuste `language` de Claude Code en `.claude/settings.local.json` del workspace (por ejemplo `"language": "portuguese"`); `aiwp update` nunca cambia ese archivo. Si no hay ninguno definido ahí ni en tu `~/.claude/settings.json`, Claude responde en el idioma en que escribes. Para definirlo o cambiarlo después, edita esa clave.

## El registro y la actualización

La carpeta de datos guarda `workspaces.json`, con todos los workspaces instalados (ruta, versión, creado, actualizado). `aiwp new` registra un workspace, y la primera ejecución de `aiwp` en uno que no está registrado lo agrega.

| Comando | Hace |
| --- | --- |
| `aiwp list` | Cada workspace registrado con su versión y estado: al día, actualización disponible (X), core modificado, carpeta ausente, fijado en X, detenido a medias |
| `aiwp forget <folder>` | Quita la entrada (para una carpeta que ya no existe, o que ya no actualizas); nunca toca la carpeta |
| `aiwp update` | Lista los workspaces registrados (número, versión, estado, ruta) y pregunta `[1] Update all` (el predeterminado), `[2] Choose which` (números) o `[3] Cancel` |
| `aiwp update <folder>` | Actualiza solo ese workspace, sin preguntar |
| `aiwp update --all` | Actualiza todos los workspaces registrados, sin preguntar |

La actualización ocurre solo por comando, en una terminal, sin sesión abierta. `aiwp update` lleva la carpeta de datos a la release más reciente una vez, luego actualiza cada workspace elegido: lo verifica contra su manifiesto, hace backup de lo que reemplaza en `.aiwp/backup/<version>/`, escribe un journal, intercambia archivos por rename y muestra el changelog. Un workspace cuyo core cambió o cuya carpeta no existe se omite y se informa, y los demás siguen; una tabla resumen cierra la ejecución.

- **Workspaces fijados** (después de `aiwp rollback`) quedan como están con `--all` y con Update all; elegir uno por número o por carpeta lo actualiza y quita la fijación.
- **Sin terminal:** se exige `--all` o una carpeta; si no, es un error de uso (salida 2).
- **Un `claude` en ejecución:** antes de intercambiar un workspace donde corre un proceso `claude` (su carpeta actual dentro del workspace), indica el pid y pregunta. Con `--all` omite ese workspace, salvo que agregues `--force`.
- **Salida 1** cuando un workspace se omitió por un core modificado, un `claude` en ejecución o un error.

## Hacer un pedido

**Un pedido simple:** escríbelo con palabras.

```text
corrige el enlace roto en el README de my-project
```

**Un pedido funcional (una funcionalidad, un sistema):** el formulario es `templates/request.md`. Sus títulos y etiquetas en negrita quedan en inglés; el contenido va en tu idioma. Hay dos formas de completarlo.

| Forma | Cómo |
| --- | --- |
| A partir de ideas sueltas | `/draft-request quiero un reporte mensual de...`; Claude pregunta solo lo que bloquea, marca el resto como "assumed decision" y lo guarda en `custom/requests/` |
| Tú mismo | copia `templates/request.md` a `tmp/request.md` y complétalo |

Luego, `/request <file>` lee `custom/requests/<file>`; `/request` solo lee `tmp/request.md`.

- Los pedidos de `/draft-request` viven en `custom/requests/`, dentro de la capa custom, un repositorio git propio: el historial de los pedidos se versiona allí.
- Un pedido pasa por tres carpetas: pendiente en la raíz de `custom/requests/` (estado `idea` o `ready`); `custom/requests/qa/<project>/` cuando `/merge` lo llevó a `developer`, con un bloque "Execution" de lo que se hizo; `custom/requests/done/<project>/` cuando `/merge --main` lo publicó, tras validarlo contra el código. Una idea es un pedido en estado `idea`; no existe un backlog.
- `/draft-request` hace commit y push del pedido que creó, en cada versión; `/merge` hace commit y push de los movimientos a qa y done, y una ola el de su punto de continuación ([Olas](#olas-checkpoint-merge-y-continuación)).
- `aiwp new` prepara `custom/`: clona el repositorio cuya URL le des (uno vacío recibe un esqueleto), o inicia uno local. Si la carpeta falta después, la sesión lo dice al inicio, y `bash scripts/setup-claude.sh --custom-repo <url>` en una terminal la clona.

El pedido escrito tiene el tamaño de lo que pediste. `/draft-request` elige uno de tres tamaños antes de escribir, y dice cuál:

| Tamaño | Cuándo | Qué sale | Tope |
| --- | --- | --- | --- |
| Ajuste | cambia un comportamiento de algo que existe ("agregar un overlay de confirmación") | pocas líneas: qué, dónde, listo cuando, effort | unas 120 palabras |
| Funcionalidad | una capacidad nueva en un sistema que existe | objetivo, reglas, criterios de aceptación, fuera de alcance, pasos y effort | unas 400 palabras, como máximo 8 reglas |
| Sistema | un sistema nuevo, arquitectura, infra, integración externa, datos personales | el formulario completo | sin tope |

- Una regla que no declaraste no se escribe, salvo que sin ella pudieran construirse dos cosas distintas.
- ¿Demasiado grande o pequeño? Responde "más pequeño" o "más grande".
- Un pedido del tamaño ajuste puede ir directo a la sesión, sin archivo.

**Effort por paso.** Todo pedido escrito lleva el effort que pide cada paso: una línea en el tamaño ajuste, y la tabla "Steps and effort" en los demás. Tú configuras la sesión con `/effort <level>` antes de cada paso; Claude dice al inicio de cada uno qué nivel pide y pasa ese nivel a los subagentes del paso.

| Effort | Cuándo |
| --- | --- |
| `low` | un cambio mecánico: un texto, una etiqueta, un renombrado |
| `medium` | un alcance claro; el predeterminado |
| `high` | donde importa la verificación: seguridad, datos personales, dinero, permisos, migración, un paso destructivo, un bug en código que existe |

Qué esperar:

- Claude pregunta las **lagunas funcionales**, todas de una vez, antes de empezar. No pide tu aprobación para decisiones técnicas.
- Una pregunta o un pedido de solo lectura se responde directo, sin rama y sin prueba.
- Al final, un resumen corto: qué cambió, qué se verificó y cómo, qué falta. Un check que falla se informa como falla, con su salida.

## Dónde ocurre el trabajo

- **Una pregunta o lectura:** Claude responde; no se abre nada.
- **Un cambio en un proyecto o en una POC:** Claude abre un clon en `tmp/work/<date>-<subject>/<clone>/` (`<clone>`: la ruta del repo relativa a `projects/`, cada `/` escrito como `--`) (`bash scripts/aiwp-cmds.sh open`), dice la ruta y trabaja solo allí. En el clon Claude trabaja sin preguntar: `guard-bash` aprueba una línea cuando todo comando de ella corre en ese clon, toda ruta que nombra se queda en él y nada actúa sobre un sistema remoto (un push, una publicación, un deploy, una CLI de nube, `ssh`); lo que no puede afirmar sigue el modo de permisos de Claude Code. Cada commit va al remoto por sí solo, tras un escaneo de secretos de los commits que salen; un commit con un secreto o un `.env` se queda en el clon.
- **Llevarlo a la base:** `/merge [<work>/<clone>]`; sin argumento, el clon de esta sesión. `/merge` integra `developer` en el clon y escribe la versión del `CHANGELOG.md` del proyecto (`## [X.Y.Z] - Unreleased`; las reglas del bump están en `rules/docs.md`) antes del gate. El gate actualiza `developer`, ejecuta la suite completa y el `validate.sh` completo, escanea todo commit entrante en busca de secretos, escribe la auditoría de lo que sale de la base (archivos borrados o renombrados fuera, pruebas eliminadas o desactivadas, SQL destructivo, infra, dependencias, las advertencias) y pide una revisión contra el pedido. Solo una hard rule detiene el gate: un secreto o un archivo de env, un comando de prueba que falla, un check que cambia archivos rastreados, las reglas de alcance de la normalización y del hotfix. Todo otro check de `validate.sh` que falle (lint, vulnerabilidades, infra, cobertura...) es una advertencia: va a la auditoría en "Warnings", `/merge` la lista en su resumen y tú decides. `/merge` lo escribes solo tú: el gate rechaza la fase 2 en caso contrario. Solo se te pregunta por lo que el pedido no explica. Luego `developer` avanza por fast-forward exactamente al commit que pasó, y el clon puede cerrarse (`aiwp-cmds.sh close`).
- **La copia de la tarea:** al final de una tarea Claude la publica en el Docker local con `aiwp-cmds.sh up <work>/<clone>`, como una copia en su propio grupo compose `agent_<MMDD>-<slug>` (`--<clone>` agregado cuando otro clon del trabajo ya lo usa), con cada puerto movido a uno libre en 61000-65535. Nunca toca el stack final. Sus redes son internas, con un gateway aislado (Docker Engine 28 o posterior), así que un contenedor sin puerto publicado no alcanza ni el host ni el exterior; `up` rechaza lo que su aislamiento exige (red del host, un socket de Docker o un bind fuera del clon, redes o volúmenes externos, Docker anterior a 28). Un servicio con una clave fuera de la lista segura (privilegios, capabilities, dispositivos, sysctls...) inicia con una advertencia, y el `exec` en él sigue el modo de permisos en vez de ser aprobado por el hook. `aiwp-cmds.sh down <work>/<clone>` la detiene; `close` y el gate la destruyen. Claude trabaja libremente dentro de ese grupo, sin preguntar (`down -v`, `logs`, `exec` en un contenedor aislado), volúmenes incluidos; iniciarla o reconstruirla pasa por `up` de nuevo.
- **`projects/` se queda siempre en `developer`.** Nadie edita allí; solo el gate avanza la base.

## Olas: checkpoint, merge y continuación

Una ola es cada paso de un plan por pasos (la tabla "Steps and effort" del pedido). Un pedido de un solo paso, o sin pasos, es una ola, que cierra cuando termina. Una pregunta o lectura no abre ola.

- **Una parte va a la base solo cuando escribes `/merge`**, cuando tú decidas. Una base que publica en producción: el gate pregunta antes de mezclar. Una rama de migración también espera tu orden.
- **Al cerrar la ola**, Claude:
  1. hace el checkpoint: un commit en el clon, que va al remoto por sí solo (`aiwp-cmds.sh status` muestra `not-pushed=0`);
  2. agrega al pedido que estaba corriendo, en `custom/requests/`, dónde se detuvo (el trabajo, el clon, la rama y el sha), las decisiones tomadas, los pendientes y los próximos pasos con su effort; el pedido sigue pendiente;
  3. termina la respuesta con el cuadro de cierre: qué se hizo y verificó, las direcciones de la copia, un ítem a probar por criterio de aceptación, qué falta, el pedido a retomar y las dos salidas: `/merge <work>/<clone>` para aprobar, `aiwp-cmds.sh close <work> --discard` para descartar el trabajo. Tras el cuadro la sesión se detiene; la siguiente ola empieza en una sesión nueva, con `/request <file>`.
- La sesión no termina la respuesta con un commit fuera del remoto: un hook la hace reintentar o decir por qué no pudo.

Regla completa: `rules/git.md`, secciones "Gate" y "Waves".

## Lo que Claude te pregunta

Lo demás sigue el modo de permisos de Claude Code: el modo auto juzga lo que es destructivo.

| Situación | Qué ocurre |
| --- | --- |
| Un gate con algo que el pedido no explica, destrucción fuera de la máquina, o una base que publica en producción | una pregunta, en una ronda, antes de mezclar |
| Una línea que mezcla un comando aprobado con comandos en el clon | rechazada con "Run it alone": Claude ejecuta los otros primero y el preguntado solo, para que la pregunta muestre solo a él |
| Borrar una base de datos: `docker volume rm`, `docker compose down -v`, `DROP`/`TRUNCATE`, borrar una carpeta `.data/` | Claude dice qué se va, y el hook pide tu confirmación |
| `aiwp-cmds.sh release` (`main` avanza, y el tag `vX.Y.Z` se envía), ejecutado por `/merge --main <project>` | confirmación, y solo a pedido tuyo |
| `aiwp-cmds.sh hotfix`, `hotfix-tag` y `hotfix-down` (la corrección a `main`, su tag de patch, `main` mezclada en `developer`), ejecutados por `/merge --hotfix` | confirmación, tras tu OK a la corrección; la pregunta "¿publicar en producción con la corrección?" viene antes del push de una `main` que despliega sola, y después de él en los demás casos |
| `aiwp-cmds.sh apply --apply` (Terraform en la nube) | confirmación del plan mostrado, y solo a pedido tuyo |
| Borrar, mover o vaciar los datos de Grafana (`tools/observability/.data`), donde sea que corra | confirmación, incluso en un clon |
| `aiwp-cmds.sh deploy` (actualiza el stack final de un proyecto, ejecutado por `/docker-deploy`), `checkpoint`, `developer --create` y `gate --untested` | el hook imprime una advertencia y el modo de permisos decide |
| `aiwp-cmds.sh close --discard` (borrar trabajo no mezclado) | confirmación |
| Una escritura git en `projects/` o en el core, Terraform fuera de `apply`, `git push --no-verify` | rechazada por el hook, con el camino correcto |
| Un subagente en Fable | el hook pide tu confirmación |
| Borrar un proyecto, POC o herramienta entero | Claude muestra el comando; **tú** lo ejecutas |

## Comandos

| Comando | Hace |
| --- | --- |
| `/merge [<work>/<clone>]` | Lleva el trabajo de un clon (sin argumento: el de esta sesión) a `developer`, mediante el gate, escribiendo el `CHANGELOG.md` y moviendo el pedido a `custom/requests/qa/<project>/` con lo que se hizo |
| `/merge --main <project> [instructions]` | El release del proyecto: cada repo de él, cada uno con su propia versión y tag, luego la versión del proyecto en su repo raíz; valida cada pedido de `qa/<project>/` contra el código (la revisión final: las tres preguntas sobre todo desde el último tag, ampliadas según haga falta), pregunta por hallazgo (corregir ahora o un pedido) y avisa de cualquier conflicto que una instrucción cause antes de actuar |
| `/merge --hotfix <project> <description>` | Un error en producción: un clon desde `main`, solo la corrección, el gate contra `main` y una revisión de la corrección, tu OK, luego `main`, la versión de patch `vX.Y.(Z+1)` y su tag cuando indiques publicar, y enseguida `main` mezclada en `developer` (un conflicto pasa por una rama de resolución y por el gate). Mientras `developer` no tenga `main`, el repo queda bloqueado: el `/merge` en su `developer` y su release se rechazan |
| `/commit [--all] [--repo <dir>]` | Un commit por cambio lógico, en un clon o en `custom/` |
| `/push [--repo custom \| <work>/<clone>]` | Hace push de `custom/`, o vuelve a hacer push de un clon cuyo push automático falló |
| `/docker-deploy [developer\|main] [<repo>]` | Actualiza el stack Docker local final de un repo desde `developer` o `main`, etiquetando las imágenes reemplazadas para rollback y sin borrar ningún volumen; solo a pedido tuyo |
| `/validate [folder] [--only <checks>] [--sonar]` | Ejecuta las validaciones en Docker |
| `/draft-request [ideas \| file]` | Arma un pedido funcional a partir de ideas |
| `/request [name \| path]` | Ejecuta el pedido escrito en un archivo |
| `/rules [exclude <name> \| include <name> \| add <subject> \| replace <rule> \| lessons]` | Muestra y cambia las reglas, skills y agentes que carga una sesión (abajo, "Cambiar el propio workspace") |
| `/pilot [auto\|manual]` | Muestra o cambia quién ejecuta las pruebas manuales |
| `/local-env [folder]` | Crea o completa un `.env` rellenado sin mostrar valores (`custom/env/<name>.env` para `docker/`, `docker/sonar/` y una herramienta) |
| `/run-tools [--down [tool...]]` | Inicia las herramientas locales que marques (abajo, "Herramientas locales"); `--down` las detiene |
| `/normalize-projects [<project>... \| --from <url \| folder>]` | Lista el estado de los proyectos, o trae uno al workspace o lo actualiza (abajo, "Proyectos") |

El comando del área de trabajo: `bash scripts/aiwp-cmds.sh --help` (`open`, `run`, `status`, `push`, `close`, `up`, `down`, `deploy`, `rollback`, `gate`, `release`, `hotfix`, `hotfix-tag`, `hotfix-down`, `apply`, `developer`, `checkpoint`, `bring`).

Los comandos propios de Claude Code que más ayudan aquí:

| Comando | Para |
| --- | --- |
| `/rewind` (o Esc dos veces) | deshacer ediciones de archivos y llevar la conversación a un punto anterior |
| `/clear` | empezar otro pedido con el contexto limpio |
| `/effort`, `/model` | cambiar el effort y el modelo |
| `/usage` | ver el costo y el uso de la sesión |

## Revisión

- Una ronda por gate, entre las dos fases, a cargo del subagente `reviewer`: contexto limpio, solo lectura. En `developer` ve solo la diferencia que entra; en `main` (release, hotfix) todo desde el último tag, ampliado a llamadores, dependientes y docs.
- Un `reviewer` por merge, effort `medium` en `developer` y `high` en `main`; un rango demasiado grande para un contexto se divide en partes, en paralelo. El brief lleva lo que autorizaste, y eso nunca es un hallazgo.
- Tres preguntas: lo pedido contra lo hecho (cada regla y criterio, probado o no), lo que fue más allá del pedido (una consecuencia o sin explicación) y lo que existía y se perdió (un comportamiento, una prueba o una protección eliminados o debilitados sin pedido). Solo informa defectos.
- Un **BLOCKER** es solo una hard rule, un defecto de corrección, un cambio fuera del alcance del pedido, un riesgo que un error alcanza o una prueba que el pedido exige ahora; se corrige en el clon, y el gate corre de nuevo. Todo lo demás es un **WARNING**: nunca devuelve la rama, `/merge` lo lista y tú decides.
- Si Claude no está de acuerdo con un hallazgo, trae las dos posiciones y tú decides.

## Pruebas que una persona haría a mano

El modo pertenece a la sesión y cambia con `/pilot`.

| Modo | Quién prueba | Cuándo usarlo |
| --- | --- | --- |
| `auto` (predeterminado) | Claude, verificaciones visuales incluidas, con el navegador que tiene la sesión | casi siempre |
| `manual` | tú: Claude da una lista numerada con lo que cambió, dónde verlo, los pasos y qué reportar, y espera | cuando la prueba necesita tu ojo, un login real o un dispositivo físico |

En ambos modos, las pruebas unitarias, la cobertura, el lint y el escaneo de secretos son de Claude.

## Proyectos

- Cada proyecto es un repositorio git independiente en `projects/`, nunca parte del core. La lista está en `custom/projects.md`.
- **Crear:** pídelo ("crea el proyecto X en projects/client-y"). Claude usa `scripts/init-repo.sh`. La carpeta de un proyecto nuevo es decisión tuya; si no la dices, Claude pregunta.
- **Ramas:** el checkout en `projects/` se queda en `developer`; el trabajo ocurre en un clon bajo `tmp/work/`, en una rama que sale de él y vuelve por el gate. `main` solo avanza cuando pides el release (`/merge --main <project>`, en un clon de release `fix/release-vX-Y-Z`, terminando en `aiwp-cmds.sh release <repo> --tag vX.Y.Z`): un fast-forward a `developer` y el tag de versión. Un error en producción se corrige desde `main` (`/merge --hotfix`), como versión de patch, y luego `main` se mezcla en `developer`. Terraform solo aplica desde `main`, con `aiwp-cmds.sh apply`, a pedido tuyo y con el plan confirmado.
- **Docker local:** `aiwp-cmds.sh up <work>/<clone>` publica la copia de una tarea en su propio grupo `agent_` y nunca sobre el stack final; `aiwp-cmds.sh up <repo>` se rechaza. El stack final solo cambia por orden tuya, con `/docker-deploy` (`aiwp-cmds.sh deploy`), que antes etiqueta las imágenes que reemplaza; `aiwp-cmds.sh rollback <repo>` vuelve a ellas. Una copia no tiene tag de rollback: ejecuta `up` de nuevo.
- **Proyectos del workspace:** la primera línea del `README.md` de cada proyecto (y de cada carpeta de POC) es un marcador con la versión del workspace con la que se normalizó por última vez: `<!-- AI-WORKSPACE-PROJECT 0.1.0 -->`. `bash scripts/aiwp-project-state.sh` muestra el estado de cada uno. Cuando un mensaje nombra un proyecto sin el marcador, o uno del que una versión más nueva del workspace pide algo (`migrations/`), Claude lo dice y pregunta si ejecuta `/normalize-projects <project>`. Decir que no nunca bloquea el pedido; el aviso vuelve la próxima vez que nombres el proyecto. `aiwp-cmds.sh open` y el gate muestran el mismo aviso.
- **Traer un proyecto existente:** `/normalize-projects --from <url | folder>` lo clona en `projects/` (desde una carpeta, vienen sus ramas locales y `origin` apunta a su remoto real; los cambios sin commit allí se listan, ya que un clon no los lleva). Un proyecto clonado a mano o una POC movida a `custom/pocs/` se normaliza igual: `/normalize-projects <project>`.
- **Cómo va una normalización:** primero, cuatro analistas leen un clon nuevo y Claude escribe un plan en `custom/migrations/`, una línea por hallazgo: qué va a tu capa custom (conocimiento de la empresa y del entorno), qué se queda en el proyecto como documentación, qué cambia en él (marcador, "How to test", `.env` ignorado, archivos de instrucciones de otras herramientas eliminados), y las lagunas y alertas de seguridad que solo informa. Tú apruebas, editas o descartas cada línea y eliges el idioma de la documentación. Luego, tras confirmar cada push: `developer` en el remoto, tags de checkpoint `ai-workspace-migration/<date>/developer` y `.../main` en las cabezas antiguas, una rama `feat/ai-workspace-migration` con el plan en commits y la documentación completa, una prueba de la rama contigo, `/merge` en `developer` y el release de `main` (un pull request cuando `main` está protegida). Nunca reescribe código, escribe pruebas ni corrige una brecha de seguridad: las lagunas van a `AI-WORKSPACE-MIGRATION.md` en la raíz del proyecto, y las alertas de seguridad (archivo, línea y tipo, nunca el valor) se te muestran al final. Una POC recibe el mismo análisis y aprobación, con los cambios commiteados en `custom/`.
- **POC o herramienta local:** una POC vive en `custom/pocs/` y se trabaja en un clon de `custom/`, con el gate usando su build como prueba. Una herramienta vive en `tools/`, parte del core, y solo cambia con el producto. Ambas solo necesitan compilar, pasar el escaneo de secretos y tener un README.
- **Puertos:** POCs y stacks de `docker/` desde 20000; herramientas y proyectos en su puerto convencional.
- **Idioma:** se recomienda código en inglés en tus proyectos, no es obligatorio (`rules/rules.md` "Language").
- **Infraestructura:** tú no la dimensionas. Sin un número tuyo, empieza en el menor tamaño que ejecuta la entrega (plan de consumo, un nodo, una región) y lista para crecer: los límites son variables de Terraform, y la documentación del proyecto dice qué señal indica que es hora de escalar y cuánto cuesta el siguiente paso. Si tienes un requisito real (un volumen, un plazo, un tope de presupuesto), dilo en el pedido y se vuelve requisito. Antes de crear un recurso que se factura, Claude da la estimación mensual.
- **Ideas:** una idea aún no lista es un pedido en `custom/requests/` en estado `idea`, en el tamaño ajuste de `templates/request.md` (What, Where, Done when, Effort).

## Herramientas locales

`/run-tools` muestra casillas con las herramientas de esta máquina, agrupadas en dos preguntas (observabilidad y consolas; simuladores), cada una con su URL y estado, e inicia las que marques. Desmarcar una herramienta que está arriba no detiene nada; `/run-tools --down` las detiene.

- Las herramientas de contenedor (observabilidad, los simuladores de login y de Safe Browsing, la consola de Azurite) corren en un solo proyecto compose, `claude-cli-agents-tools`: la consola de contenedores las muestra como un grupo (`tools/compose.yaml`).
- Solo se muestra la consola de contenedores de esta máquina: docker-ce en Linux y WSL con Docker Engine, Colima en macOS. Es un servicio de la máquina: `/run-tools` lo instala (`make install`) o lo inicia.
- La configuración de una herramienta vive en `custom/`: `custom/env/<tool>.env` (`/local-env tools/<tool>`) y `custom/config/<tool>/`. Sin ella la herramienta se lista como "configuration missing" y no inicia; un puerto ocupado se muestra igual.
- Cada inicio etiqueta las imágenes que reemplaza como `<name>:rollback-latest`.
- Una herramienta instalada antes del grupo, aún corriendo en su propio proyecto compose, pasa al grupo en su primer inicio. Un volumen nombrado (el de Azurite) se copia antes al nombre del grupo; el antiguo queda hasta que confirmes su eliminación. Cuando el stack de un proyecto aún usa una de las redes de la herramienta, `/run-tools` dice cuál, no cambia nada, y tú detienes ese stack primero.

## Varias sesiones a la vez

- **Un clon por trabajo.** Cada sesión trabaja en su propio clon bajo `tmp/work/`; dos sesiones no comparten nada salvo el remoto. Dos no pueden abrir la misma rama.
- **El gate por fast-forward.** Si otra sesión mezcló primero, la fase 2 rechaza y el gate recomienza con la base nueva.
- **`scripts/heavy-run.sh`.** Antes de una tarea pesada de CPU o GPU (gráficos, renderizado 3D), lee la temperatura: a 88 °C o más, espera a 85 °C. Las pruebas, los builds y los contenedores corren directamente, sin cola.
- **Un recurso compartido** (un puerto, un proyecto Compose en uso): dos clones del mismo proyecto compiten por los mismos puertos. Inicia el stack de uno a la vez, y dile a la sesión qué ya está corriendo.

## Validar

| Qué | Comando |
| --- | --- |
| Un clon o una carpeta | `/validate tmp/work/<work>/<clone>`, o `bash scripts/validate.sh --path <folder>` |
| Solo algunos checks | `bash scripts/validate.sh --path <dir> --only secrets,markdown` |
| SonarQube, cuando lo quieras | `/validate <dir> --sonar` |

Los checks viven en `docker/compose.yaml`, con versión y digest fijos. Un check que ya pasó para el mismo contenido aparece como `CACHED` y no corre de nuevo; `--no-cache` lo fuerza.

## Cambiar el propio workspace

- **Una sesión nunca cambia el core.** `AGENTS.md`, `rules/`, `scripts/`, `docker/`, `docs/` y `tools/` son de solo lectura: en un workspace instalado sus archivos son de solo lectura en disco, Claude Code rechaza la edición y el hook rechaza la escritura, un `chmod`, un `chown` y un `git init` allí. La raíz del workspace no es un repositorio git: `custom/` y cada proyecto lo son. Tus propias herramientas van a `custom/tools/` (`bash scripts/init-repo.sh --type tool`). Cuando una regla estorba, Claude escribe la propuesta en `custom/docs/lessons.md` y te avisa.
- **Actualizaciones:** una release nueva llega al workspace solo por `aiwp update`, en una terminal sin sesión abierta, que reemplaza solo los archivos del core que cambiaron ([El registro y la actualización](#el-registro-y-la-actualización)). Abrir con `aiwp` solo dice que existe una.
- **Quién cambia el producto:** un pull request al repositorio del producto, mantenido desde su raíz.
- **Tus propias reglas:** `/rules` muestra las reglas que carga una sesión, con el origen de cada una, y apaga reglas, skills y agentes del core, reemplaza una regla del core o agrega las tuyas, en `custom/rules-config.json` y `custom/my-rules/`; el core obligatorio siempre carga. También puedes editar esos archivos a mano. Un cambio llega a las próximas sesiones, nunca a la abierta. Un workspace que aún tiene `custom/rules/`: renómbralo con `git -C custom mv rules my-rules`.
- **Lecciones:** cuando algo sale mal por la forma en que se hizo el trabajo, Claude escribe una línea fechada en `custom/docs/lessons.md`. Ese archivo no se carga en las sesiones. Revísalo de vez en cuando y decide, línea por línea: se vuelve un hook (sin excepción permitida), una frase en una regla, o se descarta.
- **Antes de agregar una regla, pregunta:** ¿Claude ya lo hace bien sin ella? ¿Un hook puede garantizarlo? Si la respuesta a cualquiera es sí, la regla no entra.

## Cuando algo sale mal

| Síntoma | Qué hacer |
| --- | --- |
| Claude editó lo que no debía | `/rewind`, o Esc dos veces; en un clon, `git restore <file>` como último recurso |
| Un comando, una skill o un subagente no aparece | `bash scripts/setup-claude.sh` y reinicia la sesión |
| El hook pregunta o rechaza donde no debería | escríbelo en `custom/docs/lessons.md`; el conjunto está en `scripts/guard-bash.py` (`bash scripts/guard-bash.sh --help`) |
| "NOT pushed" en el clon | el hook de pre-push rechazó (un secreto, un `.env`) o el remoto no respondió: lee la salida, reescribe la rama en el clon si hace falta y `aiwp-cmds.sh push` |
| "The secret scan did not run" | Docker no respondió: inicia Docker y ejecuta `aiwp-cmds.sh push`; el commit queda en el clon hasta entonces |
| La publicación en Docker salió mal | `bash scripts/aiwp-cmds.sh rollback <repo>` vuelve a la imagen anterior del stack final; la copia de una tarea no tiene rollback: ejecuta `up <work>/<clone>` de nuevo |
| `heavy-run.sh` salió con 75 | no corrió nada: la máquina no llegó a 85 °C en 30 minutos. La salida trae la última lectura; ejecútalo de nuevo más tarde |
| El gate rechazó la fase 2 | la base avanzó, o el clon cambió después de la fase 1: el gate corre de nuevo |
| Una regla bloquea la solución más simple | Claude se detiene y muestra las opciones. Puedes pasar por encima de cualquier regla |

## Dónde está cada cosa

| Qué | Dónde |
| --- | --- |
| Lo que vale en toda sesión | `AGENTS.md` |
| Reglas por tema | `rules/*.md` |
| Subagentes y comandos | `rules/agents/`, `rules/skills/` |
| Hooks y permisos | `rules/agents/settings.json`, `scripts/guard-bash.sh`, `scripts/guard-subagent-model.sh`, `scripts/aiwp-cmds.sh` (los hooks de los clones y `Stop`) |
| Scripts | `scripts/README.md` |
| Herramientas de validación | `docker/README.md` |
| Decisiones | `docs/decisions/` |
| Lecciones | `custom/docs/lessons.md` |
| Pedidos escritos | `custom/requests/` (en la capa custom) |
| Pedidos (pendientes, `qa/<project>/`, `done/<project>/`) | `custom/requests/` |
| Empresa: nube, identidad visual, proyectos y puertos | `custom/` (`custom/README.md`) |
| Clones de trabajo | `tmp/work/<work>/` (fuera de git; `aiwp-cmds.sh status`) |
