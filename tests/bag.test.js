import { test } from 'node:test';
import assert from 'node:assert/strict';
import { Game } from '../js/engine.js';
import { clearBoard } from './helpers.js';

/**
 * Play `n` pieces and return the sequence of piece types. The board is wiped
 * after every lock so the game can never block out — this isolates the pure
 * 7-bag randomizer output, which is what these tests are about.
 */
function playSequence(seed, n) {
  const g = new Game({ seed });
  g.start();
  const out = [];
  for (let i = 0; i < n && g.state === 'playing'; i++) {
    out.push(g.current.type);
    g.hardDrop();
    clearBoard(g);
  }
  return out;
}

test('7-bag: first 7 pieces of a fresh game contain each piece exactly once', () => {
  const seq = playSequence(123, 7);
  assert.equal(seq.length, 7);
  const counts = {};
  for (const t of seq) counts[t] = (counts[t] ?? 0) + 1;
  for (const t of ['I', 'O', 'T', 'S', 'Z', 'J', 'L']) {
    assert.equal(counts[t], 1, `piece ${t} should appear exactly once in the first bag`);
  }
});

test('7-bag: queue always holds at least 5 upcoming pieces', () => {
  const g = new Game({ seed: 7 });
  g.start();
  for (let i = 0; i < 20 && g.state === 'playing'; i++) {
    assert.ok(g.queue.length >= 5, `queue length ${g.queue.length} < 5 after piece ${i}`);
    g.hardDrop();
    clearBoard(g);
  }
});

test('7-bag: same seed produces the identical sequence', () => {
  const a = playSequence(99, 21).join('');
  const b = playSequence(99, 21).join('');
  assert.equal(a.length, 21);
  assert.equal(a, b);
});

test('7-bag: different seeds produce different sequences', () => {
  const a = playSequence(1, 21).join('');
  const b = playSequence(2, 21).join('');
  assert.notEqual(a, b);
});

test('7-bag: every bag of 7 is a permutation (checked over 4 bags)', () => {
  const seq = playSequence(5, 28);
  assert.equal(seq.length, 28);
  for (let bag = 0; bag < 4; bag++) {
    const seven = seq.slice(bag * 7, bag * 7 + 7);
    assert.deepEqual([...seven].sort(), ['I', 'J', 'L', 'O', 'S', 'T', 'Z'], `bag ${bag + 1} must be a permutation of the 7 pieces`);
  }
});
