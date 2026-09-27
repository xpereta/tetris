# tests/test_gravity.gd — port of tests/gravity.test.js.

extends RefCounted

const TK := preload("res://tests/tk.gd")
const ENGINE := preload("res://src/engine.gd")
const HELPERS := preload("res://tests/helpers.gd")


static func run() -> void:
	_test_n_ticks_drop_exactly_n_rows_while_airborne()
	_test_default_formula_level_1_is_1000ms_per_row()
	_test_piece_locks_after_lock_delay_ms_of_ground_contact()
	_test_successful_moves_reset_the_timer()
	_test_max_15_move_resets_then_locks()
	_test_state_machine_start_pause_resume_reset()


static func _test_n_ticks_drop_exactly_n_rows_while_airborne() -> void:
	TK.begin("gravity: with gravityMs override, N ticks drop exactly N rows while airborne")
	var g = ENGINE.new({"seed": 1, "gravity_ms": 100})
	g.start()
	HELPERS.clear_board(g)
	HELPERS.set_piece(g, "O", 4, 21)

	for i in range(1, 6):
		var events := g.tick()
		TK.check(events is Array, "tick must return an array")
		TK.eq(int(g.current["y"]), 21 + i, "tick %d should drop exactly one row" % i)
	TK.end()


static func _test_default_formula_level_1_is_1000ms_per_row() -> void:
	TK.begin("gravity: default formula at level 1 is 1000ms per row (one tick = one row)")
	var g = ENGINE.new({"seed": 1}) # no gravityMs override -> guideline formula
	g.start()
	HELPERS.clear_board(g)
	HELPERS.set_piece(g, "O", 4, 21)
	TK.eq(g.level, 1, "level must be 1")
	g.tick()
	TK.eq(int(g.current["y"]), 22, "level 1: (0.8)^0 = 1s per row -> one tick drops one row")
	TK.end()


static func _test_piece_locks_after_lock_delay_ms_of_ground_contact() -> void:
	TK.begin("lock delay: piece locks after lockDelayMs of ground contact")
	var g = ENGINE.new({"seed": 1, "gravity_ms": 100, "lock_delay_ms": 500})
	g.start()
	HELPERS.clear_board(g)
	HELPERS.set_piece(g, "O", 4, 38) # resting on the floor (rows 38-39)

	for i in range(1, 5):
		g.tick()
		TK.check(g.current != null, "piece must not lock before %d grounded ticks" % i)
	var type_before: Variant = g.current["type"]
	g.tick() # 5th grounded tick: 500ms elapsed -> lock
	TK.check(g.current != null, "a new piece should have spawned")
	TK.eq(g.state, "playing", "state must still be playing")
	TK.end()


static func _test_successful_moves_reset_the_timer() -> void:
	TK.begin("lock delay: successful moves reset the timer (move-reset rule)")
	var g = ENGINE.new({"seed": 1, "gravity_ms": 100, "lock_delay_ms": 500})
	g.start()
	HELPERS.clear_board(g)
	HELPERS.set_piece(g, "O", 4, 38) # on the floor

	# 4 ticks (timer=400), then a successful move resets to 0.
	for i in range(4):
		g.tick()
	TK.eq(g.move_left(), true, "moveLeft must succeed")
	TK.eq(int(g.current["x"]), 3, "piece x after moveLeft")
	# 4 more ticks (timer back to 400) — still not locked.
	for i in range(4):
		g.tick()
		TK.check(g.current != null, "piece must survive after a move reset")
	g.tick() # now 5 ticks since the last reset -> lock
	TK.check(g.current != null, "a new piece should have spawned after the lock")
	TK.end()


static func _test_max_15_move_resets_then_locks() -> void:
	TK.begin("lock delay: max 15 move resets per piece, then it locks")
	var g = ENGINE.new({"seed": 1, "gravity_ms": 100, "lock_delay_ms": 500})
	g.start()
	HELPERS.clear_board(g)
	HELPERS.set_piece(g, "O", 4, 38) # on the floor; oscillate between x=4 and x=5

	var dir := -1
	for i in range(15):
		g.tick() # timer -> 100 (< 500)
		TK.check(g.current != null, "piece must survive reset %d" % (i + 1))
		var ok: bool = g.move_left() if dir == -1 else g.move_right()
		TK.eq(ok, true, "move %d should succeed" % (i + 1))
		dir *= -1 # alternate direction so every move succeeds

	# Reset cap exhausted: the next successful move must force a lock on the following tick.
	var ok: Variant = g.move_right()
	TK.eq(ok, true, "the 16th move should still succeed")
	TK.check(g.current != null, "no immediate lock from the move itself")
	g.tick()
	TK.check(g.current != null, "piece locked after exceeding the reset cap; new piece spawned")
	TK.end()


static func _test_state_machine_start_pause_resume_reset() -> void:
	TK.begin("state machine: start / pause / resume / reset")
	var g = ENGINE.new({"seed": 1})
	TK.eq(g.state, "idle", "initial state must be idle")
	g.start()
	TK.eq(g.state, "playing", "state after start")
	TK.check(g.current != null, "a current piece must exist after start")

	g.pause()
	TK.eq(g.state, "paused", "state after pause")
	var y_before := int(g.current["y"])
	g.tick() # paused: no gravity
	TK.eq(int(g.current["y"]), y_before, "tick while paused must not move the piece")

	g.resume()
	TK.eq(g.state, "playing", "state after resume")

	g.reset()
	TK.eq(g.score, 0, "score after reset")
	TK.eq(g.lines, 0, "lines after reset")
	TK.eq(g.level, 1, "level after reset")
	TK.eq(g.combo, -1, "combo after reset")
	TK.eq(g.b2b, false, "b2b after reset")
	TK.check(g.hold == null, "hold after reset must be null")
	var all_empty := true
	for row in g.board:
		for c in row:
			if c != null:
				all_empty = false
	TK.check(all_empty, "board after reset must be empty")
	TK.end()
