import { localize } from '../../i18n'
import { messages as en } from './messages.en'
import { messages as ptBR } from './messages.pt-BR'

/** The dictionary of this feature in the locale of the screen. */
export const messages = localize({ en, 'pt-BR': ptBR })
