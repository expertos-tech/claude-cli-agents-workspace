<!-- source: workspace/docs/single-agent.md sha256:1f24769bd13f90027ff3313c616ec07d89d3e164ef1ad9cf1e357fc4c35655c0 -->

# Modo single-agent

Guia para trabalhar focado num alvo, só você e um agente, sem as instruções, os hooks e as skills do workspace.

- [Instalar](#instalar)
- [Abrir uma sessão](#abrir-uma-sessão)
- [O comando /single-agent](#o-comando-single-agent)
- [O que continua valendo](#o-que-continua-valendo)
- [Histórico](#histórico)
- [Levar o trabalho à main](#levar-o-trabalho-à-main)

## Instalar

Uma vez, no seu terminal:

```bash
ln -sf "<workspace>/scripts/single-claude.sh" ~/.local/bin/single-claude
```

O link aponta para a cópia do script que é do próprio workspace, então uma atualização do workspace também atualiza o comando.

## Abrir uma sessão

```bash
single-claude [<path>] [--commit] [--merge] [--review] [-- <claude arguments>]
```

- Alvo: um repositório de `projects/` (em qualquer nível), uma ferramenta sua em `custom/tools/` (o caminho `tools/<name>` significa o mesmo) ou uma POC de `custom/pocs/`. Sem caminho, vale a pasta atual. A raiz do workspace, uma pasta do `tools/` do produto (só leitura), uma subpasta de um item e um item que a camada custom ignora são recusados, com o motivo.
- O comando prepara o alvo (recria o `SINGLE-AGENT.md` e garante `/SINGLE-AGENT.md` no `.gitignore` do alvo, sem commit), reserva o nome `single-agent-default-<n>` e abre o `claude` na pasta do alvo.
- A sessão não carrega `CLAUDE.md`, `AGENTS.md`, settings, hooks, skills nem agentes do workspace (`--setting-sources user`); o seu `~/.claude` continua valendo. As instruções dela são o `SINGLE-AGENT.md`.
- Nesse modo o hook `guard-bash` do workspace não está carregado: nada pede confirmação antes de commit, merge, push ou comando destrutivo. O comando recusa rodar dentro de uma sessão do Claude Code (`CLAUDECODE=1`); isso é só um quebra-molas, que `env -u CLAUDECODE` contorna.
- Tudo depois de `--` vai direto ao `claude`, por exemplo `-- --model sonnet`.

Opções, só desta sessão; nenhuma faz push:

| Opção | Efeito |
| --- | --- |
| nenhuma | commit, branch, merge e push só quando você pede, uma operação por pedido; um teste falhando aparece antes do commit, sem impedi-lo |
| `--commit` | commit sozinho a cada passo com os testes passando |
| `--merge` | uma branch própria por pedido e o merge de volta no fim; inclui `--commit`; pergunta antes de voltar na `main` |
| `--review` | antes de cada commit, review por um subagente novo, sem o contexto da sessão; um BLOCKER vem para você decidir |

Numa POC ou numa ferramenta, os commits caem num repositório que outras sessões dividem (o da camada custom, ou o do workspace): a sessão só adiciona caminhos do alvo e nunca troca de branch ali.

## O comando /single-agent

Existe só na sessão aberta pelo `single-claude`. Digite `/single-agent`: o Claude Code completa para `/single-agent:single-agent`, o nome com o plugin na frente, e roda o mesmo comando.

| Uso | Efeito |
| --- | --- |
| `/single-agent [<path>] [options]` | recria e carrega o `SINGLE-AGENT.md`; as opções dadas trocam as da sessão |
| `/single-agent update <path>` | reaplica o modelo e o `.gitignore` naquele alvo e lista o que mudou; sem caminho, recusa |
| `/single-agent --rename <task>` | renomeia a sessão para `single-agent-<task>` |
| `/single-agent --help` | mostra o uso e as opções |

O `SINGLE-AGENT.md` sai de `rules/single-agent/single-agent-template.md`; editar o arquivo no alvo não adianta, porque cada execução o recria.

## O que continua valendo

Sem opção para desligar: segurança dos dados, confirmação antes de ação destrutiva, leitura de temperatura antes de tarefa pesada e só a nuvem e o tenant da camada custom (`custom/rules/company.md`). A sessão single ignora por completo as mensagens de sessões `ai-workspace-*` (não responde, não age e nem comenta com você), e as sessões do workspace não mandam mensagem a ela e nunca leem `SINGLE-AGENT.md`.

## Histórico

A sessão single registra cada pedido em `single-agent-history.txt`, na raiz do alvo, no formato do `history.txt`, e esse arquivo é commitado com o alvo. Para trazer as entradas ao histórico do workspace, peça numa sessão do workspace; ela roda:

```bash
bash scripts/single-agent.sh import-history --target <target path>
```

As entradas novas entram no `history.txt` do mesmo alvo, com o `REQUEST` começando por `[single-agent <date>]`. Uma segunda importação só traz o que for novo.

## Levar o trabalho à main

O modo single-agent nunca mescla na `main` sozinho. Abra uma sessão normal na raiz do workspace e peça uma revisão de contexto limpo do que está na `developer` e não está na `main` (num repositório sem `developer`, diga a branch). Com zero BLOCKER e os checks passando, a `main` só anda pela release, `bash scripts/aiwp-cmds.sh release <repo>`, a seu pedido (`rules/git.md` "Gate").
