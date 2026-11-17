<!-- source: workspace/docs/usage.md sha256:fba8f7459a8e08b7ea785807b75c521ce3415fad82081ed806860fab053ebd94 -->

# Usando o workspace

Guia de uso do dia a dia. O desenho e os motivos estão em [overview.md](overview.md) e na [decisão 0001](../../../../workspace/docs/decisions/0001-base-design.md).

- [A ideia em uma frase](#a-ideia-em-uma-frase)
- [Antes da primeira sessão](#antes-da-primeira-sessão)
- [Abrir uma sessão](#abrir-uma-sessão)
- [O registro e a atualização](#o-registro-e-a-atualização)
- [Fazer um pedido](#fazer-um-pedido)
- [Onde o trabalho acontece](#onde-o-trabalho-acontece)
- [Ondas: checkpoint, merge e retomada](#ondas-checkpoint-merge-e-retomada)
- [O que o Claude pergunta a você](#o-que-o-claude-pergunta-a-você)
- [Comandos](#comandos)
- [Revisão](#revisão)
- [Testes que um humano faria à mão](#testes-que-um-humano-faria-à-mão)
- [Projetos](#projetos)
- [Várias sessões ao mesmo tempo](#várias-sessões-ao-mesmo-tempo)
- [Validar](#validar)
- [Mudar o próprio workspace](#mudar-o-próprio-workspace)
- [Quando algo dá errado](#quando-algo-dá-errado)
- [Onde está cada coisa](#onde-está-cada-coisa)

## A ideia em uma frase

Você diz **o que** quer; o Claude decide **como** e faz num clone isolado, onde tudo é livre. A verificação pesada e as perguntas ficam num lugar só: o gate que leva o trabalho para a base.

## Antes da primeira sessão

Uma vez por workspace:

| Passo | Comando |
| --- | --- |
| Criar o workspace: o core somente leitura, a camada custom em `custom/` e a pasta `.claude/` | o instalador faz isso (pergunta a pasta); outro: `aiwp new <pasta>` (pergunta a URL do repositório da camada custom, ou `--custom <url>`; uma resposta vazia cria um local) |
| Conferir o Docker, usado pelas validações | `docker info` |
| Criar o `.env` preenchido das ferramentas de validação, `custom/env/docker.env` | `/local-env docker`, numa sessão; depois preencha os valores num editor |
| Opcional: instalar o modo single-agent | `ln -sf "<workspace>/scripts/single-claude.sh" ~/.local/bin/single-claude` |

Daí em diante a `.claude/` se mantém atualizada sozinha: um hook de início de sessão roda o `setup-claude.sh`.

Para remover um workspace, devolva antes a permissão de escrita, já que o core é só leitura: `chmod -R u+w <folder> && rm -rf <folder>`. Faça push do `custom/` e dos seus projetos antes: eles vão junto.

## Abrir uma sessão

```bash
cd <workspace> && aiwp
```

O `aiwp` confere se há release nova (no máximo uma vez por dia, limite de 5 s; sem rede ele segue) e, quando há, imprime "A new workspace version X was detected (this workspace: Y). Run `aiwp update` to update; opening this workspace on Y." Depois roda o `setup-claude.sh` e inicia o `claude` na versão atual, com os argumentos que você passar depois de `--` (`aiwp -- --resume`). Abrir nunca atualiza. Depois de uma atualização interrompida, ele se recusa a abrir até o `aiwp repair` (ou o `aiwp update`) restaurar o workspace. O `claude` sozinho também abre o workspace: quando há release nova, o início da sessão avisa, e o Claude diz para você fechar a sessão e rodar `aiwp update` num terminal.

**Nunca dentro de uma sessão.** Numa sessão do Claude Code (a ferramenta Bash, um hook) o `aiwp` recusa `update`, `rollback`, `repair`, `forget`, a abertura e um `new` sobre uma pasta registrada, e o `guard-bash` também os recusa: eles mudam as regras da sessão aberta ou iniciam o `claude` dentro dela. `aiwp list`, `check`, `version` e `--help` funcionam em qualquer lugar. Um comando desconhecido é erro de uso; os argumentos para o `claude` vão depois de `--`.

- **Sempre na raiz do workspace**, mesmo para trabalhar num projeto: é ali que `AGENTS.md`, as regras e os hooks valem.
- **Uma sessão por pedido.** Terminou o assunto, use `/clear` ou abra outra sessão. Sessão longa fica cara: cada passo relê o contexto inteiro.
- **Effort:** `medium` serve para o trabalho de escopo claro. Suba para `high` com `/effort high` quando a mudança mexe em hook, permissão, merge ou segurança, ou para depurar uma falha difícil. Para um único passo difícil, escreva `ultrathink` no prompt.
- **Nome da sessão:** `/prompt <file>` dá à sessão o nome do projeto, numerado (`billing-api-1`, `billing-api-2`...), pela linha `**Project:**` do pedido: o número é o seguinte ao maior entre as sessões abertas daquele projeto. Sem `/prompt`, o Claude Code escolhe um título sozinho; `/rename <name>` troca.
- **Língua:** o Claude responde na língua em que você escreve.

## O registro e a atualização

A pasta de dados guarda o `workspaces.json`, com todos os workspaces instalados (caminho, versão, criado, atualizado). O `aiwp new` registra um workspace, e a primeira execução do `aiwp` num que não está registrado o adiciona.

| Comando | O que faz |
| --- | --- |
| `aiwp list` | Cada workspace registrado com a versão e o estado: em dia, atualização disponível (X), core alterado, pasta ausente, fixado em X, interrompido no meio |
| `aiwp forget <pasta>` | Tira a entrada (para uma pasta que sumiu, ou uma que você não atualiza mais); nunca toca na pasta |
| `aiwp update` | Lista os workspaces registrados (número, versão, estado, caminho) e pergunta `[1] Update all` (o padrão), `[2] Choose which` (números) ou `[3] Cancel` |
| `aiwp update <pasta>` | Atualiza só esse workspace, sem perguntar |
| `aiwp update --all` | Atualiza todos os workspaces registrados, sem perguntar |

A atualização acontece só por comando, num terminal, sem sessão aberta. O `aiwp update` leva a pasta de dados para a release mais nova uma vez, depois atualiza cada workspace escolhido: verifica contra o manifesto, guarda o que troca em `.aiwp/backup/<versão>/`, escreve um diário, troca os arquivos por renomeação e mostra o changelog. Um workspace com o core alterado ou com a pasta ausente é pulado e relatado, e os outros seguem; uma tabela-resumo termina a execução.

- **Workspaces fixados** (depois de um `aiwp rollback`) ficam como estão com `--all` e com Update all; escolher um por número ou por pasta o atualiza e tira a fixação.
- **Sem terminal:** é preciso `--all` ou uma pasta; senão é erro de uso (saída 2).
- **Um `claude` rodando:** antes de trocar um workspace em que um processo `claude` roda (a pasta atual dele dentro do workspace), ele diz o pid e pergunta. Com `--all` ele pula esse workspace, a menos que você some `--force`.
- **Código de saída 1** quando um workspace foi pulado por core alterado, por um `claude` rodando ou por erro.

## Fazer um pedido

**Pedido simples:** escreva em palavras.

```text
corrige o link quebrado do README do my-project
```

**Pedido funcional (uma feature, um sistema):** o formulário é `templates/request.md`. Os títulos e rótulos em negrito dele ficam em inglês; o conteúdo vai na sua língua. Há dois jeitos de preenchê-lo.

| Jeito | Como |
| --- | --- |
| A partir de ideias soltas | `/draft-prompt quero um relatório mensal de...`; o Claude pergunta só o que bloqueia, marca o resto como "decisão assumida" e salva em `custom/prompts/` |
| Você mesmo | copie `templates/request.md` para `tmp/prompt.md` e preencha |

Depois, `/prompt <file>` lê `custom/prompts/<file>`; só `/prompt` lê `tmp/prompt.md`.

- Os pedidos do `/draft-prompt` ficam em `custom/prompts/`, dentro da camada custom, um repositório git próprio: o histórico dos pedidos é versionado ali.
- Pedido entregue vai para `custom/prompts/archive/`. O que está na raiz de `custom/prompts/` ainda falta rodar.
- O `/draft-prompt` faz commit e push do pedido que criou, a cada versão. O resto (arquivar o pedido entregue, o pedido de retomada de uma onda) entra no checkpoint da onda ([Ondas](#ondas-checkpoint-merge-e-retomada)).
- O `aiwp new` monta o `custom/`: clona o repositório cuja URL você informar (um vazio ganha um esqueleto) ou cria um local. Se a pasta sumir depois, a sessão avisa no início, e `bash scripts/setup-claude.sh --custom-repo <url>` num terminal a clona.

O pedido escrito tem o tamanho do que você pediu. O `/draft-prompt` escolhe um de três portes antes de escrever, e diz qual:

| Porte | Quando | O que sai | Teto |
| --- | --- | --- | --- |
| Ajuste | muda um comportamento de algo que existe ("incluir um overlay de confirmação") | poucas linhas: o que, onde, pronto quando, effort | cerca de 120 palavras |
| Funcionalidade | capacidade nova num sistema que existe | objetivo, regras, critérios de aceite, fora de escopo, etapas e effort | cerca de 400 palavras, até 8 regras |
| Sistema | sistema novo, arquitetura, infra, integração externa, dado pessoal | o formulário completo | sem teto |

- Regra que você não disse não é escrita, a menos que sem ela dê para construir duas coisas diferentes.
- Grande ou pequeno demais? Responda "menor" ou "maior".
- Um pedido do porte ajuste pode ir direto na sessão, sem arquivo.

**Effort por etapa.** Todo pedido escrito traz o effort que cada etapa pede: uma linha no porte ajuste, e a tabela "Steps and effort" nos outros. Você ajusta a sessão com `/effort <level>` antes de cada etapa; o Claude avisa no início de cada uma qual nível ela pede e passa esse nível aos subagentes da etapa.

| Effort | Quando |
| --- | --- |
| `low` | mudança mecânica: um texto, um rótulo, um rename |
| `medium` | escopo claro; o padrão |
| `high` | onde a verificação importa: segurança, dado pessoal, dinheiro, permissão, migração, passo destrutivo, defeito em código que já existe |

O que esperar:

- O Claude pergunta as **lacunas funcionais**, todas de uma vez, antes de começar. Ele não pede sua aprovação para decisões técnicas.
- Uma pergunta ou um pedido só de leitura é respondido direto, sem branch nem teste.
- No fim, um resumo curto: o que mudou, o que foi verificado e como, o que ficou pendente. Check falhando é dito como falha, com a saída.

## Onde o trabalho acontece

- **Pergunta ou leitura:** o Claude responde; nada é aberto.
- **Mudança num projeto ou numa POC:** o Claude abre um clone em `tmp/work/<date>-<subject>/<repo>/` (`bash scripts/aiwp-cmds.sh open`), diz o caminho e trabalha só ali. No clone, tudo é livre: commit, rebase, reset, apagar, subir Docker. Cada commit vai sozinho para o remoto, depois de uma varredura de segredos dos commits que saem; um commit com segredo ou `.env` fica no clone.
- **Levar para a base:** `/merge [<work>/<clone>]`; sem argumento, o clone desta sessão. O `/merge` integra a `developer` no clone e escreve a versão do `CHANGELOG.md` do projeto (`## [X.Y.Z] - Unreleased`; as regras de versão estão em `rules/docs.md`) antes do gate. O gate traz a `developer` atualizada, roda a suíte inteira e o `validate.sh` completo, procura segredos em todos os commits que entram, escreve a auditoria do que sai da base (arquivos apagados ou renomeados para fora, testes removidos ou desligados, SQL destrutivo, infra, dependências) e pede uma revisão contra o pedido. Você só é perguntado sobre o que o pedido não explica. Depois, a `developer` avança por fast-forward exatamente para o commit que passou, e o clone pode ser fechado (`aiwp-cmds.sh close`).
- **`projects/` fica sempre na `developer`.** Ninguém edita ali; só o gate avança a base.

## Ondas: checkpoint, merge e retomada

Onda é cada etapa de um plano em etapas (a tabela "Steps and effort" do pedido). Um pedido de uma etapa só, ou sem etapas, é uma onda, que fecha quando ele termina. Pergunta ou leitura não abre onda.

- **Parte madura vai para a base na hora**, pelo gate, sem esperar o fim da onda. Base que publica em produção: o gate pergunta antes de mesclar. Branch de migração também espera a sua ordem.
- **Ao fechar a onda**, o Claude:
  1. faz o checkpoint: commit no clone, que vai sozinho para o remoto (`aiwp-cmds.sh status` mostra `not-pushed=0`);
  2. escreve em `custom/prompts/` o pedido de retomada, no formato do `templates/request.md`: onde parou (o trabalho, o clone, a branch e o sha), decisões tomadas, pendências e as próximas etapas com o effort delas. O pedido que estava rodando vai para `custom/prompts/archive/`;
  3. termina a resposta com um quadro destacado: o que foi feito, o que foi verificado, o que falta e o caminho do pedido de retomada. Depois do quadro a sessão para; a onda seguinte começa numa sessão nova, com `/prompt <file>`.
- A sessão não termina a resposta com commit fora do remoto: um hook a faz tentar de novo ou dizer por que não deu.

Regra completa: `rules/git.md`, seções "Gate" e "Waves".

## O que o Claude pergunta a você

O resto segue o modo de permissão do Claude Code: o auto mode julga o que é destrutivo.

| Situação | O que acontece |
| --- | --- |
| Gate com algo que o pedido não explica, destruição fora da máquina, ou base que publica em produção | uma pergunta, numa rodada, antes de mesclar |
| Apagar banco de dados: `docker volume rm`, `docker compose down -v`, `DROP`/`TRUNCATE`, apagar uma pasta `.data/` | o Claude diz o que vai embora, e o hook pede a sua confirmação |
| `aiwp-cmds.sh release` (a `main` anda, e a tag `vX.Y.Z` é enviada), executado por `/merge --main <repo>` | confirmação, e só a seu pedido |
| `aiwp-cmds.sh apply --apply` (Terraform na nuvem) | confirmação do plano mostrado, e só a seu pedido |
| `aiwp-cmds.sh close --discard` (apagar trabalho não mesclado) | confirmação |
| git que escreve em `projects/` ou no core, Terraform fora do `apply`, `git push --no-verify` | recusado pelo hook, com o caminho certo |
| Subagente em Fable | o hook pede a sua confirmação |
| Apagar um projeto, uma POC ou uma ferramenta inteira | o Claude mostra o comando; **você** o roda |

## Comandos

| Comando | Faz |
| --- | --- |
| `/merge [<work>/<clone>]` | Leva o trabalho de um clone (sem argumento: o desta sessão) para a `developer`, pelo gate, escrevendo o `CHANGELOG.md` |
| `/merge --main <repo>` | A release: um clone de release `fix/release-vX-Y-Z`, uma verificação completa em contexto limpo, correções, o `CHANGELOG.md` datado, o gate para a `developer`, depois a `main` e a tag `vX.Y.Z` |
| `/commit [--all] [--repo <dir>]` | Um commit por mudança lógica, num clone ou no `custom/` |
| `/push [--repo custom \| <work>/<clone>]` | Envia o `custom/`, ou reenvia um clone cujo push automático falhou |
| `/validate [folder] [--only <checks>] [--sonar]` | Roda as validações em Docker |
| `/draft-prompt [ideas \| file]` | Monta um pedido funcional a partir de ideias |
| `/prompt [name \| path]` | Executa o pedido escrito num arquivo |
| `/pilot [auto\|manual]` | Mostra ou troca quem faz os testes manuais |
| `/local-env [folder]` | Cria ou completa um `.env` preenchido sem mostrar valores (`custom/env/<name>.env` para `docker/`, `docker/sonar/` e uma ferramenta) |
| `/normalize-projects [<project>... \| --from <url \| folder>]` | Lista o estado dos projetos, ou traz um para o workspace ou o atualiza (abaixo, "Projetos") |

O comando da área de trabalho: `bash scripts/aiwp-cmds.sh --help` (`open`, `run`, `status`, `push`, `close`, `up`, `rollback`, `gate`, `release`, `apply`, `developer`, `checkpoint`, `bring`).

Do próprio Claude Code, os que mais ajudam aqui:

| Comando | Para quê |
| --- | --- |
| `/rewind` (ou Esc duas vezes) | desfazer edições de arquivo e voltar a conversa a um ponto anterior |
| `/clear` | começar outro pedido com o contexto limpo |
| `/effort`, `/model` | trocar o effort e o modelo |
| `/usage` | ver o custo e o uso da sessão |

## Revisão

- Uma rodada por gate, entre as duas fases, feita pelo subagente `reviewer`: contexto limpo, somente leitura.
- Ele classifica cada item da auditoria e cada critério de aceite (pedido, consequência do pedido, sem explicação) e relata só defeito de correção, segurança ou perda de dados, critério não cumprido ou não provado, teste removido sem motivo e proteção mais fraca.
- **BLOCKER** é corrigido no clone, e o gate roda de novo. **RECOMMENDED** nunca devolve a branch.
- Se o Claude discordar de um achado, ele traz as duas posições e você decide.

## Testes que um humano faria à mão

O modo é da sessão e se troca com `/pilot`.

| Modo | Quem testa | Quando usar |
| --- | --- | --- |
| `auto` (padrão) | o Claude, inclusive o visual, com o navegador que a sessão tiver | quase sempre |
| `manual` | você: o Claude entrega uma lista numerada com o que mudou, onde ver, os passos e o que devolver, e espera | quando o teste pede o seu olho, um login real ou um aparelho físico |

Nos dois modos, testes unitários, cobertura, lint e varredura de segredos são do Claude.

## Projetos

- Cada projeto é um repositório git independente em `projects/`, nunca parte do core. A lista está em `custom/projects.md`.
- **Criar:** peça ("cria o projeto X em projects/client-y"). O Claude usa `scripts/init-repo.sh`. A pasta de um projeto novo é decisão sua; se você não disser, o Claude pergunta.
- **Branches:** o checkout em `projects/` fica na `developer`; o trabalho acontece num clone em `tmp/work/`, numa branch que sai dela e volta pelo gate. A `main` só anda quando você pede a release (`/merge --main <repo>`, num clone de release `fix/release-vX-Y-Z`, terminando em `aiwp-cmds.sh release <repo> --tag vX.Y.Z`): um fast-forward para a `developer` e a tag da versão. Terraform só aplica a partir da `main`, com `aiwp-cmds.sh apply`, a seu pedido e com o plano confirmado.
- **Docker local:** `aiwp-cmds.sh up` publica e marca antes as imagens que vai substituir; `aiwp-cmds.sh rollback` volta para elas.
- **Projetos do workspace:** a primeira linha do `README.md` de cada projeto (e de cada pasta de POC) é um marcador com a versão do workspace da última normalização: `<!-- AI-WORKSPACE-PROJECT 0.1.0 -->`. `bash scripts/aiwp-project-state.sh` mostra o estado de cada um. Quando uma mensagem cita um projeto sem o marcador, ou um que uma versão mais nova do workspace pede algo (`migrations/`), o Claude avisa e pergunta se deve rodar `/normalize-projects <project>`. Dizer não nunca bloqueia o pedido; o aviso volta da próxima vez que você citar o projeto. O `aiwp-cmds.sh open` e o gate mostram o mesmo aviso.
- **Trazer um projeto que já existe:** `/normalize-projects --from <url | folder>` o clona em `projects/` (de uma pasta, as branches locais vêm junto e o `origin` aponta para o remoto real dela; mudanças não commitadas lá são listadas, pois um clone não as leva). Um projeto clonado à mão ou uma POC movida para `custom/pocs/` é normalizado do mesmo jeito: `/normalize-projects <project>`.
- **Como é uma normalização:** primeiro, quatro analistas leem um clone novo e o Claude escreve um plano em `custom/migrations/`, uma linha por achado: o que vai para a sua camada custom (conhecimento da empresa e dos ambientes), o que fica no projeto como documentação, o que muda nele (marcador, "How to test", `.env` ignorado, arquivos de instrução de outras ferramentas removidos), e as lacunas e alertas de segurança que ele só relata. Você aprova, edita ou descarta cada linha e escolhe o idioma da documentação. Depois, após você confirmar cada push: `developer` no remoto, tags de checkpoint `ai-workspace-migration/<date>/developer` e `.../main` nas pontas antigas, uma branch `feat/ai-workspace-migration` com o plano em commits e a documentação completa, um teste da branch com você, `/merge` na `developer` e o release da `main` (um pull request quando a `main` é protegida). Ele nunca reescreve código, escreve testes nem corrige uma falha de segurança: as lacunas vão para `AI-WORKSPACE-MIGRATION.md` na raiz do projeto, e os alertas de segurança (arquivo, linha e tipo, nunca o valor) são mostrados a você no fim. Uma POC recebe a mesma análise e aprovação, com as mudanças commitadas no `custom/`.
- **POC ou ferramenta local:** a POC fica em `custom/pocs/` e é trabalhada num clone do `custom/`, com o gate usando o build dela como teste. A ferramenta fica em `tools/`, parte do core, e só muda com o produto. As duas só precisam compilar, passar na varredura de segredos e ter README.
- **Portas:** POCs e stacks de `docker/` a partir de 20000; ferramentas e projetos na porta convencional.
- **Língua:** código em inglês é recomendado nos seus projetos, não obrigatório (`rules/rules.md` "Language").
- **Infraestrutura:** você não dimensiona. Sem um número seu, ela nasce com o menor tamanho que roda a entrega (plano de consumo, um nó, uma região) e pronta para crescer: os limites são variáveis do Terraform, e a documentação do projeto diz qual sinal indica a hora de escalar e quanto custa o degrau seguinte. Se você tem uma exigência real (um volume, um prazo, um teto de orçamento), diga no pedido e ela vira requisito. Antes de criar recurso que gera cobrança, o Claude informa a estimativa mensal.
- **Backlog:** ideias que ainda não viraram pedido vão para `custom/backlog/`, um item por arquivo, a partir de `templates/backlog-item.md`.

## Várias sessões ao mesmo tempo

- **Um clone por trabalho.** Cada sessão trabalha no seu clone em `tmp/work/`; duas sessões não dividem nada além do remoto. Duas não podem abrir a mesma branch.
- **O gate por fast-forward.** Se outra sessão mesclou primeiro, a fase 2 recusa e o gate recomeça com a base nova.
- **`scripts/heavy-run.sh`.** Antes de uma tarefa pesada de CPU ou GPU (gráficos, renderização 3D), lê a temperatura: a 88 °C ou mais, espera chegar a 85 °C. Testes, builds e contêineres rodam direto, sem fila.
- **Recurso compartilhado** (uma porta, um projeto Compose em uso): dois clones do mesmo projeto disputam as mesmas portas. Suba a stack de um de cada vez, e diga à sessão o que já está rodando.

## Validar

| O quê | Comando |
| --- | --- |
| Um clone ou uma pasta | `/validate tmp/work/<work>/<clone>`, ou `bash scripts/validate.sh --path <folder>` |
| Só alguns checks | `bash scripts/validate.sh --path <dir> --only secrets,markdown` |
| SonarQube, quando você quiser | `/validate <dir> --sonar` |

Os checks ficam em `docker/compose.yaml`, com versão e digest fixos. Um check que já passou para o mesmo conteúdo aparece como `CACHED` e não roda de novo; `--no-cache` força.

## Mudar o próprio workspace

- **A sessão nunca muda o core.** `AGENTS.md`, `rules/`, `scripts/`, `docker/`, `docs/` e `tools/` são só leitura: num workspace instalado os arquivos deles são só leitura no disco, o Claude Code recusa a edição e o hook recusa a escrita, um `chmod`, um `chown` e um `git init` ali. A raiz do workspace não é um repositório git: `custom/` e cada projeto são. As suas próprias ferramentas vão para `custom/tools/` (`bash scripts/init-repo.sh --type tool`). Quando uma regra atrapalha, o Claude anota a proposta em `custom/docs/lessons.md` e avisa você.
- **Atualizações:** uma release nova chega ao workspace só pelo `aiwp update`, num terminal sem sessão aberta, que troca só os arquivos do core que mudaram ([O registro e a atualização](#o-registro-e-a-atualização)). Abrir com o `aiwp` só avisa que existe uma.
- **Quem muda o produto:** um pull request para o repositório do produto, mantido a partir da raiz dele.
- **As suas próprias regras:** coloque-as em `custom/rules/`; elas chegam às próximas sessões.
- **Lições:** quando algo dá errado por causa do jeito de trabalhar, o Claude anota uma linha datada em `custom/docs/lessons.md`. Esse arquivo não é carregado nas sessões. Reveja-o de tempos em tempos e decida, linha a linha: vira hook (não admite exceção), vira uma frase numa regra, ou sai.
- **Antes de acrescentar uma regra, pergunte:** o Claude já faz certo sem ela? Dá para garantir com um hook? Se a resposta for sim para uma das duas, a regra não entra.

## Quando algo dá errado

| Sintoma | O que fazer |
| --- | --- |
| O Claude editou o que não devia | `/rewind`, ou Esc duas vezes; num clone, em último caso, `git restore <file>` |
| Um comando, uma skill ou um subagente não aparece | `bash scripts/setup-claude.sh` e reinicie a sessão |
| O hook pergunta ou recusa onde não devia | anote em `custom/docs/lessons.md`; o conjunto está em `scripts/guard-bash.py` (`bash scripts/guard-bash.sh --help`) |
| "NOT pushed" no clone | o hook de pre-push recusou (segredo, `.env`) ou o remoto não respondeu: leia a saída, reescreva a branch no clone se for o caso, e `aiwp-cmds.sh push` |
| "The secret scan did not run" | o Docker não respondeu: suba o Docker e rode `aiwp-cmds.sh push`; o commit fica no clone até lá |
| A publicação no Docker deu errado | `bash scripts/aiwp-cmds.sh rollback <work>/<clone>` (ou `<repo>`) volta para a imagem anterior |
| `heavy-run.sh` saiu com 75 | nada rodou: a máquina não chegou a 85 °C em 30 minutos. A saída traz a última leitura; rode de novo mais tarde |
| O gate recusou a fase 2 | a base andou, ou o clone mudou depois da fase 1: o gate roda de novo |
| Uma regra impede a solução mais simples | o Claude para e mostra as opções. Você pode sobrepor qualquer regra |

## Onde está cada coisa

| O quê | Onde |
| --- | --- |
| O que vale em toda sessão | `AGENTS.md` |
| Regras por assunto | `rules/*.md` |
| Subagentes e comandos | `rules/agents/`, `rules/skills/` |
| Hooks e permissões | `rules/agents/settings.json`, `scripts/guard-bash.sh`, `scripts/guard-subagent-model.sh`, `scripts/aiwp-cmds.sh` (os hooks dos clones e o `Stop`) |
| Scripts | `scripts/README.md` |
| Ferramentas de validação | `docker/README.md` |
| Decisões | `docs/decisions/` |
| Lições | `custom/docs/lessons.md` |
| Pedidos escritos | `custom/prompts/` (na camada custom) |
| Backlog | `custom/backlog/` |
| Empresa: nuvem, identidade visual, projetos e portas | `custom/` (`custom/README.md`) |
| Clones de trabalho | `tmp/work/<work>/` (fora do git; `aiwp-cmds.sh status`) |
