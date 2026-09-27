# tests/test_autoplayer.gd — port of tests/autoplayer.test.js.

extends RefCounted

const TK := preload("res://tests/tk.gd")
const ENGINE := preload("res://src/engine.gd")
const AUTOPLAYER := preload("res://src/autoplayer.gd")


static func run() -> void:
	_test_plays_a_full_seeded_game_to_game_over_without_exceptions()


static func _test_plays_a_full_seeded_game_to_game_over_without_exceptions() -> void:
	TK.begin("autoplayer: plays a full seeded game to game over without exceptions")
	var events := []
	var g = ENGINE.new({
		"seed": 42,
		"gravity_ms": 100,
		"lock_delay_ms": 500,
	})
	g.connect("event_emitted", func(e: Dictionary): events.append(e))
	var ai = AUTOPLAYER.new(g)
	g.start()

	var iterations := 0
	while g.state != "over" and iterations < 20000:
		ai.step() # one decision per piece: rotate/move to target, then hard drop
		g.tick() # advance gravity for the freshly spawned piece
		iterations += 1

	TK.eq(g.state, "over", "game should end within 20000 iterations (stopped at %d)" % iterations)
	TK.check(iterations <= 20000, "iteration budget exceeded: %d" % iterations)
	TK.check(g.score > 1000, "final score %d should exceed 1000 after a full game" % g.score)

	var clears := 0
	for e in events:
		if e["type"] == "clear":
			clears += 1
	TK.check(clears >= 1, "at least one line clear must occur during the game")

	# Sanity: board height at end is within the physical board.
	var top_filled_row := -1
	for r in range(g.board.size()):
		var any := false
		for c in g.board[r]:
			if c != null:
				any = true
				break
		if any:
			top_filled_row = r
			break
	TK.check(top_filled_row >= -1 and top_filled_row < 40, "board height must be sane (< 40 rows used)")
	TK.end()
