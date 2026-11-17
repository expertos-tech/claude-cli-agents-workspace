<!-- source: workspace/tools/container-console-docker-ce/docs/overview.md sha256:c0f002a6ccf7485f74b04c872adef89a7b678e12f5a1d7c1b55b404d845e9e90 -->

# Visão geral do `container-console-docker-ce`

## O que é

Console local, no navegador, que gerencia o ambiente de contêineres da máquina Linux: mostra o estado do docker-ce e gerencia contêineres, imagens, volumes, redes, projetos Compose e o cluster Kubernetes do kubeconfig. Roda como um serviço em Go no `systemd --user` e abre por um atalho na área de trabalho. A tela é em inglês por padrão e em português do Brasil quando o idioma do navegador começa com `pt`.

## Por quê

O docker-ce não tem interface. O console dá a gestão pela tela, sem abrir o terminal.

## Quem usa

Uma pessoa, a dona da máquina, no grupo `docker`. Sem login: só aceita acesso da própria máquina (`127.0.0.1`), e recusa `Host` e `Origin` de outros sites. Sem papéis, sem outras máquinas.

## O que faz

| Área | Ações |
| --- | --- |
| Ambiente | Só leitura: estado do daemon, versão, CPUs, memória, driver de armazenamento, sistema e arquitetura. Com o daemon desligado, mostra `sudo systemctl start docker` como texto |
| Contêineres | Listar, iniciar, parar, reiniciar, remover, detalhes, uso de recursos, logs ao vivo e terminal |
| Imagens | Listar, baixar e remover |
| Volumes e redes | Listar, criar, detalhes e remover |
| Compose | Listar projetos, subir, parar e remover |
| Kubernetes | Com o contexto atual do kubeconfig ou `CONSOLE_KUBE_CONTEXT`: listar e detalhar namespaces, pods, deployments e services; remover; escalar deployments; logs ao vivo; terminal no pod; aplicar YAML (YAML inválido é recusado e nada muda). Sem cluster acessível, mostra indisponível |
| Limpeza | Remove o que nenhum contêiner ativo usa: contêineres parados, imagens e redes sem uso, volumes só se pedido, e o cache de build |

Regras que valem em toda a tela: remoção sempre pede confirmação; uma ação que falha mostra o erro recebido, sem tradução, e a lista continua mostrando o estado real; com o Docker desligado a tela abre, mostra o estado e deixa as ações de Docker desabilitadas, com o motivo; uma mudança precisa aparecer em até 2 s, com até 30 contêineres.

## O que não faz

Ligar ou desligar o daemon do Docker, ajustar os recursos dele, criar ou ligar um cluster Kubernetes, medir desempenho, build de imagens pela tela, uso em outras máquinas ou por outros usuários, e nuvem.

## Estado

- A ferramenta não tem teste automatizado. É verificada pela compilação (`make check`) e pelos [testes manuais](manual-tests.md), que você faz em navegador real nesta máquina.
- O tema segue o sistema operacional por padrão, e a pessoa troca entre sistema, escuro e claro no menu lateral. O contraste foi calculado por script; o resultado na tela é conferido nos [testes manuais](manual-tests.md#tema).

## Mapa

[README](../README.md) · [arquitetura](architecture.md) · [API](api.md) · [operação](operations.md) · [testes manuais](manual-tests.md)
