import type { EnvironmentSnapshot } from '../../api/types'
import { bytesToGiB, createTranslator } from '../../i18n'
import { messages } from './messages'

const t = createTranslator(messages)

const MAX_DISK_GIB = 4096

/** What the user typed. A field not touched is absent and follows the current value. */
export interface ResourceDraft {
  cpus?: string
  memory?: string
  disk?: string
}

export interface ResourceValidation {
  errors: { cpus: string | null; memory: string | null; disk: string | null }
  /** The fields that changed, ready for the API. Valid only when `valid` is true. */
  payload: { cpus?: number; memoryGiB?: number; diskGiB?: number }
  valid: boolean
}

export const MAX_DISK = MAX_DISK_GIB

/** Reads an integer typed in a field, or null when it is not one. */
function parseInteger(text: string): number | null {
  return /^\d+$/.test(text.trim()) ? Number(text.trim()) : null
}

/** Validates the CPUs against the host, as the service does. */
function cpusError(value: number | null, max: number): string | null {
  if (value === null) {
    return t('errorInteger')
  }
  return value < 1 || value > max ? t('errorCpus', { max }) : null
}

/** Validates the memory against the host. A host memory of 0 means it was not read: no upper limit. */
function memoryError(value: number | null, max: number): string | null {
  if (value === null) {
    return t('errorInteger')
  }
  if (max === 0) {
    return value < 1 ? t('errorMemoryNoMax') : null
  }
  return value < 1 || value > max ? t('errorMemory', { max }) : null
}

/** Validates the disk. A smaller value is refused with the reason, since shrinking loses data. */
function diskError(value: number | null, current: number): string | null {
  if (value === null) {
    return t('errorInteger')
  }
  if (value < 1 || value > MAX_DISK_GIB) {
    return t('errorDiskRange', { max: MAX_DISK_GIB })
  }
  return value < current ? t('errorDiskShrink', { current }) : null
}

/** The values the form shows when the user has not typed anything. */
export function currentValues(environment: EnvironmentSnapshot): { cpus: number; memory: number; disk: number } {
  return {
    cpus: environment.usage.cpus,
    memory: bytesToGiB(environment.usage.memoryBytes),
    disk: bytesToGiB(environment.usage.diskBytes),
  }
}

/** Applies the rules of the contract to what was typed. The service checks them again. */
export function validateResources(draft: ResourceDraft, environment: EnvironmentSnapshot): ResourceValidation {
  const current = currentValues(environment)
  const cpus = draft.cpus === undefined ? current.cpus : parseInteger(draft.cpus)
  const memory = draft.memory === undefined ? current.memory : parseInteger(draft.memory)
  const disk = draft.disk === undefined ? current.disk : parseInteger(draft.disk)
  const errors = {
    cpus: draft.cpus === undefined ? null : cpusError(cpus, environment.host.cpus),
    memory: draft.memory === undefined ? null : memoryError(memory, bytesToGiB(environment.host.memoryBytes)),
    disk: draft.disk === undefined ? null : diskError(disk, current.disk),
  }
  const payload: ResourceValidation['payload'] = {}
  if (cpus !== null && cpus !== current.cpus) {
    payload.cpus = cpus
  }
  if (memory !== null && memory !== current.memory) {
    payload.memoryGiB = memory
  }
  if (disk !== null && disk !== current.disk) {
    payload.diskGiB = disk
  }
  return { errors, payload, valid: !errors.cpus && !errors.memory && !errors.disk }
}
