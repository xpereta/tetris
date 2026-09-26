import { test } from 'node:test';
import assert from 'node:assert/strict';
import { Game } from '../js/engine.js';
import { AutoPlayer } from '../js/autoplayer.js';

test('autoplayer: plays a full seeded game to game over without exceptions', () => {
  const events = [];
  const game = new Game({
    seed: 42,
    gravityMs: 100,
    lockDelayMs: 500,
    onEvent: (e) => events.push(e),
  });
  const ai = new AutoPlayer(game);
  game.start();

  let iterations = 0;
  while (game.state !== 'over' && iterations < 20000) {
    ai.step(); // one decision per piece: rotate/move to target, then hard drop
    game.tick(); // advance gravity for the freshly spawned piece
    iterations++;
  }

  assert.equal(game.state, 'over', `game should end within 20000 iterations (stopped at ${iterations})`);
  assert.ok(iterations <= 20000, `iteration budget exceeded: ${iterations}`);
  assert.ok(
    game.score > 1000,
    `final score ${game.score} should exceed 1000 after a full game`,
  );

  const clears = events.filter((e) => e.type === 'clear');
  assert.ok(clears.length >= 1, 'at least one line clear must occur during the game');

  // Sanity: board height at end is within the physical board.
  let topFilledRow = -1;
  for (let r = 0; r < game.board.length; r++) {
    if (game.board[r].some((c) => c !== null)) {
      topFilledRow = r;
      break;
    }
  }
  assert.ok(topFilledRow >= -1 && topFilledRow < 40, 'board height must be sane (< 40 rows used)');
});
