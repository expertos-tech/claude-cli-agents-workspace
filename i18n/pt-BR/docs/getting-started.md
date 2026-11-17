<!-- source: docs/getting-started.md sha256:184dd1b855e3665064f92e2d4107204300326725850e16f521dfd5f07685d4d2 -->

# Primeiros passos

[English](../../../docs/getting-started.md) · Português (Brasil) · [Español](../../es/docs/getting-started.md)

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
  Chrome, clicar, ler o console e tirar capturas de tela, para validar layout e fluxo de tela sozinho
  (`/pilot auto`). Ela não funciona dentro do WSL: no Windows, esses testes ficam com você (`/pilot manual`).

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
`claude` na versão atual do workspace. Abra a sessão sempre na raiz do workspace, mesmo para trabalhar num projeto só: é
ali que as regras e os hooks valem. Recomendado: o auto mode do Claude Code. O workspace deixa para ele o julgamento do
que é destrutivo e guarda nos hooks só o que nunca pode acontecer.

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
[workspace/docs/usage.md](../workspace/docs/usage.md).
