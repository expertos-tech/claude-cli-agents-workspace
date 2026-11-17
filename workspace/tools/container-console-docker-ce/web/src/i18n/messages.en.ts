/** Texts shared by the shell and the base components. Each feature has its own dictionary. */
export const messages = {
  'app.name': 'Container Console · Docker CE',
  'app.project': 'Claude CLI Agents Workspace',
  'app.skipToContent': 'Skip to content',
  'app.documentTitle': '{page} · Container Console · Docker CE',
  'app.crashTitle': 'The screen hit an unexpected error',
  'app.crashBody': 'Reload the page. Docker and the containers were not affected by this error.',
  'app.notFoundTitle': 'Page not found',
  'app.notFoundBody': 'This address does not match any screen of the console.',

  'nav.label': 'Main menu',
  'nav.open': 'Open the menu',
  'nav.close': 'Close the menu',
  'nav.group.main': 'Home',
  'nav.group.docker': 'Docker',
  'nav.group.cluster': 'Cluster',
  'nav.motion': 'Animations',
  'nav.theme': 'Theme',
  'nav.theme.system': 'Follow the system',
  'nav.theme.dark': 'Dark',
  'nav.theme.light': 'Light',

  'live.lost': 'The live connection to the service dropped. Reconnecting; the data on screen may be out of date.',

  'environment.label': 'Docker state: {state}',
  'environment.state.on': 'On',
  'environment.state.off': 'Off',
  'environment.state.unknown': 'Unknown',
  'environment.state.loading': 'Reading the state',

  'availability.environment_not_on':
    'Docker is not on, so the Docker actions are unavailable. The environment screen shows how to start it.',
  'availability.docker_error':
    'Docker did not answer, so the list and the actions are unavailable. The error received is below.',
  'availability.kubernetes_unavailable':
    'No Kubernetes cluster answers, so the list and the actions are unavailable. The service keeps trying, and the error received is below.',
  'availability.goToEnvironment': 'Go to the environment screen',
  'availability.loading': 'Reading the current state.',

  'action.cancel': 'Cancel',
  'action.back': 'Back to the list',
  'action.reconnect': 'Connect again',
  'action.dismiss': 'Dismiss: {subject}',
  'action.dismissShort': 'Dismiss',
  'action.clearFinished': 'Clear finished',
  'action.expand': 'Show the actions',
  'action.collapse': 'Hide the actions',

  'table.filter': 'Filter the list',
  'table.noMatches': 'No item matches the filter.',
  'table.actions': 'Actions',
  'table.empty': '—',

  'details.fullJson': 'See all details as JSON',
  'details.loading': 'Reading the details.',
  'details.unavailable': 'Could not read the details.',

  'confirm.irreversible': 'This action cannot be undone.',

  'dock.label': 'Running and finished actions',
  'dock.title': 'Actions',
  'dock.summaryIdle': 'No action running.',
  'dock.summaryRunning': { one: '{count} action running.', other: '{count} actions running.' },
  'dock.summaryFailed': { one: '{count} action failed.', other: '{count} actions failed.' },
  'dock.output': 'Output',
  'dock.startedAt': 'Started at {time}',
  'dock.outputLabel': 'Output of: {subject}',

  'job.status.running': 'Running',
  'job.status.succeeded': 'Succeeded',
  'job.status.failed': 'Failed',
  'job.status.refused': 'Refused',

  'error.received': 'Error received',
  'error.exitCode': 'Exit code: {code}',

  'terminal.status.connecting': 'Connecting',
  'terminal.status.open': 'Connected',
  'terminal.status.ended': 'The log stream ended',
  'terminal.status.exited': 'The process exited with code {code}',
  'terminal.status.lost': 'The connection dropped',
  'terminal.status.error': 'Error',
  'terminal.input': 'Terminal input',
  'terminal.exitHint':
    'In the terminal, the Tab key goes to the shell. To leave it with the keyboard, press Shift+Esc.',
  'terminal.reconnectLogs': 'When you connect again, the last 500 lines are shown again.',
  'terminal.reconnectShell': 'When you connect again, a new shell opens.',
} as const
