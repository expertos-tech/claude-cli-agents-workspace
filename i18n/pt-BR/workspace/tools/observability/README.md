<!-- source: workspace/tools/observability/README.md sha256:50445715b8204008e725a704879da77fe625fe0232028de397a4fe5fd3dea8f2 -->

# observability

- [O que é](#o-que-é)
- [Como rodar](#como-rodar)
- [Configurar o Claude Code](#configurar-o-claude-code)
- [Como testar](#como-testar)
- [Como adicionar dashboards](#como-adicionar-dashboards)
- [Dashboard do Claude Code](#dashboard-do-claude-code)
- [Onde ficam os dados](#onde-ficam-os-dados)
- [Dados pessoais](#dados-pessoais)

## O que é

Stack local de telemetria do workspace, com a imagem `grafana/otel-lgtm`: Grafana, Prometheus, Loki, Tempo e o receptor OTLP em um só contêiner. Roda só na máquina local, sem login, acessível apenas por `127.0.0.1`.

| Porta | Uso |
| --- | --- |
| `3000` | Grafana: <http://localhost:3000> |
| `4317` | OTLP gRPC (a telemetria do Claude Code aponta para cá) |
| `4318` | OTLP HTTP |

## Como rodar

```bash
docker compose -f tools/observability/compose.yaml up -d
```

Para reiniciá-lo à mão: `docker compose -f tools/observability/compose.yaml restart`.

Outro projeto alcança `otel-lgtm:4317` pela rede `observability`: com esta stack já no ar, o compose dele declara `networks: {observability: {external: true}}` e cada serviço que envia telemetria lista `observability` em `networks`, junto de `default` se também falar com os outros serviços do projeto.

O Grafana segue o tema do sistema operacional, inclusive se ele mudar com a página aberta. Para fixar outro, use Administration > General > Default preferences (`/org`), campo `Interface theme`: `System preference`, `Dark` ou `Light`. A escolha vale para a organização inteira e fica em `.data/`. A paleta de comandos (`Search...` no topo, `Change theme`) só oferece `Dark` e `Light` e perde a escolha ao recarregar: o acesso é anônimo, sem perfil de usuário, e `/profile` redireciona para o login. As cores fixas do dashboard têm contraste de pelo menos 3:1 nos dois temas.

A telemetria do Claude Code é configurada em `~/.claude/settings.json`; as variáveis estão em [Configurar o Claude Code](#configurar-o-claude-code).

## Configurar o Claude Code

O arquivo `settings-telemetry.json` tem o bloco `env` com as 11 variáveis que ligam a telemetria e a apontam para esta stack:

| Variável | Valor | O que faz |
| --- | --- | --- |
| `CLAUDE_CODE_ENABLE_TELEMETRY` | `1` | Liga a telemetria |
| `CLAUDE_CODE_ENHANCED_TELEMETRY_BETA` | `1` | Liga o rastreamento (traces), que ainda está em beta |
| `OTEL_METRICS_EXPORTER` | `otlp` | Envia as métricas por OTLP |
| `OTEL_LOGS_EXPORTER` | `otlp` | Envia os eventos por OTLP |
| `OTEL_TRACES_EXPORTER` | `otlp` | Envia o rastreamento por OTLP |
| `OTEL_EXPORTER_OTLP_PROTOCOL` | `grpc` | Usa gRPC nos três sinais |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | `http://localhost:4317` | Endereço do receptor OTLP gRPC desta stack |
| `OTEL_RESOURCE_ATTRIBUTES` | `deployment.environment.name=dev` | Marca todos os dados com o ambiente |
| `OTEL_LOG_USER_PROMPTS` | `0` | Não envia o texto dos prompts; já é o padrão, e o valor fica explícito |
| `OTEL_LOG_TOOL_DETAILS` | `1` | Envia os detalhes das ferramentas: comandos Bash, nomes de servidores e ferramentas MCP, nomes de skills, a entrada de cada ferramenta e o texto completo dos erros. Fica ligado porque mantém os nomes reais de agentes, skills, plugins e MCP nos contadores de custo e tokens; sem ele, esses nomes viram `custom` ou `third-party` |
| `OTEL_EXPORTER_OTLP_METRICS_TEMPORALITY_PREFERENCE` | `cumulative` | Envia as métricas como contadores acumulados |

Não troque `cumulative`: o padrão do Claude Code é `delta`, e o Prometheus descarta métricas `delta` sem avisar.

Para instalar, na raiz do workspace, faça backup das configurações e junte o bloco a elas, sem apagar o que existe:

```bash
cp ~/.claude/settings.json ~/.claude/settings.json.bak
jq -s '.[0] * .[1]' ~/.claude/settings.json.bak tools/observability/settings-telemetry.json > ~/.claude/settings.json
```

As variáveis só valem para as sessões abertas depois da mudança.

O dashboard lê `ttft_ms` dos eventos `api_request` no Loki. A documentação oficial lista esse campo só no rastreamento, mas os eventos `api_request` do Claude Code 2.1.309 também o trazem.

### Conferir se os dados chegam

Com a stack no ar e depois de alguns minutos de uso do Claude Code:

```bash
# Métricas no Prometheus
curl -s -G http://localhost:3000/api/datasources/proxy/uid/prometheus/api/v1/query \
  --data-urlencode 'query=sum by (model) (claude_code_token_usage_tokens_total)'

# Eventos no Loki
curl -s -G http://localhost:3000/api/datasources/proxy/uid/loki/loki/api/v1/query_range \
  --data-urlencode 'query={service_name="claude-code"} | event_name="api_request"' \
  --data-urlencode 'limit=5'
```

Se nada chegar, rode uma sessão com log de depuração, numa pasta fora do workspace, e procure as linhas da telemetria. O comando faz uma chamada ao modelo; apague o `telemetry.log` depois.

```bash
claude -p "answer only: ok" --debug-file telemetry.log
grep '\[3P telemetry\]' telemetry.log
```

### Desligar

```bash
cp ~/.claude/settings.json ~/.claude/settings.json.bak
jq '.env |= with_entries(select(.key | test("^(OTEL_|CLAUDE_CODE_ENABLE_TELEMETRY$|CLAUDE_CODE_ENHANCED_TELEMETRY_BETA$)") | not))' \
  ~/.claude/settings.json.bak > ~/.claude/settings.json
docker compose -f tools/observability/compose.yaml down
```

O `down` não apaga os dados (veja [Onde ficam os dados](#onde-ficam-os-dados)).

### Limite do Cowork

O Cowork não envia para esta stack. Ele roda o exportador dentro da própria máquina virtual, e a telemetria dele só é configurada no console de administração da Anthropic, nos planos Team e Enterprise. A aba Code do app desktop lê as mesmas configurações do terminal e envia normalmente.

## Como testar

```bash
bash tools/observability/tests/run-smoke.sh
```

Cada execução sobe seu próprio projeto Compose (`observability-smoke-<pid>`), com rede própria, dados temporários numa pasta dentro de `~`, projetos fictícios e portas livres de `127.0.0.1` escolhidas pelo Docker, então várias execuções podem rodar ao mesmo tempo. Valida os critérios pela API HTTP do Grafana, inclusive que todas as consultas do dashboard são aceitas sem dados (`tests/check_dashboard_queries.py`) e o que elas devolvem com telemetria fictícia de dois modelos (`tests/check_dashboard_behavior.py`), e remove tudo no fim. Precisa de `python3`. Não toca na stack real, que pode estar rodando ao mesmo tempo. Em caso de falha, mostra as linhas de provisionamento do Grafana e guarda o log completo em um arquivo temporário. Use `--verbose` para ver o progresso e os logs completos.

## Como adicionar dashboards

| Dashboard de | Onde colocar o JSON | Pasta no Grafana | Para aparecer |
| --- | --- | --- | --- |
| Claude Code e workspace | `dashboards/workspace/<name>.json` | `workspace` | Até 15 s, sem reiniciar |
| POC | `dashboards/workspace/<poc-name>.json` | `workspace` | Até 15 s, sem reiniciar |
| Projeto | `projects/<name>/observability/dashboards/*.json` ou `projects/<client>/<name>/observability/dashboards/*.json`, no repositório do próprio projeto | `<name>` | Primeiro JSON do projeto: reiniciar o contêiner. Depois: até 15 s, sem reiniciar |

- Nenhum arquivo desta ferramenta muda ao adicionar um projeto.
- Projeto sem `observability/dashboards/*.json` não cria pasta no Grafana, e `<client>` nunca cria. Uma subpasta de um repositório em `projects/<name>/` também não cria: a primeira pasta com `.git` é sempre o projeto. Projetos com o mesmo `<name>` dividem a pasta.
- Dashboards são somente leitura no Grafana: edite o JSON. Apagar o JSON apaga o dashboard em até 15 s.
- Projeto removido perde os dashboards no próximo reinício, mas a pasta dele fica vazia no Grafana: apague-a à mão.
- Os dashboards embutidos na imagem (RED Metrics e JVM) ficam de fora de propósito.

## Dashboard do Claude Code

O dashboard `Claude Code: usage` mostra custo, tokens, sessões, ferramentas, erros e latência do período selecionado, com filtro por modelo. A descrição de cada painel diz o que ele mede e se o filtro se aplica.

As cores dos modelos se repetem em cada painel que mostra modelos: para mudar uma cor ou incluir um modelo, edite `fieldConfig.overrides` de todos eles em `dashboards/workspace/claude-code.json`; o smoke test falha se os mapas divergirem.

Os totais vêm dos eventos `api_request` no Loki, porque cada evento tem a hora exata da chamada. O contador do Prometheus não serve para isso: `last_over_time` devolve o total da sessão inteira, e `increase` perde a primeira amostra e extrapola.

Linhas alteradas, commits e tempo ativo usam o contador, com delta por sessão: último valor do período menos o último antes dele, com sessão nova partindo de 0. São aproximados (`approx.` no título): subestimam sessão retomada, porque o contador reinicia. O filtro de modelo vale para linhas alteradas, mas não para commits, tempo ativo, prompts e ferramentas (`all models` no título).

A lista de modelos do filtro é aproximada e vem do Prometheus, porque o Grafana não lista como valor de variável um campo de evento que não é label indexado no Loki. Ela mostra os modelos com aumento no contador ou com contador novo no período, e o uso dos últimos 60 segundos pode ainda não aparecer.

## Onde ficam os dados

Em `tools/observability/.data/`, ignorada pelo git e pelas verificações de `scripts/validate.sh`. É um bind mount: `docker compose down -v` não apaga os dados. Para zerar a stack, apague essa pasta com o contêiner parado.

| Sinal | Retenção | Origem |
| --- | --- | --- |
| Métricas (Prometheus) | 365 dias | `PROMETHEUS_EXTRA_ARGS` em `compose.yaml` (padrão da imagem: 15 dias) |
| Traces (Tempo) | 365 dias | `TEMPO_EXTRA_ARGS` em `compose.yaml` (padrão da imagem: 14 dias) |
| Logs (Loki) | Sem limite | Padrão da imagem; `LOKI_EXTRA_ARGS` em `compose.yaml` também tira o limite de 30 dias por consulta |
| Perfis (Pyroscope) | 31 dias | Padrão da imagem |

## Dados pessoais

O coletor apaga da telemetria nova, nas métricas, nos logs e nos traces, no item e no recurso: `user.email`, `user.id`, `user.account_uuid`, `user.account_id`, `organization.id`, `process.owner` (e a variante `process_owner`), `tool_input`, `tool_parameters`, `full_command`, `file_path`, `bash_argv0`, `process.command_args` e `process.executable.*` (`grafana/otelcol-config.yaml`, cópia da configuração da imagem que deve ser refeita ao atualizar a imagem). `session.id` fica, e o nome da ferramenta segue em `tool_name`.

O histórico não é reescrito: os dados gravados antes de esses atributos serem descartados continuam com eles até expirar pela retenção da tabela acima, e nos logs não expiram.

O Claude Code continua ENVIANDO esses dados: o e-mail e os ids da conta em todo sinal e, com `OTEL_LOG_TOOL_DETAILS=1`, a entrada e os parâmetros das ferramentas. A proteção está no coletor local, que os apaga antes de gravar. Por isso, apontar `OTEL_EXPORTER_OTLP_ENDPOINT` para um servidor compartilhado a contorna: nada do que está acima seria removido no caminho. Antes disso, revise `OTEL_LOG_TOOL_DETAILS`. O que não está na lista do coletor continua gravado; `error`, o texto completo de erro em `tool_result`, que pode trazer caminhos com o login, também é apagado, e os perfis (Pyroscope) não passam por essa limpeza. O texto dos prompts não é enviado com `OTEL_LOG_USER_PROMPTS=0`. Com o coletor local, esta telemetria OTLP não sai da máquina; a telemetria operacional da Anthropic é um fluxo separado, que estas variáveis não controlam.
