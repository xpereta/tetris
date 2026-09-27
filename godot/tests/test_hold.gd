# tests/test_hold.gd — port of tests/hold.test.js.

extends RefCounted

const TK := preload("res://tests/tk.gd")
const ENGINE := preload("res://src/engine.gd")
const HELPERS := preload("res://tests/helpers.gd")


static func run() -> void:
	_test_holding_when_hold_empty_puts_current_into_hold_and_spawns_next()
	_test_cannot_re_hold_before_the_next_lock()
	_test_swapping_puts_current_into_hold_and_spawns_held_one()
	_test_works_from_a_fresh_game_with_natural_first_piece()


static func _test_holding_when_hold_empty_puts_current_into_hold_and_spawns_next() -> void:
	TK.begin("hold: holding when hold is empty puts the current piece into hold and spawns next")
	var pair := HELPERS.make_game()
	var g = pair[0]
	var events: Array = pair[1]
	g.start()
	HELPERS.clear_board(g)
	HELPERS.force_next(g, ["I"]) # known upcoming piece
	HELPERS.set_piece(g, "T", 3, 21)

	TK.check(g.hold == null, "hold must start empty")
	TK.eq(g.can_hold, true, "canHold before first hold")
	var ok: Variant = g.hold_piece()
	TK.eq(ok, true, "holdPiece must succeed")
	TK.eq(g.hold, "T", "the T goes into hold")
	TK.eq(g.current["type"], "I", "the queued piece must spawn into the current slot")
	TK.eq(g.can_hold, false, "cannot hold again until the next lock")

	var hold_event := {}
	for e in events:
		if e["type"] == "hold":
			hold_event = e
	TK.check(not hold_event.is_empty(), "a hold event must be emitted")
	TK.eq(hold_event.get("piece"), "I", "the hold event reports the newly current piece")
	TK.end()


static func _test_cannot_re_hold_before_the_next_lock() -> void:
	TK.begin("hold: cannot re-hold before the next lock (double-hold blocked)")
	var pair := HELPERS.make_game()
	var g = pair[0]
	g.start()
	HELPERS.clear_board(g)
	HELPERS.force_next(g, ["I", "O"]) # must be called AFTER start() — start() resets the queue
	HELPERS.set_piece(g, "T", 3, 21)

	TK.eq(g.hold_piece(), true, "first hold: T -> hold, I spawns")
	TK.eq(g.can_hold, false, "canHold must be false after a hold")
	TK.eq(g.hold_piece(), false, "second hold before a lock must be rejected")
	TK.eq(g.current["type"], "I", "current piece unchanged after the rejected hold")

	# After the piece locks, holding is allowed again.
	g.hard_drop() # locks the I; next queued piece (O) spawns
	TK.eq(g.can_hold, true, "canHold restored after lock")
	TK.eq(g.current["type"], "O", "the O must be current now")
	TK.eq(g.hold_piece(), true, "hold after lock must succeed")
	TK.eq(g.hold, "O", "the O goes into hold...")
	TK.eq(g.current["type"], "T", "...and the held T comes back out")
	TK.end()


static func _test_swapping_puts_current_into_hold_and_spawns_held_one() -> void:
	TK.begin("hold: swapping puts the current piece into hold and spawns the held one")
	var pair := HELPERS.make_game()
	var g = pair[0]
	g.start()
	HELPERS.clear_board(g)
	HELPERS.force_next(g, ["S"])
	HELPERS.set_piece(g, "T", 3, 21)

	TK.eq(g.hold_piece(), true, "hold=T, S spawns")
	g.hard_drop() # lock S -> canHold restored

	HELPERS.force_next(g, ["Z"])
	HELPERS.set_piece(g, "L", 3, 21)
	TK.eq(g.hold_piece(), true, "swap hold must succeed")
	TK.eq(g.hold, "L", "the L goes into hold")
	TK.eq(g.current["type"], "T", "the previously held T must spawn back out")
	TK.end()


static func _test_works_from_a_fresh_game_with_natural_first_piece() -> void:
	TK.begin("hold: works from a fresh game with the natural first piece")
	var g = ENGINE.new({"seed": 42})
	g.start()
	var first_type: Variant = g.current["type"]
	TK.eq(g.hold_piece(), true, "holdPiece on the natural first piece must succeed")
	TK.eq(g.hold, first_type, "the first piece goes into hold")
	TK.check(g.current["type"] != null, "a new current piece must exist after hold")
	TK.end()
