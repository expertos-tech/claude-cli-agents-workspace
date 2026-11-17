export const messages = {
  nav: 'Cleanup',
  title: 'Cleanup',
  description:
    'Removes what no active container uses: stopped containers, images, networks and build cache. Volumes hold data and are removed only if you tick the option.',
  loading: 'Working out what can be removed…',
  loadFailed: 'Could not work out the summary. It is recomputed when Docker changes.',
  nothing: 'Nothing to clean up: everything that exists is used by an active container.',

  summaryTitle: 'Summary',
  containers: 'Stopped containers',
  images: 'Images without an active container',
  networks: 'Networks without an active container',
  volumes: 'Volumes without an active container',
  buildCache: 'Build cache',
  showList: { one: 'See the item', other: 'See the {count} items' },
  none: 'None',

  includeVolumes: 'Also remove the unused volumes',
  includeVolumesHint:
    'Deletes the data they hold, such as databases of stopped projects. Without the tick, the volumes stay.',

  clean: 'Clean up',
  cleanTitle: 'Clean up what is not in use?',
  cleanBody:
    'Removed with docker prune: {containers} stopped containers, {images} images, {networks} networks and the build cache ({buildCache}). Containers of Kubernetes pods stay.',
  cleanVolumes: 'The {volumes} unused volumes are deleted too, with their data.',
  cleanKeepsVolumes: 'The volumes stay.',
  cleanRace:
    'The cleanup acts on the state of Docker when it runs: a container stopped after this summary is removed too.',
  running: 'Cleanup running. The summary is recomputed when it finishes.',
} as const
