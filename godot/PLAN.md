# Godot Port — Plan

Port of the web Tetris (v3.1.1) to **Godot 4.x** (current stable: 4.7.2), living in this
folder inside the same repo. The JS implementation is the source of truth; the port must be
**behaviorally identical**, verified by automated parity tests, not by eye.

## 0. Decisions & assumptions

| Decision | Choice | Why |
|---|---|---|
| Engine version | Godot **4.x stable** (≥4.6) | Current LTS-ish line; `--headless` test support is mature in 4.x |
| Language | **GDScript** | No build toolchain, idiomatic, trivially testable headless. C# rejected: adds .NET runtime + export complexity for zero gameplay benefit |
| Logic porting strategy | Port `js/engine.js` + `js/srs.js` as **pure GDScript classes** (no `Node` inheritance) | Mirrors the JS architecture; keeps logic 100% testable without a scene tree, exactly like the frozen JS engine |
| Rendering | Custom `_draw()` on a `Node2D` for board/piece/ghost/trail | Matches the canvas approach 1:1 (cell grid, same colors), fast, no per-cell node overhead. HUD/menus are normal `Control` nodes |
| Audio | **Pre-rendered WAVs** generated once from `assets/melody.json` + SFX synthesis script, committed to `godot/assets/audio/` | The web version synthesizes via WebAudio; Godot's equivalent (`AudioStreamGenerator`) is realtime and fragile. A one-time offline render of the same 4 MIDI tracks (square/triangle/saw recipes) gives identical music with zero runtime cost |
| Particles | `CPUParticles2D` pools for lock bursts + clear spray; trail = small sprites spawned above the piece top edge at exact fall speed (same v3.1.1 rules: never in front of motion, killed on ground/lock/hold) | Reuses the tuned v3.1/v3.1.1 behavior directly |
| Settings persistence | `ConfigFile` → `user://settings.cfg` | Godot's standard; same 3 options (particles on/off, trail on/off, intensity Low/Med/High) + mute |
| Input feel | DAS 167 ms / ARR 33 ms ported verbatim from `ui.js` manual auto-repeat | Same feel as the web game |

**Out of scope:** mobile/touch layout (Godot export targets desktop first), online play,
leaderboards. Autoplayer is ported **only as a test/parity driver**, not exposed in the UI.

## 1. Folder layout

```
godot/
├── PLAN.md                  ← this file
├── project.godot            ← Godot 4 project (main scene, input map, display size)
├── icon.svg                 ← simple T-piece icon
├── src/                     ← PURE logic — no Node classes, no scene refs
│   ├── rng.gd               ← mulberry32 EXACT port (uint32 emulated with & 0xFFFFFFFF masks)
│   ├── srs.gd               ← SHAPES + official kick tables, copied verbatim from js/srs.js
│   ├── engine.gd            ← Game class port of js/engine.js (484 lines): states, tick(),
│   │                          rotate/move/hold/drop, lock delay w/ 15-reset cap, guideline
│   │                          scoring (T-spin/mini/b2b/combo), gravity formula, events via signals
│   └── autoplayer.gd        ← heuristic port of js/autoplayer.js (parity driver only)
├── scenes/
│   ├── main.tscn            ← board view + HUD + settings menu root
│   └── settings_menu.tscn   ← ⚙ / S-key menu, same controls as web v3
├── scripts/                 ← presentation layer (Node classes)
│   ├── board_view.gd        ← _draw(): 10×20 visible grid, ghost α≈0.32, piece, clear-wipe anim
│   ├── hud.gd               ← score / level / lines / next-5 queue / hold box; count-up + pulse tweens
│   ├── input_controller.gd  ← DAS/ARR state machine (167/33 ms), key map identical to web
│   ├── particles_fx.gd      ← CPUParticles2D pools: lock burst, clear spray (real cell colors), trail
│   └── audio_manager.gd     ← WAV loop player + 15 SFX one-shots, mute persistence
├── tests/                   ← headless test suite (run via `godot --headless -s`)
│   ├── run_tests.gd         ← SceneTree script: discovers & runs all test_*.gd, prints TAP-ish summary
│   ├── test_srs.gd          ← shape/kick table identity vs js/srs.js values
│   ├── test_rng.gd          ← mulberry32 first 100 outputs == JS reference vector (committed)
│   ├── test_engine.gd       ← ports of the 60 JS tests: rotation, bag, scoring, tspin, ghost,
│   │                          gravity, hold, gameover (+ autoplayer sanity)
│   └── parity/
│       ├── trace_js.mjs     ← Node script: runs js/engine.js + autoplayer for N seeds, dumps
│       │                      event traces (piece seq, per-lock score/board-hash) to JSON
│       ├── trace_godot.gd   ← same walk against src/engine.gd, same JSON shape
│       └── check.sh         ← runs both, diffs → exit 0 only on byte-identical traces
├── tools/
│   └── gen_audio.py         ← one-time: assets/melody.json (4 MIDI tracks) + SFX recipes → WAVs
└── assets/audio/            ← generated & committed: loop.wav (~64 s, 44.1 kHz mono) + sfx_*.wav
```

## 2. Parity strategy (the heart of the port)

Two layers, both automated and CI-runnable headless:

**Layer A — unit parity.** The existing 60 JS tests (`tests/*.test.js`) become GDScript tests in
`godot/tests/`. Same inputs, same expected outputs (scoring table values, kick results, bag order,
ghost rows, gravity ms per level). Plus a **reference vector test**: `rng.gd` must reproduce the
first 100 mulberry32 outputs of the JS implementation for seed 42 — this single test pins the
entire piece-sequence stream.

**Layer B — game-level trace parity.** For N=50 seeds, drive a full game to game-over with the
ported autoplayer (deterministic input) in BOTH implementations and dump an event trace:
`[seed, bag sequence, per-lock {piece,type,x,y,rot,score,lines,boardHash}]`. `check.sh` diffs the
two JSON files. **Acceptance gate: byte-identical traces.** This proves SRS + scoring + gravity
+ lock delay + 7-bag all behave identically end-to-end — far stronger than any visual check.

Known parity hazards and how they're handled:

| Hazard | Handling |
|---|---|
| JS `Math.imul` / 32-bit ops vs GDScript (64-bit ints) | `rng.gd` masks every step with `& 0xFFFFFFFF`; reference-vector test catches any drift |
| Float math (`pow(0.8-(L-1)*0.007, L-1)`) | Both are IEEE-754 doubles; formula copied verbatim. Gravity is compared in **ms at level granularity** (the engine's own `gravityMs`), not per-frame accumulation — frame pacing legitimately differs between rAF and `_process(delta)` |
| Timing-dependent behavior (lock delay, DAS) | Engine takes explicit time steps (`tick(dt_ms)` style, same as JS `tick()`); the UI layer paces it. Parity traces use fixed-step driving, so no wall-clock dependence |
| Event ordering (lock emitted BEFORE row removal — critical for clear FX) | Ported exactly; documented in `engine.gd` header like the JS original |

## 3. Phases & acceptance gates

**Phase 0 — Scaffold.** Create project (`project.godot`, input map, folder tree), download
Godot 4.x Linux binary to a pinned path (record version in PLAN.md changelog), verify
`godot --headless --quit` runs clean. *Gate: headless launch OK.*

**Phase 1 — Pure logic port.** `rng.gd`, `srs.gd`, `engine.gd`, `autoplayer.gd` + full test suite
in `tests/`. No scenes yet. *Gate: all GDScript tests pass headless, including the RNG reference
vector and kick-table identity.*

**Phase 2 — Trace parity.** Build `parity/trace_js.mjs` (reuses existing frozen JS engine),
`trace_godot.gd`, `check.sh`. *Gate: byte-identical traces for 50 seeds × full games. Any diff =
bug in the port, fix until clean.*

**Phase 3 — UI & feel.** `main.tscn`: board `_draw()` (same palette/ghost alpha), HUD with next-5
+ hold, DAS/ARR input controller, pause/menu/game-over states, v2 animations as tweens (level-up
pulse scale 1→1.4→1 + gold border, clear wipe L→R ~250 ms, game-over fade + score count-up).
*Gate: manual playthrough to level ≥5 with no logic divergence from web version; screenshots for
the record.*

**Phase 4 — Audio, particles, settings.** `gen_audio.py` renders the Korobeiniki loop (same 4
tracks/instruments as `js/audio.js`) + 15 SFX WAVs → commit. Wire `audio_manager.gd`,
`particles_fx.gd` (v3.1 density: lock bursts ~3/cell cap 60, clear spray ×3 with real cell colors,
trail per v3.1.1 rules), settings menu with persistence. *Gate: feature checklist — music loops
seamlessly at the 64 s wrap, all SFX fire on their events, trail never in front of motion (same
audit approach as web v3.1.1), settings survive restart.*

**Phase 5 — Packaging & docs.** Export preset for Linux/X11 (single binary), `godot/README.md`
(open-in-editor instructions + headless test commands + how to regenerate audio), final full
test run, commit + tag `godot-0.1`. *Gate: exported binary runs the game; README verified by a
fresh clone.*

## 4. Verification tooling on this machine

- **Headless logic gates (Phases 1–2):** download Godot 4.x Linux x86_64 to `~/.local/bin/godot`
  (pinned version), run tests with `godot --headless -s res://tests/run_tests.gd`. No display needed.
- **Visual checks (Phases 3–4):** if a virtual display is available (`Xvfb`) run the game under it
  and screenshot; otherwise visual verification falls back to the user opening the project in the
  Godot editor — logic correctness is already guaranteed by Phases 1–2 gates, so this only checks
  presentation.
- **JS side stays frozen:** `js/engine.js`, `js/srs.js` are never modified for the port; the parity
  harness reads them read-only.

## 5. Risks & mitigations

| Risk | Mitigation |
|---|---|
| GDScript float/int quirks break RNG or scoring parity | Reference-vector test (Phase 1) + trace diff (Phase 2) catch it before any UI work; fix in `rng.gd`/`engine.gd`, never by "adjusting" the JS side |
| Audio render quality differs from WebAudio synthesis | Acceptable: same melody/timbre recipe, offline-rendered. If a track sounds off, tweak `gen_audio.py` (one knob per instrument), re-render — no engine changes |
| Godot version drift (4.x minor updates) | Pin exact binary version in PLAN.md + export preset; tests are the contract, not the editor build |
| Scope creep (mobile, online, extra pieces) | Out of scope per §0; port is feature-parity with web v3.1.1 only |

## 6. Changelog

- 2026-09-27 — Plan written (pre-execution). Godot target: 4.x stable (4.7.2 at time of writing).
  JS source of truth: commit `129ecb4` (v3.1.1), 60 tests green.
