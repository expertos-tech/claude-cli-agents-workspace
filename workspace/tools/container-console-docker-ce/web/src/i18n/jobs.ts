import { createTranslator, localize } from './index'
import { messages as en } from './jobs.en'
import { messages as ptBR } from './jobs.pt-BR'

const messages = localize({ en, 'pt-BR': ptBR })

const translate = createTranslator(messages)

/** Describes what a job does. A kind this dictionary does not know is shown as received. */
export function jobSentence(kind: string, target: string): string {
  if (!Object.hasOwn(messages, kind)) {
    return target ? `${kind} ${target}` : kind
  }
  return translate(kind as keyof typeof messages, { target })
}
