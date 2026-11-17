import type { Translation } from '../../i18n'
import type { messages as en } from './messages.en'

/** The Brazilian Portuguese translation of messages.en.ts. */
export const messages: Translation<typeof en> = {
  nav: 'Ambiente',
  title: 'Ambiente',
  description:
    'O estado e os dados do daemon do Docker nesta máquina. Esta tela só mostra: quem liga e desliga o Docker é o sistema.',

  statusTitle: 'Daemon do Docker',
  version: 'Versão',
  cpus: 'CPUs',
  memory: 'Memória',
  memoryValue: '{value} GiB',
  driver: 'Driver de armazenamento',
  system: 'Sistema operacional',
  architecture: 'Arquitetura',

  stateOff:
    'O Docker está desligado. O console não liga o Docker, porque isso exige privilégio de administrador. Para ligar, rode este comando em um terminal:',
  startCommand: 'sudo systemctl start docker',
  stateUnknown: 'Não foi possível saber o estado do Docker. O motivo recebido está abaixo.',

  unavailableTitle: 'O que fica indisponível com o Docker desligado',
  unavailableDocker: 'Contêineres, imagens, volumes e redes.',
  unavailableCompose: 'Subir, parar e remover projetos Compose. A lista e a escolha de arquivo continuam funcionando.',
  kubernetesNote:
    'O Kubernetes não depende desta tela: a tela de Kubernetes mostra se há um cluster acessível no contexto do kubeconfig.',
}
