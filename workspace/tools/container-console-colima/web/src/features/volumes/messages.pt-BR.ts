import type { Translation } from '../../i18n'
import type { messages as en } from './messages.en'

/** The Brazilian Portuguese translation of messages.en.ts. */
export const messages: Translation<typeof en> = {
  nav: 'Volumes',
  eyebrow: 'Docker',
  title: 'Volumes',
  description: 'Volumes guardam os dados dos contêineres fora deles.',
  caption: { one: '{count} volume', other: '{count} volumes' },
  empty: 'Nenhum volume existe agora.',
  createTitle: 'Criar volume',
  nameLabel: 'Nome do volume',
  nameHint: 'Letras, números, ponto, hífen e sublinhado, começando com letra ou número.',
  nameInvalid:
    'O nome precisa começar com letra ou número e ter só letras, números, ponto, hífen ou sublinhado, até 255 caracteres.',
  create: 'Criar',
  remove: 'Remover',
  removeAria: 'Remover o volume {name}',
  removeTitle: 'Remover o volume {name}?',
  removeBody:
    'Os dados do volume {name} são apagados. A remoção não usa força: se ele estiver em uso, continua aqui e o erro do Docker aparece no painel de ações.',
  detailsBack: 'Voltar para a lista',
  detailsMissing: 'Este volume não aparece mais na lista. Ele pode ter sido removido.',
  columnName: 'Nome',
  columnDriver: 'Driver',
  columnScope: 'Escopo',
  columnMountpoint: 'Caminho na VM',
  columnProject: 'Projeto Compose',
  noProject: 'Nenhum',
}
