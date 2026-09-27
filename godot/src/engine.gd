# src/engine.gd — PURE Tetris game logic (no Node/Control, no scene loading).
# Full port of js/engine.js with identical public API names and semantics.
# Board = Array of 40 Arrays of 10; empty cell = null (same as JS).

class_name Game extends RefCounted

const BOARD_WIDTH := 10
const BOARD_HEIGHT := 40 # rows 0..19 hidden above the visible area (rows 20..39)
const VISIBLE_TOP_ROW := 20
const MAX_LOCK_RESETS := 15

const RNG := preload("res://src/rng.gd")
const SRS := preload("res://src/srs.gd")


signal event_emitted(event: Dictionary)

# ------------------------------------------------------------------ public state
var seed: Variant = null
var gravity_ms_override: Variant = null
var lock_delay_ms: int = 500

var state: String = "idle"
var board: Array = []
var score: int = 0
var level: int = 1
var lines: int = 0
var combo: int = -1
var b2b: bool = false
var hold: Variant = null
var can_hold: bool = true
var queue: Array = []
var current: Variant = null

# Internal gravity / lock-delay state.
var _rng: Variant = null
var _bag: Array = []
var _gravity_accum_ms: float = 0.0
var _grounded: bool = false
var _lock_timer_ms: Variant = null
var _resets_used: int = 0
var _last_move_was_kick: bool = false


# Guideline gravity: seconds per row at level L.
static func gravity_seconds(level: int) -> float:
	return pow(0.8 - (level - 1) * 0.007, level - 1)


func _init(options: Dictionary = {}) -> void:
	seed = options.get("seed", null)
	var gms := options.get("gravity_ms", null)
	if gms != null and (typeof(gms) == TYPE_INT or typeof(gms) == TYPE_FLOAT):
		if not (typeof(gms) == TYPE_FLOAT and gms != gms): # NaN -> no override (JS Number.isFinite)
			gravity_ms_override = float(gms)
	var ldm := options.get("lock_delay_ms", null)
	if ldm != null and (typeof(ldm) == TYPE_INT or typeof(ldm) == TYPE_FLOAT):
		lock_delay_ms = int(ldm)

	state = "idle"
	board = _empty_board()
	score = 0
	level = 1
	lines = 0
	combo = -1
	b2b = false
	hold = null
	can_hold = true
	queue = []
	current = null

	# Internal gravity / lock-delay state.
	var s := seed if seed != null else ((Time.get_ticks_msec() ^ randi()) & 0xFFFFFFFF)
	_rng = RNG.new(int(s))
	_bag = []
	_gravity_accum_ms = 0.0
	_grounded = false
	_lock_timer_ms = null
	_resets_used = 0
	_last_move_was_kick = false

	reset()


# ------------------------------------------------------------------ events

func _emit(event: Dictionary) -> Dictionary:
	emit_signal("event_emitted", event)
	return event


# ------------------------------------------------------------- randomizer

func _refill_queue() -> void:
	while queue.size() < 5:
		if _bag.is_empty():
			var bag := ["I", "O", "T", "S", "Z", "J", "L"]
			for i in range(bag.size() - 1, 0, -1):
				var j := int(floor(_rng.next() * (i + 1)))
				var tmp = bag[i]
				bag[i] = bag[j]
				bag[j] = tmp
			_bag = bag
		queue.append(_bag.pop_back())


func _next_piece_type() -> String:
	_refill_queue()
	var type := queue.pop_front()
	_refill_queue() # keep >= 5 upcoming pieces visible after the shift
	return type


# ------------------------------------------------------------- geometry

static func _empty_row() -> Array:
	var row := []
	for i in range(BOARD_WIDTH):
		row.append(null)
	return row


func _empty_board() -> Array:
	var b := []
	for r in range(BOARD_HEIGHT):
		b.append(_empty_row())
	return b


func cells_of(type: String, x: int, y: int, rot: int) -> Array:
	var out := []
	for cell in SRS.SHAPES[type][rot]:
		out.append([x + int(cell[0]), y + int(cell[1])])
	return out


func collides(cells: Array) -> bool:
	for cell in cells:
		var cx := int(cell[0])
		var cy := int(cell[1])
		if cx < 0 or cx >= BOARD_WIDTH or cy >= BOARD_HEIGHT:
			return true
		if cy >= 0 and board[cy][cx] != null:
			return true # rows above the board are open space
	return false


func is_on_ground(piece: Variant = null) -> bool:
	if piece == null:
		piece = current
	var cells: Variant = cells_of(piece["type"], int(piece["x"]), int(piece["y"]) + 1, int(piece["rot"]))
	return collides(cells)


# Public: ghost row for the current piece (null when no current piece).
func ghost_y() -> Variant:
	if current == null:
		return null
	var gy := int(current["y"])
	while true:
		var cells: Variant = cells_of(current["type"], int(current["x"]), gy + 1, int(current["rot"]))
		if collides(cells):
			break
		gy += 1
	return gy


# ------------------------------------------------------------- lifecycle

func start() -> void:
	reset()
	state = "playing"
	_spawn_next() # block-out at spawn (e.g. board pre-filled) -> over


func pause() -> void:
	if state == "playing":
		state = "paused"


func resume() -> void:
	if state == "paused":
		state = "playing"


func reset() -> void:
	board = _empty_board()
	score = 0
	level = 1
	lines = 0
	combo = -1
	b2b = false
	hold = null
	can_hold = true
	queue = []
	current = null
	_gravity_accum_ms = 0.0
	_grounded = false
	_lock_timer_ms = null
	_resets_used = 0
	_last_move_was_kick = false
	# Re-seed the PRNG so a reset with options.seed replays the same sequence.
	var s := seed if seed != null else ((Time.get_ticks_msec() ^ randi()) & 0xFFFFFFFF)
	_rng = RNG.new(int(s))
	_bag = []
	_refill_queue()


func _spawn(type: String) -> bool:
	# Standard SRS spawn: I in row 21 (hidden), others in rows 21-22, centered.
	var x := 4 if type == "O" else 3
	var y := 21
	current = {"type": type, "x": x, "y": y, "rot": 0}
	if collides(cells_of(type, x, y, 0)):
		# Block out at spawn -> game over.
		state = "over"
		_emit({"type": "gameover"})
		return false
	can_hold = true
	_gravity_accum_ms = 0.0
	_grounded = is_on_ground()
	_lock_timer_ms = null
	_resets_used = 0
	return true


func _spawn_next() -> bool:
	var type := _next_piece_type()
	if not _spawn(type):
		return false
	return true


# ------------------------------------------------------------- input

func move_left() -> bool:
	if state != "playing" or current == null:
		return false
	var cells: Variant = cells_of(current["type"], int(current["x"]) - 1, int(current["y"]), int(current["rot"]))
	if collides(cells):
		return false
	current["x"] = int(current["x"]) - 1
	_last_move_was_kick = false # a plain move is not a kick
	_after_successful_move()
	return true


func move_right() -> bool:
	if state != "playing" or current == null:
		return false
	var cells: Variant = cells_of(current["type"], int(current["x"]) + 1, int(current["y"]), int(current["rot"]))
	if collides(cells):
		return false
	current["x"] = int(current["x"]) + 1
	_last_move_was_kick = false # a plain move is not a kick
	_after_successful_move()
	return true


func soft_drop() -> bool:
	if state != "playing" or current == null:
		return false
	var cells: Variant = cells_of(current["type"], int(current["x"]), int(current["y"]) + 1, int(current["rot"]))
	if collides(cells):
		return false
	current["y"] = int(current["y"]) + 1
	score += 1 # guideline: +1 per cell, not multiplied by level
	_gravity_accum_ms = 0.0
	_last_move_was_kick = false # a plain move is not a kick
	_grounded = is_on_ground()
	if not _grounded:
		_lock_timer_ms = null
	return true


func hard_drop() -> void:
	if state != "playing" or current == null:
		return
	var gy := ghost_y()
	var distance := int(gy) - int(current["y"])
	score += 2 * distance # guideline: +2 per cell, not multiplied by level
	current["y"] = int(gy)
	_lock_piece()


func rotate_cw() -> bool:
	return _rotate(1)


func rotate_ccw() -> bool:
	return _rotate(-1)


func _rotate(dir: int) -> bool:
	if state != "playing" or current == null:
		return false
	var from := int(current["rot"])
	var to := (from + dir + 4) % 4
	var kicks := SRS.get_kicks(current["type"], from, to)
	for i in range(kicks.size()):
		var dx := int(kicks[i][0])
		var dy := int(kicks[i][1])
		var nx := int(current["x"]) + dx
		var ny := int(current["y"]) + dy
		if not collides(cells_of(current["type"], nx, ny, to)):
			current["x"] = nx
			current["y"] = ny
			current["rot"] = to
			# A non-zero kick is what makes a 3-corner T-lock a "mini" T-spin.
			_last_move_was_kick = i > 0 and (dx != 0 or dy != 0)
			_after_successful_move()
			return true
	_last_move_was_kick = false
	return false


func hold_piece() -> bool:
	if state != "playing" or current == null or not can_hold:
		return false
	var cur_type: Variant = current["type"]
	if hold == null:
		hold = cur_type
		if not _spawn_next():
			return true # game over already handled
	else:
		var held_type := hold
		hold = cur_type
		if not _spawn(held_type):
			return true
	can_hold = false
	_emit({"type": "hold", "piece": current["type"] if current != null else null})
	return true


# ------------------------------------------------------------- gravity & lock delay

func _gravity_ms() -> float:
	if gravity_ms_override != null:
		return float(gravity_ms_override)
	return gravity_seconds(level) * 1000.0


# Public: current gravity interval in ms (UI loop uses this to pace tick()).
func gravity_ms() -> float:
	return _gravity_ms()


func tick() -> Array:
	var events := []
	if state != "playing" or current == null:
		return events

	# Lock delay: while grounded, the piece locks after lockDelayMs of ground contact.
	if is_on_ground():
		_grounded = true
		if _lock_timer_ms == null:
			_lock_timer_ms = 0.0
		_lock_timer_ms += _gravity_ms()
		if float(_lock_timer_ms) >= float(lock_delay_ms):
			_lock_piece(events)
			return events
	else:
		# Falling: accumulate gravity time and drop whole rows.
		_grounded = false
		_lock_timer_ms = null
		var gms := _gravity_ms()
		_gravity_accum_ms += gms
		while _gravity_accum_ms >= gms:
			_gravity_accum_ms -= gms
			if not is_on_ground():
				var cells: Variant = cells_of(current["type"], int(current["x"]), int(current["y"]) + 1, int(current["rot"]))
				if collides(cells):
					break # landed on the ground mid-tick
				current["y"] = int(current["y"]) + 1
			else:
				break

	# After gravity, re-check grounding for lock-delay bookkeeping.
	if is_on_ground() and _lock_timer_ms == null:
		_grounded = true
		_lock_timer_ms = 0.0
	return events


func _after_successful_move() -> void:
	# Move-reset rule: reset the lock timer on a successful move/rotate, up to 15 times.
	if is_on_ground():
		if _resets_used < MAX_LOCK_RESETS:
			_lock_timer_ms = 0.0
			_resets_used += 1
		else:
			# Reset cap exhausted: lock on the next tick.
			_lock_timer_ms = float(lock_delay_ms)
	else:
		_grounded = false
		_lock_timer_ms = null


func _lock_piece(events: Array = []) -> void:
	var piece: Variant = current
	for cell in cells_of(piece["type"], int(piece["x"]), int(piece["y"]), int(piece["rot"])):
		var cx := int(cell[0])
		var cy := int(cell[1])
		if cy >= 0 and cy < BOARD_HEIGHT:
			board[cy][cx] = piece["type"]

	# T-spin detection must be evaluated on lock while `current` is still set.
	var t_spin_info := _detect_t_spin()
	current = null
	var cleared_rows := []
	for r in range(BOARD_HEIGHT):
		var full := true
		for c in range(BOARD_WIDTH):
			if board[r][c] == null:
				full = false
				break
		if full:
			cleared_rows.append(r)

	# Lock event is emitted BEFORE row removal (same order as JS).
	_emit({"type": "lock", "piece": piece["type"], "x": piece["x"], "y": piece["y"], "rot": piece["rot"]})

	var clear_event := {}
	if not cleared_rows.is_empty():
		for r in cleared_rows:
			board.remove_at(r)
			board.push_front(_empty_row())
		var points := _score_clear(cleared_rows.size(), t_spin_info)
		clear_event = {
			"type": "clear",
			"lines": cleared_rows.size(),
			"tSpin": t_spin_info["tSpin"],
			"miniTSpin": t_spin_info["miniTSpin"],
			"points": points,
			"combo": combo,
			"b2b": b2b,
		}
	else:
		combo = -1 # a non-clearing lock breaks the combo chain

	if not clear_event.is_empty():
		_emit(clear_event)
		events.append(clear_event)

	var prev_level := level
	level = int(floor(lines / 10.0)) + 1
	if level > prev_level:
		var ev := {"type": "levelup", "level": level}
		_emit(ev)
		events.append(ev)

	# Spawn the next piece (may trigger game over).
	_spawn_next()


func _score_clear(n: int, t_spin_info: Dictionary) -> int:
	var L := level
	var base := 0
	if t_spin_info["tSpin"]:
		base = 800 if n == 1 else (1200 if n == 2 else (1600 if n == 3 else 1600)) # T-spin tetris = 1600
	elif t_spin_info["miniTSpin"]:
		base = 100 if n == 1 else (200 if n == 2 else 400) # mini: no b2b, capped at triple
	else:
		base = 100 if n == 1 else (300 if n == 2 else (500 if n == 3 else 800))

	var qualifies_b2b: Variant = (t_spin_info["tSpin"] and n >= 1) or (not t_spin_info["miniTSpin"] and n == 4)
	var points := base * L
	if qualifies_b2b and b2b:
		points = int(floor(points * 1.5))

	# Combo: increments on every consecutive clearing lock, resets to -1 otherwise.
	combo += 1
	if combo > 0:
		points += 50 * combo * L

	b2b = qualifies_b2b
	lines += n
	score += points
	return points


# ------------------------------------------------------------- T-spin detection

func _corner_filled(cx: int, cy: int) -> bool:
	if cx < 0 or cx >= BOARD_WIDTH or cy < 0 or cy >= BOARD_HEIGHT:
		return true
	return board[cy][cx] != null


func is_t_spin() -> bool:
	# Exposed for tests: evaluates the current piece's lock position.
	if current == null or current["type"] != "T":
		return false
	var x := int(current["x"])
	var y := int(current["y"])
	var rot := int(current["rot"])
	var corners := [[x, y], [x + 2, y], [x, y + 2], [x + 2, y + 2]]
	var filled := []
	for c in corners:
		filled.append(_corner_filled(int(c[0]), int(c[1])))
	var count := 0
	for f in filled:
		if f:
			count += 1
	if count < 3:
		return false
	# Front corners depend on the rotation state.
	var front: Array
	match rot:
		0: front = [1, 2] # facing up: TR, BR
		1: front = [0, 1] # facing right: TL, TR
		2: front = [2, 3] # facing down: BL, BR
		_: front = [0, 3] # facing left: TL, BL
	return filled[front[0]] and filled[front[1]]


func _detect_t_spin() -> Dictionary:
	if current == null or current["type"] != "T":
		return {"tSpin": false, "miniTSpin": false}
	var x := int(current["x"])
	var y := int(current["y"])
	var rot := int(current["rot"])
	var corners := [[x, y], [x + 2, y], [x, y + 2], [x + 2, y + 2]]
	var filled := []
	for c in corners:
		filled.append(_corner_filled(int(c[0]), int(c[1])))
	var count := 0
	for f in filled:
		if f:
			count += 1
	if count < 3:
		return {"tSpin": false, "miniTSpin": false}

	var front: Array
	match rot:
		0: front = [1, 2]
		1: front = [0, 1]
		2: front = [2, 3]
		_: front = [0, 3]
	if filled[front[0]] and filled[front[1]]:
		return {"tSpin": true, "miniTSpin": false}

	# Mini T-spin: 3 corners filled but the last successful move was a kick.
	var last_kick := _last_move_was_kick
	_last_move_was_kick = false
	if last_kick:
		return {"tSpin": false, "miniTSpin": true}
	return {"tSpin": false, "miniTSpin": false}
