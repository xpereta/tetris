// js/engine.js — PURE Tetris game logic (no DOM / browser APIs). ESM only.
// Implements the API contract in CONTRACT.md: SRS rotation with wall kicks,
// 7-bag randomizer (seeded mulberry32), guideline scoring (T-spins, b2b, combo),
// gravity formula, lock delay with move-reset cap, ghost piece, events.

import { SHAPES, getKicks } from './srs.js';

export const BOARD_WIDTH = 10;
export const BOARD_HEIGHT = 40; // rows 0..19 hidden above the visible area (rows 20..39)
export const VISIBLE_TOP_ROW = 20;
export const MAX_LOCK_RESETS = 15;

// Guideline gravity: seconds per row at level L.
export function gravitySeconds(level) {
  return Math.pow(0.8 - (level - 1) * 0.007, level - 1);
}

function mulberry32(seed) {
  let a = seed >>> 0;
  return function () {
    a |= 0;
    a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

function emptyBoard() {
  return Array.from({ length: BOARD_HEIGHT }, () => new Array(BOARD_WIDTH).fill(null));
}

export class Game {
  constructor(options = {}) {
    this.seed = options.seed ?? null;
    this.onEvent = typeof options.onEvent === 'function' ? options.onEvent : null;
    this.gravityMsOverride = Number.isFinite(options.gravityMs) ? options.gravityMs : null;
    this.lockDelayMs = Number.isFinite(options.lockDelayMs) ? options.lockDelayMs : 500;

    this.state = 'idle';
    this.board = emptyBoard();
    this.score = 0;
    this.level = 1;
    this.lines = 0;
    this.combo = -1;
    this.b2b = false;
    this.hold = null;
    this.canHold = true;
    this.queue = [];
    this.current = null;

    // Internal gravity / lock-delay state.
    this._rng = mulberry32(this.seed ?? (Date.now() ^ Math.floor(Math.random() * 0xffffffff)) >>> 0);
    this._bag = [];
    this._gravityAccumMs = 0;
    this._grounded = false;
    this._lockTimerMs = null;
    this._resetsUsed = 0;
    this._lastMoveWasKick = false;

    this.reset();
  }

  // ------------------------------------------------------------------ events

  _emit(event) {
    if (this.onEvent) this.onEvent(event);
    return event;
  }

  // ------------------------------------------------------------- randomizer

  _refillQueue() {
    while (this.queue.length < 5) {
      if (this._bag.length === 0) {
        const bag = ['I', 'O', 'T', 'S', 'Z', 'J', 'L'];
        for (let i = bag.length - 1; i > 0; i--) {
          const j = Math.floor(this._rng() * (i + 1));
          [bag[i], bag[j]] = [bag[j], bag[i]];
        }
        this._bag = bag;
      }
      this.queue.push(this._bag.pop());
    }
  }

  _nextPieceType() {
    this._refillQueue();
    const type = this.queue.shift();
    this._refillQueue(); // keep >= 5 upcoming pieces visible after the shift
    return type;
  }

  // ------------------------------------------------------------- geometry

  cellsOf(type, x, y, rot) {
    return SHAPES[type][rot].map(([c, r]) => [x + c, y + r]);
  }

  collides(cells) {
    for (const [cx, cy] of cells) {
      if (cx < 0 || cx >= BOARD_WIDTH || cy >= BOARD_HEIGHT) return true;
      if (cy >= 0 && this.board[cy][cx]) return true; // rows above the board are open space
    }
    return false;
  }

  isOnGround(piece = this.current) {
    const cells = this.cellsOf(piece.type, piece.x, piece.y + 1, piece.rot);
    return this.collides(cells);
  }

  get ghostY() {
    if (!this.current) return null;
    let gy = this.current.y;
    while (true) {
      const cells = this.cellsOf(this.current.type, this.current.x, gy + 1, this.current.rot);
      if (this.collides(cells)) break;
      gy++;
    }
    return gy;
  }

  // ------------------------------------------------------------- lifecycle

  start() {
    this.reset();
    this.state = 'playing';
    if (!this._spawnNext()) return; // block-out at spawn (e.g. board pre-filled) -> over
  }

  pause() {
    if (this.state === 'playing') this.state = 'paused';
  }

  resume() {
    if (this.state === 'paused') this.state = 'playing';
  }

  reset() {
    this.board = emptyBoard();
    this.score = 0;
    this.level = 1;
    this.lines = 0;
    this.combo = -1;
    this.b2b = false;
    this.hold = null;
    this.canHold = true;
    this.queue = [];
    this.current = null;
    this._gravityAccumMs = 0;
    this._grounded = false;
    this._lockTimerMs = null;
    this._resetsUsed = 0;
    this._lastMoveWasKick = false;
    // Re-seed the PRNG so a reset with options.seed replays the same sequence.
    const seed = this.seed ?? (Date.now() ^ Math.floor(Math.random() * 0xffffffff)) >>> 0;
    this._rng = mulberry32(seed);
    this._bag = [];
    this._refillQueue();
  }

  _spawn(type) {
    // Standard SRS spawn: I in row 21 (hidden), others in rows 21-22, centered.
    const x = type === 'O' ? 4 : 3;
    const y = 21;
    this.current = { type, x, y, rot: 0 };
    if (this.collides(this.cellsOf(type, x, y, 0))) {
      // Block out at spawn -> game over.
      this.state = 'over';
      this._emit({ type: 'gameover' });
      return false;
    }
    this.canHold = true;
    this._gravityAccumMs = 0;
    this._grounded = this.isOnGround();
    this._lockTimerMs = null;
    this._resetsUsed = 0;
    return true;
  }

  _spawnNext() {
    const type = this._nextPieceType();
    if (!this._spawn(type)) return false;
    return true;
  }

  // ------------------------------------------------------------- input

  moveLeft() {
    if (this.state !== 'playing' || !this.current) return false;
    const cells = this.cellsOf(this.current.type, this.current.x - 1, this.current.y, this.current.rot);
    if (this.collides(cells)) return false;
    this.current.x -= 1;
    this._lastMoveWasKick = false; // a plain move is not a kick
    this._afterSuccessfulMove();
    return true;
  }

  moveRight() {
    if (this.state !== 'playing' || !this.current) return false;
    const cells = this.cellsOf(this.current.type, this.current.x + 1, this.current.y, this.current.rot);
    if (this.collides(cells)) return false;
    this.current.x += 1;
    this._lastMoveWasKick = false; // a plain move is not a kick
    this._afterSuccessfulMove();
    return true;
  }

  softDrop() {
    if (this.state !== 'playing' || !this.current) return false;
    const cells = this.cellsOf(this.current.type, this.current.x, this.current.y + 1, this.current.rot);
    if (this.collides(cells)) return false;
    this.current.y += 1;
    this.score += 1; // guideline: +1 per cell, not multiplied by level
    this._gravityAccumMs = 0;
    this._lastMoveWasKick = false; // a plain move is not a kick
    this._grounded = this.isOnGround();
    if (!this._grounded) this._lockTimerMs = null;
    return true;
  }

  hardDrop() {
    if (this.state !== 'playing' || !this.current) return;
    const gy = this.ghostY;
    const distance = gy - this.current.y;
    this.score += 2 * distance; // guideline: +2 per cell, not multiplied by level
    this.current.y = gy;
    this._lockPiece();
  }

  rotateCW() {
    return this._rotate(1);
  }

  rotateCCW() {
    return this._rotate(-1);
  }

  _rotate(dir) {
    if (this.state !== 'playing' || !this.current) return false;
    const from = this.current.rot;
    const to = (from + dir + 4) % 4;
    for (let i = 0; i < getKicks(this.current.type, from, to).length; i++) {
      const [dx, dy] = getKicks(this.current.type, from, to)[i];
      const nx = this.current.x + dx;
      const ny = this.current.y + dy;
      if (!this.collides(this.cellsOf(this.current.type, nx, ny, to))) {
        this.current.x = nx;
        this.current.y = ny;
        this.current.rot = to;
        // A non-zero kick is what makes a 3-corner T-lock a "mini" T-spin.
        this._lastMoveWasKick = i > 0 && (dx !== 0 || dy !== 0);
        this._afterSuccessfulMove();
        return true;
      }
    }
    this._lastMoveWasKick = false;
    return false;
  }

  holdPiece() {
    if (this.state !== 'playing' || !this.current || !this.canHold) return false;
    const curType = this.current.type;
    if (this.hold === null) {
      this.hold = curType;
      if (!this._spawnNext()) return true; // game over already handled
    } else {
      const heldType = this.hold;
      this.hold = curType;
      if (!this._spawn(heldType)) return true;
    }
    this.canHold = false;
    this._emit({ type: 'hold', piece: this.current ? this.current.type : null });
    return true;
  }

  // ------------------------------------------------------------- gravity & lock delay

  _gravityMs() {
    if (this.gravityMsOverride != null) return this.gravityMsOverride;
    return gravitySeconds(this.level) * 1000;
  }

  /** Public: current gravity interval in ms (UI loop uses this to pace tick()). */
  get gravityMs() {
    return this._gravityMs();
  }

  tick() {
    const events = [];
    if (this.state !== 'playing' || !this.current) return events;

    // Lock delay: while grounded, the piece locks after lockDelayMs of ground contact.
    if (this.isOnGround()) {
      this._grounded = true;
      this._lockTimerMs = (this._lockTimerMs ?? 0) + this._gravityMs();
      if (this._lockTimerMs >= this.lockDelayMs) {
        this._lockPiece(events);
        return events;
      }
    } else {
      // Falling: accumulate gravity time and drop whole rows.
      this._grounded = false;
      this._lockTimerMs = null;
      const gms = this._gravityMs();
      this._gravityAccumMs += gms;
      while (this._gravityAccumMs >= gms) {
        this._gravityAccumMs -= gms;
        if (!this.isOnGround()) {
          const cells = this.cellsOf(this.current.type, this.current.x, this.current.y + 1, this.current.rot);
          if (this.collides(cells)) break; // landed on the ground mid-tick
          this.current.y += 1;
        } else {
          break;
        }
      }
    }

    // After gravity, re-check grounding for lock-delay bookkeeping.
    if (this.isOnGround() && this._lockTimerMs == null) {
      this._grounded = true;
      this._lockTimerMs = 0;
    }
    return events;
  }

  _afterSuccessfulMove() {
    // Move-reset rule: reset the lock timer on a successful move/rotate, up to 15 times.
    if (this.isOnGround()) {
      if (this._resetsUsed < MAX_LOCK_RESETS) {
        this._lockTimerMs = 0;
        this._resetsUsed += 1;
      } else {
        // Reset cap exhausted: lock on the next tick.
        this._lockTimerMs = this.lockDelayMs;
      }
    } else {
      this._grounded = false;
      this._lockTimerMs = null;
    }
  }

  _lockPiece(events = []) {
    const piece = this.current;
    for (const [cx, cy] of this.cellsOf(piece.type, piece.x, piece.y, piece.rot)) {
      if (cy >= 0 && cy < BOARD_HEIGHT) this.board[cy][cx] = piece.type;
    }

    // T-spin detection must be evaluated on lock while `current` is still set.
    const tSpinInfo = this._detectTSpin();
    this.current = null;
    const clearedRows = [];
    for (let r = 0; r < BOARD_HEIGHT; r++) {
      if (this.board[r].every((c) => c !== null)) clearedRows.push(r);
    }

    this._emit({ type: 'lock', piece: piece.type, x: piece.x, y: piece.y, rot: piece.rot });

    let clearEvent = null;
    if (clearedRows.length > 0) {
      for (const r of clearedRows) {
        this.board.splice(r, 1);
        this.board.unshift(new Array(BOARD_WIDTH).fill(null));
      }
      const points = this._scoreClear(clearedRows.length, tSpinInfo);
      clearEvent = {
        type: 'clear',
        lines: clearedRows.length,
        tSpin: tSpinInfo.tSpin,
        miniTSpin: tSpinInfo.miniTSpin,
        points,
        combo: this.combo,
        b2b: this.b2b,
      };
    } else {
      this.combo = -1; // a non-clearing lock breaks the combo chain
    }

    if (clearEvent) {
      this._emit(clearEvent);
      events.push(clearEvent);
    }

    const prevLevel = this.level;
    this.level = Math.floor(this.lines / 10) + 1;
    if (this.level > prevLevel) {
      const ev = { type: 'levelup', level: this.level };
      this._emit(ev);
      events.push(ev);
    }

    // Spawn the next piece (may trigger game over).
    this._spawnNext();
  }

  _scoreClear(n, tSpinInfo) {
    const L = this.level;
    let base = 0;
    if (tSpinInfo.tSpin) {
      base = n === 1 ? 800 : n === 2 ? 1200 : n === 3 ? 1600 : 1600; // T-spin tetris = 1600
    } else if (tSpinInfo.miniTSpin) {
      base = n === 1 ? 100 : n === 2 ? 200 : 400; // mini: no b2b, capped at triple
    } else {
      base = n === 1 ? 100 : n === 2 ? 300 : n === 3 ? 500 : 800;
    }

    const qualifiesB2B = (tSpinInfo.tSpin && n >= 1) || (!tSpinInfo.miniTSpin && n === 4);
    let points = base * L;
    if (qualifiesB2B && this.b2b) points = Math.floor(points * 1.5);

    // Combo: increments on every consecutive clearing lock, resets to -1 otherwise.
    this.combo += 1;
    if (this.combo > 0) points += 50 * this.combo * L;

    this.b2b = qualifiesB2B;
    this.lines += n;
    this.score += points;
    return points;
  }

  // ------------------------------------------------------------- T-spin detection

  /**
   * 3-corner rule, evaluated on lock (before line clears).
   * Corners of the 3x3 bounding box: TL(x,y) TR(x+2,y) BL(x,y+2) BR(x+2,y+2).
   * A corner is "filled" if it lies outside the board or holds a block.
   */
  _cornerFilled(cx, cy) {
    if (cx < 0 || cx >= BOARD_WIDTH || cy < 0 || cy >= BOARD_HEIGHT) return true;
    return this.board[cy][cx] !== null;
  }

  isTSpin() {
    // Exposed for tests: evaluates the current piece's lock position.
    if (!this.current || this.current.type !== 'T') return false;
    const { x, y, rot } = this.current;
    const corners = [
      [x, y],
      [x + 2, y],
      [x, y + 2],
      [x + 2, y + 2],
    ];
    const filled = corners.map(([cx, cy]) => this._cornerFilled(cx, cy));
    if (filled.filter(Boolean).length < 3) return false;
    // Front corners depend on the rotation state.
    let front;
    switch (rot) {
      case 0: front = [1, 2]; break; // facing up: TR, BR
      case 1: front = [0, 1]; break; // facing right: TL, TR
      case 2: front = [2, 3]; break; // facing down: BL, BR
      default: front = [0, 3]; break; // facing left: TL, BL
    }
    return filled[front[0]] && filled[front[1]];
  }

  _detectTSpin() {
    if (!this.current || this.current.type !== 'T') return { tSpin: false, miniTSpin: false };
    const { x, y, rot } = this.current;
    const corners = [
      [x, y],
      [x + 2, y],
      [x, y + 2],
      [x + 2, y + 2],
    ];
    const filled = corners.map(([cx, cy]) => this._cornerFilled(cx, cy));
    if (filled.filter(Boolean).length < 3) return { tSpin: false, miniTSpin: false };

    let front;
    switch (rot) {
      case 0: front = [1, 2]; break;
      case 1: front = [0, 1]; break;
      case 2: front = [2, 3]; break;
      default: front = [0, 3]; break;
    }
    if (filled[front[0]] && filled[front[1]]) return { tSpin: true, miniTSpin: false };

    // Mini T-spin: 3 corners filled but the last successful move was a kick.
    const lastKick = this._lastMoveWasKick;
    this._lastMoveWasKick = false;
    if (lastKick) return { tSpin: false, miniTSpin: true };
    return { tSpin: false, miniTSpin: false };
  }
}
