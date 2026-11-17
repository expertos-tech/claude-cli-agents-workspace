<!-- source: workspace/tools/container-console-docker-ce/README.md sha256:f49c5fde8eb0ad671c828e5b8e3c1ed9cb6786216f75ca6e5c794abb9ee01761 -->

# container-console-docker-ce

- [O que é](#o-que-é)
- [Como rodar](#como-rodar)
- [Como testar](#como-testar)
- [Como desinstalar](#como-desinstalar)
- [Como implantar](#como-implantar)
- [Documentação](#documentação)

## O que é

Console local, no navegador, para o ambiente de contêineres desta máquina Linux com docker-ce: mostra o estado do daemon do Docker e gerencia contêineres (agrupados por projeto Compose), imagens, volumes, redes, projetos Compose e recursos do Kubernetes, com logs ao vivo e terminal, e limpa o que nenhum contêiner ativo usa. A tela é em inglês por padrão e passa para o português do Brasil quando o idioma do navegador começa com `pt`.

É um serviço em Go que escuta só em `127.0.0.1:27850`, sem login, e serve a tela React embutida no binário. Um atalho na área de trabalho abre o endereço no navegador padrão, e o serviço sobe sozinho a cada login na sessão gráfica. Para um usuário.

A tela de ambiente é só leitura: controlar o docker-ce exige root, então o console nunca liga nem desliga o daemon. Com o daemon desligado, a tela diz isso e mostra o comando `sudo systemctl start docker`, para você rodar.

O tema segue o sistema operacional por padrão, e o campo `Tema`, no menu lateral, troca entre sistema, escuro e claro.

## Como rodar

Pré-requisitos: docker-ce com Docker Compose v2 e o seu usuário no grupo `docker`, `kubectl` (só para a tela de Kubernetes), `zenity` (só para o diálogo de arquivo), `xdg-open`, `systemd --user`, Go (versão do `go.mod`) e Node 24, que só o build usa.

Na pasta `tools/container-console-docker-ce`, com o Node 24 no `PATH`:

```bash
make install
```

O `make install` compila o front-end e o binário e roda `linux/install-console.sh`, que instala o binário em `~/.local/bin`, a unit `container-console-docker-ce.service` do `systemd --user` e o atalho `container-console-docker-ce.desktop`, com o ícone do projeto Claude CLI Agents Workspace (`web/public/favicon.png`, recortado do logo em `assets/` da raiz). Ao terminar, imprime `installed container-console-docker-ce.service and <caminho do atalho>`. Repetir o comando é seguro.

Depois, clique em "Container Console" no menu de aplicativos ou abra <http://127.0.0.1:27850/>. O atalho acorda o serviço se ele estiver parado.

Sem instalar, para experimentar: `make build` e `.data/bin/container-console-docker-ce`.

Não há agente de login para o Docker: o `dockerd` sobe com o sistema, e o Grafana de `tools/observability` volta sozinho com ele, pela política `restart: unless-stopped`.

Verificações de compilação: `make check` (`gofmt`, `go vet`, `go build`, `npm audit --audit-level=high` e `tsc --noEmit`).

## Como testar

Não há teste automatizado: a ferramenta é verificada pela compilação (`make check`, mais `bash scripts/validate.sh --only secrets` na raiz do workspace) e por testes manuais. Os testes manuais, com passos e resultado esperado, um bloco por requisito, estão em [`docs/manual-tests.md`](docs/manual-tests.md): as telas, o atalho, a unit e o reinício da máquina.

## Como desinstalar

```bash
bash linux/uninstall-console.sh
```

Remove a unit, o atalho, o ícone copiado e o binário. Não mexe no Docker, nos contêineres, no log, na lista de projetos Compose nem em `~/.config/container-console-docker-ce/env`.

## Como implantar

Só local, nesta máquina: não há nuvem, servidor nem custo. O `make install` é a implantação.

## Documentação

| Página | Conteúdo |
| --- | --- |
| [docs/overview.md](docs/overview.md) | O que é, para quem, escopo |
| [docs/architecture.md](docs/architecture.md) | Componentes e fluxos |
| [docs/api.md](docs/api.md) | Contrato REST e WebSocket |
| [docs/operations.md](docs/operations.md) | Configuração, logs e falhas comuns |
| [docs/manual-tests.md](docs/manual-tests.md) | Testes que você faz, por requisito |
