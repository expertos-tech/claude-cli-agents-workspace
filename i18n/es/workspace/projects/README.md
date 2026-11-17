<!-- source: workspace/projects/README.md sha256:7ce630b736d61b678d355daf5b9f06a97c4ba8448f12345103691ff85f9a53a7 -->

# projects

Aquí viven los repositorios de los proyectos en los que trabaja el workspace. La carpeta pertenece al workspace; su contenido no: el núcleo ignora las subcarpetas, y solo este README forma parte de él.

## Cómo funciona la carpeta

- **Un repositorio por proyecto.** Cada proyecto es un repositorio git independiente, en `projects/<name>/`. Una carpeta puede agrupar repositorios (por ejemplo, los de un cliente: `projects/<client>/<name>/`); la carpeta que agrupa no es un repositorio.
- **La lista de proyectos vive en la capa custom**, en `custom/projects.md`: ruta, remoto, propósito y puertos de cada proyecto. Un proyecto nuevo se registra allí, con un commit en el repositorio `custom/`.
- **Siempre en `developer`.** El checkout de cada repositorio se queda en `developer` (o en `main`, cuando el proyecto no tiene `developer`) y no se edita aquí. Todo el trabajo ocurre en un clon bajo `tmp/work/` (`bash scripts/aiwp-cmds.sh open`) y llega a esta carpeta solo mediante el gate (`/merge`). Un hook rechaza cualquier escritura git en esta carpeta fuera de él.
- **Abre Claude en la raíz del workspace**, no dentro de un proyecto, para que se apliquen `AGENTS.md`, `rules/` y los hooks.

## Cómo traer un proyecto

- **Uno que ya existe:** en una sesión, `/normalize-projects --from <url | folder> --name [<folder>/]<name>`. Clona el proyecto aquí y lo trae al workspace: un análisis, un plan que apruebas, la migración en una rama probada, `developer` y `main` con el marcador. Un proyecto clonado aquí a mano también sirve: la sesión avisa que no tiene marcador y pide normalizarlo.
- **Uno nuevo:** `bash scripts/init-repo.sh --type project --name <name> [--parent <folder>]`, que crea el repositorio, escribe el marcador en su `README.md` y registra su fila en `custom/projects.md`.
- **El marcador:** la línea 1 del `README.md` de cada proyecto en `developer`, `<!-- AI-WORKSPACE-PROJECT x.y.z -->`. `bash scripts/aiwp-project-state.sh` muestra el estado de cada proyecto.

## Convenciones

- **Puertos:** cada proyecto usa puertos de host propios, registrados en `custom/projects.md`; los de las herramientas del workspace están en `tools/README.md`. Elige uno que no esté en ninguna de las dos tablas, fuera de 32768–60999, y regístralo en el mismo commit que empieza a usarlo (`rules/rules.md` "Workspace layout").
- **Dashboards en el Grafana local:** `observability/dashboards/*.json` en el repositorio del proyecto (convención en `tools/observability/README.md`).
- **Lengua:** se recomienda código en inglés, no es obligatorio (`rules/rules.md` "Language").
