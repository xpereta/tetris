// js/ui.js — canvas rendering, keyboard/touch input, HUD for the Tetris engine.
//
// Structure (per CONTRACT.md): pure helpers at the top (DOM-free), then
// `export function initUI(root)` which does all browser work. The module top
// level never touches document/window, so it can be imported in Node (gate C).

import { Game, BOARD_WIDTH, VISIBLE_TOP_ROW } from './engine.js';
import { SHAPES } from './srs.js';

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
const FLASH_MS = 220; // line-clear flash duration

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

  // ------------------------------------------------------------- game + events
  let flash = null; // { until, lines } — line-clear feedback
  const game = new Game({
    onEvent: (e) => {
      if (e.type === 'clear') flash = { until: performance.now() + FLASH_MS, lines: e.lines };
    },
  });

  // Debug/test hook: exposes the live game instance for headless verification.
  if (typeof window !== 'undefined') window.__tetrisGame = game;

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

    // line-clear flash: fading white band over the bottom rows
    if (flash && now < flash.until) {
      const a = ((flash.until - now) / FLASH_MS) * 0.45;
      bctx.fillStyle = `rgba(255,255,255,${a.toFixed(3)})`;
      bctx.fillRect(0, H - Math.min(flash.lines, 20) * cell, W, Math.min(flash.lines, 20) * cell);
    } else if (flash) {
      flash = null;
    }
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
  function drawOverlays() {
    const st = game.state;
    if (st === lastOverlayState) return;
    lastOverlayState = st;
    if (st === 'idle') {
      overlayTitle.textContent = 'TETRIS';
      overlaySub.textContent = 'Press Enter to start\n(tap here on mobile)';
      overlay.classList.remove('hidden');
    } else if (st === 'paused') {
      overlayTitle.textContent = 'PAUSED';
      overlaySub.textContent = 'Press P or Esc to resume';
      overlay.classList.remove('hidden');
    } else if (st === 'over') {
      overlayTitle.textContent = 'GAME OVER';
      overlaySub.textContent = `Final score: ${game.score}\n\nPress Enter to restart`;
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
    setStat(levelEl, game.level);
    setStat(linesEl, game.lines);
    drawOverlays();
  }

  // ------------------------------------------------------------------- input

  const das = { dir: 0, nextRepeat: 0 }; // horizontal auto-repeat state
  const sd = { held: false, next: 0 }; // soft drop repeat state

  function moveDir(dir) {
    if (dir === -1) game.moveLeft();
    else game.moveRight();
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

  function togglePause() {
    if (game.state === 'playing') game.pause();
    else if (game.state === 'paused') game.resume();
  }

  function startOrRestart() {
    if (game.state === 'idle' || game.state === 'over') game.start();
  }

  const GAME_KEYS = new Set([
    'ArrowLeft', 'ArrowRight', 'ArrowDown', 'ArrowUp', ' ',
    'x', 'X', 'z', 'Z', 'c', 'C', 'Shift', 'p', 'P', 'Escape', 'Enter',
  ]);

  window.addEventListener('keydown', (e) => {
    if (!GAME_KEYS.has(e.key)) return;
    e.preventDefault(); // stop page scroll on Space/arrows
    if (e.repeat) return; // OS repeat ignored — DAS/ARR handled in the frame loop
    const now = performance.now();
    switch (e.key) {
      case 'ArrowLeft': pressDir(-1, now); break;
      case 'ArrowRight': pressDir(1, now); break;
      case 'ArrowDown':
        if (game.state === 'playing') {
          sd.held = true;
          game.softDrop();
          sd.next = now + SOFT_REPEAT_MS;
        }
        break;
      case 'ArrowUp': case 'x': case 'X':
        if (game.state === 'playing') game.rotateCW();
        break;
      case 'z': case 'Z':
        if (game.state === 'playing') game.rotateCCW();
        break;
      case ' ':
        if (game.state === 'playing') game.hardDrop();
        else startOrRestart();
        break;
      case 'c': case 'C': case 'Shift':
        if (game.state === 'playing') game.holdPiece();
        break;
      case 'p': case 'P': case 'Escape':
        togglePause();
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
      case 'rotate': if (game.state === 'playing') game.rotateCW(); break;
      case 'drop': if (game.state === 'playing') game.hardDrop(); else startOrRestart(); break;
      case 'hold': if (game.state === 'playing') game.holdPiece(); break;
    }
  };
  for (const btn of touchBar.querySelectorAll('button')) {
    btn.addEventListener('pointerdown', (e) => {
      e.preventDefault();
      doAction(btn.dataset.act, performance.now());
    });
  }
  const clearTouch = () => { das.dir = 0; sd.held = false; };
  window.addEventListener('pointerup', clearTouch);
  window.addEventListener('pointercancel', clearTouch);

  // Overlay tap: start / resume.
  overlay.addEventListener('click', () => {
    if (game.state === 'paused') game.resume();
    else startOrRestart();
  });

  // Auto-pause when the tab loses focus.
  const autoPause = () => { if (game.state === 'playing') game.pause(); };
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
      // Soft drop repeat while ArrowDown held.
      if (sd.held && now >= sd.next) {
        while (now >= sd.next) {
          game.softDrop();
          sd.next += SOFT_REPEAT_MS;
        }
      }
      // Gravity: pace tick() with the engine's current gravityMs getter.
      acc += dt;
      let gms = game.gravityMs;
      while (acc >= gms) {
        game.tick();
        acc -= gms;
        gms = game.gravityMs; // level may have changed mid-frame
      }
    } else {
      acc = 0;
    }

    drawAll(now);
  }

  window.addEventListener('resize', resize);
  window.addEventListener('orientationchange', () => setTimeout(resize, 120));

  resize();
  requestAnimationFrame(frame);

  if (typeof window !== 'undefined') window.__tetris = { game }; // debug/test hook
  return { game }; // exposed for debugging / future tests
}

// Auto-init in the browser (module scripts run after DOM parse). No-op in Node.
if (typeof document !== 'undefined' && typeof window !== 'undefined') {
  const app = document.getElementById('app');
  if (app) initUI(app);
}
