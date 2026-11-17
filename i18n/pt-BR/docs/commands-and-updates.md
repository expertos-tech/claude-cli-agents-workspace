<!-- source: docs/commands-and-updates.md sha256:83b4ef9f8458442b906524a519232cffec49b15b850a6743d67a327a54bd4299 -->

# Comandos e atualizações

[English](../../../docs/commands-and-updates.md) · Português (Brasil) · [Español](../../es/docs/commands-and-updates.md)

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
  444), e o workspace não tem `.git`: `custom/` e cada projeto são os repositórios. Graváveis são só `custom/`,
  `projects/`, `tmp/`, `.claude/`, `.history/` e uma lista fechada de saídas geradas das ferramentas (os dados do
  Grafana, `node_modules`, as páginas compiladas e os binários dos consoles). Para remover um workspace, devolva antes
  a permissão de escrita: `chmod -R u+w <pasta> && rm -rf <pasta>` (faça push do `custom/` e dos seus projetos antes).
- **Manifesto:** cada workspace guarda a versão e o hash de cada arquivo que recebeu. Uma atualização troca só o que a
  release nova mudou, apaga o que ela removeu e pula o workspace se um arquivo do core difere do manifesto (a
  atualização mostra isso no resumo); o `aiwp repair` o restaura.
- **Backup:** os arquivos são trocados por renomeação, depois de um backup em `.aiwp/backup/<versão>/` (os 3 últimos
  ficam), com um diário. Se uma atualização cair no meio, o `aiwp` se recusa a abrir o workspace até o `aiwp repair` (ou
  o `aiwp update`) restaurá-lo. O `aiwp rollback` volta para a versão do backup mais recente.
- **Só `workspace/` é instalado**, por uma lista de inclusão. Nada mais deste repositório chega ao seu workspace.
