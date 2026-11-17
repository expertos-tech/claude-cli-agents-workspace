export const messages = {
  nav: 'Compose',
  title: 'Compose projects',
  description: 'The known projects and the files you chose. They stay in the list even with Docker off.',

  addTitle: 'Add project',
  addDescription: 'Choose a .yaml or .yml file inside your home folder. The project name comes from Compose itself.',
  chooseFile: 'Choose file',
  choosing: 'Waiting for the file dialog',
  choosingHint:
    'The file dialog opens on the desktop, sometimes behind the browser. It stays open for up to 5 minutes.',
  pathLabel: 'File path',
  pathHint: 'Use this field if the dialog does not open. The path must be absolute.',
  pathInvalid: 'The path must be absolute, without `..`, and end in .yaml or .yml.',
  add: 'Add',
  added: 'Project {name} was added to the list.',

  caption: { one: '{count} project', other: '{count} projects' },
  empty: 'No known project. Add a file above.',
  columnName: 'Project',
  columnState: 'State',
  columnStatus: 'Status',
  columnFiles: 'Files',
  noFiles: 'No known file',

  'state.running': 'Running',
  'state.exited': 'Stopped',
  'state.down': 'No containers',
  'state.unknown': 'Unknown',

  up: 'Start',
  stop: 'Stop',
  remove: 'Remove',
  upAria: 'Start project {name}',
  stopAria: 'Stop project {name}',
  removeAria: 'Remove project {name}',
  removeTitle: 'Remove project {name}?',
  removeBody:
    'Runs docker compose down: the containers and networks of the project are removed, and it leaves the list. The volumes are kept unless you tick the option below.',
  removeVolumes: 'Also remove the volumes of the project, which deletes their data',
} as const
