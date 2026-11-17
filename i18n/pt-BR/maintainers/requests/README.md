<!-- source: maintainers/requests/README.md sha256:7d1d94a127d87311db94b2d82b49a6326f391a259ca5a54f74cf31b1455881b3 -->

# Pedidos

[English](../../../../maintainers/requests/README.md) · Português (Brasil) · [Español](../../../es/maintainers/requests/README.md)

Pedidos funcionais para o próprio workspace, prontos para rodar na raiz do repositório, onde o projeto é mantido. Cada
um tem o objetivo, as regras de negócio (BR-n), os critérios de aceite (AC-n), o que está fora de escopo e as etapas com
o effort de cada uma. O desenho por trás de cada pedido está em `maintainers/plans/`.

Rode-os nesta ordem; cada um depende dos anteriores:

| # | Pedido | Desenho | Estado |
| --- | --- | --- | --- |
| 0a | `done/merge-versioned-changelog.md` | — | Em andamento; plano aprovado em 2026-11-17, registrado na aprovação |
| 0b | `done/caw-merge-two-changelogs.md` | — | Construído em 2026-11-17: dois changelogs, só o produto recebe release |
| 0c | `done/project-docs.md` | — | Construído em 2026-11-17: `docs/`, um README curto, traduções de todo README |
| 0 | `import-from-fork.md` | — | Pendente; o primeiro depois da publicação, com release própria |
| 1 | `done/normalize-projects.md` | `plans/normalize-projects.md` | Construído na 0.1.0; teste de ponta a ponta passou em seis projetos; um segundo teste em projetos nunca vistos pendente |
| 2 | `rules.md` | `plans/rules-config.md` | Pendente |
| 3 | `normalize-rules.md` | `plans/normalize-rules.md` | Pendente; precisa de `rules` |
| 4 | `run-tools.md` | `plans/run-tools.md` | Pendente |
| 5 | `tools-hub.md` | `plans/tools-hub.md` | Pendente; precisa de `run-tools` |
| 6 | `fork-my-rules.md` | `plans/fork-my-rules.md` | Pendente; precisa de `rules` |
| 7 | `final-review.md` | — | Pendente; roda por último, numa sessão nova |
| 8 | `done/readme-get-involved-first.md` | — | Construído em 2026-11-17 dentro de `done/project-docs.md` |
| 9 | `prompt-log-results.md` | — | Pendente; rodada 1 |
| 10 | `gate-audit-gaps.md` | — | Pendente; rodada 1 |
| 11 | `work-status-docker-stacks.md` | — | Pendente; rodada 1 |
| 12 | `aiwp-remove.md` | — | Pendente; rodada 1; a primeira decisão dele é se vale construí-lo |
| 13 | `measure-quality-indicators.md` | — | Pendente; rodada 1, depois de `import-from-fork` (os dois mudam o `measure.py`) |
| 14 | `onboard.md` | `plans/distribution.md` | Pendente; rodada 2; precisa de `rules` |
| 15 | `rules-size-budget.md` | — | Pendente; rodada 3, ou incorporado ao `final-review` |
| 16 | `os-sandbox-trial.md` | — | Pendente; depois da rodada 3 |

Pedidos da mesma rodada rodam em sessões paralelas, cada uma no seu worktree (`claude --worktree <pedido>` a partir da
raiz do repositório), com merge na `main` um de cada vez:

| Rodada | Pedidos |
| --- | --- |
| 0a | `merge-versioned-changelog`, sozinho: a `developer` como base, o changelog versionado e o `/merge --main` |
| 0 | `import-from-fork`, sozinho, com release minor própria: o primeiro teste real do `aiwp update` |
| 1 | `rules`, `run-tools`, `prompt-log-results`, `gate-audit-gaps`, `work-status-docker-stacks`, `aiwp-remove`, `measure-quality-indicators` |
| 2 | `normalize-rules`, `fork-my-rules`, `tools-hub`, `onboard` |
| 3 | `final-review` (com `rules-size-budget` incorporado ou logo antes), que lança a próxima versão uma vez e testa a atualização de um workspace instalado de verdade, dedicado a isso |
| 4 | `os-sandbox-trial` |

Rode um pedido numa sessão nova aberta na raiz do repositório, uma etapa por sessão quando a etapa é grande. Um plano que
o dono aprova numa sessão é registrado na hora, em inglês e neste formato, em `done/`, com a sua linha aqui. Um pedido
entregue vai para `done/` (`git mv`, no commit que o fecha); a linha dele continua aqui com o novo caminho e o seu
Estado.
