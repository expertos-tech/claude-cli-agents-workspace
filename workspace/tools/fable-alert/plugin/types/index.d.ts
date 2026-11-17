export type FableFlag = boolean

declare module 'claude-code' {
  interface PluginState {
    'fable-alert': { isFable: FableFlag }
  }
}
