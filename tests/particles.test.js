// tests/particles.test.js — CONTRACT-V3 §4 gate 1: ParticleSystem in Node.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { ParticleSystem } from '../js/particles.js';
import { fullVisibleRows, COLORS } from '../js/ui.js'; // pure helpers — safe in Node (no DOM at import)

test('particles: imports cleanly and instantiates with no DOM', () => {
  const ps = new ParticleSystem(); // must not touch document/window
  assert.equal(ps.count, 0);
});

test('particles: spawnBurst/spawnTrail/spawnClearRow increase count; update culls to 0', () => {
  const ps = new ParticleSystem();
  ps.spawnBurst(10, 20, '#ff5c5c', 8);
  assert.equal(ps.count, 8);

  ps.spawnTrail(30, 40, 28); // exactly one particle per call
  assert.equal(ps.count, 9);

  const before = ps.count;
  ps.spawnClearRow(100, 10, 28); // ~widthCells×3 = 30 particles (v3.1 density)
  const added = ps.count - before;
  assert.ok(added >= 25 && added <= 35, `clear row should add ~30 (got ${added})`);

  const total = ps.count;
  // Max lifetime is now 800 ms — stepping past that must cull everything.
  for (let i = 0; i < 12 && ps.count > 0; i++) ps.update(200);
  assert.equal(ps.count, 0, `all ${total} particles should be culled after enough update() time`);
});

test('particles: spawnClearRow honors explicit colors and count overrides', () => {
  const ps = new ParticleSystem();
  ps.spawnClearRow(50, 10, 28, [COLORS.I, COLORS.T], 7); // exact count + real cell colors
  assert.equal(ps.count, 7);
});

test('fullVisibleRows: reports the ACTUAL full visible rows (not bottom-N)', () => {
  const W = 10;
  // 40-row board: only row 39 (bottom, vr=19) and row 25 (vr=5) are full.
  const board = Array.from({ length: 40 }, () => new Array(W).fill(null));
  for (let c = 0; c < W; c++) { board[39][c] = 'I'; board[25][c] = c % 2 ? 'T' : 'Z'; }
  // A full row in the HIDDEN area (row 10) must NOT be reported.
  for (let c = 0; c < W; c++) board[10][c] = 'O';
  const out = fullVisibleRows(board);
  assert.deepEqual(out.map((r) => r.vr), [5, 19], 'visible rows only, in order');
  assert.deepEqual([...out[0].colors].sort(), ['T', 'Z'], 'distinct cell types of the row');
  assert.equal(out[1].colors.length, 1);
});

test('fullVisibleRows: empty board → no rows; all-full visible area → 20 rows', () => {
  const W = 10;
  const empty = Array.from({ length: 40 }, () => new Array(W).fill(null));
  assert.deepEqual(fullVisibleRows(empty), []);
  const full = Array.from({ length: 40 }, (_, r) => (r >= 20 ? new Array(W).fill('L') : new Array(W).fill(null)));
  assert.equal(fullVisibleRows(full).length, 20);
});

test('particles: hard cap of 600 — spawning 1000 leaves count ≤ 600', () => {
  const ps = new ParticleSystem();
  for (let i = 0; i < 125; i++) ps.spawnBurst(0, 0, '#ffffff', 8); // 1000 particles requested
  assert.ok(ps.count <= 600, `count ${ps.count} exceeds the hard cap of 600`);
  assert.equal(ps.count, 600, 'cap should hold exactly at 600 after overflow');
});

test('particles: draw() does not throw against a stub ctx2d (no-op methods)', () => {
  const ps = new ParticleSystem();
  ps.spawnBurst(5, 5, '#3fd8f0', 16);
  ps.spawnTrail(9, 9, 28);
  ps.spawnClearRow(40, 10, 28);
  const calls = { arc: 0, fill: 0 };
  const stubCtx = {
    globalAlpha: 1,
    fillStyle: '',
    beginPath() {},
    arc(x, y, r) { calls.arc++; assert.ok(Number.isFinite(r) && r >= 0); },
    fill() { calls.fill++; },
  };
  ps.draw(stubCtx); // must not throw
  assert.equal(calls.arc, ps.count, 'one arc per live particle');
  assert.equal(calls.fill, ps.count, 'one fill per live particle');
});

test('particles: update() is O(count)-friendly and keeps count monotonic under culling', () => {
  const ps = new ParticleSystem();
  ps.spawnBurst(0, 0, '#ffd75e', 64);
  const n0 = ps.count;
  ps.update(16); // one frame — nothing should die this fast (min life 350 ms)
  assert.equal(ps.count, n0, 'no particle may die before its lifetime');
  ps.update(800);
  assert.equal(ps.count, 0);
});
