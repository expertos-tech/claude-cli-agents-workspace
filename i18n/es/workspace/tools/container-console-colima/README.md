<!-- source: workspace/tools/container-console-colima/README.md sha256:7086e78e80dea49a544f21c9fd89d27d30fd70c32e82207f4e7f7aaf2d55be34 -->

# container-console-colima

- [Qué es](#qué-es)
- [Cómo ejecutarlo](#cómo-ejecutarlo)
- [Cómo probarlo](#cómo-probarlo)
- [Cómo desinstalarlo](#cómo-desinstalarlo)
- [Cómo desplegarlo](#cómo-desplegarlo)

## Qué es

Consola local, en el navegador, para el entorno de contenedores de un Mac con Colima: muestra y controla la VM de Colima, enciende y apaga su Kubernetes, y administra contenedores, imágenes, volúmenes, redes, proyectos Compose y recursos de Kubernetes, con logs en vivo y terminal. Es el gemelo macOS/Colima de [`container-console-docker-ce`](../container-console-docker-ce/README.md), con la misma identidad visual: el ícono y el nombre del proyecto Claude CLI Agents Workspace en la barra superior, con "Container Console · Colima" debajo. La interfaz está en inglés por defecto y cambia al portugués de Brasil cuando el idioma del navegador empieza con `pt`.

Es un servicio en Go que escucha solo en `127.0.0.1:17850`, sin inicio de sesión, y sirve la interfaz React incrustada en el binario. Un ícono en el Dock abre la dirección en el navegador predeterminado, y un LaunchAgent arranca el servicio en cada inicio de sesión gráfica. Para un solo usuario.

El diálogo de archivo es el nativo de macOS, mediante `osascript`. El tema sigue al sistema operativo por defecto, y el campo `Theme` del menú lateral cambia entre sistema, oscuro y claro.

## Cómo ejecutarlo

Requisitos previos: macOS con Colima, la CLI `docker` con Docker Compose v2 y `kubectl` (solo para la pantalla de Kubernetes), desde Homebrew en `/opt/homebrew/bin`; Go (la versión de `go.mod`) y Node, que solo usa la compilación.

En la carpeta `tools/container-console-colima`:

```bash
make install
```

`make install` compila el front-end y el binario y ejecuta `macos/install-console.sh`, que instala:

- el binario en `~/Library/Application Support/container-console-colima/bin`;
- el LaunchAgent `io.github.expertos-tech.claude-cli-agents-workspace.container-console-colima` en `~/Library/LaunchAgents`, cargado de inmediato por `RunAtLoad`;
- la app `~/Applications/Container Console (Colima).app`, con el ícono del proyecto (`web/public/favicon.png`);
- la app en el Dock. Si este paso falla, el script explica cómo hacerlo a mano y la instalación sigue siendo válida.

Al terminar, imprime `installed <label> and <ruta de la app>`. Repetir el comando es seguro. El instalador se niega a sobrescribir un plist o una app con el mismo nombre que él no escribió. Use `--verbose` para ver cada paso.

Después, haga clic en "Container Console (Colima)" en el Dock o abra <http://127.0.0.1:17850/>. El ícono despierta el servicio si no responde y, si no arranca en 5 s, muestra una alerta con la ruta de los logs (`~/Library/Logs/container-console-colima/`).

Para probarlo sin instalar: `make build` y `.data/bin/container-console-colima`.

Opcional, para arrancar el runtime al iniciar sesión: `runtime/install-runtime.sh --compose-file <ruta absoluta>` instala el LaunchAgent `io.github.expertos-tech.claude-cli-agents-workspace.container-runtime`, que ejecuta `runtime/login-start.sh` en cada inicio de sesión. Enciende la VM de Colima con Kubernetes apagado (lo reintenta una vez, después de un `colima stop --force`), apaga Kubernetes si está encendido y ejecuta `docker compose up` sobre el archivo indicado. Registra horarios y duraciones en `~/Library/Logs/container-console-colima/runtime.log` y muestra una notificación de macOS si falla. El plist apunta a `login-start.sh` en esta carpeta: mover el workspace requiere una nueva instalación.

Verificaciones de compilación: `make check` (`gofmt`, `go vet`, `go build`, `npm audit --audit-level=high` y `tsc --noEmit`).

## Cómo probarlo

Los scripts del runtime tienen pruebas unitarias, con `colima`, `docker`, `osascript` y `launchctl` falsos en el `PATH`, que no tocan la VM, Docker ni launchd. Necesitan el `plutil` de macOS:

```bash
bash runtime/tests/test-login-start.sh
```

La pantalla y el ícono del Dock se comprueban a mano, en el Mac: instale, abra desde el Dock y recorra las pantallas de visión general, entorno, contenedores, imágenes, volúmenes, redes, Compose y Kubernetes.

## Cómo desinstalarlo

```bash
bash macos/uninstall-console.sh
bash runtime/uninstall-runtime.sh
```

El primero elimina solo lo que escribió `install-console.sh`: el ícono del Dock, la app, el LaunchAgent y el binario. No toca el LaunchAgent del runtime, la VM, los contenedores, los logs ni la lista de proyectos Compose. El segundo descarga el LaunchAgent del runtime y elimina su plist, sin detener la VM ni los contenedores. Ambos fallan, sin cambiar nada, ante un plist o una app con el mismo nombre que no escribieron.

## Cómo desplegarlo

Solo local, en el Mac: no hay nube, servidor ni costo. `make install` es el despliegue.
