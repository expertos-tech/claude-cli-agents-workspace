<!-- source: maintainers/plans/README.md sha256:09b6ec770d2312538eab18fb6a67b4cbf43c495942dbf4dafe1c51b71f4bf70a -->

# Planes

[English](../../../../maintainers/plans/README.md) · [Português (Brasil)](../../../pt-BR/maintainers/plans/README.md) · Español

Los diseños aprobados detrás de los pedidos de `maintainers/requests/`. Un plan dice qué construir y por qué; su pedido
dice qué debe ser cierto cuando esté terminado. Lee el plan antes de ejecutar su pedido.

| Plan | Cubre | Pedido |
| --- | --- | --- |
| `distribution.md` | Las tres carpetas, el instalador y `aiwp`, la sincronización del manifiesto, la instalación de solo lectura, el mantenimiento en la raíz del repositorio, plataformas e idiomas | Construido en la publicación 0.1.0 |
| `normalize-projects.md` | El análisis y la migración de proyectos, la marca de versión y la comprobación en cada interacción | `requests/done/normalize-projects.md` |
| `rules-config.md` | `custom/rules-config.json`, `custom/my-rules/`, el core obligatorio y `/rules` | `requests/rules.md` |
| `normalize-rules.md` | Llevar las reglas de un workspace antiguo a `custom/my-rules/` y listar sus proyectos | `requests/normalize-rules.md` |
| `run-tools.md` | El archivo compose único de las herramientas y `/run-tools` | `requests/run-tools.md` |
| `tools-hub.md` | La página de herramientas, el ícono del menú y el área Workspace | `requests/tools-hub.md` |
| `fork-my-rules.md` | Devolver al proyecto las reglas propias mediante fork y pull request | `requests/fork-my-rules.md` |

El orden en que corren está en `maintainers/requests/README.md`.
