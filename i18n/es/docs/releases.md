<!-- source: docs/releases.md sha256:9b00ec33fe4f4ce46809f5cd7bef650cd134c92017aa6f99dc58827e95563322 -->

# Releases

[English](../../../docs/releases.md) · [Português (Brasil)](../../pt-BR/docs/releases.md) · Español

Solo se publica el producto. El mantenimiento del repositorio se registra, pero nunca se publica por sí solo.

## Ramas

- `developer` es la rama predeterminada: todo cambio entra en ella, mediante `/caw-merge`.
- `main` solo avanza con un release del producto.

## Los dos changelogs

| Archivo | Qué registra |
| --- | --- |
| `CHANGELOG.md` (raíz) | El repositorio: cada cambio. Un cambio de mantenimiento (`CLAUDE.md`, `.claude/`, `tests/`, `maintainers/`, `i18n/`, `docs/`, el `README.md` de la raíz) en detalle; un cambio del producto como una línea de resumen bajo `### Product` |
| `workspace/CHANGELOG.md` | El producto: solo un cambio en `workspace/` o `install.sh`, en detalle, para quien usa el workspace |

Ambos siguen [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) y [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

- Una versión en curso es `## [X.Y.Z] - Unreleased`.
- El incremento sigue los tipos de Conventional Commit de lo que entra en cada changelog.
- Una corrección de algo que entró en la misma versión sin publicar no es un fix: no añade entrada `### Fixed` ni
  incremento. La entrada original solo se ajusta cuando el comportamiento que describe cambió.
- Las versiones del changelog de la raíz nunca se publican por sí solas: una sección se fecha con el release del
  producto que la incluye, y enlaza a él.
- Los cambios de mantenimiento solos nunca se publican: sin una versión `Unreleased` en `workspace/CHANGELOG.md`, no hay
  nada que publicar.

## Publicar el producto

`/caw-merge --main`, solo cuando el owner lo pide. La versión es la `Unreleased` de `workspace/CHANGELOG.md`.

1. Un clon de release `tmp/work/<yyyy-mm-dd>-release-vX-Y-Z/` en la rama `fix/release-vX-Y-Z`.
2. Una verificación completa con contexto limpio: la suite desde la última etiqueta, la instalación de prueba y una
   revisión del rango.
3. Correcciones de lo que encuentre, como commits en el clon.
4. `workspace/VERSION` a `X.Y.Z`, la sección del producto fechada, la sección de la raíz fechada y enlazada al release,
   las traducciones de los documentos cambiados, y el commit `chore(release): X.Y.Z`.
5. El clon entra en `developer` como en cualquier merge.
6. Cada paso público lo confirma el owner, uno por uno: `main` (un fast-forward desde `developer`, o un pull request
   si se rechaza), la etiqueta `vX.Y.Z` (nunca movida ni borrada) y el release de GitHub, con la sección del changelog
   del producto como notas.
7. Una comprobación de que una instalación nueva toma la etiqueta nueva.

Un paso público rechazado o fallido detiene el release ahí. No se fuerza nada.

## Instaladores y etiquetas

El instalador y `aiwp` solo toman etiquetas `vX.Y.Z`, nunca una rama: un workspace ejecuta una versión publicada
([cómo funcionan las actualizaciones](commands-and-updates.md#cómo-funcionan-las-actualizaciones)).
