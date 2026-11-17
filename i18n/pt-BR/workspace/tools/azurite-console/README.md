<!-- source: workspace/tools/azurite-console/README.md sha256:05b950e383fec8306721c9fcacb730ba400f5b4ae23c48aec098ec6d4fe9df18 -->

# azurite-console

- [O que é](#o-que-é)
- [Como rodar](#como-rodar)
- [Como funciona](#como-funciona)
- [A página](#a-página)
- [API](#api)
- [Estrutura](#estrutura)
- [Como testar](#como-testar)
- [Dependências](#dependências)

## O que é

Uma página para ver e operar um Azurite local: containers e blobs, filas e mensagens, tabelas e entidades, e o log de acesso do container. Ela mostra o que os serviços gravaram (arquivos, documentos JSON, mensagens das filas) e permite apagar, reenviar, mover e editar sem `az storage` nem `docker logs`.

Um programa Go pequeno sobre o SDK do Azure, com uma página React sem biblioteca de interface, que opera os três serviços do Azurite com segurança: só a conta local, confirmação antes de apagar, ETag e recibo de mensagem respeitados.

## Como rodar

Tudo a partir da raiz do workspace. O `compose.yaml` sobe o Azurite e o console, com o nome de projeto `azurite-console`. A chave da conta vem de `AZURITE_ACCOUNT_KEY`, no ambiente ou em `custom/env/azurite-console.env`, a cópia preenchida do `.env.example` desta pasta na camada custom (ignorada pelo git lá, modo 600), que o compose lê com `--env-file`. Nenhum `.env` é escrito nesta pasta. A chave é sua: o Azurite usa a mesma chave por `AZURITE_ACCOUNTS`. O Compose recusa subir sem ela. `DOCKER_SOCKET_GID` é o grupo dono do socket do Docker, para o painel do log de acesso; sem ele, o container entra no grupo 0, e o painel diz o motivo quando não consegue ler.

Uma vez, crie o arquivo e preencha os dois valores sem mostrá-los (`/local-env tools/azurite-console` numa sessão o cria com valores vazios para você preencher num editor):

```bash
mkdir -p custom/env && chmod 700 custom/env
(umask 077; printf 'AZURITE_ACCOUNT_KEY=%s\nDOCKER_SOCKET_GID=%s\n' "$(openssl rand -base64 48)" "$(stat -c %g /var/run/docker.sock)" > custom/env/azurite-console.env)
docker compose --env-file custom/env/azurite-console.env -f tools/azurite-console/compose.yaml up -d --build --wait
```

Abra `http://127.0.0.1:28091`. A imagem gera a página e compila o programa; depois de mudar o código, rode o mesmo `up -d --build --wait` de novo. Para parar e apagar os dados deste projeto, `docker compose --env-file custom/env/azurite-console.env -f tools/azurite-console/compose.yaml down -v`.

Portas, todas só em `127.0.0.1`:

| Serviço | Host | Container |
| --- | --- | --- |
| `azurite-console` | 28091 | 28091 |
| `azurite`, Blob | 30000 | 10000 |
| `azurite`, Queue | 30001 | 10001 |
| `azurite`, Table | 30002 | 10002 |

O Azurite sobe com `--skipApiVersionCheck`, porque o SDK de Blob do `go.mod` manda uma versão de API mais nova que a conhecida pelo Azurite da imagem, que recusaria toda chamada com `400 InvalidHeaderValue`.

Fora do Compose, para desenvolver o programa, deixe só o Azurite no ar, porque o serviço do console e o `go run` usam a mesma porta 28091. O padrão de `-azurite-port` já é a porta 30000 publicada pelo Compose:

```bash
docker compose --env-file ../../custom/env/azurite-console.env stop azurite-console
npm --prefix web ci
npm --prefix web run build
go run . -env-file ../../custom/env/azurite-console.env
```

Isto roda a partir desta pasta. O `npm` escreve só em `web/node_modules/` e `web/dist/`, as pastas de saída graváveis de um workspace instalado.

Flags:

| Flag | Padrão | O que faz |
| --- | --- | --- |
| `-addr` | `127.0.0.1:28091` | Endereço do servidor; só loopback é aceito, salvo com `-container` |
| `-host` | `127.0.0.1` | Host do Azurite; só loopback, `localhost` ou `azurite` |
| `-azurite-port` | `30000` | Primeira das três portas seguidas do Azurite: Blob, Queue e Table. Para um Azurite nas portas padrão, `-azurite-port 10000` |
| `-web` | `web/dist` | Pasta da página gerada |
| `-env-file` | nenhum | Arquivo `KEY=VALUE` lido para `AZURITE_ACCOUNT_KEY` quando o ambiente não a tem: `../../custom/env/azurite-console.env`. Nenhuma pasta é varrida atrás de um `.env` |
| `-max-upload` | 64 MiB | Maior corpo de requisição, upload incluído |
| `-container` | desligada | Aceita qualquer endereço de escuta; usada só no Compose, que publica a porta apenas em `127.0.0.1` |
| `-healthcheck` | desligada | Chama o `/healthz` da instância em `-addr` e sai com 0 se ela responder; é o healthcheck do container, já que o container não tem shell |

No Compose, a imagem roda com `-container -addr :28091 -host azurite -azurite-port 10000 -web /web`. Fora dele, a chave vem de `AZURITE_ACCOUNT_KEY` no ambiente ou, se faltar, do arquivo de `-env-file`. Sem o build, `/` mostra os comandos de build, e a API funciona do mesmo jeito.

Para mexer na página com recarga automática, `npm --prefix web run dev`: a página abre em `http://127.0.0.1:25174`, e `/api` vai para a porta 28091, seja o serviço do Compose, seja o `go run`.

## Como funciona

```text
navegador --/api/...-->  azurite-console (Go, 127.0.0.1:28091)  --azblob/azqueue/aztables-->  Azurite (no Compose, azurite:10000-10002; fora dele, 127.0.0.1:30000-30002)
                                |--docker logs (só leitura)-->  container azurite
```

- **Só o Azurite local.** O programa monta a connection string com a conta `devstoreaccount1`, o host de `-host` e a chave; nenhuma flag aceita outra connection string. Fora do Compose o servidor escuta só em loopback; no Compose escuta em todas as interfaces do container, e a porta é publicada só em `127.0.0.1`. A chave nunca é exibida.
- **Socket do Docker.** No Compose, o container monta `/var/run/docker.sock` e entra no grupo `DOCKER_SOCKET_GID`, dono do socket, para que o `docker` CLI leia o log do `azurite`. O socket dá acesso à API inteira do Docker; o programa só faz leituras (lista de containers, inspeção e logs).
- **O navegador fala só com o programa.** A assinatura das chamadas ao Storage fica no Go; a página não guarda credencial.
- **Erros.** Toda falha é um problem document, em inglês por padrão e em português do Brasil com `Accept-Language: pt-BR`. Quando o Azurite responde, o `detail` traz o status e o código dele (por exemplo `409 ContainerAlreadyExists`). Os códigos: `console.not_found` (404), `console.conflict` (409), `console.precondition` (412, inclusive o recibo de mensagem vencido, que o Azurite responde como `400 PopReceiptMismatch`), `console.bad_request` (400), `console.unavailable` (503, Azurite fora do ar; a conexão desiste em 3 s) e `console.entity_invalid` (400).
- **Prévia segura.** O conteúdo de um blob é servido como está só para PDF, JSON, texto, CSV e imagens PNG, JPEG, GIF e WebP; qualquer outro tipo (HTML, SVG) vai como texto, com `X-Content-Type-Options: nosniff`, para nunca rodar como página do console.
- **Log de acesso.** O container é achado pelo label `com.docker.compose.service=azurite` e lido com `docker logs --tail N --timestamps`. Cada linha vira horário, quem chamou, serviço, método, recurso decodificado, status e tamanho. Quem chamou é o serviço do Compose dono do IP; o gateway da rede aparece como `host` (um programa na máquina). As chamadas do próprio console aparecem como `azurite-console` no Compose e como `host` com o `go run`. O serviço sai da forma do pedido e dos nomes das filas e tabelas; uma chamada sobre a própria conta, como listar containers ou filas, aparece como `account`. Sem o Docker ou sem o container, o painel diz o motivo e o resto da página continua.
- **Operações.** As ações que mudam algo (criar, excluir, enviar, receber, salvar) ficam numa lista em memória com as últimas 200: horário, ação, alvo, status, duração e código do erro.
- **Logs e parada.** Logs em JSON na saída padrão. Com SIGINT ou SIGTERM, o servidor para de aceitar pedidos e espera os que estão em andamento por até 8 s.

## A página

Uma página com quatro abas. A aba e a seleção ficam no hash da URL (`#/blobs/events/2026/11/16/`, `#/queues/<queue>`, `#/tables/<table>`), então recarregar não perde o lugar. A barra do topo mostra Blob, Queue e Table no ar ou fora, com a latência, e atualiza a cada 5 segundos (dá para desligar).

| Aba | O que mostra e faz |
| --- | --- |
| Visão geral | Contadores de cada serviço (containers, blobs e tamanho; filas e mensagens; tabelas e entidades, com as contagens parando em 10.000 por container e por tabela) e a versão do Azurite; os recursos com link para a aba deles; os erros do log agrupados por serviço, recurso e status, sem os 404 e 409 que fazem parte do trabalho normal; o log de acesso com filtros por serviço, chamador, só erros e texto; as operações desta página |
| Blobs | Containers (criar, excluir, esvaziar); navegação por pastas com trilha, filtro por prefixo e "load more"; detalhe do blob com propriedades, metadados e prévia (JSON formatado, texto até 256 KB, PDF, imagem); download; upload de vários arquivos na pasta atual; exclusão dos selecionados e de uma pasta inteira, com a contagem e o tamanho antes da confirmação |
| Filas | Filas com a contagem aproximada (criar, excluir, limpar); espiar até 32 mensagens sem tirá-las da fila, com JSON formatado, opção de decodificar base64 e destaque para mensagens recebidas 5 vezes ou mais; receber com tempo de invisibilidade e, para cada recebida, excluir, devolver, editar o texto ou mover para outra fila, com a contagem do tempo até voltar; enviar com conferência de JSON, atraso e TTL |
| Tabelas | Tabelas (criar, excluir); consulta com filtro OData, tamanho da página e navegação pela continuação; grade com uma coluna por propriedade; editor da entidade em JSON com as anotações `@odata.type`, salvar em merge ou replace com o ETag lido (o conflito oferece recarregar), inserir, duplicar e excluir; propriedades de texto que contêm JSON aparecem formatadas; exclusão das selecionadas ou de tudo o que o filtro traz, com a contagem antes; exportar a página em JSON |

Excluir ou esvaziar um container, excluir ou limpar uma fila, excluir uma tabela e apagar todas as entidades pedem que se digite o nome.

## API

| Grupo | Rotas |
| --- | --- |
| Geral | `GET /api/overview`, `GET /api/activity?tail=` (1 a 5000), `GET /api/operations` |
| Blob | `GET`/`POST /api/containers`, `DELETE /api/containers/{c}`, `POST /api/containers/{c}/empty`, `GET /api/containers/{c}/list?prefix=&marker=`, `GET /api/containers/{c}/usage?prefix=`, `DELETE /api/containers/{c}/prefix?prefix=`, `GET`/`PUT`/`DELETE /api/containers/{c}/blobs/{path}` (`GET` com `?props`, `?download` ou `?max=`) |
| Queue | `GET`/`POST /api/queues`, `DELETE /api/queues/{q}`, `POST /api/queues/{q}/clear`, `GET /api/queues/{q}/peek?n=`, `POST /api/queues/{q}/receive`, `POST /api/queues/{q}/messages`, `PUT`/`DELETE /api/queues/{q}/messages/{id}`, `POST /api/queues/{q}/messages/{id}/move` |
| Table | `GET`/`POST /api/tables`, `DELETE /api/tables/{t}`, `GET /api/tables/{t}/entities?filter=&top=&next_pk=&next_rk=`, `GET /api/tables/{t}/entity?pk=&rk=`, `POST`/`PUT`/`DELETE /api/tables/{t}/entities`, `POST /api/tables/{t}/delete-by-filter` (com `dry_run` para só contar) |

## Estrutura

```text
main.go               flags, servidor com parada limpa, regra de loopback, prazo de conexão e healthcheck
compose.yaml          Azurite e o console, com as portas só em 127.0.0.1
Dockerfile            imagem do console: página gerada com Node, programa com Go, docker CLI e distroless nonroot
internal/azurite      conta local: chave (ambiente ou .env), connection string, regra do host local, portas e os três clientes
internal/storage      operações de Blob, Queue e Table em tipos próprios; classificação dos erros do Azurite
internal/activity     leitura do log do container pelo docker CLI, parser do log de acesso, chamador pelo IP do Compose, operações em memória
internal/httpjson     respostas JSON, problem documents e catálogo de mensagens, só com a biblioteca padrão
internal/api          rotas /api/, mensagens do console (locales en e pt-BR), página de web/dist
web/                  página React (Vite e TypeScript), CSS próprio, sem biblioteca de interface nem router
```

## Como testar

```bash
go test ./...
npm --prefix web run build
```

Os testes do Go rodam sem rede: a conta local (hosts e portas aceitos e recusados, connection string, busca da chave no arquivo de `-env-file`, nunca num `.env` pelas pastas acima), a classificação dos erros e a limpeza da entidade antes de gravar, o parser do log com linhas reais do container, o chamador pelo IP e as rotas com fakes (status e código do Azurite no problem, idioma do problem, método errado, Azurite fora do ar, ETag e modo, validações, contagem antes de apagar, prévia que nunca serve HTML, visão geral com um serviço fora do ar, página sem build). O build da página confere os tipos com o `tsc`.

Sem Go ou Node no host, rode-os em contêineres, como o seu próprio usuário, para que escrevam só onde você pode (num workspace instalado, `web/node_modules/` e `web/dist/`):

```bash
docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp -v "$PWD":/src:ro -w /src golang:1.27.3-trixie go test ./...
docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp -v "$PWD/web":/app -w /app node:24.21.0-bookworm-slim sh -c 'npm ci && npm run build'
```

Com o Azurite do `compose.yaml` no ar, `AZURITE_CONSOLE_IT=1 AZURITE_CONSOLE_ENV_FILE=../../custom/env/azurite-console.env go test ./internal/storage/` roda também os testes contra as portas 30000 a 30002, que criam recursos `it-console-*` (tabelas `itconsole*`) e os apagam no fim. A chave é a mesma do Compose: no ambiente ou no arquivo de `AZURITE_CONSOLE_ENV_FILE`.

## Dependências

- O SDK do Azure para Go: `azblob`, `azqueue`, `aztables` e `azcore`. O resto do programa usa só a biblioteca padrão.
- A imagem `mcr.microsoft.com/azure-storage/azurite:3.37.0`, fixada por tag e digest no `compose.yaml`.
- O `docker` CLI, só para o log de acesso: no `PATH` com o `go run`; na imagem, copiado da `docker:29.9.1-cli`.
- Na página: React e React DOM, com Vite, `@vitejs/plugin-react` e TypeScript no build.
