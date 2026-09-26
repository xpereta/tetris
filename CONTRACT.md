# Tetris — Project Contract (shared by all phases/subagents)

## File layout
```
/home/xavi/tetris/
├── index.html          # single page; loads js/ui.js as <script type="module">
├── package.json        # "type":"module", scripts: test = node --test tests/
├── CONTRACT.md         # this file — the source of truth for APIs
├── js/
│   ├── engine.js       # PURE game logic. No DOM, no browser APIs. ESM exports.
│   ├── srs.js          # SRS shape data + wall-kick tables (imported by engine)
│   ├── ui.js           # canvas rendering, keyboard/touch input, HUD. Imports engine.
│   └── autoplayer.js   # simple AI that drives a Game via the same public API as human input.
├── tests/              # node:test unit tests (run with: npm test)
```

## Engine contract — `js/engine.js`

```js
export class Game {
  constructor(options = {})
  // options.seed?: number        -> deterministic piece sequence (mulberry32 PRNG)
  // options.onEvent?: fn(e)      -> event callback, see Events below

  state: 'idle' | 'playing' | 'paused' | 'over'
  board: Array<Array<string|null>>   // [row][col], row 0 = TOP. 10 wide x 40 tall (20 hidden rows on top).
                                     // cell holds piece type char or null.
  score: number; level: number; lines: number
  combo: number          // -1 when no active combo
  b2b: boolean           // back-to-back chain active
  hold: string | null    // held piece type
  canHold: boolean       // false until next piece locks (no double-hold)
  queue: string[]        // upcoming pieces, always >= 5 visible; 7-bag randomizer
  current: { type, x, y, rot } | null   // x = leftmost col of bounding box, y = top row of bbox

  start(); pause(); resume(); reset()
  moveLeft(): boolean; moveRight(): boolean
  softDrop(): boolean    // +1 score per cell dropped (guideline)
  hardDrop(): void       // +2 score per cell, locks immediately
  rotateCW(): boolean; rotateCCW(): boolean   // SRS with wall kicks
  holdPiece(): boolean   // swap current<->hold per guideline rules
  tick(): Event[]        // advance gravity one frame at current level speed (see Gravity)
  ghostY: number         // y where current piece would land if dropped now

  isTSpin(): boolean     // 3-corner rule, evaluated on lock (also exposed for tests)
}
```

### Pieces & SRS
- Types: `I O T S Z J L`. Standard SRS spawn orientations and bounding boxes
  (I in 4x4 box, O in 2x2 box with no effective kicks, others 3x3).
- Full official SRS wall-kick tables for JLSTZ (JLSTZ table) and I piece.
- Rotation state `rot` ∈ {0,1,2,3} = R, R2, L, spawn... use standard: 0=spawn, 1=CW, 2=180, 3=CCW.

### Randomizer
- 7-bag: shuffle all 7 pieces per bag (Fisher–Yates with seeded mulberry32 PRNG).
- `queue` must always be refillable to >= 5 entries; expose the full upcoming list for HUD (show next 5 in UI).

### Scoring (Tetris Guideline)
| Event | Points (× level) |
|---|---|
| Single / Double / Triple | 100 / 300 / 500 |
| Tetris | 800 |
| T-spin single / double / triple | 800 / 1200 / 1600 |
| T-spin tetris | 1600 |
| Mini T-spin single/double/triple | 100 / 200 / 400 (no b2b) |
| Soft drop | +1 per cell (not × level) |
| Hard drop | +2 per cell (not × level) |
| Combo | +50 × combo × level |
| Back-to-back (Tetris or T-spin line clears) | × 1.5 on the base clear points |

- Level = floor(lines / 10) + 1.

### Gravity (guideline formula, seconds per row at level L):
`t(L) = (0.8 - (L-1)*0.007)^(L-1)` — engine `tick()` is called by the UI on a fixed
frame interval; Game internally accumulates time and locks when t(L) elapses.
For testability, `Game` accepts `options.gravityMs?: number` to override (fixed ms per row).

### Lock delay
- 500 ms lock delay after piece first touches ground; resets on successful move/rotate,
  max 15 resets per piece ("move reset" rule), then locks.
- Testable via `options.lockDelayMs?: number`.

### Game over
- Piece spawns overlapping existing blocks (block out) → state 'over', event fired.

### Events (via onEvent and/or returned from tick/hardDrop/holdPiece)
```js
{ type: 'lock', piece, x, y, rot }
{ type: 'clear', lines: 1|2|3|4, tSpin: bool, miniTSpin: bool, points, combo, b2b }
{ type: 'levelup', level }
{ type: 'hold', piece }
{ type: 'gameover' }
```

## UI contract — `js/ui.js`
- Canvas board 10×20 visible (cell size responsive), plus side panels: score/level/lines,
  next queue (5 pieces), hold box. Ghost piece rendered semi-transparent.
- Keyboard: ← → move (DAS ~167ms / ARR ~33ms), ↓ soft drop, ↑ or X = CW rotate, Z = CCW,
  Space = hard drop, C or Shift = hold, P/Esc = pause, Enter = start/restart.
- Touch controls for mobile: on-screen buttons (left/right/rotate/drop/hold) shown when
  `('ontouchstart' in window)` — must be playable from a phone.
- HUD updates reactively; game-over overlay with final score + restart button.

## Autoplayer contract — `js/autoplayer.js`
```js
export class AutoPlayer {
  constructor(game)          // drives the given Game instance
  step(): void               // one decision: move/rotate/drop current piece toward a heuristic target
}
```
- Simple heuristic (minimize height + holes, maximize clears). Used ONLY for validation.

## Validation gates (a phase is DONE only when these pass)
1. `npm test` — all unit tests green (Phase 1 gate).
2. Autoplayer: 5 full games to game-over with seeded RNG, no exceptions, score strictly increases over time, final board height sane (< 40 rows used). (Phase 3 gate.)
3. Headless browser: page loads without console errors; simulated keypresses start a game and reach line clears + game over; screenshots at milestones look correct. (Phase 3 gate.)
