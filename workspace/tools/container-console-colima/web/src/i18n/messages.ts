import { createTranslator, localize } from './index'
import { messages as en } from './messages.en'
import { messages as ptBR } from './messages.pt-BR'

const messages = localize({ en, 'pt-BR': ptBR })

export const t = createTranslator(messages)
