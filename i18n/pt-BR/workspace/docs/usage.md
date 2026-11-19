<!-- source: workspace/docs/usage.md sha256:6438c5c43f9cb69a88d0447d3247a710fc93940bc2a8ff82baede21fdea88148 -->

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
| Opcional, mas a única forma de medir as sessões: subir a stack de observabilidade (um Grafana local) | `/run-tools`, numa sessão, marcando Observability; depois o README dela liga a telemetria do Claude Code |

Daí em diante a `.claude/` se mantém atualizada sozinha: um hook de início de sessão roda o `setup-claude.sh`.

Para remover um workspace, devolva antes a permissão de escrita, já que o core é só leitura: `chmod -R u+w <folder> && rm -rf <folder>`. Faça push do `custom/` e dos seus projetos antes: eles vão junto.

## Abrir uma sessão

```bash
cd <workspace> && aiwp
```

O `aiwp` confere se há release nova (no máximo uma vez por dia, limite de 5 s; offline ele segue em frente) e, quando há, imprime "A new workspace version X was detected (this workspace: Y). Run `aiwp update` to update; opening this workspace on Y." Depois roda o `setup-claude.sh` e inicia o `claude` na versão atual, com os argumentos que você passar depois de `--` (`aiwp -- --resume`). Abrir nunca atualiza. Depois de uma atualização interrompida, ele se recusa a abrir até que `aiwp repair` (ou `aiwp update`) restaure o workspace. O `claude` sozinho também abre o workspace: quando existe uma release nova, o início da sessão avisa, e o Claude diz para você fechar a sessão e rodar `aiwp update` num terminal.

**Nunca dentro de uma sessão.** De uma sessão do Claude Code (a ferramenta Bash dela, um hook) o `aiwp` recusa `update`, `rollback`, `repair`, `forget`, a abertura e um `new` sobre uma pasta registrada, e o `guard-bash` também os nega: eles mudam as regras da sessão aberta ou iniciam o `claude` dentro dela. `aiwp list`, `check`, `version` e `--help` funcionam em qualquer lugar. Um comando desconhecido é erro de uso; os argumentos para o `claude` vão depois de `--`.

- **Sempre na raiz do workspace**, mesmo para trabalhar num projeto: é ali que o `AGENTS.md`, as regras e os hooks valem.
- **Uma sessão por pedido.** Terminado o assunto, use `/clear` ou abra outra sessão. Uma sessão longa fica cara: cada passo lê o contexto inteiro de novo.
- **Effort:** `medium` serve para o trabalho de escopo claro. Suba para `high` com `/effort high` quando a mudança mexe em hook, permissão, merge ou segurança, ou para depurar uma falha difícil. Para um único passo difícil, escreva `ultrathink` no prompt.
- **Nome da sessão:** `/request <file>` dá à sessão o nome do projeto, numerado (`billing-api-1`, `billing-api-2`...), pela linha `**Project:**` do pedido: o número é o seguinte ao maior entre as sessões abertas daquele projeto. Sem `/request`, o Claude Code escolhe um título sozinho; `/rename <name>` troca.
- **Idioma:** o Claude responde no seu idioma preferido de comunicação, o que o `aiwp new` perguntou quando criou o workspace, mesmo quando roda um arquivo de pedido escrito em inglês. É a configuração `language` do Claude Code em `.claude/settings.local.json` do workspace (por exemplo `"language": "portuguese"`); o `aiwp update` nunca muda esse arquivo. Sem nenhuma definida ali nem no seu `~/.claude/settings.json`, o Claude responde no idioma em que você escreve. Para definir ou mudar depois, edite essa chave.

## O registro e a atualização

A pasta de dados guarda o `workspaces.json`, com todos os workspaces instalados (caminho, versão, criado, atualizado). O `aiwp new` registra um workspace, e a primeira execução do `aiwp` num que não está registrado o adiciona.

| Comando | Faz |
| --- | --- |
| `aiwp list` | Cada workspace registrado com a versão e o estado: em dia, atualização disponível (X), core alterado, pasta ausente, fixado em X, parado no meio |
| `aiwp forget <folder>` | Remove a entrada (para uma pasta que sumiu, ou que você não atualiza mais); nunca toca na pasta |
| `aiwp update` | Lista os workspaces registrados (número, versão, estado, caminho) e pergunta `[1] Update all` (o padrão), `[2] Choose which` (números) ou `[3] Cancel` |
| `aiwp update <folder>` | Atualiza só aquele workspace, sem perguntar |
| `aiwp update --all` | Atualiza todos os workspaces registrados, sem perguntar |

A atualização acontece só por comando, num terminal, sem sessão aberta. O `aiwp update` leva a pasta de dados à release mais nova uma vez, depois atualiza cada workspace escolhido: confere-o contra o manifesto, faz backup do que substitui em `.aiwp/backup/<version>/`, escreve um journal, troca os arquivos por rename e mostra o changelog. Um workspace cujo core mudou ou cuja pasta sumiu é pulado e relatado, e os outros seguem; uma tabela-resumo encerra a execução.

- **Workspaces fixados** (depois de `aiwp rollback`) ficam como estão com `--all` e com Update all; escolher um por número ou por pasta o atualiza e tira a fixação.
- **Sem terminal:** `--all` ou uma pasta é obrigatório; senão é erro de uso (saída 2).
- **Um `claude` em execução:** antes de trocar um workspace onde roda um processo `claude` (a pasta atual dele dentro do workspace), ele diz o pid e pergunta. Com `--all` ele pula esse workspace, a menos que você acrescente `--force`.
- **Saída 1** quando um workspace foi pulado por core alterado, por um `claude` em execução ou por um erro.

## Fazer um pedido

**Um pedido simples:** escreva em palavras.

```text
corrija o link quebrado no README do my-project
```

**Um pedido funcional (uma funcionalidade, um sistema):** o formulário é o `templates/request.md`. Os títulos e os rótulos em negrito dele ficam em inglês; o conteúdo vai no seu idioma. Há duas formas de preenchê-lo.

| Forma | Como |
| --- | --- |
| A partir de ideias soltas | `/draft-request quero um relatório mensal de...`; o Claude pergunta só o que bloqueia, marca o resto como "assumed decision" e salva em `custom/requests/` |
| Você mesmo | copie `templates/request.md` para `tmp/request.md` e preencha |

Depois, `/request <file>` lê `custom/requests/<file>`; `/request` sozinho lê `tmp/request.md`.

- Os pedidos do `/draft-request` ficam em `custom/requests/`, dentro da camada custom, um repositório git próprio: o histórico dos pedidos é versionado ali.
- Um pedido passa por três pastas: pendente na raiz de `custom/requests/` (estado `idea` ou `ready`); `custom/requests/qa/<project>/` quando o `/merge` o levou para a `developer`, com um bloco "Execution" do que foi feito; `custom/requests/done/<project>/` quando o `/merge --main` o lançou, depois de validá-lo contra o código. Uma ideia é um pedido no estado `idea`; não existe backlog.
- O `/draft-request` faz commit e push do pedido que criou, a cada versão; o `/merge` faz commit e push das mudanças para qa e done, e uma onda faz o do ponto de retomada ([Ondas](#ondas-checkpoint-merge-e-retomada)).
- O `aiwp new` prepara o `custom/`: clona o repositório cuja URL você der (um vazio ganha um esqueleto), ou inicia um local. Se a pasta sumir depois, a sessão avisa no início, e `bash scripts/setup-claude.sh --custom-repo <url>` num terminal a clona.

O pedido escrito tem o tamanho do que você pediu. O `/draft-request` escolhe um de três tamanhos antes de escrever, e diz qual:

| Tamanho | Quando | O que sai | Teto |
| --- | --- | --- | --- |
| Ajuste | muda um comportamento de algo que existe ("adicionar um overlay de confirmação") | poucas linhas: o quê, onde, pronto quando, effort | cerca de 120 palavras |
| Funcionalidade | uma capacidade nova num sistema que existe | objetivo, regras, critérios de aceite, fora de escopo, etapas e effort | cerca de 400 palavras, no máximo 8 regras |
| Sistema | um sistema novo, arquitetura, infra, integração externa, dados pessoais | o formulário completo | sem teto |

- Uma regra que você não declarou não é escrita, a menos que sem ela duas coisas diferentes pudessem ser construídas.
- Grande ou pequeno demais? Responda "menor" ou "maior".
- Um pedido do tamanho ajuste pode ir direto para a sessão, sem arquivo.

**Effort por etapa.** Todo pedido escrito traz o effort que cada etapa pede: uma linha no tamanho ajuste, e a tabela "Steps and effort" nos outros. Você define a sessão com `/effort <level>` antes de cada etapa; o Claude diz no início de cada uma qual nível ela pede e passa esse nível aos subagentes da etapa.

| Effort | Quando |
| --- | --- |
| `low` | uma mudança mecânica: um texto, um rótulo, uma renomeação |
| `medium` | um escopo claro; o padrão |
| `high` | onde a verificação importa: segurança, dados pessoais, dinheiro, permissões, migração, uma etapa destrutiva, um bug em código que existe |

O que esperar:

- O Claude pergunta as **lacunas funcionais**, todas de uma vez, antes de começar. Ele não pede a sua aprovação para decisões técnicas.
- Uma pergunta ou um pedido somente de leitura é respondido direto, sem branch e sem teste.
- No fim, um resumo curto: o que mudou, o que foi verificado e como, o que falta. Um check que falha é relatado como falha, com a saída dele.

## Onde o trabalho acontece

- **Pergunta ou leitura:** o Claude responde; nada é aberto.
- **Mudança num projeto ou numa POC:** o Claude abre um clone em `tmp/work/<date>-<subject>/<clone>/` (`<clone>`: o caminho do repo relativo a `projects/`, cada `/` escrito como `--`) (`bash scripts/aiwp-cmds.sh open`), diz o caminho e trabalha só ali. No clone o Claude trabalha sem perguntar: o `guard-bash` aprova uma linha quando todo comando dela roda naquele clone, todo caminho que ela cita fica nele e nada age sobre um sistema remoto (um push, uma publicação, um deploy, uma CLI de nuvem, `ssh`); o que ele não consegue dizer segue o modo de permissão do Claude Code. Cada commit vai sozinho para o remoto, depois de uma varredura de segredos dos commits que saem; um commit com segredo ou um `.env` fica no clone.
- **Levar para a base:** `/merge [<work>/<clone>]`; sem argumento, o clone desta sessão. O `/merge` integra a `developer` no clone e escreve a versão do `CHANGELOG.md` do projeto (`## [X.Y.Z] - Unreleased`; as regras do bump estão em `rules/docs.md`) antes do gate. O gate traz a `developer` atualizada, roda a suíte completa e o `validate.sh` completo, varre todo commit que entra atrás de segredos, escreve a auditoria do que sai da base (arquivos apagados ou renomeados para fora, testes removidos ou desativados, SQL destrutivo, infra, dependências, os avisos) e pede uma revisão contra o pedido. Só uma hard rule para o gate: um segredo ou um arquivo de env, um comando de teste que falha, um check que altera arquivos rastreados, as regras de escopo da normalização e do hotfix. Todo outro check do `validate.sh` que falhe (lint, vulnerabilidades, infra, cobertura...) é um aviso: ele vai para a auditoria em "Warnings", o `/merge` o lista no resumo e você decide. O `/merge` é digitado só por você: o gate recusa a fase 2 caso contrário. Você só é perguntado sobre o que o pedido não explica. Depois a `developer` avança por fast-forward exatamente para o commit que passou, e o clone pode ser fechado (`aiwp-cmds.sh close`).
- **A cópia da tarefa:** ao fim de uma tarefa o Claude a publica no Docker local com `aiwp-cmds.sh up <work>/<clone>`, como uma cópia no próprio grupo compose `agent_<MMDD>-<slug>` (`--<clone>` acrescentado quando outro clone do trabalho já o usa), com toda porta movida para uma livre em 61000-65535. Ela nunca toca a stack final. As redes dela são internas, com um gateway isolado (Docker Engine 28 ou posterior), então um contêiner sem porta publicada não alcança nem o host nem o exterior; o `up` recusa o que o isolamento dele exige (rede do host, um socket do Docker ou um bind fora do clone, redes ou volumes externos, Docker anterior ao 28). Um serviço com uma chave fora da lista segura (privilégios, capabilities, dispositivos, sysctls...) inicia com um aviso, e o `exec` nele segue o modo de permissão em vez de ser aprovado pelo hook. O `aiwp-cmds.sh down <work>/<clone>` a para; o `close` e o gate a destroem. O Claude trabalha livremente dentro desse grupo, sem perguntar (`down -v`, `logs`, `exec` num contêiner isolado), volumes incluídos; iniciá-la ou reconstruí-la passa pelo `up` de novo.
- **`projects/` fica sempre na `developer`.** Ninguém edita ali; só o gate avança a base.

## Ondas: checkpoint, merge e retomada

Onda é cada etapa de um plano em etapas (a tabela "Steps and effort" do pedido). Um pedido de uma etapa só, ou sem etapas, é uma onda, que fecha quando ele termina. Pergunta ou leitura não abre onda.

- **Uma parte vai para a base só quando você digita `/merge`**, quando você decidir. Base que publica em produção: o gate pergunta antes de mesclar. Uma branch de migração também espera a sua ordem.
- **Ao fechar a onda**, o Claude:
  1. faz o checkpoint: um commit no clone, que vai sozinho para o remoto (`aiwp-cmds.sh status` mostra `not-pushed=0`);
  2. acrescenta ao pedido que estava rodando, em `custom/requests/`, onde ele parou (o trabalho, o clone, a branch e o sha), as decisões tomadas, as pendências e as próximas etapas com o effort delas; o pedido continua pendente;
  3. termina a resposta com o quadro de fechamento: o que foi feito e verificado, os endereços da cópia, um item a testar por critério de aceite, o que falta, o pedido a retomar e as duas saídas: `/merge <work>/<clone>` para aprovar, `aiwp-cmds.sh close <work> --discard` para descartar o trabalho. Depois do quadro a sessão para; a onda seguinte começa numa sessão nova, com `/request <file>`.
- A sessão não termina a resposta com commit fora do remoto: um hook a faz tentar de novo ou dizer por que não deu.

Regra completa: `rules/git.md`, seções "Gate" e "Waves".

## O que o Claude pergunta a você

O resto segue o modo de permissão do Claude Code: o auto mode julga o que é destrutivo.

| Situação | O que acontece |
| --- | --- |
| Um gate com algo que o pedido não explica, destruição fora da máquina, ou uma base que publica em produção | uma pergunta, numa rodada, antes de mesclar |
| Uma linha que mistura um comando aprovado com comandos no clone | recusada com "Run it alone": o Claude roda os outros primeiro e o perguntado sozinho, para que a pergunta mostre só ele |
| Apagar um banco de dados: `docker volume rm`, `docker compose down -v`, `DROP`/`TRUNCATE`, apagar uma pasta `.data/` | o Claude diz o que vai embora, e o hook pede a sua confirmação |
| `aiwp-cmds.sh release` (a `main` avança, e a tag `vX.Y.Z` é enviada), rodado pelo `/merge --main <project>` | confirmação, e só a seu pedido |
| `aiwp-cmds.sh hotfix`, `hotfix-tag` e `hotfix-down` (a correção para a `main`, a tag de patch dela, a `main` mesclada na `developer`), rodados pelo `/merge --hotfix` | confirmação, depois do seu OK à correção; a pergunta "publicar em produção com a correção?" vem antes do push de uma `main` que faz deploy sozinha, e depois dele nos outros casos |
| `aiwp-cmds.sh apply --apply` (Terraform na nuvem) | confirmação do plano mostrado, e só a seu pedido |
| Apagar, mover ou esvaziar os dados do Grafana (`tools/observability/.data`), onde quer que rode | confirmação, até num clone |
| `aiwp-cmds.sh deploy` (atualiza a stack final de um projeto, rodado pelo `/docker-deploy`), `checkpoint`, `developer --create` e `gate --untested` | o hook imprime um aviso e o modo de permissão decide |
| `aiwp-cmds.sh close --discard` (apagar trabalho não mesclado) | confirmação |
| Uma escrita git em `projects/` ou no core, Terraform fora do `apply`, `git push --no-verify` | recusada pelo hook, com o caminho certo |
| Um subagente no Fable | o hook pede a sua confirmação |
| Apagar um projeto, POC ou ferramenta inteiro | o Claude mostra o comando; **você** o roda |

## Comandos

| Comando | Faz |
| --- | --- |
| `/merge [<work>/<clone>]` | Leva o trabalho de um clone (sem argumento: o desta sessão) para a `developer`, pelo gate, escrevendo o `CHANGELOG.md` e movendo o pedido para `custom/requests/qa/<project>/` com o que foi feito |
| `/merge --main <project> [instructions]` | A release do projeto: todo repo dele, cada um com a própria versão e tag, depois a versão do projeto no repo raiz dele; valida todo pedido de `qa/<project>/` contra o código (a revisão final: as três perguntas sobre tudo desde a última tag, ampliadas conforme preciso), pergunta por achado (corrigir agora ou um pedido) e avisa de qualquer conflito que uma instrução cause antes de agir |
| `/merge --hotfix <project> <description>` | Um erro em produção: um clone a partir da `main`, só a correção, o gate contra a `main` e uma revisão da correção, o seu OK, depois a `main`, a versão de patch `vX.Y.(Z+1)` e a tag dela quando você mandar publicar, e logo em seguida a `main` mesclada na `developer` (um conflito passa por uma branch de resolução e pelo gate). Enquanto a `developer` não tiver a `main`, o repo fica bloqueado: o `/merge` na `developer` dele e a release dele são recusados |
| `/commit [--all] [--repo <dir>]` | Um commit por mudança lógica, num clone ou no `custom/` |
| `/push [--repo custom \| <work>/<clone>]` | Envia o `custom/`, ou reenvia um clone cujo push automático falhou |
| `/docker-deploy [developer\|main] [<repo>]` | Atualiza a stack Docker local final de um repo a partir da `developer` ou da `main`, marcando as imagens substituídas para rollback e sem apagar nenhum volume; só a seu pedido |
| `/validate [folder] [--only <checks>] [--sonar]` | Roda as validações em Docker |
| `/draft-request [ideas \| file]` | Monta um pedido funcional a partir de ideias |
| `/request [name \| path]` | Executa o pedido escrito num arquivo |
| `/rules [exclude <name> \| include <name> \| add <subject> \| replace <rule> \| lessons]` | Mostra e muda as regras, skills e agentes que uma sessão carrega (abaixo, "Mudar o próprio workspace") |
| `/pilot [auto\|manual]` | Mostra ou troca quem faz os testes manuais |
| `/local-env [folder]` | Cria ou completa um `.env` preenchido sem mostrar valores (`custom/env/<name>.env` para `docker/`, `docker/sonar/` e uma ferramenta) |
| `/run-tools [--down [tool...]]` | Inicia as ferramentas locais que você marcar (abaixo, "Ferramentas locais"); `--down` para |
| `/normalize-projects [<project>... \| --from <url \| folder>]` | Lista o estado dos projetos, ou traz um para o workspace ou o atualiza (abaixo, "Projetos") |

O comando da área de trabalho: `bash scripts/aiwp-cmds.sh --help` (`open`, `run`, `status`, `push`, `close`, `up`, `down`, `deploy`, `rollback`, `gate`, `release`, `hotfix`, `hotfix-tag`, `hotfix-down`, `apply`, `developer`, `checkpoint`, `bring`).

Os comandos do próprio Claude Code que mais ajudam aqui:

| Comando | Para |
| --- | --- |
| `/rewind` (ou Esc duas vezes) | desfazer edições de arquivos e levar a conversa de volta a um ponto anterior |
| `/clear` | começar outro pedido com o contexto limpo |
| `/effort`, `/model` | mudar o effort e o modelo |
| `/usage` | ver o custo e o uso da sessão |

## Revisão

- Uma rodada por gate, entre as duas fases, feita pelo subagente `reviewer`: contexto limpo, somente leitura. Na `developer` ele vê só a diferença que entra; na `main` (release, hotfix) tudo desde a última tag, ampliado para chamadores, dependentes e docs.
- Um `reviewer` por merge, effort `medium` na `developer` e `high` na `main`; um intervalo grande demais para um contexto é dividido em partes, em paralelo. O brief leva o que você autorizou, e isso nunca é um achado.
- Três perguntas: o que foi pedido contra o que foi feito (cada regra e critério, provado ou não), o que foi além do pedido (uma consequência ou sem explicação) e o que existia e se perdeu (um comportamento, um teste ou uma proteção removido ou enfraquecido sem pedido). Ele relata só defeitos.
- Um **BLOCKER** é só uma hard rule, um defeito de correção, uma mudança fora do escopo do pedido, um risco que um erro alcança ou uma prova que o pedido exige agora; é corrigido no clone, e o gate roda de novo. Todo o resto é um **WARNING**: nunca devolve a branch, o `/merge` o lista e você decide.
- Se o Claude discordar de um achado, ele traz as duas posições e você decide.

## Testes que um humano faria à mão

O modo pertence à sessão e muda com `/pilot`.

| Modo | Quem testa | Quando usar |
| --- | --- | --- |
| `auto` (padrão) | o Claude, verificações visuais incluídas, com o navegador que a sessão tem | quase sempre |
| `manual` | você: o Claude dá uma lista numerada com o que mudou, onde ver, os passos e o que reportar de volta, e espera | quando o teste precisa do seu olho, de um login real ou de um dispositivo físico |

Nos dois modos, testes unitários, cobertura, lint e a varredura de segredos são do Claude.

## Projetos

- Cada projeto é um repositório git independente em `projects/`, nunca parte do core. A lista está em `custom/projects.md`.
- **Criar:** peça ("crie o projeto X em projects/client-y"). O Claude usa o `scripts/init-repo.sh`. A pasta de um projeto novo é decisão sua; se você não a disser, o Claude pergunta.
- **Branches:** o checkout em `projects/` fica na `developer`; o trabalho acontece num clone em `tmp/work/`, numa branch que sai dele e volta pelo gate. A `main` só avança quando você pede a release (`/merge --main <project>`, num clone de release `fix/release-vX-Y-Z`, terminando em `aiwp-cmds.sh release <repo> --tag vX.Y.Z`): um fast-forward para a `developer` e a tag de versão. Um erro em produção é corrigido a partir da `main` (`/merge --hotfix`), como versão de patch, e a `main` é então mesclada na `developer`. O Terraform só aplica a partir da `main`, com `aiwp-cmds.sh apply`, a seu pedido e com o plano confirmado.
- **Docker local:** `aiwp-cmds.sh up <work>/<clone>` publica a cópia de uma tarefa no próprio grupo `agent_` e nunca sobre a stack final; `aiwp-cmds.sh up <repo>` é recusado. A stack final só muda por ordem sua, com `/docker-deploy` (`aiwp-cmds.sh deploy`), que antes marca as imagens que substitui; `aiwp-cmds.sh rollback <repo>` volta para elas. Uma cópia não tem tag de rollback: rode `up` de novo.
- **Projetos do workspace:** a primeira linha do `README.md` de cada projeto (e de cada pasta de POC) é um marcador com a versão do workspace com a qual ele foi normalizado pela última vez: `<!-- AI-WORKSPACE-PROJECT 0.1.0 -->`. O `bash scripts/aiwp-project-state.sh` mostra o estado de cada um. Quando uma mensagem cita um projeto sem o marcador, ou um de que uma versão mais nova do workspace pede algo (`migrations/`), o Claude diz isso e pergunta se roda `/normalize-projects <project>`. Dizer não nunca bloqueia o pedido; o aviso volta da próxima vez que você citar o projeto. O `aiwp-cmds.sh open` e o gate mostram o mesmo aviso.
- **Trazer um projeto existente:** `/normalize-projects --from <url | folder>` o clona em `projects/` (de uma pasta, as branches locais dela vêm junto e o `origin` aponta para o remoto real dela; mudanças não commitadas ali são listadas, já que um clone não as leva). Um projeto clonado à mão ou uma POC movida para `custom/pocs/` é normalizado do mesmo jeito: `/normalize-projects <project>`.
- **Como funciona uma normalização:** primeiro, quatro analistas leem um clone novo e o Claude escreve um plano em `custom/migrations/`, uma linha por achado: o que vai para a sua camada custom (conhecimento da empresa e do ambiente), o que fica no projeto como documentação, o que muda nele (marcador, "How to test", `.env` ignorado, arquivos de instrução de outras ferramentas removidos), e as lacunas e alertas de segurança que ele só relata. Você aprova, edita ou descarta cada linha e escolhe o idioma da documentação. Depois, a cada push que você confirmar: a `developer` no remoto, tags de checkpoint `ai-workspace-migration/<date>/developer` e `.../main` nas cabeças antigas, uma branch `feat/ai-workspace-migration` com o plano em commits e a documentação completa, um teste da branch com você, `/merge` na `developer` e a release da `main` (um pull request quando a `main` é protegida). Ele nunca reescreve código, escreve testes nem corrige uma falha de segurança: as lacunas vão para o `AI-WORKSPACE-MIGRATION.md` na raiz do projeto, e os alertas de segurança (arquivo, linha e tipo, nunca o valor) são mostrados a você no fim. Uma POC recebe a mesma análise e aprovação, com as mudanças commitadas no `custom/`.
- **POC ou ferramenta local:** uma POC mora em `custom/pocs/` e é trabalhada num clone do `custom/`, com o gate usando o build dela como teste. Uma ferramenta mora em `tools/`, parte do core, e só muda com o produto. As duas só precisam compilar, passar na varredura de segredos e ter um README.
- **Portas:** POCs e stacks de `docker/` a partir de 20000; ferramentas e projetos na porta convencional deles.
- **Idioma:** código em inglês é recomendado nos seus projetos, não obrigatório (`rules/rules.md` "Language").
- **Infraestrutura:** você não a dimensiona. Sem um número seu, ela começa no menor tamanho que roda a entrega (plano de consumo, um nó, uma região) e pronta para crescer: os limites são variáveis do Terraform, e a documentação do projeto diz qual sinal indica que é hora de escalar e quanto custa o próximo passo. Se você tem um requisito real (um volume, um prazo, um teto de orçamento), diga no pedido e ele vira requisito. Antes de criar um recurso que é cobrado, o Claude dá a estimativa mensal.
- **Ideias:** uma ideia ainda não pronta é um pedido em `custom/requests/` no estado `idea`, no tamanho ajuste do `templates/request.md` (What, Where, Done when, Effort).

## Ferramentas locais

O `/run-tools` mostra caixas de seleção com as ferramentas desta máquina, agrupadas em duas perguntas (observabilidade e consoles; simuladores), cada uma com a URL e o estado, e inicia as que você marcar. Desmarcar uma ferramenta que está no ar não para nada; o `/run-tools --down` para.

- As ferramentas de contêiner (observabilidade, os simuladores de login e de Safe Browsing, o console do Azurite) rodam num projeto compose só, `claude-cli-agents-tools`: o console de contêineres as mostra como um grupo (`tools/compose.yaml`).
- Só o console de contêineres desta máquina aparece: docker-ce no Linux e no WSL com Docker Engine, Colima no macOS. É um serviço da máquina: o `/run-tools` o instala (`make install`) ou o inicia.
- A configuração de uma ferramenta mora em `custom/`: `custom/env/<tool>.env` (`/local-env tools/<tool>`) e `custom/config/<tool>/`. Sem ela a ferramenta é listada como "configuration missing" e não inicia; uma porta ocupada é mostrada do mesmo jeito.
- Cada início marca as imagens que substitui como `<name>:rollback-latest`.
- Uma ferramenta instalada antes do grupo, ainda rodando no próprio projeto compose, passa para o grupo no primeiro início. Um volume nomeado (o do Azurite) é copiado antes para o nome do grupo; o antigo fica até você confirmar a exclusão. Quando a stack de um projeto ainda usa uma das redes da ferramenta, o `/run-tools` diz qual, não muda nada, e você para essa stack primeiro.

## Várias sessões ao mesmo tempo

- **Um clone por trabalho.** Cada sessão trabalha no próprio clone em `tmp/work/`; duas sessões não compartilham nada além do remoto. Duas não podem abrir a mesma branch.
- **O gate por fast-forward.** Se outra sessão mesclou primeiro, a fase 2 recusa e o gate recomeça com a base nova.
- **`scripts/heavy-run.sh`.** Antes de uma tarefa pesada de CPU ou GPU (gráficos, renderização 3D), ele lê a temperatura: a 88 °C ou mais, espera chegar a 85 °C. Testes, builds e contêineres rodam direto, sem fila.
- **Um recurso compartilhado** (uma porta, um projeto Compose em uso): dois clones do mesmo projeto disputam as mesmas portas. Inicie a stack de um por vez e diga à sessão o que já está rodando.

## Validar

| O quê | Comando |
| --- | --- |
| Um clone ou uma pasta | `/validate tmp/work/<work>/<clone>`, ou `bash scripts/validate.sh --path <folder>` |
| Só alguns checks | `bash scripts/validate.sh --path <dir> --only secrets,markdown` |
| SonarQube, quando você quiser | `/validate <dir> --sonar` |

Os checks moram em `docker/compose.yaml`, com versão e digest fixos. Um check que já passou para o mesmo conteúdo aparece como `CACHED` e não roda de novo; `--no-cache` o força.

## Mudar o próprio workspace

- **Uma sessão nunca muda o core.** `AGENTS.md`, `rules/`, `scripts/`, `docker/`, `docs/` e `tools/` são só leitura: num workspace instalado os arquivos deles são só leitura no disco, o Claude Code recusa a edição e o hook recusa a escrita, um `chmod`, um `chown` e um `git init` ali. A raiz do workspace não é um repositório git: `custom/` e cada projeto são. As suas próprias ferramentas vão para `custom/tools/` (`bash scripts/init-repo.sh --type tool`). Quando uma regra atrapalha, o Claude escreve a proposta em `custom/docs/lessons.md` e avisa você.
- **Atualizações:** uma release nova chega ao workspace só pelo `aiwp update`, num terminal sem sessão aberta, que troca só os arquivos do core que mudaram ([O registro e a atualização](#o-registro-e-a-atualização)). Abrir com `aiwp` só diz que existe uma.
- **Quem muda o produto:** um pull request para o repositório do produto, mantido a partir da raiz dele.
- **Suas próprias regras:** o `/rules` mostra as regras que uma sessão carrega, com a origem de cada uma, e desliga regras, skills e agentes do core, substitui uma regra do core ou adiciona as suas, em `custom/rules-config.json` e `custom/my-rules/`; o core obrigatório sempre carrega. Você também pode editar esses arquivos à mão. Uma mudança vale para as próximas sessões, nunca para a aberta. Um workspace que ainda tem `custom/rules/`: renomeie com `git -C custom mv rules my-rules`.
- **Lições:** quando algo dá errado por causa do jeito como o trabalho foi feito, o Claude escreve uma linha datada em `custom/docs/lessons.md`. Esse arquivo não é carregado nas sessões. Revise-o de vez em quando e decida, linha a linha: ela vira um hook (sem exceção permitida), uma frase numa regra, ou some.
- **Antes de acrescentar uma regra, pergunte:** o Claude já faz certo sem ela? Um hook consegue garantir? Se a resposta a qualquer uma for sim, a regra não entra.

## Quando algo dá errado

| Sintoma | O que fazer |
| --- | --- |
| O Claude editou o que não devia | `/rewind`, ou Esc duas vezes; num clone, `git restore <file>` como último recurso |
| Um comando, uma skill ou um subagente não aparece | `bash scripts/setup-claude.sh` e reinicie a sessão |
| O hook pergunta ou recusa onde não devia | escreva em `custom/docs/lessons.md`; o conjunto está em `scripts/guard-bash.py` (`bash scripts/guard-bash.sh --help`) |
| "NOT pushed" no clone | o hook de pre-push recusou (um segredo, um `.env`) ou o remoto não respondeu: leia a saída, reescreva a branch no clone se preciso e `aiwp-cmds.sh push` |
| "The secret scan did not run" | o Docker não respondeu: inicie o Docker e rode `aiwp-cmds.sh push`; o commit fica no clone até lá |
| A publicação no Docker deu errado | `bash scripts/aiwp-cmds.sh rollback <repo>` volta para a imagem anterior da stack final; a cópia de uma tarefa não tem rollback: rode `up <work>/<clone>` de novo |
| O `heavy-run.sh` saiu com 75 | nada rodou: a máquina não chegou a 85 °C em 30 minutos. A saída traz a última leitura; rode de novo mais tarde |
| O gate recusou a fase 2 | a base andou, ou o clone mudou depois da fase 1: o gate roda de novo |
| Uma regra bloqueia a solução mais simples | o Claude para e mostra as opções. Você pode passar por cima de qualquer regra |

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
| Pedidos escritos | `custom/requests/` (na camada custom) |
| Pedidos (pendentes, `qa/<project>/`, `done/<project>/`) | `custom/requests/` |
| Empresa: nuvem, identidade visual, projetos e portas | `custom/` (`custom/README.md`) |
| Clones de trabalho | `tmp/work/<work>/` (fora do git; `aiwp-cmds.sh status`) |
