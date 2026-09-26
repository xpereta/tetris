# CONTRACT V2 — Audio & Animations (additive; v1 contract unchanged)

v2 adds music, sound effects, and animations on top of v1. **The engine
(`js/engine.js`, `js/srs.js`) is FROZEN** — no changes unless a proven bug is
found. All new behavior lives in:

- `js/audio.js` (NEW) — Web Audio API, procedural only (no audio files)
- `js/ui.js` (MODIFIED) — animation hooks + wiring to audio events
- `index.html` (MODIFIED) — mute button, no other structural changes

## 1. Audio module (`js/audio.js`)

Pure ESM, **must import cleanly in Node** (no DOM access at import time; all
AudioContext creation deferred until first user gesture). Exports:

```js
export class TetrisAudio {
  constructor()            // no args; does NOT create AudioContext yet
  unlock()                 // call on first user gesture; creates/resumes ctx, starts music
  setMuted(bool)           // master mute (music + SFX); returns current state
  get muted()              // boolean
  playSfx(name)            // name: 'move'|'rotate'|'softDrop'|'hardDrop'|'lock'|
                           //       'clear1'|'clear2'|'clear3'|'tetris'|'tspin'|
                           //       'hold'|'levelUp'|'gameOver'|'start'|'pause'
  startMusic()             // idempotent; starts the Korobeiniki loop
  stopMusic()              // stops loop (used on pause/game-over)
}
```

### Music
- **Korobeiniki** (Tetris theme A), E minor, ~149 BPM. The exact note data is in
  `assets/melody.json` (committed): `{division, tracks: [[[startSec, midiNote, durSec], ...], ...]}` —
  track[0]=melody, track[1]=harmony, track[2]=bass, track[3]=accompaniment.
  **Use this data verbatim** for note timing/pitch; do not re-transcribe from memory.
- Synthesis (all procedural Web Audio):
  - melody: square wave, gain ~0.16, slight lowpass (~2.5 kHz)
  - harmony: triangle, gain ~0.10
  - bass: sawtooth through lowpass (~400 Hz), gain ~0.18
  - accompaniment: short triangle plucks, gain ~0.07
- Looping: schedule notes ahead with a lookahead timer (e.g. every 25 ms,
  schedule anything within the next 120 ms); loop point = end of track data.
  Must survive tab throttling gracefully (no crash; may drift slightly).
- Music starts only after `unlock()` (browser autoplay policy) and stops on
  pause/game-over, resumes on resume/restart.

### SFX design (procedural, short, non-clashing with music)
- move: tiny blip ~20 ms, square 660 Hz, gain 0.05
- rotate: 30 ms sweep 440→587 Hz, gain 0.06
- softDrop: 15 ms tick 220 Hz, gain 0.04 (throttle: max once per 50 ms)
- hardDrop: noise burst 60 ms + low thump 90 Hz sine decay, gain 0.12
- lock: 30 ms 180 Hz square, gain 0.07
- clear1/2/3: rising arpeggio (C5-E5-G5 / add B5 / add D6), triangle, ~120 ms total
- tetris: bigger 4-note fanfare + noise shimmer, ~250 ms, gain 0.14
- tspin: quick two-tone "ding" 880→1319 Hz, ~150 ms
- hold: soft 523 Hz blip, 40 ms
- levelUp: ascending 3-note run (A4-C#5-E5), 200 ms
- gameOver: descending minor phrase (E5-D5-B4-G4), sawtooth lowpass, ~700 ms
- start/pause: single soft blip

All SFX routed through a master gain node so `setMuted` kills everything in one
place. Mute state persists to `localStorage('tetris.muted')`.

## 2. UI wiring (`js/ui.js`)

- Create ONE `TetrisAudio` instance; call `unlock()` on first keydown/touch.
- Map engine events (already emitted via `onEvent`: `clear`, `levelUp`,
  `gameOver`, etc.) + input actions to `playSfx(...)`.
- Mute button in the HUD header: 🔊/🔇 toggle, keyboard shortcut **M**.
- Music follows game state: start on `start()`, stop on pause/game-over.

## 3. Animations (canvas, no libraries)

All animations are additive overlays — the board must remain fully readable at
all times; nothing may block input or change engine timing.

1. **Line clear**: when a clear event fires, flash the cleared rows white for
   ~250 ms with a horizontal wipe (left→right gradient sweep), then remove.
   Implementation: UI keeps a `clearAnim {rows, t0}` state; during the anim it
   draws those rows as filled + sweeping highlight on top of normal render.
   The engine already removes rows immediately — so the animation is purely
   visual (UI snapshots which rows cleared from the event payload).
2. **Hard drop trail**: for ~150 ms after a hard drop, draw a fading vertical
   streak under the piece's final column footprint (alpha decays 0.35→0).
3. **Level up flash**: HUD level number pulses scale 1→1.4→1 over 400 ms +
   brief golden tint on the board border for 600 ms.
4. **Game over**: overlay fades in (alpha 0→1, 500 ms) instead of popping;
   final score counts up from 0 to final value over ~800 ms.
5. **Piece lock pop**: on lock, the newly settled cells draw a 60 ms bright
   outline pulse (white, alpha 0.5→0).

Animation state lives in `ui.js` only; driven by the existing rAF loop with
`performance.now()` timestamps. No new timers that could drift from render.

## 4. Acceptance gates (subagent must satisfy ALL)

1. `npm test` — all v1 tests still pass, **plus** a new `tests/audio.test.js`:
   - imports `js/audio.js` in Node without error (no AudioContext at import)
   - `TetrisAudio` instantiates; `setMuted(true)` returns true; `playSfx('lock')`
     does not throw when ctx is absent (must no-op safely before unlock)
   - melody.json parses, has 4 tracks, all notes have start>=0 and dur>0
2. `node --input-type=module -e "import('./js/ui.js').then(()=>console.log('ui ok'))"` passes
3. Autoplayer still plays full games to game-over (existing test green)
4. No console errors in a real browser session (verified by parent, not subagent)

## 5. Style rules
- Vanilla JS ESM only; no dependencies; no build step.
- Keep functions small; comment non-obvious audio math.
- Do NOT modify `js/engine.js`, `js/srs.js`, or any v1 test file.
- Commit nothing — parent handles git.
