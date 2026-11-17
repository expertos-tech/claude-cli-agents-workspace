<!-- source: docs/maintenance.md sha256:15b1d2a7623544cc1105895d68119cf1966e795dce5b79203fbf587b64d1b884 -->

# Mantenimiento

[English](../../../docs/maintenance.md) · [Português (Brasil)](../../pt-BR/docs/maintenance.md) · Español

Cómo se mantiene este repositorio. Una sesión abierta en la raíz del repositorio cambia el producto; no lo usa. Las
reglas de esa sesión son el `CLAUDE.md` de la raíz y `.claude/rules/`.

## Mantener desde la raíz del repositorio

- El producto es `workspace/`. Su `AGENTS.md`, `CLAUDE.md`, `rules/`, skills, agentes y hooks son código que se edita,
  nunca instrucciones para la sesión de mantenimiento. `.claude/settings.json` los deja fuera del contexto con
  `claudeMdExcludes`.
- Inicia Claude Code en la raíz del repositorio. La configuración del proyecto se lee de la carpeta donde empieza la
  sesión, así que una sesión iniciada dentro de `workspace/` no ve la configuración de la raíz.
- Los patrones de `claudeMdExcludes` coinciden con rutas absolutas. Los del commit suponen que la carpeta del clon se
  llama `claude-cli-agents-workspace`. En un clon con otro nombre, añade los mismos patrones con tu ruta absoluta a
  `.claude/settings.local.json`, que git ignora.
- Aquí no se ejecuta ningún hook del producto. Nunca ejecutes `workspace/scripts/setup-claude.sh` dentro de
  `workspace/`; prueba los hooks en una instalación de prueba (`/caw-test-install`).

## El proceso

Detalle en `.claude/rules/process.md`. Corregir un typo puede saltarse el plan y el pedido.

1. **Evaluar** el producto y, solo lectura, su uso real (un workspace instalado, transcripciones, el registro de
   prompts, mediciones). Un hallazgo que nombra una empresa, un cliente o un proyecto se queda en `tmp/`, ignorado por
   git.
2. **Planificar** en `maintainers/plans/`: el problema, opciones, una recomendación y decisiones numeradas para el
   owner.
3. **Pedido**, con las respuestas del owner, en `maintainers/requests/`: objetivo, BR-n, AC-n, fuera de alcance y las
   etapas con effort.
4. **Ejecutar** por etapas, con subagentes cuando valga la pena, siempre con modelo y effort explícitos, y una revisión
   independiente con contexto limpio de los hooks y de la seguridad.
5. **Probar**: `bash tests/check.sh --all` en cada cambio; `/caw-test-install` cuando cambia el instalador, un hook o
   `setup-claude.sh`.
6. **Cerrar**: commits en Conventional Commits, un cambio lógico cada uno; push solo cuando el owner lo pide.

## `maintainers/`

El trabajo de quienes mantienen, a la vista. Nada de allí llega a un workspace instalado.

| Carpeta | Qué guarda |
| --- | --- |
| `maintainers/backlog/` | Ideas, defectos y deudas del producto que aún no son un pedido, un ítem por archivo |
| `maintainers/plans/` | Diseños: problema, opciones, recomendación, decisiones numeradas. Un plan que el owner aprueba se registra en `maintainers/requests/done/` en el momento de la aprobación |
| `maintainers/requests/` | Pedidos listos para ejecutar con `/caw-prompt`; el orden en que corren está en su README |
| `maintainers/requests/done/` | Pedidos entregados y los planes aprobados |
| `maintainers/reviews/` | Informes de revisiones independientes; lo crea la primera |

## Skills

Las skills de mantenimiento llevan el prefijo `caw-`, para no chocar con las skills del producto del mismo propósito
(`/merge`, `/commit`, `/prompt`...). Viven en `.claude/skills/`.

| Skill | Argumentos | Qué hace |
| --- | --- | --- |
| `/caw-check` | `[--base <ref>] [--floor] [extra check.sh options]` | Ejecuta `tests/check.sh --all` con las banderas correctas y explica cada falla |
| `/caw-commit` | `[--all]` | Un Conventional Commit por cambio lógico de la sesión, por ruta; sin push, sin rama, sin etiqueta |
| `/caw-draft-prompt` | `[plan \| request] [ideas \| path]` | Convierte ideas en un plan o un pedido, preguntando solo lo que no tiene mejor alternativa |
| `/caw-prompt` | `[file name \| path]` | Ejecuta un pedido escrito en un archivo: un nombre simple se busca en `maintainers/requests/`, `tmp/prompts/` y luego `tmp/`; sin argumento lee `tmp/prompt.md` |
| `/caw-test-install` | `[--keep]` | Instala un workspace desechable a partir del árbol actual en `tmp/test-install/` y ejercita hooks y scripts |
| `/caw-merge` | `[<work>/<clone> \| --main]` | Lleva el trabajo a `developer` por los gates y ambos changelogs; `--main` publica el release del producto ([releases](releases.md)) |

## Subagentes

Cada llamada a un subagente indica su modelo y su effort; una llamada que los heredaría es un error. Effort `high` para
hooks, el instalador, seguridad, acciones riesgosas y toda revisión (`.claude/rules/models.md`).

| Tarea | Agente | Modelo | Effort |
| --- | --- | --- | --- |
| Lagunas de un plan o pedido | `requirements-analyst` | claude-opus-5-5 | high |
| Revisión independiente | `reviewer` | claude-opus-5-5 | high |
| Scripts, hooks y sus pruebas | `script-engineer` | claude-opus-5-5 | high para hooks y el instalador, si no medium |
| Docs y sus traducciones pt-BR y es | `docs-writer` | claude-sonnet-5-5 | medium |
| Ejecutar la suite, devolviendo solo las líneas de resultado | `verifier` | claude-haiku-5-5 | low |
| Docs oficiales, versiones, precios | `web-researcher` | claude-sonnet-5-5 | high |

Lo predeterminado es ningún subagente. Los subagentes nunca hacen commit ni push: lo hace la sesión principal.

## Dónde ocurre el trabajo

- **En un clon:** `/caw-prompt` abre un clon del repositorio en `tmp/work/<yyyy-mm-dd>-<slug>/`, en una rama de trabajo
  `<type>/<slug>` a partir de `origin/developer`, y trabaja solo allí. La rama se sube después de cada commit.
- **Directo en `developer`:** una sesión en la raíz que no abrió ningún clon trabaja en `developer`.
- **Los planes y pedidos** se muestran al owner en su idioma y se guardan en inglés.

## `/caw-merge`

Solo cuando el owner lo pide. Ejecutarlo es la orden del owner para los push que hace.

- **Desde un clon:** hace merge de `origin/developer` en el clon, escribe los changelogs, ejecuta
  `bash tests/check.sh --all --base origin/developer` (y `/caw-test-install` cuando cambió el instalador, un hook o
  `setup-claude.sh`), y después un `reviewer` con contexto limpio. Solo entonces, en la raíz, avanza `developer`
  (fast-forward) hasta el commit del clon, lo sube, y borra la rama de trabajo y el clon.
- **En developer:** los mismos gates sobre los commits desde el último commit de changelog
  (`docs(changelog)` o `chore(release)`), y después el push.
- **`--main`:** el release del producto ([releases](releases.md)).

Nunca hace merge con un check fallando o un BLOCKER abierto, y nunca reescribe `developer` ni `main`.

## Repositorio público

Este repositorio es público: todo lo que se commitea, incluido `maintainers/`, puede leerlo cualquiera
(`.claude/rules/security.md`).

- Nunca commitees un término de empresa, el nombre de un cliente o proyecto, una ruta personal, una dirección de
  e-mail, una URL interna, un token ni ningún secreto. `bash tests/check.sh --all` escanea el repositorio con la lista
  de términos del owner; una coincidencia se reformula, nunca se exime, y nunca se imprime en un issue, commit, pull
  request o informe.
- Los análisis privados del uso real viven en `tmp/`, ignorado por git, o en la capa custom del owner; el repositorio
  recibe el hallazgo general.
- Los archivos `.env` nunca se leen ni se editan; las plantillas `.env.example` sí.
- Los ejemplos y fixtures usan datos inventados (`acme`, `example.com`, `billing-api`).
- Un cambio que debilita una protección del producto (un hook, una regla deny, el gate, un modo de archivo) necesita la
  aprobación explícita del owner y una revisión independiente.
