<!-- source: maintainers/backlog/README.md sha256:c3c389dfc0be8c7685fddee325f13883091e53af6d8b832dbccde622e7013f6d -->

# Backlog

[English](../../../../maintainers/backlog/README.md) · [Português (Brasil)](../../../pt-BR/maintainers/backlog/README.md) · Español

El backlog del propio workspace: ideas, defectos, mejoras y deudas técnicas del producto en `workspace/` que aún no se
convirtieron en un pedido. Un ítem por archivo. Ninguna regla carga esta carpeta: Claude lee o cambia un ítem solo
cuando se lo pides.

## Crear un ítem

1. Crea `maintainers/backlog/<short-kebab-title>.md`, por ejemplo `export-usage-report.md`.
2. Completa la tabla y las secciones de abajo, y borra lo que no aplique.

O pídeselo a Claude. Nunca escribas un secreto, un dato personal ni un término de empresa: el backlog es público.

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

| Status | Cuándo |
| --- | --- |
| `idea` | Registrada, aún sin criterios de aceptación |
| `ready` | Tiene criterios de aceptación y puede convertirse en un pedido |
| `in progress` | Se convirtió en un pedido y está en ejecución |
| `done` | Entregado |
| `dropped` | No se hará; di por qué en "Notes" |

Un ítem terminado o descartado se queda en su archivo, con el estado actualizado, para conservar el motivo.

## Convertir un ítem en un pedido

Los criterios de aceptación y la lista de fuera de alcance tienen el mismo formato que la plantilla de pedido del
producto (`workspace/templates/request.md`). Cópialos a un pedido en `maintainers/requests/`, o pídele a Claude que
implemente el ítem por el nombre de su archivo. Lo que le falte al ítem se vuelve una pregunta antes de empezar el
trabajo.
