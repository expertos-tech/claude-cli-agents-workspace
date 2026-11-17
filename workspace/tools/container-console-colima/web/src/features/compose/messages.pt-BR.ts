import type { Translation } from '../../i18n'
import type { messages as en } from './messages.en'

/** The Brazilian Portuguese translation of messages.en.ts. */
export const messages: Translation<typeof en> = {
  nav: 'Compose',
  eyebrow: 'Docker',
  title: 'Projetos Compose',
  description:
    'Os projetos conhecidos e os arquivos que você escolheu. Eles continuam na lista mesmo com o ambiente desligado.',

  addTitle: 'Adicionar projeto',
  addDescription:
    'Escolha um arquivo .yaml ou .yml dentro da sua pasta pessoal. O nome do projeto vem do próprio Compose.',
  chooseFile: 'Escolher arquivo no Mac',
  choosing: 'Esperando o diálogo do Mac',
  choosingHint: 'O diálogo de arquivo abre no Mac, às vezes atrás do navegador. Ele fica aberto por até 5 minutos.',
  pathLabel: 'Caminho do arquivo',
  pathHint: 'Use este campo se o diálogo não abrir. O caminho precisa ser absoluto.',
  pathInvalid: 'O caminho precisa ser absoluto, sem `..`, e terminar em .yaml ou .yml.',
  add: 'Adicionar',
  added: 'O projeto {name} foi adicionado à lista.',

  caption: { one: '{count} projeto', other: '{count} projetos' },
  empty: 'Nenhum projeto conhecido. Adicione um arquivo acima.',
  columnName: 'Projeto',
  columnState: 'Estado',
  columnStatus: 'Situação',
  columnFiles: 'Arquivos',
  noFiles: 'Nenhum arquivo conhecido',

  'state.running': 'Rodando',
  'state.exited': 'Parado',
  'state.down': 'Sem contêineres',
  'state.unknown': 'Desconhecido',

  up: 'Subir',
  stop: 'Parar',
  remove: 'Remover',
  upAria: 'Subir o projeto {name}',
  stopAria: 'Parar o projeto {name}',
  removeAria: 'Remover o projeto {name}',
  removeTitle: 'Remover o projeto {name}?',
  removeBody:
    'Roda docker compose down: os contêineres e as redes do projeto são removidos, e ele sai da lista. Os volumes são mantidos, a menos que você marque a opção abaixo.',
  removeVolumes: 'Remover também os volumes do projeto, o que apaga os dados deles',
}
