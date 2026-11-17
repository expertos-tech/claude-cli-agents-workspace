<!-- source: workspace/tools/container-console-docker-ce/docs/api.md sha256:1b973a49e35ebec110e74d073d205c9d07585072ed781f5cffc2446767464394 -->

# Contrato da API do `container-console-docker-ce`

- [Convenções](#convenções)
- [Erros](#erros)
- [Jobs](#jobs)
- [Rotas REST](#rotas-rest)
- [WebSocket: regras comuns](#websocket-regras-comuns)
- [Tópicos ao vivo](#tópicos-ao-vivo)
- [Logs](#logs)
- [Terminal](#terminal)
- [O que o front-end precisa respeitar](#o-que-o-front-end-precisa-respeitar)

Referência para quem escreve a tela. Fonte das rotas: `internal/httpapi/`.

## Convenções

- Base: `http://127.0.0.1:27850` ou `http://localhost:27850`. Use URLs relativas e monte o WebSocket a partir de `location.host`.
- Sem login. O acesso é protegido por `Host` e `Origin`, descritos abaixo.
- Todo corpo e toda resposta são JSON com campos em `camelCase`. Horários dos jobs: RFC 3339 em UTC.
- GET nunca muda estado. Toda mutação vira [job](#jobs) e não segura o HTTP. As duas exceções estão indicadas nas rotas de Compose.
- Listas não têm rota REST: chegam pelos [tópicos](#tópicos-ao-vivo). REST é só para detalhes e comandos.

Regras aplicadas a todas as rotas, nesta ordem:

| Regra | Recusa |
| --- | --- |
| `Host` exatamente igual a `127.0.0.1:<porta>` ou `localhost:<porta>` | 403 `forbidden` |
| `http.CrossOriginProtection`: `Sec-Fetch-Site` ou `Origin` de outro site em método que muda estado | 403 `forbidden` |
| POST com `Content-Type: application/json`, **mesmo sem corpo** | 403 `forbidden` |
| Corpo de até 1 MiB | 413 `body_too_large` |
| Campo desconhecido, JSON malformado ou dados depois do JSON | 422 `invalid_body` |

Toda recusa de segurança é igual, de propósito: o motivo só vai para o log do serviço. Corpo vazio equivale a `{}`, então `confirm` ausente é `false`.

Formatos aceitos:

| Valor | Formato |
| --- | --- |
| Id ou nome de contêiner, volume e rede | `^[a-zA-Z0-9][a-zA-Z0-9_.-]*$`, até 255 caracteres |
| Referência de imagem | `^[a-zA-Z0-9][a-zA-Z0-9._:/@-]*$`, até 512 caracteres |
| Projeto Compose | `^[a-z0-9][a-z0-9_-]*$` |
| Caminho de Compose | Absoluto, sem `..`, `.yaml` ou `.yml`, arquivo regular dentro de `$HOME`, conferido depois de resolver links |
| Namespace e service | DNS-1123 label |
| Pod e deployment | DNS-1123 subdomain |

Cabeçalhos de toda resposta: `Content-Security-Policy`, `X-Content-Type-Options: nosniff`, `Referrer-Policy: no-referrer` e `Cross-Origin-Resource-Policy: same-origin`.

## Erros

Forma única no REST:

```json
{ "error": { "code": "environment_not_on", "message": "the docker daemon is not on", "params": { "state": "off" } } }
```

- `code`: estável, é a chave do dicionário de tradução.
- `message`: técnica, em inglês. Quando o erro vem de uma CLI, é o stderr recebido, que a tela mostra sem tradução.
- `params`: valores nomeados para a frase traduzida, quando houver.
- `exitCode`: código de saída da CLI, quando houver.

| Status | Significado | Códigos |
| --- | --- | --- |
| 403 | Recusa de segurança, ver [Convenções](#convenções) | `forbidden` |
| 404 | Alvo inexistente | `container_not_found`, `volume_not_found`, `network_not_found`, `kubernetes_resource_not_found`, `kubernetes_kind_unknown`, `compose_project_not_found`, `job_not_found`, `route_not_found` |
| 409 | O estado atual recusa a ação | `environment_not_on` (com `params.state`), `kubernetes_unavailable` (com o erro do `kubectl` em `message`), `file_picker_busy`, `compose_files_unknown` |
| 413 | Corpo acima do limite | `body_too_large` |
| 422 | Entrada recusada; nada foi executado | `invalid_body`, `confirmation_required`, `invalid_docker_name`, `invalid_image_reference`, `invalid_compose_project`, `compose_path_invalid`, `compose_file_invalid`, `invalid_kubernetes_name`, `replicas_required`, `replicas_out_of_range` (`params.max`), `yaml_empty` |
| 502 | A CLI falhou numa consulta | `command_failed`, `command_timeout`, `binary_not_found`, `action_failed` |

Rota com método errado recebe o 405 padrão do Go, em texto.

Códigos que só existem no WebSocket. Chegam num quadro `error` depois do upgrade (ver [WebSocket: regras comuns](#websocket-regras-comuns)), com a mesma forma de `code`, `message` e `params`, e a classe do erro entre parênteses:

| Código | Quando | Fechamento |
| --- | --- | --- |
| `topic_not_found` (não encontrado) | `/ws/live/{topic}` com tópico que não existe | 1000 |
| `too_many_terminals` (conflito, `params.max`) | Um novo terminal depois do limite de terminais simultâneos | 1013 |
| `invalid_terminal_size` (entrada inválida) | `cols` ou `rows` na URL, ou num quadro `resize`, fora de 1 a 1000 | 1000 na URL; 1008 no quadro |
| `invalid_terminal_frame` (entrada inválida) | Quadro de texto que não é `resize` | 1008 |

Os erros de REST (`environment_not_on`, `container_not_found` e os demais da tabela acima) também podem chegar em quadro `error`, por exemplo ao abrir logs ou terminal com o Docker desligado.

## Jobs

Fluxo de toda mutação:

1. A tela envia o POST.
2. O serviço valida formato, confirmação e estado. Falha aqui devolve erro e nada é executado.
3. O serviço devolve `202` com `{ "job": <Job> }` no estado `running`.
4. O tópico `jobs` traz cada mudança: novas linhas de saída e o fim.
5. Ao terminar, `environment`, `docker` e `kubernetes` são atualizados de imediato. A linha na tela só muda com esse snapshot, nunca de forma otimista.

```json
{
  "id": "J4PZ3Q8W2M6XK1VBN7TRY5HGCD",
  "kind": "container.stop",
  "target": "b2958c286bef",
  "status": "failed",
  "output": ["..."],
  "error": { "code": "command_failed", "message": "Error response from daemon: ...", "exitCode": 1 },
  "startedAt": "2026-11-16T22:15:00Z",
  "finishedAt": "2026-11-16T22:15:02Z"
}
```

- `status`: `running`, `succeeded` ou `failed`. `error` e `finishedAt` só aparecem quando se aplicam.
- `output`: últimas 200 linhas. O serviço guarda em memória os jobs em execução e os 50 últimos terminados, e perde tudo ao reiniciar.
- `error.code`: `command_failed`, `command_timeout`, `binary_not_found` ou o código de domínio. `error.message` é o erro recebido, a ser exibido como veio.

| `kind` | `target` |
| --- | --- |
| `container.start`, `container.stop`, `container.restart`, `container.remove` | Id ou nome |
| `image.pull`, `image.remove` | Referência |
| `volume.create`, `volume.remove`, `network.create`, `network.remove` | Id ou nome |
| `compose.up`, `compose.stop`, `compose.remove` | Nome do projeto |
| `kubernetes.remove`, `kubernetes.scale` | `<kind>/<namespace>/<nome>`, ou `namespaces/<nome>` |
| `kubernetes.apply` | Vazio |
| `docker.cleanup` | `volumes` quando inclui volumes, vazio sem eles |

## Rotas REST

`job` na coluna de resposta significa `202 { "job": <Job> }`. Toda remoção exige `"confirm": true`, conferido no servidor. Sem isso: 422 `confirmation_required`.

### Serviço

| Rota | Corpo | Resposta |
| --- | --- | --- |
| `GET /healthz` | Nenhum | `200 { "status": "ok" }` |
| `GET /api/jobs/{id}` | Nenhum | `200 { "job": <Job> }` |

### Ambiente

Sem rota REST: o ambiente é só leitura e chega pelo tópico [`environment`](#environment). Controlar o docker-ce exige root, e o console nunca liga nem desliga o daemon.

### Contêineres

| Rota | Corpo | Resposta |
| --- | --- | --- |
| `GET /api/containers/{id}` | Nenhum | `200` com o objeto de `docker inspect` |
| `GET /api/containers/{id}/stats` | Nenhum | `200 { "cpuPercent", "memoryUsage", "memoryPercent", "networkIO", "blockIO", "pids" }`, textos como a CLI imprime |
| `POST /api/containers/{id}/start` | `{}` | job |
| `POST /api/containers/{id}/stop` | `{}` | job |
| `POST /api/containers/{id}/restart` | `{}` | job |
| `POST /api/containers/{id}/remove` | `{ "confirm": true }` | job. Usa `docker rm --force`, e o diálogo precisa dizer isso |

`stats` leva cerca de 1 s. Consulte a cada 2 s só enquanto os detalhes estiverem abertos.

### Imagens

| Rota | Corpo | Resposta |
| --- | --- | --- |
| `POST /api/images/pull` | `{ "reference": "alpine:3.20" }` | job, com as linhas de progresso em `output` |
| `POST /api/images/remove` | `{ "reference": "<campo reference da lista>", "confirm": true }` | job. Sem `--force`: imagem em uso devolve o erro no job |

A referência vai no corpo porque contém `/`.

### Volumes e redes

| Rota | Corpo | Resposta |
| --- | --- | --- |
| `POST /api/volumes` | `{ "name": "data" }` | job |
| `GET /api/volumes/{id}` | Nenhum | `200` com o objeto de `docker volume inspect` |
| `POST /api/volumes/{id}/remove` | `{ "confirm": true }` | job |
| `POST /api/networks` | `{ "name": "my-network" }` | job |
| `GET /api/networks/{id}` | Nenhum | `200` com o objeto de `docker network inspect` |
| `POST /api/networks/{id}/remove` | `{ "confirm": true }` | job |

As remoções não usam `--force`: recurso em uso devolve o erro no job.

### Limpeza

| Rota | Corpo | Resposta |
| --- | --- | --- |
| `GET /api/cleanup` | Nenhum | `200` com `{ containers, images, networks, volumes, buildCache }`: cada lista com `{ id, name, detail? }`, e `buildCache` como `docker system df` imprime |
| `POST /api/cleanup` | `{ "confirm": true, "volumes": false }` | job `docker.cleanup` |

Ativo é o contêiner `running`, `paused`, `restarting` ou `removing`; contêiner de pod do Kubernetes conta como ativo. O resumo lista os contêineres que não estão ativos e as imagens, redes (menos `bridge`, `host` e `none`) e volumes que nenhum contêiner ativo usa. O job roda, em ordem: `docker container prune --force --filter label!=io.kubernetes.pod.namespace`, `docker image prune --all --force`, `docker network prune --force`, `docker volume prune --all --force` (só com `"volumes": true`) e `docker builder prune --all --force`, cada passo com o prazo de `CONSOLE_TIMEOUT_DOCKER_PULL`. Cada passo age sobre o estado do daemon na hora em que roda.

### Compose

| Rota | Corpo | Resposta |
| --- | --- | --- |
| `POST /api/compose/file-dialog` | `{}` | `200 { "path": "/home/.../compose.yaml", "canceled": false }`. Cancelado: `path` vazio e `canceled: true`. Não é job |
| `POST /api/compose/projects` | `{ "path": "<caminho absoluto>" }` | `201 { "project": <Project> }`. Não é job e funciona com o Docker desligado |
| `POST /api/compose/projects/{name}/up` | `{}` | job |
| `POST /api/compose/projects/{name}/stop` | `{}` | job |
| `POST /api/compose/projects/{name}/remove` | `{ "confirm": true, "removeVolumes": false }` | job. Roda `down`, com `--volumes` só se marcado, e tira da lista |

- `file-dialog` abre `zenity --file-selection` e só devolve o caminho. Uma sessão sem display devolve 502 `command_failed`, com o erro recebido, e não cancelamento. Para adicionar o projeto, envie-o a `POST /api/compose/projects`. Fica aberto por até 5 min; um segundo pedido recebe 409 `file_picker_busy`. A tela também oferece um campo de caminho, para quando o diálogo não abrir.
- O nome do projeto vem do próprio Compose. Arquivo recusado por ele: 422 `compose_file_invalid`, com o erro em `message`.
- As ações usam os arquivos que o serviço conhece, e o navegador nunca envia caminho nelas. Projeto com arquivo fora de `$HOME` recebe 422 `compose_path_invalid`.

### Kubernetes

`{kind}` é `pods`, `deployments` ou `services`. Sem cluster acessível, toda rota desta seção recebe 409 `kubernetes_unavailable`.

| Rota | Corpo | Resposta |
| --- | --- | --- |
| `GET /api/kubernetes/namespaces/{name}` | Nenhum | `200` com o JSON de `kubectl get` |
| `GET /api/kubernetes/{kind}/{namespace}/{name}` | Nenhum | `200` com o JSON de `kubectl get` |
| `POST /api/kubernetes/namespaces/{name}/remove` | `{ "confirm": true }` | job |
| `POST /api/kubernetes/{kind}/{namespace}/{name}/remove` | `{ "confirm": true }` | job |
| `POST /api/kubernetes/deployments/{namespace}/{name}/scale` | `{ "replicas": 3 }`, de 0 a 1000 | job |
| `POST /api/kubernetes/apply` | `{ "yaml": "<texto>" }` | job |

`apply` roda `kubectl apply --dry-run=server --validate=strict -f -` e, só com sucesso, `kubectl apply -f -`. YAML inválido termina o job em `failed`, com o erro em `error.message`, e nada muda. Limite conhecido: arquivo que cria um namespace e recursos dentro dele é recusado no ensaio; a orientação é aplicar o namespace antes.

## WebSocket: regras comuns

- `Origin` obrigatória e exatamente igual a `http://127.0.0.1:<porta>` ou `http://localhost:<porta>`. Errada ou ausente: 403 antes do upgrade. Não existe exceção para servidor de desenvolvimento.
- Tudo o que não é segurança é recusado depois do upgrade, com um quadro de erro, porque o navegador não lê o corpo de um upgrade recusado.
- Quadros de controle são texto, com JSON:

```json
{ "type": "error", "code": "environment_not_on", "message": "the environment is not on", "params": { "state": "off" } }
```

| `type` | Onde | Significado |
| --- | --- | --- |
| `snapshot` | Tópicos | Snapshot completo, ver [Tópicos ao vivo](#tópicos-ao-vivo) |
| `error` | Todos | Mesmos `code`, `message`, `exitCode` e `params` do REST. A conexão fecha em seguida |
| `end` | Logs | O stream terminou normalmente |
| `exit` | Terminal | O processo terminou. Traz `exitCode` |

Fechamento: 1000 normal, 1001 serviço encerrando, 1008 quadro inválido do cliente, 1009 quadro acima de 64 KiB, 1013 limite de terminais.

Cada escrita tem prazo de 5 s: cliente lento demais perde a conexão. Compressão desligada.

## Tópicos ao vivo

`GET /ws/live/{topic}`, com `topic` igual a `environment`, `docker`, `kubernetes` ou `jobs`. Tópico inexistente: quadro `error` com `topic_not_found`.

- Cada quadro é o snapshot completo, sem diff: `{ "type": "snapshot", "topic": "docker", "data": { ... } }`.
- O primeiro chega logo ao assinar, e os seguintes a cada mudança de conteúdo. Cliente lento pula intermediários.
- O cliente não envia nada: mensagem recebida fecha a conexão.
- Sem assinante, o observador do tópico para. O cliente reconecta sozinho, com espera de até 2 s, e mostra a faixa enquanto reconecta.

| Tópico | Dispara em |
| --- | --- |
| `environment` | A cada 1 s e no fim de um job. Cada leitura roda `docker info` |
| `docker` | `docker events` relevante, com debounce de 150 ms; a cada 5 s; no fim de um job |
| `kubernetes` | A cada 1 s e no fim de um job |
| `jobs` | Cada mudança de job |

### `environment`

```json
{
  "state": "on",
  "serverVersion": "28.4.0",
  "cpus": 8,
  "memoryBytes": 16448081920,
  "storageDriver": "overlay2",
  "operatingSystem": "Ubuntu 24.04.3 LTS",
  "osType": "linux",
  "architecture": "x86_64"
}
```

- `state`: `on`, `off` ou `unknown`. `off` significa que nada responde no socket. `unknown` significa outra falha, como permissão negada ou binário ausente.
- `reason`, só quando o estado não é `on`: o erro recebido.
- Os demais campos só existem com o estado `on`. Memória em bytes.

### `docker`

```json
{
  "available": true,
  "composeProjects": [{ "name": "observability", "state": "running", "status": "running(1)", "configFiles": ["/home/.../compose.yaml"] }],
  "containers": [{ "id": "b295...", "name": "observability-otel-lgtm-1", "image": "grafana/otel-lgtm:0.39.0", "command": "\"bash ...\"", "state": "running", "status": "Up 5 minutes (healthy)", "health": "healthy", "ports": "127.0.0.1:3000->3000/tcp", "createdAt": "2026-11-16 18:34:13 -0300 -03", "composeProject": "observability" }],
  "images": [{ "id": "sha256:...", "repository": "alpine", "tag": "3.20", "reference": "alpine:3.20", "size": "7.8MB", "createdAt": "..." }],
  "volumes": [{ "name": "data", "driver": "local", "scope": "local", "mountpoint": "/var/lib/docker/volumes/data/_data", "composeProject": "observability" }],
  "networks": [{ "id": "48b4...", "name": "bridge", "driver": "bridge", "scope": "local", "internal": false, "createdAt": "..." }]
}
```

- `available: false`: listas vazias, `reason` com o erro recebido e `reasonCode` igual a `environment_not_on` ou `docker_error`. A tela mostra as ações desabilitadas, com o motivo.
- Contêineres de pods, com o rótulo `io.kubernetes.pod.namespace`, não aparecem: têm tela própria.
- `composeProjects` aparece mesmo com o Docker desligado, com `state` igual a `unknown`. Valores de `state`: `running`, `exited`, `down` ou `unknown`.
- `composeProject` existe em contêineres, volumes e redes. Vem do rótulo `com.docker.compose.project` do recurso e diz a qual projeto Compose ele pertence. Recurso sem o rótulo não tem o campo (no exemplo, a rede `bridge`).
- Campos vazios em `health`, `composeProject`, `reason` e `reasonCode` são omitidos.

### `kubernetes`

```json
{
  "available": true,
  "namespaces": [{ "name": "default", "status": "Active", "createdAt": "2026-11-16T21:00:00Z" }],
  "pods": [{ "namespace": "default", "name": "web-1", "status": "Running", "ready": "1/1", "restarts": 0, "ip": "10.42.0.9", "containers": ["web"], "createdAt": "..." }],
  "deployments": [{ "namespace": "default", "name": "web", "replicas": 2, "ready": 2, "updated": 2, "available": 2, "createdAt": "..." }],
  "services": [{ "namespace": "default", "name": "web", "type": "NodePort", "clusterIP": "10.43.0.5", "ports": ["80:30080/TCP"], "createdAt": "..." }]
}
```

`available: false`: listas vazias, `reason` com o erro recebido e `reasonCode` igual a `kubernetes_unavailable`, sem cluster acessível no contexto atual do kubeconfig ou em `CONSOLE_KUBE_CONTEXT`. A tela mostra o erro e o tópico continua tentando. O tópico não depende do tópico `environment`.

### `jobs`

`{ "jobs": [<Job>, ...] }`, do mais novo para o mais antigo.

## Logs

- `GET /ws/logs/containers/{id}`
- `GET /ws/logs/pods/{namespace}/{name}?container=<opcional>`

Só servidor para cliente:

- Quadro **binário**: bytes crus de stdout e stderr, com ANSI, começando pelas últimas 500 linhas.
- Quadro de texto: `end` ou `error`, seguido do fechamento.

O cliente não envia nada. Fechar o WebSocket encerra o processo no host.

## Terminal

- `GET /ws/terminal/containers/{id}?cols=80&rows=24`
- `GET /ws/terminal/pods/{namespace}/{name}?container=<opcional>&cols=80&rows=24`

`cols` e `rows` são opcionais, de 1 a 1000; o padrão é 80 por 24. Até 8 terminais simultâneos: acima disso, `error` com `too_many_terminals` e fechamento 1013. O serviço tenta `bash` e cai para `sh`; imagem sem shell mostra o erro no próprio terminal e termina com `exit`.

| Direção | Quadro | Conteúdo |
| --- | --- | --- |
| Cliente para servidor | Binário | Teclas, em bytes |
| Cliente para servidor | Texto | `{ "type": "resize", "cols": 120, "rows": 40 }` |
| Servidor para cliente | Binário | Saída do PTY |
| Servidor para cliente | Texto | `{ "type": "exit", "exitCode": 0 }` ou `error`, seguido do fechamento |

Texto diferente de `resize`, ou tamanho fora do limite, termina com `error` (`invalid_terminal_frame` ou `invalid_terminal_size`) e fechamento 1008. Fechar o WebSocket encerra o processo no host. O conteúdo do terminal nunca vai para o log do serviço.

## O que o front-end precisa respeitar

- Enviar `Content-Type: application/json` em todo POST, mesmo com corpo vazio. Sem ele a resposta é 403.
- `vite.config.ts`: `build.outDir` igual a `../internal/webui/dist`, `build.emptyOutDir` igual a `false` (o `Makefile` limpa a pasta preservando `placeholder.html`) e `build.assetsInlineLimit` igual a `0`, porque a CSP recusa `data:`.
- CSP: `default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; connect-src 'self' ws://127.0.0.1:<porta> ws://localhost:<porta>; frame-ancestors 'none'; base-uri 'none'; form-action 'none'`. Sem script inline, recurso externo nem `<form action>`. Use `onSubmit` com `preventDefault`.
- Rotas da tela por hash. O serviço só entrega arquivos do `dist/`, e `/assets/` tem cache longo.
- `package.json` precisa dos scripts `build` e `check`, chamados pelo `Makefile`.
- xterm: nos logs, ative `convertEol`, porque a saída tem só `\n`, e `disableStdin`. No terminal, envie cada entrada em quadros de até 64 KiB, inclusive ao colar: acima disso o servidor fecha com 1009.
- Depois de uma ação, espere o snapshot em vez de mudar a linha sozinho. Uma falha aparece pelo `error` do job, e a linha continua mostrando o estado real.
