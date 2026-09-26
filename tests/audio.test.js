// tests/audio.test.js — CONTRACT-V2 §4 gate 1: audio module in Node.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

// Importing must not throw and must not create an AudioContext (no DOM here).
const audioMod = await import('../js/audio.js');
const melodyMod = await import('../js/melody.js');

test('audio.js imports cleanly in Node without creating an AudioContext', () => {
  assert.equal(typeof audioMod.TetrisAudio, 'function');
  // No global AudioContext exists in Node — if the module touched one at
  // import time it would have thrown ReferenceError above.
  assert.equal(typeof globalThis.AudioContext, 'undefined');
});

test('TetrisAudio instantiates; setMuted(true) returns true', () => {
  const a = new audioMod.TetrisAudio();
  assert.equal(a.muted, false); // fresh state (no localStorage in Node)
  assert.equal(a.setMuted(true), true);
  assert.equal(a.muted, true);
  assert.equal(a.setMuted(false), false);
});

test('playSfx does not throw when ctx is absent (safe no-op before unlock)', () => {
  const a = new audioMod.TetrisAudio();
  for (const name of [
    'move', 'rotate', 'softDrop', 'hardDrop', 'lock',
    'clear1', 'clear2', 'clear3', 'tetris', 'tspin',
    'hold', 'levelUp', 'gameOver', 'start', 'pause',
  ]) {
    assert.doesNotThrow(() => a.playSfx(name), `playSfx('${name}') must no-op safely`);
  }
});

test('unlock/startMusic/stopMusic are safe no-ops in Node (no window)', () => {
  const a = new audioMod.TetrisAudio();
  assert.equal(a.unlock(), false); // no AudioContext available → reports failure, no throw
  assert.doesNotThrow(() => a.startMusic());
  assert.doesNotThrow(() => a.stopMusic());
});

test('melody.json parses with 4 tracks and valid note timing', () => {
  const raw = fs.readFileSync(new URL('../assets/melody.json', import.meta.url), 'utf8');
  const m = JSON.parse(raw);
  assert.ok(Number.isFinite(m.division) && m.division > 0, 'division must be positive');
  assert.equal(m.tracks.length, 4, 'exactly 4 tracks: melody/harmony/bass/accompaniment');
  for (const track of m.tracks) {
    assert.ok(Array.isArray(track) && track.length > 0, 'each track has notes');
    for (const [start, midi, dur] of track) {
      assert.ok(start >= 0, `note start ${start} must be >= 0`);
      assert.ok(dur > 0, `note duration ${dur} must be > 0`);
      assert.ok(Number.isInteger(midi), 'midi note is an integer');
    }
  }
});

test('js/melody.js data is identical to assets/melody.json (provenance)', () => {
  const raw = fs.readFileSync(new URL('../assets/melody.json', import.meta.url), 'utf8');
  assert.equal(JSON.stringify(melodyMod.MELODY), JSON.stringify(JSON.parse(raw)));
  assert.ok(Number.isFinite(melodyMod.LOOP_SECONDS) && melodyMod.LOOP_SECONDS > 0);
});
