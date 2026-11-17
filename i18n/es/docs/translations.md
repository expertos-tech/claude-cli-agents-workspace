<!-- source: docs/translations.md sha256:225842fa6e74ffb3491965ef0b2cd24fdedc8f99c74a25f8eba7bbc723662f35 -->

# Traducciones

[English](../../../docs/translations.md) · [Português (Brasil)](../../pt-BR/docs/translations.md) · Español

Los documentos se escriben en inglés y se traducen a dos idiomas: `pt-BR` y `es`. La regla es
`.claude/rules/docs.md`; la suite la verifica.

## Qué se traduce

- el `README.md` de la raíz y cada `README.md` del repositorio, incluidos los del producto y los de las herramientas;
- las páginas de `docs/` de la raíz;
- las páginas de `workspace/docs/`, salvo los registros de decisión (`workspace/docs/decisions/`);
- las páginas de `workspace/tools/*/docs/`.

## Qué nunca se traduce

Reglas, skills, agentes, scripts y hooks, `CLAUDE.md`, `.claude/`, `maintainers/`, los changelogs y los registros de
decisión. Se quedan en inglés.

## Dónde vive una traducción

`i18n/<locale>/<misma ruta que el archivo en inglés>`, con `<locale>` `pt-BR` o `es`. La traducción de `docs/hooks.md`
es `i18n/pt-BR/docs/hooks.md` y `i18n/es/docs/hooks.md`. Mantén la estructura del archivo en inglés. El código, las
rutas, los comandos y los términos técnicos del mercado se quedan en inglés.

## La línea de origen

La línea 1 de cada traducción es exactamente:

```text
<!-- source: <path from the repository root> sha256:<sha256 of the English file> -->
```

Recalcúlala después de la última edición del archivo en inglés (`sha256sum <path>`). Un cambio en un documento en
inglés actualiza ambas traducciones en el mismo commit.

## Enlaces de idioma

Justo bajo el H1, cada página en inglés tiene una línea que enlaza a sus traducciones (`English · Português (Brasil) ·
Español`); las traducciones llevan la misma línea, con enlace de vuelta. En el `README.md` de la raíz va centrada, en
HTML.

## Enlaces en una traducción

Un enlace apunta a la traducción del mismo idioma cuando existe, y si no al original en inglés, con una ruta relativa a
la traducción.

## La verificación

`bash tests/check.sh --all` tiene un paso `i18n`: falla ante una traducción ausente, desactualizada (el hash difiere) o
huérfana (cuyo origen en inglés no existe). Se corrige traduciendo el cambio y fijando la línea de origen.
