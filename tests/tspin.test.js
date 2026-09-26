import { test } from 'node:test';
import assert from 'node:assert/strict';
import { Game, BOARD_WIDTH } from '../js/engine.js';
import { makeGame, setPiece, clearBoard, forceNext } from './helpers.js';

/**
 * Classic T-spin double setup (built in code):
 *
 *   row 37: . . . . X . . . . .        <- TL corner of the T's bbox filled
 *   row 38: X X X X X . . . X X X      <- gap at cols 5,6,7 for the slot
 *   row 39: X X X X X X . X X X        <- gap only at col 6 (the T's bottom cell)
 *
 * Natural play: the T spawns, moves right twice to x=5, rotates CW to rot=1 and
 * descends vertically through cols 6-7 until it rests on row 39 (y=37). One more
 * CW rotation drops it into the slot at x=5,y=37,rot=2: cells (5,38),(6,38),
 * (7,38),(6,39) — completing rows 38 and 39. On lock:
 *   bbox corners TL(5,37)=X, TR(7,37)=., BL(5,39)=X, BR(7,39)=X -> 3 filled,
 *   front corners for rot=2 are BL+BR (both filled) -> full T-spin double.
 */
function buildTSpinDouble(g) {
  clearBoard(g);
  g.board[37][5] = 'X'; // TL corner overhang
  for (const c of [0, 1, 2, 3, 4, 8, 9]) g.board[38][c] = 'X'; // gap cols 5-7
  for (const c of [0, 1, 2, 3, 4, 5, 7, 8, 9]) g.board[39][c] = 'X'; // gap col 6 only
}

function playTSpinDouble(g) {
  setPiece(g, 'T', 3, 21); // standard T spawn (cells (4,21),(3,22),(4,22),(5,22))
  assert.equal(g.moveRight(), true);
  assert.equal(g.moveRight(), true);
  assert.equal(g.current.x, 5);
  assert.equal(g.rotateCW(), true); // rot=1: cells (6,21),(6,22),(7,22),(6,23)
  for (let i = 0; i < 16; i++) assert.equal(g.softDrop(), true); // descend to y=37
  assert.equal(g.current.y, 37);
  assert.equal(g.rotateCW(), true); // into the slot: rot=2 at x=5,y=37
  assert.equal(g.current.rot, 2);
}

test('T-spin double: natural descent detects tSpin with 1200*level points', () => {
  const { game: g, events } = makeGame();
  g.start();
  buildTSpinDouble(g);
  forceNext(g, 'I'); // known upcoming piece for the b2b follow-up test

  playTSpinDouble(g);
  assert.equal(g.isTSpin(), true, '3-corner rule must classify this lock as a T-spin');

  g.hardDrop();
  const clear = events.find((e) => e.type === 'clear');
  assert.ok(clear, 'a clear event must be emitted');
  assert.equal(clear.lines, 2);
  assert.equal(clear.tSpin, true, 'must be detected as a T-spin (3-corner rule)');
  assert.equal(clear.miniTSpin, false);
  assert.equal(clear.points, 1200 * g.level); // level is still 1 (lines=2)
  assert.equal(g.b2b, true, 'a T-spin line clear must start a b2b chain');
});

test('T-spin double: following Tetris gets the x1.5 back-to-back multiplier', () => {
  const { game: g, events } = makeGame();
  g.start();
  buildTSpinDouble(g);
  forceNext(g, 'I');

  playTSpinDouble(g);
  g.hardDrop(); // T-spin double -> b2b = true

  assert.equal(g.current.type, 'I', 'the forced I must be the next piece');

  // Now a plain Tetris while b2b is active.
  clearBoard(g);
  for (let r = 36; r <= 39; r++) {
    for (let c = 0; c < BOARD_WIDTH; c++) if (c !== 4) g.board[r][c] = 'X';
  }
  setPiece(g, 'I', 2, 20, 1); // vertical I in col 4
  const L = g.level; // lines=2 -> level 1 at lock time
  const scoreBefore = g.score;

  g.hardDrop();
  const clear = events.filter((e) => e.type === 'clear').at(-1);
  assert.ok(clear);
  assert.equal(clear.lines, 4);
  assert.equal(clear.tSpin, false);
  assert.equal(clear.b2b, true, 'the Tetris must be flagged as b2b');
  // Base 800*L * 1.5 + combo (combo was 0 after the TSD, now 1): +50*1*L.
  const expected = Math.floor(800 * L * 1.5) + 50 * 1 * L;
  assert.equal(clear.points, expected); // clear points only (no drop bonus)
  assert.equal(g.score - scoreBefore, expected + 2 * (36 - 20)); // + hard drop bonus (16 cells)
  assert.equal(g.b2b, true, 'chain stays alive after a b2b-qualifying clear');
});

test('isTSpin(): true at the T-spin double lock position, false otherwise', () => {
  const g = new Game({ seed: 1 });
  g.start();
  buildTSpinDouble(g);
  setPiece(g, 'T', 5, 37, 2); // exactly where it locks in the natural test
  assert.equal(g.isTSpin(), true);

  clearBoard(g);
  setPiece(g, 'T', 4, 30, 1); // open space: no corners filled
  assert.equal(g.isTSpin(), false);

  const g2 = new Game({ seed: 1 });
  g2.start();
  setPiece(g2, 'I', 4, 30, 0); // non-T piece is never a T-spin
  assert.equal(g2.isTSpin(), false);
});

test('mini T-spin single: 3 corners filled but front not both -> mini (100*level, no b2b)', () => {
  const { game: g, events } = makeGame();
  g.start();
  clearBoard(g);
  // T in rot=1 at x=4,y=37: cells (5,37),(5,38),(6,38),(5,39). Clears row 39 only.
  for (let c = 0; c < BOARD_WIDTH; c++) if (c !== 5) g.board[39][c] = 'X'; // gap at col 5
  g.board[37][6] = 'X'; // TR corner filled -> corners: TR, BL(4,39), BR(6,39) = 3
  setPiece(g, 'T', 4, 37, 1);
  assert.equal(g.isTSpin(), false, 'front corners (TL,TR) are not both filled');
  g._lastMoveWasKick = true; // last successful move was a kick -> mini T-spin

  g.hardDrop();
  const clear = events.find((e) => e.type === 'clear');
  assert.ok(clear);
  assert.equal(clear.lines, 1);
  assert.equal(clear.tSpin, false);
  assert.equal(clear.miniTSpin, true);
  assert.equal(clear.points, 100 * g.level); // mini single: no b2b multiplier
  assert.equal(g.b2b, false, 'mini T-spins must not start a b2b chain');
});
