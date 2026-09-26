import { test } from 'node:test';
import assert from 'node:assert/strict';
import { Game, BOARD_WIDTH } from '../js/engine.js';
import { setPiece, clearBoard } from './helpers.js';

const sorted = (cells) => [...cells].sort((a, b) => a[0] - b[0] || a[1] - b[1]);

test('SRS: T-piece spawn -> CW -> CCW returns to the exact spawn cells', () => {
  const g = new Game({ seed: 1 });
  g.start();
  setPiece(g, 'T', 3, 21); // standard T spawn position
  assert.deepEqual(g.current, { type: 'T', x: 3, y: 21, rot: 0 });

  const cellsAt = () => sorted(g.cellsOf('T', g.current.x, g.current.y, g.current.rot));
  const spawnCells = cellsAt();
  assert.deepEqual(spawnCells, [[3, 22], [4, 21], [4, 22], [5, 22]]);

  assert.equal(g.rotateCW(), true);
  assert.equal(g.current.rot, 1);
  assert.deepEqual(cellsAt(), [[4, 21], [4, 22], [4, 23], [5, 22]]);

  assert.equal(g.rotateCCW(), true);
  assert.equal(g.current.rot, 0);
  assert.deepEqual(cellsAt(), spawnCells, 'CW then CCW must restore the exact spawn cells');
});

test('SRS: I-piece vertical against the right wall kicks left (kick #3 of 3->0)', () => {
  const g = new Game({ seed: 1 });
  g.start();
  clearBoard(g);
  // Vertical I in rot=3 occupies column x+1. Flush against the right wall: col 9 -> x=8.
  setPiece(g, 'I', 8, 20, 3);
  assert.deepEqual(g.cellsOf('I', 8, 20, 3).map(([c]) => c), [9, 9, 9, 9]);

  const ok = g.rotateCW(); // 3 -> 0
  assert.equal(ok, true);
  assert.equal(g.current.rot, 0);
  // I kicks for 3->0 (board coords): (0,0),(+1,0),(-2,0),(+1,+2),(-2,-2).
  // Base and kick #2 push the horizontal I into col 10 -> out of bounds.
  // Kick #3 (-2,0) applies: x=6, cells cols 6-9 in row y+1 = 21.
  assert.equal(g.current.x, 6);
  assert.equal(g.current.y, 20);
  assert.deepEqual(sorted(g.cellsOf('I', g.current.x, g.current.y, g.current.rot)), [
    [6, 21], [7, 21], [8, 21], [9, 21],
  ]);
});

test('SRS: O piece stays in place on rotate (no effective kicks)', () => {
  const g = new Game({ seed: 1 });
  g.start();
  setPiece(g, 'O', 4, 21);
  assert.equal(g.rotateCW(), true);
  assert.deepEqual(g.current, { type: 'O', x: 4, y: 21, rot: 1 });
  assert.equal(g.rotateCCW(), true);
  assert.deepEqual(g.current, { type: 'O', x: 4, y: 21, rot: 0 });
});

test('wall kicks (JLSTZ): T against right wall uses kick #2 of 3->0 (dx=-1), exact x/y/rot', () => {
  const g = new Game({ seed: 1 });
  g.start();
  clearBoard(g);
  // T in rot=3 at x=8: cells (9,30),(8,31),(9,31),(9,32) — flush against the right wall.
  setPiece(g, 'T', 8, 30, 3);
  const ok = g.rotateCW(); // 3 -> 0
  assert.equal(ok, true);
  assert.equal(g.current.rot, 0);
  // JLSTZ kicks for 3->0: (0,0),(-1,0),(-1,-1),(0,-2),(-1,-2).
  // Base rot=0 at x=8 needs col 10 -> out of bounds. Kick #2 (-1,0) applies.
  assert.equal(g.current.x, 7);
  assert.equal(g.current.y, 30);
  assert.deepEqual(sorted(g.cellsOf('T', g.current.x, g.current.y, g.current.rot)), [
    [7, 31], [8, 30], [8, 31], [9, 31],
  ]);
});

test('wall kicks (JLSTZ): T in a slot uses kick #2 of 0->1 (dx=-1), exact x/y/rot', () => {
  const g = new Game({ seed: 1 });
  g.start();
  clearBoard(g);
  // T rot=0 at x=4,y=30: cells (5,30),(4,31),(5,31),(6,31).
  setPiece(g, 'T', 4, 30);
  // Block the base rot=1 cell that is not part of rot=0: (x+1,y+2) = (5,32).
  g.board[32][5] = 'X';
  const ok = g.rotateCW(); // 0 -> 1
  assert.equal(ok, true);
  assert.equal(g.current.rot, 1);
  // Kick #2 (-1,0): x=3,y=30: cells (4,30),(4,31),(5,31),(4,32) — all free.
  assert.equal(g.current.x, 3);
  assert.equal(g.current.y, 30);
});

test('wall kicks (JLSTZ): T in a slot uses kick #1 of 1->2 (dx=+1), exact x/y/rot', () => {
  const g = new Game({ seed: 1 });
  g.start();
  clearBoard(g);
  // T rot=1 at x=4,y=30: cells (5,30),(5,31),(6,31),(5,32).
  setPiece(g, 'T', 4, 30, 1);
  // Block the base rot=2 cell that is not part of rot=1: (x,y+1) = (4,31).
  g.board[31][4] = 'X';
  const ok = g.rotateCW(); // 1 -> 2
  assert.equal(ok, true);
  assert.equal(g.current.rot, 2);
  // Kick #1 (+1,0): x=5,y=30: cells (5,31),(6,31),(7,31),(6,32) — all free.
  assert.equal(g.current.x, 5);
  assert.equal(g.current.y, 30);
});

test('wall kicks (I): I against left wall uses kick #3 of 1->2 (dx=+2), exact x/y/rot', () => {
  const g = new Game({ seed: 1 });
  g.start();
  clearBoard(g);
  // Vertical I in rot=1 occupies column x+2. Flush against the left wall: col 0 -> x=-2 (bbox may extend off-board).
  setPiece(g, 'I', -2, 30, 1);
  assert.deepEqual(g.cellsOf('I', -2, 30, 1).map(([c]) => c), [0, 0, 0, 0]);

  const ok = g.rotateCW(); // 1 -> 2
  assert.equal(ok, true);
  assert.equal(g.current.rot, 2);
  // I kicks for 1->2: (0,0),(-1,0),(+2,0),(-1,+2),(+2,-1).
  // Base rot=2 at x=-2 spans cols -2..1 -> out of bounds; kick #2 (-1) worse. Kick #3 (+2,0) applies.
  assert.equal(g.current.x, 0);
  assert.equal(g.current.y, 30);
  assert.deepEqual(sorted(g.cellsOf('I', g.current.x, g.current.y, g.current.rot)), [
    [0, 32], [1, 32], [2, 32], [3, 32],
  ]);
});

test('rotation fails when all five kick tests collide', () => {
  const g = new Game({ seed: 1 });
  g.start();
  clearBoard(g);
  // T rot=0 at x=4,y=30 (cells (5,30),(4,31),(5,31),(6,31)). JLSTZ kicks for 0->1:
  //   base (x=4): needs (5,32)          -> block board[32][5]
  //   #2 (-1,0) x=3,y=30: needs (4,30)  -> block board[30][4]
  //   #3 (-1,-1) x=3,y=29: needs (4,29) -> block board[29][4]
  //   #4 (0,+2) x=4,y=32: needs (5,32)  -> already blocked
  //   #5 (-1,+2) x=3,y=32: needs (4,32) -> block board[32][4]
  setPiece(g, 'T', 4, 30);
  g.board[32][5] = 'X';
  g.board[30][4] = 'X';
  g.board[29][4] = 'X';
  g.board[32][4] = 'X';
  assert.equal(g.rotateCW(), false);
  // Piece unchanged.
  assert.deepEqual(g.current, { type: 'T', x: 4, y: 30, rot: 0 });
});
