// js/particles.js — lightweight particle system for v3 effects (CONTRACT-V3 §1).
//
// Pure ESM, NO DOM access at import time: safe to instantiate in Node (gates 1/2).
// Coordinates are board pixel space ((0,0) = top-left of the visible board);
// ui.js translates game coords before calling. Physics: position + velocity
// (px/s), gravity ~600 px/s² for bursts/clears; trail dots fall straight with
// no horizontal spread. Lifetime 350–700 ms, alpha fades linearly to 0, size
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
      const sp = rand(60, 240); // px/s in a random direction
      p.x = x; p.y = y;
      p.vx = Math.cos(a) * sp;
      p.vy = Math.sin(a) * sp;
      p.size = rand(1.5, 3.5);
      p.alpha = rand(0.7, 1);
      p.life = rand(350, 700); // ms
      p.age = 0;
      p.color = Math.random() < 0.3 ? '#ffffff' : color;
      p.grav = true;
      this._parts.push(p);
    }
  }

  /** Falling: exactly ONE subtle dot below the piece (alpha ≤ 0.35, ~300 ms). */
  spawnTrail(x, y, dyPx) {
    const p = this._alloc();
    p.x = x; p.y = y;
    p.vx = 0; // straight down — no spread
    p.vy = Math.max(0, dyPx) * 2; // gentle initial fall scaled to the cell size (judgment call: dyPx drives speed, not offset)
    p.size = rand(1.5, 2.5);
    p.alpha = rand(0.2, 0.35);
    p.life = rand(280, 340); // ~300 ms
    p.age = 0;
    p.color = '#ffffff';
    p.grav = false; // constant velocity — falls straight down
    this._makeRoom(1);
    this._parts.push(p);
  }

  /** Line clear: horizontal spray across a row (~widthCells×2 particles). */
  spawnClearRow(y, widthCells, cellPx) {
    const n = Math.max(1, Math.round(widthCells * 2));
    if (n <= 0) return;
    this._makeRoom(n);
    const w = Math.max(1, widthCells * cellPx); // full board width in px
    for (let i = 0; i < n; i++) {
      const p = this._alloc();
      const t = n === 1 ? 0.5 : i / (n - 1);
      p.x = t * w + rand(-cellPx * 0.2, cellPx * 0.2); // spread across the full width
      p.y = y + rand(-cellPx * 0.25, cellPx * 0.25);
      const dir = Math.random() < 0.5 ? -1 : 1;
      p.vx = dir * rand(40, 180); // mostly horizontal
      p.vy = -rand(20, 100); // upward kick (gravity pulls it back down)
      p.size = rand(1.5, 3);
      p.alpha = rand(0.7, 1);
      p.life = rand(350, 700);
      p.age = 0;
      p.color = CLEAR_PALETTE[(Math.random() * CLEAR_PALETTE.length) | 0];
      p.grav = true; // recycled objects may carry grav=false from a trail dot
      this._parts.push(p);
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
