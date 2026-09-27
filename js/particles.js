// js/particles.js — lightweight particle system for v3 effects (CONTRACT-V3 §1).
//
// Pure ESM, NO DOM access at import time: safe to instantiate in Node (gates 1/2).
// Coordinates are board pixel space ((0,0) = top-left of the visible board);
// ui.js translates game coords before calling. Physics: position + velocity
// (px/s), gravity ~600 px/s² for bursts/clears; trail dots fall straight with
// no horizontal spread. Lifetime 400–800 ms, alpha fades linearly to 0, size
// shrinks slightly over life. Hard cap: 600 particles (drop oldest on overflow).

const CAP = 600; // hard particle cap — spawning beyond it drops the oldest
const GRAVITY = 600; // px/s²
const TAU = Math.PI * 2;
// Fixed celebratory palette for line clears (§1) — removed-cell colors are not
// recoverable (the engine removes rows before emitting 'clear').
const CLEAR_PALETTE = ['#ffffff', '#ffd75e', '#6ee7ff'];

function rand(a, b) { return a + Math.random() * (b - a); }

export class ParticleSystem {
  constructor() {
    this._parts = []; // live particles, oldest first (order kept for cap drops)
    this._free = [];  // recycled particle objects — keeps update/draw allocation-light
  }

  get count() { return this._parts.length; }

  _alloc() {
    const p = this._free.pop();
    if (p) return p;
    // grav=false → constant velocity (trail dots fall straight, no gravity — §1).
    return { x: 0, y: 0, vx: 0, vy: 0, size: 1, alpha: 1, life: 1, age: 0, color: '#ffffff', grav: true };
  }

  /** Reserve room for n new particles, dropping the oldest first when over CAP. */
  _makeRoom(n) {
    const excess = this._parts.length + n - CAP;
    if (excess > 0) this._parts.splice(0, Math.min(excess, this._parts.length));
  }

  /** Lock: radial burst at pixel (x,y). ~30% of the sparks are white. */
  spawnBurst(x, y, color, n = 8) {
    if (n <= 0) return;
    this._makeRoom(n);
    for (let i = 0; i < n; i++) {
      const p = this._alloc();
      const a = Math.random() * TAU;
      const sp = rand(80, 300); // px/s in a random direction
      p.x = x; p.y = y;
      p.vx = Math.cos(a) * sp;
      p.vy = Math.sin(a) * sp;
      p.size = rand(2, 4);
      p.alpha = rand(0.75, 1);
      p.life = rand(400, 800); // ms
      p.age = 0;
      p.color = Math.random() < 0.3 ? '#ffffff' : color;
      p.grav = true;
      this._parts.push(p);
    }
  }

  /** Falling: exactly ONE dot below the piece (alpha ≤ 0.45, ~380 ms).
   * `fallSpeedPxPerSec` should match the piece's CURRENT fall speed so the dot
   * stays glued just below it — never running ahead of or overlapping the piece. */
  spawnTrail(x, y, fallSpeedPxPerSec) {
    const p = this._alloc();
    p.x = x; p.y = y;
    p.vx = 0; // straight down — no spread
    p.vy = Math.max(0, fallSpeedPxPerSec); // match the piece's speed (v3.1.1: was a fixed 2×cell px/s)
    p.size = rand(2, 3);
    p.alpha = rand(0.3, 0.45);
    p.life = rand(320, 420); // ~380 ms
    p.age = 0;
    p.color = '#ffffff';
    p.grav = false; // constant velocity — falls straight down
    this._makeRoom(1);
    this._parts.push(p);
  }

  /** Line clear: horizontal spray across a row (~widthCells×3 particles).
   * `colors` (optional) tints the sparks with the actual cleared-cell colors;
   * otherwise the fixed celebratory palette is used. `count` overrides n. */
  spawnClearRow(y, widthCells, cellPx, colors = null, count = 0) {
    const n = Math.max(1, count || Math.round(widthCells * 3));
    if (n <= 0) return;
    this._makeRoom(n);
    const w = Math.max(1, widthCells * cellPx); // full board width in px
    for (let i = 0; i < n; i++) {
      const p = this._alloc();
      const t = n === 1 ? 0.5 : i / (n - 1);
      p.x = t * w + rand(-cellPx * 0.2, cellPx * 0.2); // spread across the full width
      p.y = y + rand(-cellPx * 0.25, cellPx * 0.25);
      const dir = Math.random() < 0.5 ? -1 : 1;
      p.vx = dir * rand(40, 200); // mostly horizontal
      p.vy = -rand(30, 120); // upward kick (gravity pulls it back down)
      p.size = rand(2, 4);
      p.alpha = rand(0.75, 1);
      p.life = rand(400, 800);
      p.age = 0;
      if (colors && colors.length) {
        // ~25% white sparks over the real cleared-cell colors (v3.1).
        p.color = Math.random() < 0.25 ? '#ffffff' : colors[(Math.random() * colors.length) | 0];
      } else {
        p.color = CLEAR_PALETTE[(Math.random() * CLEAR_PALETTE.length) | 0];
      }
      p.grav = true; // recycled objects may carry grav=false from a trail dot
      this._parts.push(p);
    }
  }

  /** Remove all trail dots (grav=false) — called when a piece locks or is held,
   * so stale dots can't drift into the NEXT piece's body. Bursts/clears survive. */
  killTrails() {
    let w = 0;
    for (let i = 0; i < this._parts.length; i++) {
      const p = this._parts[i];
      if (!p.grav) { this._free.push(p); continue; } // recycle trail dots only
      this._parts[w++] = p;
    }
    this._parts.length = w;
  }

  /** Hard invariant for the falling trail: no trail dot may sit below yPx — that
   * would be IN FRONT of a downward-moving piece. Free physics + quantized
   * gravity can overshoot at high levels (several ticks per frame, one update),
   * so stragglers are snapped back to just above the line. Bursts/clears untouched. */
  clampTrailsAbove(yPx) {
    const limit = yPx - 2; // a hair above the piece's top edge (y grows downward)
    for (let i = 0; i < this._parts.length; i++) {
      const p = this._parts[i];
      if (!p.grav && p.y > limit) p.y = limit;
    }
  }

  /** Advance physics and cull dead particles. dt in ms. O(count), no allocation. */
  update(dtMs) {
    if (dtMs <= 0 || this._parts.length === 0) return;
    const dt = dtMs / 1000;
    let w = 0; // in-place compaction keeps oldest-first order for cap drops
    for (let i = 0; i < this._parts.length; i++) {
      const p = this._parts[i];
      p.age += dtMs;
      if (p.age >= p.life) { this._free.push(p); continue; } // recycle the object
      if (p.grav) p.vy += GRAVITY * dt;
      p.x += p.vx * dt;
      p.y += p.vy * dt;
      this._parts[w++] = p;
    }
    this._parts.length = w;
  }

  /** Render all particles. Only arc+fill — no shadows/blur/filters (mobile perf). */
  draw(ctx) {
    for (let i = 0; i < this._parts.length; i++) {
      const p = this._parts[i];
      const t = p.age / p.life; // 0 → 1 over life
      ctx.globalAlpha = p.alpha * (1 - t); // linear fade to 0
      ctx.fillStyle = p.color;
      const s = Math.max(0.5, p.size * (1 - 0.4 * t)); // shrink slightly over life
      ctx.beginPath();
      ctx.arc(p.x, p.y, s, 0, TAU);
      ctx.fill();
    }
    if (this._parts.length) ctx.globalAlpha = 1;
  }
}

export default ParticleSystem;
