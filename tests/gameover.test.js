import { test } from 'node:test';
import assert from 'node:assert/strict';
import { Game, BOARD_WIDTH } from '../js/engine.js';
import { makeGame, setPiece, clearBoard } from './helpers.js';

test('game over: block-out at spawn sets state to over and fires the gameover event', () => {
  const events = [];
  const g = new Game({ seed: 42, onEvent: (e) => events.push(e) });
  g.start();
  clearBoard(g);

  // Fill rows 21-23 in cols 1-9 so any spawn overlaps existing blocks.
  // Col 0 stays empty so no row is complete (no accidental line clears).
  for (let r = 21; r <= 23; r++) {
    for (let c = 1; c < BOARD_WIDTH; c++) g.board[r][c] = 'X';
  }

  // Lock the current piece -> next piece spawns into the filled area.
  setPiece(g, 'O', 4, 21);
  g.hardDrop();

  assert.equal(g.state, 'over');
  const over = events.find((e) => e.type === 'gameover');
  assert.ok(over, 'a gameover event must be fired');
});

test('game over: input is ignored once the state is over', () => {
  const g = new Game({ seed: 42 });
  g.start();
  clearBoard(g);
  for (let r = 21; r <= 23; r++) {
    for (let c = 1; c < BOARD_WIDTH; c++) g.board[r][c] = 'X';
  }
  setPiece(g, 'O', 4, 21);
  g.hardDrop();
  assert.equal(g.state, 'over');

  assert.equal(g.moveLeft(), false);
  assert.equal(g.rotateCW(), false);
  assert.equal(g.softDrop(), false);
  assert.equal(g.holdPiece(), false);
  const before = JSON.stringify(g.board);
  g.tick();
  assert.equal(JSON.stringify(g.board), before, 'tick must not mutate the board after game over');
});

test('game over: a piece can still lock normally when spawn is clear', () => {
  const { game: g } = makeGame();
  g.start();
  // Fill only rows 24+ (below the spawn area) — spawning must succeed.
  for (let r = 24; r <= 39; r++) {
    for (let c = 0; c < BOARD_WIDTH; c++) if (c !== 5) g.board[r][c] = 'X';
  }
  assert.equal(g.state, 'playing');
  assert.ok(g.current);
});
