<!-- source: docs/features.md sha256:1184b77dc92e9620543dd97b37cdc7008e99ad96961ea016f6267e81bee7510c -->

# Funcionalidades

[English](../../../docs/features.md) · Português (Brasil) · [Español](../../es/docs/features.md)

## O que você recebe

- **Regras** para o agente: uma página que vale em toda sessão (`AGENTS.md`) e regras por assunto (git, segurança,
  qualidade, documentação, frontend, infraestrutura, modelos, revisão), lidas quando o assunto aparece.
- **Skills**: comandos de barra para o fluxo do dia a dia (`/merge`, `/commit`, `/push`, `/validate`, `/draft-prompt`,
  `/prompt`, `/pilot`, `/local-env`, `/normalize-projects`).
- **Agentes**: subagentes para requisitos, arquitetura, implementação, testes, revisão, verificação, infraestrutura,
  scripts, documentação e pesquisa, cada um com o seu modelo e o seu effort.
- **Hooks** que guardam só o que nunca pode acontecer sem você: escrita git fora do gate, mudança na nuvem, apagar
  banco de dados, segredo num commit. [Hooks que rodam na sua máquina](hooks.md) lista todos.
- **Um gate de merge**: o trabalho acontece num clone em `tmp/work/`, e o `/merge` o leva para a branch `developer` do
  projeto depois da suíte de testes inteira, das validações, de uma varredura de segredos e de uma revisão contra o seu
  pedido.
- **Uma camada custom**: o seu próprio repositório git privado em `custom/`, para a sua empresa, a nuvem, a identidade
  visual, a lista de projetos, os pedidos e as lições. Ela nunca entra neste repositório.
- **Ferramentas**: um Grafana local para a telemetria do Claude Code, um console de contêineres (Docker CE no Linux,
  Colima no macOS), simuladores de login e de Safe Browsing, um console do Azurite, um relatório de uso e um alerta de
  modelo. Cada uma tem o seu README em `workspace/tools/`.

## A camada custom

O `custom/` é o **seu** repositório git privado, separado do produto, e o único lugar para o que é seu: nome e grafia da
empresa, nuvem e tenant, identidade visual, a lista dos seus projetos, os pedidos escritos, as lições, os `.env`
preenchidos (`custom/env/`, sempre ignorados pelo git) e o registro de prompts. O workspace funciona sem ela e pergunta,
quando precisa, a nuvem, a identidade visual e a pasta de cada projeto. Ela nunca entra num pull request para este
repositório.
