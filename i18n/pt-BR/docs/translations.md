<!-- source: docs/translations.md sha256:9386c43a384d50fc639d1997ac03130221e4d9163f4e0757e5ff0f244f62fc9a -->

# Traduções

[English](../../../docs/translations.md) · Português (Brasil) · [Español](../../es/docs/translations.md)

Os documentos são escritos em inglês e traduzidos para dois idiomas: `pt-BR` e `es`. A regra é
`.claude/rules/docs.md`; a suíte a verifica.

## O que é traduzido

- o `README.md` da raiz e todo `README.md` do repositório, incluindo os do produto e os das ferramentas;
- as páginas do `docs/` da raiz;
- as páginas de `workspace/docs/`, exceto os registros de decisão (`workspace/docs/decisions/`);
- as páginas de `workspace/tools/*/docs/`.

## O que nunca é traduzido

Regras, skills, agentes, scripts e hooks, `CLAUDE.md`, `.claude/`, os arquivos de `maintainers/` que não são
READMEs, os changelogs e os registros de
decisão. Eles ficam em inglês.

## Onde fica uma tradução

`i18n/<locale>/<mesmo caminho do arquivo em inglês>`, com `<locale>` `pt-BR` ou `es`. A tradução de `docs/hooks.md` é
`i18n/pt-BR/docs/hooks.md` e `i18n/es/docs/hooks.md`. Mantenha a estrutura do arquivo em inglês. Código, caminhos,
comandos e os termos técnicos do mercado ficam em inglês.

## A linha de origem

A linha 1 de cada tradução é exatamente:

```text
<!-- source: <caminho a partir da raiz do repositório> sha256:<sha256 do arquivo em inglês> -->
```

Recalcule-a depois da última edição do arquivo em inglês (`sha256sum <caminho>`). Uma mudança num documento em inglês
atualiza as duas traduções no mesmo commit.

## Links de idioma

Logo abaixo do H1, cada documento traduzido fora de `workspace/` tem uma linha que leva às traduções (`English · Português (Brasil) ·
Español`); as traduções levam a mesma linha, apontando de volta. No `README.md` da raiz ela é centralizada, em HTML.

## Links numa tradução

Um link aponta para a tradução do mesmo idioma quando ela existe; senão, para o original em inglês, com um caminho
relativo à tradução.

## O check

O `bash tests/check.sh --all` tem uma etapa `i18n`: ela falha com uma tradução ausente, desatualizada (o hash difere) ou
órfã (cujo original em inglês não existe). Corrija traduzindo a mudança e ajustando a linha de origem.
