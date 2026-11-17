<!-- source: workspace/tools/container-console-colima/README.md sha256:7086e78e80dea49a544f21c9fd89d27d30fd70c32e82207f4e7f7aaf2d55be34 -->

# container-console-colima

- [O que é](#o-que-é)
- [Como rodar](#como-rodar)
- [Como testar](#como-testar)
- [Como desinstalar](#como-desinstalar)
- [Como implantar](#como-implantar)

## O que é

Console local, no navegador, para o ambiente de contêineres de um Mac com Colima: mostra e controla a VM do Colima, liga e desliga o Kubernetes dela, e gerencia contêineres, imagens, volumes, redes, projetos Compose e recursos do Kubernetes, com logs ao vivo e terminal. É o gêmeo macOS/Colima do [`container-console-docker-ce`](../container-console-docker-ce/README.md), com a mesma identidade visual: o ícone e o nome do projeto Claude CLI Agents Workspace na barra do topo, com "Container Console · Colima" embaixo. A tela é em inglês por padrão e passa para o português do Brasil quando o idioma do navegador começa com `pt`.

É um serviço em Go que escuta só em `127.0.0.1:17850`, sem login, e serve a tela React embutida no binário. Um ícone no Dock abre o endereço no navegador padrão, e um LaunchAgent sobe o serviço a cada login na sessão gráfica. Para um usuário.

O diálogo de arquivo é o nativo do macOS, por `osascript`. O tema segue o sistema operacional por padrão, e o campo `Tema`, no menu lateral, troca entre sistema, escuro e claro.

## Como rodar

Pré-requisitos: macOS com Colima, o CLI `docker` com Docker Compose v2 e `kubectl` (só para a tela de Kubernetes), pelo Homebrew em `/opt/homebrew/bin`; Go (versão do `go.mod`) e Node, que só o build usa.

Na pasta `tools/container-console-colima`:

```bash
make install
```

O `make install` compila o front-end e o binário e roda `macos/install-console.sh`, que instala:

- o binário em `~/Library/Application Support/container-console-colima/bin`;
- o LaunchAgent `io.github.expertos-tech.claude-cli-agents-workspace.container-console-colima` em `~/Library/LaunchAgents`, carregado na hora por causa do `RunAtLoad`;
- o app `~/Applications/Container Console (Colima).app`, com o ícone do projeto (`web/public/favicon.png`);
- o app no Dock. Se esse passo falha, o script diz como fazer à mão e a instalação continua valendo.

Ao terminar, imprime `installed <label> and <caminho do app>`. Repetir o comando é seguro. O instalador recusa sobrescrever um plist ou um app com o mesmo nome que ele não escreveu. Use `--verbose` para ver cada passo.

Depois, clique em "Container Console (Colima)" no Dock ou abra <http://127.0.0.1:17850/>. O ícone acorda o serviço se ele não responde e, se ele não sobe em 5 s, mostra um alerta com o caminho dos logs (`~/Library/Logs/container-console-colima/`).

Sem instalar, para experimentar: `make build` e `.data/bin/container-console-colima`.

Opcional, para subir o runtime no login: `runtime/install-runtime.sh --compose-file <caminho absoluto>` instala o LaunchAgent `io.github.expertos-tech.claude-cli-agents-workspace.container-runtime`, que roda `runtime/login-start.sh` a cada login. Ele liga a VM do Colima com o Kubernetes desligado (tenta de novo uma vez, depois de um `colima stop --force`), desliga o Kubernetes se estiver ligado e roda `docker compose up` no arquivo dado. Grava horários e durações em `~/Library/Logs/container-console-colima/runtime.log` e mostra uma notificação do macOS se falha. O plist aponta para `login-start.sh` nesta pasta: mover o workspace pede uma nova instalação.

Verificações de compilação: `make check` (`gofmt`, `go vet`, `go build`, `npm audit --audit-level=high` e `tsc --noEmit`).

## Como testar

Os scripts do runtime têm testes de unidade, com `colima`, `docker`, `osascript` e `launchctl` falsos no `PATH`, que não tocam na VM, no Docker nem no launchd. Precisam do `plutil` do macOS:

```bash
bash runtime/tests/test-login-start.sh
```

A tela e o ícone do Dock você confere à mão, no Mac: instale, abra pelo Dock e percorra as telas de visão geral, ambiente, contêineres, imagens, volumes, redes, Compose e Kubernetes.

## Como desinstalar

```bash
bash macos/uninstall-console.sh
bash runtime/uninstall-runtime.sh
```

O primeiro remove só o que `install-console.sh` escreveu: o ícone do Dock, o app, o LaunchAgent e o binário. Não mexe no LaunchAgent do runtime, na VM, nos contêineres, nos logs nem na lista de projetos Compose. O segundo descarrega o LaunchAgent do runtime e remove o plist dele, sem parar a VM nem os contêineres. Os dois falham, sem mudar nada, diante de um plist ou app com o mesmo nome que não foi escrito por eles.

## Como implantar

Só local, no Mac: não há nuvem, servidor nem custo. O `make install` é a implantação.
