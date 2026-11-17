<!-- source: workspace/projects/README.md sha256:7ce630b736d61b678d355daf5b9f06a97c4ba8448f12345103691ff85f9a53a7 -->

# projects

Aqui ficam os repositórios dos projetos em que o workspace trabalha. A pasta é do workspace; o conteúdo, não: as subpastas são ignoradas pelo core, e só este README faz parte dele.

## Como a pasta funciona

- **Um repositório por projeto.** Cada projeto é um repositório git independente, em `projects/<name>/`. Uma pasta pode agrupar repositórios (por exemplo, os de um cliente: `projects/<client>/<name>/`); a pasta que agrupa não é repositório.
- **A lista de projetos fica na camada custom**, em `custom/projects.md`: caminho, remoto, objetivo e portas de cada projeto. É lá que um projeto novo é registrado, com commit no repositório do `custom/`.
- **Sempre na `developer`.** O checkout de cada repositório fica na `developer` (ou na `main`, quando o projeto não tem `developer`) e não é editado aqui. Todo trabalho acontece num clone em `tmp/work/` (`bash scripts/aiwp-cmds.sh open`) e chega a esta pasta só pelo gate (`/merge`). Um hook recusa qualquer escrita git nesta pasta fora dele.
- **Abra o Claude na raiz do workspace**, não dentro de um projeto, para valerem o `AGENTS.md`, as `rules/` e os hooks.

## Como trazer um projeto

- **Um que já existe:** numa sessão, `/normalize-projects --from <url | folder> --name [<folder>/]<name>`. Ele clona o projeto aqui e o traz para o workspace: uma análise, um plano que você aprova, a migração numa branch testada, `developer` e `main` com o marcador. Um projeto clonado aqui à mão também serve: a sessão avisa que ele não tem marcador e pede para normalizar.
- **Um novo:** `bash scripts/init-repo.sh --type project --name <name> [--parent <folder>]`, que cria o repositório, escreve o marcador no `README.md` dele e registra a linha dele em `custom/projects.md`.
- **O marcador:** a linha 1 do `README.md` de cada projeto na `developer`, `<!-- AI-WORKSPACE-PROJECT x.y.z -->`. `bash scripts/aiwp-project-state.sh` mostra o estado de cada projeto.

## Convenções

- **Portas:** cada projeto usa portas no host só suas, registradas em `custom/projects.md`; as das ferramentas do workspace estão em `tools/README.md`. Escolha uma que não esteja em nenhuma das duas tabelas, fora de 32768–60999, e registre no mesmo commit que passa a usá-la (`rules/rules.md` "Workspace layout").
- **Dashboards no Grafana local:** `observability/dashboards/*.json` no repositório do projeto (convenção em `tools/observability/README.md`).
- **Língua:** código em inglês é recomendado, não obrigatório (`rules/rules.md` "Language").
