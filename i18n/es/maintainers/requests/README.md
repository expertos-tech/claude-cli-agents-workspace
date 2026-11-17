<!-- source: maintainers/requests/README.md sha256:7d1d94a127d87311db94b2d82b49a6326f391a259ca5a54f74cf31b1455881b3 -->

# Pedidos

[English](../../../../maintainers/requests/README.md) · [Português (Brasil)](../../../pt-BR/maintainers/requests/README.md) · Español

Pedidos funcionales para el propio workspace, listos para ejecutar en la raíz del repositorio, donde se mantiene el
proyecto. Cada uno tiene el objetivo, las reglas de negocio (BR-n), los criterios de aceptación (AC-n), lo que queda
fuera de alcance y las etapas con el effort de cada una. El diseño detrás de cada pedido está en `maintainers/plans/`.

Ejecútalos en este orden; cada uno depende de los anteriores:

| # | Pedido | Diseño | Estado |
| --- | --- | --- | --- |
| 0a | `done/merge-versioned-changelog.md` | — | En curso; plan aprobado el 2026-11-17, registrado en la aprobación |
| 0b | `done/caw-merge-two-changelogs.md` | — | Construido el 2026-11-17: dos changelogs, solo se publica el producto |
| 0c | `done/project-docs.md` | — | Construido el 2026-11-17: `docs/`, un README corto, traducciones de cada README |
| 0 | `import-from-fork.md` | — | Pendiente; primero tras la publicación, con su propio release |
| 1 | `done/normalize-projects.md` | `plans/normalize-projects.md` | Construido en 0.1.0; prueba de extremo a extremo aprobada en seis proyectos; falta una segunda prueba en proyectos nuevos |
| 2 | `rules.md` | `plans/rules-config.md` | Pendiente |
| 3 | `normalize-rules.md` | `plans/normalize-rules.md` | Pendiente; necesita `rules` |
| 4 | `run-tools.md` | `plans/run-tools.md` | Pendiente |
| 5 | `tools-hub.md` | `plans/tools-hub.md` | Pendiente; necesita `run-tools` |
| 6 | `fork-my-rules.md` | `plans/fork-my-rules.md` | Pendiente; necesita `rules` |
| 7 | `final-review.md` | — | Pendiente; corre al final, en una sesión nueva |
| 8 | `done/readme-get-involved-first.md` | — | Construido el 2026-11-17 dentro de `done/project-docs.md` |
| 9 | `prompt-log-results.md` | — | Pendiente; ronda 1 |
| 10 | `gate-audit-gaps.md` | — | Pendiente; ronda 1 |
| 11 | `work-status-docker-stacks.md` | — | Pendiente; ronda 1 |
| 12 | `aiwp-remove.md` | — | Pendiente; ronda 1; su primera decisión es si construirlo |
| 13 | `measure-quality-indicators.md` | — | Pendiente; ronda 1, después de `import-from-fork` (ambos cambian `measure.py`) |
| 14 | `onboard.md` | `plans/distribution.md` | Pendiente; ronda 2; necesita `rules` |
| 15 | `rules-size-budget.md` | — | Pendiente; ronda 3, o incorporado a `final-review` |
| 16 | `os-sandbox-trial.md` | — | Pendiente; después de la ronda 3 |

Los pedidos de la misma ronda corren en sesiones paralelas, cada una en su propio worktree
(`claude --worktree <request>` desde la raíz del repositorio), y se integran en `main` de uno en uno:

| Ronda | Pedidos |
| --- | --- |
| 0a | `merge-versioned-changelog`, solo: `developer` como base, el changelog versionado y `/merge --main` |
| 0 | `import-from-fork`, solo, con su propio release menor: la primera prueba real de `aiwp update` |
| 1 | `rules`, `run-tools`, `prompt-log-results`, `gate-audit-gaps`, `work-status-docker-stacks`, `aiwp-remove`, `measure-quality-indicators` |
| 2 | `normalize-rules`, `fork-my-rules`, `tools-hub`, `onboard` |
| 3 | `final-review` (con `rules-size-budget` incorporado o justo antes), que publica la versión siguiente una sola vez y prueba la actualización de un workspace real instalado dedicado a ello |
| 4 | `os-sandbox-trial` |

Ejecuta un pedido en una sesión nueva abierta en la raíz del repositorio, una etapa por sesión cuando una etapa es
grande. Un plan que el owner aprueba en una sesión se registra de inmediato, en inglés y en este formato, en `done/`,
con su fila aquí. Un pedido entregado pasa a `done/` (`git mv`, en el commit que lo cierra); su fila se queda aquí con
la nueva ruta y su Estado.
