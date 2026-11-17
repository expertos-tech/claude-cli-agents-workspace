<!-- source: docs/contributing.md sha256:bba3576d4af8b0194938380fd8e00c83f76eb68f84a4fa8f37fc7d094b205b2f -->

# Contribuir

[English](../../../docs/contributing.md) · [Português (Brasil)](../../pt-BR/docs/contributing.md) · Español

Este workspace nació del uso diario: de equivocarse, medir y simplificar. Mejora con cada persona que lo usa en un
proyecto real.

¿Encontraste una forma mejor de hacer algo? ¿Corregiste un defecto? ¿Escribiste un hook que ahorra preguntas, una regla
más clara, una herramienta útil? **Compártelo.** Haz un fork del repositorio, haz tu cambio y envía un pull request.

## Cómo enviar un cambio

1. **Bug o idea:** abre un issue con lo que pasó, lo que esperabas y cómo reproducirlo.
2. **Fork** del repositorio y crea una rama desde `developer`, la rama predeterminada, con el nombre
   `<type>/<kebab-description>` (por ejemplo `fix/session-title-prefix`).
3. **Cambio:** pequeño y enfocado, con un commit por cambio lógico en Conventional Commits
   (`type(scope): subject`, en inglés).
4. **Antes de enviar:** `bash tests/check.sh --all` debe pasar. Ejecuta el lint, el escaneo de secretos, las suites de
   los scripts y la comprobación que mantiene los datos de empresa fuera del repositorio.
5. **Pull request** a `developer`, que diga el porqué y no solo el qué.

## Qué tener en cuenta

- **Traducciones:** un cambio en un documento en inglés actualiza sus traducciones en `i18n/pt-BR/` y `i18n/es/` en el
  mismo commit ([traducciones](translations.md)).
- **Lo tuyo se queda contigo:** empresa, proyectos, identidad visual y pedidos se quedan en tu capa custom, nunca en el
  pull request.
- **Regla nueva:** prefiere un hook o un script probado a más texto, y di lo que el cambio añade o quita de cada sesión
  (un paso, una pregunta, texto cargado).
- **Mantén desde la raíz del repositorio:** clona este repositorio y abre `claude` en su raíz. El `CLAUDE.md` y la
  `.claude/` de la raíz dan a esa sesión el proceso de mantenimiento (plan, pedido, etapas, pruebas, revisión) y dejan
  las reglas del producto fuera de ella, porque allí son el código que se edita. [Mantenimiento](maintenance.md) lo
  explica.
