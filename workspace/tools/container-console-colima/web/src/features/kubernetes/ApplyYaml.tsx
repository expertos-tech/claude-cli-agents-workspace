import { type FormEvent, useState } from 'react'
import { useJob } from '../../api/useJob'
import { Button } from '../../components/Button'
import { Card, Field, uiStyles } from '../../components/ui'
import { createTranslator } from '../../i18n'
import { messages } from './messages'

const t = createTranslator(messages)

/** The service refuses a body above 1 MiB, and the JSON around the YAML also counts. */
const MAX_YAML_BYTES = 1024 * 1024 - 1024

/** Sends a YAML to the cluster. The text stays in the field, so a refused file can be corrected. */
export function ApplyYaml({ available, describedBy }: { available: boolean; describedBy: string | undefined }) {
  const { run } = useJob()
  const [yaml, setYaml] = useState('')
  const [submitted, setSubmitted] = useState(false)
  const empty = yaml.trim().length === 0
  const tooLarge = new TextEncoder().encode(yaml).length > MAX_YAML_BYTES
  const fieldError = tooLarge ? t('yamlTooLarge') : submitted && empty ? t('yamlEmpty') : null

  /** Validates what the screen can and leaves the rest to the dry run on the cluster. */
  function submit(event: FormEvent): void {
    event.preventDefault()
    setSubmitted(true)
    if (!empty && !tooLarge) {
      void run('kubernetes.apply', '', '/api/kubernetes/apply', { yaml })
    }
  }

  return (
    <Card title={t('applyTitle')}>
      <p className={uiStyles.hint}>{t('applyDescription')}</p>
      <p className={uiStyles.hint}>{t('applyNamespaceNote')}</p>
      <form className={uiStyles.form} onSubmit={submit} noValidate>
        <Field label={t('yamlLabel')} error={fieldError} describedBy={describedBy} multiline>
          {control => (
            <textarea
              {...control}
              rows={16}
              spellCheck={false}
              autoComplete="off"
              disabled={!available}
              value={yaml}
              onChange={event => setYaml(event.target.value)}
            />
          )}
        </Field>
        <div className={uiStyles.row}>
          <Button type="submit" variant="primary" icon="check" disabled={!available}>
            {t('apply')}
          </Button>
        </div>
      </form>
    </Card>
  )
}
