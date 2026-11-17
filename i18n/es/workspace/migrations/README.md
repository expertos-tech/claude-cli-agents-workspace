<!-- source: workspace/migrations/README.md sha256:5752e6a9703407f247e212529cb5397a20499152c80405982923b777f7ac95b6 -->

# migrations

Lo que cada versión del workspace pide a los proyectos y las POCs. Un archivo por versión que pide algo:
`<x.y.z>.md`, con el nombre de la versión que lo introdujo. Una versión que no pide nada a los proyectos no tiene archivo.

## Cómo se usan los archivos

- Cada proyecto de `projects/` y cada POC de `custom/pocs/` lleva un marcador en la línea 1 de su `README.md`:
  `<!-- AI-WORKSPACE-PROJECT x.y.z -->`, la versión del workspace de su última normalización. En un proyecto, el
  marcador que cuenta es el confirmado en `developer`.
- Un proyecto está desactualizado solo cuando un archivo de aquí tiene una versión por encima de su marcador y hasta el
  `VERSION` del workspace. Un proyecto marcado `0.1.0` en un workspace en `0.3.0` cuyo último archivo de aquí es
  `0.1.0.md` está al día: un release que no pide nada a los proyectos nunca avisa.
- `bash scripts/aiwp-project-state.sh` imprime el estado de cada proyecto; el hook `UserPromptSubmit`, `aiwp-cmds.sh
  open` y el gate lo muestran, y `/normalize-projects` aplica los archivos pendientes en orden y luego escribe el
  marcador de la versión actual.

## Cómo se escribe un archivo

- Título `# <x.y.z>`, luego lo que un proyecto marcado con una versión anterior debe cambiar, como pasos que
  `/normalize-projects` puede aplicar: qué buscar (descrito por lo que hace, nunca por una lista fija de nombres de
  archivo), adónde va y cómo comprobar el resultado.
- Un archivo nunca cambia después de su release: una corrección posterior es un archivo nuevo para una versión posterior.

| Versión | Pide |
| --- | --- |
| [0.1.0](../../../../workspace/migrations/0.1.0.md) | La primera normalización: el análisis, la capa custom, la documentación, el informe y el marcador |
