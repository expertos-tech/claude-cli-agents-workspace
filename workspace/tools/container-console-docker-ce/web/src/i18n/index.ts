/** The languages of the screen. English is the default; the rest are translations of it. */
export type Locale = 'en' | 'pt-BR'

/** English, or Brazilian Portuguese when the browser language is any Portuguese. */
function detectLocale(): Locale {
  const language = typeof navigator === 'undefined' ? '' : navigator.language
  return language.toLowerCase().startsWith('pt') ? 'pt-BR' : 'en'
}

export const LOCALE: Locale = detectLocale()
const GIBIBYTE = 1024 ** 3
const DOCKER_TIMESTAMP = /^(\d{4}-\d{2}-\d{2}) (\d{2}:\d{2}:\d{2}) ([+-]\d{2})(\d{2})/

const numberFormat = new Intl.NumberFormat(LOCALE)
const pluralRules = new Intl.PluralRules(LOCALE)
const dateTimeFormat = new Intl.DateTimeFormat(LOCALE, { dateStyle: 'short', timeStyle: 'short' })
const timeFormat = new Intl.DateTimeFormat(LOCALE, { timeStyle: 'medium' })

/** A whole sentence, or the two plural forms of one, selected by the `count` parameter. */
export type Message = string | { one: string; other: string }
export type Messages = Record<string, Message>
export type Params = Record<string, string | number>
export type Translator<Key extends string> = (key: Key, params?: Params) => string

/** A translation of an English dictionary: the same keys, and the same plural shape for each. */
export type Translation<English extends Messages> = {
  [Key in keyof English]: English[Key] extends string ? string : { one: string; other: string }
}

/** One dictionary in every locale. The compiler refuses a translation with a missing or extra key. */
export type Localized<English extends Messages> = { en: English } & {
  [Other in Exclude<Locale, 'en'>]: Translation<English>
}

/** Picks the dictionary of the current locale. */
export function localize<English extends Messages>(dictionaries: Localized<English>): Translation<English> {
  return dictionaries[LOCALE] as Translation<English>
}

/** Replaces each `{name}` with its parameter, formatting numbers for the locale. */
function interpolate(template: string, params: Params): string {
  return template.replace(/\{(\w+)\}/g, (whole, name: string) => {
    const value = params[name]
    if (value === undefined) {
      return whole
    }
    return typeof value === 'number' ? numberFormat.format(value) : value
  })
}

/** Picks the plural form that the `count` parameter asks for. */
function selectForm(message: Message, params: Params): string {
  if (typeof message === 'string') {
    return message
  }
  const count = typeof params.count === 'number' ? params.count : 0
  return pluralRules.select(count) === 'one' ? message.one : message.other
}

/** Builds the translator of one dictionary. Keys are checked at compile time. */
export function createTranslator<Dictionary extends Messages>(
  messages: Dictionary,
): Translator<Extract<keyof Dictionary, string>> {
  return (key, params = {}) => interpolate(selectForm(messages[key] as Message, params), params)
}

/** Converts bytes to whole GiB, rounding down as the service does when it compares limits. */
export function bytesToGiB(bytes: number): number {
  return Math.floor(bytes / GIBIBYTE)
}

/** Formats a number for the locale. */
export function formatNumber(value: number): string {
  return numberFormat.format(value)
}

/** Parses an RFC 3339 date or the date `docker` prints; null when it is neither. */
function parseTimestamp(value: string): Date | null {
  const docker = DOCKER_TIMESTAMP.exec(value)
  const normalized = docker ? `${docker[1]}T${docker[2]}${docker[3]}:${docker[4]}` : value
  const date = new Date(normalized)
  return Number.isNaN(date.getTime()) ? null : date
}

/** Formats date and time for the locale, or returns the value as received if it cannot be read. */
export function formatTimestamp(value: string): string {
  const date = parseTimestamp(value)
  return date ? dateTimeFormat.format(date) : value
}

/** Formats only the time of an RFC 3339 date. */
export function formatTime(value: string): string {
  const date = parseTimestamp(value)
  return date ? timeFormat.format(date) : value
}
