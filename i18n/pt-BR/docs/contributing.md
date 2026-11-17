<!-- source: docs/contributing.md sha256:bba3576d4af8b0194938380fd8e00c83f76eb68f84a4fa8f37fc7d094b205b2f -->

# Contribuindo

[English](../../../docs/contributing.md) · Português (Brasil) · [Español](../../es/docs/contributing.md)

Este workspace nasceu do uso diário: de errar, medir e simplificar. Ele fica melhor a cada pessoa que o usa num projeto
de verdade.

Encontrou um jeito melhor de fazer algo? Corrigiu um defeito? Escreveu um hook que poupa perguntas, uma regra mais
clara, uma ferramenta útil? **Compartilhe.** Faça um fork do repositório, faça a sua mudança e mande um pull request.

## Como enviar uma mudança

1. **Bug ou ideia:** abra uma issue com o que aconteceu, o que você esperava e como reproduzir.
2. **Fork** do repositório e uma branch a partir de `developer`, a branch padrão, com o nome
   `<type>/<kebab-description>` (por exemplo `fix/session-title-prefix`).
3. **Mudança:** pequena e focada, com um commit por mudança lógica em Conventional Commits
   (`type(scope): subject`, em inglês).
4. **Antes de enviar:** `bash tests/check.sh --all` passando. Ele roda o lint, a varredura de segredos, as suítes dos
   scripts e o check que mantém dado de empresa fora do repositório.
5. **Pull request** para `developer`, dizendo o porquê, e não só o quê.

## O que ter em mente

- **Traduções:** uma mudança num documento em inglês atualiza as traduções dele em `i18n/pt-BR/` e `i18n/es/` no mesmo
  commit ([traduções](translations.md)).
- **O que é seu fica com você:** empresa, projetos, identidade visual e pedidos ficam na sua camada custom, nunca no
  pull request.
- **Regra nova:** prefira um hook ou um script testado a mais texto, e diga o que a mudança acrescenta ou tira de toda
  sessão (um passo, uma pergunta, texto carregado).
- **Mantenha a partir da raiz do repositório:** clone este repositório e abra o `claude` na raiz dele. O `CLAUDE.md` e
  a `.claude/` da raiz dão a essa sessão o processo de manutenção (plano, pedido, etapas, testes, revisão) e deixam as
  regras do produto fora dela, porque ali elas são o código sendo editado. A [manutenção](maintenance.md) explica.
