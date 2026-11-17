import { type FormEvent, useState } from 'react'
import type { DockerSnapshot, EnvironmentSnapshot, KubernetesSnapshot } from '../../api/types'
import { useJob } from '../../api/useJob'
import { useLive } from '../../api/useLive'
import { Button } from '../../components/Button'
import { ConfirmButton, ConfirmDialog } from '../../components/ConfirmDialog'
import { EnvironmentStateBadge } from '../../components/EnvironmentBadge'
import { KubernetesToggle } from '../../components/KubernetesToggle'
import { MonoId } from '../../components/MonoId'
import { Card, DetailList, Field, Meter, Notice, Page, PageHeader, uiStyles } from '../../components/ui'
import { bytesToGiB, createTranslator } from '../../i18n'
import type { FeatureRoute } from '../../routing'
import { messages } from './messages'
import { currentValues, MAX_DISK, type ResourceDraft, validateResources } from './resources'

const t = createTranslator(messages)

interface WhatStopsProps {
  docker: DockerSnapshot | null
  kubernetes: KubernetesSnapshot | null
  kubernetesEnabled: boolean
}

/** The list that every confirmation of a VM stop shows, read from the latest snapshots. */
function WhatStops({ docker, kubernetes, kubernetesEnabled }: WhatStopsProps) {
  const running = docker?.containers.filter(item => item.state === 'running') ?? []
  const pods = kubernetes?.pods ?? []
  return (
    <>
      {!docker?.available && <p>{t('stopsUnknown')}</p>}
      {docker?.available && running.length === 0 && <p>{t('stopsNoContainers')}</p>}
      {running.length > 0 && (
        <>
          <p>{t('stopsContainers')}</p>
          <ul className={uiStyles.bulletList}>
            {running.map(item => (
              <li key={item.id}>{item.name}</li>
            ))}
          </ul>
        </>
      )}
      {kubernetesEnabled && pods.length === 0 && <p>{t('stopsPodsBackground')}</p>}
      {kubernetesEnabled && pods.length > 0 && (
        <>
          <p>{t('stopsPods')}</p>
          <ul className={uiStyles.bulletList}>
            {pods.map(pod => (
              <li key={`${pod.namespace}/${pod.name}`}>{`${pod.namespace}/${pod.name}`}</li>
            ))}
          </ul>
        </>
      )}
    </>
  )
}

/** The sentence of a state that is not `on`. */
function stateNotice(environment: EnvironmentSnapshot): string | null {
  switch (environment.state) {
    case 'off':
      return t('stateOff')
    case 'starting':
      return t('stateStarting')
    case 'stopping':
      return t('stateStopping')
    case 'unknown':
      return t('stateUnknown')
    case 'on':
      return null
  }
}

/** The current state and what the VM has allocated, next to the total of the Mac. */
function StatusCard({ environment }: { environment: EnvironmentSnapshot }) {
  const { usage, host } = environment
  const memory = bytesToGiB(usage.memoryBytes)
  const hostMemory = bytesToGiB(host.memoryBytes)
  const notice = stateNotice(environment)
  const onlyWithVm = <span className={uiStyles.hint}>{t('notAvailable')}</span>
  const text = (value: string | undefined) => (value ? <MonoId value={value} /> : onlyWithVm)
  return (
    <Card title={t('statusTitle')} actions={<EnvironmentStateBadge state={environment.state} />}>
      {notice && (
        <Notice>
          <p>{notice}</p>
          {environment.reason && <pre className={uiStyles.pre}>{environment.reason}</pre>}
        </Notice>
      )}
      <div className={uiStyles.grid}>
        <div className={uiStyles.metric}>
          <span className={uiStyles.detailTerm}>{t('cpus')}</span>
          <span className={uiStyles.figure}>{t('cpusValue', { used: usage.cpus, total: host.cpus })}</span>
          <Meter ratio={host.cpus > 0 ? usage.cpus / host.cpus : 0} />
        </div>
        <div className={uiStyles.metric}>
          <span className={uiStyles.detailTerm}>{t('memory')}</span>
          <span className={uiStyles.figure}>
            {hostMemory > 0
              ? t('memoryValue', { used: memory, total: hostMemory })
              : t('memoryValueNoTotal', { used: memory })}
          </span>
          <Meter ratio={hostMemory > 0 ? memory / hostMemory : 0} />
        </div>
        <div className={uiStyles.metric}>
          <span className={uiStyles.detailTerm}>{t('disk')}</span>
          <span className={uiStyles.figure}>{t('diskValue', { used: bytesToGiB(usage.diskBytes) })}</span>
        </div>
      </div>
      <DetailList
        items={[
          { term: t('profile'), value: <MonoId value={environment.profile} /> },
          {
            term: t('mode'),
            value: environment.kubernetes.enabled ? t('modeKubernetes') : t('modeDocker'),
          },
          { term: t('arch'), value: text(environment.arch) },
          { term: t('runtime'), value: text(environment.runtime) },
          { term: t('driver'), value: text(environment.driver) },
          { term: t('mountType'), value: text(environment.mountType) },
        ]}
      />
    </Card>
  )
}

interface ResourceFieldsProps {
  environment: EnvironmentSnapshot
  draft: ResourceDraft
  disabled: boolean
  onChange: (draft: ResourceDraft) => void
}

/** The three fields with their limits and the reason of each refusal. */
function ResourceFields({ environment, draft, disabled, onChange }: ResourceFieldsProps) {
  const current = currentValues(environment)
  const { errors } = validateResources(draft, environment)
  const hostMemory = bytesToGiB(environment.host.memoryBytes)
  return (
    <div className={uiStyles.formRow}>
      <Field label={t('cpusLabel')} hint={t('cpusHint', { max: environment.host.cpus })} error={errors.cpus}>
        {control => (
          <input
            {...control}
            type="text"
            inputMode="numeric"
            disabled={disabled}
            value={draft.cpus ?? String(current.cpus)}
            onChange={event => onChange({ ...draft, cpus: event.target.value })}
          />
        )}
      </Field>
      <Field
        label={t('memoryLabel')}
        hint={hostMemory > 0 ? t('memoryHint', { max: hostMemory }) : t('memoryHintNoMax')}
        error={errors.memory}
      >
        {control => (
          <input
            {...control}
            type="text"
            inputMode="numeric"
            disabled={disabled}
            value={draft.memory ?? String(current.memory)}
            onChange={event => onChange({ ...draft, memory: event.target.value })}
          />
        )}
      </Field>
      <Field label={t('diskLabel')} hint={t('diskHint', { current: current.disk, max: MAX_DISK })} error={errors.disk}>
        {control => (
          <input
            {...control}
            type="text"
            inputMode="numeric"
            disabled={disabled}
            value={draft.disk ?? String(current.disk)}
            onChange={event => onChange({ ...draft, disk: event.target.value })}
          />
        )}
      </Field>
    </div>
  )
}

/** Turns the VM on in the chosen mode, with optional new resources. */
function StartCard({ environment }: { environment: EnvironmentSnapshot }) {
  const { run, isBusy } = useJob()
  const [withKubernetes, setWithKubernetes] = useState(false)
  const [draft, setDraft] = useState<ResourceDraft>({})
  const validation = validateResources(draft, environment)

  /** Sends the start request. Only the fields that changed go, and the rest stays saved in Colima. */
  async function submit(event: FormEvent): Promise<void> {
    event.preventDefault()
    if (!validation.valid) {
      return
    }
    const job = await run('environment.start', environment.profile, '/api/environment/start', {
      kubernetes: withKubernetes,
      ...validation.payload,
    })
    if (job) {
      setDraft({})
    }
  }

  return (
    <Card title={t('startTitle')}>
      <form className={uiStyles.form} onSubmit={submit} noValidate>
        <fieldset className={uiStyles.field}>
          <legend className={uiStyles.label}>{t('modeLegend')}</legend>
          <div className={uiStyles.choices}>
            <label className={uiStyles.choice}>
              <input
                type="radio"
                name="environment-mode"
                checked={!withKubernetes}
                onChange={() => setWithKubernetes(false)}
              />
              <span>
                {t('modeDocker')}
                <br />
                <span className={uiStyles.hint}>{t('modeDockerHint')}</span>
              </span>
            </label>
            <label className={uiStyles.choice}>
              <input
                type="radio"
                name="environment-mode"
                checked={withKubernetes}
                onChange={() => setWithKubernetes(true)}
              />
              <span>
                {t('modeKubernetes')}
                <br />
                <span className={uiStyles.hint}>{t('modeKubernetesHint')}</span>
              </span>
            </label>
          </div>
        </fieldset>
        <ResourceFields environment={environment} draft={draft} disabled={false} onChange={setDraft} />
        <p className={uiStyles.hint}>{t('resourcesHint')}</p>
        <div className={uiStyles.row}>
          <Button
            type="submit"
            variant="primary"
            icon="play"
            busy={isBusy(environment.profile)}
            disabled={!validation.valid}
          >
            {t('start')}
          </Button>
        </div>
      </form>
    </Card>
  )
}

interface LiveListsProps {
  environment: EnvironmentSnapshot
  docker: DockerSnapshot | null
  kubernetes: KubernetesSnapshot | null
}

/** Applies new resources to a running VM, which needs a restart and so an explicit confirmation. */
function ResourcesCard({ environment, docker, kubernetes }: LiveListsProps) {
  const { run, isBusy } = useJob()
  const [draft, setDraft] = useState<ResourceDraft>({})
  const [confirming, setConfirming] = useState(false)
  const validation = validateResources(draft, environment)
  const hasChanges = Object.keys(validation.payload).length > 0
  const blocked = environment.state !== 'on'

  /** Validates first: the confirmation only opens for values the service would accept. */
  function submit(event: FormEvent): void {
    event.preventDefault()
    if (validation.valid && hasChanges && !blocked) {
      setConfirming(true)
    }
  }

  /** Sends the values with the confirmation the service demands. */
  async function apply(): Promise<void> {
    setConfirming(false)
    const job = await run('environment.resources', environment.profile, '/api/environment/resources', {
      ...validation.payload,
      confirm: true,
    })
    if (job) {
      setDraft({})
    }
  }

  return (
    <Card title={t('resourcesTitle')}>
      <p className={uiStyles.hint}>{blocked ? t('resourcesBlocked') : t('resourcesDescriptionOn')}</p>
      <form className={uiStyles.form} onSubmit={submit} noValidate>
        <ResourceFields environment={environment} draft={draft} disabled={blocked} onChange={setDraft} />
        <div className={uiStyles.row}>
          <Button
            type="submit"
            variant="primary"
            icon="check"
            busy={isBusy(environment.profile)}
            disabled={blocked || !validation.valid || !hasChanges}
          >
            {t('apply')}
          </Button>
          {!hasChanges && !blocked && <span className={uiStyles.hint}>{t('noChanges')}</span>}
        </div>
      </form>
      <ConfirmDialog
        open={confirming}
        title={t('applyConfirmTitle')}
        confirmLabel={t('applyConfirm')}
        onCancel={() => setConfirming(false)}
        onConfirm={apply}
      >
        <p>{t('applyBody')}</p>
        <WhatStops docker={docker} kubernetes={kubernetes} kubernetesEnabled={environment.kubernetes.enabled} />
        <p>{t('telemetryNote')}</p>
      </ConfirmDialog>
    </Card>
  )
}

/** Turns the VM off after the confirmation that lists what stops. */
function StopCard({ environment, docker, kubernetes }: LiveListsProps) {
  const { run, isBusy } = useJob()
  const canStop = environment.state === 'on' || environment.state === 'unknown'
  return (
    <Card title={t('stopTitle')}>
      <p className={uiStyles.hint}>{canStop ? t('stopDescription') : t('stopBlocked')}</p>
      <div className={uiStyles.row}>
        <ConfirmButton
          label={t('stop')}
          icon="stop"
          disabled={!canStop}
          busy={isBusy(environment.profile)}
          dialogTitle={t('stopConfirmTitle')}
          confirmLabel={t('stop')}
          onConfirm={() => run('environment.stop', environment.profile, '/api/environment/stop', { confirm: true })}
        >
          <WhatStops docker={docker} kubernetes={kubernetes} kubernetesEnabled={environment.kubernetes.enabled} />
          <p>{t('telemetryNote')}</p>
        </ConfirmButton>
      </div>
    </Card>
  )
}

/** Explains which screens wait for the environment. */
function UnavailableCard() {
  return (
    <Card title={t('unavailableTitle')}>
      <ul className={uiStyles.bulletList}>
        <li>{t('unavailableDocker')}</li>
        <li>{t('unavailableCompose')}</li>
        <li>{t('unavailableKubernetes')}</li>
      </ul>
    </Card>
  )
}

/** The screen of the environment. What it offers depends on the state in the latest snapshot. */
function EnvironmentPage() {
  const environment = useLive('environment').data
  const vmUp = environment?.state === 'on'
  const docker = useLive('docker', vmUp).data
  const kubernetes = useLive('kubernetes', vmUp && environment?.kubernetes.enabled === true).data

  if (!environment) {
    return (
      <Page>
        <PageHeader eyebrow={t('eyebrow')} title={t('title')} description={t('description')} />
      </Page>
    )
  }

  const canStart = environment.state === 'off' || environment.state === 'unknown'
  const lists = { environment, docker, kubernetes }
  return (
    <Page>
      <PageHeader eyebrow={t('eyebrow')} title={t('title')} description={t('description')} />
      <StatusCard environment={environment} />
      {canStart && <StartCard environment={environment} />}
      {environment.state === 'off' && <UnavailableCard />}
      {!canStart && <ResourcesCard {...lists} />}
      <Card title={t('kubernetesTitle')}>
        <p className={uiStyles.hint}>{t('kubernetesDescription')}</p>
        <KubernetesToggle environment={environment} kubernetes={kubernetes} />
      </Card>
      <StopCard {...lists} />
    </Page>
  )
}

export const route: FeatureRoute = {
  id: 'environment',
  order: 20,
  group: 'main',
  icon: 'environment',
  Page: EnvironmentPage,
}
