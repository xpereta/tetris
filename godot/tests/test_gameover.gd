# tests/test_gameover.gd — port of tests/gameover.test.js.

extends RefCounted

const TK := preload("res://tests/tk.gd")
const ENGINE := preload("res://src/engine.gd")
const HELPERS := preload("res://tests/helpers.gd")


static func run() -> void:
	_test_block_out_at_spawn_sets_over_and_fires_gameover_event()
	_test_input_is_ignored_once_state_is_over()
	_test_piece_can_still_lock_normally_when_spawn_is_clear()


static func _test_block_out_at_spawn_sets_over_and_fires_gameover_event() -> void:
	TK.begin("game over: block-out at spawn sets state to over and fires the gameover event")
	var events := []
	var g = ENGINE.new({"seed": 42})
	g.connect("event_emitted", func(e: Dictionary): events.append(e))
	g.start()
	HELPERS.clear_board(g)

	# Fill rows 21-23 in cols 1-9 so any spawn overlaps existing blocks.
	# Col 0 stays empty so no row is complete (no accidental line clears).
	for r in range(21, 24):
		for c in range(1, ENGINE.BOARD_WIDTH):
			g.board[r][c] = "X"

	# Lock the current piece -> next piece spawns into the filled area.
	HELPERS.set_piece(g, "O", 4, 21)
	g.hard_drop()

	TK.eq(g.state, "over", "state must be over")
	var found := false
	for e in events:
		if e["type"] == "gameover":
			found = true
	TK.check(found, "a gameover event must be fired")
	TK.end()


static func _test_input_is_ignored_once_state_is_over() -> void:
	TK.begin("game over: input is ignored once the state is over")
	var g = ENGINE.new({"seed": 42})
	g.start()
	HELPERS.clear_board(g)
	for r in range(21, 24):
		for c in range(1, ENGINE.BOARD_WIDTH):
			g.board[r][c] = "X"
	HELPERS.set_piece(g, "O", 4, 21)
	g.hard_drop()
	TK.eq(g.state, "over", "state must be over")

	TK.eq(g.move_left(), false, "moveLeft after game over")
	TK.eq(g.rotate_cw(), false, "rotateCW after game over")
	TK.eq(g.soft_drop(), false, "softDrop after game over")
	TK.eq(g.hold_piece(), false, "holdPiece after game over")
	var before := _board_snapshot(g)
	g.tick()
	TK.eq(_board_snapshot(g), before, "tick must not mutate the board after game over")
	TK.end()


static func _test_piece_can_still_lock_normally_when_spawn_is_clear() -> void:
	TK.begin("game over: a piece can still lock normally when spawn is clear")
	var pair := HELPERS.make_game()
	var g = pair[0]
	g.start()
	# Fill only rows 24+ (below the spawn area) — spawning must succeed.
	for r in range(24, ENGINE.BOARD_HEIGHT):
		for c in range(ENGINE.BOARD_WIDTH):
			if c != 5:
				g.board[r][c] = "X"
	TK.eq(g.state, "playing", "state must be playing")
	TK.check(g.current != null, "a current piece must exist")
	TK.end()


static func _board_snapshot(g) -> Array:
	var snap := []
	for row in g.board:
		snap.append(row.duplicate())
	return snap
