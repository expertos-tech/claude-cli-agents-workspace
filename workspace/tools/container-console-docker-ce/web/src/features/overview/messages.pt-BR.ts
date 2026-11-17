import type { Translation } from '../../i18n'
import type { messages as en } from './messages.en'

/** The Brazilian Portuguese translation of messages.en.ts. */
export const messages: Translation<typeof en> = {
  nav: 'Visão geral',
  title: 'Visão geral',
  description: 'O estado do Docker e o que existe agora.',
  environmentTitle: 'Docker',
  version: 'Versão',
  cpus: 'CPUs',
  memory: 'Memória',
  memoryValue: '{value} GiB',
  off: 'O Docker está desligado, e as ações de Docker ficam indisponíveis até ele ser ligado. A tela de ambiente mostra como ligar.',
  unknown: 'Não foi possível saber o estado do Docker. O motivo recebido está abaixo.',
  details: 'Ver o ambiente',
  resourcesTitle: 'Recursos',
  containers: 'Contêineres',
  containersValue: {
    one: '{running} rodando, de {count} contêiner',
    other: '{running} rodando, de {count} contêineres',
  },
  images: 'Imagens',
  volumes: 'Volumes',
  networks: 'Redes',
  compose: 'Projetos Compose',
  namespaces: 'Namespaces',
  pods: 'Pods',
  deployments: 'Deployments',
  services: 'Services',
  unavailable: 'Indisponível',
  loading: 'Lendo o estado atual.',
}
