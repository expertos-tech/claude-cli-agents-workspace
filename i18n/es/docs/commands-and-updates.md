<!-- source: docs/commands-and-updates.md sha256:83b4ef9f8458442b906524a519232cffec49b15b850a6743d67a327a54bd4299 -->

# Comandos y actualizaciones

[English](../../../docs/commands-and-updates.md) · [Português (Brasil)](../../pt-BR/docs/commands-and-updates.md) · Español

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
  archivos 444), y el workspace no tiene `.git`: `custom/` y cada proyecto son los repositorios. Solo se pueden escribir
  `custom/`, `projects/`, `tmp/`, `.claude/`, `.history/` y una lista cerrada de salidas generadas por las herramientas
  (los datos de Grafana, `node_modules`, las páginas compiladas y los binarios de las consolas). Para eliminar un
  workspace, devuelve antes el permiso de escritura: `chmod -R u+w <carpeta> && rm -rf <carpeta>` (haz push de
  `custom/` y de tus proyectos antes).
- **Manifiesto:** cada workspace guarda la versión y el hash de cada archivo que recibió. Una actualización reemplaza
  solo lo que cambió la release nueva, borra lo que ella eliminó y omite el workspace si un archivo del core difiere del
  manifiesto (la actualización lo muestra en el resumen); `aiwp repair` lo restaura.
- **Copia de seguridad:** los archivos se reemplazan por renombrado, después de una copia de seguridad en
  `.aiwp/backup/<versión>/` (se guardan las 3 últimas), con un diario. Si una actualización se interrumpe a la mitad,
  `aiwp` se niega a abrir el workspace hasta que `aiwp repair` (o `aiwp update`) lo restaure. `aiwp rollback` vuelve a
  la versión de la copia de seguridad más reciente.
- **Solo se instala `workspace/`**, mediante una lista de inclusión. Nada más de este repositorio llega a tu
  workspace.
