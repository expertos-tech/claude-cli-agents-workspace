<!-- source: docs/hooks.md sha256:b844f1efc10b1173a4294a37da67faad60d98b8463803b5f5d402b87dfc9b07e -->

# Hooks

[English](../../../docs/hooks.md) · Português (Brasil) · [Español](../../es/docs/hooks.md)

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
