<!-- source: workspace/scripts/performance/README.md sha256:f026b1a5f52b6b39e29726e92378849ab9bb6603d7c7c5acf5b02a8e1e92adf3 -->

# performance

Mede como o workspace se comporta nas sessões reais: quanto do trabalho do Claude vai para o processo do workspace, quanto para validação e gate, quantas perguntas chegam a você, quanto contexto cada sessão carrega e quanto tempo leva até a primeira edição.

## Como rodar

Precisa da stack de observabilidade no ar. Sem ela o script recusa, com o comando que a sobe:

```bash
docker compose -f tools/observability/compose.yaml up -d
python3 -I -B scripts/performance/measure.py --name after-the-gate
```

- Grava `custom/performance/<yyyy-mm-dd>-<name>.md` (nome padrão: `measurement`). Sem `custom/`, passe `--out <folder>`.
- O período começa onde a medição anterior terminou. `--since <date>` escolhe outro início; `--all` mede tudo o que os transcripts ainda guardam.
- O relatório compara com a medição anterior e põe lado a lado as últimas cinco (`--compare <n>` muda o número).
- **Por projeto:** linhas entregues por hora de trabalho do agente, em código e em documentação, com o total do período e a taxa anterior de cada projeto. As horas vêm dos turnos das sessões, cada pedido atribuído ao projeto que as ferramentas dele mais tocaram (`projects/<project>`, um clone em `tmp/work/`); as linhas vêm dos commits de agente (`[#automatic-agent-commit]`) dos repositórios de `projects/`, sem arquivos gerados (lock, build, imagens, fontes). Com menos de meia hora num projeto, a taxa fica em branco. Sem `git` na máquina, a seção diz isso e o resto do relatório sai igual.
- Os números de cada relatório vão nele mesmo, num comentário `performance-data`, e é dali que a próxima medição compara.

## O que lê

- Os transcripts das sessões abertas na raiz do workspace (`~/.claude/projects/<root>/*.jsonl`), só a sessão principal; subagentes ficam de fora.
- Só agregados saem do script: nenhum texto de prompt, nenhum conteúdo de arquivo.
- O formato dos transcripts é interno do Claude Code e pode mudar entre versões. Os transcripts são apagados depois de `cleanupPeriodDays` (30 dias por padrão): meça antes disso.
- A classificação de cada tool call é heurística (`classify` e `SCRIPT_CATEGORY` em `measure.py`). Quando um script do workspace muda de nome ou de papel, atualize ali.

## Como testar

```bash
cd scripts && python3 -I -B -m unittest discover -s tests -p 'test_performance.py'
```
