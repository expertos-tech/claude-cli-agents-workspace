<!-- source: docs/repository.md sha256:1228db8a4c22eae1ba86b00e57209517b357df37964c47940723eaeb2ba01b24 -->

# Repositório

[English](../../../docs/repository.md) · Português (Brasil) · [Español](../../es/docs/repository.md)

## Estrutura do repositório

| Caminho | O que é |
| --- | --- |
| `workspace/` | O produto: `AGENTS.md`, `rules/`, `scripts/`, `tools/`, `docker/`, `docs/`, `assets/`, `templates/`, `VERSION`, `CHANGELOG.md`. É o que é instalado |
| `CLAUDE.md`, `.claude/` | A manutenção do repositório, na raiz dele: o processo, as regras, as skills (`.claude/skills/caw-*`) e os agentes de quem mantém o produto, e a configuração que deixa as regras do produto fora dessa sessão |
| `docs/` | A documentação do repositório: como usar o workspace, contribuir, mantê-lo e lançar uma release |
| `CHANGELOG.md` | O histórico do repositório: toda mudança, com as mudanças do produto em resumo ([releases](releases.md)) |
| `tests/` | A suíte do repositório (`check.sh`) e a instalação de teste |
| `maintainers/` | O trabalho de quem mantém o projeto, às claras: backlog, planos, pedidos e revisões |
| `i18n/` | As traduções dos documentos e READMEs (`pt-BR`, `es`), com a mesma estrutura do repositório |
| `install.sh` | O instalador |
| `tmp/` | Rascunho ignorado pelo git: instalações de teste e notas privadas |
