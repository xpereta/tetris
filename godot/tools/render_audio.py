#!/usr/bin/env python3
"""tools/render_audio.py — offline render of the web game's WebAudio synthesis
into 16-bit mono WAVs for Godot (Phase 4, PLAN.md §audio).

Replicates js/audio.js exactly:
  - music: 4 tracks from assets/melody.json (seconds-based note times)
      t0 melody        square   peak .16 lowpass 2500 Hz
      t1 harmony       triangle peak .10
      t2 bass          sawtooth peak .18 lowpass 400 Hz
      t3 accompaniment triangle peak .07 pluck (dur<=.15, tau=.03)
    envelope per _tone(): linear attack min(.008, dur*.3), then exponential
    approach to 0.0001 with tau = max(.02, dur*.3) (or .03 for plucks).
  - sfx: one short WAV per playSfx() name, same _tone/_noise recipes.

Lowpass/highpass are first-order IIR approximations of the WebAudio biquads —
faithful enough for chiptune material; the web game stays the reference.

Usage: python3 tools/render_audio.py   (run from godot/ or anywhere)
Output: assets/audio/music_loop.wav + assets/audio/sfx_*.wav
"""
import json, math, os, random, struct, sys, wave

SR = 44100
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)                      # godot/
MELODY_JSON = os.path.join(ROOT, "..", "assets", "melody.json")
OUT_DIR = os.path.join(ROOT, "assets", "audio")

def midi_to_freq(m): return 440.0 * (2.0 ** ((m - 69) / 12.0))

# ---------------------------------------------------------------- waveforms
def square(f, t):   return 1.0 if math.sin(2*math.pi*f*t) >= 0 else -1.0
def sawtooth(f, t):
    p = (f * t) % 1.0
    return 2.0 * p - 1.0
def triangle(f, t):
    p = (f * t) % 1.0
    return 4.0 * abs(p - 0.5) - 1.0

WAVES = {"square": square, "sawtooth": sawtooth, "triangle": triangle}

def sine(f, t): return math.sin(2*math.pi*f*t)

# ---------------------------------------------------------------- filters
class OnePoleLP:
    def __init__(self, fc):
        self.a = 1.0 - math.exp(-2.0 * math.pi * fc / SR)
        self.y = 0.0
    def push(self, x):
        self.y += self.a * (x - self.y)
        return self.y

class OnePoleHP:
    def __init__(self, fc):
        self.a = math.exp(-2.0 * math.pi * fc / SR)
        self.xp = 0.0; self.y = 0.0
    def push(self, x):
        self.y = (1.0 - self.a) * (x - self.xp) + self.a * self.y
        self.xp = x
        return self.y

# ---------------------------------------------------------------- _tone / _noise
def tone(buf, start_s, type_, f0, dur, peak, lp=None, f1=None, tau=None):
    """Replicates TetrisAudio._tone into a float list `buf` (seconds-based)."""
    n0 = int(start_s * SR)
    n_end = int((start_s + dur + 0.45) * SR)   # headroom for decay tail
    if n_end > len(buf):
        buf.extend([0.0] * (n_end - len(buf)))
    a = min(0.008, dur * 0.3)
    tau = tau if tau is not None else max(0.02, dur * 0.3)
    filt = OnePoleLP(lp) if lp else None
    wave_fn = WAVES[type_]
    for i in range(n0, n_end):
        t = (i - n0) / SR
        f = f0 + ((f1 - f0) * t / dur) if f1 is not None else f0  # linear sweep
        x = wave_fn(f, t)
        if filt: x = filt.push(x)
        if t < a:
            g = 0.0001 + (peak - 0.0001) * (t / a)
        else:
            g = 0.0001 + (peak - 0.0001) * math.exp(-(t - a) / tau)
        buf[i] += x * g

def noise(buf, start_s, dur, peak=0.1, hp=None, seed=1234):
    """Replicates TetrisAudio._noise (deterministic: seeded LCG instead of Math.random)."""
    n0 = int(start_s * SR)
    n_end = int((start_s + dur + 0.45) * SR)
    if n_end > len(buf):
        buf.extend([0.0] * (n_end - len(buf)))
    filt = OnePoleHP(hp) if hp else None
    rnd = random.Random(seed)
    t3 = dur * 0.3
    tau = max(0.015, dur * 0.25)
    for i in range(n0, n_end):
        t = (i - n0) / SR
        x = rnd.uniform(-1.0, 1.0)
        if filt: x = filt.push(x)
        g = peak if t < t3 else 0.0001 + (peak - 0.0001) * math.exp(-(t - t3) / tau)
        buf[i] += x * g

def arpeggio(buf, notes, at, total, peak, type_):
    step = total / len(notes)
    for i, f in enumerate(notes):
        tone(buf, at + i * step, type_, f, min(0.08, step * 1.6), peak)

# ---------------------------------------------------------------- music loop
def render_music():
    m = json.load(open(MELODY_JSON))
    tracks = [list(map(tuple, t)) for t in m["tracks"]]
    loop_s = max(max(s + d for s, _, d in tr) for tr in tracks)
    buf = [0.0] * int((loop_s + 1.0) * SR)

    specs = [
        (0, "square",   0.16, 2500, None),
        (1, "triangle", 0.10, None, None),
        (2, "sawtooth", 0.18, 400,  None),
        (3, "triangle", 0.07, None, True),   # pluck
    ]
    for ti, type_, peak, lp, pluck in specs:
        for s, midi, d in tracks[ti]:
            dur = min(d, 0.15) if pluck else d
            tau = 0.03 if pluck else None
            tone(buf, s, type_, midi_to_freq(midi), dur, peak, lp=lp, tau=tau)

    # soft limiter so overlapping peaks never clip (web master gain is 1.0;
    # keep the same relative balance, just avoid digital clipping in WAV)
    mx = max(abs(x) for x in buf) or 1.0
    scale = min(1.0, 0.95 / mx)
    return [x * scale for x in buf], loop_s

# ---------------------------------------------------------------- sfx set
def render_sfx():
    out = {}
    def mk(name, build, length):
        buf = [0.0] * int(length * SR)
        t = 0.01
        build(buf, t)
        mx = max(abs(x) for x in buf) or 1.0
        scale = min(1.0, 0.95 / mx)
        out[name] = [x * scale for x in buf]

    mk("move",      lambda b, t: tone(b, t, "square", 660, 0.02, 0.05), 0.15)
    mk("rotate",    lambda b, t: tone(b, t, "square", 440, 0.03, 0.06, f1=587), 0.15)
    mk("softdrop",  lambda b, t: tone(b, t, "square", 220, 0.015, 0.04), 0.1)
    def hard_drop_real(b, t):
        noise(b, t, 0.06, 0.12)
        n0 = int(t * SR); n_end = int((t + 0.57) * SR)
        if n_end > len(b): b.extend([0.0] * (n_end - len(b)))
        a = min(0.008, 0.12 * 0.3); tau = max(0.02, 0.12 * 0.3)
        for i in range(n0, n_end):
            tt = (i - n0) / SR
            g = 0.0001 + (0.12 - 0.0001) * (tt / a) if tt < a else \
                0.0001 + (0.12 - 0.0001) * math.exp(-(tt - a) / tau)
            b[i] += sine(90, tt) * g
    mk("harddrop", hard_drop_real, 0.7)
    mk("lock",      lambda b, t: tone(b, t, "square", 180, 0.03, 0.07), 0.2)
    def clear(n):
        notes = [523.25, 659.25, 783.99] + ([987.77] if n >= 2 else []) + ([1174.66] if n >= 3 else [])
        return lambda b, t: arpeggio(b, notes, t, 0.12, 0.09, "triangle")
    mk("clear1", clear(1), 0.5); mk("clear2", clear(2), 0.5); mk("clear3", clear(3), 0.5)
    def tetris(b, t):
        arpeggio(b, [523.25, 659.25, 783.99, 1046.5], t, 0.2, 0.14, "triangle")
        noise(b, t + 0.16, 0.1, 0.05, hp=3000)
    mk("tetris", tetris, 0.7)
    def tspin(b, t):
        tone(b, t, "triangle", 880, 0.07, 0.1)
        tone(b, t + 0.06, "triangle", 1319, 0.09, 0.1)
    mk("tspin", tspin, 0.4)
    def hold_sfx(b, t):
        n0 = int(t * SR); n_end = int((t + 0.45) * SR)
        if n_end > len(b): b.extend([0.0] * (n_end - len(b)))
        a = min(0.008, 0.04 * 0.3); tau = max(0.02, 0.04 * 0.3)
        for i in range(n0, n_end):
            tt = (i - n0) / SR
            g = 0.0001 + (0.06 - 0.0001) * (tt / a) if tt < a else \
                0.0001 + (0.06 - 0.0001) * math.exp(-(tt - a) / tau)
            b[i] += sine(523.25, tt) * g
    mk("hold", hold_sfx, 0.5)
    mk("levelup", lambda b, t: arpeggio(b, [440, 554.37, 659.25], t, 0.18, 0.1, "triangle"), 0.6)
    def game_over(b, t):
        for i, f in enumerate([659.25, 587.33, 493.88, 392]):
            tone(b, t + i * 0.16, "sawtooth", f, 0.18, 0.12, lp=1500)
    mk("gameover", game_over, 1.2)
    def blip(b, t):
        n0 = int(t * SR); n_end = int((t + 0.45) * SR)
        if n_end > len(b): b.extend([0.0] * (n_end - len(b)))
        a = min(0.008, 0.04 * 0.3); tau = max(0.02, 0.04 * 0.3)
        for i in range(n0, n_end):
            tt = (i - n0) / SR
            g = 0.0001 + (0.05 - 0.0001) * (tt / a) if tt < a else \
                0.0001 + (0.05 - 0.0001) * math.exp(-(tt - a) / tau)
            b[i] += sine(660, tt) * g
    mk("start", blip, 0.5); mk("pause", blip, 0.5)
    return out

# ---------------------------------------------------------------- wav writer
def write_wav(path, samples):
    with wave.open(path, "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        frames = bytearray()
        for x in samples:
            v = int(max(-1.0, min(1.0, x)) * 32767)
            frames += struct.pack("<h", v)
        w.writeframes(bytes(frames))

def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    print("rendering music loop (pure python, ~30-90s)...")
    music, loop_s = render_music()
    write_wav(os.path.join(OUT_DIR, "music_loop.wav"), music)
    print(f"  music_loop.wav: {loop_s:.2f}s loop, {len(music)/SR:.2f}s file")
    sfx = render_sfx()
    for name, samples in sorted(sfx.items()):
        p = os.path.join(OUT_DIR, f"sfx_{name}.wav")
        write_wav(p, samples)
        print(f"  sfx_{name}.wav: {len(samples)/SR:.2f}s")
    print("done ->", OUT_DIR)

if __name__ == "__main__":
    main()
