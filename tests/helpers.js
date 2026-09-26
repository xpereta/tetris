// Shared helpers for the unit tests (not a test file itself).
import { Game } from '../js/engine.js';

/** Create a deterministic game that records every event in `events`. */
export function makeGame(opts = {}) {
  const events = [];
  const game = new Game({
    seed: 42,
    gravityMs: 100,
    lockDelayMs: 500,
    onEvent: (e) => events.push(e),
    ...opts,
  });
  return { game, events };
}

/** Place a piece directly (white-box helper for deterministic setups). */
export function setPiece(game, type, x, y, rot = 0) {
  game.current = { type, x, y, rot };
  game._lastMoveWasKick = false;
  game._gravityAccumMs = 0;
  game._lockTimerMs = null;
  game._grounded = game.isOnGround();
}

export function clearBoard(game) {
  for (let r = 0; r < game.board.length; r++) game.board[r].fill(null);
}

/** Fill `row` in every column except the listed ones. */
export function fillRow(game, row, exceptCols = []) {
  for (let c = 0; c < 10; c++) {
    if (!exceptCols.includes(c)) game.board[row][c] = 'X';
  }
}

/** Put specific piece types at the front of the upcoming queue. */
export function forceNext(game, ...types) {
  game.queue.unshift(...types);
}
