<!-- source: workspace/tools/container-console-docker-ce/docs/operations.md sha256:50c3b74822fa515306ba895949da38ee8c4a27312073935b0b7bc3966bd7ee98 -->

# Operação do `container-console-docker-ce`

- [Instalar, atualizar e remover](#instalar-atualizar-e-remover)
- [A unit e o atalho](#a-unit-e-o-atalho)
- [Configuração](#configuração)
- [Arquivos e logs](#arquivos-e-logs)
- [Monitoramento](#monitoramento)
- [Falhas comuns](#falhas-comuns)

Guia de quem opera a ferramenta, que é a mesma pessoa que a usa. Ferramenta local: sem nuvem, sem servidor, sem custo de infraestrutura. Sem alertas.

## Instalar, atualizar e remover

| Tarefa | Comando, na pasta `tools/container-console-docker-ce` |
| --- | --- |
| Instalar ou atualizar o console | `make install`, com o Node 24 no `PATH` (repetir é seguro) |
| Só compilar, sem instalar | `make build` e `.data/bin/container-console-docker-ce` |
| Verificar a compilação | `make check` |
| Remover o console | `bash linux/uninstall-console.sh` |

O instalador recusa sobrescrever uma unit ou um atalho com o mesmo nome que ele não escreveu, reconhecidos pelo comentário `Installed by container-console-docker-ce`. O desinstalador desfaz só o que o instalador escreveu e não mexe no Docker, nos contêineres, no log, na lista de projetos Compose nem em `~/.config/container-console-docker-ce/env`.

## A unit e o atalho

| Peça | Quando roda | O que faz |
| --- | --- | --- |
| `container-console-docker-ce.service` (`systemd --user`) | Do login na sessão gráfica em diante (`WantedBy=graphical-session.target`, `Restart=on-failure`) | Mantém o serviço em `127.0.0.1:27850`. Se o processo falha, o systemd o sobe de novo |
| `container-console-docker-ce.desktop` | Ao clicar no atalho | Roda `systemctl --user start container-console-docker-ce.service` e abre o endereço com `xdg-open` |

- A unit parte da sessão gráfica porque o diálogo de arquivo precisa de `DISPLAY` ou `WAYLAND_DISPLAY`, que a sessão exporta ao gerenciador do usuário.
- `KillMode=process`: reiniciar o serviço não envia sinal às CLIs em andamento. O registro do job se perde, e uma CLI que ainda escreva saída pode terminar com o pipe fechado. Depois de reiniciar, confira o estado real na lista.
- O Docker não depende do console: o `dockerd` sobe com o sistema, e o Grafana volta sozinho com ele, pela política `restart: unless-stopped` de `tools/observability`.

## Configuração

O serviço lê variáveis `CONSOLE_*` ao iniciar. Valor inválido impede o início e é listado na saída de erro. Todas têm padrão; a instalação não define nenhuma.

Para testar uma variável, pare a unit com `systemctl --user stop container-console-docker-ce.service` e rode o binário à mão (`CONSOLE_MAX_TERMINALS=2 .data/bin/container-console-docker-ce`). Para fixar uma variável, escreva `VARIAVEL=valor`, uma por linha, em `~/.config/container-console-docker-ce/env`, e rode `systemctl --user restart container-console-docker-ce.service`.

Rede, contexto e caminhos:

| Variável | Padrão | Observação |
| --- | --- | --- |
| `CONSOLE_LISTEN` | `127.0.0.1:27850` | O host só pode ser `127.0.0.1`; outro endereço impede o início |
| `CONSOLE_DOCKER_HOST` | `unix:///var/run/docker.sock` | Precisa começar com `unix://` |
| `CONSOLE_KUBE_CONTEXT` | Vazio | Vazio não passa `--context`, e vale o contexto atual do kubeconfig |
| `CONSOLE_STATE_DIR` | `$XDG_STATE_HOME/container-console-docker-ce`, ou `~/.local/state/container-console-docker-ce` | Lista de projetos Compose |
| `CONSOLE_LOG_FILE` | `console.log` em `CONSOLE_STATE_DIR` | Truncado a cada início |
| `CONSOLE_PATH_PREPEND` | Vazio | Pastas que vão na frente do `PATH` herdado |
| `CONSOLE_DOCKER_BIN`, `CONSOLE_KUBECTL_BIN`, `CONSOLE_ZENITY_BIN` | Nome puro (`docker`, `kubectl`, `zenity`) | Nome puro ou caminho absoluto |

Prazos (duração, como `90s` ou `5m`):

| Variável | Padrão |
| --- | --- |
| `CONSOLE_TIMEOUT_READ` | `5s` (consultas) |
| `CONSOLE_TIMEOUT_DOCKER_ACTION` | `90s` |
| `CONSOLE_TIMEOUT_DOCKER_PULL` | `30m` |
| `CONSOLE_TIMEOUT_COMPOSE_ACTION` | `15m` |
| `CONSOLE_TIMEOUT_KUBE_ACTION` | `2m` |
| `CONSOLE_TIMEOUT_FILE_PICKER` | `5m` |
| `CONSOLE_TIMEOUT_PROCESS_WAIT` | `5s` |
| `CONSOLE_TIMEOUT_HTTP_HEADER` | `5s` |
| `CONSOLE_TIMEOUT_HTTP_READ` | `30s` |
| `CONSOLE_TIMEOUT_HTTP_IDLE` | `60s` |
| `CONSOLE_TIMEOUT_WS_WRITE` | `5s` |
| `CONSOLE_TIMEOUT_SHUTDOWN` | `10s` |

Cadência dos tópicos ao vivo e limites:

| Variável | Padrão |
| --- | --- |
| `CONSOLE_INTERVAL_ENVIRONMENT`, `CONSOLE_INTERVAL_KUBERNETES` | `1s` |
| `CONSOLE_INTERVAL_DOCKER_SYNC` | `5s` |
| `CONSOLE_INTERVAL_DOCKER_DEBOUNCE` | `150ms` |
| `CONSOLE_INTERVAL_EVENTS_RETRY` | `2s` |
| `CONSOLE_MAX_BODY_BYTES` | `1048576` (1 MiB) |
| `CONSOLE_MAX_HEADER_BYTES` | `65536` |
| `CONSOLE_WS_READ_BYTES` | `65536` |
| `CONSOLE_MAX_TERMINALS` | `8` |
| `CONSOLE_JOBS_KEPT` | `50` |
| `CONSOLE_JOB_OUTPUT_LINES` | `200` |
| `CONSOLE_REPLICAS_MAXIMUM` | `1000` |

## Arquivos e logs

| O quê | Onde |
| --- | --- |
| Log do serviço (JSON, sem conteúdo de terminal nem de logs de contêiner) | `~/.local/state/container-console-docker-ce/console.log` |
| Erros de início do serviço, como porta ocupada | `journalctl --user -u container-console-docker-ce.service` |
| Binário instalado | `~/.local/bin/container-console-docker-ce` |
| Projetos Compose conhecidos (nome e caminho) | `~/.local/state/container-console-docker-ce/compose-projects.json` |
| Unit | `~/.config/systemd/user/container-console-docker-ce.service` |
| Variáveis opcionais | `~/.config/container-console-docker-ce/env` |
| Atalho | `~/.local/share/applications/container-console-docker-ce.desktop` |
| Ícone, cópia sem alteração de `web/public/favicon.png` | `~/.local/share/container-console-docker-ce/favicon.png` |
| Dados do Grafana | `tools/observability/.data/` (bind mount) |

## Monitoramento

- Saúde do serviço: `curl -s http://127.0.0.1:27850/healthz` devolve `{"status":"ok"}`.
- Unit: `systemctl --user status container-console-docker-ce.service`.
- Docker: `systemctl status docker` e `docker info`.
- Kubernetes: `kubectl config current-context` e `kubectl get --raw /version`.
- Grafana: <http://localhost:3000>.

## Falhas comuns

| Sintoma | Causa provável | O que fazer |
| --- | --- | --- |
| O atalho abre o navegador, mas a página não carrega | A unit não subiu: porta ocupada ou erro ao iniciar | Leia `journalctl --user -u container-console-docker-ce.service`. Se a unit não existir, rode `make install` |
| A tela mostra o ambiente como desligado | O `dockerd` não responde no socket | Rode `sudo systemctl start docker`. O console nunca roda esse comando, porque ele exige root |
| A tela mostra o ambiente como desconhecido, com `permission denied` | O usuário não está no grupo `docker`, ou a sessão é anterior à entrada nele | `sudo usermod -aG docker $USER` e entre de novo na sessão |
| A tela mostra o ambiente como desconhecido, com motivo de binário ausente | `docker` fora do `PATH` da unit | Ajuste `CONSOLE_PATH_PREPEND` ou `CONSOLE_DOCKER_BIN` |
| Ações de Docker indisponíveis com o Docker ligado | Socket diferente do configurado | Confira `CONSOLE_DOCKER_HOST` e a saída de `docker context ls` |
| O Docker volta sozinho depois de `sudo systemctl stop docker` | O `docker.socket` segue ativo, e a leitura de `docker info` do console reativa o daemon | Para mantê-lo parado: `sudo systemctl stop docker.socket docker.service` |
| Kubernetes indisponível | Nenhum cluster responde no contexto usado | Confira `kubectl config current-context` e `CONSOLE_KUBE_CONTEXT`. A tela mostra o erro e continua tentando |
| `kubectl` diz que o contexto não existe | `CONSOLE_KUBE_CONTEXT` aponta para um nome fora do kubeconfig, ou a unit lê outro kubeconfig | `kubectl config get-contexts`. Um `KUBECONFIG` fora do padrão vai em `~/.config/container-console-docker-ce/env` |
| "Escolher arquivo" falha com `Failed to open display` | A unit subiu sem as variáveis da sessão gráfica | Em um terminal da sessão: `systemctl --user import-environment DISPLAY WAYLAND_DISPLAY` e `systemctl --user restart container-console-docker-ce.service`. O campo de caminho continua funcionando |
| "Escolher arquivo" falha com binário ausente | `zenity` não instalado | Instale o pacote `zenity` ou ajuste `CONSOLE_ZENITY_BIN`. O campo de caminho continua funcionando |
| `docker pull` falha com `docker-credential-*: executable file not found` | `credsStore` em `~/.docker/config.json` aponta para um programa que não existe nesta máquina | Remova a chave ou aponte para um auxiliar instalado |
| Porta 3000, 4317 ou 4318 ocupada ao subir o Grafana | Outra stack usa a porta | Pare a outra stack |
| O atalho não aparece no menu depois do `make install` | O menu ainda não leu a pasta de atalhos | `update-desktop-database ~/.local/share/applications` e, se persistir, entre de novo na sessão |
