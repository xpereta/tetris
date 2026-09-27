// js/ui.js — canvas rendering, keyboard/touch input, HUD for the Tetris engine.
//
// Structure (per CONTRACT.md): pure helpers at the top (DOM-free), then
// `export function initUI(root)` which does all browser work. The module top
// level never touches document/window, so it can be imported in Node (gate C).

import { Game, BOARD_WIDTH, VISIBLE_TOP_ROW } from './engine.js';
import { SHAPES } from './srs.js';
import { TetrisAudio } from './audio.js';
import { ParticleSystem } from './particles.js'; // v3: particle effects (CONTRACT-V3 §1)

export const COLORS = {
  I: '#3fd8f0',
  O: '#ffd54a',
  T: '#b06ef2',
  S: '#59d97e',
  Z: '#ff5c5c',
  J: '#5b8cff',
  L: '#ffa14e',
};

const DAS_MS = 167; // delayed auto shift
const ARR_MS = 33; // auto repeat rate after DAS
const SOFT_REPEAT_MS = 30; // soft drop repeat while ArrowDown held
// v2 animation timings (CONTRACT-V2 §3) — all driven by the rAF loop, no timers.
const CLEAR_MS = 250;       // line-clear flash + left→right wipe duration
const TRAIL_MS = 150;       // hard-drop trail fade (alpha 0.35 → 0)
const LEVEL_PULSE_MS = 400; // level number scale pulse 1 → 1.4 → 1
const LEVEL_BORDER_MS = 600;// golden board-border tint after a level-up
const LOCKPOP_MS = 60;      // settled-cell white outline pulse (alpha 0.5 → 0)
const OVERLAY_FADE_MS = 500;// game-over overlay fade-in instead of popping
const SCORE_COUNT_MS = 800; // final score counts up from 0 over this long

// ---------------------------------------------------------------- pure helpers

/** Bounding box (in cells) of a piece at a rotation state. */
export function pieceBounds(type, rot = 0) {
  let minC = Infinity, maxC = -Infinity, minR = Infinity, maxR = -Infinity;
  for (const [c, r] of SHAPES[type][rot]) {
    if (c < minC) minC = c;
    if (c > maxC) maxC = c;
    if (r < minR) minR = r;
    if (r > maxR) maxR = r;
  }
  return { minC, maxC, minR, maxR };
}

/** Draw one block with a simple bevel. ctx is any canvas 2D context. */
export function drawCell(ctx, px, py, cell, color) {
  const inset = Math.max(1, Math.floor(cell * 0.06));
  ctx.fillStyle = color;
  ctx.fillRect(px + inset, py + inset, cell - inset * 2, cell - inset * 2);
  // top highlight / bottom shade for a subtle 3D look
  const strip = Math.max(1, Math.floor(cell * 0.16));
  ctx.fillStyle = 'rgba(255,255,255,0.28)';
  ctx.fillRect(px + inset, py + inset, cell - inset * 2, strip);
  ctx.fillStyle = 'rgba(0,0,0,0.28)';
  ctx.fillRect(px + inset, py + cell - inset - strip, cell - inset * 2, strip);
}

/** Draw a piece at the top-left corner (ox, oy) of its bounding box. */
export function drawPiece(ctx, type, rot, cell, ox, oy, alpha = 1) {
  ctx.save();
  ctx.globalAlpha = alpha;
  for (const [c, r] of SHAPES[type][rot]) {
    drawCell(ctx, ox + c * cell, oy + r * cell, cell, COLORS[type]);
  }
  ctx.restore();
}

/** Draw a piece centered inside a slot of size slotW x slotH. */
export function drawPieceCentered(ctx, type, rot, cell, slotX, slotY, slotW, slotH) {
  const b = pieceBounds(type, rot);
  const w = (b.maxC - b.minC + 1) * cell;
  const h = (b.maxR - b.minR + 1) * cell;
  drawPiece(ctx, type, rot, cell, slotX + (slotW - w) / 2 - b.minC * cell, slotY + (slotH - h) / 2 - b.minR * cell);
}

// ------------------------------------------------- v3 settings (CONTRACT-V3 §2)

const SETTINGS_KEY = 'tetris.settings';
export const DEFAULT_SETTINGS = { particles: true, trail: true, intensity: 1 }; // Med
const INTENSITY_STEPS = [0.5, 1, 2]; // Low / Med / High spawn-count multipliers (§2 table)
const INTENSITY_LABELS = ['Low', 'Med', 'High'];

/** localStorage or null — same guard pattern as the mute persistence in audio.js. */
function settingsStorage() {
  if (typeof window === 'undefined') return null;
  try { return window.localStorage || null; } catch { return null; }
}

/** Load persisted settings with safe fallbacks: corrupt/missing → defaults (§2). */
export function loadSettings() {
  const out = { ...DEFAULT_SETTINGS };
  const s = settingsStorage();
  if (!s) return out;
  try {
    const raw = s.getItem(SETTINGS_KEY);
    if (raw == null) return out;
    const p = JSON.parse(raw);
    if (p && typeof p === 'object') {
      if (typeof p.particles === 'boolean') out.particles = p.particles;
      if (typeof p.trail === 'boolean') out.trail = p.trail;
      if (Number.isInteger(p.intensity) && p.intensity >= 0 && p.intensity <= 2) out.intensity = p.intensity;
    }
  } catch { /* corrupt JSON → defaults */ }
  return out;
}

/** Persist settings as JSON. try/catch + window guard, like the mute persistence. */
export function saveSettings(settings) {
  const s = settingsStorage();
  if (!s) return;
  try {
    s.setItem(SETTINGS_KEY, JSON.stringify({
      particles: !!settings.particles,
      trail: !!settings.trail,
      intensity: Math.max(0, Math.min(2, settings.intensity | 0)),
    }));
  } catch { /* storage full/blocked — ignore */ }
}

/** Spawn-count multiplier for the current intensity step (§2): round up, min 1. */
export function spawnCount(base, intensity) {
  if (base <= 0) return 0;
  const m = INTENSITY_STEPS[Math.max(0, Math.min(2, intensity | 0))] ?? 1;
  return Math.max(1, Math.ceil(base * m)); // min 1 when the master switch is on
}

/** Visible-row info for fully filled rows in a 40-row board: [{vr, colors}].
 * Pure — unit-testable without DOM. The engine emits 'lock' BEFORE it removes
 * full rows, so ui.js snapshots this right after each lock to know exactly
 * which rows the clear wipe/spray must target (v3 bugfix: they are NOT always
 * the bottom N visible rows) and what colors those cells had. */
export function fullVisibleRows(board) {
  const out = [];
  for (let r = VISIBLE_TOP_ROW; r < board.length; r++) {
    if (board[r].every((c) => c !== null)) {
      const colors = [...new Set(board[r])]; // distinct piece types in the row
      out.push({ vr: r - VISIBLE_TOP_ROW, colors });
    }
  }
  return out;
}

// ------------------------------------------------------------------- UI init

let _initialized = false;

export function initUI(root = document.getElementById('app')) {
  if (_initialized || typeof document === 'undefined') return null;
  _initialized = true;

  const boardCanvas = root.querySelector('#board');
  const holdBox = root.querySelector('#hold-box');
  const holdCanvas = root.querySelector('#hold-canvas');
  const nextCanvas = root.querySelector('#next-canvas');
  const scoreEl = root.querySelector('#score');
  const levelEl = root.querySelector('#level');
  const linesEl = root.querySelector('#lines');
  const overlay = root.querySelector('#overlay');
  const overlayTitle = root.querySelector('#overlay-title');
  const overlaySub = root.querySelector('#overlay-sub');
  const boardWrap = root.querySelector('#board-wrap');
  const touchBar = document.getElementById('touch');
  // v2 §3.3: transforms don't apply to plain inline elements — make the level
  // value a block-level box so its scale pulse renders (layout unchanged).
  levelEl.style.display = 'inline-block';

  // ------------------------------------------------------------- game + events
  const audio = new TetrisAudio(); // v2: one shared instance (CONTRACT-V2 §1/§2)
  let clearAnim = null;   // { rows, t0 } — line-clear flash/wipe (visual only)
  let pendingClearRows = []; // visible rows full at last lock — ground truth for the wipe
  let dropTrail = null;   // { cols:[{c,top,bottom}], t0 } — hard-drop streaks
  let lockPop = null;     // { cells:[[cx,cy]], t0 } — settled-cell outline pulse
  let levelPulseT0 = 0;   // timestamp of last level-up (HUD scale pulse)
  let levelBorderT0 = 0;  // timestamp of last level-up (golden board-border tint)
  let overFadeT0 = 0;     // game-over overlay fade-in start
  // v3: particle system + settings (CONTRACT-V3 §1/§2). Particles are purely
  // visual — they never touch engine timing or input.
  const particles = new ParticleSystem();
  const settings = loadSettings();
  const game = new Game({
    onEvent: (e) => {
      if (e.type === 'clear') {
        // Ground truth: the rows snapshotted at lock time (the engine emits
        // 'lock' before removing full rows — they are NOT always bottom-N).
        const snap = pendingClearRows;
        const rows = snap.length ? snap.map((s) => s.vr) : Array.from({ length: Math.min(e.lines, 20) }, (_, i) => 20 - e.lines + i);
        clearAnim = { rows, t0: performance.now() };
        spawnClearRows(rows, snap.length ? snap : null); // v3 §3: spray on the ACTUAL cleared rows
        if (e.tSpin && e.lines > 0) audio.playSfx('tspin');
        else if (e.lines === 4) audio.playSfx('tetris');
        else if (e.lines >= 1) audio.playSfx(`clear${Math.min(e.lines, 3)}`);
      } else if (e.type === 'lock') {
        // Snapshot NOW: the board already holds the just-locked cells and the
        // full rows are still present — this is ground truth for the clear FX.
        pendingClearRows = fullVisibleRows(game.board);
        // §3.5: pulse the newly settled cells (visible rows only).
        const cells = [];
        for (const [cx, cy] of game.cellsOf(e.piece, e.x, e.y, e.rot)) {
          if (cy >= VISIBLE_TOP_ROW) cells.push([cx, cy]);
        }
        lockPop = { cells, t0: performance.now() };
        spawnLockBursts(e.piece, e.x, e.y, e.rot); // v3 §3: particle burst per locked cell
        audio.playSfx('lock');
      } else if (e.type === 'hold') {
        audio.playSfx('hold');
      } else if (e.type === 'levelup') {
        levelPulseT0 = performance.now(); // §3.3: HUD scale pulse
        levelBorderT0 = performance.now(); // §3.3: golden board-border tint
        audio.playSfx('levelUp');
      } else if (e.type === 'gameover') {
        overFadeT0 = performance.now(); // §3.4: fade-in overlay + score count-up
        audio.stopMusic();
        audio.playSfx('gameOver');
      }
    },
  });

  // Debug/test hooks: expose live instances for headless verification.
  if (typeof window !== 'undefined') {
    window.__tetrisGame = game;
    window.__tetrisAudio = audio;
    window.__tetrisParticles = particles; // v3 §2
    window.__tetrisSettings = settings;   // v3 §2 — live reference, mutated in place
  }

  // ------------------------------------------------------------- canvas sizing
  let cell = 28;
  const dprOf = () => Math.max(1, window.devicePixelRatio || 1);

  function sizeCanvas(canvas, w, h) {
    const dpr = dprOf();
    canvas.width = Math.round(w * dpr);
    canvas.height = Math.round(h * dpr);
    canvas.style.width = w + 'px';
    canvas.style.height = h + 'px';
    const ctx = canvas.getContext('2d');
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    return ctx;
  }

  function computeLayout() {
    const touchPad = document.body.classList.contains('touch-mode') ? 130 : 0;
    const availH = Math.max(240, window.innerHeight - 56 - touchPad);
    const wrapW = boardWrap.clientWidth || Math.max(200, window.innerWidth - 380);
    const availW = Math.min(wrapW, 560);
    cell = Math.floor(Math.min(availH / 20, availW / BOARD_WIDTH));
    cell = Math.max(14, Math.min(cell, 48));
  }

  let bctx; // board context (logical pixels)
  const MINI_CELL = 15;
  const HOLD_W = 80, HOLD_H = 62;
  const NEXT_W = 80, SLOT_H = 52, NEXT_H = SLOT_H * 5 + 4;

  function resize() {
    computeLayout();
    bctx = sizeCanvas(boardCanvas, BOARD_WIDTH * cell, 20 * cell);
    holdCtx = sizeCanvas(holdCanvas, HOLD_W, HOLD_H);
    nextCtx = sizeCanvas(nextCanvas, NEXT_W, NEXT_H);
    holdSig = ''; // force redraw
    nextSig = '';
  }

  let holdCtx, nextCtx;

  // ------------------------------------------------------------------ drawing

  function drawBoard(now) {
    const W = BOARD_WIDTH * cell, H = 20 * cell;
    bctx.clearRect(0, 0, W, H);

    // faint grid
    bctx.strokeStyle = 'rgba(130,160,200,0.07)';
    bctx.lineWidth = 1;
    bctx.beginPath();
    for (let c = 1; c < BOARD_WIDTH; c++) {
      bctx.moveTo(c * cell + 0.5, 0);
      bctx.lineTo(c * cell + 0.5, H);
    }
    for (let r = 1; r < 20; r++) {
      bctx.moveTo(0, r * cell + 0.5);
      bctx.lineTo(W, r * cell + 0.5);
    }
    bctx.stroke();

    // settled blocks — only the visible rows (20..39)
    for (let vr = 0; vr < 20; vr++) {
      const row = game.board[VISIBLE_TOP_ROW + vr];
      for (let c = 0; c < BOARD_WIDTH; c++) {
        const t = row[c];
        if (t) drawCell(bctx, c * cell, vr * cell, cell, COLORS[t]);
      }
    }

    // ghost piece (semi-transparent landing preview)
    const cur = game.current;
    if (cur && (game.state === 'playing' || game.state === 'paused')) {
      const gy = game.ghostY;
      bctx.save();
      bctx.globalAlpha = 0.32;
      for (const [cx, cy] of game.cellsOf(cur.type, cur.x, gy, cur.rot)) {
        if (cy < VISIBLE_TOP_ROW) continue;
        const px = cx * cell, py = (cy - VISIBLE_TOP_ROW) * cell;
        bctx.fillStyle = COLORS[cur.type];
        bctx.fillRect(px + 2, py + 2, cell - 4, cell - 4);
      }
      bctx.restore();

      // current piece
      for (const [cx, cy] of game.cellsOf(cur.type, cur.x, cur.y, cur.rot)) {
        if (cy < VISIBLE_TOP_ROW) continue;
        drawCell(bctx, cx * cell, (cy - VISIBLE_TOP_ROW) * cell, cell, COLORS[cur.type]);
      }
    }

    // v2 §3.1 line-clear flash: white fill + left→right wipe over cleared rows.
    if (clearAnim) {
      const p = Math.min(1, (now - clearAnim.t0) / CLEAR_MS);
      if (p < 1) {
        for (const vr of clearAnim.rows) {
          const py = vr * cell;
          bctx.fillStyle = 'rgba(255,255,255,0.85)'; // flash the row white
          bctx.fillRect(0, py, W, cell);
        }
        // horizontal wipe: a bright band sweeps left→right across the rows
        const x = p * (W + 60) - 30;
        const grad = bctx.createLinearGradient(x - 45, 0, x + 15, 0);
        grad.addColorStop(0, 'rgba(255,255,255,0)');
        grad.addColorStop(1, `rgba(255,255,255,${(0.9 * (1 - p)).toFixed(3)})`);
        bctx.fillStyle = grad;
        const top = clearAnim.rows[0] * cell;
        const h = (clearAnim.rows.length) * cell;
        bctx.fillRect(x - 45, top, 60, h);
      } else {
        clearAnim = null; // engine already removed the rows — purely visual
      }
    }

    // v2 §3.2 hard-drop trail: fading vertical streaks under the final footprint.
    if (dropTrail) {
      const p = Math.min(1, (now - dropTrail.t0) / TRAIL_MS);
      if (p < 1) {
        bctx.save();
        for (const seg of dropTrail.cols) {
          const a = 0.35 * (1 - p); // alpha decays 0.35 → 0
          const x = seg.c * cell + cell * 0.2;
          const w = cell * 0.6;
          bctx.fillStyle = `rgba(255,255,255,${a.toFixed(3)})`;
          bctx.fillRect(x, seg.top * cell, w, (seg.bottom - seg.top + 1) * cell);
        }
        bctx.restore();
      } else {
        dropTrail = null;
      }
    }

    // v2 §3.5 piece-lock pop: bright white outline pulse on settled cells.
    if (lockPop) {
      const p = Math.min(1, (now - lockPop.t0) / LOCKPOP_MS);
      if (p < 1) {
        bctx.save();
        bctx.strokeStyle = `rgba(255,255,255,${(0.5 * (1 - p)).toFixed(3)})`; // 0.5 → 0
        bctx.lineWidth = 2;
        for (const [cx, cy] of lockPop.cells) {
          const px = cx * cell, py = (cy - VISIBLE_TOP_ROW) * cell;
          bctx.strokeRect(px + 1.5, py + 1.5, cell - 3, cell - 3);
        }
        bctx.restore();
      } else {
        lockPop = null;
      }
    }

    // v3 §1: particles on top of everything (board pixel space — no transform).
    if (particles.count > 0) particles.draw(bctx);
  }

  let holdSig = '';
  function drawHold() {
    const sig = `${game.hold}|${game.canHold}`;
    if (sig === holdSig) return;
    holdSig = sig;
    holdCtx.clearRect(0, 0, HOLD_W, HOLD_H);
    if (game.hold) drawPieceCentered(holdCtx, game.hold, 0, MINI_CELL, 0, 0, HOLD_W, HOLD_H);
    holdBox.classList.toggle('dim', !game.canHold);
  }

  let nextSig = '';
  function drawNext() {
    const sig = game.queue.slice(0, 5).join('');
    if (sig === nextSig) return;
    nextSig = sig;
    nextCtx.clearRect(0, 0, NEXT_W, NEXT_H);
    for (let i = 0; i < 5; i++) {
      const t = game.queue[i];
      if (!t) break;
      drawPieceCentered(nextCtx, t, 0, MINI_CELL, 0, 2 + i * SLOT_H, NEXT_W, SLOT_H);
    }
  }

  function setStat(el, v) {
    const s = String(v);
    if (el.textContent !== s) el.textContent = s;
  }

  let lastOverlayState = null;
  function drawOverlays(now) {
    const st = game.state;
    if (st === 'over') {
      // v2 §3.4: fade the overlay in over OVERLAY_FADE_MS, count score up over
      // SCORE_COUNT_MS; once done, stop re-evaluating every frame.
      const t = now - overFadeT0;
      if (lastOverlayState !== 'over' || t < SCORE_COUNT_MS) {
        overlay.style.opacity = Math.min(1, t / OVERLAY_FADE_MS).toFixed(3);
        const shown = Math.round(game.score * Math.min(1, t / SCORE_COUNT_MS));
        if (overlayTitle.textContent !== 'GAME OVER') {
          overlayTitle.textContent = 'GAME OVER';
          overlay.classList.remove('hidden');
        }
        const sub = `Final score: ${shown}\n\nPress Enter to restart`;
        if (overlaySub.textContent !== sub) overlaySub.textContent = sub;
      }
      if (t >= SCORE_COUNT_MS) lastOverlayState = 'over'; // done animating
      return;
    }
    if (st === lastOverlayState) return;
    lastOverlayState = st;
    overlay.style.opacity = ''; // reset any fade state for other overlays
    if (st === 'idle') {
      overlayTitle.textContent = 'TETRIS';
      overlaySub.textContent = 'Press Enter to start\n(tap here on mobile)';
      overlay.classList.remove('hidden');
    } else if (st === 'paused') {
      overlayTitle.textContent = 'PAUSED';
      overlaySub.textContent = 'Press P or Esc to resume';
      overlay.classList.remove('hidden');
    } else {
      overlay.classList.add('hidden');
    }
  }

  function drawAll(now) {
    drawBoard(now);
    drawHold();
    drawNext();
    setStat(scoreEl, game.score);
    // v2 §3.3: level number pulses scale 1 → 1.4 → 1 over LEVEL_PULSE_MS.
    const lp = now - levelPulseT0;
    if (levelPulseT0 && lp < LEVEL_PULSE_MS) {
      const s = 1 + 0.4 * Math.sin(Math.PI * (lp / LEVEL_PULSE_MS)); // 1→1.4→1
      levelEl.style.transform = `scale(${s.toFixed(3)})`;
    } else if (levelPulseT0) {
      levelPulseT0 = 0;
      levelEl.style.transform = '';
    }
    setStat(levelEl, game.level);
    setStat(linesEl, game.lines);
    // v2 §3.3: brief golden tint on the board border for LEVEL_BORDER_MS.
    const lb = now - levelBorderT0;
    if (levelBorderT0 && lb < LEVEL_BORDER_MS) {
      const a = 1 - lb / LEVEL_BORDER_MS;
      boardCanvas.style.boxShadow = `0 0 ${Math.round(24 + 36 * a)}px rgba(255, 200, 80, ${(0.7 * a).toFixed(3)})`;
    } else if (levelBorderT0) {
      levelBorderT0 = 0;
      boardCanvas.style.boxShadow = '';
    }
    drawOverlays(now);
  }

  // ------------------------------------------------------------------- input

  const das = { dir: 0, nextRepeat: 0 }; // horizontal auto-repeat state
  const sd = { held: false, next: 0 }; // soft drop repeat state

  function moveDir(dir) {
    const ok = dir === -1 ? game.moveLeft() : game.moveRight();
    if (ok) audio.playSfx('move'); // SFX only on a successful step
  }

  function pressDir(dir, now) {
    if (das.dir === dir) return;
    das.dir = dir;
    moveDir(dir); // immediate first step
    das.nextRepeat = now + DAS_MS;
  }

  function releaseDir(dir) {
    if (das.dir === dir) das.dir = 0;
  }

  /** Hard drop + §3.2 trail: snapshot the final footprint before the lock. */
  function hardDropWithTrail() {
    const cur = game.current;
    if (!cur) return false;
    const gy = game.ghostY;
    const cols = new Map(); // col → vertical span of the landing cells (visible rows)
    for (const [cx, cy] of game.cellsOf(cur.type, cur.x, gy, cur.rot)) {
      if (cy < VISIBLE_TOP_ROW) continue;
      const vr = cy - VISIBLE_TOP_ROW;
      const seg = cols.get(cx);
      if (!seg) cols.set(cx, { c: cx, top: vr, bottom: vr });
      else { seg.top = Math.min(seg.top, vr); seg.bottom = Math.max(seg.bottom, vr); }
    }
    game.hardDrop(); // locks synchronously — `current` is gone afterwards
    dropTrail = { cols: [...cols.values()], t0: performance.now() };
    audio.playSfx('hardDrop');
    return true;
  }

  function rotate(dir) {
    const ok = dir === 1 ? game.rotateCW() : game.rotateCCW();
    if (ok) audio.playSfx('rotate');
  }

  // ------------------------------------------- v3 particle spawn wiring (§3)
  // All helpers are no-ops when settings.particles is off — checked ONCE here,
  // never per-particle. Coordinates: board pixel space of the visible 20 rows.

  /** Falling trail dot below the piece's bounding box (gravity tick / soft drop). */
  function spawnTrailDot() {
    if (!settings.particles || !settings.trail) return; // master + trail switches
    const cur = game.current;
    if (!cur) return;
    const b = pieceBounds(cur.type, cur.rot);
    const cx = (cur.x + (b.minC + b.maxC) / 2 + 0.5) * cell; // center x of the bounding box
    const bottomY = (cur.y + b.maxR - VISIBLE_TOP_ROW + 1) * cell; // just below the lowest row
    particles.spawnTrail(cx, bottomY + cell / 2, cell);
  }

  /** Lock: small burst per locked cell, capped at ~60 total (§3). */
  function spawnLockBursts(type, x, y, rot) {
    if (!settings.particles) return; // master switch — checked once
    const all = game.cellsOf(type, x, y, rot);
    let cells = [];
    for (const [cx, cy] of all) {
      if (cy >= VISIBLE_TOP_ROW && cy < 40) cells.push([cx, cy]); // visible rows only
    }
    if (!cells.length) return;
    const perCell = spawnCount(3, settings.intensity); // base 3 sparks/cell × intensity
    let total = 0;
    for (const [cx, cy] of cells) {
      if (total >= 60) break; // hard cap ~60 particles per lock
      const n = Math.min(perCell, 60 - total);
      particles.spawnBurst((cx + 0.5) * cell, (cy - VISIBLE_TOP_ROW + 0.5) * cell, COLORS[type], n);
      total += n;
    }
  }

  /** Line clear: spray across each ACTUAL cleared row (§3). `snap` is the
   * lock-time snapshot [{vr, colors}] — rows are no longer assumed to be the
   * bottom N (v3 bugfix); colors tint the sparks with the real cell types. */
  function spawnClearRows(rows, snap) {
    if (!settings.particles || !rows.length) return; // master switch — checked once
    const mult = INTENSITY_STEPS[Math.max(0, Math.min(2, settings.intensity | 0))] ?? 1;
    for (let i = 0; i < rows.length; i++) {
      const vr = rows[i];
      if (vr < 0 || vr >= 20) continue; // hidden-row clears: no visible spray
      const colors = snap && snap[i] ? snap[i].colors.map((t) => COLORS[t]) : null;
      particles.spawnClearRow((vr + 0.5) * cell, BOARD_WIDTH, cell, colors, Math.max(1, Math.round(BOARD_WIDTH * 3 * mult)));
    }
  }

  // v2 §2: mute button in the HUD header + M shortcut. Created here so no
  // index.html change is needed; inline styles keep it dependency-free.
  const statsBox = root.querySelector('.stats');
  const muteBtn = document.createElement('button');
  muteBtn.id = 'mute-btn';
  muteBtn.type = 'button';
  muteBtn.title = 'Toggle sound (M)';
  Object.assign(muteBtn.style, {
    margin: '2px auto 0', padding: '4px 10px', fontSize: '15px', lineHeight: '1',
    background: '#17233a', color: '#dce7f5', border: '1px solid #2c3e5c',
    borderRadius: '8px', cursor: 'pointer', font: 'inherit',
  });
  const syncMuteIcon = () => { muteBtn.textContent = audio.muted ? '🔇' : '🔊'; };
  const toggleMute = () => { audio.setMuted(!audio.muted); syncMuteIcon(); };
  muteBtn.addEventListener('click', (e) => { e.stopPropagation(); toggleMute(); });
  syncMuteIcon();
  statsBox.appendChild(muteBtn);

  // v3 §2: gear button + settings overlay panel. Reuses the pause-overlay visual
  // language (dark backdrop, centered card); created here so no index.html change.
  const gearBtn = document.createElement('button');
  gearBtn.id = 'settings-btn';
  gearBtn.type = 'button';
  gearBtn.title = 'Settings (S)';
  Object.assign(gearBtn.style, {
    margin: '2px auto 0', padding: '4px 10px', fontSize: '15px', lineHeight: '1',
    background: '#17233a', color: '#dce7f5', border: '1px solid #2c3e5c',
    borderRadius: '8px', cursor: 'pointer', font: 'inherit',
  });
  gearBtn.textContent = '\u2699'; // ⚙ — same style as the mute button
  statsBox.appendChild(gearBtn);

  const settingsPanel = document.createElement('div');
  settingsPanel.id = 'settings-panel';
  Object.assign(settingsPanel.style, {
    position: 'absolute', inset: '-1px', zIndex: '8', // above the game overlay (z-5)
    display: 'flex', alignItems: 'center', justifyContent: 'center',
    background: 'rgba(6, 10, 17, .78)', backdropFilter: 'blur(3px)', borderRadius: '6px',
  });
  const card = document.createElement('div');
  Object.assign(card.style, {
    width: '248px', background: '#101826', border: '1px solid #2c3e5c', borderRadius: '10px',
    padding: '16px 18px', display: 'flex', flexDirection: 'column', gap: '12px', textAlign: 'center',
  });
  const panelTitle = document.createElement('div');
  panelTitle.textContent = 'SETTINGS';
  Object.assign(panelTitle.style, { fontSize: '17px', letterSpacing: '3px', fontWeight: '700', color: '#eaf2ff' });
  card.appendChild(panelTitle);

  const makeRow = (label) => {
    const row = document.createElement('div');
    Object.assign(row.style, { display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: '8px' });
    const lab = document.createElement('span');
    lab.textContent = label;
    Object.assign(lab.style, { fontSize: '13px', color: '#9fb2cc' });
    row.appendChild(lab);
    return row;
  };
  const makeToggleBtn = (initial) => {
    const b = document.createElement('button');
    b.type = 'button';
    Object.assign(b.style, {
      padding: '4px 12px', fontSize: '13px', lineHeight: '1.2', cursor: 'pointer', font: 'inherit',
      background: '#17233a', color: '#dce7f5', border: '1px solid #2c3e5c', borderRadius: '8px',
    });
    b.textContent = initial ? 'ON' : 'OFF';
    return b;
  };

  const particlesToggle = makeToggleBtn(settings.particles);
  const trailToggle = makeToggleBtn(settings.trail);
  const intensityBtns = INTENSITY_LABELS.map((lab, i) => {
    const b = document.createElement('button');
    b.type = 'button';
    Object.assign(b.style, {
      padding: '4px 8px', fontSize: '12px', lineHeight: '1.2', cursor: 'pointer', font: 'inherit',
      background: '#17233a', color: '#dce7f5', border: '1px solid #2c3e5c', borderRadius: '8px',
    });
    b.textContent = lab;
    return b;
  });

  const rowParticles = makeRow('Particles');
  rowParticles.appendChild(particlesToggle);
  card.appendChild(rowParticles);
  const rowTrail = makeRow('Falling trail');
  rowTrail.appendChild(trailToggle);
  card.appendChild(rowTrail);
  const rowIntensity = makeRow('Intensity');
  const intensityGroup = document.createElement('div');
  Object.assign(intensityGroup.style, { display: 'flex', gap: '4px' });
  for (const b of intensityBtns) intensityGroup.appendChild(b);
  rowIntensity.appendChild(intensityGroup);
  card.appendChild(rowIntensity);

  const closeBtn = document.createElement('button');
  closeBtn.type = 'button';
  Object.assign(closeBtn.style, {
    marginTop: '2px', padding: '6px 10px', fontSize: '13px', lineHeight: '1.2', cursor: 'pointer', font: 'inherit',
    background: '#17233a', color: '#dce7f5', border: '1px solid #2c3e5c', borderRadius: '8px',
  });
  closeBtn.textContent = 'CLOSE (Esc)';
  card.appendChild(closeBtn);

  settingsPanel.appendChild(card);
  boardWrap.appendChild(settingsPanel);
  settingsPanel.classList.add('hidden'); // .hidden is display:none !important — overrides flex

  let settingsOpen = false;
  let pausedForSettings = false; // did WE pause the game? (never double-pause, §2)

  const syncSettingsUI = () => {
    particlesToggle.textContent = settings.particles ? 'ON' : 'OFF';
    trailToggle.textContent = settings.trail ? 'ON' : 'OFF';
    for (let i = 0; i < intensityBtns.length; i++) {
      intensityBtns[i].style.background = settings.intensity === i ? '#26406b' : '';
    }
  };

  function openSettingsMenu() {
    if (settingsOpen) return;
    settingsOpen = true;
    pausedForSettings = game.state === 'playing'; // reuse existing pause mechanics — no double-pause
    if (pausedForSettings) pauseGame();
    syncSettingsUI();
    settingsPanel.classList.remove('hidden');
  }

  function closeSettingsMenu() {
    if (!settingsOpen) return;
    settingsOpen = false;
    settingsPanel.classList.add('hidden');
    // Resume only the pause we caused — a user-initiated pause stays intact.
    const wasOurs = pausedForSettings;
    pausedForSettings = false;
    if (wasOurs && game.state === 'paused') resumeGame();
  }

  gearBtn.addEventListener('click', (e) => { e.stopPropagation(); openSettingsMenu(); });
  closeBtn.addEventListener('click', (e) => { e.stopPropagation(); closeSettingsMenu(); });
  settingsPanel.addEventListener('click', (e) => { if (e.target === settingsPanel) closeSettingsMenu(); }); // backdrop click

  const setSetting = (key, value) => { settings[key] = value; saveSettings(settings); syncSettingsUI(); };
  particlesToggle.addEventListener('click', () => setSetting('particles', !settings.particles));
  trailToggle.addEventListener('click', () => setSetting('trail', !settings.trail));
  intensityBtns.forEach((b, i) => b.addEventListener('click', () => setSetting('intensity', i)));

  function pauseGame() { game.pause(); audio.stopMusic(); audio.playSfx('pause'); }
  function resumeGame() { game.resume(); audio.startMusic(); }

  function togglePause() {
    if (game.state === 'playing') pauseGame();
    else if (game.state === 'paused') resumeGame();
  }

  function startOrRestart() {
    if (game.state === 'idle' || game.state === 'over') {
      game.start();
      audio.playSfx('start');
      audio.startMusic(); // idempotent — music follows the playing state (§2)
    }
  }

  const GAME_KEYS = new Set([
    'ArrowLeft', 'ArrowRight', 'ArrowDown', 'ArrowUp', ' ',
    'x', 'X', 'z', 'Z', 'c', 'C', 'Shift', 'p', 'P', 'Escape', 'Enter',
    'm', 'M', 's', 'S', // v3: S opens/closes the settings menu (§2)
  ]);

  window.addEventListener('keydown', (e) => {
    audio.unlock(); // first user gesture: create/resume AudioContext (§1/§2)
    if (!GAME_KEYS.has(e.key)) return;
    e.preventDefault(); // stop page scroll on Space/arrows
    if (e.repeat) return; // OS repeat ignored — DAS/ARR handled in the frame loop
    const now = performance.now();
    // v3 §2: while the settings menu is open, only S/Esc act — everything else
    // is swallowed so no game input leaks through. The game itself is paused.
    if (settingsOpen) {
      if (e.key === 's' || e.key === 'S') closeSettingsMenu();
      else if (e.key === 'Escape') closeSettingsMenu();
      return;
    }
    switch (e.key) {
      case 'ArrowLeft': pressDir(-1, now); break;
      case 'ArrowRight': pressDir(1, now); break;
      case 'ArrowDown':
        if (game.state === 'playing') {
          sd.held = true;
          if (game.softDrop()) { audio.playSfx('softDrop'); spawnTrailDot(); } // v3 §3: soft-drop trail
          sd.next = now + SOFT_REPEAT_MS;
        }
        break;
      case 'ArrowUp': case 'x': case 'X':
        if (game.state === 'playing') rotate(1);
        break;
      case 'z': case 'Z':
        if (game.state === 'playing') rotate(-1);
        break;
      case ' ':
        if (game.state === 'playing') hardDropWithTrail();
        else startOrRestart();
        break;
      case 'c': case 'C': case 'Shift':
        if (game.state === 'playing') game.holdPiece(); // SFX via the hold event
        break;
      case 'p': case 'P': case 'Escape':
        togglePause();
        break;
      case 's': case 'S':
        openSettingsMenu(); // v3 §2 — S opens/closes (closing handled above)
        break;
      case 'm': case 'M':
        toggleMute();
        break;
      case 'Enter':
        startOrRestart();
        break;
    }
  });

  window.addEventListener('keyup', (e) => {
    if (!GAME_KEYS.has(e.key)) return;
    e.preventDefault();
    switch (e.key) {
      case 'ArrowLeft': releaseDir(-1); break;
      case 'ArrowRight': releaseDir(1); break;
      case 'ArrowDown': sd.held = false; break;
    }
  });

  // Touch controls: shown on touch devices, wired to the same handlers.
  if ('ontouchstart' in window) {
    touchBar.classList.remove('hidden');
    document.body.classList.add('touch-mode');
  }
  const doAction = (act, now) => {
    switch (act) {
      case 'left': pressDir(-1, now); break;
      case 'right': pressDir(1, now); break;
      case 'rotate': if (game.state === 'playing') rotate(1); break;
      case 'drop': if (game.state === 'playing') hardDropWithTrail(); else startOrRestart(); break;
      case 'hold': if (game.state === 'playing') game.holdPiece(); break;
    }
  };
  for (const btn of touchBar.querySelectorAll('button')) {
    btn.addEventListener('pointerdown', (e) => {
      e.preventDefault();
      audio.unlock(); // first user gesture (§1/§2)
      doAction(btn.dataset.act, performance.now());
    });
  }
  const clearTouch = () => { das.dir = 0; sd.held = false; };
  window.addEventListener('pointerup', clearTouch);
  window.addEventListener('pointercancel', clearTouch);

  // Overlay tap: start / resume.
  overlay.addEventListener('click', () => {
    audio.unlock();
    if (game.state === 'paused') resumeGame();
    else startOrRestart();
  });

  // Auto-pause when the tab loses focus (music stops with it).
  const autoPause = () => { if (game.state === 'playing') pauseGame(); };
  window.addEventListener('blur', autoPause);
  document.addEventListener('visibilitychange', () => {
    if (document.hidden) autoPause();
  });

  // ------------------------------------------------------------------ main loop

  let last = performance.now();
  let acc = 0;

  function frame(now) {
    requestAnimationFrame(frame);
    const dt = Math.min(now - last, 250); // clamp: no gravity burst after tab switch
    last = now;

    if (game.state === 'playing') {
      // DAS/ARR horizontal auto-repeat.
      if (das.dir !== 0 && now >= das.nextRepeat) {
        while (now >= das.nextRepeat) {
          moveDir(das.dir);
          das.nextRepeat += ARR_MS;
        }
      }
      // Soft drop repeat while ArrowDown held (SFX throttled inside audio).
      if (sd.held && now >= sd.next) {
        while (now >= sd.next) {
          if (game.softDrop()) { audio.playSfx('softDrop'); spawnTrailDot(); } // v3 §3: soft-drop trail
          sd.next += SOFT_REPEAT_MS;
        }
      }
      // Gravity: pace tick() with the engine's current gravityMs getter.
      acc += dt;
      let gms = game.gravityMs;
      while (acc >= gms) {
        const curBefore = game.current; // identity check: tick() may lock + respawn
        const yBefore = curBefore ? curBefore.y : null;
        game.tick();
        acc -= gms;
        gms = game.gravityMs; // level may have changed mid-frame
        // v3 §3: falling trail — only when the SAME piece actually moved down.
        if (game.state === 'playing' && game.current === curBefore && yBefore !== null && curBefore.y > yBefore) {
          spawnTrailDot();
        }
      }
    } else {
      acc = 0;
    }

    // v3 §1: advance particle physics with the same clamped dt (visual only —
    // never touches engine timing or input).
    particles.update(dt);

    drawAll(now);
  }

  window.addEventListener('resize', resize);
  window.addEventListener('orientationchange', () => setTimeout(resize, 120));

  resize();
  requestAnimationFrame(frame);

  if (typeof window !== 'undefined') window.__tetris = { game, audio }; // debug/test hook
  return { game, audio }; // exposed for debugging / future tests
}

// Auto-init in the browser (module scripts run after DOM parse). No-op in Node.
if (typeof document !== 'undefined' && typeof window !== 'undefined') {
  const app = document.getElementById('app');
  if (app) initUI(app);
}
