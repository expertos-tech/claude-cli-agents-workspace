<!-- source: workspace/tools/README.md sha256:00dd8dc067c2bac16b1bb13fd18682f03d625c0fb16076389693887c49c017fd -->

# tools

Ferramentas de apoio a ambientes locais, parte do core do workspace. Uma pasta por ferramenta. Uma ferramenta com interface mostra a identidade do projeto, Claude CLI Agents Workspace: o nome e o logo ou o ícone de `assets/` da raiz, nunca a identidade de uma empresa. Num workspace instalado esta pasta é só leitura: as suas próprias ferramentas ficam na camada custom, em `custom/tools/<name>/` (`bash scripts/init-repo.sh --type tool`), e as POCs em `custom/pocs/`. Uma ferramenta que aceita configurações tem um `.env.example` ao lado; o arquivo preenchido é `custom/env/<name>.env` (`/local-env tools/<name>`), passado ao compose com `--env-file`.

| Item | Tipo | Objetivo |
| --- | --- | --- |
| observability | ferramenta | Grafana e receptor OTLP locais para a telemetria do Claude Code e os dashboards dos projetos |
| container-console-docker-ce | ferramenta | Console local no navegador para ver o docker-ce e gerir contêineres, Compose e Kubernetes, aberto por um atalho no GNOME |
| container-console-colima | ferramenta | Gêmeo macOS do container-console-docker-ce: console local no navegador para controlar o Colima e gerir contêineres, Compose e Kubernetes, aberto por um ícone no Dock |
| claude-usage | ferramenta | Relatório local de uso do Claude Code por dia, por sessão e por modelo, lido dos registros em `~/.claude/projects` |
| fable-alert | ferramenta | Alerta visual (fundo do terminal e faixa) quando a sessão do Claude Code roda no Fable, com barra de status e gravador de abertura |
| login-simulator | ferramenta | Login local no lugar do Auth0: usuários fictícios fixos, login por clique, sem internet, sempre ativo no Docker |
| azurite-console | ferramenta | Página para ver e operar o Azurite local: blobs, filas, tabelas e o log de acesso, com compose próprio |
| safe-browsing-simulator | ferramenta | Google Safe Browsing local (Lookup v4): URLs perigosas e serviço fora do ar vindos de um arquivo, sem internet e sem chave real |

## Portas no host

Uma porta aparece uma vez só. Projeto: a convencional quando livre, senão outra livre abaixo de 20000. Ferramenta: a convencional; sem convencional, a partir de 20000. POC e `docker/`: a partir de 20000.

| Porta | Dono | Tipo | Uso |
| --- | --- | --- | --- |
| 3000 | `tools/observability` | ferramenta | Grafana |
| 4317, 4318 | `tools/observability` | ferramenta | OTLP gRPC e HTTP |
| 17850 | `tools/container-console-colima` | ferramenta | serviço (`CONSOLE_LISTEN`); macOS, agente launchd |
| 27850 | `tools/container-console-docker-ce` | ferramenta | serviço (`CONSOLE_LISTEN`); Linux e WSL, `systemd --user` |
| 28080 | `tools/login-simulator` | ferramenta | simulador de login no lugar do Auth0; fotos geradas em `172.31.250.10:8080`, rede `login-simulator` com a sub-rede fixa `172.31.250.0/24` |
| 25174 | `tools/azurite-console` | ferramenta | Vite em desenvolvimento |
| 28090 | `tools/safe-browsing-simulator` | ferramenta | simulador do Google Safe Browsing (Lookup v4); rede `safe-browsing-simulator` |
| 28091 | `tools/azurite-console` | ferramenta | console |
| 29000 | `docker/sonar` | `docker/` | SonarQube |
| 30000–30002 | `tools/azurite-console` | ferramenta | Azurite (blob, fila, tabela) |

As portas dos projetos estão na camada custom, em `custom/projects.md`.
