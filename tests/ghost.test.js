import { test } from 'node:test';
import assert from 'node:assert/strict';
import { Game, BOARD_WIDTH } from '../js/engine.js';
import { makeGame, setPiece, clearBoard } from './helpers.js';

test('ghost: empty board — O piece ghost lands on the floor', () => {
  const g = new Game({ seed: 1 });
  g.start();
  clearBoard(g);
  setPiece(g, 'O', 4, 21); // occupies rows y..y+1; floor is row 39 -> ghost at y=38
  assert.equal(g.ghostY, 38);
});

test('ghost: empty board — I piece (rot=0) ghost lands on the floor', () => {
  const g = new Game({ seed: 1 });
  g.start();
  clearBoard(g);
  setPiece(g, 'I', 3, 21, 0); // occupies row y+1; ghost at y=38 (row 39)
  assert.equal(g.ghostY, 38);
});

test('ghost: vertical I piece ghost lands on the floor', () => {
  const g = new Game({ seed: 1 });
  g.start();
  clearBoard(g);
  setPiece(g, 'I', 4, 20, 1); // occupies rows y..y+3; ghost at y=36 (rows 36-39)
  assert.equal(g.ghostY, 36);
});

test('ghost: lands on top of a stack', () => {
  const g = new Game({ seed: 1 });
  g.start();
  clearBoard(g);
  // Stack: col 5 filled in rows 37-39.
  for (let r = 37; r <= 39; r++) g.board[r][5] = 'X';
  setPiece(g, 'O', 4, 21); // O spans cols 4-5 -> must land on top of col 5's stack: rows y..y+1 with y+1=36 -> y=35?
  // O cells are (x,y),(x+1,y),(x,y+1),(x+1,y+1). To rest on row 36 (top of stack at 37): bottom row y+1 = 36 -> y=35.
  assert.equal(g.ghostY, 35);
});

test('ghost: piece already resting on the ground has ghostY == current.y', () => {
  const g = new Game({ seed: 1 });
  g.start();
  clearBoard(g);
  setPiece(g, 'O', 4, 38); // rows 38-39: on the floor
  assert.equal(g.ghostY, 38);
});

test('ghost: T piece ghost lands in a slot', () => {
  const g = new Game({ seed: 1 });
  g.start();
  clearBoard(g);
  // Slot for a rot=2 T at x=4,y=37: cells (4,38),(5,38),(6,38),(5,39).
  // Fill row 39 except col 5; fill row 38 cols 0-3 and 7-9.
  for (let c = 0; c < BOARD_WIDTH; c++) if (c !== 5) g.board[39][c] = 'X';
  for (const c of [0, 1, 2, 3, 7, 8, 9]) g.board[38][c] = 'X';
  setPiece(g, 'T', 4, 20, 2); // rot=2 cells: (x,y+1),(x+1,y+1),(x+2,y+1),(x+1,y+2)
  assert.equal(g.ghostY, 37);
});
