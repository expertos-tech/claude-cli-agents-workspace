<!-- source: docs/getting-started.md sha256:184dd1b855e3665064f92e2d4107204300326725850e16f521dfd5f07685d4d2 -->

# Primeros pasos

[English](../../../docs/getting-started.md) · [Português (Brasil)](../../pt-BR/docs/getting-started.md) · Español

## Requisitos

- **Linux o macOS.** En **Windows, solo mediante WSL2**: instala una distribución Linux (Ubuntu, por ejemplo) y haz todo
  desde dentro de ella, con la misma estructura que en Linux. El workspace, los proyectos, Docker y `claude` viven en el
  sistema de archivos de WSL (`~/...`), nunca en `/mnt/c`. No hay versión nativa para Windows.
- `git`, `bash`, `python3` y Docker.
- Claude Code CLI instalado y con la sesión iniciada: `claude` abre una sesión.
- **Opcional, pero importante: el stack de observabilidad** (`workspace/tools/observability/`, un Grafana local en
  <http://localhost:3000>). Muestra lo que cuesta cada sesión en tokens, tiempo y modelo; sin medición no hay forma de
  saber si un cambio en las reglas mejoró o empeoró el trabajo.
- **Recomendado: [Claude in Chrome](https://claude.com/chrome)**, la extensión que permite a Claude abrir páginas en tu
  Chrome, hacer clic, leer la consola y tomar capturas de pantalla, para validar diseños y flujos de pantalla por sí
  mismo (`/pilot auto`). No funciona dentro de WSL: en Windows, esas pruebas quedan a tu cargo (`/pilot manual`).

## Inicio rápido

### 1. Instala y crea el workspace

```bash
curl -fsSL https://raw.githubusercontent.com/expertos-tech/claude-cli-agents-workspace/main/install.sh | bash
```

`curl | bash` ejecuta lo que el script contenga en ese momento. Para leerlo antes de ejecutarlo:

```bash
curl -fsSL -o install.sh https://raw.githubusercontent.com/expertos-tech/claude-cli-agents-workspace/main/install.sh
less install.sh
bash install.sh
```

El instalador comprueba los requisitos y dice lo que falta, sin instalar nada por su cuenta. Clona el repositorio en tu
carpeta de datos local, en la etiqueta de la release más reciente, pone el comando `aiwp` en `~/.local/bin` y después
crea tu workspace con `aiwp new` y lo añade al registro de workspaces. No necesita permisos de administrador ni `sudo`.

Pregunta dónde va el workspace, en la terminal (funciona con `curl | bash`), según la carpeta en la que se ejecuta:

- **Una carpeta vacía:** `1) Install here` o `2) Give another path`.
- **Una carpeta con contenido:** solo la ruta, de una carpeta nueva o vacía. Una mala respuesta se vuelve a preguntar.

Después `aiwp new` pide la URL de tu repositorio custom: crea un repositorio privado vacío en tu servidor git e indica
su URL. Un repositorio vacío recibe un esqueleto y un primer commit; una respuesta vacía crea un repositorio local.

Para saltarte las preguntas, indica la carpeta:

```bash
curl -fsSL https://raw.githubusercontent.com/expertos-tech/claude-cli-agents-workspace/main/install.sh | bash -s -- ~/my-workspace
AIWP_WORKSPACE=~/my-workspace bash install.sh
```

El argumento gana a `AIWP_WORKSPACE`. Sin terminal y sin carpeta, el instalador instala solo la carpeta de datos e
imprime cómo crear un workspace después (`aiwp new <carpeta>`). Volver a ejecutar el instalador actualiza la carpeta de
datos y nunca un workspace: eso lo hace `aiwp update`. Cuando la carpeta de datos ya está instalada, la pregunta
también ofrece solo actualizarla (`3)`, o una ruta vacía).

### 2. Crea otro workspace

```bash
aiwp new ~/other-workspace
```

Cada workspace es una copia del producto en su propia carpeta, y todos comparten la instalación de la carpeta de datos.

### 3. Ábrelo

```bash
cd ~/my-workspace && aiwp
```

`aiwp` comprueba si hay una release nueva y, cuando la hay, avisa y manda ejecutar `aiwp update`; nunca actualiza.
Después inicia `claude` en la versión actual del workspace. Abre siempre la sesión en la raíz del workspace, incluso
para trabajar en un solo proyecto: ahí es donde valen las reglas y los hooks. Se recomienda el auto mode de Claude
Code: el workspace le deja el juicio sobre lo que es destructivo y guarda en los hooks solo lo que nunca debe ocurrir.

### 4. Trae un proyecto y pide

```bash
git clone <url de tu proyecto> projects/my-app
git -C projects/my-app switch developer
```

Después, en la sesión:

```text
en my-app, crea un endpoint GET /health que responda 200 con la versión de la aplicación
```

Claude pregunta solo lo que impide empezar, abre un clon en `tmp/work/<fecha>-<asunto>/my-app/`, te dice la ruta y
trabaja solo allí, con pruebas. Cada commit va al remoto después de un escaneo de secretos. Cuando termine:

```text
/merge <fecha>-<asunto>/my-app
```

El gate trae la `developer` actualizada, ejecuta la suite completa y las validaciones, busca secretos, muestra lo que
sale de la base y pide una revisión contra tu pedido. Solo se te pregunta si aparece algo que el pedido no explica.
Para pedidos más grandes, escribe el pedido con `/draft-prompt` y ejecútalo con `/prompt`. La guía completa está en
[workspace/docs/usage.md](../workspace/docs/usage.md).
