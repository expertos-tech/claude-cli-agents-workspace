<!-- source: README.md sha256:d8e456251d94fe8bb9e4f03432f0654800646781daf87f54bade67093ea44d05 -->

# Claude CLI Agents Workspace

<p align="center"><img src="../../workspace/assets/logo.png" alt="Claude CLI Agents Workspace" width="320"></p>

<p align="center"><a href="../../README.md">English</a> · Português (Brasil) · <a href="../es/README.md">Español</a></p>

Um workspace para o **Claude Code CLI**. Você diz **o que** quer, e o Claude decide **como**, trabalhando num clone
isolado onde tudo é livre. A verificação pesada e as perguntas para você ficam num lugar só: o gate que leva o trabalho
para a branch base do projeto.

> **Feito para a CLI.** Hooks, permissões, skills e o nome das sessões foram desenhados e testados no Claude Code de
> terminal (`claude`). O app do Claude (desktop ou web) e as extensões de IDE provavelmente conseguem abrir o workspace,
> mas podem tratar hooks, permissões e comandos de outro jeito; ali, o que esta página descreve não é garantido.

## O que você recebe

- **Regras** para o agente: uma página que vale em toda sessão (`AGENTS.md`) e regras por assunto (git, segurança,
  qualidade, documentação, frontend, infraestrutura, modelos, revisão), lidas quando o assunto aparece.
- **Skills**: comandos de barra para o fluxo do dia a dia (`/merge`, `/commit`, `/push`, `/validate`, `/draft-prompt`,
  `/prompt`, `/pilot`, `/local-env`, `/normalize-projects`).
- **Agentes**: subagentes para requisitos, arquitetura, implementação, testes, revisão, verificação, infraestrutura,
  scripts, documentação e pesquisa, cada um com o seu modelo e o seu effort.
- **Hooks** que guardam só o que nunca pode acontecer sem você: escrita git fora do gate, mudança na nuvem, apagar
  banco de dados, segredo num commit. [Hooks que rodam na sua máquina](#hooks-que-rodam-na-sua-máquina) lista todos.
- **Um gate de merge**: o trabalho acontece num clone em `tmp/work/`, e o `/merge` o leva para a branch `developer` do
  projeto depois da suíte de testes inteira, das validações, de uma varredura de segredos e de uma revisão contra o seu
  pedido.
- **Uma camada custom**: o seu próprio repositório git privado em `custom/`, para a sua empresa, a nuvem, a identidade
  visual, a lista de projetos, os pedidos e as lições. Ela nunca entra neste repositório.
- **Ferramentas**: um Grafana local para a telemetria do Claude Code, um console de contêineres (Docker CE no Linux,
  Colima no macOS), simuladores de login e de Safe Browsing, um console do Azurite, um relatório de uso e um alerta de
  modelo. Cada uma tem o seu README em `workspace/tools/`.

## Requisitos

- **Linux ou macOS.** No **Windows, só pelo WSL2**: instale uma distribuição Linux (Ubuntu, por exemplo) e faça tudo de
  dentro dela, com a mesma estrutura do Linux. O workspace, os projetos, o Docker e o `claude` ficam no sistema de
  arquivos do WSL (`~/...`), nunca em `/mnt/c`. Não há versão nativa para Windows.
- `git`, `bash`, `python3` e Docker.
- O Claude Code CLI instalado e com login feito: `claude` abre uma sessão.
- **Opcional, mas importante: a stack de observabilidade** (`workspace/tools/observability/`, um Grafana local em
  <http://localhost:3000>). Ela mostra o que cada sessão custa em tokens, tempo e modelo; sem medição, não há como saber
  se uma mudança nas regras melhorou ou piorou o trabalho.
- **Recomendado: o [Claude in Chrome](https://claude.com/chrome)**, a extensão que deixa o Claude abrir páginas no seu
  Chrome, clicar, ler o console e tirar capturas de tela, para validar layout e fluxo de tela sozinho (`/pilot auto`).
  Ela não funciona dentro do WSL: no Windows, esses testes ficam com você (`/pilot manual`).

## Quick start

### 1. Instale e crie o workspace

```bash
curl -fsSL https://raw.githubusercontent.com/expertos-tech/claude-cli-agents-workspace/main/install.sh | bash
```

`curl | bash` roda o que o script tiver naquele momento. Para lê-lo antes de rodar:

```bash
curl -fsSL -o install.sh https://raw.githubusercontent.com/expertos-tech/claude-cli-agents-workspace/main/install.sh
less install.sh
bash install.sh
```

O instalador confere os pré-requisitos e diz o que falta, sem instalar nada por conta própria. Ele clona o repositório
na sua pasta de dados local, na tag da release mais nova, põe o comando `aiwp` em `~/.local/bin` e em seguida cria o seu
workspace com `aiwp new` e o adiciona ao registro de workspaces. Não precisa de administrador nem de `sudo`.

Ele pergunta onde o workspace vai, no terminal (funciona com `curl | bash`), conforme a pasta em que roda:

- **Uma pasta vazia:** `1) Install here` ou `2) Give another path`.
- **Uma pasta com conteúdo:** só o caminho, de uma pasta nova ou vazia. Uma resposta ruim é perguntada de novo.

Depois o `aiwp new` pede a URL do seu repositório custom: crie um repositório privado vazio no seu servidor git e
informe a URL. Um repositório vazio ganha um esqueleto e um primeiro commit; uma resposta vazia cria um repositório
local.

Para pular as perguntas, informe a pasta:

```bash
curl -fsSL https://raw.githubusercontent.com/expertos-tech/claude-cli-agents-workspace/main/install.sh | bash -s -- ~/my-workspace
AIWP_WORKSPACE=~/my-workspace bash install.sh
```

O argumento vence `AIWP_WORKSPACE`. Sem terminal e sem pasta, o instalador instala só a pasta de dados e imprime como
criar um workspace depois (`aiwp new <pasta>`). Rodar o instalador de novo atualiza a pasta de dados e nunca um
workspace: quem faz isso é o `aiwp update`. Quando a pasta de dados já está instalada, a pergunta também oferece só
atualizá-la (`3)`, ou um caminho vazio).

### 2. Crie outro workspace

```bash
aiwp new ~/other-workspace
```

Cada workspace é uma cópia do produto na sua própria pasta, e todos compartilham a instalação da pasta de dados.

### 3. Abra

```bash
cd ~/my-workspace && aiwp
```

O `aiwp` confere se há release nova e, quando há, avisa e manda rodar `aiwp update`; ele nunca atualiza. Depois inicia o
`claude` na versão atual do workspace. Abra a sessão sempre na raiz
do workspace, mesmo para trabalhar num projeto só: é ali que as regras e os hooks valem. Recomendado: o auto mode do
Claude Code. O workspace deixa para ele o julgamento do que é destrutivo e guarda nos hooks só o que nunca pode
acontecer.

### 4. Traga um projeto e peça

```bash
git clone <url do seu projeto> projects/my-app
git -C projects/my-app switch developer
```

Depois, na sessão:

```text
no my-app, cria um endpoint GET /health que responde 200 com a versão da aplicação
```

O Claude pergunta só o que impede de começar, abre um clone em `tmp/work/<data>-<assunto>/my-app/`, diz o caminho e
trabalha só ali, com testes. Cada commit vai para o remoto depois de uma varredura de segredos. Quando terminar:

```text
/merge <data>-<assunto>/my-app
```

O gate traz a `developer` atualizada, roda a suíte inteira e as validações, procura segredos, mostra o que sai da base e
pede uma revisão contra o seu pedido. Você só é perguntado se aparecer algo que o pedido não explica. Para pedidos
maiores, escreva o pedido com `/draft-prompt` e rode com `/prompt`. O guia completo está em
[workspace/docs/usage.md](workspace/docs/usage.md).

## Comandos

| Comando | Faz |
| --- | --- |
| `aiwp` | Abre o workspace da pasta atual: confere se há release nova e só avisa, depois inicia o `claude` com os argumentos que você passar depois de `--` |
| `aiwp new <pasta>` | Cria um workspace novo: copia o produto, pede o seu repositório custom, monta a `.claude/` e o adiciona ao registro |
| `aiwp list` | Lista os workspaces registrados com a versão e o estado de cada um |
| `aiwp forget <pasta>` | Tira um workspace do registro; nunca toca na pasta |
| `aiwp update` | Lista os workspaces registrados e pergunta: atualizar todos, escolher quais ou cancelar |
| `aiwp update --all` | Atualiza todos os workspaces registrados sem perguntar; os fixados ficam como estão |
| `aiwp update <pasta>` | Atualiza só esse workspace |
| `aiwp rollback` | Volta para a versão do backup mais recente e fixa o workspace nela |
| `aiwp repair` | Restaura os arquivos do core que diferem do manifesto ou estão com a permissão errada |
| `aiwp check` | Diz numa linha se existe uma release mais nova, sem atualizar nada |
| `aiwp version` | Mostra a versão instalada e a do workspace |

## Como funcionam as atualizações

São três lugares:

| Lugar | O que é |
| --- | --- |
| Este repositório | Onde o workspace é desenvolvido. As releases são tags `vX.Y.Z` |
| A sua pasta de dados local: `${XDG_DATA_HOME:-~/.local/share}/claude-cli-agents-workspace` no Linux e no WSL, `~/Library/Application Support/claude-cli-agents-workspace` no macOS | O repositório completo, clonado pelo instalador. O `aiwp` o leva para a tag da release mais nova. Ninguém edita aqui |
| Cada workspace que você cria | Uma cópia só de `workspace/`, mais o seu `custom/`, `projects/` e `tmp/` |

A pasta de dados guarda o `workspaces.json`, o registro de todos os workspaces instalados (caminho, versão, criado,
atualizado). O `aiwp new` registra um workspace, e a primeira execução do `aiwp` num que não está registrado o adiciona.
O `aiwp list` mostra cada um com o estado: em dia, atualização disponível, core alterado, pasta ausente, fixado ou
interrompido no meio.

- **Conferência:** o `aiwp` procura uma tag nova (`git ls-remote --tags`) no máximo uma vez por dia, com limite de 5 s.
  Sem rede, ele segue. Quando há release nova, imprime "A new workspace version X was detected (this workspace: Y). Run
  `aiwp update` to update; opening this workspace on Y." e abre na versão atual. Abrir nunca atualiza. Numa sessão, o
  hook de início de sessão dá o mesmo aviso: feche a sessão e rode `aiwp update` num terminal.
- **Atualizar, só por comando, num terminal, sem sessão aberta:** o `aiwp update` lista todos os workspaces registrados
  e pergunta `[1] Update all` (o padrão), `[2] Choose which` (por número) ou `[3] Cancel`. Ele leva a pasta de dados
  para a release mais nova uma vez, depois atualiza cada workspace escolhido e termina com uma tabela-resumo. Um
  workspace com o core alterado, ou com a pasta ausente, é pulado e relatado; os outros seguem. O `aiwp update <pasta>`
  atualiza só aquele; o `aiwp update --all` atualiza todos sem perguntar e deixa como estão os workspaces fixados
  (depois de um `aiwp rollback`); escolher um fixado por número ou por pasta o atualiza e tira a fixação. Sem terminal,
  é preciso `--all` ou uma pasta. Antes de trocar um workspace em que o `claude` está rodando, o `aiwp update` diz o
  processo e pergunta; com `--all` ele pula esse workspace, a menos que você some `--force`. O código de saída é 1
  quando um workspace foi pulado por core alterado, por um `claude` rodando ou por erro.
- **Nunca dentro de uma sessão:** numa sessão do Claude Code (a ferramenta Bash, um hook) o `aiwp` recusa `update`,
  `rollback`, `repair`, `forget`, a abertura e um `new` sobre uma pasta registrada, e o `guard-bash` também os recusa:
  eles mudam as regras da sessão aberta. `aiwp list`, `check`, `version` e `--help` funcionam em qualquer lugar. Um
  comando desconhecido é erro de uso: os argumentos para o `claude` vão depois de `--`.
- **Core só de leitura:** os arquivos do produto num workspace são só de leitura (pastas e executáveis 555, arquivos
  444), e o workspace não tem `.git`: `custom/` e cada projeto são os repositórios. Para remover um workspace, devolva
  antes a permissão de escrita: `chmod -R u+w <pasta> && rm -rf <pasta>` (faça push do `custom/` e dos seus projetos
  antes). Graváveis são só `custom/`, `projects/`, `tmp/`, `.claude/`, `.history/` e uma
  lista fechada de saídas geradas das ferramentas (os dados do Grafana, `node_modules`, as páginas compiladas e os
  binários dos consoles).
- **Manifesto:** cada workspace guarda a versão e o hash de cada arquivo que recebeu. Uma atualização troca só o que a
  release nova mudou, apaga o que ela removeu e pula o workspace se um arquivo do core difere do manifesto (a
  atualização mostra isso no resumo); o `aiwp repair` o restaura.
- **Backup:** os arquivos são trocados por renomeação, depois de um backup em `.aiwp/backup/<versão>/` (os 3 últimos
  ficam), com um diário. Se uma atualização cair no meio, o `aiwp` se recusa a abrir o workspace até o `aiwp repair` (ou
  o `aiwp update`) restaurá-lo. O `aiwp rollback` volta para a versão do backup mais recente.
- **Só `workspace/` é instalado**, por uma lista de inclusão. Nada mais deste repositório chega ao seu workspace.

## Hooks que rodam na sua máquina

O workspace roda estes hooks em toda sessão aberta num workspace (`workspace/rules/agents/settings.json`). São scripts
em `workspace/scripts/`; cada um imprime a referência completa com `--help`. O que eles não cobrem segue o modo de
permissão do Claude Code que você escolheu.

| Hook | Quando | O que faz |
| --- | --- | --- |
| `guard-bash.sh` | Antes de todo comando Bash | Recusa escrita git em `projects/` e no core fora do gate, mudança de Terraform fora do `aiwp-cmds.sh apply`, `git push --no-verify`, commit no `custom/` que leva um `.env` ou um segredo, `chmod`, `chown` ou `git init` em caminhos do core, e `aiwp update`, `rollback`, `repair`, `forget` e a abertura dentro de uma sessão (eles mudam as regras da sessão aberta ou iniciam o `claude` dentro dela). Pergunta antes de apagar um banco de dados ou um volume do Docker, antes de um release, de um apply ou de descartar um clone, e antes de configuração git que pode rodar um comando. É um quebra-molas com a sua confirmação por trás, não uma sandbox |
| `guard-subagent-model.sh` | Antes de toda chamada de subagente | Recusa forks e modelos fora da lista permitida, pergunta antes de um subagente em Fable e define o modelo numa chamada que herdaria um |
| `setup-claude.sh` | Início da sessão | Monta a `.claude/`, ignorada pelo git, a partir das regras, skills e agentes do produto mais a sua camada custom |
| `release-notice.sh` | Início da sessão | Roda `aiwp check` (uma resposta por dia, limite de tempo curto, silencioso sem rede) e, quando há release mais nova, faz o Claude avisar para fechar a sessão e rodar `aiwp update` num terminal. Nunca atualiza nada |
| `prompt-log.py` | Início da sessão | Registra os seus prompts, a partir das transcrições das sessões, em `custom/prompts/log/`, por projeto e por semana, e mostra um resumo do último dia. Nunca faz push |
| `session-title.py` | A cada prompt que você envia | Dá à sessão o nome do projeto no `/prompt` (`my-app-1`, `my-app-2`...) e lembra a sessão quando um projeto que você cita não está normalizado ou está atrás da versão do workspace |
| `aiwp-cmds.sh _stop-check` | Quando o Claude termina uma resposta | Não deixa a resposta terminar com um commit que está só na sua máquina, num clone de trabalho |

As varreduras de segredos usam o gitleaks no Docker. Nenhum hook manda dados para lugar nenhum: as únicas chamadas de
rede são as do próprio git, para os seus remotos e para as tags deste repositório.

## A camada custom

O `custom/` é o **seu** repositório git privado, separado do produto, e o único lugar para o que é seu: nome e grafia da
empresa, nuvem e tenant, identidade visual, a lista dos seus projetos, os pedidos escritos, as lições, os `.env`
preenchidos (`custom/env/`, sempre ignorados pelo git) e o registro de prompts. O workspace funciona sem ela e pergunta,
quando precisa, a nuvem, a identidade visual e a pasta de cada projeto. Ela nunca entra num pull request para este
repositório.

## Estrutura do repositório

| Caminho | O que é |
| --- | --- |
| `workspace/` | O produto: `AGENTS.md`, `rules/`, `scripts/`, `tools/`, `docker/`, `docs/`, `assets/`, `templates/`, `VERSION`, `CHANGELOG.md`. É o que é instalado |
| `CLAUDE.md`, `.claude/` | A manutenção do repositório, na raiz dele: o processo, as regras, as skills e os agentes de quem mantém o produto, e a configuração que deixa as regras do produto fora dessa sessão |
| `tests/` | A suíte do repositório (`check.sh`) e a instalação de teste |
| `maintainers/` | O trabalho de quem mantém o projeto, às claras: backlog, planos, pedidos e revisões |
| `i18n/` | As traduções dos documentos e READMEs (`pt-BR`, `es`), com a mesma estrutura do repositório |
| `install.sh` | O instalador |
| `tmp/` | Rascunho ignorado pelo git: instalações de teste e notas privadas |

## Faça parte

Este workspace nasceu do uso diário: de errar, medir e simplificar. Ele fica melhor a cada pessoa que o usa num projeto
de verdade.

Encontrou um jeito melhor de fazer algo? Corrigiu um defeito? Escreveu um hook que poupa perguntas, uma regra mais
clara, uma ferramenta útil? **Compartilhe.** Faça um fork do repositório, faça a sua mudança e mande um pull request.

- **Bug ou ideia:** abra uma issue com o que aconteceu, o que você esperava e como reproduzir.
- **Mudança:** um fork, uma branch e um pull request pequeno e focado, que diga o porquê, e não só o quê.
- **Mantenha a partir da raiz do repositório:** clone este repositório e abra o `claude` na raiz dele. O `CLAUDE.md` e
  a `.claude/` da raiz dão a essa sessão o processo de manutenção (plano, pedido, etapas, testes, revisão) e deixam as
  regras do produto fora dela, porque ali elas são o código sendo editado.
- **Antes de enviar:** `bash tests/check.sh --all` passando. Ele roda o lint, a varredura de segredos, as
  suítes dos scripts e o check que mantém dado de empresa fora do repositório.
- **Traduções:** uma mudança num documento em inglês atualiza as traduções dele em `i18n/pt-BR/` e `i18n/es/` no mesmo
  commit.
- **O que é seu fica com você:** empresa, projetos, identidade visual e pedidos ficam na sua camada custom, nunca no
  pull request.
- **Regra nova:** prefira um hook ou um script testado a mais texto, e diga o que a mudança acrescenta ou tira de toda
  sessão (um passo, uma pergunta, texto carregado).

## Licença

[MIT](../../LICENSE).
