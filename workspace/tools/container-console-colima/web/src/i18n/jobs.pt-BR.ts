import type { Translation } from './index'
import type { messages as en } from './jobs.en'

/** The Brazilian Portuguese translation of jobs.en.ts. */
export const messages: Translation<typeof en> = {
  'environment.start': 'Ligar o ambiente',
  'environment.stop': 'Desligar o ambiente',
  'environment.resources': 'Aplicar CPU, memória e disco no ambiente',
  'kubernetes.start': 'Ligar o Kubernetes',
  'kubernetes.stop': 'Desligar o Kubernetes',
  'container.start': 'Iniciar o contêiner {target}',
  'container.stop': 'Parar o contêiner {target}',
  'container.restart': 'Reiniciar o contêiner {target}',
  'container.remove': 'Remover o contêiner {target}',
  'image.pull': 'Baixar a imagem {target}',
  'image.remove': 'Remover a imagem {target}',
  'volume.create': 'Criar o volume {target}',
  'volume.remove': 'Remover o volume {target}',
  'network.create': 'Criar a rede {target}',
  'network.remove': 'Remover a rede {target}',
  'compose.add': 'Adicionar o arquivo Compose {target}',
  'compose.pick': 'Abrir o diálogo de arquivo do Mac',
  'compose.up': 'Subir o projeto Compose {target}',
  'compose.stop': 'Parar o projeto Compose {target}',
  'compose.remove': 'Remover o projeto Compose {target}',
  'kubernetes.remove': 'Remover o recurso {target}',
  'kubernetes.scale': 'Escalar o deployment {target}',
  'kubernetes.apply': 'Aplicar YAML no Kubernetes',
}
