<!-- source: workspace/scripts/README.md sha256:f8d70c963263f286cbd565fae8e11ebbc15afb75362da6a96a5c5bed1a66a41f -->

# scripts/

Catálogo dos scripts do workspace. Regras: `rules/scripts.md`. Consulte esta lista antes de escrever um comando longo.
Rode como `bash scripts/<name>.sh`. Cada script mostra a referência completa com `--help`: esta página só diz o que existe.

Num workspace instalado, os scripts nunca escrevem no core: a saída deles vai para `custom/`, `projects/`, `tmp/`, `.history/` ou a pasta de saída de uma ferramenta (`bash scripts/aiwp.sh _writable` as lista).

## Validação

| Script | Faz | Exemplo |
| --- | --- | --- |
| `validate.sh` | Roda em Docker as ferramentas de validação de `docker/compose.yaml` e mostra PASS/FAIL por check: `secrets`, `vuln`, `iac`, `shell`, `dockerfile`, `markdown`, `mermaid`, `terraform`, `python`, `typescript`, `coverage` (e `cost`). O check `secrets` também falha quando o git rastreia um `.env` ou um `local.settings.json`. O compose lê `custom/env/docker.env` (senão, os padrões de `docker/.env.example`) e monta o workspace só leitura | `bash scripts/validate.sh --path projects/billing --only secrets,markdown` |
| `aiwp-cmds.sh` | Área de trabalho: `open` abre um clone de um projeto (ou do `custom/`, para uma POC) em `tmp/work/<work>/`, na branch do pedido, com push a cada commit depois de uma varredura de segredos dos commits; `run`, `status`, `push`, `close`; `up` publica no Docker local marcando antes uma tag de rollback, e `rollback` volta para ela. O `_stop-check` dele é o hook `Stop` | `bash scripts/aiwp-cmds.sh --help` |
| `aiwp-gate.sh` | Os únicos caminhos para `projects/`, chamados pelo `aiwp-cmds.sh`: `gate` (fase 1: base atualizada, testes completos, `validate.sh`, arquivos de env e segredos, a auditoria do que sai da base; fase 2 `--merge`: fast-forward do sha verificado; uma branch de normalização é julgada pelo que ela acrescenta), `release` (`developer` para `main`; um pull request quando a `main` é protegida), `apply` (plano do Terraform a partir da `main`, depois o apply desse plano) e os passos do `/normalize-projects`: `developer`, `checkpoint` (as tags anotadas, enviadas) e `bring` (`--from`) | `bash scripts/aiwp-gate.sh --help` |
| `check-workspace.sh` | Gate do repositório do produto, uma ferramenta de manutenção (num workspace instalado ele imprime uma linha e sai com 2), para o checkout que o contém (só a pasta do produto, quando ela fica numa subpasta do repositório git dela): números de decisão únicos, nenhum termo da lista de termos (`AIWP_TERMS_FILE`, senão `custom/core-terms.txt`) no repositório, todo documento traduzido (`i18n`, só quando a raiz do repositório tem `i18n/`), `rules/agents/settings.json` válido, arquivos de POC que fazem parse, `validate.sh` nos arquivos alterados e as suítes de scripts cujas entradas mudaram | `bash scripts/check-workspace.sh` |
| `check-ledger.sh` | Biblioteca carregada pelos dois scripts acima: registra cada PASS sob um hash das entradas dele, para que um check rode uma vez por estado do código (`CACHED <check>`). Não se roda à mão | — |
| `heavy-run.sh` | Roda uma tarefa pesada de CPU ou GPU (gráficos, renderização 3D): na hora abaixo de 88 °C, senão quando o mais quente entre CPU e GPU marcar 85 °C ou menos; sem fila (`rules/machine-load.md`). Saída 75: ainda quente depois de 30 minutos, nada rodou | `bash scripts/heavy-run.sh -- <render command>` |
| `performance/measure.py` | Mede o workspace a partir dos transcripts das sessões (processo, validação e gate, perguntas, contexto, tempo até a primeira edição) e grava `custom/performance/<date>-<name>.md`, comparado com o relatório anterior e com os últimos cinco. Só roda com a stack de observabilidade no ar | `python3 -I -B scripts/performance/measure.py --name <name>` |
| `prompt-log.py` | Registra todo prompt humano dos transcripts das sessões (a raiz do workspace mais as pastas de `custom/prompts/log/sources.json`) em `custom/prompts/log/<project>/<year>-W<week>.md`, com os commits de agente e os merges do gate que vieram depois, e resumos de dia e de semana montados a partir desses dados. Só acrescenta: um transcript expirado mantém os registros. `--context` é um hook `SessionStart` (mostra o último dia com atividade, nunca derruba a sessão); `--commit` varre os arquivos alterados com gitleaks em Docker, remove o que encontrar e os commita no `custom/`, nunca faz push | `python3 -I -B scripts/prompt-log.py sync --commit` |
| `sonar.sh` | Stack opcional do SonarQube (`up`, `down`, `status`, `scan`), só quando o humano pede. Lê `custom/env/docker-sonar.env`; o scan monta a pasta só leitura e mantém o `.scannerwork` no `/tmp` do contêiner | `bash scripts/sonar.sh scan --key billing --path projects/billing` |

## Hooks

Ligados em `rules/agents/settings.json`. Cada um lê o JSON do hook na stdin.

| Script | Faz |
| --- | --- |
| `guard-bash.sh` (+ `guard-bash.py`) | `PreToolUse` em `Bash`. Recusa escrita git em `projects/` e no core, mudanças de Terraform, `push --no-verify` e um commit no `custom/` que leva um segredo. Num workspace instalado, também recusa `chmod`, `chown`, `chgrp`, `git init` e `git clone` que chegam ao core só leitura (links, globs, `-R`, `find`, `xargs`, `sudo` e `bash -c` são seguidos; os caminhos graváveis vêm de `aiwp.sh _writable`, e se isso falhar ele pergunta), e `aiwp update`, `rollback`, `repair`, `forget` e a abertura (`aiwp` sozinho, `aiwp -- ...`) dentro de uma sessão. Pergunta antes de apagar um banco de dados e antes de `aiwp-cmds.sh release`, `checkpoint`, `developer --create`, `gate --untested`, `apply --apply` e `close --discard`. Lê a linha do jeito que um shell a agrupa; o `--help` lista tudo e o que ele não vê. Um erro interno pergunta, nunca passa calado |
| `release-notice.sh` | `SessionStart`: num workspace instalado, roda `aiwp.sh check --quiet` (uma resposta por dia, tempo limitado, seguro offline) e, quando há release mais nova, acrescenta ao contexto da sessão que o Claude avisa para você fechar a sessão e rodar `aiwp update` num terminal. Só detecta; fora isso, silencioso |
| `guard-subagent-model.sh` (+ `guard-subagent-model.py`) | `PreToolUse` em `Agent`. Nega um fork e um modelo fora da lista permitida, pergunta no Fable, define `opus` numa chamada que herdaria o modelo. Uma falha bloqueia a chamada |

## Setup e repositórios

| Script | Faz | Exemplo |
| --- | --- | --- |
| `aiwp.sh` | O comando `aiwp` (`~/.local/bin/aiwp` aponta para a cópia na pasta de dados): `new` cria um workspace (o core somente leitura, um manifesto, `custom/`) e o registra no `workspaces.json` da pasta de dados; sem comando ele abre o workspace (checagem de release que só avisa quando há uma, `setup-claude.sh`, `claude`); `list` e `forget` mostram e editam o registro; `update` lista os workspaces registrados e atualiza todos, os escolhidos, uma pasta (`<pasta>`) ou cada um (`--all`, `--force`), só por comando e num terminal; `rollback`, `repair`, `check`, `version`. Numa sessão ele recusa `update`, `rollback`, `repair`, `forget` e a abertura. As pastas graváveis de um workspace instalado estão listadas uma vez, no topo dele; o `aiwp.sh _writable` as imprime para o `guard-bash` | `aiwp new ~/my-workspace` |
| `setup-claude.sh` | Cria ou sincroniza a `.claude/` ignorada pelo git a partir de `rules/agents/`, `rules/skills/` e das `rules/*.md` que têm front matter `paths:`, mais todo `custom/rules/*.md` como `.claude/rules/custom-*.md` e os caminhos de `custom/claude-md-excludes.txt` em `claudeMdExcludes`; instala o alerta de Fable uma vez; quando falta o `custom/`, pergunta o repositório git dele (`--custom-repo <url>`). Um hook `SessionStart` o roda com `--quiet`; `--check` só relata | `bash scripts/setup-claude.sh --check` |
| `session-title.py` | Hook `UserPromptSubmit`: no `/prompt <file>`, dá à sessão o nome `<project>-<n>` pela linha `**Project:**` do arquivo, com `<n>` um a mais que o maior daquele projeto entre as sessões do workspace em execução. Em toda mensagem que cita um projeto de `projects/` ou uma POC (nome da pasta, caminho, linha `**Project:**`), acrescenta o estado dele ao contexto quando não tem marcador ou está desatualizado, para o Claude avisar e pedir para rodar `/normalize-projects`; nunca bloqueia, tem tempo limitado, silencioso em erros | — (hook) |
| `aiwp-project-state.sh` | Imprime se cada projeto e POC é um projeto do workspace: o marcador na linha 1 do `README.md` dele (da `developer`, lido com `git show`) contra o `VERSION` e o `migrations/`: sem marcador, em dia, desatualizado com as migrações pendentes, ou o próprio repositório do workspace. Só leitura; usado pelo hook, pelo `aiwp-cmds.sh open`, pelo gate e pelo `/normalize-projects` | `bash scripts/aiwp-project-state.sh billing-api` |
| `init-repo.sh` | Cria um projeto em `projects/` como repositório git independente, ou uma POC (`custom/pocs/`) ou uma ferramenta sua (`custom/tools/`) na camada custom, com o README de um projeto ou POC começando pelo marcador da versão do workspace; nunca escreve no core. Nunca sobrescreve | `bash scripts/init-repo.sh --type project --name billing-api` |
| `sync-env.sh` | Cria ou completa o `.env` preenchido a partir do `.env.example` de uma pasta, mostrando só os nomes das chaves: `custom/env/<name>.env` (modo 600) para `docker`, `docker/sonar` e `tools/<name>`, acrescentando `env/` ao `custom/.gitignore` quando falta; `<dir>/.env` para um projeto ou clone. Por trás do `/local-env` | `bash scripts/sync-env.sh --path docker` |
| `lib/env.sh` | Biblioteca: onde mora o `.env` preenchido de uma pasta do core e qual arquivo o compose lê com `--env-file`. Carregada por `sync-env.sh`, `sonar.sh` e `validate.sh` | — |
| `lib/projects.sh` | Biblioteca: o layout de `projects/` (qual pasta é repositório). Carregada por `init-repo.sh`, `history.sh`, `aiwp-project-state.sh` e `aiwp-gate.sh` | — |

## Opcionais

| Script | Faz |
| --- | --- |
| `history.sh` | Acrescenta uma entrada ao `history.txt` de um projeto, de uma ferramenta sua (`custom/tools/<name>`) ou de uma POC, ou mostra as últimas (`add`, `flush`, `show`); nunca no core. Nenhuma regra pede entradas de histórico; o `single-agent.sh import-history` o usa para trazer as entradas de uma sessão single-agent para o alvo dela |
| `single-claude.sh` | Rodado pelo humano, num terminal: abre o Claude num projeto, numa ferramenta sua ou numa pasta de POC sem as instruções, os hooks e as skills do workspace (guia em `docs/single-agent.md`) |
| `single-agent.sh` | Apoio desse modo: validação do alvo, o `SINGLE-AGENT.md` gerado, os nomes de sessão dele, `import-history` |

## Testes

Cada suíte roda sozinha, em pastas descartáveis: `bash scripts/tests/<name>/test-<name>.sh`. Os testes Python (`scripts/tests/test_*.py`) rodam sob o gate de cobertura: `bash scripts/validate.sh --only coverage`.

| Suíte | Cobre |
| --- | --- |
| `tests/check-workspace/` | `check-workspace.sh`, o ledger, e o tratamento de argumentos e o check de segredo rastreado do `validate.sh` |
| `tests/aiwp-cmds/` | `aiwp-cmds.sh`: clones, push automático, recusas do pre-push, hook Stop, close, up e rollback |
| `tests/aiwp-gate/` | `aiwp-gate.sh`: as duas fases do gate, base que andou, conflitos, a auditoria, release (uma `main` protegida e o pull request dela), apply, e os passos da normalização contra remotos bare locais: `developer`, as tags de checkpoint, `bring`, o gate que julga o que a branch acrescenta |
| `tests/guard-bash/`, `tests/test_guard_bash.py` | `guard-bash.sh` e `guard-bash.py` |
| `tests/guard-subagent-model/`, `tests/test_guard_subagent_model.py` | `guard-subagent-model.sh` e `guard-subagent-model.py` |
| `tests/setup-claude/` | `setup-claude.sh` |
| `tests/aiwp/` | `aiwp.sh`, o `install.sh` da raiz e o `release-notice.sh`, offline, sobre um repositório de fixture com duas releases |
| `tests/sync-env/` | `sync-env.sh` e `lib/env.sh` |
| `tests/heavy-run/` | `heavy-run.sh` |
| `tests/single-agent/` | `single-agent.sh` e `single-claude.sh` |
| `tests/test-projects-layout.sh` | `init-repo.sh` (o marcador incluído), `history.sh`, `lib/projects.sh` |
| `tests/aiwp-project-state/` | `aiwp-project-state.sh`: sem marcador, igual, mais antigo com e sem migração mais nova, README sem marcador, POC, o repositório do próprio workspace |

Uma suíte nova entra em `SUITES` e em `suite_inputs` do `check-workspace.sh`.
