
import { Game } from './js/engine.js';
import { AutoPlayer } from './js/autoplayer.js';

const seeds = [1, 2, 3, 42, 99, 123, 777, 2026, 55555, 987654];
let allOk = true;
for (const seed of seeds) {
  const clears = [];
  let maxScore = 0;
  const g = new Game({
    seed, gravityMs: 100, lockDelayMs: 200,
    onEvent: (e) => { if (e.type === 'clear') clears.push(e); },
  });
  g.start();
  const ap = new AutoPlayer(g);
  let iters = 0;
  try {
    while (g.state !== 'over' && iters < 20000) {
      ap.step();
      if (g.state === 'playing') maxScore = Math.max(maxScore, g.score);
      g.tick();
      iters++;
    }
  } catch (err) {
    console.log(JSON.stringify({ seed, error: String(err), stack: err.stack?.split('\n')[1] }));
    allOk = false;
    continue;
  }
  const scoreMonotonic = maxScore <= g.score + 200; // final >= near-max (score only grows)
  console.log(JSON.stringify({
    seed, state: g.state, iters, score: g.score, lines: g.lines, level: g.level,
    clears: clears.length, clearTypes: [...new Set(clears.map(c => c.lines))].sort(),
    tspins: clears.filter(c => c.tSpin).length,
  }));
}
console.log('ALL_OK=' + allOk);
