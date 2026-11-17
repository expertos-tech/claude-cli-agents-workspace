<!-- source: workspace/tools/fable-alert/README.md sha256:9b9df9f7c36b476ec400a37a35d89418679b8e9ff76abd3d1958183fd584d1bc -->

# fable-alert

Alerta visual para Claude Code: mientras Fable está activo, el fondo de la terminal se vuelve rojo oscuro y aparece una banda "FABLE ACTIVE" encima del prompt. También incluye la línea de estado que muestra el modelo, el fragmento de configuración y `ptyrun.py`, que graba lo que Claude Code dibuja al abrirse.

- [Qué es](#qué-es)
- [Cómo funciona](#cómo-funciona)
- [Estructura](#estructura)
- [Cómo instalarlo](#cómo-instalarlo)
- [Cómo ejecutarlo](#cómo-ejecutarlo)
- [Cómo probarlo](#cómo-probarlo)
- [Criterios de aceptación](#criterios-de-aceptación)
- [Personalización](#personalización)
- [Desinstalación](#desinstalación)
- [Limitaciones](#limitaciones)
- [Notas de diseño](#notas-de-diseño)

## Qué es

Un mod de Claude Code (carpeta `plugin/`) más tres piezas de apoyo. El mod existe porque `/model` guarda el modelo elegido como predeterminado de toda sesión nueva. Después de un `/model fable`, cada sesión siguiente puede abrirse en Fable sin ningún aviso en pantalla, y su cuota semanal se agota en pocos días.

No hay instalación por marketplace.

## Cómo funciona

Código en `plugin/hooks/register.tsx`.

1. Dos segundos después de abrirse la sesión (`FIRST_CHECK_MS`), el mod empieza a consultar el modelo activo cada segundo.
2. Si el nombre del modelo contiene `fable` (en mayúsculas o minúsculas), escribe en la terminal la secuencia OSC 11, que cambia el fondo a `#420c0c`, y solo entonces activa el átomo `isFable`, que dibuja la banda. La banda cambia el layout y obliga al prompt a redibujarse sobre cualquier cosa que la escritura haya alterado.
3. Cuando el modelo deja de ser Fable, escribe OSC 111, que restaura el fondo propio de la terminal, y oculta la banda. Fuera de Fable, el mod solo escribe para deshacer un tinte que sigue registrado.
4. El átomo `isFable`, que conserva el host, es el único registro de "fondo pintado": la banda y el tinte salen de él y nunca se desincronizan, y sobrevive a una recarga del mod.
5. Cuando la sesión termina con Fable activo, restaura el fondo antes de cerrar. Con `/clear` o `/resume` el proceso sigue en ejecución, con otro id de sesión y sin un nuevo `session.start`: el mod restaura el fondo, sigue vigilando y vuelve a pintar en el siguiente ciclo si el modelo sigue siendo Fable. Si la sesión termina mientras se escribe el tinte, el mod deshace la escritura, siempre que el proceso siga vivo cuando esta termine.
6. La banda no aparece mientras una encuesta ocupa el espacio encima del prompt.

El comando que escribe el tinte se ejecuta en un proceso hijo sin terminal propia. Por eso el script sube hasta 8 ancestros, encuentra el primero con terminal (`ps -o tty=`) y escribe la secuencia directamente en `/dev/<tty>`.

La línea de estado (`statusline/statusline.sh`) muestra el modelo y la carpeta de la sesión, con `~` en lugar de la carpeta personal. Un modelo cuyo nombre o id contiene `Fable` o `fable` aparece en blanco sobre rojo; los demás, en cian. Necesita `bash` y `jq`.

## Estructura

| Ruta | Qué es |
| --- | --- |
| `plugin/` | El mod: `.claude-plugin/plugin.json`, `hooks/register.tsx`, `types/index.d.ts` y `tests/fable-alert.test.tsx` |
| `statusline/statusline.sh` | Línea de estado con el modelo activo |
| `settings-snippet.json` | Fragmentos de `~/.claude/settings.json`: `statusLine` y `env.CLAUDE_CODE_PLUGIN_DIRS` |
| `tools/ptyrun.py` | Abre Claude Code en una terminal falsa, graba lo que dibuja e informa las escrituras de color de fondo |
| `tests/` | Pruebas en Python de `ptyrun.py`, del script de terminal y de la línea de estado |
| `.coveragerc` | Objetivo de la verificación `coverage` de `scripts/validate.sh` |

## Cómo instalarlo

Requiere Claude Code 2.1.309 o posterior, el mínimo para mods; las pruebas de aquí se ejecutaron en 2.1.314.

Se ejecuta desde la raíz del workspace. Lo que se ejecuta es la copia instalada: cambiar la herramienta no tiene efecto hasta volver a copiarla. Instalado desde una carpeta, el mod se une a una sesión cuando esta se abre y, a partir de ahí, la sesión lo recarga por sí sola cuando cambia un archivo de la copia instalada.

```bash
mkdir -p ~/.claude/mods/fable-alert && cp -R tools/fable-alert/plugin/. ~/.claude/mods/fable-alert/
```

Línea de estado (necesita `jq`):

```bash
cp tools/fable-alert/statusline/statusline.sh ~/.claude/statusline.sh
chmod +x ~/.claude/statusline.sh
```

Configuración. El comando hace una copia de seguridad y fusiona el fragmento con la configuración actual, sin borrar lo que existe; si `env.CLAUDE_CODE_PLUGIN_DIRS` ya tiene un valor, el del fragmento lo reemplaza.

```bash
cp ~/.claude/settings.json ~/.claude/settings.json.bak
jq -s '.[0] * .[1]' ~/.claude/settings.json.bak tools/fable-alert/settings-snippet.json > ~/.claude/settings.json
```

El mod se une a las sesiones abiertas después de esta configuración.

## Cómo ejecutarlo

No hay nada que ejecutar: una vez instalado, el mod actúa en cada sesión nueva. Para ver lo que Claude Code dibuja al abrirse, usa `ptyrun.py` en una carpeta fuera del workspace (consulta la advertencia en [Cómo probarlo](#cómo-probarlo)):

```bash
python3 -I <workspace-root>/tools/fable-alert/tools/ptyrun.py open-default.bin 6
python3 -I <workspace-root>/tools/fable-alert/tools/ptyrun.py open-fable.bin 7 --model fable
```

El primer argumento es el archivo de salida; el segundo, los segundos de grabación; el resto va a `claude`. La terminal falsa es de 120 x 40, y la sesión termina con `SIGTERM`. El informe lista cada escritura de color de fondo (`set (OSC 11)` o `reset (OSC 111)`) y marca `SPLITS A CHARACTER` si alguna cortó un carácter UTF-8 por la mitad, que es lo que rompe una línea. Abrir Claude sin enviar un mensaje no hace ninguna solicitud al modelo.

## Cómo probarlo

Pruebas automatizadas, desde la raíz del workspace. `claude plugin validate` y `claude plugin test` escriben `tsconfig.json` y `.claude-plugin/types/` dentro de la carpeta del plugin, que es de solo lectura en un workspace instalado, así que se ejecutan sobre una copia en `tmp/`:

```bash
rm -rf tmp/fable-alert-plugin && cp -R tools/fable-alert/plugin tmp/fable-alert-plugin && chmod -R u+w tmp/fable-alert-plugin
claude plugin validate tmp/fable-alert-plugin
claude plugin test tmp/fable-alert-plugin
(cd tools/fable-alert && python3 -I -B -m unittest discover -s tests)
bash scripts/validate.sh --path tools/fable-alert
```

- `claude plugin test` ejecuta las 37 pruebas de `plugin/tests/fable-alert.test.tsx`.
- Las pruebas en Python cubren `ptyrun.py` (con un `claude` falso), el script que sube por el árbol de procesos (con un `ps` falso) y la línea de estado. Las 6 pruebas de la línea de estado (AC-11) necesitan `bash` y `jq`: en el contenedor de la verificación `coverage` se omiten, y se ejecutan en el host.
- Las pruebas son opcionales: una herramienta solo tiene que compilar, y `scripts/validate.sh` no mide la cobertura en esta carpeta.

**Cobertura del mod.** `claude plugin test` no tiene opción de cobertura, por lo que el 85 % de `rules/quality.md` no se mide para el mod. En su lugar, el encabezado de `plugin/tests/fable-alert.test.tsx` asocia cada rama de `register.tsx` a una prueba, y una verificación de mutación detectó 22 de 22 inversiones de rama y 13 de 13 mutantes adicionales, sin ninguna guarda sobreviviente. Es una brecha aceptada, ya que se trata de una herramienta local. `ptyrun.py` tiene 98,9 % de cobertura de líneas y 95,4 % de ramas.

**Cobertura de la línea de estado.** La verificación `coverage` no mide bash, y las 6 pruebas de AC-11 se omiten en su contenedor. Una regresión en la línea de estado no hace fallar `validate.sh`: ejecuta el comando en el host (`python3 -I -B -m unittest discover -s tests`). También es una brecha aceptada.

**Verificación en el motor real** (Claude Code 2.1.314, abierto sin prompt): una copia temporal del mod, con la expresión regular cambiada para reaccionar a Opus, sin Fable de por medio, dio exactamente 1 escritura OSC 11 en unos 8 segundos de observación, 1 OSC 111 al salir, ningún carácter cortado y la banda presente. Límites: un cambio de modelo en medio de una sesión y `/resume` se comprueban solo con las pruebas, no en el motor real.

**Prueba visual**, fuera del workspace:

1. Abre `claude` en una carpeta fuera del workspace. Dentro de él, `rules/agents/settings.json` define `availableModels` sin Fable.
2. Sin enviar un mensaje, ejecuta `/model fable`: el fondo se vuelve rojo oscuro y la banda aparece en menos de un segundo.
3. Vuelve al modelo que era tu predeterminado antes, que no es necesariamente Opus, con `/model <model>`. `/model` guarda la elección como predeterminada de las sesiones nuevas: olvidar este paso deja cada sesión nueva en Fable.

## Criterios de aceptación

Los ids aparecen en los nombres de las pruebas.

| Id | Criterio |
| --- | --- |
| AC-1 | Un modelo con `fable` en el nombre, en mayúsculas o minúsculas: el tinte se escribe una vez y la banda aparece |
| AC-2 | Otro modelo: no se escribe nada y la banda no aparece |
| AC-3 | Cambiar entre Fable y otro modelo cambia el tinte y la banda en menos de un segundo, incluida una banda ya dibujada |
| AC-4 | Salir de la sesión detiene la vigilancia; en Fable restaura el tinte, en otro modelo no escribe nada; un ciclo en curso no hace nada |
| AC-5 | `/clear` restaura el tinte, sigue vigilando y vuelve a pintar si el modelo sigue siendo Fable |
| AC-6 | No se lee ni se escribe nada antes de `FIRST_CHECK_MS` |
| AC-7 | Un fallo al leer el modelo, escribir el tinte o restaurarlo (al salir o con `/clear`) no rompe la sesión; el siguiente ciclo vuelve a intentarlo, salvo el restablecimiento que falló |
| AC-8 | Una encuesta oculta la banda, incluso en Fable |
| AC-9 | Condiciones de carrera: ciclos superpuestos no escriben dos veces; que la sesión termine mientras se lee el modelo, se escribe el tinte o se escribe el restablecimiento no deja el tinte incorrecto; un deshacer que falla queda contenido |
| AC-10 | Script de terminal: sube hasta 8 ancestros, omite `??` y una terminal vacía, se detiene en el pid 1 o sin padre, prueba el siguiente si la escritura falla; sale con 0 cuando escribe y con 1 sin terminal |
| AC-11 | Línea de estado: resaltado de Fable (`Fable` o `fable` en el nombre o el id), cian para los demás, `~` en lugar de la carpeta personal, campos ausentes con valor de respaldo, JSON inválido sale con error y sin salida |
| AC-12 | `ptyrun.py` graba lo que `claude` dibuja, pasa los argumentos, termina con `SIGTERM`, responde a las consultas de la terminal e informa cada escritura de color de fondo |
| AC-13 | `splits_utf8` señala la escritura que cae en medio de un carácter UTF-8 |
| AC-14 | `ptyrun.py` con argumentos o entorno inválidos (tiempo, `claude` ausente del `PATH`, carpeta de salida inexistente o sin permiso) sale con un mensaje, sin traceback y sin bloquearse |
| AC-15 | `/resume` mantiene la vigilancia, igual que `/clear` |
| AC-16 | El átomo es el único registro de un tinte pintado: banda y tinte no se desincronizan después de `/clear`, del fin de la sesión, de un deshacer en medio de la escritura, de un ciclo y el fin al mismo tiempo ni del estado dejado por una recarga; en Fable, que el host borre el estado solo hace que el mod vuelva a pintar |
| AC-17 | Una escritura cuyo proceso sale con código distinto de cero (sin terminal): la banda aparece y la escritura no se repite cada segundo |
| AC-18 | Un fallo al leer el estado al final de la sesión cuenta como tinte pintado: el mod intenta restaurar el tinte, y la salida continúa |

## Personalización

Al principio de `plugin/hooks/register.tsx`: `TINT` (color de fondo) y `FIRST_CHECK_MS` (espera antes de la primera verificación). El texto de la banda está al final del archivo. Las pruebas tienen estos valores escritos a mano: al cambiar `TINT` o `FIRST_CHECK_MS`, cambia también `SET_TINT` y `FIRST_CHECK_MS` en `plugin/tests/fable-alert.test.tsx`; al cambiar el título "FABLE ACTIVE", cambia lo que busca la prueba. Luego ejecuta las pruebas y vuelve a copiar el mod en `~/.claude/mods/fable-alert/`.

## Desinstalación

```bash
cp ~/.claude/settings.json ~/.claude/settings.json.bak
jq 'del(.env.CLAUDE_CODE_PLUGIN_DIRS, .statusLine)' ~/.claude/settings.json.bak > ~/.claude/settings.json
rm -r ~/.claude/mods/fable-alert ~/.claude/statusline.sh
```

Si un bloqueo deja la terminal con el fondo rojo:

```bash
printf '\033]111\007'
```

## Limitaciones

- La API de mods de Claude Code está en acceso anticipado y puede cambiar entre versiones.
- La terminal debe aceptar OSC 11 y OSC 111. Probado en Ghostty 1.3.1.
- Si no se encuentra ninguna terminal en los 8 ancestros, el fondo no cambia, la banda aparece de todos modos y la escritura no se repite (AC-17).
- Un restablecimiento del tinte que falla, al salir, con `/clear` o con `/resume`, no se repite: el fondo rojo puede quedarse hasta el comando de recuperación de arriba (AC-7).
- Si el proceso se cierra justo después de una escritura en curso, el tinte puede quedarse hasta el mismo comando. La ventana es corta, y AC-9 solo comprueba el caso con el proceso vivo. El fin de la sesión no espera esa escritura a propósito: una llamada trabada no debe retener la salida de Claude.
- Si el host borra el estado con el tinte pintado y el modelo ya no es Fable, el mod no sabe que pintó, y el tinte se queda hasta el mismo comando.
- El script de terminal usa `ps -o tty=`, disponible en macOS y otros sistemas Unix.
- La línea de estado queda fuera de la cobertura automática de `validate.sh` (consulta [Cómo probarlo](#cómo-probarlo)).
- Los archivos `.bin` de `ptyrun.py` contienen todo lo dibujado en la pantalla. El `.gitignore` de esta carpeta los ignora; no los compartas.

## Notas de diseño

- **Ninguna escritura al abrir la sesión.** Escribir en la terminal mientras la sesión dibuja su primera pantalla puede caer en medio de una línea del prompt y cortar un carácter por la mitad. Por eso, fuera de Fable, el mod solo escribe para deshacer un tinte que sigue registrado, espera a que termine el dibujo inicial y redibuja el prompt después de cada escritura. `ptyrun.py` lo confirma en aperturas con Opus y con Fable.
- **El temporizador se detiene al final de la sesión**, salvo con `/clear` o `/resume`, y una escritura en curso al final se deshace, de modo que salir con Fable activo no deja la terminal en rojo.
- **`/resume` mantiene viva la alerta**: el fin de la sesión no detiene los temporizadores con `/clear` o `/resume`, ya que ninguna sesión nueva los reinicia.
- **Un solo registro para banda y tinte.** El estado del tinte vive solo en el átomo del host, nunca en una variable del mod, de modo que la banda y el tinte no pueden divergir.
