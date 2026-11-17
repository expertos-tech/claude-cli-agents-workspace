<!-- source: workspace/tools/claude-usage/README.md sha256:abaeaefa883640b119a4e75de72d167252418d2b81a7c53c5e067589e454570b -->

# claude-usage

- [Qué es](#qué-es)
- [Cómo ejecutarlo](#cómo-ejecutarlo)
- [Qué lee y qué imprime](#qué-lee-y-qué-imprime)
- [Cómo probarlo](#cómo-probarlo)
- [Criterios de aceptación](#criterios-de-aceptación)

## Qué es

Un script de un solo archivo, que usa solo la biblioteca estándar de Python, que lee las transcripciones locales de las sesiones de Claude Code y muestra cuánto se usó cada modelo. Cuenta solo las sesiones de esta máquina. El modelo de cada respuesta proviene de la propia respuesta de la API, el mismo dato con el que se cuentan los límites del plan. Sirve, por ejemplo, para ver cuándo cambió el modelo predeterminado.

## Cómo ejecutarlo

No hay nada que instalar. Se ejecuta desde la raíz del workspace, con Python 3.9 o posterior:

```bash
# Respuestas y tokens por día y por modelo
python3 -I tools/claude-usage/claude_usage.py daily --since 2026-11-16T04:59

# Una línea por sesión, de la que generó más tokens a la que generó menos
python3 -I tools/claude-usage/claude_usage.py sessions --since 2026-11-16 --sort tokens

# Modelo de la primera respuesta de cada sesión nueva, por día
python3 -I tools/claude-usage/claude_usage.py default-model
```

| Opción | Comandos | Predeterminado |
| --- | --- | --- |
| `--since` | los tres | `daily` y `sessions`: hace 7 días; `default-model`: hace 35 días |
| `--sort start\|tokens` | `sessions` | `start` (orden de inicio) |
| `--projects-dir` | los tres | `~/.claude/projects` |

- `--since` acepta una fecha (`2026-11-16`) o una fecha y hora (`2026-11-16T04:59`), en la zona horaria de la máquina, o con `Z` o un desfase. Un valor inválido, o una carpeta de `--projects-dir` que no existe, termina con código de salida 2.
- Los informes usan la zona horaria de la máquina.
- `sessions` lista solo las sesiones que tuvieron alguna respuesta de modelo, y muestra el modelo de la conversación principal y el de los subagentes.
- `-I` ejecuta Python aislado: ignora las variables `PYTHON*`, el `site` del usuario y la carpeta actual, para que no se importe un módulo suelto en lugar de uno de la biblioteca estándar.

## Qué lee y qué imprime

Lee los archivos `*.jsonl` bajo `--projects-dir` modificados desde `--since`. Se omiten las líneas corruptas, el JSON que no es un objeto y los archivos que desaparecen durante la lectura. Cada respuesta de la API se cuenta una sola vez, aunque aparezca repetida.

Imprime solo conteos y etiquetas: tokens, número de prompts, los primeros 8 caracteres del id de sesión, el nombre de la carpeta del proyecto, el nombre del punto de entrada (`entrypoint`) y los nombres de los modelos. Nunca imprime el contenido de los mensajes; el texto del prompt se lee solo para saber si existe. Todo es local: el script no usa la red.

El nombre de la carpeta del proyecto codifica la ruta absoluta de la carpeta de trabajo, por lo que el login de la persona puede aparecer en la parte impresa (el informe `sessions` muestra los últimos 32 caracteres). No pegues informes sin revisarlos antes.

## Cómo probarlo

```bash
cd tools/claude-usage && python3 -I -B -m unittest discover -s tests
bash scripts/validate.sh --path tools/claude-usage
```

Las pruebas usan transcripciones ficticias en una carpeta temporal, con `HOME` apuntando a ella, y no leen el `~/.claude` real. Las pruebas son opcionales: una herramienta solo tiene que compilar, y `validate.sh` no mide la cobertura en esta carpeta. La suite tiene 62 pruebas, con 100 % de cobertura de líneas y de ramas.

## Criterios de aceptación

Los ids aparecen en los nombres de las pruebas en `tests/test_claude_usage.py`.

| Id | Criterio |
| --- | --- |
| AC-1 | `daily`: respuestas y los cuatro tipos de token sumados por día y modelo, más la participación de cada modelo en el total de salida |
| AC-2 | `sessions`: inicio, carpeta, puntos de entrada, prompts, salida y modelos de la conversación principal y de los subagentes; `--sort start` o `tokens`; una sesión con solo prompts queda fuera |
| AC-3 | `default-model`: solo cuenta la primera respuesta de la conversación principal de cada transcripción, en el día en que ocurrió |
| AC-4 | Qué es una respuesta: se cuenta una vez por par de id de mensaje e id de solicitud, en todas las transcripciones; una sintética, una sin modelo o sin uso no cuenta |
| AC-5 | `--since`: una fecha empieza a la medianoche de la zona; una fecha y hora es local, salvo que tenga desfase; predeterminado de 7 días (`daily`, `sessions`) y 35 (`default-model`); un valor inválido sale con código 2 |
| AC-6 | Los datos incorrectos se omiten y nunca interrumpen la ejecución: líneas que no son JSON, JSON que no es un objeto, campos de tipo incorrecto, bytes fuera de UTF-8, archivos que desaparecen, un surrogate suelto en la salida |
| AC-7 | `--projects-dir`: válido en los tres comandos, acepta `~`, una carpeta que no existe o que no es una carpeta sale con código 2, los caracteres glob se representan solo a sí mismos; predeterminado `~/.claude/projects` |
| AC-8 | Formato de salida fijo, comparado con informes de referencia del mismo árbol; sin datos en el período, los encabezados se mantienen; el comando es obligatorio |
