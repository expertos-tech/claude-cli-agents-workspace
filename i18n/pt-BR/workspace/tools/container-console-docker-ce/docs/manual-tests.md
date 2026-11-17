<!-- source: workspace/tools/container-console-docker-ce/docs/manual-tests.md sha256:08b2532fac27e443b159023a10afa985bf2d77fc2de90cb763105ed94071992e -->

# Testes manuais do `container-console-docker-ce`

- [Como usar](#como-usar)
- [Cobertura](#cobertura)
- [Preparação](#preparação)
- [Linux: instalação, atalho e unit](#linux-instalação-atalho-e-unit)
- [Reinício da máquina](#reinício-da-máquina)
- [Acesso só da própria máquina](#acesso-só-da-própria-máquina)
- [Ambiente desligado](#ambiente-desligado)
- [Ambiente só leitura](#ambiente-só-leitura)
- [Controle do daemon fora da API](#controle-do-daemon-fora-da-api)
- [Contêineres](#contêineres)
- [Imagens, volumes, redes e Compose](#imagens-volumes-redes-e-compose)
- [Kubernetes](#kubernetes)
- [YAML inválido](#yaml-inválido)
- [Cancelar a remoção](#cancelar-a-remoção)
- [Erro recebido e estado real](#erro-recebido-e-estado-real)
- [Mudança em até 2 s](#mudança-em-até-2-s)
- [Layout e identidade](#layout-e-identidade)
- [Tema](#tema)
- [Idioma](#idioma)

Guia de verificação, feito por você, em navegador real e nesta máquina. A ferramenta não tem teste automatizado: é verificada pela compilação (`make check`) e por estes passos. Qualquer item pode falhar: anote o que viu e traga de volta.

## Como usar

- Cada bloco tem passos numerados e o resultado esperado. Um item passa só se o resultado for o descrito.
- Faça nesta ordem: preparação, Linux, ambiente desligado, ambiente só leitura e os demais. As telas dependem do Docker ligado, exceto o bloco de ambiente desligado.
- Os recursos de teste levam o prefixo `cc-` para você limpar no fim. Não use o Grafana (`observability`) para testar: ele recebe a telemetria real.
- Os rótulos da tela citados abaixo são os do português do Brasil, que aparecem quando o idioma do navegador começa com `pt`. Com outro idioma, a tela fica em inglês.

## Cobertura

Os requisitos da tela e da instalação:

| Requisito | Onde conferir |
| --- | --- |
| Estado e dados do daemon, só leitura | [Ambiente só leitura](#ambiente-só-leitura) |
| O console não controla o daemon | [Controle do daemon fora da API](#controle-do-daemon-fora-da-api) |
| Contêineres, logs ao vivo e terminal | [Contêineres](#contêineres) |
| Imagens, volumes, redes e Compose | [Imagens, volumes, redes e Compose](#imagens-volumes-redes-e-compose) |
| Kubernetes, logs e terminal no pod | [Kubernetes](#kubernetes) |
| YAML inválido não muda nada | [YAML inválido](#yaml-inválido) |
| Cancelar a remoção não envia nada | [Cancelar a remoção](#cancelar-a-remoção) |
| A tela funciona com o Docker desligado | [Ambiente desligado](#ambiente-desligado) |
| Serviço e Grafana depois do login | [Linux](#linux-instalação-atalho-e-unit) (serviço no login) e [reinício da máquina](#reinício-da-máquina) |
| Acesso só da própria máquina | [Acesso só da própria máquina](#acesso-só-da-própria-máquina) |
| Erro recebido e estado real | [Erro recebido e estado real](#erro-recebido-e-estado-real) |
| Mudança em até 2 s | [Mudança em até 2 s](#mudança-em-até-2-s) |
| Atalho na área de trabalho | [Linux](#linux-instalação-atalho-e-unit) |
| Identidade visual (`rules/frontend.md`) | [Layout e identidade](#layout-e-identidade) |
| Tema que segue o sistema, com a escolha da pessoa | [Tema](#tema) |
| Inglês por padrão, português do Brasil para navegadores `pt` | [Idioma](#idioma) |

## Preparação

1. Em `tools/container-console-docker-ce`, com o Node 24 no `PATH`: `make install`. Isso também instala a unit e o atalho, que os testes do Linux conferem.
2. Sem a unit, para testar só a tela: `make build`, rode `.data/bin/container-console-docker-ce` e abra <http://127.0.0.1:27850/>. Com a unit instalada, basta abrir o endereço.
3. Com o Docker ligado, crie os recursos de teste:
   - `docker run -d --name cc-test busybox sleep 3600`
   - Um arquivo `~/cc-test/compose.yaml`:

     ```yaml
     services:
       busybox:
         image: busybox
         command: ["sleep", "3600"]
     ```

4. O painel "Ações" fica abaixo do conteúdo. É nele que aparecem o progresso, o sucesso e os erros de toda ação.

## Linux: instalação, atalho e unit

Valem para o atalho, a unit e o início do serviço no login. Rode na pasta `tools/container-console-docker-ce`, na sessão gráfica do seu usuário.

| # | Passos | Resultado esperado |
| --- | --- | --- |
| 1 | `make install` | Imprime `installed container-console-docker-ce.service and <caminho do atalho>`. `Container Console` aparece no menu de aplicativos, com o ícone do Claude CLI Agents Workspace sem distorção |
| 2 | `curl -s http://127.0.0.1:27850/healthz` | Responde `{"status":"ok"}` |
| 3 | Clique no atalho | O navegador padrão abre <http://127.0.0.1:27850/> |
| 4 | Rode `make install` de novo | Termina sem erro, com um só atalho no menu |
| 5 | `systemctl --user stop container-console-docker-ce.service` e depois clique no atalho | O serviço sobe de novo, e a tela abre |
| 6 | `systemctl --user kill --signal=SIGKILL container-console-docker-ce.service` | O systemd sobe o serviço de novo: `/healthz` responde em cerca de 2 s |
| 7 | Encerre a sessão e entre de novo | `/healthz` responde sem você abrir terminal |
| 8 | `bash linux/uninstall-console.sh` | Somem o atalho, a unit e o binário. O Docker, os contêineres e `~/.local/state/container-console-docker-ce` continuam |

Reinstale com `make install` antes dos blocos seguintes.

## Reinício da máquina

| # | Passos | Resultado esperado |
| --- | --- | --- |
| 1 | Reinicie a máquina e entre na sessão gráfica | `/healthz` responde em até 1 minuto, sem você abrir terminal |
| 2 | Abra <http://127.0.0.1:27850/> | Badge "Ligado" na barra superior |
| 3 | Abra <http://localhost:3000> | Grafana saudável na porta 3000, sem você ter subido nada |

## Acesso só da própria máquina

| # | Passos | Resultado esperado |
| --- | --- | --- |
| 1 | `hostname -I` (o primeiro IP da interface de rede ativa), depois `curl --max-time 3 http://<ip>:27850/healthz` | Conexão recusada (curl sai com erro 7). Sem rede ativa, marque como **não verificado**, nunca como aprovado |
| 2 | `curl -s -o /dev/null -w '%{http_code}\n' -H 'Host: attacker.example' http://127.0.0.1:27850/healthz` | `403` |
| 3 | `curl -s -o /dev/null -w '%{http_code}\n' -X POST -H 'Content-Type: application/json' -H 'Origin: http://attacker.example' -H 'Sec-Fetch-Site: cross-site' -d '{"confirm":false}' http://127.0.0.1:27850/api/volumes/cc-x/remove` | `403` (sem a proteção, seria `422`, porque falta a confirmação) |
| 4 | `curl -s -o /dev/null -w '%{http_code}\n' -H 'Connection: Upgrade' -H 'Upgrade: websocket' -H 'Sec-WebSocket-Version: 13' -H "Sec-WebSocket-Key: $(openssl rand -base64 16)" http://127.0.0.1:27850/ws/live/docker` | `403`, porque falta o `Origin` |
| 5 | Rode `CONSOLE_LISTEN=0.0.0.0:27850 .data/bin/container-console-docker-ce` | Sai com erro `CONSOLE_LISTEN: host must be 127.0.0.1` |

## Ambiente desligado

Pare o Docker com `sudo systemctl stop docker.socket docker.service`. Só `docker.service` não basta: o `docker.socket` reativa o daemon na próxima leitura do console.

| # | Passos | Resultado esperado |
| --- | --- | --- |
| 1 | Abra `#/overview` | A página abre. Badge "Desligado" na barra superior e no cartão. Frase explica o que fica indisponível. Contagens de Docker dizem "Indisponível" |
| 2 | Abra `#/environment` | A frase diz que o Docker está desligado, e `sudo systemctl start docker` aparece como texto. Nenhum botão de ligar ou desligar. Cartão "O que fica indisponível com o Docker desligado" com Docker e Compose |
| 3 | Abra `#/containers`, `#/images`, `#/volumes`, `#/networks` | Aviso explica o motivo, com link para o ambiente. Campos e botões de criar e baixar aparecem desabilitados, não escondidos |
| 4 | Abra `#/compose` | Projetos conhecidos continuam na lista, com estado "Desconhecido". Subir, Parar e Remover desabilitados. Adicionar arquivo continua habilitado |
| 5 | Com um cluster acessível, abra `#/kubernetes` | A lista continua funcionando: o Kubernetes não depende do estado do Docker neste console |
| 6 | Rode `sudo systemctl start docker` no terminal | Sem recarregar, o badge passa a "Ligado" e as listas voltam |

## Ambiente só leitura

| # | Passos | Resultado esperado |
| --- | --- | --- |
| 1 | Com o Docker ligado, abra `#/environment` | Badge "Ligado", com versão, CPUs, memória, driver de armazenamento, sistema e arquitetura iguais aos de `docker info` |
| 2 | Procure ações na tela | Não há botão, campo nem diálogo: a tela só mostra |
| 3 | Abra `#/overview` | Cartão "Docker" com estado, versão, CPUs e memória, e o link "Ver o ambiente" |
| 4 | Rode o serviço com `CONSOLE_DOCKER_HOST` apontando para um socket sem permissão de leitura para você | Badge "Desconhecido", com o erro recebido na tela |

## Controle do daemon fora da API

| # | Passos | Resultado esperado |
| --- | --- | --- |
| 1 | `curl -s -o /dev/null -w '%{http_code}\n' -X POST -H 'Content-Type: application/json' -d '{}' http://127.0.0.1:27850/api/environment/start`; repita com `stop`, `resources`, `kubernetes/start` e `kubernetes/stop` | `404` em todas |
| 2 | Abra `#/kubernetes` | Não há botão de ligar nem de desligar o Kubernetes |

## Contêineres

| # | Passos | Resultado esperado |
| --- | --- | --- |
| 1 | Abra `#/containers` | `cc-test` aparece, com badge de estado (ícone e texto). Contêineres de pods não aparecem |
| 2 | Na linha, clique em "Parar" | Job no painel. O badge só muda quando o estado real muda: "Parado" |
| 3 | Clique em "Iniciar", depois em "Reiniciar" | Estado acompanha cada ação, voltando a "Rodando" |
| 4 | Clique no nome do contêiner | Abre os detalhes, com id completo, imagem, comando, redes e montagens. "Ver todos os detalhes em JSON" abre o inspect |
| 5 | Olhe "Uso de recursos" | CPU, memória, rede, disco e processos mudam a cada 2 s. Ao sair da tela, as consultas a `/stats` param (aba Network do navegador) |
| 6 | Aba "Logs", com `docker run -d --name cc-log busybox sh -c 'while true; do date; sleep 1; done'` | Linhas novas aparecem ao vivo, sem degraus na margem. Tab sai da área de logs |
| 7 | Aba "Terminal" de `cc-test`; rode `echo hello` e `ls` | O comando roda dentro do contêiner. Redimensionar a janela ajusta o terminal (`stty size` muda) |
| 8 | No terminal, cole um texto com mais de 64 KiB | A conexão não cai e o texto inteiro chega ao shell |
| 9 | No terminal, pressione Shift+Esc e depois Tab | O foco sai do terminal e segue para o próximo controle |
| 10 | Rode `exit` | Badge mostra que o processo terminou com o código recebido. "Conectar de novo" abre outro shell |
| 11 | Em "Remover", leia o diálogo e confirme | O diálogo cita `docker rm --force`. O contêiner some da lista |
| 12 | Rode `docker tag busybox example.local/a/very/long/image/name/for/testing:1` e `docker run -d --name cc-long example.local/a/very/long/image/name/for/testing:1 sleep 600`; em `#/containers`, pare o ponteiro sobre a coluna Imagem | O nome termina em `...` em uma linha só, e o navegador mostra o nome inteiro ao lado do ponteiro. Nos detalhes do contêiner o nome aparece inteiro |

## Imagens, volumes, redes e Compose

| # | Passos | Resultado esperado |
| --- | --- | --- |
| 1 | Em `#/images`, baixe `alpine:3.20` | Linhas de progresso no painel Ações. A imagem aparece na lista ao terminar |
| 2 | Digite `-rf` na referência e clique em "Baixar" | Erro de formato abaixo do campo. Nada é enviado |
| 3 | Remova `alpine:3.20` | Diálogo, depois a imagem some |
| 4 | Remova a imagem de um contêiner existente | O erro do Docker aparece no painel, e a imagem continua na lista |
| 5 | Em `#/volumes`, crie `cc-volume`, abra os detalhes e remova | Aparece, o JSON do inspect abre e some depois de confirmar |
| 6 | Em `#/networks`, crie `cc-network`, abra os detalhes e remova | Igual ao volume |
| 7 | Remova a rede `bridge` | O erro do Docker aparece, e a rede continua na lista |
| 8 | Em `#/compose`, clique em "Escolher arquivo" e escolha `~/cc-test/compose.yaml` | O diálogo do `zenity` abre, filtrando YAML. O projeto aparece na lista |
| 9 | Clique no botão de novo e cancele no diálogo | Nada muda, sem erro |
| 10 | Digite `/tmp/x.txt` no campo de caminho | Erro de formato abaixo do campo |
| 11 | Digite `/etc/compose.yaml` | Recusa do serviço, com o motivo, no painel Ações |
| 12 | Digite o caminho de `~/cc-test/compose.yaml` e adicione | Funciona igual ao diálogo |
| 13 | Clique em "Subir", depois em "Parar" | Estado vai a "Rodando" e depois a "Parado" |
| 14 | Crie um volume no projeto, clique em "Remover" e confirme com a opção desmarcada | Projeto sai da lista, e o volume continua (`docker volume ls`) |
| 15 | Adicione de novo, suba, remova com "Remover também os volumes do projeto, o que apaga os dados deles" marcado | O volume some. Reabrir o diálogo mostra a opção desmarcada |

## Kubernetes

Precisa de um cluster acessível no contexto atual do kubeconfig ou em `CONSOLE_KUBE_CONTEXT`. Prepare com `kubectl create deployment cc-web --image=nginx:alpine` e `kubectl expose deployment cc-web --port=80`.

| # | Passos | Resultado esperado |
| --- | --- | --- |
| 1 | Abra as abas Namespaces, Pods, Deployments e Services | Tabelas reais, com o recurso de teste. O filtro de namespace funciona |
| 2 | Abra os detalhes de cada tipo | Dados da lista e JSON completo |
| 3 | Em Deployments, clique em "Escalar", informe 3 | O diálogo abre com o valor atual. Depois, "3 de 3 prontas" |
| 4 | Informe 1001 | Erro abaixo do campo. Nada é enviado |
| 5 | Abra um pod, aba Logs | Linhas ao vivo |
| 6 | Aba Terminal; rode `hostname` | Mostra o nome do pod |
| 7 | Remova o pod | Diálogo avisa que o deployment cria outro. Um novo pod aparece |
| 8 | Remova service, deployment e um namespace de teste | Cada um some depois de confirmar |
| 9 | Aponte o contexto para um cluster fora do ar (`CONSOLE_KUBE_CONTEXT`, ou `kubectl config use-context`) e abra a tela | Aviso "Nenhum cluster Kubernetes responde", com o erro recebido. Aba "Aplicar YAML" com campo e botão desabilitados. A tela segue tentando |
| 10 | Volte ao contexto do cluster no ar | A lista volta sem recarregar |

Se o `kubectl` disser que o contexto não existe, a causa é a descrita em [operação](operations.md#falhas-comuns), e não um defeito da tela.

## YAML inválido

| # | Passos | Resultado esperado |
| --- | --- | --- |
| 1 | Em "Aplicar YAML", clique em "Aplicar" com o campo vazio | "O YAML está vazio." abaixo do campo |
| 2 | Cole um Deployment com um campo inexistente em `spec` | O job falha, com o erro do `kubectl` no painel. O texto continua no campo. Nada muda no cluster (`kubectl get`) |
| 3 | Cole um recurso válido e outro inválido no mesmo arquivo | Falha igual, e o válido também não é criado |
| 4 | Cole um YAML válido | O recurso aparece na lista |

## Cancelar a remoção

Para contêiner, imagem, volume, rede, projeto Compose, namespace, pod, deployment e service:

| # | Passos | Resultado esperado |
| --- | --- | --- |
| 1 | Clique em "Remover" | O diálogo abre com o foco em "Cancelar" |
| 2 | Tente tirar o foco do diálogo com Tab | O foco não sai dele |
| 3 | Clique em "Cancelar" | O diálogo fecha, o foco volta ao botão e o recurso continua. Na aba Network, nenhum POST |
| 4 | Repita e pressione Esc | Mesmo resultado |

## Erro recebido e estado real

| # | Passos | Resultado esperado |
| --- | --- | --- |
| 1 | Em outro terminal, `docker rm -f cc-test` e, antes da lista atualizar, clique em "Parar" na tela; ou pare o contêiner duas vezes | O erro recebido aparece sem tradução em "Erro recebido", com o código de saída. A linha mostra o estado real |
| 2 | Remova uma imagem em uso | Mesmo comportamento, com a linha ainda na lista |
| 3 | Clique em "Dispensar" no erro | A entrada some, o foco fica no painel. Recarregar não traz o erro de volta |
| 4 | Provoque um erro e recarregue sem dispensar | O erro continua no painel |
| 5 | Pare o serviço com a tela aberta | Faixa "A conexão ao vivo com o serviço caiu" aparece em até 2 s. Um clique em qualquer ação mostra "Não foi possível falar com o serviço" |
| 6 | Suba o serviço de novo | A faixa some em até 2 s, e os dados voltam sem recarregar |

## Mudança em até 2 s

| # | Passos | Resultado esperado |
| --- | --- | --- |
| 1 | Crie 30 contêineres: `for i in $(seq 30); do docker run -d --name cc-$i busybox sleep 3600; done` | Os 30 aparecem na lista |
| 2 | `docker stop -t 0 cc-7` pelo terminal, com a tela aberta | A linha muda para "Parado" em até 2 s |
| 3 | Clique em "Iniciar" na linha de `cc-7` | A linha muda para "Rodando" em até 2 s depois do fim do job |
| 4 | Com 30 pods, repita apagando um pod pelo terminal | A lista de pods muda em até 2 s |

Limpeza: `docker rm -f $(docker ps -aq --filter name=cc-)`, e apague o namespace, os recursos Kubernetes e `~/cc-test`.

## Layout e identidade

Em 320, 390, 768, 1024 e 1280 px, nas telas de contêineres, ambiente, Compose e pods (`rules/frontend.md`):

| # | Conferir | Resultado esperado |
| --- | --- | --- |
| 1 | Rolagem horizontal da página | Nunca aparece. Uma tabela larga rola só dentro do cartão dela |
| 2 | Tabelas abaixo de cerca de 1024 px | Colunas secundárias passam para dentro da primeira célula, com rótulo. Nome, estado e ações sempre visíveis |
| 3 | Tabelas em 320 px | Cada linha vira um bloco: nome, dados empilhados, estado e botões, sem cortar texto |
| 4 | Menu abaixo de 1024 px | Botão de menu abre a gaveta `<dialog>` sobre `ink`. Esc fecha, e o foco volta ao botão |
| 5 | Barra superior e menu | Fundo `ink`, o ícone do projeto e, ao lado, `Claude CLI Agents Workspace` com `Container Console` embaixo, sem distorção. O favicon é o mesmo ícone. O ícone é decorativo (texto alternativo vazio): o nome ao lado é o que o leitor de tela lê |
| 6 | Títulos e texto | Títulos em Poppins 700, sem ponto final azul e sem texto acima do título. O resto em Roboto. Cantos de 5 px em botões, campos e selos, e 20 px em cartões |
| 7 | Foco com Tab em todas as telas | Anel `#0076a3` no claro, `#24bee6` no escuro e sobre `ink`. O primeiro Tab mostra "Ir para o conteúdo" |
| 8 | Status | Sempre ícone e texto |
| 9 | Ids e caminhos longos | Monoespaçados, quebrando só depois de `.`, `/` ou `-`. Um trecho sem esses sinais rola na própria caixa |
| 10 | Toggle "Animar mudanças nos dados", no menu | Desligado, as barras de CPU e memória dos detalhes de um contêiner mudam sem transição, e a escolha persiste. O mesmo com a redução de animações do sistema |
| 11 | Console do navegador em todas as telas | Nenhuma violação de CSP, nenhum erro de fonte ou imagem |
| 12 | Celular ou simulador com toque | Campos em 16 px, sem zoom ao focar. Botões com pelo menos 40 px |

## Tema

A aparência do GNOME muda em Configurações > Aparência. Comece sem escolha salva: no console do navegador, rode `localStorage.removeItem("container-console-docker-ce.theme")` e recarregue.

| # | Passos | Resultado esperado |
| --- | --- | --- |
| 1 | Sem escolha salva, com o sistema em Claro | Fundo `#f8f9fc`, cartões brancos. O campo `Tema`, no menu lateral, mostra "Seguir o sistema" |
| 2 | Com a tela aberta, mude o sistema para Escuro | Sem recarregar, o fundo passa a `#303841` e os cartões a `#343f4b`. Barra superior e menu seguem em `ink` |
| 3 | Volte o sistema para Claro | A tela volta ao claro sem recarregar |
| 4 | Com o sistema em Claro, escolha "Escuro" | A tela escurece na hora |
| 5 | Recarregue a página | Continua escura, sem piscar em claro antes |
| 6 | Mude o sistema para Escuro e depois para Claro | A tela fica escura nos dois casos: a escolha vence o sistema |
| 7 | Com o sistema em Escuro, escolha "Claro" e recarregue | Continua clara, sem piscar em escuro antes |
| 8 | Mude o sistema para Claro e de novo para Escuro | A tela fica clara nos dois casos |
| 9 | Escolha "Seguir o sistema", recarregue e mude o sistema | A escolha persiste, e a tela volta a acompanhar o sistema |
| 10 | Só com teclado: Tab até `Tema`, setas e Enter para trocar | O anel de foco aparece no campo, e o tema muda |
| 11 | Abaixo de 1024 px, troque o tema na gaveta do menu e amplie a janela para 1024 px ou mais | O tema muda com a gaveta aberta, e o campo do menu lateral mostra a mesma escolha |
| 12 | No escuro, percorra contêineres, ambiente, Compose e pods | Texto legível em cartões, tabelas, avisos e blocos de código. Status sempre com ícone e texto, e o ícone legível dentro do selo |
| 13 | No escuro, botões, links e abas | Botão primário `#0076a3` com borda `#24bee6`. Links e aba atual em `#24bee6`. Botão desabilitado distinguível. Anel de foco visível em todas as superfícies |
| 14 | No escuro, abra um diálogo de confirmação e passe o mouse por linhas de tabela | O diálogo destaca-se do fundo escurecido. A linha muda de fundo, com texto legível |
| 15 | No escuro, veja as barras de CPU e memória nos detalhes de um contêiner e force um erro em um campo | Barra visível sobre a trilha. Ícone do erro legível sobre o cartão |
| 16 | Nos dois temas, abra logs e terminal de um contêiner | Fundo escuro e texto claro, iguais nos dois temas. Texto selecionado continua legível |
| 17 | Com o terminal aberto, troque o tema | O terminal não muda de cor, e a conexão continua aberta |
| 18 | Console e aba de rede do navegador, nos dois temas | Nenhuma violação de CSP. `/theme-init.js` responde 200 |

## Idioma

| # | Passos | Resultado esperado |
| --- | --- | --- |
| 1 | Com o idioma do navegador em inglês (ou qualquer idioma que não comece com `pt`), abra o console | Todo texto está em inglês: menu, títulos, botões, avisos e as descrições dos jobs no painel Actions |
| 2 | Mude o idioma do navegador para português (`pt` ou `pt-BR`) e recarregue | Todo texto está em português do Brasil, por exemplo "Ligado" na barra superior e "Seguir o sistema" no campo `Tema`. Números e datas usam o formato brasileiro |
| 3 | Nos dois idiomas, provoque um erro de CLI (por exemplo, remova a rede `bridge`) | A frase do código de erro é traduzida, e o erro recebido aparece como veio, sem tradução |

Fora destas listas e não verificados: leitores de tela, outros navegadores além do que você usar e cores forçadas.
