// parity/trace_js.mjs — Golden-trace generator for Godot port parity (Phase 2).
// Drives the FROZEN JS engine + autoplayer with a fully deterministic protocol:
//   per piece: up to 2 gravity ticks, then one autoplayer step (hard drop).
// Emits JSON: {protocol, seeds:[{seed, score, level, lines, locks:[...], clears:[...]}]}
// The GDScript side (trace_godot.gd) must reproduce this byte-for-byte.

import { Game } from '../../js/engine.js';
import { AutoPlayer } from '../../js/autoplayer.js';
import { writeFileSync } from 'node:fs';

const SEEDS = 50;
const TICKS_PER_PIECE = 2;

function serializeBoard(board) {
  // row-major, '.' for empty, piece letter otherwise — identical on both sides.
  return board.map((row) => row.map((c) => (c === null ? '.' : c)).join('')).join('|');
}

function runGame(seed) {
  const events = [];
  const game = new Game({ seed });
  game.onEvent = (ev) => events.push(ev);
  const ap = new AutoPlayer(game);
  game.start();

  let locks = 0;
  while (game.state === 'playing') {
    for (let i = 0; i < TICKS_PER_PIECE; i++) {
      game.tick();
      if (game.state !== 'playing' || !game.current) break;
    }
    if (game.state !== 'playing' || !game.current) break;
    ap.step(); // rotates/slides to best placement, then hardDrop() -> lock + next piece
    locks++;
  }

  const lockEvents = events.filter((e) => e.type === 'lock');
  const clearEvents = events.filter((e) => e.type === 'clear');
  return {
    seed,
    state: game.state,
    score: game.score,
    level: game.level,
    lines: game.lines,
    locks: lockEvents.length, // count from events (a gravity-locked final piece is not an ap.step())
    lockSeq: lockEvents.map((e) => `${e.piece}@${e.x},${e.y},r${e.rot}`),
    clears: clearEvents.map(
      (e) => `c${e.lines}${e.tSpin ? 'T' : ''}${e.miniTSpin ? 'm' : ''}+${e.points}(combo${e.combo}${e.b2b ? ',b2b' : ''})`
    ),
    finalBoard: serializeBoard(game.board),
  };
}

const out = { protocol: `ticks=${TICKS_PER_PIECE}/piece, autoplayer=harddrop`, seeds: [] };
for (let s = 1; s <= SEEDS; s++) {
  const r = runGame(s);
  if (r.state !== 'over') throw new Error(`seed ${s}: expected game over, got state=${r.state}`);
  out.seeds.push(r);
}

const dest = process.argv[2] || 'reference_traces.json';
writeFileSync(dest, JSON.stringify(out));
console.log(
  `traced ${SEEDS} games -> ${dest}; total locks: ${out.seeds.reduce((a, r) => a + r.locks, 0)}; ` +
    `score range [${Math.min(...out.seeds.map((r) => r.score))}, ${Math.max(...out.seeds.map((r) => r.score))}]`
);
