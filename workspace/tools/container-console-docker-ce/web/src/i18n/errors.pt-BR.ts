import type { messages as en } from './errors.en'
import type { Translation } from './index'

/** The Brazilian Portuguese translation of errors.en.ts. */
export const messages: Translation<typeof en> = {
  forbidden: 'O serviço recusou o pedido por segurança. O motivo está no log do serviço.',
  route_not_found: 'O serviço não conhece esta rota.',
  topic_not_found: 'O serviço não conhece este tópico ao vivo.',
  job_not_found: 'O serviço não conhece esta ação. Ele perde o histórico ao reiniciar.',
  container_not_found: 'O contêiner não existe mais.',
  volume_not_found: 'O volume não existe mais.',
  network_not_found: 'A rede não existe mais.',
  kubernetes_resource_not_found: 'O recurso do Kubernetes não existe mais.',
  kubernetes_kind_unknown: 'O serviço não conhece este tipo de recurso do Kubernetes.',
  compose_project_not_found: 'O projeto Compose não está na lista de projetos conhecidos.',
  environment_not_on: 'O Docker precisa estar ligado para esta ação.',
  kubernetes_unavailable: 'Nenhum cluster Kubernetes responde. O erro recebido está abaixo.',
  file_picker_busy: 'O diálogo de arquivo já está aberto. Escolha o arquivo ou cancele nele.',
  compose_files_unknown: 'O serviço não conhece os arquivos deste projeto Compose. Adicione o arquivo de novo.',
  body_too_large: 'O conteúdo enviado passa de 1 MiB.',
  invalid_body: 'O serviço não aceitou os dados enviados.',
  confirmation_required: 'Esta ação exige confirmação, e nada foi executado.',
  invalid_docker_name:
    'O nome precisa começar com letra ou número e ter só letras, números, ponto, hífen ou sublinhado.',
  invalid_image_reference: 'A referência de imagem não tem um formato válido.',
  invalid_compose_project: 'O nome do projeto Compose não tem um formato válido.',
  compose_path_invalid:
    'O caminho precisa ser absoluto, sem `..`, terminar em .yaml ou .yml e apontar para um arquivo dentro da sua pasta pessoal.',
  compose_file_invalid: 'O Compose recusou este arquivo.',
  invalid_kubernetes_name: 'O nome não é um nome válido do Kubernetes.',
  replicas_required: 'Informe o número de réplicas.',
  replicas_out_of_range: 'O número de réplicas precisa estar entre 0 e {max}.',
  yaml_empty: 'O YAML está vazio.',
  command_failed: 'O comando falhou.',
  command_timeout: 'O comando passou do prazo e foi encerrado.',
  binary_not_found: 'O programa necessário não foi encontrado nesta máquina.',
  action_failed: 'A ação falhou.',
  too_many_terminals:
    'O limite de {max} terminais abertos ao mesmo tempo foi atingido. Feche um deles e conecte de novo.',
  invalid_terminal_frame: 'O terminal enviou um quadro que o serviço não aceita.',
  invalid_terminal_size: 'O tamanho do terminal está fora do limite aceito.',
  network_error: 'Não foi possível falar com o serviço. Confira se ele está no ar.',
  request_timeout: 'O serviço não respondeu no prazo.',
  unexpected_response: 'O serviço devolveu uma resposta inesperada.',
}
