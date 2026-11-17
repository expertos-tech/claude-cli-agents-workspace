<!-- source: maintainers/backlog/README.md sha256:c3c389dfc0be8c7685fddee325f13883091e53af6d8b832dbccde622e7013f6d -->

# Backlog

[English](../../../../maintainers/backlog/README.md) · Português (Brasil) · [Español](../../../es/maintainers/backlog/README.md)

O backlog do próprio workspace: ideias, defeitos, melhorias e débitos técnicos do produto em `workspace/` que ainda não
viraram pedido. Um item por arquivo. Nenhuma regra carrega esta pasta: o Claude lê ou muda um item só quando você pede.

## Crie um item

1. Crie `maintainers/backlog/<short-kebab-title>.md`, por exemplo `export-usage-report.md`.
2. Preencha a tabela e as seções abaixo, e apague o que não se aplica.

Ou peça ao Claude. Nunca escreva um segredo, um dado pessoal ou um termo de empresa: o backlog é público.

```markdown
# Short title

| Field | Value |
| --- | --- |
| Type | feature, defect, improvement or technical debt |
| Status | idea, ready, in progress, done or dropped |
| Priority | high, medium or low |
| Target | workspace, or tools/<name> |
| Created | YYYY-MM-DD |
| Source | who asked, or where it came up |

## Problem

What is wrong or missing, and who feels it, in 2 to 5 lines.

## Expected result

What changes when the item is done.

## Acceptance criteria

- AC-1: Given ..., when ..., then ...

## Out of scope

- What this item does not cover.

## Notes

Links, dependencies and decisions already taken.
```

## Campos

| Status | Quando |
| --- | --- |
| `idea` | Registrado, ainda sem critérios de aceite |
| `ready` | Tem critérios de aceite e pode virar um pedido |
| `in progress` | Virou um pedido e está rodando |
| `done` | Entregue |
| `dropped` | Não será feito; diga por quê em "Notes" |

Um item done ou dropped continua no seu arquivo, com o status atualizado, para guardar o motivo.

## Transforme um item em pedido

Os critérios de aceite e a lista de fora de escopo têm o mesmo formato do modelo de pedido do produto
(`workspace/templates/request.md`). Copie-os para um pedido em `maintainers/requests/`, ou peça ao Claude que
implemente o item pelo nome do arquivo. O que faltar no item vira pergunta antes de o trabalho começar.
