# CONTRACT V3 — Particles & Settings Menu (additive; v1/v2 contracts unchanged)

v3 adds particle effects and a settings menu on top of v2. **Frozen:**
`js/engine.js`, `js/srs.js`, all v1/v2 test files, and the audio system in
`js/audio.js` (do not modify). New/changed:

- `js/particles.js` (NEW) — particle system, Node-safe pure ESM
- `js/ui.js` (MODIFIED) — spawn wiring + settings menu UI
- `tests/particles.test.js` (NEW)

## 1. Particle system (`js/particles.js`)

```js
export class ParticleSystem {
  constructor()                 // no DOM access; safe in Node
  get count()                   // live particle count
  spawnBurst(x, y, color, n = 8)        // lock: radial burst at pixel (x,y)
  spawnTrail(x, y, dyPx)             // falling: one small dot below the piece
  spawnClearRow(y, widthCells, cellPx)  // line clear: horizontal spray across row
  update(dtMs)                  // advance physics, cull dead; dt in ms
  draw(ctx2d)                   // render all particles (caller sets transform/clip)
}
```

- Coordinates are **board pixel space** (0,0 = top-left of the visible board);
  ui.js translates game coords before calling.
- Physics per particle: position, velocity (px/s), gravity ~600 px/s² for
  bursts/clears (trail dots fall straight, no spread), lifetime 350–700 ms,
  alpha fades linearly to 0, size shrinks slightly over life.
- `spawnBurst`: n particles in random directions, speed 60–240 px/s, color =
  the piece's CSS color (passed by ui.js), plus ~30% white sparks mixed in.
- `spawnTrail`: exactly ONE particle per call, size ~1.5–2.5 px, alpha ≤ 0.35,
  lifetime ~300 ms — must stay subtle.
- `spawnClearRow`: ~widthCells×2 particles along the row (x spread across full
  width), velocities mostly horizontal ± upward kick, colors from a fixed
  celebratory palette [white, gold #ffd75e, cyan #6ee7ff] chosen randomly —
  do NOT try to recover removed cell colors (engine removes rows before the
  event; documented judgment call).
- **Hard cap: 600 particles.** When spawning would exceed it, drop oldest.
  `update` must be O(count) and allocation-light (reuse where easy).
- `draw(ctx2d)` uses only fillRect or arc+fill — no shadows/blur/filters
  (perf on mobile).

## 2. Settings menu (`js/ui.js`)

A gear button (⚙, same style as the mute button) in the HUD stats box opens a
settings overlay panel (reuse the pause-overlay visual language; centered card):

| Control | Type | Default | Effect |
|---|---|---|---|
| Particles | toggle | ON | master switch for all particle effects |
| Falling trail | toggle | ON | only `spawnTrail` particles |
| Intensity | 3-step (Low/Med/High) | Med | spawn-count multiplier: Low=0.5, Med=1, High=2 (round up; min 1 when master on) |

- Keyboard: **S** opens/closes the menu; **Esc** closes it. While open, the
  game is paused (reuse existing pause mechanics — do not double-pause if
  already paused).
- Persist to `localStorage('tetris.settings')` as JSON `{particles, trail, intensity}`;
  load on boot with safe fallbacks (corrupt/missing → defaults). Wrap storage
  access in try/catch + `typeof window` guard like the mute persistence does.
- Expose debug hooks: `window.__tetrisParticles` (the ParticleSystem instance)
  and `window.__tetrisSettings` (live settings object reference).

## 3. Spawn wiring (`js/ui.js`)

- **Falling**: on each gravity tick or soft-drop that actually moves the piece
  down one row, call `spawnTrail(cx, bottomY + cell/2, cell)` where cx = center
  x of the piece's bounding box (board pixel space). Skip when paused/over.
- **Lock**: on the existing lock event (where v2 does the lock-pop), for each
  locked cell spawn a small burst — but cap total per lock at ~40 particles:
  if cells > 10, sample every k-th cell instead of all. Color = current piece's
  CSS color (ui.js already has the palette map).
- **Line clear**: on the existing clear event (where v2 starts the wipe), call
  `spawnClearRow(rowY, 10, cell)` for each cleared row index (bottom N rows of
  the visible board — same visual approximation as the v2 wipe; document it).
- All spawn calls must be no-ops when settings.particles is false (check once
  in a helper, not per-particle).

## 4. Acceptance gates (subagent must satisfy ALL)

1. `npm test` — all prior tests pass **plus** new `tests/particles.test.js`:
   - imports cleanly in Node; instantiates with no DOM
   - spawnBurst/spawnTrail/spawnClearRow increase `count`; update(dtMs) over
     enough time culls everything back to 0
   - cap: spawning 1000 particles leaves count ≤ 600
   - draw() does not throw against a stub ctx2d object (no-op methods)
2. `node --input-type=module -e "import('./js/ui.js').then(()=>console.log('ui ok'))"` passes
3. Autoplayer still plays full games to game-over (existing test green)
4. No console errors in real browser (verified by parent, not subagent)

## 5. Style rules
- Vanilla JS ESM only; no dependencies; no build step.
- Do NOT modify `js/engine.js`, `js/srs.js`, `js/audio.js`, or any existing test file.
- Keep the settings menu DOM creation inside ui.js (no index.html change needed).
- Commit nothing — parent handles git.
