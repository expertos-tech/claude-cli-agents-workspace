<!-- source: docs/repository.md sha256:1228db8a4c22eae1ba86b00e57209517b357df37964c47940723eaeb2ba01b24 -->

# Repositorio

[English](../../../docs/repository.md) · [Português (Brasil)](../../pt-BR/docs/repository.md) · Español

## Estructura del repositorio

| Ruta | Qué es |
| --- | --- |
| `workspace/` | El producto: `AGENTS.md`, `rules/`, `scripts/`, `tools/`, `docker/`, `docs/`, `assets/`, `templates/`, `VERSION`, `CHANGELOG.md`. Es lo que se instala |
| `CLAUDE.md`, `.claude/` | El mantenimiento del repositorio, en su raíz: el proceso, las reglas, las skills (`.claude/skills/caw-*`) y los agentes de quien mantiene el producto, y la configuración que deja las reglas del producto fuera de esa sesión |
| `docs/` | La documentación del repositorio: cómo usar el workspace, contribuir, mantenerlo y publicar sus releases |
| `CHANGELOG.md` | El historial del repositorio: cada cambio, con los del producto como resúmenes ([releases](releases.md)) |
| `tests/` | La suite del repositorio (`check.sh`) y la instalación de prueba |
| `maintainers/` | El trabajo de quien mantiene el proyecto, a la vista: backlog, planes, pedidos y revisiones |
| `i18n/` | Las traducciones de los documentos y READMEs (`pt-BR`, `es`), con la misma estructura que el repositorio |
| `install.sh` | El instalador |
| `tmp/` | Borrador ignorado por git: instalaciones de prueba y notas privadas |
