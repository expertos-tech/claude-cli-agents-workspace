export const messages = {
  nav: 'Environment',
  title: 'Environment',
  description:
    'The state and data of the Docker daemon on this machine. This screen only shows: the system starts and stops Docker.',

  statusTitle: 'Docker daemon',
  version: 'Version',
  cpus: 'CPUs',
  memory: 'Memory',
  memoryValue: '{value} GiB',
  driver: 'Storage driver',
  system: 'Operating system',
  architecture: 'Architecture',

  stateOff:
    'Docker is off. The console does not start Docker, because that needs administrator privileges. To start it, run this command in a terminal:',
  startCommand: 'sudo systemctl start docker',
  stateUnknown: 'Could not tell the state of Docker. The reason received is below.',

  unavailableTitle: 'What is unavailable with Docker off',
  unavailableDocker: 'Containers, images, volumes and networks.',
  unavailableCompose: 'Starting, stopping and removing Compose projects. The list and the file choice keep working.',
  kubernetesNote:
    'Kubernetes does not depend on this screen: the Kubernetes screen shows whether a cluster answers in the kubeconfig context.',
} as const
