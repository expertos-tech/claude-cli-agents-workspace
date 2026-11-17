<!-- source: workspace/scripts/performance/README.md sha256:f026b1a5f52b6b39e29726e92378849ab9bb6603d7c7c5acf5b02a8e1e92adf3 -->

# performance

Mide cómo se comporta el workspace en sesiones reales: cuánto del trabajo de Claude se va en el proceso del workspace, cuánto en validación y en el gate, cuántas preguntas te llegan, cuánto contexto carga cada sesión y cuánto tarda hasta la primera edición.

## Cómo ejecutarlo

Necesita el stack de observabilidad levantado. Sin él, el script se niega y muestra el comando que lo levanta:

```bash
docker compose -f tools/observability/compose.yaml up -d
python3 -I -B scripts/performance/measure.py --name after-the-gate
```

- Escribe `custom/performance/<yyyy-mm-dd>-<name>.md` (nombre por defecto: `measurement`). Sin `custom/`, pasa `--out <folder>`.
- El período empieza donde terminó la medición anterior. `--since <date>` elige otro inicio; `--all` mide todo lo que las transcripciones todavía conservan.
- El informe compara con la medición anterior y pone las cinco últimas lado a lado (`--compare <n>` cambia la cantidad).
- **Por proyecto:** líneas entregadas por hora de trabajo del agente, en código y en documentación, con el total del período y la tasa anterior de cada proyecto. Las horas salen de los turnos de las sesiones, y cada pedido cuenta para el proyecto que más tocaron sus herramientas (`projects/<project>`, un clon en `tmp/work/`); las líneas salen de los commits del agente (`[#automatic-agent-commit]`) de los repositorios de `projects/`, sin archivos generados (lock, build, imágenes, fuentes). Con menos de media hora en un proyecto, la tasa queda en blanco. Sin `git` en la máquina, la sección lo dice y el resto del informe sale igual.
- Los números de cada informe van dentro de él, en un comentario `performance-data`, y la siguiente medición compara a partir de ahí.

## Qué lee

- Las transcripciones de las sesiones abiertas en la raíz del workspace (`~/.claude/projects/<root>/*.jsonl`), solo la sesión principal; los subagentes quedan fuera.
- Del script solo salen agregados: ningún texto de prompt, ningún contenido de archivo.
- El formato de las transcripciones es interno de Claude Code y puede cambiar entre versiones. Las transcripciones se borran después de `cleanupPeriodDays` (30 días por defecto): mide antes de eso.
- La clasificación de cada llamada a herramienta es heurística (`classify` y `SCRIPT_CATEGORY` en `measure.py`). Cuando un script del workspace cambia de nombre o de función, actualízala allí.

## Cómo probarlo

```bash
cd scripts && python3 -I -B -m unittest discover -s tests -p 'test_performance.py'
```
