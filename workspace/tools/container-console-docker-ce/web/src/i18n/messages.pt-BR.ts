import type { Translation } from './index'
import type { messages as en } from './messages.en'

/** The Brazilian Portuguese translation of messages.en.ts. */
export const messages: Translation<typeof en> = {
  'app.name': 'Container Console · Docker CE',
  'app.project': 'Claude CLI Agents Workspace',
  'app.skipToContent': 'Ir para o conteúdo',
  'app.documentTitle': '{page} · Container Console · Docker CE',
  'app.crashTitle': 'A tela encontrou um erro inesperado',
  'app.crashBody': 'Recarregue a página. O Docker e os contêineres não foram afetados por este erro.',
  'app.notFoundTitle': 'Página não encontrada',
  'app.notFoundBody': 'Este endereço não corresponde a nenhuma tela do console.',

  'nav.label': 'Menu principal',
  'nav.open': 'Abrir o menu',
  'nav.close': 'Fechar o menu',
  'nav.group.main': 'Início',
  'nav.group.docker': 'Docker',
  'nav.group.cluster': 'Cluster',
  'nav.motion': 'Animar mudanças nos dados',
  'nav.theme': 'Tema',
  'nav.theme.system': 'Seguir o sistema',
  'nav.theme.dark': 'Escuro',
  'nav.theme.light': 'Claro',

  'live.lost':
    'A conexão ao vivo com o serviço caiu. Tentando reconectar; os dados na tela podem estar desatualizados.',

  'environment.label': 'Estado do Docker: {state}',
  'environment.state.on': 'Ligado',
  'environment.state.off': 'Desligado',
  'environment.state.unknown': 'Desconhecido',
  'environment.state.loading': 'Lendo o estado',

  'availability.environment_not_on':
    'O Docker não está ligado, por isso as ações de Docker estão indisponíveis. A tela de ambiente mostra como ligar.',
  'availability.docker_error':
    'O Docker não respondeu, por isso a lista e as ações estão indisponíveis. O erro recebido está abaixo.',
  'availability.kubernetes_unavailable':
    'Nenhum cluster Kubernetes responde, por isso a lista e as ações estão indisponíveis. O serviço continua tentando, e o erro recebido está abaixo.',
  'availability.goToEnvironment': 'Ir para a tela de ambiente',
  'availability.loading': 'Lendo o estado atual.',

  'action.cancel': 'Cancelar',
  'action.back': 'Voltar para a lista',
  'action.reconnect': 'Conectar de novo',
  'action.dismiss': 'Dispensar: {subject}',
  'action.dismissShort': 'Dispensar',
  'action.clearFinished': 'Limpar concluídas',
  'action.expand': 'Mostrar as ações',
  'action.collapse': 'Ocultar as ações',

  'table.filter': 'Filtrar a lista',
  'table.noMatches': 'Nenhum item corresponde ao filtro.',
  'table.actions': 'Ações',
  'table.empty': '—',

  'details.fullJson': 'Ver todos os detalhes em JSON',
  'details.loading': 'Lendo os detalhes.',
  'details.unavailable': 'Não foi possível ler os detalhes.',

  'confirm.irreversible': 'Esta ação não pode ser desfeita.',

  'dock.label': 'Ações em andamento e concluídas',
  'dock.title': 'Ações',
  'dock.summaryIdle': 'Nenhuma ação em andamento.',
  'dock.summaryRunning': { one: '{count} ação em andamento.', other: '{count} ações em andamento.' },
  'dock.summaryFailed': { one: '{count} ação com erro.', other: '{count} ações com erro.' },
  'dock.output': 'Saída',
  'dock.startedAt': 'Iniciada às {time}',
  'dock.outputLabel': 'Saída de: {subject}',

  'job.status.running': 'Em andamento',
  'job.status.succeeded': 'Concluída',
  'job.status.failed': 'Falhou',
  'job.status.refused': 'Recusada',

  'error.received': 'Erro recebido',
  'error.exitCode': 'Código de saída: {code}',

  'terminal.status.connecting': 'Conectando',
  'terminal.status.open': 'Conectado',
  'terminal.status.ended': 'O stream de logs terminou',
  'terminal.status.exited': 'O processo terminou com o código {code}',
  'terminal.status.lost': 'A conexão caiu',
  'terminal.status.error': 'Erro',
  'terminal.input': 'Entrada do terminal',
  'terminal.exitHint': 'No terminal, a tecla Tab vai para o shell. Para sair dele com o teclado, pressione Shift+Esc.',
  'terminal.reconnectLogs': 'Ao conectar de novo, as últimas 500 linhas são exibidas outra vez.',
  'terminal.reconnectShell': 'Ao conectar de novo, um novo shell é aberto.',
}
