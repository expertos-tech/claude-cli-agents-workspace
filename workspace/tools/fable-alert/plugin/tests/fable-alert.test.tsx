/**
 * Tests of the Fable alert mod: AC-1 to AC-9 and AC-15 to AC-18.
 *
 * `claude plugin test` has no coverage option, so this map stands in for it: every branch of
 * hooks/register.tsx and the test that exercises each side. A mutation check flipped each one.
 *
 * paint
 * - `fable ? SET_TINT : RESET_TINT`: AC-1 (set), AC-3 (reset).
 * sync
 * - `if (isBusy)`: AC-9 "overlapping ticks".
 * - `!isEnded` in `!isEnded && fable !== isTinted`: AC-9 "session ending while the model is read".
 * - `fable !== isTinted`: AC-1 (tint once across ticks), AC-2 (nothing on another model), AC-3 (both changes),
 *   AC-16 "state left by a reload".
 * - `isEnded` in `isEnded && fable`: AC-9 "session ending while the tint is written" (true), AC-1 (false).
 * - `fable` in `isEnded && fable`: AC-9 "session ending while the reset is written" (false).
 * - `catch`: AC-7 "failing process.run" and "failing session.model"; AC-9 "failing undo".
 * - `finally` releasing `isBusy`: AC-7 (the next tick retries).
 * session.end
 * - `e.reason !== 'clear'`: AC-4 (leaving stops), AC-5 (a /clear keeps watching).
 * - `e.reason !== 'resume'`: AC-4 (leaving stops), AC-15 (a /resume keeps watching).
 * - `if (await read($, isFable)...)`: AC-4 (on Fable resets), AC-4 "leaving on another model" (writes nothing).
 * - `.catch(() => true)` on that read: AC-18 (a failed read still resets).
 * - `catch`: AC-7 "failing reset on exit" and "failing reset on /clear".
 * ui.render
 * - `e.props.hasSurvey`: AC-8.
 * - `!(await read($, isFable))`: AC-1 (shown), AC-2 (hidden).
 * No branch, also pinned: `/fable/i` (AC-1 case), FIRST_CHECK_MS (AC-6), the polling period (AC-3),
 * `isEnded = false` and `stop()` on `session.start` ("a new session.start"), `stop()` on `session.end`
 * (AC-4 "a tick in flight"), the writes to the atom after a reset (AC-16a, AC-16b, AC-16c), a process that
 * exits non-zero (AC-17).
 */
import type { On } from 'claude-code'
import type { Engine } from 'claude-code/testing'
import { expect, mock, test } from 'claude-code/testing'

const FABLE = 'claude-fable-5-1'
const OPUS = 'claude-opus-5-5'
const SET_TINT = '\\033]11;#420c0c\\007'
const RESET_TINT = '\\033]111\\007'
const FIRST_CHECK_MS = 2000
const EVENT_LOOP_TURNS = 20
const SURFACES = ['terminal', 'desktop'] as const
const RUN_RESULT = { exitCode: 0, stdout: '', stderr: '', isStdoutTruncated: false, isStderrTruncated: false }
const LEAVE = { reason: 'prompt_input_exit', sessionId: 's1', resume: { id: 's1' } } as const
const CLEAR = { reason: 'clear', sessionId: 's1', resume: { id: 's1' } } as const
const RESUME = { reason: 'resume', sessionId: 's1', resume: { id: 's1' } } as const

const BAND = {
  plugin: 'fable-alert',
  component: 'AbovePrompt',
  requestId: 'above-prompt',
  props: {
    hasSurvey: false,
    isWorking: false,
    maxRows: 20,
    bodyColumns: 80,
    scroll: { offset: 0, bodyRows: 20 },
    view: {},
  },
} as const

/** Builds a promise the test settles by hand, to hold an engine call open at a chosen moment. */
function deferred() {
  let release = () => {}
  const held = new Promise<void>(resolve => {
    release = resolve
  })
  return { held, release }
}

/**
 * Stands for the engine beneath the mod, its clock aside. The test changes `model` and `runExitCode`, sets
 * `runFailures` or `modelFailures` to fail the next calls, and sets `holdRun` or `holdModel` to keep the next
 * call open. Each attempted write lands in `writes`, the failed and held ones too.
 */
function engineWithoutClock(on: On, model: string) {
  const world = {
    model,
    writes: [] as string[],
    modelReads: 0,
    ends: 0,
    runExitCode: 0,
    runFailures: 0,
    modelFailures: 0,
    holdRun: undefined as Promise<void> | undefined,
    holdModel: undefined as Promise<void> | undefined,
  }

  on('session.start', (_, e) => ({ cwd: e.cwd }))
  on('session.end', (_, e) => {
    world.ends += 1
    return { sessionId: e.sessionId }
  })
  on('session.model', async () => {
    world.modelReads += 1
    const held = world.holdModel
    world.holdModel = undefined
    if (held) await held
    if (world.modelFailures > 0) {
      world.modelFailures -= 1
      throw new Error('session.model failed')
    }
    return { value: world.model }
  })
  on('process.run', async (_, e) => {
    world.writes.push(String(e.argv[4]))
    const isFailing = world.runFailures > 0
    if (isFailing) world.runFailures -= 1
    const held = world.holdRun
    world.holdRun = undefined
    if (held) await held
    if (isFailing) throw new Error('process.run failed')
    return { value: { ...RUN_RESULT, exitCode: world.runExitCode } }
  })
  on('ui.render', ($, e) => {
    const { Text } = $.ui.resolve(e)
    return <Text>engine</Text>
  })

  return world
}

/** Stands for the engine beneath the mod, with a clock in memory that moves only when the test moves it. */
function fakeEngine(on: On, model: string) {
  return Object.assign(engineWithoutClock(on, model), { clock: mock.clock(on) })
}

/**
 * Answers `$.clock` by hand, for what `mock.clock` keeps to itself: each wait stays open until the test
 * calls what `after` or `ticks` holds, and `everyDispatches` counts the polling periods the mod asked for.
 */
function handTimers(on: On) {
  const timers = { after: [] as (() => void)[], ticks: [] as (() => void)[], everyDispatches: 0 }

  on('clock.after', async () => {
    await new Promise<void>(resolve => timers.after.push(resolve))
    return { value: undefined }
  })
  on('clock.every', async () => {
    timers.everyDispatches += 1
    await new Promise<void>(resolve => timers.ticks.push(resolve))
    return { value: undefined }
  })

  return timers
}

/**
 * Answers `$.state` from a store of the test's, standing for the host: `tinted` is what the host holds, and
 * setting it undefined wipes it, as a value never written reads. `failReads` makes each read reject; a thrown
 * hook would not do, because the kit then answers from its own store instead.
 */
function hostState(on: On, tinted?: boolean) {
  const host = { tinted, version: 1, failReads: false }

  on('state.get', () => {
    if (host.failReads) return { deny: 'state read refused' }
    return { value: { value: host.tinted, version: host.version } }
  })
  on('state.set', (_, e) => {
    host.tinted = e.value as boolean
    host.version += 1
    return { value: { isSet: true, version: host.version } }
  })

  return host
}

/** Lets the dispatches under way finish: with no mocked clock they take real turns of the event loop. */
async function settleEventLoop() {
  for (let turn = 0; turn < EVENT_LOOP_TURNS; turn += 1) {
    await new Promise(resolve => setTimeout(resolve, 1))
  }
}

/** Opens a session in the fake engine. */
function startSession($: Engine) {
  return $.session.start({ cwd: '/', surface: 'terminal', isInteractive: true })
}

/** Checks on every surface that the band is drawn or that the mod left the drawing to the engine. */
async function expectBand($: Engine, isShown: boolean, props: { hasSurvey?: boolean } = {}) {
  for (const surface of SURFACES) {
    const ui = await $.ui.mount({ ...BAND, surface, props: { ...BAND.props, ...props } })
    const banner = await ui.find({ type: 'Text', text: /FABLE ACTIVE/ })
    const engine = await ui.find({ type: 'Text', text: /engine/ })
    expect(banner?.text).toBe(isShown ? 'FABLE ACTIVE' : undefined)
    expect(engine?.text).toBe(isShown ? undefined : 'engine')
    await ui.unmount()
  }
}

test('AC-1 claude-fable-5-1: band shown, tint set once', async ($, on) => {
  const world = fakeEngine(on, FABLE)

  await startSession($)
  await world.clock.advance(3500)

  expect(world.writes).toEqual([SET_TINT])
  await expectBand($, true)
})

test('AC-1 the model name matches whatever its case', async ($, on) => {
  const world = fakeEngine(on, 'Claude-FABLE-5-1')

  await startSession($)
  await world.clock.advance(FIRST_CHECK_MS)

  expect(world.writes).toEqual([SET_TINT])
})

test('AC-2 claude-opus-5-5: band hidden, tint untouched', async ($, on) => {
  const world = fakeEngine(on, OPUS)

  await startSession($)
  await world.clock.advance(3500)

  expect(world.writes).toEqual([])
  await expectBand($, false)
})

test('AC-3 switching from Fable to Opus resets the tint and hides the band', async ($, on) => {
  const world = fakeEngine(on, FABLE)

  await startSession($)
  await world.clock.advance(FIRST_CHECK_MS)
  world.model = OPUS
  await world.clock.advance(999)
  expect(world.writes).toEqual([SET_TINT])
  await world.clock.advance(1)

  expect(world.writes).toEqual([SET_TINT, RESET_TINT])
  await expectBand($, false)
})

test('AC-3 switching from Opus to Fable sets the tint and shows the band', async ($, on) => {
  const world = fakeEngine(on, OPUS)

  await startSession($)
  await world.clock.advance(FIRST_CHECK_MS)
  world.model = FABLE
  await world.clock.advance(1000)

  expect(world.writes).toEqual([SET_TINT])
  await expectBand($, true)
})

test('AC-3 a band already drawn follows the switch', async ($, on) => {
  const world = fakeEngine(on, FABLE)

  await startSession($)
  await world.clock.advance(FIRST_CHECK_MS)
  const ui = await $.ui.mount({ ...BAND, surface: 'terminal' })
  expect((await ui.find({ type: 'Text', text: /FABLE ACTIVE/ }))?.text).toBe('FABLE ACTIVE')

  world.model = OPUS
  await world.clock.advance(1000)

  expect(await ui.find({ type: 'Text', text: /FABLE ACTIVE/ })).toBeUndefined()
  await ui.unmount()
})

test('AC-4 leaving the session on Fable resets the tint and stops watching', async ($, on) => {
  const world = fakeEngine(on, FABLE)

  await startSession($)
  await world.clock.advance(1000)
  expect(world.writes).toEqual([])
  await world.clock.advance(2500)
  await $.session.end(LEAVE)
  const readsAtExit = world.modelReads
  await world.clock.advance(5000)

  expect(world.writes).toEqual([SET_TINT, RESET_TINT])
  expect(world.modelReads).toBe(readsAtExit)
})

test('AC-4 leaving on another model writes nothing', async ($, on) => {
  const world = fakeEngine(on, OPUS)

  await startSession($)
  await world.clock.advance(3500)
  await $.session.end(LEAVE)

  expect(world.writes).toEqual([])
  expect(world.ends).toBe(1)
})

test('AC-4 a tick in flight at the end does nothing and no further period is asked', async ($, on) => {
  const timers = handTimers(on)
  const world = engineWithoutClock(on, OPUS)

  await startSession($)
  await settleEventLoop()
  timers.after.shift()?.()
  await settleEventLoop()
  timers.ticks.shift()?.()
  await settleEventLoop()
  expect(world.modelReads).toBe(2)
  expect(timers.everyDispatches).toBe(2)

  await $.session.end(LEAVE)
  timers.ticks.shift()?.()
  await settleEventLoop()

  expect(world.modelReads).toBe(2)
  expect(timers.everyDispatches).toBe(2)
})

test('AC-5 a /clear on Fable resets the tint and the next tick sets it again', async ($, on) => {
  const world = fakeEngine(on, FABLE)

  await startSession($)
  await world.clock.advance(FIRST_CHECK_MS)
  await $.session.end(CLEAR)
  expect(world.writes).toEqual([SET_TINT, RESET_TINT])
  await expectBand($, false)
  await world.clock.advance(1000)

  expect(world.writes).toEqual([SET_TINT, RESET_TINT, SET_TINT])
  await expectBand($, true)
})

test('AC-5 after a /clear on Opus a switch to Fable is still seen', async ($, on) => {
  const world = fakeEngine(on, OPUS)

  await startSession($)
  await world.clock.advance(FIRST_CHECK_MS)
  await $.session.end(CLEAR)
  expect(world.writes).toEqual([])
  world.model = FABLE
  await world.clock.advance(1000)

  expect(world.writes).toEqual([SET_TINT])
})

test('AC-6 nothing is read or written before FIRST_CHECK_MS', async ($, on) => {
  const world = fakeEngine(on, FABLE)

  await startSession($)
  await world.clock.advance(FIRST_CHECK_MS - 1)
  expect(world.writes).toEqual([])
  expect(world.modelReads).toBe(0)

  await world.clock.advance(1)
  expect(world.writes).toEqual([SET_TINT])
})

test('AC-7 a failing process.run leaves the band hidden and the next tick retries', async ($, on) => {
  const world = fakeEngine(on, FABLE)
  world.runFailures = 1

  await startSession($)
  await world.clock.advance(FIRST_CHECK_MS)
  expect(world.writes).toEqual([SET_TINT])
  await expectBand($, false)

  await world.clock.advance(1000)
  expect(world.writes).toEqual([SET_TINT, SET_TINT])
  await expectBand($, true)

  await world.clock.advance(1000)
  expect(world.writes).toEqual([SET_TINT, SET_TINT])
})

test('AC-7 a failing session.model writes nothing and the next tick retries', async ($, on) => {
  const world = fakeEngine(on, FABLE)
  world.modelFailures = 1

  await startSession($)
  await world.clock.advance(FIRST_CHECK_MS)
  expect(world.writes).toEqual([])

  await world.clock.advance(1000)
  expect(world.writes).toEqual([SET_TINT])
})

test('AC-7 a failing reset on exit does not stop the exit', async ($, on) => {
  const world = fakeEngine(on, FABLE)

  await startSession($)
  await world.clock.advance(FIRST_CHECK_MS)
  world.runFailures = 1
  await $.session.end(LEAVE)

  expect(world.writes).toEqual([SET_TINT, RESET_TINT])
  expect(world.ends).toBe(1)
})

test('AC-7 a failing reset on /clear still counts the tint as gone', async ($, on) => {
  const world = fakeEngine(on, FABLE)

  await startSession($)
  await world.clock.advance(FIRST_CHECK_MS)
  world.runFailures = 1
  await $.session.end(CLEAR)
  await world.clock.advance(1000)

  expect(world.writes).toEqual([SET_TINT, RESET_TINT, SET_TINT])
})

test('AC-8 a survey hides the band even on Fable', async ($, on) => {
  const world = fakeEngine(on, FABLE)

  await startSession($)
  await world.clock.advance(FIRST_CHECK_MS)

  await expectBand($, false, { hasSurvey: true })
  await expectBand($, true, { hasSurvey: false })
})

test('AC-9 overlapping ticks do not write twice', async ($, on) => {
  const world = fakeEngine(on, FABLE)
  const { held, release } = deferred()
  world.holdRun = held

  await startSession($)
  await world.clock.advance(FIRST_CHECK_MS + 3000)
  expect(world.writes).toEqual([SET_TINT])
  expect(world.modelReads).toBe(1)

  release()
  await world.clock.advance(1000)
  expect(world.writes).toEqual([SET_TINT])
  expect(world.modelReads).toBe(2)
})

test('AC-9 session ending while the tint is written undoes the tint', async ($, on) => {
  const world = fakeEngine(on, FABLE)
  const { held, release } = deferred()
  world.holdRun = held

  await startSession($)
  await world.clock.advance(FIRST_CHECK_MS)
  await $.session.end(LEAVE)
  expect(world.writes).toEqual([SET_TINT])

  release()
  await world.clock.settle()
  expect(world.writes).toEqual([SET_TINT, RESET_TINT])

  await world.clock.advance(5000)
  expect(world.writes).toEqual([SET_TINT, RESET_TINT])
})

test('AC-9 session ending while the reset is written does not reset again', async ($, on) => {
  const world = fakeEngine(on, FABLE)
  const { held, release } = deferred()

  await startSession($)
  await world.clock.advance(FIRST_CHECK_MS)
  world.model = OPUS
  world.holdRun = held
  await world.clock.advance(1000)
  await $.session.end(LEAVE)
  expect(world.writes).toEqual([SET_TINT, RESET_TINT, RESET_TINT])

  release()
  await world.clock.settle()
  expect(world.writes).toEqual([SET_TINT, RESET_TINT, RESET_TINT])
})

test('AC-9 session ending while the model is read writes nothing', async ($, on) => {
  const world = fakeEngine(on, FABLE)
  const { held, release } = deferred()
  world.holdModel = held

  await startSession($)
  await world.clock.advance(FIRST_CHECK_MS)
  await $.session.end(LEAVE)

  release()
  await world.clock.settle()
  expect(world.writes).toEqual([])
})

test('AC-9 a failing undo after the end stays contained', async ($, on) => {
  const world = fakeEngine(on, FABLE)
  const { held, release } = deferred()
  world.holdRun = held

  await startSession($)
  await world.clock.advance(FIRST_CHECK_MS)
  await $.session.end(LEAVE)
  world.runFailures = 1

  release()
  await world.clock.advance(5000)
  expect(world.writes).toEqual([SET_TINT, RESET_TINT])
})

test('AC-15 after a /resume on Opus a switch to Fable tints and shows the band', async ($, on) => {
  const world = fakeEngine(on, OPUS)

  await startSession($)
  await world.clock.advance(FIRST_CHECK_MS)
  await $.session.end(RESUME)
  expect(world.writes).toEqual([])
  world.model = FABLE
  await world.clock.advance(1000)

  expect(world.writes).toEqual([SET_TINT])
  await expectBand($, true)
})

test('AC-15 after a /resume on Fable the tint comes back and a switch to Opus clears it', async ($, on) => {
  const world = fakeEngine(on, FABLE)

  await startSession($)
  await world.clock.advance(FIRST_CHECK_MS)
  await $.session.end(RESUME)
  await world.clock.advance(1000)
  expect(world.writes).toEqual([SET_TINT, RESET_TINT, SET_TINT])
  await expectBand($, true)

  world.model = OPUS
  await world.clock.advance(1000)
  expect(world.writes).toEqual([SET_TINT, RESET_TINT, SET_TINT, RESET_TINT])
  await expectBand($, false)
})

test('AC-16a a /clear on Fable and then Opus before the next tick leaves no band', async ($, on) => {
  const world = fakeEngine(on, FABLE)

  await startSession($)
  await world.clock.advance(FIRST_CHECK_MS)
  await $.session.end(CLEAR)
  world.model = OPUS
  await world.clock.advance(5000)

  expect(world.writes).toEqual([SET_TINT, RESET_TINT])
  await expectBand($, false)
})

test('AC-16b the end on Fable and a later session.start on Opus leave no band', async ($, on) => {
  const world = fakeEngine(on, FABLE)

  await startSession($)
  await world.clock.advance(FIRST_CHECK_MS)
  await $.session.end(LEAVE)
  await expectBand($, false)
  world.model = OPUS
  await startSession($)
  await world.clock.advance(FIRST_CHECK_MS + 2000)

  expect(world.writes).toEqual([SET_TINT, RESET_TINT])
  await expectBand($, false)
})

test('AC-16c the undo after an end mid-write lets a later session.start on Fable tint again', async ($, on) => {
  const world = fakeEngine(on, FABLE)
  const { held, release } = deferred()
  world.holdRun = held

  await startSession($)
  await world.clock.advance(FIRST_CHECK_MS)
  await $.session.end(LEAVE)
  release()
  await world.clock.settle()
  expect(world.writes).toEqual([SET_TINT, RESET_TINT])
  await expectBand($, false)

  await startSession($)
  await world.clock.advance(FIRST_CHECK_MS + 2000)
  expect(world.writes).toEqual([SET_TINT, RESET_TINT, SET_TINT])
  await expectBand($, true)
})

test('AC-16 a tick finishing its reset while session.end resets too settles on no band', async ($, on) => {
  const world = fakeEngine(on, FABLE)
  const tick = deferred()
  const end = deferred()

  await startSession($)
  await world.clock.advance(FIRST_CHECK_MS)
  world.model = OPUS
  world.holdRun = tick.held
  await world.clock.advance(1000)
  world.holdRun = end.held
  const ending = $.session.end(LEAVE)
  await world.clock.settle()
  tick.release()
  await world.clock.settle()
  end.release()
  await ending

  expect(world.writes).toEqual([SET_TINT, RESET_TINT, RESET_TINT])
  await expectBand($, false)
})

test('AC-16 state left by a reload on Fable is still reset on Opus', async ($, on) => {
  const host = hostState(on, true)
  const world = fakeEngine(on, OPUS)

  await startSession($)
  await world.clock.advance(FIRST_CHECK_MS)

  expect(world.writes).toEqual([RESET_TINT])
  expect(host.tinted).toBe(false)
})

test('AC-16 state left by a reload on Fable writes nothing while still on Fable', async ($, on) => {
  const host = hostState(on, true)
  const world = fakeEngine(on, FABLE)

  await startSession($)
  await world.clock.advance(FIRST_CHECK_MS + 2000)

  expect(world.writes).toEqual([])
  expect(host.tinted).toBe(true)
})

test('AC-16 the host wiping its state after a /clear only means tinting again', async ($, on) => {
  const host = hostState(on)
  const world = fakeEngine(on, FABLE)

  await startSession($)
  await world.clock.advance(FIRST_CHECK_MS)
  await $.session.end(CLEAR)
  host.tinted = undefined
  await world.clock.advance(1000)

  expect(world.writes).toEqual([SET_TINT, RESET_TINT, SET_TINT])
  expect(host.tinted).toBe(true)
})

test('AC-17 a write exiting 1 still shows the band and is not repeated every second', async ($, on) => {
  const world = fakeEngine(on, FABLE)
  world.runExitCode = 1

  await startSession($)
  await world.clock.advance(FIRST_CHECK_MS + 5000)

  expect(world.writes).toEqual([SET_TINT])
  await expectBand($, true)
})

test('AC-18 a failed state read on leaving still resets the tint and the exit goes on', async ($, on) => {
  const host = hostState(on)
  const world = fakeEngine(on, FABLE)

  await startSession($)
  await world.clock.advance(FIRST_CHECK_MS)
  host.failReads = true
  await $.session.end(LEAVE)
  const readsAtExit = world.modelReads
  await world.clock.advance(5000)

  expect(world.writes).toEqual([SET_TINT, RESET_TINT])
  expect(world.ends).toBe(1)
  expect(world.modelReads).toBe(readsAtExit)
})

test('AC-18 a failed state read counts as tinted even on another model', async ($, on) => {
  const host = hostState(on)
  const world = fakeEngine(on, OPUS)

  await startSession($)
  await world.clock.advance(FIRST_CHECK_MS)
  host.failReads = true
  await $.session.end(LEAVE)

  expect(world.writes).toEqual([RESET_TINT])
  expect(world.ends).toBe(1)
})

test('AC-18 a failed state read and a failed reset do not stop the exit', async ($, on) => {
  const host = hostState(on)
  const world = fakeEngine(on, FABLE)

  await startSession($)
  await world.clock.advance(FIRST_CHECK_MS)
  host.failReads = true
  world.runFailures = 1
  await $.session.end(LEAVE)

  expect(world.writes).toEqual([SET_TINT, RESET_TINT])
  expect(world.ends).toBe(1)
})

test('a new session.start after the end watches the model again', async ($, on) => {
  const world = fakeEngine(on, FABLE)

  await startSession($)
  await world.clock.advance(FIRST_CHECK_MS)
  await $.session.end(LEAVE)
  await startSession($)
  await world.clock.advance(FIRST_CHECK_MS)

  expect(world.writes).toEqual([SET_TINT, RESET_TINT, SET_TINT])
})

test('a second session.start replaces the timers of the first', async ($, on) => {
  const world = fakeEngine(on, OPUS)

  await startSession($)
  await startSession($)
  await world.clock.advance(FIRST_CHECK_MS)
  expect(world.modelReads).toBe(1)

  await world.clock.advance(1000)
  expect(world.modelReads).toBe(2)
})
