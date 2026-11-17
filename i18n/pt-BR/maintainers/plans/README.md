<!-- source: maintainers/plans/README.md sha256:09b6ec770d2312538eab18fb6a67b4cbf43c495942dbf4dafe1c51b71f4bf70a -->

# Planos

[English](../../../../maintainers/plans/README.md) · Português (Brasil) · [Español](../../../es/maintainers/plans/README.md)

Os desenhos aprovados por trás dos pedidos em `maintainers/requests/`. Um plano diz o que construir e por quê; o pedido
dele diz o que precisa ser verdade quando estiver pronto. Leia o plano antes de rodar o pedido.

| Plano | Cobre | Pedido |
| --- | --- | --- |
| `distribution.md` | As três pastas, o instalador e o `aiwp`, a sincronização do manifesto, a instalação só de leitura, a manutenção na raiz do repositório, plataformas e idiomas | Construído na publicação da 0.1.0 |
| `normalize-projects.md` | A análise e a migração de projetos, o marcador de versão e a conferência a cada interação | `requests/done/normalize-projects.md` |
| `rules-config.md` | `custom/rules-config.json`, `custom/my-rules/`, o core obrigatório e `/rules` | `requests/rules.md` |
| `normalize-rules.md` | Trazer as regras de um workspace mais antigo para `custom/my-rules/` e listar os projetos dele | `requests/normalize-rules.md` |
| `run-tools.md` | O compose único das ferramentas e o `/run-tools` | `requests/run-tools.md` |
| `tools-hub.md` | A página de ferramentas, o ícone do menu e a área Workspace | `requests/tools-hub.md` |
| `fork-my-rules.md` | Devolver regras próprias ao projeto por fork e pull request | `requests/fork-my-rules.md` |

A ordem em que rodam está em `maintainers/requests/README.md`.
