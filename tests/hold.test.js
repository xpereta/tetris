import { test } from 'node:test';
import assert from 'node:assert/strict';
import { Game } from '../js/engine.js';
import { makeGame, setPiece, clearBoard, forceNext } from './helpers.js';

test('hold: holding when hold is empty puts the current piece into hold and spawns next', () => {
  const { game: g, events } = makeGame();
  g.start();
  clearBoard(g);
  forceNext(g, 'I'); // known upcoming piece
  setPiece(g, 'T', 3, 21);

  assert.equal(g.hold, null);
  assert.equal(g.canHold, true);
  const ok = g.holdPiece();
  assert.equal(ok, true);
  assert.equal(g.hold, 'T');
  assert.equal(g.current.type, 'I', 'the queued piece must spawn into the current slot');
  assert.equal(g.canHold, false, 'cannot hold again until the next lock');

  const holdEvent = events.find((e) => e.type === 'hold');
  assert.ok(holdEvent);
  assert.equal(holdEvent.piece, 'I', 'the hold event reports the newly current piece');
});

test('hold: cannot re-hold before the next lock (double-hold blocked)', () => {
  const { game: g } = makeGame();
  g.start();
  clearBoard(g);
  forceNext(g, 'I', 'O'); // must be called AFTER start() — start() resets the queue
  setPiece(g, 'T', 3, 21);

  assert.equal(g.holdPiece(), true); // T -> hold, I spawns
  assert.equal(g.canHold, false);
  assert.equal(g.holdPiece(), false, 'second hold before a lock must be rejected');
  assert.equal(g.current.type, 'I', 'current piece unchanged after the rejected hold');

  // After the piece locks, holding is allowed again.
  g.hardDrop(); // locks the I; next queued piece (O) spawns
  assert.equal(g.canHold, true);
  assert.equal(g.current.type, 'O');
  assert.equal(g.holdPiece(), true);
  assert.equal(g.hold, 'O', 'the O goes into hold...');
  assert.equal(g.current.type, 'T', '...and the held T comes back out');
});

test('hold: swapping puts the current piece into hold and spawns the held one', () => {
  const { game: g } = makeGame();
  g.start();
  clearBoard(g);
  forceNext(g, 'S');
  setPiece(g, 'T', 3, 21);

  assert.equal(g.holdPiece(), true); // hold=T, S spawns
  g.hardDrop(); // lock S -> canHold restored

  forceNext(g, 'Z');
  setPiece(g, 'L', 3, 21);
  assert.equal(g.holdPiece(), true);
  assert.equal(g.hold, 'L');
  assert.equal(g.current.type, 'T', 'the previously held T must spawn back out');
});

test('hold: works from a fresh game with the natural first piece', () => {
  const g = new Game({ seed: 42 });
  g.start();
  const firstType = g.current.type;
  assert.equal(g.holdPiece(), true);
  assert.equal(g.hold, firstType);
  assert.notEqual(g.current.type, null);
});
