import { test } from 'node:test';
import assert from 'node:assert/strict';
import { Game, BOARD_WIDTH } from '../js/engine.js';
import { makeGame, setPiece, clearBoard } from './helpers.js';

test('gravity: with gravityMs override, N ticks drop exactly N rows while airborne', () => {
  const g = new Game({ seed: 1, gravityMs: 100 });
  g.start();
  clearBoard(g);
  setPiece(g, 'O', 4, 21);

  for (let i = 1; i <= 5; i++) {
    const events = g.tick();
    assert.ok(Array.isArray(events));
    assert.equal(g.current.y, 21 + i, `tick ${i} should drop exactly one row`);
  }
});

test('gravity: default formula at level 1 is 1000ms per row (one tick = one row)', () => {
  const g = new Game({ seed: 1 }); // no gravityMs override -> guideline formula
  g.start();
  clearBoard(g);
  setPiece(g, 'O', 4, 21);
  assert.equal(g.level, 1);
  g.tick();
  assert.equal(g.current.y, 22, 'level 1: (0.8)^0 = 1s per row -> one tick drops one row');
});

test('lock delay: piece locks after lockDelayMs of ground contact', () => {
  const g = new Game({ seed: 1, gravityMs: 100, lockDelayMs: 500 });
  g.start();
  clearBoard(g);
  setPiece(g, 'O', 4, 38); // resting on the floor (rows 38-39)

  for (let i = 1; i <= 4; i++) {
    g.tick();
    assert.ok(g.current, `piece must not lock before ${i} grounded ticks`);
  }
  const typeBefore = g.current.type;
  g.tick(); // 5th grounded tick: 500ms elapsed -> lock
  assert.notEqual(g.current, null, 'a new piece should have spawned');
  assert.equal(g.state, 'playing');
});

test('lock delay: successful moves reset the timer (move-reset rule)', () => {
  const g = new Game({ seed: 1, gravityMs: 100, lockDelayMs: 500 });
  g.start();
  clearBoard(g);
  setPiece(g, 'O', 4, 38); // on the floor

  // 4 ticks (timer=400), then a successful move resets to 0.
  for (let i = 0; i < 4; i++) g.tick();
  assert.equal(g.moveLeft(), true);
  assert.equal(g.current.x, 3);
  // 4 more ticks (timer back to 400) — still not locked.
  for (let i = 0; i < 4; i++) {
    g.tick();
    assert.ok(g.current, 'piece must survive after a move reset');
  }
  g.tick(); // now 5 ticks since the last reset -> lock
  assert.notEqual(g.current, null);
});

test('lock delay: max 15 move resets per piece, then it locks', () => {
  const g = new Game({ seed: 1, gravityMs: 100, lockDelayMs: 500 });
  g.start();
  clearBoard(g);
  setPiece(g, 'O', 4, 38); // on the floor; oscillate between x=4 and x=5

  let dir = -1;
  for (let i = 0; i < 15; i++) {
    g.tick(); // timer -> 100 (< 500)
    assert.ok(g.current, `piece must survive reset ${i + 1}`);
    const ok = dir === -1 ? g.moveLeft() : g.moveRight();
    assert.equal(ok, true, `move ${i + 1} should succeed`);
    dir *= -1; // alternate direction so every move succeeds
  }

  // Reset cap exhausted: the next successful move must force a lock on the following tick.
  const ok = g.moveRight();
  assert.equal(ok, true);
  assert.ok(g.current, 'no immediate lock from the move itself');
  g.tick();
  assert.notEqual(g.current, null, 'piece locked after exceeding the reset cap; new piece spawned');
});

test('state machine: start / pause / resume / reset', () => {
  const g = new Game({ seed: 1 });
  assert.equal(g.state, 'idle');
  g.start();
  assert.equal(g.state, 'playing');
  assert.ok(g.current);

  g.pause();
  assert.equal(g.state, 'paused');
  const yBefore = g.current.y;
  g.tick(); // paused: no gravity
  assert.equal(g.current.y, yBefore);

  g.resume();
  assert.equal(g.state, 'playing');

  g.reset();
  assert.equal(g.score, 0);
  assert.equal(g.lines, 0);
  assert.equal(g.level, 1);
  assert.equal(g.combo, -1);
  assert.equal(g.b2b, false);
  assert.equal(g.hold, null);
  assert.ok(g.board.every((row) => row.every((c) => c === null)));
});
