<!-- source: workspace/tools/container-console-docker-ce/docs/overview.md sha256:c0f002a6ccf7485f74b04c872adef89a7b678e12f5a1d7c1b55b404d845e9e90 -->

# Visión general de `container-console-docker-ce`

## Qué es

Consola local, en el navegador, que administra el entorno de contenedores de la máquina Linux: muestra el estado de docker-ce y administra contenedores, imágenes, volúmenes, redes, proyectos Compose y el clúster Kubernetes del kubeconfig. Se ejecuta como un servicio en Go bajo `systemd --user` y se abre desde un acceso directo en el escritorio. La interfaz está en inglés por defecto y en portugués de Brasil cuando el idioma del navegador empieza con `pt`.

## Por qué

docker-ce no tiene interfaz. La consola ofrece la gestión desde una pantalla, sin abrir la terminal.

## Quién la usa

Una persona, la dueña de la máquina, en el grupo `docker`. Sin inicio de sesión: solo acepta acceso desde la propia máquina (`127.0.0.1`) y rechaza encabezados `Host` y `Origin` de otros sitios. Sin roles, sin otras máquinas.

## Qué hace

| Área | Acciones |
| --- | --- |
| Entorno | Solo lectura: estado del daemon, versión, CPUs, memoria, driver de almacenamiento, sistema operativo y arquitectura. Con el daemon apagado, muestra `sudo systemctl start docker` como texto |
| Contenedores | Listar, iniciar, detener, reiniciar, eliminar, detalles, uso de recursos, logs en vivo y terminal |
| Imágenes | Listar, descargar y eliminar |
| Volúmenes y redes | Listar, crear, detalles y eliminar |
| Compose | Listar proyectos, levantar, detener y eliminar |
| Kubernetes | Con el contexto actual del kubeconfig o `CONSOLE_KUBE_CONTEXT`: listar y detallar namespaces, pods, deployments y services; eliminar; escalar deployments; logs en vivo; terminal en el pod; aplicar YAML (un YAML inválido se rechaza y nada cambia). Sin un clúster accesible, muestra no disponible |
| Limpieza | Elimina lo que ningún contenedor activo usa: contenedores detenidos, imágenes y redes sin uso, volúmenes solo si se pide, y la caché de build |

Reglas que valen en toda la pantalla: eliminar siempre pide confirmación; una acción que falla muestra el error recibido, sin traducir, y la lista sigue mostrando el estado real; con Docker apagado la pantalla abre, muestra el estado y deja las acciones de Docker deshabilitadas, con el motivo; un cambio debe aparecer en hasta 2 s, con hasta 30 contenedores.

## Qué no hace

Encender o apagar el daemon de Docker, ajustar sus recursos, crear o encender un clúster Kubernetes, medir rendimiento, construir imágenes desde la pantalla, uso desde otras máquinas o por otros usuarios, ni nube.

## Estado

- La herramienta no tiene pruebas automatizadas. Se verifica compilando (`make check`) y con las [pruebas manuales](manual-tests.md), que usted ejecuta en un navegador real en esta máquina.
- El tema sigue al sistema operativo por defecto, y la persona cambia entre sistema, oscuro y claro en el menú lateral. El contraste se calculó con un script; el resultado en pantalla se comprueba en las [pruebas manuales](manual-tests.md#tema).

## Mapa

[README](../README.md) · [arquitectura](architecture.md) · [API](api.md) · [operación](operations.md) · [pruebas manuales](manual-tests.md)
