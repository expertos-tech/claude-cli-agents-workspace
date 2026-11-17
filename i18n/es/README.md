<!-- source: README.md sha256:5a05e088078e5004c9da8056d08b776791db4410533ec4ba6ab49e29d950674b -->

# Claude CLI Agents Workspace

<p align="center"><img src="../../workspace/assets/logo.png" alt="Claude CLI Agents Workspace" width="320"></p>

<p align="center"><a href="../../README.md">English</a> · <a href="../pt-BR/README.md">Português (Brasil)</a> · Español</p>

Un workspace para **Claude Code CLI**. Tú dices **qué** quieres, y Claude decide **cómo**, trabajando en un clon
aislado donde todo está permitido. Las verificaciones pesadas y las preguntas para ti quedan en un solo lugar: el gate
que lleva el trabajo a la rama base del proyecto.

> **Hecho para la CLI.** Los hooks, los permisos, las skills y los nombres de sesión se diseñaron y probaron en Claude
> Code de terminal (`claude`). La app de Claude (escritorio o web) y las extensiones de IDE probablemente puedan abrir
> el workspace, pero pueden tratar los hooks, los permisos y los comandos de otra forma; allí, lo que describe esta
> documentación no está garantizado.

## Participa

Este workspace nació del uso diario, y mejora con cada persona que lo usa en un proyecto real. ¿Encontraste una forma
mejor de hacer algo, corregiste un defecto, escribiste un hook o una regla más clara? **Compártelo**: haz un fork del
repositorio, haz tu cambio y envía un pull request. Construyamos una comunidad open source a su alrededor. Los pasos
están en [Contribuir](docs/contributing.md).

## Inicio rápido

1. Revisa los [requisitos](docs/getting-started.md#requisitos): Linux, macOS o WSL2, `git`, `bash`, `python3`, Docker
   y Claude Code CLI con la sesión iniciada.
2. Instala y crea tu workspace:

   ```bash
   curl -fsSL https://raw.githubusercontent.com/expertos-tech/claude-cli-agents-workspace/main/install.sh | bash
   ```

3. Ábrelo en su raíz: `cd ~/my-workspace && aiwp`.
4. Trae un proyecto a `projects/` y pide en la sesión lo que quieras, por ejemplo:
   `en my-app, crea un endpoint GET /health que responda 200 con la versión de la aplicación`.

Cada paso, con las opciones, está en [Primeros pasos](docs/getting-started.md).

## Documentación

| Página | Qué cubre |
| --- | --- |
| [Primeros pasos](docs/getting-started.md) | Requisitos, instalación, creación, apertura y el primer pedido |
| [Funcionalidades](docs/features.md) | Qué obtienes, y la capa custom |
| [Comandos y actualizaciones](docs/commands-and-updates.md) | Los comandos `aiwp` y cómo funcionan las actualizaciones |
| [Hooks](docs/hooks.md) | Los hooks que se ejecutan en tu máquina |
| [Guía del producto](workspace/docs/usage.md) | El uso diario del workspace |
| [Contribuir](docs/contributing.md) | Issues, fork, rama, pull request |
| [Mantenimiento](docs/maintenance.md) | Cómo se mantiene el repositorio |
| [Releases](docs/releases.md) | Ramas, changelogs y el release del producto |
| [Traducciones](docs/translations.md) | Qué se traduce y cómo se verifica |
| [Repositorio](docs/repository.md) | La estructura del repositorio |

## Licencia

[MIT](../../LICENSE).
