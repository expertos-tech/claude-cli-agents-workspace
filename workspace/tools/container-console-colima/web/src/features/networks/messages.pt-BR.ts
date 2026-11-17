import type { Translation } from '../../i18n'
import type { messages as en } from './messages.en'

/** The Brazilian Portuguese translation of messages.en.ts. */
export const messages: Translation<typeof en> = {
  nav: 'Redes',
  eyebrow: 'Docker',
  title: 'Redes',
  description: 'Redes ligam contêineres entre si. As redes padrão do Docker também aparecem aqui.',
  caption: { one: '{count} rede', other: '{count} redes' },
  empty: 'Nenhuma rede existe agora.',
  createTitle: 'Criar rede',
  nameLabel: 'Nome da rede',
  nameHint: 'Letras, números, ponto, hífen e sublinhado, começando com letra ou número.',
  nameInvalid:
    'O nome precisa começar com letra ou número e ter só letras, números, ponto, hífen ou sublinhado, até 255 caracteres.',
  create: 'Criar',
  remove: 'Remover',
  removeAria: 'Remover a rede {name}',
  removeTitle: 'Remover a rede {name}?',
  removeBody:
    'A rede {name} é apagada. A remoção não usa força: se ela estiver em uso, continua aqui e o erro do Docker aparece no painel de ações.',
  detailsBack: 'Voltar para a lista',
  detailsMissing: 'Esta rede não aparece mais na lista. Ela pode ter sido removida.',
  columnName: 'Nome',
  columnId: 'Id',
  columnDriver: 'Driver',
  columnScope: 'Escopo',
  columnInternal: 'Interna',
  columnCreated: 'Criada em',
  columnProject: 'Projeto Compose',
  internalYes: 'Sim',
  internalNo: 'Não',
  noProject: 'Nenhum',
}
