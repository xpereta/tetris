# Tetris — Godot port

A faithful port of the web version (v3.1.1) to **Godot 4.x** (developed on
4.7.2-stable, GDScript). The engine logic is a line-for-line port of the frozen
`js/engine.js` / `js/srs.js`; presentation, audio and particles follow
CONTRACT-V2/V3 with web parity as the acceptance bar.

## Open in the editor

1. Install Godot 4.x (4.7+ recommended) — https://godotengine.org/download
2. In the Project Manager: **Import** → select this folder's `project.godot`.
3. Press **F5** (or the ▶ button). The game starts on the "Press Enter to start" screen.

No assets need generating first — all audio WAVs are committed in `assets/audio/`
and import automatically on first open.

## Controls (same as web)

| Key | Action |
| --- | --- |
| ← / → | Move (DAS 167 ms, ARR 33 ms) |
| ↓ | Soft drop (repeat 30 ms) |
| Space | Hard drop |
| ↑ or X | Rotate CW |
| Z | Rotate CCW |
| C or Shift | Hold |
| P or Esc | Pause |
| S | Settings menu (particles, trail, intensity; persisted to `user://tetris_settings.json`) |
| M | Mute (persisted to `user://tetris_muted.json`) |
| Enter | Start / restart |

## Headless test commands

All gates run without a display:

```sh
# Logic parity suite — 49 tests (engine, SRS kicks, RNG reference vectors, autoplayer)
godot --headless -s res://tests/run_tests.gd

# Audio gate — 25 checks (music loop length/loop-point, all 16 WAVs load & play, mute)
godot --headless -s res://tests/test_audio.gd

# v3 particles + settings parity — 16 checks (cap, gravity, trail rules, clamp invariant, persistence)
godot --headless -s res://tests/test_fx_settings.gd

# Smoke: full autoplayer game to level ≥2, renders a board PNG
godot --headless -s res://scripts/smoke_autoplayer.gd

# Trace-parity gate (the acceptance bar): 50 seeded autoplayer games must produce
# byte-identical event traces vs the JS engine. Regenerate both sides:
./parity/check.sh
```

Visual probes (need Xvfb or a display):

```sh
xvfb-run -a godot --path . res://tests/ui_probe.tscn      # mid-game + game-over screenshots
xvfb-run -a godot --path . res://tests/fx_probe.tscn      # particles + settings menu shots
xvfb-run -a godot --path . res://tests/fx_diff_probe.tscn # proves particles are drawn (pixel diff)
```

## Regenerating the audio assets

`assets/audio/` contains `music_loop.wav` (~65 s, 4 tracks) + 15 SFX WAVs — a one-time
offline render of the exact WebAudio synthesis chain in `js/audio.js` (square/sawtooth/
triangle oscillators, gain envelopes, lowpass filters). To regenerate:

```sh
python3 tools/render_audio.py   # pure stdlib; reads ../assets/melody.json; ~10 s
```

**Import gotcha:** every WAV in `assets/audio/*.import` must stay at
`compress/mode=0` (uncompressed PCM). Godot's default Vorbis mode changes the imported
data size, which breaks the seamless-loop math (`loop_end = data.size() / 2` samples) —
the music would stop ~13 s into a 65 s loop. If you re-import and hear it cut short,
check these files first.

## Exporting (Linux/X11 single binary)

```sh
godot --headless --export-release "Linux" dist/tetris_linux.x86_64
```

The preset (`export_presets.cfg`) embeds the PCK into the binary
(`binary_format/embed_pck=true`), so the result is one self-contained executable.
Export templates for 4.7.2 must be installed (Editor → Manage Export Templates).

## Layout

```
project.godot            viewport 480x640, input map (DAS/ARR handled in code)
src/engine.gd            pure game logic — port of js/engine.js (FROZEN contract)
src/srs.gd               shapes + official SRS kick tables — port of js/srs.js
src/rng.gd               mulberry32 with exact uint32 parity (next_uint())
src/autoplayer.gd        heuristic autoplayer used by smoke + trace-parity tests
scripts/main.gd          scene root: tick pacing, event routing, overlays, settings/mute wiring
scripts/board_view.gd    board _draw() — web palette/bevels/ghost alpha 0.32, v2 FX tweens
scripts/hud.gd           SCORE/LEVEL/LINES + HOLD + NEXT-5 (16 px mini cells)
scripts/input_controller.gd  manual DAS/ARR state machine (web timings), S/M routing
scripts/audio_manager.gd offline WAV playback: seamless music loop + SFX map, mute
scripts/particles_fx.gd  v3 particle layer — pure visual, never touches engine timing
scripts/settings_menu.gd §2 settings overlay with persistence
tests/                   headless gates (run_tests, test_audio, test_fx_settings) + Xvfb probes
parity/                  trace-parity harness: JS traces vs Godot traces, byte-identical gate
tools/render_audio.py    offline WebAudio-chain replica → WAVs
assets/audio/            music_loop.wav + 15 SFX (committed; keep compress/mode=0)
```

## Parity status

- **Trace parity:** PASSED — 50 seeds / 4864 locks, byte-identical event traces vs JS.
- **Logic suite:** 49/49 · **Audio gate:** 25/25 · **FX/settings gate:** 16/16 · **Smoke:** OK.
