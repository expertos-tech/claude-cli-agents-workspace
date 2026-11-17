import type { Translation } from '../../i18n'
import type { messages as en } from './messages.en'

/** The Brazilian Portuguese translation of messages.en.ts. */
export const messages: Translation<typeof en> = {
  nav: 'Imagens',
  eyebrow: 'Docker',
  title: 'Imagens',
  description: 'As linhas de progresso do download aparecem no painel de ações, abaixo da tela.',
  pullTitle: 'Baixar imagem',
  referenceLabel: 'Referência da imagem',
  referenceHint: 'Exemplo: alpine:3.20',
  referenceInvalid:
    'A referência precisa começar com letra ou número e ter só letras, números e os sinais . _ : / @ -, até 512 caracteres.',
  pull: 'Baixar',
  caption: { one: '{count} imagem', other: '{count} imagens' },
  empty: 'Nenhuma imagem existe agora.',
  columnReference: 'Referência',
  columnId: 'Id',
  columnSize: 'Tamanho',
  columnCreated: 'Criada em',
  remove: 'Remover',
  removeAria: 'Remover a imagem {reference}',
  removeTitle: 'Remover a imagem {reference}?',
  removeBody:
    'A remoção não usa força: se a imagem estiver em uso, ela continua aqui e o erro do Docker aparece no painel de ações.',
}
