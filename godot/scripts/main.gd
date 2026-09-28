# scripts/main.gd — scene root: owns a Game instance, paces tick() from
# _process (accumulate delta; one tick per gravity interval, max 5/frame),
# routes engine events to board_view/hud FX, and manages the start/pause/
# game-over overlays (game over fades in 500ms with score counting up 800ms).
extends Node2D

const GameScript := preload("res://src/engine.gd")
const BoardViewScript := preload("res://scripts/board_view.gd")
const HudScript := preload("res://scripts/hud.gd")
const InputCtrlScript := preload("res://scripts/input_controller.gd")
const AudioMgrScript := preload("res://scripts/audio_manager.gd")
const ParticlesFxScript := preload("res://scripts/particles_fx.gd")
const SettingsMenuScript := preload("res://scripts/settings_menu.gd")

const WIN_SIZE := Vector2(480, 640)
const BOARD_POS := Vector2(16, 40)
const OVERLAY_FADE_MS := 500.0
const SCORE_COUNT_MS := 800.0
const MUTE_PATH := "user://tetris_muted.json" # web parity: localStorage('tetris.muted')

var game: Variant = null
var board_view: Node2D
var hud: Control
var input_ctrl: Node
var audio: Node # AudioManager — shared with the input controller for action SFX
var particles_fx: Node2D # v3 particle layer (board-local coords)
var settings_menu: Control

# v3 §2 settings state (live copy of settings_menu.settings).
var fx_particles := true
var fx_trail := true
var fx_intensity := 1 # index into [0.5, 1, 2]

var start_overlay: ColorRect
var pause_overlay: ColorRect
var over_overlay: ColorRect
var _over_label: Label
var _acc := 0.0
var _was_over := false


func _ready() -> void:
	game = GameScript.new({}) # random seed, like the web game
	game.connect("event_emitted", _on_event)

	var bg := ColorRect.new()
	bg.color = Color("#1a1d27")
	bg.position = Vector2.ZERO
	bg.size = WIN_SIZE
	add_child(bg)

	board_view = BoardViewScript.new() as Node2D
	board_view.game = game
	board_view.position = BOARD_POS
	add_child(board_view)

	hud = HudScript.new()
	hud.game = game
	add_child(hud)

	input_ctrl = InputCtrlScript.new()
	input_ctrl.game = game
	input_ctrl.main_ref = self # settings menu + mute (v3 §2/§4)
	add_child(input_ctrl)

	audio = AudioMgrScript.new()
	add_child(audio)
	input_ctrl.audio = audio # action SFX (move/rotate/drop/start/pause)

	# v3 particle layer — board-local coords, so position it at the board origin.
	particles_fx = ParticlesFxScript.new() as Node2D
	particles_fx.position = BOARD_POS
	add_child(particles_fx)

	# v3 §2 settings menu (S opens/closes; hidden until then).
	settings_menu = SettingsMenuScript.new()
	settings_menu.visible = false
	settings_menu.setting_changed.connect(_on_settings_changed)
	add_child(settings_menu)
	fx_particles = bool(settings_menu.settings["particles"])
	fx_trail = bool(settings_menu.settings["trail"])
	fx_intensity = int(settings_menu.settings["intensity"])

	# Web parity: mute persists across sessions (localStorage('tetris.muted')).
	if FileAccess.file_exists(MUTE_PATH):
		var f := FileAccess.open(MUTE_PATH, FileAccess.READ)
		if f != null and JSON.parse_string(f.get_as_text()) == true:
			audio.set_muted(true)
		f.close()

	start_overlay = _make_overlay("TETRIS\n\nPress Enter to start")
	pause_overlay = _make_overlay("PAUSED\n\nP or Enter to resume")
	over_overlay = ColorRect.new()
	over_overlay.color = Color(0, 0, 0, 0.75)
	over_overlay.position = Vector2.ZERO
	over_overlay.size = WIN_SIZE
	_over_label = Label.new()
	_over_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_over_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_over_label.add_theme_font_size_override("font_size", 24)
	_over_label.add_theme_color_override("font_color", Color("#ffd54a"))
	_over_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	over_overlay.add_child(_over_label)
	add_child(over_overlay)


func _make_overlay(text: String) -> ColorRect:
	var c := ColorRect.new()
	c.color = Color(0, 0, 0, 0.6)
	c.position = Vector2.ZERO
	c.size = WIN_SIZE
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 24)
	l.add_theme_color_override("font_color", Color(0.9, 0.92, 0.98))
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.add_child(l)
	add_child(c)
	return c


func _process(delta: float) -> void:
	# v3 §2: while the settings menu is open, only S/Esc act (handled in
	# input_controller); the game itself stays paused — no ticks here.
	if game.state == "playing":
		_acc += delta
		var interval: float = game.gravity_ms() / 1000.0
		var n := 0
		while _acc >= interval and n < 5: # guard: max 5 ticks/frame
			_tick_with_trail(interval)
			_acc -= interval
			n += 1
		if n == 5:
			_acc = 0.0 # drop backlog after a stall

	# v3 §1: advance particle physics with the same clamped dt (visual only —
	# never touches engine timing or input). Web clamps dt to 250 ms.
	particles_fx.update(minf(delta * 1000.0, 250.0))

	# v3.1.1b invariant (AFTER physics, before draw): trail dots may never be in
	# front of the falling piece's motion — i.e. below its top edge. Quantized
	# gravity can overshoot at high levels, so snap stragglers back above it.
	if game.state == "playing" and game.current != null:
		var b: Dictionary = game.piece_bounds(str(game.current["type"]), int(game.current["rot"]))
		particles_fx.clamp_trails_above((int(game.current["y"]) + int(b["minR"]) - board_view.VISIBLE_TOP_ROW) * board_view.CELL)

	# Overlays follow game state (cheap per-frame check).
	start_overlay.visible = game.state == "idle" and not settings_menu.visible
	pause_overlay.visible = game.state == "paused" and not settings_menu.visible
	if game.state == "over":
		if not _was_over:
			_was_over = true
			_show_game_over()
	else:
		_was_over = false
		over_overlay.visible = false


# One gravity tick + the v3 §3 trail rule: a dot spawns only when the SAME piece
# actually moved down (speed = current gravity speed → trails behind it); when
# the piece stopped moving (grounded/lock delay) stale dots are killed.
func _tick_with_trail(interval_s: float) -> void:
	var cur_before: Variant = game.current
	var y_before := int(cur_before["y"]) if cur_before != null else -1
	game.tick()
	if game.state == "playing" and game.current != null and game.current == cur_before \
			and int(game.current["y"]) > y_before:
		_spawn_trail_dot(board_view.CELL / interval_s) # px/s = one cell per gravity tick (web §3)
	elif game.state == "playing":
		particles_fx.kill_trails()


# v3 §3: falling trail dot BEHIND the piece — spawned 1.5 cells ABOVE its top
# edge at exactly the piece's current speed (web spawnTrailDot).
func _spawn_trail_dot(speed_px_per_sec: float) -> void:
	if not fx_particles or not fx_trail:
		return # master + trail switches (checked once, never per-particle)
	var cur: Variant = game.current
	if cur == null:
		return
	var b: Dictionary = game.piece_bounds(str(cur["type"]), int(cur["rot"]))
	var cx: float = (int(cur["x"]) + (int(b["minC"]) + int(b["maxC"])) / 2.0 + 0.5) * board_view.CELL
	var top_y: float = (int(cur["y"]) + int(b["minR"]) - board_view.VISIBLE_TOP_ROW) * board_view.CELL
	particles_fx.spawn_trail(cx, top_y - 1.5 * board_view.CELL, speed_px_per_sec)


# v3 §3: lock burst — small burst per locked cell (base 3 × intensity), capped
# at ~60 total per lock. Visible rows only.
func _spawn_lock_bursts(type: String, x: int, y: int, rot: int) -> void:
	if not fx_particles:
		return # master switch — checked once
	var mult: float = [0.5, 1.0, 2.0][clampi(fx_intensity, 0, 2)]
	var per_cell := maxi(1, ceili(3 * mult))
	var total := 0
	for cell in game.cells_of(type, x, y, rot):
		var cy := int(cell[1])
		if cy < board_view.VISIBLE_TOP_ROW or cy >= 40:
			continue # visible rows only (web §3)
		if total >= 60:
			break # hard cap ~60 particles per lock
		var n := mini(per_cell, 60 - total)
		particles_fx.spawn_burst((int(cell[0]) + 0.5) * board_view.CELL, (cy - board_view.VISIBLE_TOP_ROW + 0.5) * board_view.CELL, board_view.COLORS[type], n)
		total += n


# v3 §3: line-clear spray across each ACTUAL cleared row (lock-time snapshot —
# rows are NOT always the bottom N). colors tint sparks with real cell types.
func _spawn_clear_rows(rows: Array, snap: Array) -> void:
	if not fx_particles or rows.is_empty():
		return # master switch — checked once
	var mult: float = [0.5, 1.0, 2.0][clampi(fx_intensity, 0, 2)]
	for i in range(rows.size()):
		var vr := int(rows[i])
		if vr < 0 or vr >= 20:
			continue # hidden-row clears: no visible spray
		var colors: Array = []
		if snap.size() > i and not (snap[i] as Dictionary).is_empty():
			for t in (snap[i] as Dictionary)["colors"]:
				colors.append(board_view.COLORS[str(t)])
		particles_fx.spawn_clear_row((vr + 0.5) * board_view.CELL, board_view.COLS, board_view.CELL, colors, maxi(1, roundi(float(board_view.COLS) * 3 * mult)))


# v3 §2: S opens/closes the settings menu — reuses the pause mechanics (no
# double-pause). Closing resumes ONLY the pause we caused.
func toggle_settings() -> void:
	if not settings_menu.visible:
		settings_menu.visible = true
		if game.state == "playing":
			game.pause() # pausedForSettings — web §2
	else:
		var was_ours: bool = game.state == "paused"
		settings_menu.visible = false
		if was_ours and game.state == "paused":
			game.resume()


# Web toggleMute(): flip + persist (localStorage('tetris.muted')).
func toggle_mute() -> void:
	var m: bool = not audio.is_muted()
	audio.set_muted(m)
	var f := FileAccess.open(MUTE_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string("true" if m else "false")
		f.close()


# Settings menu changed a value → re-apply live FX state (web syncSettingsUI).
func _on_settings_changed(_key: String, s: Variant) -> void:
	fx_particles = bool(s["particles"])
	fx_trail = bool(s["trail"])
	fx_intensity = int(s["intensity"])
	if not fx_particles:
		particles_fx.update(1e9) # cull everything (age > life for all live parts)


# Lock-time snapshot of full visible rows + their distinct colors (web §3.5 /
# v3 bugfix ground truth — the engine emits 'lock' BEFORE removing full rows).
func _full_visible_rows() -> Array:
	var out := []
	for r in range(board_view.VISIBLE_TOP_ROW, 40):
		var is_full := true
		var seen := {}
		for c in range(board_view.COLS):
			var t = game.board[r][c]
			if t == null or t == "":
				is_full = false
				break
			seen[str(t)] = true
		if is_full:
			out.append({"vr": r - board_view.VISIBLE_TOP_ROW, "colors": seen.keys()})
	return out


var _pending_clear_rows: Array = [] # lock-time snapshot for the clear FX



func _on_event(ev: Dictionary) -> void:
	match ev.get("type"):
		"lock":
			board_view.note_lock(str(ev["piece"]), int(ev["x"]), int(ev["y"]), int(ev["rot"]))
			board_view.note_full_rows() # rows still present at lock time
			_pending_clear_rows = _full_visible_rows() # ground truth for clear FX (web §3)
			_spawn_lock_bursts(str(ev["piece"]), int(ev["x"]), int(ev["y"]), int(ev["rot"]))
			particles_fx.kill_trails() # stale dots must not drift into the NEXT piece's body
			audio.play_sfx("lock")
		"clear":
			board_view.start_clear()
			var rows := []
			for snap_row in _pending_clear_rows:
				rows.append(int(snap_row["vr"]))
			if rows.is_empty(): # fallback (web): bottom-N visible rows
				var lines := int(ev["lines"])
				for i in range(mini(lines, 20)):
					rows.append(20 - lines + i)
			_spawn_clear_rows(rows, _pending_clear_rows)
			_pending_clear_rows = []
			# Web mapping (ui.js): tspin > tetris > clear1..3, in that priority.
			var lines := int(ev["lines"])
			if ev.get("tSpin", false) and lines > 0:
				audio.play_sfx("tspin")
			elif lines == 4:
				audio.play_sfx("tetris")
			elif lines >= 1:
				audio.play_sfx("clear%d" % mini(lines, 3))
		"hold":
			particles_fx.kill_trails() # same reason — a new piece spawns at the top
			audio.play_sfx("hold")
		"levelup":
			hud.note_levelup(int(ev["level"]))
			audio.play_sfx("levelup")
		"gameover":
			audio.stop_music()
			audio.play_sfx("gameover") # overlay handled in _process on state change


# v2: game-over overlay fades in over 500ms; final score counts up from 0
# over 800ms.
func _show_game_over() -> void:
	var final_score := int(game.score)
	over_overlay.modulate = Color(1, 1, 1, 0.0)
	over_overlay.visible = true
	_set_final_score(0)
	var tw := create_tween()
	tw.tween_property(over_overlay, "modulate:a", 1.0, OVERLAY_FADE_MS / 1000.0)
	tw.parallel().tween_method(_set_final_score, 0, final_score, SCORE_COUNT_MS / 1000.0)


func _set_final_score(v: float) -> void:
	_over_label.text = "GAME OVER\nScore: %d\n\nEnter to restart" % int(v)
