import { test } from 'node:test';
import assert from 'node:assert/strict';
import { Game, BOARD_WIDTH } from '../js/engine.js';
import { makeGame, setPiece, clearBoard, fillRow } from './helpers.js';

test('line clears: single = 100*level via hardDrop (drop bonus not multiplied)', () => {
  const { game: g, events } = makeGame();
  g.start();
  clearBoard(g);
  fillRow(g, 39, [4]); // one full row with a gap at col 4
  setPiece(g, 'I', 2, 30, 1); // vertical I in col x+2 = 4; falls to y=36 (rows 36-39), filling the gap

  g.hardDrop();
  const clear = events.find((e) => e.type === 'clear');
  assert.ok(clear, 'a clear event must be emitted');
  assert.equal(clear.lines, 1);
  assert.equal(clear.tSpin, false);
  assert.equal(clear.points, 100 * g.level); // level is still 1 (lines=1)
  const dropDistance = 36 - 30;
  assert.equal(g.score, 100 + 2 * dropDistance); // clear points + hard drop bonus (+2/cell)
  assert.equal(g.lines, 1);
});

test('line clears: double = 300*level', () => {
  const { game: g, events } = makeGame();
  g.start();
  clearBoard(g);
  fillRow(g, 38, [4]);
  fillRow(g, 39, [4]);
  // Vertical I in col x+2 = 4 (x=2), covering rows y..y+3; place it so it fills col 4 of both rows.
  setPiece(g, 'I', 2, 36, 1);

  g.hardDrop();
  const clear = events.find((e) => e.type === 'clear');
  assert.ok(clear);
  assert.equal(clear.lines, 2);
  assert.equal(clear.points, 300 * g.level);
});

test('line clears: tetris (4 rows) = 800*level', () => {
  const { game: g, events } = makeGame();
  g.start();
  clearBoard(g);
  for (let r = 36; r <= 39; r++) fillRow(g, r, [4]); // four full rows with a vertical gap at col 4
  setPiece(g, 'I', 2, 20, 1); // vertical I in col 4

  g.hardDrop();
  const clear = events.find((e) => e.type === 'clear');
  assert.ok(clear);
  assert.equal(clear.lines, 4);
  assert.equal(clear.points, 800 * g.level);
});

test('level up at 10 total lines (level = floor(lines/10)+1)', () => {
  const { game: g, events } = makeGame();
  g.start();
  clearBoard(g);
  // Simulate 9 prior lines without disturbing the board.
  g.lines = 9;
  for (let r = 36; r <= 39; r++) fillRow(g, r, [4]);
  setPiece(g, 'I', 2, 20, 1); // vertical I in col 4

  g.hardDrop();
  assert.equal(g.lines, 13);
  assert.equal(g.level, 2);
  const levelup = events.find((e) => e.type === 'levelup');
  assert.ok(levelup, 'a levelup event must be emitted');
  assert.equal(levelup.level, 2);
});

test('combo: increments across consecutive clears and resets to -1 after a non-clearing lock', () => {
  const { game: g, events } = makeGame();
  g.start();
  clearBoard(g);

  // Lock #1: single (row 39 full except col 4; vertical I in col 4 fills it).
  fillRow(g, 39, [4]);
  setPiece(g, 'I', 2, 36, 1);
  g.hardDrop();
  let clear = events.find((e) => e.type === 'clear');
  assert.equal(clear.combo, 0, 'first clearing lock has combo 0 (no bonus)');

  // Lock #2: another single -> combo should be 1 and add 50*combo*level.
  clearBoard(g);
  fillRow(g, 39, [4]);
  setPiece(g, 'I', 2, 36, 1);
  g.hardDrop();
  clear = events.filter((e) => e.type === 'clear').at(-1);
  assert.equal(clear.combo, 1);
  assert.equal(clear.points, 100 + 50 * 1 * g.level);

  // Lock #3: non-clearing lock -> combo resets to -1.
  clearBoard(g);
  setPiece(g, 'O', 4, 38);
  g.hardDrop();
  assert.equal(g.combo, -1);

  // Lock #4: clearing again -> combo back to 0.
  clearBoard(g);
  fillRow(g, 39, [4]);
  setPiece(g, 'I', 2, 36, 1);
  g.hardDrop();
  clear = events.filter((e) => e.type === 'clear').at(-1);
  assert.equal(clear.combo, 0);
});

test('back-to-back: applies only to Tetrises and T-spin line clears', () => {
  const { game: g } = makeGame();
  g.start();
  clearBoard(g);

  // A double does NOT qualify for b2b.
  fillRow(g, 38, [4]);
  fillRow(g, 39, [4]);
  setPiece(g, 'I', 2, 36, 1); // vertical I in col 4 filling both rows
  g.hardDrop();
  assert.equal(g.b2b, false, 'a double must not start a b2b chain');

  // A Tetris qualifies.
  clearBoard(g);
  for (let r = 36; r <= 39; r++) fillRow(g, r, [4]);
  setPiece(g, 'I', 2, 20, 1);
  g.hardDrop();
  assert.equal(g.b2b, true, 'a Tetris must start a b2b chain');

  // A following Tetris gets the x1.5 multiplier (level at lock time = 1: lines=6).
  clearBoard(g);
  for (let r = 36; r <= 39; r++) fillRow(g, r, [4]);
  setPiece(g, 'I', 2, 20, 1);
  const L = g.level; // level at lock time (lines=6 -> level 1)
  const scoreBefore = g.score;
  g.hardDrop();
  assert.equal(g.b2b, true);
  // Combo is now 2 (double->0, first Tetris->1, this one->2): base 800*L*1.5 + 50*2*L.
  const expected = Math.floor(800 * L * 1.5) + 50 * 2 * L;
  assert.equal(g.score - scoreBefore, expected + 2 * (36 - 20)); // + hard drop bonus (16 cells)

  // A single after the chain does NOT get b2b and breaks the chain.
  clearBoard(g);
  fillRow(g, 39, [4]);
  setPiece(g, 'I', 2, 36, 1); // vertical I in col 4; already resting on row 39 (drop distance 0)
  const L2 = g.level; // lines=10 -> level 2 at lock time
  const scoreBefore2 = g.score;
  g.hardDrop();
  assert.equal(g.b2b, false, 'a single must break the b2b chain');
  // No multiplier: 100*L2 + combo (now 3): 50*3*L2. Drop distance is 0.
  const expected2 = 100 * L2 + 50 * 3 * L2;
  assert.equal(g.score - scoreBefore2, expected2);
});

test('soft drop adds +1 per cell; hard drop adds +2 per cell (not multiplied by level)', () => {
  const { game: g } = makeGame();
  g.start();
  clearBoard(g);
  setPiece(g, 'O', 4, 21); // O occupies rows 21-22; floor at row 39 -> lands at y=38 (rows 38-39)

  const dist = 38 - 21;
  for (let i = 0; i < dist; i++) assert.equal(g.softDrop(), true);
  assert.equal(g.score, dist * 1);
  g.hardDrop(); // already on the ground: +0 drop cells, locks
  assert.equal(g.score, dist * 1);

  const { game: g2 } = makeGame();
  g2.start();
  clearBoard(g2);
  setPiece(g2, 'O', 4, 21);
  g2.hardDrop();
  assert.equal(g2.score, dist * 2);
});
