<!-- source: workspace/migrations/README.md sha256:5752e6a9703407f247e212529cb5397a20499152c80405982923b777f7ac95b6 -->

# migrations

O que cada versão do workspace pede dos projetos e das POCs. Um arquivo por versão que pede algo:
`<x.y.z>.md`, com o nome da versão que o introduziu. Uma versão que não pede nada dos projetos não tem arquivo.

## Como os arquivos são usados

- Todo projeto de `projects/` e toda POC de `custom/pocs/` leva um marcador na linha 1 do `README.md`:
  `<!-- AI-WORKSPACE-PROJECT x.y.z -->`, a versão do workspace da última normalização. Para um projeto, o
  marcador que vale é o commitado na `developer`.
- Um projeto está desatualizado só quando um arquivo daqui tem uma versão acima do marcador dele e até o `VERSION` do
  workspace. Um projeto marcado `0.1.0` num workspace na `0.3.0` cujo último arquivo daqui é `0.1.0.md` está em dia:
  um release que não pede nada dos projetos nunca avisa.
- `bash scripts/aiwp-project-state.sh` imprime o estado de cada projeto; o hook `UserPromptSubmit`, o `aiwp-cmds.sh
  open` e o gate o mostram, e o `/normalize-projects` aplica os arquivos pendentes em ordem e depois escreve o marcador
  da versão atual.

## Como um arquivo é escrito

- Título `# <x.y.z>`, depois o que um projeto marcado com uma versão anterior deve mudar, como passos que o
  `/normalize-projects` pode aplicar: o que procurar (descrito pelo que faz, nunca por uma lista fixa de nomes de
  arquivo), para onde vai e como conferir o resultado.
- Um arquivo nunca muda depois do release dele: uma correção posterior é um arquivo novo para uma versão posterior.

| Versão | Pede |
| --- | --- |
| [0.1.0](../../../../workspace/migrations/0.1.0.md) | A primeira normalização: a análise, a camada custom, a documentação, o relatório e o marcador |
