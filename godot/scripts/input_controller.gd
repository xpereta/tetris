# scripts/input_controller.gd — manual DAS/ARR auto-repeat (web values) + action
# routing. NOT OS key repeat: on move press -> immediate move, then after
# DAS_MS one more move, then every ARR_MS while held. Soft drop repeats every
# SOFT_REPEAT_MS while ArrowDown is held. Actions are read by name from the
# project input map (move_left/move_right/soft_drop/hard_drop/rotate_cw/
# rotate_ccw/hold/pause/start).
extends Node

const DAS_MS := 167
const ARR_MS := 33
const SOFT_REPEAT_MS := 30

var game: Variant = null # Game instance, set by main.gd
var audio: Node = null   # AudioManager (optional — headless smoke runs without it)
var main_ref: Node = null # Main scene root (settings menu + mute), set by main.gd


func _sfx(name: String) -> void:
	if audio != null:
		audio.play_sfx(name)

enum Dir { NONE, LEFT, RIGHT }

var _dir := Dir.NONE
var _next_repeat_ms := -1.0
var _soft_next_ms := -1.0


func _unhandled_input(event: InputEvent) -> void:
	if game == null or not (event is InputEventKey):
		return
	var k := event as InputEventKey
	if k.pressed and not k.echo:
		# v3 §2: while the settings menu is open, only S/Esc act — everything else
		# is swallowed so no game input leaks through. The game itself is paused.
		if main_ref != null and bool(main_ref.settings_menu.visible):
			if k.keycode == KEY_S or k.keycode == KEY_ESCAPE:
				main_ref.toggle_settings() # S closes; Esc closes (web §2)
			return
		# v3 §2/§4: S opens/closes settings, M toggles mute — work in any state.
		if k.is_action_pressed("settings"):
			if main_ref != null:
				main_ref.toggle_settings()
			return
		if k.is_action_pressed("mute"):
			if main_ref != null:
				main_ref.toggle_mute() # web toggleMute(): flip + persist
			return
		match game.state:
			"idle", "over":
				if k.is_action_pressed("start"):
					game.start()
					_sfx("start")
					if audio != null:
						audio.start_music() # idempotent — music follows playing state (web §2)
			"playing":
				if k.is_action_pressed("move_left") and not Input.is_action_pressed("move_right"):
					press_move(Dir.LEFT)
				elif k.is_action_pressed("move_right") and not Input.is_action_pressed("move_left"):
					press_move(Dir.RIGHT)
				elif k.is_action_pressed("soft_drop"):
					press_soft_drop()
				elif k.is_action_pressed("rotate_cw"):
					if game.rotate_cw():
						_sfx("rotate") # SFX only on a successful rotation (web behavior)
				elif k.is_action_pressed("rotate_ccw"):
					if game.rotate_ccw():
						_sfx("rotate")
				elif k.is_action_pressed("hold"):
					game.hold_piece() # 'hold' event -> sfx in main._on_event
				elif k.is_action_pressed("hard_drop"):
					var had_piece := game.current != null
					game.hard_drop()
					if had_piece:
						_sfx("harddrop")
				elif k.is_action_pressed("pause"):
					game.pause()
					if audio != null:
						audio.stop_music()
					_sfx("pause")
			"paused":
				if k.is_action_pressed("pause") or k.is_action_pressed("start"):
					game.resume()
					if audio != null:
						audio.start_music() # web resumeGame(): music back on
	# s (settings) and m (mute) are handled above in any state (v3 §2/§4).


func _process(_delta: float) -> void:
	if game == null or game.state != "playing" or game.current == null:
		return
	var now := Time.get_ticks_msec() as float

	# DAS/ARR horizontal auto-repeat state machine (web semantics).
	if _dir != Dir.NONE:
		var held := Input.is_action_pressed("move_left") if _dir == Dir.LEFT else Input.is_action_pressed("move_right")
		if not held:
			_dir = Dir.NONE # key released mid-DAS/ARR
		elif now >= _next_repeat_ms:
			var ok: bool = game.move_left() if _dir == Dir.LEFT else game.move_right()
			if not ok:
				_dir = Dir.NONE # hit a wall: stop repeating until re-press
			else:
				_sfx("move") # SFX only on a successful step (web behavior)
				_next_repeat_ms = now + ARR_MS

	# Soft drop repeat while ArrowDown held (timer keeps running across locks,
	# like the web loop — a failed attempt just waits one more interval).
	if Input.is_action_pressed("soft_drop") and now >= _soft_next_ms:
		var ok_soft: bool = game.soft_drop() # explicit type — game is a Variant
		if ok_soft:
			_sfx("softdrop") # AudioManager throttles to max once per 50 ms (web)
		_soft_next_ms = now + SOFT_REPEAT_MS


# First press of a move key: immediate move, then arm DAS (web behavior).
func press_move(dir: Dir) -> void:
	if game == null or game.state != "playing" or game.current == null:
		return
	var ok: bool = game.move_left() if dir == Dir.LEFT else game.move_right()
	if not ok:
		return # blocked on first press: no repeat armed (web behavior)
	_sfx("move")
	_dir = dir
	_next_repeat_ms = Time.get_ticks_msec() as float + DAS_MS


func press_soft_drop() -> void:
	if game == null or game.state != "playing" or game.current == null:
		return
	var ok: bool = game.soft_drop()
	if ok:
		_sfx("softdrop")
		_soft_next_ms = Time.get_ticks_msec() as float + SOFT_REPEAT_MS
