<!-- source: docs/maintenance.md sha256:15b1d2a7623544cc1105895d68119cf1966e795dce5b79203fbf587b64d1b884 -->

# Manutenção

[English](../../../docs/maintenance.md) · Português (Brasil) · [Español](../../es/docs/maintenance.md)

Como este repositório é mantido. Uma sessão aberta na raiz do repositório muda o produto; não o usa. As regras dessa
sessão são o `CLAUDE.md` da raiz e `.claude/rules/`.

## Mantenha a partir da raiz do repositório

- O produto é `workspace/`. O `AGENTS.md`, o `CLAUDE.md`, as `rules/`, as skills, os agentes e os hooks dele são código
  sendo editado, nunca instruções para a sessão de manutenção. O `.claude/settings.json` os mantém fora do contexto com
  `claudeMdExcludes`.
- Inicie o Claude Code na raiz do repositório. As configurações do projeto são lidas da pasta onde a sessão começa, então
  uma sessão iniciada dentro de `workspace/` não enxerga as configurações da raiz.
- Os padrões de `claudeMdExcludes` casam com caminhos absolutos. Os commitados supõem que a pasta do clone se chama
  `claude-cli-agents-workspace`. Num clone com outro nome, adicione os mesmos padrões com o seu caminho absoluto em
  `.claude/settings.local.json`, que o git ignora.
- Nenhum hook do produto roda aqui. Nunca rode `workspace/scripts/setup-claude.sh` dentro de `workspace/`; exercite os
  hooks numa instalação de teste (`/caw-test-install`).

## O processo

Detalhe em `.claude/rules/process.md`. A correção de um erro de digitação pode pular plano e pedido.

1. **Avaliar** o produto e, só para leitura, o uso real dele (um workspace instalado, transcrições, o registro de
   prompts, medições). Um achado que nomeia empresa, cliente ou projeto fica no `tmp/`, ignorado pelo git.
2. **Planejar** em `maintainers/plans/`: o problema, as opções, uma recomendação e decisões numeradas para o dono.
3. **Pedir**, com as respostas do dono, em `maintainers/requests/`: objetivo, BR-n, AC-n, fora de escopo e as etapas com
   o effort.
4. **Executar** em etapas, com subagentes quando valer a pena, sempre com modelo e effort explícitos, e uma revisão
   independente, em contexto limpo, de hooks e segurança.
5. **Provar**: `bash tests/check.sh --all` a cada mudança; `/caw-test-install` quando o instalador, um hook ou o
   `setup-claude.sh` mudam.
6. **Fechar**: commits em Conventional Commits, um por mudança lógica; push só quando o dono pede.

## `maintainers/`

O trabalho de quem mantém, às claras. Nada ali chega a um workspace instalado.

| Pasta | O que guarda |
| --- | --- |
| `maintainers/backlog/` | Ideias, defeitos e débitos do produto que ainda não viraram pedido, um item por arquivo |
| `maintainers/plans/` | Desenhos: problema, opções, recomendação, decisões numeradas. Um plano que o dono aprova é registrado em `maintainers/requests/done/` na aprovação |
| `maintainers/requests/` | Pedidos prontos para rodar com `/caw-prompt`; a ordem em que rodam está no README dela |
| `maintainers/requests/done/` | Pedidos entregues e os planos aprovados |
| `maintainers/reviews/` | Relatórios de revisões independentes; criada pela primeira |

## Skills

As skills de manutenção levam o prefixo `caw-`, para não colidir com as skills do produto de mesmo propósito (`/merge`,
`/commit`, `/prompt`...). Elas ficam em `.claude/skills/`.

| Skill | Argumentos | O que faz |
| --- | --- | --- |
| `/caw-check` | `[--base <ref>] [--floor] [extra check.sh options]` | Roda `tests/check.sh --all` com as flags certas e explica cada falha |
| `/caw-commit` | `[--all]` | Um Conventional Commit por mudança lógica da sessão, por caminho; sem push, sem branch, sem tag |
| `/caw-draft-prompt` | `[plan \| request] [ideas \| path]` | Transforma ideias num plano ou num pedido, perguntando só o que não tem melhor alternativa |
| `/caw-prompt` | `[file name \| path]` | Roda um pedido escrito num arquivo: um nome simples é procurado em `maintainers/requests/`, `tmp/prompts/` e depois `tmp/`; sem argumento, lê `tmp/prompt.md` |
| `/caw-test-install` | `[--keep]` | Instala um workspace descartável a partir da árvore atual em `tmp/test-install/` e exercita hooks e scripts |
| `/caw-merge` | `[<work>/<clone> \| --main]` | Leva o trabalho para a `developer` pelos gates e pelos dois changelogs; `--main` lança a release do produto ([releases](releases.md)) |

## Subagentes

Toda chamada de subagente declara o seu modelo e o seu effort; uma chamada que os herdaria é um erro. Effort `high`
para hooks, o instalador, segurança, ações arriscadas e toda revisão (`.claude/rules/models.md`).

| Tarefa | Agente | Modelo | Effort |
| --- | --- | --- | --- |
| Lacunas de um plano ou pedido | `requirements-analyst` | claude-opus-5-5 | high |
| Revisão independente | `reviewer` | claude-opus-5-5 | high |
| Scripts, hooks e seus testes | `script-engineer` | claude-opus-5-5 | high para hooks e o instalador, senão medium |
| Docs e as traduções pt-BR e es | `docs-writer` | claude-sonnet-5-5 | medium |
| Rodar a suíte, devolvendo só as linhas de resultado | `verifier` | claude-haiku-5-5 | low |
| Docs oficiais, versões, preços | `web-researcher` | claude-sonnet-5-5 | high |

O padrão é nenhum subagente. Subagentes nunca fazem commit nem push: quem faz é a sessão principal.

## Onde o trabalho acontece

- **Num clone:** o `/caw-prompt` abre um clone do repositório em `tmp/work/<yyyy-mm-dd>-<slug>/`, numa branch de trabalho
  `<type>/<slug>` a partir de `origin/developer`, e trabalha só ali. A branch recebe push depois de cada commit.
- **Direto na `developer`:** uma sessão na raiz que não abriu clone trabalha na `developer`.
- **Planos e pedidos** são mostrados ao dono no idioma dele e salvos em inglês.

## `/caw-merge`

Só quando o dono pede. Rodá-lo é a ordem do dono para os pushes que ele faz.

- **De um clone:** faz o merge de `origin/developer` no clone, escreve os changelogs, roda
  `bash tests/check.sh --all --base origin/developer` (e `/caw-test-install` quando o instalador, um hook ou o
  `setup-claude.sh` mudaram), depois um `reviewer` em contexto limpo. Só então, na raiz, avança a `developer` em
  fast-forward até o commit do clone, faz o push, apaga a branch de trabalho e o clone.
- **Na developer:** os mesmos gates sobre os commits desde o último commit de changelog
  (`docs(changelog)` ou `chore(release)`), depois o push.
- **`--main`:** a release do produto ([releases](releases.md)).

Nunca faz merge com um check falhando ou um BLOCKER aberto, e nunca reescreve a `developer` nem a `main`.

## Repositório público

Este repositório é público: tudo o que é commitado, incluindo `maintainers/`, pode ser lido por qualquer pessoa
(`.claude/rules/security.md`).

- Nunca commite um termo de empresa, o nome de um cliente ou projeto, um caminho pessoal, um endereço de e-mail, uma URL
  interna, um token ou qualquer segredo. O `bash tests/check.sh --all` varre o repositório com a lista de termos do
  dono; uma ocorrência é reescrita, nunca isentada, e nunca impressa numa issue, commit, pull request ou relatório.
- Análises privadas do uso real ficam no `tmp/`, ignorado pelo git, ou na camada custom do dono; o repositório recebe o
  achado geral.
- Arquivos `.env` nunca são lidos nem editados; os modelos `.env.example` são.
- Exemplos e fixtures usam dados inventados (`acme`, `example.com`, `billing-api`).
- Uma mudança que enfraquece uma proteção do produto (um hook, uma regra de deny, o gate, uma permissão de arquivo)
  precisa da aprovação explícita do dono e de uma revisão independente.
