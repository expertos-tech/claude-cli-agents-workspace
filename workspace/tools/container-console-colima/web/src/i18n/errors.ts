import { messages as en } from './errors.en'
import { messages as ptBR } from './errors.pt-BR'
import { createTranslator, localize } from './index'

const messages = localize({ en, 'pt-BR': ptBR })

const translate = createTranslator(messages)

/** Returns the sentence of an error code, or null for a code this dictionary does not know. */
export function errorSentence(code: string, params: Record<string, unknown> = {}): string | null {
  if (!Object.hasOwn(messages, code)) {
    return null
  }
  const textParams: Record<string, string | number> = {}
  for (const [name, value] of Object.entries(params)) {
    if (typeof value === 'string' || typeof value === 'number') {
      textParams[name] = value
    }
  }
  const sentence = translate(code as keyof typeof messages, textParams)
  // A job error carries no params. Without them the raw message, always shown, says it alone.
  return /\{\w+\}/.test(sentence) ? null : sentence
}
