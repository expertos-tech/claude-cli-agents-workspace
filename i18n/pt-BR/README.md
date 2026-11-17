<!-- source: README.md sha256:5a05e088078e5004c9da8056d08b776791db4410533ec4ba6ab49e29d950674b -->

# Claude CLI Agents Workspace

<p align="center"><img src="../../workspace/assets/logo.png" alt="Claude CLI Agents Workspace" width="320"></p>

<p align="center"><a href="../../README.md">English</a> · Português (Brasil) · <a href="../es/README.md">Español</a></p>

Um workspace para o **Claude Code CLI**. Você diz **o que** quer, e o Claude decide **como**, trabalhando num clone
isolado onde tudo é livre. A verificação pesada e as perguntas para você ficam num lugar só: o gate que leva o trabalho
para a branch base do projeto.

> **Feito para a CLI.** Hooks, permissões, skills e o nome das sessões foram desenhados e testados no Claude Code de
> terminal (`claude`). O app do Claude (desktop ou web) e as extensões de IDE provavelmente conseguem abrir o workspace,
> mas podem tratar hooks, permissões e comandos de outro jeito; ali, o que esta documentação descreve não é
> garantido.

## Faça parte

Este workspace nasceu do uso diário e fica melhor a cada pessoa que o usa num projeto de verdade. Encontrou um jeito
melhor de fazer algo, corrigiu um defeito, escreveu um hook ou uma regra mais clara? **Compartilhe**: faça um fork do
repositório, faça a sua mudança e mande um pull request. Vamos construir uma comunidade open source em torno dele. Os
passos estão em [Contribuindo](docs/contributing.md).

## Quick start

1. Confira os [requisitos](docs/getting-started.md#requisitos): Linux, macOS ou WSL2, `git`, `bash`, `python3`, Docker
   e o Claude Code CLI com login feito.
2. Instale e crie o seu workspace:

   ```bash
   curl -fsSL https://raw.githubusercontent.com/expertos-tech/claude-cli-agents-workspace/main/install.sh | bash
   ```

3. Abra-o na raiz: `cd ~/my-workspace && aiwp`.
4. Traga um projeto para `projects/` e peça na sessão o que quiser, por exemplo:
   `no my-app, cria um endpoint GET /health que responde 200 com a versão da aplicação`.

Cada passo, com as opções, está em [Primeiros passos](docs/getting-started.md).

## Documentação

| Página | O que cobre |
| --- | --- |
| [Primeiros passos](docs/getting-started.md) | Requisitos, instalação, criação, abertura e o primeiro pedido |
| [Funcionalidades](docs/features.md) | O que você recebe e a camada custom |
| [Comandos e atualizações](docs/commands-and-updates.md) | Os comandos `aiwp` e como funcionam as atualizações |
| [Hooks](docs/hooks.md) | Os hooks que rodam na sua máquina |
| [Guia do produto](workspace/docs/usage.md) | O uso diário do workspace |
| [Contribuindo](docs/contributing.md) | Issues, fork, branch, pull request |
| [Manutenção](docs/maintenance.md) | Como o repositório é mantido |
| [Releases](docs/releases.md) | Branches, changelogs e a release do produto |
| [Traduções](docs/translations.md) | O que é traduzido e como é verificado |
| [Repositório](docs/repository.md) | A estrutura do repositório |

## Licença

[MIT](../../LICENSE).
