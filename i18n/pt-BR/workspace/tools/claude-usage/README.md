<!-- source: workspace/tools/claude-usage/README.md sha256:abaeaefa883640b119a4e75de72d167252418d2b81a7c53c5e067589e454570b -->

# claude-usage

- [O que é](#o-que-é)
- [Como rodar](#como-rodar)
- [O que lê e o que imprime](#o-que-lê-e-o-que-imprime)
- [Como testar](#como-testar)
- [Critérios de aceitação](#critérios-de-aceitação)

## O que é

Script de um arquivo, só com a biblioteca padrão do Python, que lê os registros locais das sessões do Claude Code e mostra quanto cada modelo foi usado. Conta só as sessões desta máquina. O modelo de cada resposta vem da própria resposta da API, o mesmo dado contra o qual os limites do plano são contados. Serve, por exemplo, para ver quando o modelo padrão mudou.

## Como rodar

Não há o que instalar. Execute da raiz do workspace, com Python 3.9 ou mais novo:

```bash
# Respostas e tokens por dia e por modelo
python3 -I tools/claude-usage/claude_usage.py daily --since 2026-11-16T04:59

# Uma linha por sessão, da que mais gerou tokens para a que menos gerou
python3 -I tools/claude-usage/claude_usage.py sessions --since 2026-11-16 --sort tokens

# Modelo da primeira resposta de cada sessão nova, por dia
python3 -I tools/claude-usage/claude_usage.py default-model
```

| Opção | Comandos | Padrão |
| --- | --- | --- |
| `--since` | os três | `daily` e `sessions`: 7 dias atrás; `default-model`: 35 dias atrás |
| `--sort start\|tokens` | `sessions` | `start` (ordem de início) |
| `--projects-dir` | os três | `~/.claude/projects` |

- `--since` aceita data (`2026-11-16`) ou data e hora (`2026-11-16T04:59`), no fuso horário da máquina, ou com `Z` ou deslocamento. Valor inválido, ou pasta de `--projects-dir` inexistente, termina com código 2.
- Os relatórios usam o fuso horário da máquina.
- `sessions` lista só as sessões que tiveram resposta de modelo, e mostra o modelo da conversa principal e o dos subagentes.
- `-I` roda o Python isolado: ignora as variáveis `PYTHON*`, o `site` do usuário e a pasta atual, para que um módulo solto não seja importado no lugar de um da biblioteca padrão.

## O que lê e o que imprime

Lê os arquivos `*.jsonl` sob `--projects-dir` modificados desde `--since`. Linhas corrompidas, JSON que não é objeto e arquivos que somem durante a leitura são ignorados. Cada resposta da API é contada uma vez, mesmo quando aparece repetida.

Imprime só contagens e rótulos: tokens, número de prompts, os 8 primeiros caracteres do id da sessão, o nome da pasta do projeto, o nome do ponto de entrada (`entrypoint`) e o nome dos modelos. Nunca imprime o conteúdo das mensagens; o texto do prompt é lido apenas para saber se existe. Tudo é local: o script não usa rede.

O nome da pasta do projeto codifica o caminho absoluto da pasta de trabalho, então o login da pessoa pode aparecer na parte impressa (o relatório `sessions` mostra os últimos 32 caracteres). Não cole relatórios sem olhar antes.

## Como testar

```bash
cd tools/claude-usage && python3 -I -B -m unittest discover -s tests
bash scripts/validate.sh --path tools/claude-usage
```

Os testes usam transcritos fictícios em pasta temporária, com `HOME` apontado para ela, e não leem o `~/.claude` real. Os testes são opcionais: ferramenta só precisa compilar, e o `validate.sh` não mede cobertura nesta pasta. A suíte tem 62 testes, com 100% de cobertura de linhas e de ramos.

## Critérios de aceitação

Os ids aparecem nos nomes dos testes em `tests/test_claude_usage.py`.

| Id | Critério |
| --- | --- |
| AC-1 | `daily`: respostas e os quatro tipos de token somados por dia e modelo, mais a parcela de cada modelo no total de saída |
| AC-2 | `sessions`: início, pasta, pontos de entrada, prompts, saída e modelos da conversa principal e dos subagentes; `--sort start` ou `tokens`; sessão só com prompts fica de fora |
| AC-3 | `default-model`: só a primeira resposta da conversa principal de cada transcrito conta, no dia em que ocorreu |
| AC-4 | O que é uma resposta: contada uma vez por par de id da mensagem e id da requisição, em todos os transcritos; sintética, sem modelo ou sem uso não conta |
| AC-5 | `--since`: data começa à meia-noite do fuso; data e hora é local, salvo deslocamento; padrão de 7 dias (`daily`, `sessions`) e 35 (`default-model`); valor inválido sai com código 2 |
| AC-6 | Dado ruim é ignorado e nunca derruba a execução: linhas que não são JSON, JSON que não é objeto, campos com tipo errado, bytes fora de UTF-8, arquivos que somem, substituto isolado na saída |
| AC-7 | `--projects-dir`: vale nos três comandos, aceita `~`, pasta inexistente ou que não é pasta sai com código 2, caracteres de glob valem só por si; padrão `~/.claude/projects` |
| AC-8 | Formato de saída fixo, conferido contra relatórios de referência (golden) da mesma árvore; sem dados no período, os cabeçalhos continuam; o comando é obrigatório |
