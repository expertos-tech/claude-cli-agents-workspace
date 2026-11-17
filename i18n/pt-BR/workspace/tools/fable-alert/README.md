<!-- source: workspace/tools/fable-alert/README.md sha256:9b9df9f7c36b476ec400a37a35d89418679b8e9ff76abd3d1958183fd584d1bc -->

# fable-alert

Alerta visual para o Claude Code: com o Fable ativo, o fundo do terminal fica vermelho-escuro e aparece uma faixa "FABLE ACTIVE" acima do prompt. Inclui também a barra de status que mostra o modelo, o trecho de configuração e o `ptyrun.py`, que grava o que o Claude Code desenha ao abrir.

- [O que é](#o-que-é)
- [Como funciona](#como-funciona)
- [Estrutura](#estrutura)
- [Como instalar](#como-instalar)
- [Como rodar](#como-rodar)
- [Como testar](#como-testar)
- [Critérios de aceitação](#critérios-de-aceitação)
- [Personalização](#personalização)
- [Desinstalação](#desinstalação)
- [Limitações](#limitações)
- [Notas de design](#notas-de-design)

## O que é

Um mod do Claude Code (pasta `plugin/`) mais três peças de apoio. O mod existe porque o `/model` salva o modelo escolhido como padrão de todas as sessões novas. Depois de um `/model fable`, todas as sessões seguintes podem abrir no Fable sem aviso na tela, e a cota semanal dele acaba em poucos dias.

Não há instalação por marketplace.

## Como funciona

Código em `plugin/hooks/register.tsx`.

1. Dois segundos depois de a sessão abrir (`FIRST_CHECK_MS`), o mod passa a perguntar o modelo ativo a cada segundo.
2. Se o nome do modelo contém `fable` (maiúsculas ou minúsculas), escreve no terminal a sequência OSC 11, que troca o fundo para `#420c0c`, e só depois grava o átomo `isFable`, que desenha a faixa. A faixa muda o layout e força o prompt a se redesenhar por cima de qualquer coisa que a escrita tenha perturbado.
3. Quando o modelo deixa de ser o Fable, escreve a OSC 111, que devolve o fundo do próprio terminal, e esconde a faixa. Fora do Fable, o mod só escreve para desfazer uma cor que ainda está registrada.
4. O átomo `isFable`, guardado pelo host, é o único registro de "fundo pintado": a faixa e a cor saem dele e nunca se separam, e ele sobrevive a um recarregamento do mod.
5. Ao sair da sessão com o Fable ativo, devolve o fundo antes de fechar. Num `/clear` ou num `/resume` o processo continua, com outro id de sessão e sem um novo `session.start`: o mod devolve o fundo, segue vigiando e pinta de novo no próximo ciclo se o modelo ainda for o Fable. Se a sessão terminar enquanto a cor está sendo escrita, o mod desfaz a escrita, desde que o processo ainda esteja vivo quando ela acabar.
6. A faixa não aparece enquanto uma pesquisa (survey) ocupa o espaço acima do prompt.

O comando que escreve a cor roda num processo filho sem terminal próprio. Por isso o script sobe até 8 ancestrais, procura o primeiro com terminal (`ps -o tty=`) e escreve a sequência direto em `/dev/<tty>`.

A barra de status (`statusline/statusline.sh`) mostra o modelo e a pasta da sessão, com `~` no lugar da pasta home. Modelo cujo nome ou id contém `Fable` ou `fable` aparece em branco sobre vermelho; os outros, em ciano. Precisa de `bash` e `jq`.

## Estrutura

| Caminho | O que é |
| --- | --- |
| `plugin/` | O mod: `.claude-plugin/plugin.json`, `hooks/register.tsx`, `types/index.d.ts` e `tests/fable-alert.test.tsx` |
| `statusline/statusline.sh` | Barra de status com o modelo ativo |
| `settings-snippet.json` | Trechos do `~/.claude/settings.json`: `statusLine` e `env.CLAUDE_CODE_PLUGIN_DIRS` |
| `tools/ptyrun.py` | Abre o Claude Code num terminal falso, grava o que ele desenha e relata as escritas de cor de fundo |
| `tests/` | Testes em Python do `ptyrun.py`, do script de terminal e da barra de status |
| `.coveragerc` | Alvo da verificação `coverage` do `scripts/validate.sh` |

## Como instalar

Requer Claude Code 2.1.309 ou mais novo, o mínimo para mods; os testes daqui rodaram na 2.1.314.

Execute na raiz do workspace. O que roda é a cópia instalada: mudar a ferramenta não tem efeito até copiá-la de novo. Instalado por pasta, o mod entra numa sessão quando ela abre e, depois disso, a sessão o recarrega sozinha quando um arquivo da cópia instalada muda.

```bash
mkdir -p ~/.claude/mods/fable-alert && cp -R tools/fable-alert/plugin/. ~/.claude/mods/fable-alert/
```

Barra de status (precisa de `jq`):

```bash
cp tools/fable-alert/statusline/statusline.sh ~/.claude/statusline.sh
chmod +x ~/.claude/statusline.sh
```

Configurações. O comando faz backup e junta o trecho às configurações atuais, sem apagar o que existe; se `env.CLAUDE_CODE_PLUGIN_DIRS` já tiver valor, o do trecho o substitui.

```bash
cp ~/.claude/settings.json ~/.claude/settings.json.bak
jq -s '.[0] * .[1]' ~/.claude/settings.json.bak tools/fable-alert/settings-snippet.json > ~/.claude/settings.json
```

O mod entra nas sessões abertas depois dessa configuração.

## Como rodar

Não há o que rodar: com o mod instalado, ele age em toda sessão nova. Para ver o que o Claude Code desenha ao abrir, use o `ptyrun.py` numa pasta fora do workspace (veja o aviso em [Como testar](#como-testar)):

```bash
python3 -I <workspace-root>/tools/fable-alert/tools/ptyrun.py open-default.bin 6
python3 -I <workspace-root>/tools/fable-alert/tools/ptyrun.py open-fable.bin 7 --model fable
```

O primeiro argumento é o arquivo de saída; o segundo, os segundos de gravação; o resto vai para o `claude`. O terminal falso tem 120 x 40, e a sessão termina com `SIGTERM`. O relatório lista cada escrita de cor de fundo (`set (OSC 11)` ou `reset (OSC 111)`) e marca `SPLITS A CHARACTER` se alguma cortou um caractere UTF-8 ao meio, que é o que quebra uma linha. Abrir o Claude sem mandar mensagem não faz requisição ao modelo.

## Como testar

Testes automáticos, da raiz do workspace. O `claude plugin validate` e o `claude plugin test` gravam `tsconfig.json` e `.claude-plugin/types/` dentro da pasta do plugin, que é só leitura num workspace instalado, então rodam numa cópia em `tmp/`:

```bash
rm -rf tmp/fable-alert-plugin && cp -R tools/fable-alert/plugin tmp/fable-alert-plugin && chmod -R u+w tmp/fable-alert-plugin
claude plugin validate tmp/fable-alert-plugin
claude plugin test tmp/fable-alert-plugin
(cd tools/fable-alert && python3 -I -B -m unittest discover -s tests)
bash scripts/validate.sh --path tools/fable-alert
```

- `claude plugin test` roda os 37 testes de `plugin/tests/fable-alert.test.tsx`.
- Os testes em Python cobrem o `ptyrun.py` (com um `claude` falso), o script que sobe a árvore de processos (com um `ps` falso) e a barra de status. Os 6 testes da barra (AC-11) precisam de `bash` e `jq`: no contêiner da verificação `coverage` eles são pulados, e rodam no host.
- Os testes são opcionais: ferramenta só precisa compilar, e `scripts/validate.sh` não mede cobertura nesta pasta.

**Cobertura do mod.** O `claude plugin test` não tem opção de cobertura, então o 85% de `rules/quality.md` não é medido no mod. No lugar, o cabeçalho de `plugin/tests/fable-alert.test.tsx` mapeia cada branch de `register.tsx` a um teste, e uma verificação por mutação pegou 22 de 22 inversões de branch e 13 de 13 mutantes extras, sem guarda sobrevivente. É uma lacuna aceita, por ser uma ferramenta local. O `ptyrun.py` tem 98,9% de cobertura de linhas e 95,4% de branches.

**Cobertura da barra de status.** A verificação `coverage` não mede bash, e os 6 testes AC-11 são pulados no contêiner dela. Uma regressão na barra de status não derruba o `validate.sh`: rode o comando no host (`python3 -I -B -m unittest discover -s tests`). Também é uma lacuna aceita.

**Verificação no motor real** (Claude Code 2.1.314, abrindo sem prompt): uma cópia temporária do mod, com a expressão regular trocada para reagir ao Opus, sem Fable no caminho, deu exatamente 1 escrita OSC 11 em cerca de 8 segundos de observação, 1 OSC 111 na saída, nenhum caractere cortado e a faixa presente. Limites: a troca de modelo no meio da sessão e o `/resume` só foram provados pelos testes, não no motor real.

**Teste visual**, fora do workspace:

1. Abra o `claude` numa pasta fora do workspace. Dentro dele, `rules/agents/settings.json` define `availableModels` sem o Fable.
2. Sem mandar mensagem, rode `/model fable`: o fundo fica vermelho-escuro e a faixa aparece em até um segundo.
3. Volte ao modelo que era o seu padrão antes, que não é necessariamente o Opus, com `/model <model>`. O `/model` salva a escolha como padrão das sessões novas: esquecer este passo deixa toda sessão nova no Fable.

## Critérios de aceitação

Os ids aparecem nos nomes dos testes.

| Id | Critério |
| --- | --- |
| AC-1 | Modelo com `fable` no nome, em qualquer caixa: a cor é escrita uma vez e a faixa aparece |
| AC-2 | Outro modelo: nada é escrito e a faixa não aparece |
| AC-3 | Trocar entre Fable e outro modelo muda a cor e a faixa em até um segundo, inclusive uma faixa já desenhada |
| AC-4 | Sair da sessão para a vigilância; no Fable devolve a cor, em outro modelo não escreve nada; um ciclo em andamento não faz nada |
| AC-5 | `/clear` devolve a cor, continua vigiando e pinta de novo se o modelo ainda for o Fable |
| AC-6 | Nada é lido nem escrito antes de `FIRST_CHECK_MS` |
| AC-7 | Falha ao ler o modelo, escrever a cor ou devolvê-la (na saída ou no `/clear`) não derruba a sessão; o ciclo seguinte tenta de novo, exceto o reset que falhou |
| AC-8 | Uma pesquisa (survey) esconde a faixa, mesmo no Fable |
| AC-9 | Corridas: ciclos sobrepostos não escrevem duas vezes; fim da sessão durante a leitura do modelo, a escrita da cor ou a escrita do reset não deixa a cor errada; desfazer que falha fica contido |
| AC-10 | Script de terminal: sobe até 8 ancestrais, pula `??` e terminal vazio, para no pid 1 ou sem pai, tenta o próximo se a escrita falhar; sai com 0 ao escrever e 1 sem terminal |
| AC-11 | Barra de status: realce do Fable (`Fable` ou `fable` no nome ou no id), ciano nos outros, `~` no lugar da pasta home, campos ausentes com valor de reserva, JSON inválido sai com erro e sem saída |
| AC-12 | `ptyrun.py` grava o que o `claude` desenha, repassa os argumentos, encerra com `SIGTERM`, responde às consultas do terminal e relata cada escrita de cor de fundo |
| AC-13 | `splits_utf8` aponta a escrita que cai no meio de um caractere UTF-8 |
| AC-14 | `ptyrun.py` com argumentos ou ambiente inválidos (tempo, `claude` fora do `PATH`, pasta de saída ausente ou sem permissão) sai com mensagem, sem traceback e sem travar |
| AC-15 | `/resume` mantém a vigilância, como o `/clear` |
| AC-16 | O átomo é o único registro de cor pintada: faixa e cor não se separam após `/clear`, fim de sessão, desfazer no meio da escrita, ciclo e fim ao mesmo tempo ou estado deixado por um recarregamento; no Fable, o host apagar o estado só faz o mod pintar de novo |
| AC-17 | Escrita cujo processo sai com código diferente de 0 (sem terminal): a faixa aparece e a escrita não se repete a cada segundo |
| AC-18 | Falha ao ler o estado no fim da sessão conta como cor pintada: o mod tenta devolver a cor, e a saída continua |

## Personalização

No começo de `plugin/hooks/register.tsx`: `TINT` (cor de fundo) e `FIRST_CHECK_MS` (espera antes da primeira checagem). O texto da faixa fica no fim do arquivo. Os testes têm esses valores escritos à mão: ao mudar `TINT` ou `FIRST_CHECK_MS`, mude também `SET_TINT` e `FIRST_CHECK_MS` em `plugin/tests/fable-alert.test.tsx`; ao mudar o título "FABLE ACTIVE", mude o que o teste procura. Depois rode os testes e copie o mod de novo para `~/.claude/mods/fable-alert/`.

## Desinstalação

```bash
cp ~/.claude/settings.json ~/.claude/settings.json.bak
jq 'del(.env.CLAUDE_CODE_PLUGIN_DIRS, .statusLine)' ~/.claude/settings.json.bak > ~/.claude/settings.json
rm -r ~/.claude/mods/fable-alert ~/.claude/statusline.sh
```

Se um travamento deixar o terminal com o fundo vermelho:

```bash
printf '\033]111\007'
```

## Limitações

- A API de mods do Claude Code está em acesso antecipado e pode mudar entre versões.
- O terminal precisa aceitar OSC 11 e OSC 111. Testado no Ghostty 1.3.1.
- Sem terminal encontrado nos 8 ancestrais, o fundo não muda, a faixa aparece mesmo assim e a escrita não é repetida (AC-17).
- Um reset da cor que falha, na saída, num `/clear` ou num `/resume`, não é repetido: o fundo vermelho pode ficar até o comando de recuperação acima (AC-7).
- Se o processo fechar logo depois de uma escrita em andamento, a cor pode ficar até o mesmo comando. A janela é curta, e o AC-9 só prova o caso com o processo vivo. O fim da sessão não espera essa escrita de propósito: uma chamada travada não pode segurar a saída do Claude.
- Se o host apagar o estado com a cor pintada e o modelo já não for o Fable, o mod não sabe que pintou, e a cor fica até o mesmo comando.
- O script de terminal usa `ps -o tty=`, disponível no macOS e em outros sistemas Unix.
- A barra de status fica fora da cobertura automática do `validate.sh` (veja [Como testar](#como-testar)).
- Os arquivos `.bin` do `ptyrun.py` guardam tudo o que foi desenhado na tela. O `.gitignore` desta pasta os ignora; não os compartilhe.

## Notas de design

- **Nenhuma escrita ao abrir a sessão.** Escrever no terminal enquanto a sessão desenha a primeira tela pode cair no meio de uma linha do prompt e cortar um caractere ao meio. Por isso, fora do Fable, o mod só escreve para desfazer uma cor que ainda está registrada, espera o desenho inicial terminar e redesenha o prompt depois de cada escrita. O `ptyrun.py` confirma isso nas aberturas com o Opus e com o Fable.
- **O timer para no fim da sessão**, exceto num `/clear` ou `/resume`, e uma escrita em andamento no fim é desfeita, então sair com o Fable ativo não deixa o terminal vermelho.
- **O `/resume` mantém o alerta vivo**: o fim da sessão não para os timers num `/clear` ou `/resume`, já que nenhuma sessão nova os reinicia.
- **Um registro só para faixa e cor.** O estado da cor fica só no átomo do host, nunca numa variável do mod, então a faixa e a cor não podem divergir.
