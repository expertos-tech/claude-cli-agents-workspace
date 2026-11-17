<!-- source: workspace/docs/usage.md sha256:fba8f7459a8e08b7ea785807b75c521ce3415fad82081ed806860fab053ebd94 -->

# Usar el workspace

Guía del día a día. El diseño y sus razones están en [overview.md](overview.md) y en la [decisión 0001](../../../../workspace/docs/decisions/0001-base-design.md).

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

Tú dices **qué** quieres; Claude decide **cómo** y lo hace en un clon aislado, donde todo está permitido. Las verificaciones pesadas y las preguntas quedan en un solo lugar: el gate que lleva el trabajo a la base.

## Antes de la primera sesión

Una vez por workspace:

| Paso | Comando |
| --- | --- |
| Crear el workspace: el core de solo lectura, la capa custom en `custom/` y la carpeta `.claude/` | lo hace el instalador (pide la carpeta); otro: `aiwp new <carpeta>` (pide la URL del repositorio de la capa custom, o `--custom <url>`; una respuesta vacía crea uno local) |
| Comprobar Docker, que usan las validaciones | `docker info` |
| Crear el `.env` rellenado de las herramientas de validación, `custom/env/docker.env` | `/local-env docker`, en una sesión; después rellena los valores en un editor |
| Opcional: instalar el modo de agente único | `ln -sf "<workspace>/scripts/single-claude.sh" ~/.local/bin/single-claude` |

A partir de ahí `.claude/` se mantiene actualizada sola: un hook de inicio de sesión ejecuta `setup-claude.sh`.

Para eliminar un workspace, devuelve antes el permiso de escritura, ya que el núcleo es de solo lectura: `chmod -R u+w <folder> && rm -rf <folder>`. Haz push de `custom/` y de tus proyectos antes: se van con él.

## Abrir una sesión

```bash
cd <workspace> && aiwp
```

`aiwp` comprueba si hay una release nueva (como mucho una vez al día, límite de 5 s; sin red sigue) y, cuando la hay, imprime "A new workspace version X was detected (this workspace: Y). Run `aiwp update` to update; opening this workspace on Y." Después ejecuta `setup-claude.sh` e inicia `claude` en la versión actual, con los argumentos que pases después de `--` (`aiwp -- --resume`). Abrir nunca actualiza. Tras una actualización interrumpida, se niega a abrir hasta que `aiwp repair` (o `aiwp update`) restaure el workspace. `claude` solo también abre el workspace: cuando hay una release nueva, el inicio de sesión lo avisa, y Claude te dice que cierres la sesión y ejecutes `aiwp update` en una terminal.

**Nunca dentro de una sesión.** Desde una sesión de Claude Code (su herramienta Bash, un hook) `aiwp` rechaza `update`, `rollback`, `repair`, `forget`, la apertura y un `new` sobre una carpeta registrada, y `guard-bash` también los rechaza: cambian las reglas de la sesión abierta o inician `claude` dentro de ella. `aiwp list`, `check`, `version` y `--help` funcionan en cualquier lugar. Un comando desconocido es un error de uso; los argumentos para `claude` van después de `--`.

- **Siempre en la raíz del workspace**, incluso para trabajar en un proyecto: ahí es donde se aplican `AGENTS.md`, las reglas y los hooks.
- **Una sesión por pedido.** Cuando el tema termina, usa `/clear` o abre otra sesión. Una sesión larga sale cara: cada paso vuelve a leer todo el contexto.
- **Effort:** `medium` sirve para trabajo con alcance claro. Súbelo a `high` con `/effort high` cuando el cambio toca un hook, un permiso, un merge o la seguridad, o para depurar una falla difícil. Para un único paso difícil, escribe `ultrathink` en el prompt.
- **Nombre de la sesión:** `/prompt <file>` da a la sesión el nombre del proyecto, numerado (`billing-api-1`, `billing-api-2`...), a partir de la línea `**Project:**` del pedido: el número es uno más que el mayor entre las sesiones abiertas de ese proyecto. Sin `/prompt`, Claude Code elige un título por su cuenta; `/rename <name>` lo cambia.
- **Lengua:** Claude responde en la lengua en que escribes.

## El registro y la actualización

La carpeta de datos guarda `workspaces.json`, con todos los workspaces instalados (ruta, versión, creado, actualizado). `aiwp new` registra un workspace, y la primera ejecución de `aiwp` en uno que no está registrado lo añade.

| Comando | Qué hace |
| --- | --- |
| `aiwp list` | Cada workspace registrado con su versión y estado: al día, actualización disponible (X), core cambiado, carpeta ausente, fijado en X, interrumpido a la mitad |
| `aiwp forget <carpeta>` | Quita la entrada (de una carpeta que ya no está, o de una que ya no actualizas); nunca toca la carpeta |
| `aiwp update` | Lista los workspaces registrados (número, versión, estado, ruta) y pregunta `[1] Update all` (el predeterminado), `[2] Choose which` (números) o `[3] Cancel` |
| `aiwp update <carpeta>` | Actualiza solo ese workspace, sin preguntar |
| `aiwp update --all` | Actualiza todos los workspaces registrados, sin preguntar |

La actualización ocurre solo por comando, en una terminal, sin sesión abierta. `aiwp update` lleva la carpeta de datos a la release más reciente una vez, después actualiza cada workspace elegido: lo verifica contra el manifiesto, guarda lo que reemplaza en `.aiwp/backup/<versión>/`, escribe un diario, reemplaza los archivos por renombrado y muestra el changelog. Un workspace con el core cambiado o con la carpeta ausente se omite y se informa, y los demás siguen; una tabla resumen termina la ejecución.

- **Workspaces fijados** (tras un `aiwp rollback`) quedan como están con `--all` y con Update all; elegir uno por número o por carpeta lo actualiza y quita la fijación.
- **Sin terminal:** hace falta `--all` o una carpeta; si no, es un error de uso (salida 2).
- **Un `claude` en ejecución:** antes de reemplazar un workspace donde corre un proceso `claude` (su carpeta actual dentro del workspace), nombra el pid y pregunta. Con `--all` omite ese workspace, salvo que añadas `--force`.
- **Código de salida 1** cuando se omitió un workspace por core cambiado, por un `claude` en ejecución o por un error.

## Hacer un pedido

**Un pedido simple:** escríbelo con palabras.

```text
corrige el enlace roto en el README de my-project
```

**Un pedido funcional (una funcionalidad, un sistema):** el formulario es `templates/request.md`. Sus encabezados y etiquetas en negrita quedan en inglés; el contenido va en tu lengua. Hay dos formas de completarlo.

| Forma | Cómo |
| --- | --- |
| A partir de ideas sueltas | `/draft-prompt quiero un informe mensual de...`; Claude pregunta solo lo que bloquea, marca el resto como "assumed decision" y lo guarda en `custom/prompts/` |
| Tú mismo | copia `templates/request.md` a `tmp/prompt.md` y complétalo |

Luego `/prompt <file>` lee `custom/prompts/<file>`; `/prompt` solo lee `tmp/prompt.md`.

- Los pedidos de `/draft-prompt` viven en `custom/prompts/`, dentro de la capa custom, un repositorio git propio: el historial de los pedidos queda versionado allí.
- Un pedido entregado pasa a `custom/prompts/archive/`. Lo que está en la raíz de `custom/prompts/` todavía tiene que ejecutarse.
- `/draft-prompt` hace commit y push del pedido que creó, en cada versión. El resto (archivar el pedido entregado, el pedido de continuación de una ola) entra en el checkpoint de la ola ([Olas](#olas-checkpoint-merge-y-continuación)).
- `aiwp new` monta `custom/`: clona el repositorio cuya URL indiques (uno vacío recibe un esqueleto) o crea uno local. Si la carpeta falta después, la sesión lo avisa al inicio, y `bash scripts/setup-claude.sh --custom-repo <url>` en una terminal la clona.

El pedido escrito es tan grande como lo que pediste. `/draft-prompt` elige uno de tres tamaños antes de escribir, y dice cuál:

| Tamaño | Cuándo | Qué sale | Tope |
| --- | --- | --- | --- |
| Ajuste | cambia un comportamiento de algo que existe ("agrega un overlay de confirmación") | unas pocas líneas: qué, dónde, listo cuando, effort | unas 120 palabras |
| Funcionalidad | una capacidad nueva en un sistema que existe | objetivo, reglas, criterios de aceptación, fuera de alcance, pasos y effort | unas 400 palabras, como máximo 8 reglas |
| Sistema | un sistema nuevo, arquitectura, infra, integración externa, datos personales | el formulario completo | sin tope |

- Una regla que no enunciaste no se escribe, salvo que sin ella se pudieran construir dos cosas distintas.
- ¿Demasiado grande o demasiado chico? Responde "más chico" o "más grande".
- Un pedido de tamaño ajuste puede ir directo a la sesión, sin archivo.

**Effort por paso.** Todo pedido escrito lleva el effort que pide cada paso: una línea en el tamaño ajuste, y la tabla "Steps and effort" en los demás. Tú configuras la sesión con `/effort <level>` antes de cada paso; Claude dice al inicio de cada uno qué nivel pide y pasa ese nivel a los subagentes del paso.

| Effort | Cuándo |
| --- | --- |
| `low` | un cambio mecánico: un texto, una etiqueta, un renombrado |
| `medium` | un alcance claro; el valor por defecto |
| `high` | donde la verificación importa: seguridad, datos personales, dinero, permisos, migración, un paso destructivo, un bug en código que existe |

Qué esperar:

- Claude pregunta los **huecos funcionales**, todos juntos, antes de empezar. No pide tu aprobación para decisiones técnicas.
- Una pregunta o un pedido de solo lectura se responde directamente, sin rama y sin prueba.
- Al final, un resumen corto: qué cambió, qué se verificó y cómo, qué falta. Una verificación que falla se informa como falla, con su salida.

## Dónde ocurre el trabajo

- **Una pregunta o lectura:** Claude responde; no se abre nada.
- **Un cambio en un proyecto o en una POC:** Claude abre un clon en `tmp/work/<date>-<subject>/<repo>/` (`bash scripts/aiwp-cmds.sh open`), indica la ruta y trabaja solo allí. En el clon todo está permitido: commit, rebase, reset, borrar, levantar Docker. Cada commit va al remoto por sí solo, tras un escaneo de secretos de los commits que salen; un commit con un secreto o un `.env` se queda en el clon.
- **Llevarlo a la base:** `/merge [<work>/<clone>]`; sin argumento, el clon de esta sesión. `/merge` integra `developer` en el clon y escribe la versión del `CHANGELOG.md` del proyecto (`## [X.Y.Z] - Unreleased`; las reglas de versión están en `rules/docs.md`) antes del gate. El gate actualiza `developer`, ejecuta la suite completa y el `validate.sh` completo, escanea en busca de secretos cada commit entrante, escribe la auditoría de lo que sale de la base (archivos borrados o renombrados hacia fuera, pruebas eliminadas o desactivadas, SQL destructivo, infra, dependencias) y pide una revisión contra el pedido. Solo te pregunta por lo que el pedido no explica. Luego `developer` avanza por fast-forward exactamente al commit que pasó, y el clon se puede cerrar (`aiwp-cmds.sh close`).
- **`projects/` siempre se queda en `developer`.** Nadie edita allí; solo el gate mueve la base.

## Olas: checkpoint, merge y continuación

Una ola es cada paso de un plan por pasos (la tabla "Steps and effort" del pedido). Un pedido con un paso, o ninguno, es una ola, que se cierra al terminar. Una pregunta o lectura no abre ninguna ola.

- **Una parte madura va a la base de inmediato**, mediante el gate, sin esperar al final de la ola. Con una base que publica en producción, el gate pregunta antes del merge. Una rama de migración también espera tu orden.
- **Cuando la ola se cierra**, Claude:
  1. hace el checkpoint: un commit en el clon, que va al remoto por sí solo (`aiwp-cmds.sh status` muestra `not-pushed=0`);
  2. escribe el pedido de continuación en `custom/prompts/`, en el formato de `templates/request.md`: dónde se detuvo (el trabajo, el clon, la rama y el sha), decisiones tomadas, puntos abiertos y los siguientes pasos con su effort. El pedido que estaba en ejecución pasa a `custom/prompts/archive/`;
  3. termina la respuesta con un cuadro destacado: qué se hizo, qué se verificó, qué falta y la ruta del pedido de continuación. Tras el cuadro la sesión se detiene; la siguiente ola empieza en una sesión nueva, con `/prompt <file>`.
- La sesión no termina su respuesta con un commit que falta en el remoto: un hook la hace intentarlo de nuevo o decir por qué no pudo.

Regla completa: `rules/git.md`, secciones "Gate" y "Waves".

## Lo que Claude te pregunta

El resto sigue el modo de permisos de Claude Code: el modo auto juzga qué es destructivo.

| Situación | Qué ocurre |
| --- | --- |
| Un gate con algo que el pedido no explica, una destrucción fuera de la máquina o una base que publica en producción | una pregunta, en una sola ronda, antes del merge |
| Borrar una base de datos: `docker volume rm`, `docker compose down -v`, `DROP`/`TRUNCATE`, borrar una carpeta `.data/` | Claude dice qué se va, y el hook pide tu confirmación |
| `aiwp-cmds.sh release` (`main` se mueve, y se envía el tag `vX.Y.Z`), ejecutado por `/merge --main <repo>` | confirmación, y solo a pedido tuyo |
| `aiwp-cmds.sh apply --apply` (Terraform en la nube) | confirmación del plan mostrado, y solo a pedido tuyo |
| `aiwp-cmds.sh close --discard` (borrar trabajo sin merge) | confirmación |
| Una escritura git en `projects/` o en el núcleo, Terraform fuera de `apply`, `git push --no-verify` | rechazado por el hook, con la forma correcta |
| Un subagente en Fable | el hook pide tu confirmación |
| Borrar un proyecto, una POC o una herramienta completa | Claude muestra el comando; **tú** lo ejecutas |

## Comandos

| Comando | Hace |
| --- | --- |
| `/merge [<work>/<clone>]` | Lleva el trabajo de un clon (sin argumento: el de esta sesión) a `developer`, mediante el gate, escribiendo el `CHANGELOG.md` |
| `/merge --main <repo>` | El release: un clon de release `fix/release-vX-Y-Z`, una verificación completa en contexto limpio, correcciones, el `CHANGELOG.md` fechado, el gate hacia `developer`, luego `main` y el tag `vX.Y.Z` |
| `/commit [--all] [--repo <dir>]` | Un commit por cambio lógico, en un clon o en `custom/` |
| `/push [--repo custom \| <work>/<clone>]` | Hace push de `custom/`, o vuelve a hacer push de un clon cuyo push automático falló |
| `/validate [folder] [--only <checks>] [--sonar]` | Ejecuta las validaciones en Docker |
| `/draft-prompt [ideas \| file]` | Arma un pedido funcional a partir de ideas |
| `/prompt [name \| path]` | Ejecuta el pedido escrito en un archivo |
| `/pilot [auto\|manual]` | Muestra o cambia quién ejecuta las pruebas manuales |
| `/local-env [folder]` | Crea o completa un `.env` rellenado sin mostrar valores (`custom/env/<name>.env` para `docker/`, `docker/sonar/` y una herramienta) |
| `/normalize-projects [<project>... \| --from <url \| folder>]` | Lista el estado de los proyectos, o trae uno al workspace o lo actualiza (abajo, "Proyectos") |

El comando del área de trabajo: `bash scripts/aiwp-cmds.sh --help` (`open`, `run`, `status`, `push`, `close`, `up`, `rollback`, `gate`, `release`, `apply`, `developer`, `checkpoint`, `bring`).

Los comandos propios de Claude Code que más ayudan aquí:

| Comando | Para |
| --- | --- |
| `/rewind` (o Esc dos veces) | deshacer ediciones de archivos y llevar la conversación a un punto anterior |
| `/clear` | empezar otro pedido con el contexto limpio |
| `/effort`, `/model` | cambiar el effort y el modelo |
| `/usage` | ver el costo y el uso de la sesión |

## Revisión

- Una ronda por gate, entre las dos fases, a cargo del subagente `reviewer`: contexto limpio, solo lectura.
- Clasifica cada ítem de la auditoría y cada criterio de aceptación (pedido, consecuencia del pedido, sin explicación) e informa solo defectos de corrección, de seguridad o de pérdida de datos, un criterio no cumplido o no demostrado, una prueba eliminada sin motivo y una protección más débil.
- Un **BLOCKER** se corrige en el clon, y el gate se ejecuta de nuevo. Un **RECOMMENDED** nunca devuelve la rama.
- Si Claude no está de acuerdo con un hallazgo, presenta ambas posiciones y tú decides.

## Pruebas que una persona haría a mano

El modo pertenece a la sesión y cambia con `/pilot`.

| Modo | Quién prueba | Cuándo usarlo |
| --- | --- | --- |
| `auto` (por defecto) | Claude, verificaciones visuales incluidas, con el navegador que tenga la sesión | casi siempre |
| `manual` | tú: Claude da una lista numerada con lo que cambió, dónde verlo, los pasos y qué informar de vuelta, y espera | cuando la prueba necesita tu ojo, un login real o un dispositivo físico |

En ambos modos, las pruebas unitarias, la cobertura, el lint y el escaneo de secretos son de Claude.

## Proyectos

- Cada proyecto es un repositorio git independiente en `projects/`, nunca parte del núcleo. La lista está en `custom/projects.md`.
- **Crear:** pídelo ("crea el proyecto X en projects/client-y"). Claude usa `scripts/init-repo.sh`. La carpeta de un proyecto nuevo es decisión tuya; si no la dices, Claude pregunta.
- **Ramas:** el checkout en `projects/` se queda en `developer`; el trabajo ocurre en un clon bajo `tmp/work/`, en una rama que sale de él y vuelve mediante el gate. `main` se mueve solo cuando pides el release (`/merge --main <repo>`, en un clon de release `fix/release-vX-Y-Z`, que termina en `aiwp-cmds.sh release <repo> --tag vX.Y.Z`): un fast-forward a `developer` y el tag de la versión. Terraform aplica solo desde `main`, con `aiwp-cmds.sh apply`, a pedido tuyo y con el plan confirmado.
- **Docker local:** `aiwp-cmds.sh up` publica y primero etiqueta las imágenes que va a reemplazar; `aiwp-cmds.sh rollback` vuelve a ellas.
- **Proyectos del workspace:** la primera línea del `README.md` de cada proyecto (y de cada carpeta de POC) es un marcador con la versión del workspace de la última normalización: `<!-- AI-WORKSPACE-PROJECT 0.1.0 -->`. `bash scripts/aiwp-project-state.sh` muestra el estado de cada uno. Cuando un mensaje nombra un proyecto sin el marcador, o uno al que una versión más nueva del workspace le pide algo (`migrations/`), Claude lo dice y pregunta si ejecutar `/normalize-projects <project>`. Decir que no nunca bloquea el pedido; el aviso vuelve la próxima vez que nombres el proyecto. `aiwp-cmds.sh open` y el gate muestran el mismo aviso.
- **Traer un proyecto existente:** `/normalize-projects --from <url | folder>` lo clona en `projects/` (desde una carpeta, vienen sus ramas locales y `origin` apunta a su remoto real; los cambios sin commit allí se listan, porque un clon no los lleva). Un proyecto clonado a mano o una POC movida a `custom/pocs/` se normaliza igual: `/normalize-projects <project>`.
- **Cómo es una normalización:** primero, cuatro analistas leen un clon nuevo y Claude escribe un plan en `custom/migrations/`, una línea por hallazgo: lo que va a tu capa custom (conocimiento de la empresa y de los entornos), lo que queda en el proyecto como documentación, lo que cambia en él (marcador, "How to test", `.env` ignorado, archivos de instrucciones de otras herramientas eliminados), y las brechas y alertas de seguridad que solo informa. Apruebas, editas o descartas cada línea y eliges el idioma de la documentación. Después, tras confirmar cada push: `developer` en el remoto, tags de checkpoint `ai-workspace-migration/<date>/developer` y `.../main` en las puntas antiguas, una rama `feat/ai-workspace-migration` con el plan en commits y la documentación completa, una prueba de la rama contigo, `/merge` en `developer` y el release de `main` (un pull request cuando `main` está protegida). Nunca reescribe código, escribe pruebas ni corrige una brecha de seguridad: las brechas van a `AI-WORKSPACE-MIGRATION.md` en la raíz del proyecto, y las alertas de seguridad (archivo, línea y tipo, nunca el valor) se te muestran al final. Una POC recibe el mismo análisis y aprobación, con los cambios en commits de `custom/`.
- **POC o herramienta local:** una POC vive en `custom/pocs/` y se trabaja en un clon de `custom/`, con el gate usando su build como prueba. Una herramienta vive en `tools/`, parte del núcleo, y solo cambia con el producto. A ambas les basta compilar, pasar el escaneo de secretos y tener un README.
- **Puertos:** POCs y stacks de `docker/` desde 20000 hacia arriba; herramientas y proyectos en su puerto convencional.
- **Lengua:** se recomienda código en inglés en tus proyectos, no es obligatorio (`rules/rules.md` "Language").
- **Infraestructura:** tú no la dimensionas. Sin un número tuyo, empieza en el tamaño más chico que ejecute la entrega (plan de consumo, un nodo, una región) y lista para crecer: los límites son variables de Terraform, y la documentación del proyecto dice qué señal indica que es hora de escalar y cuánto cuesta el siguiente paso. Si tienes un requisito real (un volumen, un plazo, un tope de presupuesto), dilo en el pedido y se convierte en requisito. Antes de crear un recurso que se factura, Claude da la estimación mensual.
- **Backlog:** las ideas que todavía no se convirtieron en pedido van a `custom/backlog/`, un ítem por archivo, a partir de `templates/backlog-item.md`.

## Varias sesiones a la vez

- **Un clon por trabajo.** Cada sesión trabaja en su propio clon bajo `tmp/work/`; dos sesiones no comparten nada más que el remoto. Dos no pueden abrir la misma rama.
- **El gate por fast-forward.** Si otra sesión hizo merge antes, la fase 2 se rechaza y el gate empieza de nuevo con la base nueva.
- **`scripts/heavy-run.sh`.** Antes de una tarea pesada de CPU o GPU (gráficos, renderizado 3D), lee la temperatura: con 88 °C o más, espera a 85 °C. Las pruebas, los builds y los contenedores corren directamente, sin cola.
- **Un recurso compartido** (un puerto, un proyecto de Compose en uso): dos clones del mismo proyecto compiten por los mismos puertos. Levanta el stack de uno por vez, y dile a la sesión lo que ya está corriendo.

## Validar

| Qué | Comando |
| --- | --- |
| Un clon o una carpeta | `/validate tmp/work/<work>/<clone>`, o `bash scripts/validate.sh --path <folder>` |
| Solo algunas verificaciones | `bash scripts/validate.sh --path <dir> --only secrets,markdown` |
| SonarQube, cuando lo quieras | `/validate <dir> --sonar` |

Las verificaciones viven en `docker/compose.yaml`, con versión y digest fijos. Una verificación que ya pasó para el mismo contenido aparece como `CACHED` y no se ejecuta de nuevo; `--no-cache` la fuerza.

## Cambiar el propio workspace

- **Una sesión nunca cambia el núcleo.** `AGENTS.md`, `rules/`, `scripts/`, `docker/`, `docs/` y `tools/` son de solo lectura: en un workspace instalado sus archivos son de solo lectura en disco, Claude Code rechaza la edición y el hook rechaza la escritura, un `chmod`, un `chown` y un `git init` allí. La raíz del workspace no es un repositorio git: `custom/` y cada proyecto sí lo son. Tus propias herramientas van a `custom/tools/` (`bash scripts/init-repo.sh --type tool`). Cuando una regla estorba, Claude escribe la propuesta en `custom/docs/lessons.md` y te avisa.
- **Actualizaciones:** una nueva versión llega al workspace solo mediante `aiwp update`, en una terminal sin sesión abierta, que reemplaza solo los archivos del núcleo que cambiaron ([El registro y la actualización](#el-registro-y-la-actualización)). Abrir con `aiwp` solo avisa de que existe una.
- **Quién cambia el producto:** un pull request al repositorio del producto, mantenido desde su raíz.
- **Tus propias reglas:** agrégalas en `custom/rules/`; llegan a las sesiones siguientes.
- **Lecciones:** cuando algo sale mal por la forma en que se hizo el trabajo, Claude escribe una línea con fecha en `custom/docs/lessons.md`. Ese archivo no se carga en las sesiones. Revísalo de vez en cuando y decide, línea por línea: se convierte en un hook (sin excepción permitida), en una frase de una regla, o se va.
- **Antes de agregar una regla, pregúntate:** ¿Claude ya lo hace bien sin ella? ¿Un hook puede garantizarlo? Si la respuesta a cualquiera de las dos es sí, la regla no entra.

## Cuando algo sale mal

| Síntoma | Qué hacer |
| --- | --- |
| Claude editó lo que no debía | `/rewind`, o Esc dos veces; en un clon, `git restore <file>` como último recurso |
| Un comando, una skill o un subagente no aparece | `bash scripts/setup-claude.sh` y reinicia la sesión |
| El hook pregunta o rechaza donde no debería | anótalo en `custom/docs/lessons.md`; el conjunto está en `scripts/guard-bash.py` (`bash scripts/guard-bash.sh --help`) |
| "NOT pushed" en el clon | el hook pre-push rechazó (un secreto, un `.env`) o el remoto no respondió: lee la salida, reescribe la rama en el clon si hace falta, y `aiwp-cmds.sh push` |
| "The secret scan did not run" | Docker no respondió: levanta Docker y ejecuta `aiwp-cmds.sh push`; el commit se queda en el clon hasta entonces |
| La publicación en Docker salió mal | `bash scripts/aiwp-cmds.sh rollback <work>/<clone>` (o `<repo>`) vuelve a la imagen anterior |
| `heavy-run.sh` salió con 75 | no se ejecutó nada: la máquina no llegó a 85 °C en 30 minutos. La salida tiene la última lectura; ejecútalo de nuevo más tarde |
| El gate rechazó la fase 2 | la base se movió, o el clon cambió después de la fase 1: el gate se ejecuta de nuevo |
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
| Pedidos escritos | `custom/prompts/` (en la capa custom) |
| Backlog | `custom/backlog/` |
| Empresa: nube, identidad visual, proyectos y puertos | `custom/` (`custom/README.md`) |
| Clones de trabajo | `tmp/work/<work>/` (fuera de git; `aiwp-cmds.sh status`) |
