<!-- source: workspace/tools/container-console-docker-ce/README.md sha256:f49c5fde8eb0ad671c828e5b8e3c1ed9cb6786216f75ca6e5c794abb9ee01761 -->

# container-console-docker-ce

- [Qué es](#qué-es)
- [Cómo ejecutarlo](#cómo-ejecutarlo)
- [Cómo probarlo](#cómo-probarlo)
- [Cómo desinstalarlo](#cómo-desinstalarlo)
- [Cómo desplegarlo](#cómo-desplegarlo)
- [Documentación](#documentación)

## Qué es

Consola local, en el navegador, para el entorno de contenedores de esta máquina Linux con docker-ce: muestra el estado del daemon de Docker y administra contenedores (agrupados por proyecto Compose), imágenes, volúmenes, redes, proyectos Compose y recursos de Kubernetes, con logs en vivo y terminal, y limpia lo que ningún contenedor activo usa. La interfaz está en inglés por defecto y cambia al portugués de Brasil cuando el idioma del navegador empieza con `pt`.

Es un servicio en Go que escucha solo en `127.0.0.1:27850`, sin inicio de sesión, y sirve la interfaz React incrustada en el binario. Un acceso directo en el escritorio abre la dirección en el navegador predeterminado, y el servicio arranca solo en cada inicio de sesión gráfica. Para un solo usuario.

La pantalla de entorno es de solo lectura: controlar docker-ce requiere root, así que la consola nunca enciende ni apaga el daemon. Con el daemon apagado, la pantalla lo indica y muestra el comando `sudo systemctl start docker` para que usted lo ejecute.

El tema sigue al sistema operativo por defecto, y el campo `Theme` del menú lateral cambia entre sistema, oscuro y claro.

## Cómo ejecutarlo

Requisitos previos: docker-ce con Docker Compose v2 y su usuario en el grupo `docker`, `kubectl` (solo para la pantalla de Kubernetes), `zenity` (solo para el diálogo de archivo), `xdg-open`, `systemd --user`, Go (la versión de `go.mod`) y Node 24, que solo usa la compilación.

En la carpeta `tools/container-console-docker-ce`, con Node 24 en el `PATH`:

```bash
make install
```

`make install` compila el front-end y el binario y ejecuta `linux/install-console.sh`, que instala el binario en `~/.local/bin`, la unit `container-console-docker-ce.service` de `systemd --user` y el acceso directo `container-console-docker-ce.desktop`, con el ícono del proyecto Claude CLI Agents Workspace (`web/public/favicon.png`, recortado del logo en `assets/` de la raíz). Al terminar, imprime `installed container-console-docker-ce.service and <ruta del acceso directo>`. Repetir el comando es seguro.

Después, haga clic en "Container Console" en el menú de aplicaciones o abra <http://127.0.0.1:27850/>. El acceso directo despierta el servicio si está detenido.

Para probarlo sin instalar: `make build` y `.data/bin/container-console-docker-ce`.

No hay agente de inicio de sesión para Docker: `dockerd` arranca con el sistema, y el Grafana de `tools/observability` vuelve solo con él, por la política `restart: unless-stopped`.

Verificaciones de compilación: `make check` (`gofmt`, `go vet`, `go build`, `npm audit --audit-level=high` y `tsc --noEmit`).

## Cómo probarlo

No hay pruebas automatizadas: la herramienta se verifica compilando (`make check`, más `bash scripts/validate.sh --only secrets` en la raíz del workspace) y con pruebas manuales. Las pruebas manuales, con pasos y resultado esperado, un bloque por requisito, están en [`docs/manual-tests.md`](docs/manual-tests.md): las pantallas, el acceso directo, la unit y el reinicio de la máquina.

## Cómo desinstalarlo

```bash
bash linux/uninstall-console.sh
```

Elimina la unit, el acceso directo, el ícono copiado y el binario. No toca Docker, los contenedores, el log, la lista de proyectos Compose ni `~/.config/container-console-docker-ce/env`.

## Cómo desplegarlo

Solo local, en esta máquina: no hay nube, servidor ni costo. `make install` es el despliegue.

## Documentación

| Página | Contenido |
| --- | --- |
| [docs/overview.md](docs/overview.md) | Qué es, para quién, alcance |
| [docs/architecture.md](docs/architecture.md) | Componentes y flujos |
| [docs/api.md](docs/api.md) | Contrato REST y WebSocket |
| [docs/operations.md](docs/operations.md) | Configuración, logs y fallas comunes |
| [docs/manual-tests.md](docs/manual-tests.md) | Pruebas que usted ejecuta, por requisito |
