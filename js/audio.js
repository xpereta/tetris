// js/audio.js — procedural Web Audio for Tetris v2 (CONTRACT-V2 §1).
//
// Pure ESM and Node-safe: no DOM access, no AudioContext at import time. All
// context creation is deferred to unlock() (first user gesture), per the
// browser autoplay policy. Music = Korobeiniki from js/melody.js (extracted
// verbatim from assets/melody.json). SFX are short procedural blips; everything
// routes through one master gain so setMuted() kills all audio in one place.

import { MELODY, LOOP_SECONDS } from './melody.js';

const LOOKAHEAD_MS = 25; // scheduler tick interval (contract: ~every 25 ms)
const SCHEDULE_AHEAD_S = 0.12; // schedule anything within the next 120 ms
const BACKLOG_MAX_S = 2; // after throttling, skip bars missed by more than this
const MUTE_KEY = 'tetris.muted';

/** MIDI note number → frequency in Hz (A4 = 69 = 440 Hz). */
function midiToFreq(n) {
  return 440 * Math.pow(2, (n - 69) / 12);
}

/** localStorage or null — gated on window because Node's experimental
 * globalThis.localStorage accessor warns (and is unavailable) without flags. */
function storage() {
  if (typeof window === 'undefined') return null;
  try { return window.localStorage || null; } catch { return null; }
}

export class TetrisAudio {
  constructor() {
    this._ctx = null; // AudioContext — created on unlock() only
    this._master = null; // master gain: all audio routes through here
    this._musicGain = null; // music bus (faded for a clean stop)
    this._noiseBuf = null; // cached white-noise buffer (SFX)
    this._muted = false;
    const s = storage();
    if (s) { try { this._muted = s.getItem(MUTE_KEY) === 'true'; } catch { /* ignore */ } }
    this._musicOn = false;
    this._timer = null;
    // Per-track scheduler state: absolute ctx-time of the current loop start +
    // index of the next note to schedule. Tracks wrap independently but stay in
    // phase because every track shares the same LOOP_SECONDS length.
    this._trackBase = [0, 0, 0, 0];
    this._trackIdx = [0, 0, 0, 0];
    this._lastSoftDropAt = -1;
  }

  get muted() { return this._muted; }

  /** Master mute (music + SFX). Persists to localStorage. Returns new state. */
  setMuted(b) {
    this._muted = !!b;
    const s = storage();
    if (s) { try { s.setItem(MUTE_KEY, String(this._muted)); } catch { /* ignore */ } }
    if (this._ctx && this._master) {
      const t = this._ctx.currentTime;
      this._master.gain.cancelScheduledValues(t);
      // short ramp so unmuting doesn't click
      this._master.gain.setTargetAtTime(this._muted ? 0 : 1, t, 0.01);
    }
    return this._muted;
  }

  /** Call on first user gesture: creates/resumes the context and starts music. */
  unlock() {
    if (typeof window === 'undefined') return false; // Node / headless: safe no-op
    const AC = window.AudioContext || window.webkitAudioContext;
    if (!AC) return false;
    if (!this._ctx) {
      this._ctx = new AC();
      this._master = this._ctx.createGain();
      this._master.gain.value = this._muted ? 0 : 1;
      this._master.connect(this._ctx.destination);
      this._musicGain = this._ctx.createGain();
      this._musicGain.gain.value = 1;
      this._musicGain.connect(this._master);
    }
    if (this._ctx.state === 'suspended') this._ctx.resume().catch(() => {});
    this.startMusic(); // contract: unlock starts the music loop
    return true;
  }

  /** Idempotent: start the Korobeiniki loop from its beginning. */
  startMusic() {
    if (!this._ctx || this._musicOn) return;
    const t0 = this._ctx.currentTime + 0.15; // small lead-in so notes don't clip
    for (let i = 0; i < MELODY.tracks.length; i++) {
      this._trackBase[i] = t0;
      this._trackIdx[i] = 0;
    }
    const t = this._ctx.currentTime;
    this._musicGain.gain.cancelScheduledValues(t);
    this._musicGain.gain.setValueAtTime(1, t); // undo any stop fade
    this._musicOn = true;
    this._timer = setInterval(() => this._schedule(), LOOKAHEAD_MS);
  }

  /** Stop the loop (pause / game over). Fades out already-scheduled notes. */
  stopMusic() {
    if (!this._ctx) return;
    if (this._timer != null) { clearInterval(this._timer); this._timer = null; }
    this._musicOn = false;
    const t = this._ctx.currentTime;
    this._musicGain.gain.cancelScheduledValues(t);
    this._musicGain.gain.setTargetAtTime(0, t, 0.02);
  }

  // ------------------------------------------------------------- music engine

  /** Lookahead scheduler: every tick, schedule notes that start within the next
   * SCHEDULE_AHEAD_S seconds of context time. Survives tab throttling by
   * skipping bars missed by more than BACKLOG_MAX_S (slight drift is acceptable
   * per contract; crashes are not). */
  _schedule() {
    if (!this._ctx || !this._musicOn) return;
    if (this._ctx.state !== 'running') return; // suspended: time frozen, skip
    const now = this._ctx.currentTime;
    const horizon = now + SCHEDULE_AHEAD_S;
    for (let t = 0; t < MELODY.tracks.length; t++) {
      const notes = MELODY.tracks[t];
      let i = this._trackIdx[t];
      // Survive tab throttling: if the next due note is more than BACKLOG_MAX_S
      // in the past, jump forward one loop (skip the missed bar) instead of
      // fast-forwarding a whole bar at once. Small backlogs play as a quick
      // catch-up run-through — graceful drift per contract.
      for (;;) {
        const due = this._trackBase[t] + notes[i][0];
        if (due >= now - BACKLOG_MAX_S) break;
        this._trackBase[t] += LOOP_SECONDS;
        i = 0;
      }
      let scheduled = 0;
      for (;;) {
        if (i >= notes.length) { this._trackBase[t] += LOOP_SECONDS; i = 0; continue; }
        const at = this._trackBase[t] + notes[i][0];
        if (at > horizon) break;
        // After heavy tab throttling many notes can be "due" at once — cap the
        // burst per tick and chew through the rest on following ticks (they get
        // clamped to ~now, so a missed bar plays as a fast run-through instead
        // of an instant wall of audio).
        if (scheduled >= 12) break;
        this._playNote(t, notes[i], Math.max(at, now + 0.01)); // never in the past
        scheduled++;
        i++;
      }
      this._trackIdx[t] = i;
    }
  }

  /** Schedule one note of track t at context time `at`. */
  _playNote(t, [, midi, durSec], at) {
    const freq = midiToFreq(midi);
    let type, peak, lp = null, pluck = false;
    switch (t) {
      case 0: type = 'square'; peak = 0.16; lp = 2500; break; // melody
      case 1: type = 'triangle'; peak = 0.10; break;          // harmony
      case 2: type = 'sawtooth'; peak = 0.18; lp = 400; break; // bass
      default: type = 'triangle'; peak = 0.07; pluck = true; break; // accompaniment
    }
    const dur = pluck ? Math.min(durSec, 0.15) : durSec; // "short" plucks (§1)
    this._tone({ type, f0: freq, at, dur, peak, lp, dest: this._musicGain, tau: pluck ? 0.03 : null });
  }

  // ------------------------------------------------------------- SFX (CONTRACT-V2 §1)

  /** Play a named SFX. Safe no-op before unlock() or when muted. */
  playSfx(name) {
    if (!this._ctx || this._muted) return;
    const t = this._ctx.currentTime + 0.01;
    switch (name) {
      case 'move': // tiny blip, square 660 Hz, ~20 ms
        this._tone({ type: 'square', f0: 660, at: t, dur: 0.02, peak: 0.05 });
        break;
      case 'rotate': // 30 ms sweep 440 → 587 Hz
        this._tone({ type: 'square', f0: 440, f1: 587, at: t, dur: 0.03, peak: 0.06 });
        break;
      case 'softDrop': { // 15 ms tick 220 Hz — throttled to max once per 50 ms
        const now = this._ctx.currentTime;
        if (now - this._lastSoftDropAt < 0.05) return;
        this._lastSoftDropAt = now;
        this._tone({ type: 'square', f0: 220, at: t, dur: 0.015, peak: 0.04 });
        break;
      }
      case 'hardDrop': // noise burst + low 90 Hz sine thump
        this._noise(t, 0.06, 0.12);
        this._tone({ type: 'sine', f0: 90, at: t, dur: 0.12, peak: 0.12 });
        break;
      case 'lock': // 30 ms square 180 Hz
        this._tone({ type: 'square', f0: 180, at: t, dur: 0.03, peak: 0.07 });
        break;
      case 'clear1': case 'clear2': case 'clear3': { // rising triangle arpeggio ~120 ms
        const notes = [523.25, 659.25, 783.99]; // C5 E5 G5
        if (name === 'clear2') notes.push(987.77); // + B5
        if (name === 'clear3') notes.push(1174.66); // + D6
        this._arpeggio(notes, t, 0.12, 0.09, 'triangle');
        break;
      }
      case 'tetris': { // bigger 4-note fanfare + noise shimmer, ~250 ms
        this._arpeggio([523.25, 659.25, 783.99, 1046.5], t, 0.2, 0.14, 'triangle');
        this._noise(t + 0.16, 0.1, 0.05, 3000); // high shimmer
        break;
      }
      case 'tspin': { // quick two-tone ding 880 → 1319 Hz, ~150 ms
        this._tone({ type: 'triangle', f0: 880, at: t, dur: 0.07, peak: 0.1 });
        this._tone({ type: 'triangle', f0: 1319, at: t + 0.06, dur: 0.09, peak: 0.1 });
        break;
      }
      case 'hold': // soft 523 Hz blip, 40 ms
        this._tone({ type: 'sine', f0: 523.25, at: t, dur: 0.04, peak: 0.06 });
        break;
      case 'levelUp': // ascending A4-C#5-E5 run, ~200 ms
        this._arpeggio([440, 554.37, 659.25], t, 0.18, 0.1, 'triangle');
        break;
      case 'gameOver': { // descending minor phrase E5-D5-B4-G4, sawtooth lowpass ~700 ms
        const notes = [659.25, 587.33, 493.88, 392];
        for (let i = 0; i < notes.length; i++) {
          this._tone({ type: 'sawtooth', f0: notes[i], at: t + i * 0.16, dur: 0.18, peak: 0.12, lp: 1500 });
        }
        break;
      }
      case 'start': case 'pause': // single soft blip
        this._tone({ type: 'sine', f0: 660, at: t, dur: 0.04, peak: 0.05 });
        break;
    }
  }

  /** Evenly spaced arpeggio of `notes` spanning ~total seconds. */
  _arpeggio(notes, at, total, peak, type) {
    const step = total / notes.length;
    for (let i = 0; i < notes.length; i++) {
      this._tone({ type, f0: notes[i], at: at + i * step, dur: Math.min(0.08, step * 1.6), peak });
    }
  }

  // ------------------------------------------------------------- low-level helpers

  /** One oscillator with a short attack and exponential-ish decay envelope. */
  _tone({ type = 'sine', f0, f1 = null, at, dur, peak = 0.05, lp = null, dest = null, tau = null }) {
    const ctx = this._ctx;
    const o = ctx.createOscillator();
    o.type = type;
    o.frequency.setValueAtTime(f0, at);
    if (f1 != null) o.frequency.linearRampToValueAtTime(f1, at + dur); // sweep
    let node = o;
    if (lp) {
      const f = ctx.createBiquadFilter();
      f.type = 'lowpass';
      f.frequency.value = lp;
      node.connect(f);
      node = f;
    }
    const g = ctx.createGain();
    // Envelope: ≤8 ms attack, then setTargetAtTime decay with time constant tau
    // (smaller tau = pluckier). Values stay > 0 so ramps never glitch.
    const a = Math.min(0.008, dur * 0.3);
    g.gain.setValueAtTime(0.0001, at);
    g.gain.linearRampToValueAtTime(peak, at + a);
    g.gain.setTargetAtTime(0.0001, at + a, tau ?? Math.max(0.02, dur * 0.3));
    node.connect(g);
    g.connect(dest || this._master);
    o.start(at);
    o.stop(at + dur + 0.15); // headroom for the decay tail
  }

  /** White-noise burst (hard-drop thump, tetris shimmer). */
  _noise(at, dur, peak = 0.1, hp = null) {
    const ctx = this._ctx;
    if (!this._noiseBuf) {
      const sr = ctx.sampleRate;
      const buf = ctx.createBuffer(1, Math.ceil(sr * 0.3), sr); // 300 ms covers all SFX
      const d = buf.getChannelData(0);
      for (let i = 0; i < d.length; i++) d[i] = Math.random() * 2 - 1;
      this._noiseBuf = buf;
    }
    const src = ctx.createBufferSource();
    src.buffer = this._noiseBuf;
    let node = src;
    if (hp) {
      const f = ctx.createBiquadFilter();
      f.type = 'highpass';
      f.frequency.value = hp;
      node.connect(f);
      node = f;
    }
    const g = ctx.createGain();
    g.gain.setValueAtTime(peak, at);
    g.gain.setTargetAtTime(0.0001, at + dur * 0.3, Math.max(0.015, dur * 0.25));
    node.connect(g);
    g.connect(this._master);
    src.start(at);
    src.stop(at + dur + 0.1);
  }
}

export default TetrisAudio; // convenience (the named export is the contract API)
