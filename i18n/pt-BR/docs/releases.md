<!-- source: docs/releases.md sha256:9b00ec33fe4f4ce46809f5cd7bef650cd134c92017aa6f99dc58827e95563322 -->

# Releases

[English](../../../docs/releases.md) · Português (Brasil) · [Español](../../es/docs/releases.md)

Só o produto recebe release. A manutenção do repositório é registrada, mas nunca lançada sozinha.

## Branches

- `developer` é a branch padrão: toda mudança entra nela, pelo `/caw-merge`.
- `main` só se move por uma release do produto.

## Os dois changelogs

| Arquivo | O que registra |
| --- | --- |
| `CHANGELOG.md` (raiz) | O repositório: toda mudança. Uma mudança de manutenção (`CLAUDE.md`, `.claude/`, `tests/`, `maintainers/`, `i18n/`, `docs/`, o `README.md` da raiz) em detalhe; uma mudança do produto como uma linha de resumo em `### Product` |
| `workspace/CHANGELOG.md` | O produto: só uma mudança em `workspace/` ou `install.sh`, em detalhe, para quem usa o workspace |

Ambos seguem o [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) e o [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

- Uma versão em andamento é `## [X.Y.Z] - Unreleased`.
- O bump segue os tipos de Conventional Commit do que entra em cada changelog.
- A correção de algo que entrou na mesma versão ainda não lançada não é uma correção: não cria entrada em `### Fixed`
  nem bump. A entrada original só é ajustada quando o comportamento que ela descreve mudou.
- As versões do changelog da raiz nunca são lançadas sozinhas: uma seção recebe a data da release do produto que a
  entrega, e aponta para ela.
- Mudanças de manutenção sozinhas nunca são lançadas: sem uma versão `Unreleased` em `workspace/CHANGELOG.md`, não há
  nada a lançar.

## Lançar o produto

`/caw-merge --main`, só quando o dono pede. A versão é a `Unreleased` do `workspace/CHANGELOG.md`.

1. Um clone de release `tmp/work/<yyyy-mm-dd>-release-vX-Y-Z/` na branch `fix/release-vX-Y-Z`.
2. Uma verificação completa em contexto limpo: a suíte desde a última tag, a instalação de teste e uma revisão do
   intervalo.
3. Correções do que ela achar, como commits no clone.
4. `workspace/VERSION` para `X.Y.Z`, a seção do produto com data, a seção da raiz com data e ligada à release, as
   traduções dos documentos alterados e o commit `chore(release): X.Y.Z`.
5. O clone entra na `developer` como em qualquer merge.
6. Cada passo público é confirmado pelo dono, um a um: a `main` (um fast-forward a partir da `developer`, ou um pull
   request quando recusado), a tag `vX.Y.Z` (nunca movida nem apagada) e a release no GitHub, com a seção do changelog
   do produto como notas.
7. Uma conferência de que uma instalação nova pega a tag nova.

Um passo público recusado ou que falha interrompe a release ali. Nada é forçado.

## Instaladores e tags

O instalador e o `aiwp` só pegam tags `vX.Y.Z`, nunca uma branch: um workspace roda uma versão lançada
([como funcionam as atualizações](commands-and-updates.md)).
