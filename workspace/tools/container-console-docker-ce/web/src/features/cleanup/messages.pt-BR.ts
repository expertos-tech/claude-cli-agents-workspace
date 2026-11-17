import type { Translation } from '../../i18n'
import type { messages as en } from './messages.en'

/** The Brazilian Portuguese translation of messages.en.ts. */
export const messages: Translation<typeof en> = {
  nav: 'Limpeza',
  title: 'Limpeza',
  description:
    'Remove o que nenhum contêiner ativo usa: contêineres parados, imagens, redes e cache de build. Volumes guardam dados e só saem se você marcar.',
  loading: 'Calculando o que pode ser removido…',
  loadFailed: 'Não foi possível calcular o resumo. Ele é refeito quando o Docker mudar.',
  nothing: 'Nada para limpar: tudo o que existe está em uso por um contêiner ativo.',

  summaryTitle: 'Resumo',
  containers: 'Contêineres parados',
  images: 'Imagens sem contêiner ativo',
  networks: 'Redes sem contêiner ativo',
  volumes: 'Volumes sem contêiner ativo',
  buildCache: 'Cache de build',
  showList: { one: 'Ver o item', other: 'Ver os {count} itens' },
  none: 'Nenhum',

  includeVolumes: 'Remover também os volumes sem uso',
  includeVolumesHint:
    'Apaga os dados guardados neles, como bancos de projetos que estão parados. Sem marcar, os volumes ficam.',

  clean: 'Limpar',
  cleanTitle: 'Limpar o que não está em uso?',
  cleanBody:
    'São removidos com docker prune: {containers} contêineres parados, {images} imagens, {networks} redes e o cache de build ({buildCache}). Contêineres de pods do Kubernetes ficam.',
  cleanVolumes: 'Os {volumes} volumes sem uso também são apagados, com os dados deles.',
  cleanKeepsVolumes: 'Os volumes ficam.',
  cleanRace: 'A limpeza age sobre o estado do Docker na hora: um contêiner parado depois deste resumo também sai.',
  running: 'Limpeza em andamento. O resumo é refeito ao terminar.',
}
