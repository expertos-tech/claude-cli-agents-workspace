// Shapes of docs/api.md. Field names follow the wire format.

export type EnvironmentState = 'off' | 'starting' | 'on' | 'stopping' | 'unknown'

export interface EnvironmentSnapshot {
  state: EnvironmentState
  reason?: string
  profile: string
  kubernetes: { enabled: boolean; transition?: 'starting' | 'stopping' }
  usage: { cpus: number; memoryBytes: number; diskBytes: number }
  host: { cpus: number; memoryBytes: number }
  arch?: string
  runtime?: string
  driver?: string
  mountType?: string
}

export interface Container {
  id: string
  name: string
  image: string
  command: string
  state: string
  status: string
  health?: string
  ports: string
  createdAt: string
  composeProject?: string
}

export interface Image {
  id: string
  repository: string
  tag: string
  reference: string
  size: string
  createdAt: string
}

export interface Volume {
  name: string
  driver: string
  scope: string
  mountpoint: string
  composeProject?: string
}

export interface Network {
  id: string
  name: string
  driver: string
  scope: string
  internal: boolean
  createdAt: string
  composeProject?: string
}

export interface ComposeProject {
  name: string
  state: string
  status: string
  configFiles: string[]
}

export interface DockerSnapshot {
  available: boolean
  reasonCode?: string
  reason?: string
  composeProjects: ComposeProject[]
  containers: Container[]
  images: Image[]
  volumes: Volume[]
  networks: Network[]
}

export interface Namespace {
  name: string
  status: string
  createdAt: string
}

export interface Pod {
  namespace: string
  name: string
  status: string
  ready: string
  restarts: number
  ip: string
  containers: string[]
  createdAt: string
}

export interface Deployment {
  namespace: string
  name: string
  replicas: number
  ready: number
  updated: number
  available: number
  createdAt: string
}

export interface Service {
  namespace: string
  name: string
  type: string
  clusterIP: string
  ports: string[]
  createdAt: string
}

export interface KubernetesSnapshot {
  available: boolean
  reasonCode?: string
  reason?: string
  namespaces: Namespace[]
  pods: Pod[]
  deployments: Deployment[]
  services: Service[]
}

export interface ApiErrorBody {
  code: string
  message: string
  exitCode?: number
  params?: Record<string, unknown>
}

export type JobStatus = 'running' | 'succeeded' | 'failed'

export interface Job {
  id: string
  kind: string
  target: string
  status: JobStatus
  output: string[]
  error?: ApiErrorBody
  startedAt: string
  finishedAt?: string
}

export interface JobsSnapshot {
  jobs: Job[]
}

export interface ContainerStats {
  cpuPercent: string
  memoryUsage: string
  memoryPercent: string
  networkIO: string
  blockIO: string
  pids: string
}

export interface LiveSnapshots {
  environment: EnvironmentSnapshot
  docker: DockerSnapshot
  kubernetes: KubernetesSnapshot
  jobs: JobsSnapshot
}

export type Topic = keyof LiveSnapshots
