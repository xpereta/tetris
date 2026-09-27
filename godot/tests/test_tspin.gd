# tests/test_tspin.gd — port of tests/tspin.test.js.

extends RefCounted

const TK := preload("res://tests/tk.gd")
const ENGINE := preload("res://src/engine.gd")
const HELPERS := preload("res://tests/helpers.gd")


static func run() -> void:
	_test_t_spin_double_natural_descent_1200_points()
	_test_following_tetris_gets_b2b_multiplier()
	_test_is_t_spin_true_at_lock_position_false_otherwise()
	_test_mini_t_spin_single_100_no_b2b()


# Classic T-spin double setup (built in code):
#   row 37: . . . . X . . . . .        <- TL corner of the T's bbox filled
#   row 38: X X X X X . . . X X X      <- gap at cols 5,6,7 for the slot
#   row 39: X X X X X X . X X X        <- gap only at col 6 (the T's bottom cell)
static func _build_t_spin_double(g) -> void:
	HELPERS.clear_board(g)
	g.board[37][5] = "X" # TL corner overhang
	for c in [0, 1, 2, 3, 4, 8, 9]:
		g.board[38][c] = "X" # gap cols 5-7
	for c in [0, 1, 2, 3, 4, 5, 7, 8, 9]:
		g.board[39][c] = "X" # gap col 6 only


# Natural play: the T spawns, moves right twice to x=5, rotates CW to rot=1 and
# descends vertically through cols 6-7 until it rests on row 39 (y=37). One more
# CW rotation drops it into the slot at x=5,y=37,rot=2.
static func _play_t_spin_double(g) -> void:
	HELPERS.set_piece(g, "T", 3, 21) # standard T spawn (cells (4,21),(3,22),(4,22),(5,22))
	TK.eq(g.move_right(), true, "moveRight #1")
	TK.eq(g.move_right(), true, "moveRight #2")
	TK.eq(int(g.current["x"]), 5, "T at x=5 after two moves right")
	TK.eq(g.rotate_cw(), true, "rotateCW to rot=1")
	for i in range(16):
		TK.eq(g.soft_drop(), true, "softDrop %d descending" % (i + 1)) # descend to y=37
	TK.eq(int(g.current["y"]), 37, "T rests at y=37")
	TK.eq(g.rotate_cw(), true, "rotateCW into the slot")
	TK.eq(int(g.current["rot"]), 2, "T in rot=2 inside the slot")


static func _test_t_spin_double_natural_descent_1200_points() -> void:
	TK.begin("T-spin double: natural descent detects tSpin with 1200*level points")
	var pair := HELPERS.make_game()
	var g = pair[0]
	var events: Array = pair[1]
	g.start()
	_build_t_spin_double(g)
	HELPERS.force_next(g, ["I"]) # known upcoming piece for the b2b follow-up test

	_play_t_spin_double(g)
	TK.eq(g.is_t_spin(), true, "3-corner rule must classify this lock as a T-spin")

	g.hard_drop()
	var clear := {}
	for e in events:
		if e["type"] == "clear":
			clear = e
	TK.check(not clear.is_empty(), "a clear event must be emitted")
	TK.eq(int(clear["lines"]), 2, "clear.lines")
	TK.eq(bool(clear["tSpin"]), true, "must be detected as a T-spin (3-corner rule)")
	TK.eq(bool(clear["miniTSpin"]), false, "must not be flagged mini")
	TK.eq(int(clear["points"]), 1200 * g.level, "clear.points = 1200*level (level is still 1)")
	TK.eq(g.b2b, true, "a T-spin line clear must start a b2b chain")
	TK.end()


static func _test_following_tetris_gets_b2b_multiplier() -> void:
	TK.begin("T-spin double: following Tetris gets the x1.5 back-to-back multiplier")
	var pair := HELPERS.make_game()
	var g = pair[0]
	var events: Array = pair[1]
	g.start()
	_build_t_spin_double(g)
	HELPERS.force_next(g, ["I"])

	_play_t_spin_double(g)
	g.hard_drop() # T-spin double -> b2b = true

	TK.eq(g.current["type"], "I", "the forced I must be the next piece")

	# Now a plain Tetris while b2b is active.
	HELPERS.clear_board(g)
	for r in range(36, 40):
		for c in range(ENGINE.BOARD_WIDTH):
			if c != 4:
				g.board[r][c] = "X"
	HELPERS.set_piece(g, "I", 2, 20, 1) # vertical I in col 4
	var L: Variant = g.level # lines=2 -> level 1 at lock time
	var score_before: Variant = g.score

	g.hard_drop()
	var clear := {}
	for e in events:
		if e["type"] == "clear":
			clear = e
	TK.check(not clear.is_empty(), "a clear event must be emitted")
	TK.eq(int(clear["lines"]), 4, "clear.lines for the tetris")
	TK.eq(bool(clear["tSpin"]), false, "the tetris is not a T-spin")
	TK.eq(bool(clear["b2b"]), true, "the Tetris must be flagged as b2b")
	# Base 800*L * 1.5 + combo (combo was 0 after the TSD, now 1): +50*1*L.
	var expected: Variant = int(floor(800 * L * 1.5)) + 50 * 1 * L
	TK.eq(int(clear["points"]), expected, "clear.points = b2b tetris base + combo (no drop bonus)")
	TK.eq(g.score - score_before, expected + 2 * (36 - 20), "score delta includes the hard drop bonus (16 cells)")
	TK.eq(g.b2b, true, "chain stays alive after a b2b-qualifying clear")
	TK.end()


static func _test_is_t_spin_true_at_lock_position_false_otherwise() -> void:
	TK.begin("isTSpin(): true at the T-spin double lock position, false otherwise")
	var g = ENGINE.new({"seed": 1})
	g.start()
	_build_t_spin_double(g)
	HELPERS.set_piece(g, "T", 5, 37, 2) # exactly where it locks in the natural test
	TK.eq(g.is_t_spin(), true, "isTSpin at the TSD lock position")

	HELPERS.clear_board(g)
	HELPERS.set_piece(g, "T", 4, 30, 1) # open space: no corners filled
	TK.eq(g.is_t_spin(), false, "isTSpin in open space must be false")

	var g2 = ENGINE.new({"seed": 1})
	g2.start()
	HELPERS.set_piece(g2, "I", 4, 30, 0) # non-T piece is never a T-spin
	TK.eq(g2.is_t_spin(), false, "non-T pieces are never T-spins")
	TK.end()


static func _test_mini_t_spin_single_100_no_b2b() -> void:
	TK.begin("mini T-spin single: 3 corners filled but front not both -> mini (100*level, no b2b)")
	var pair := HELPERS.make_game()
	var g = pair[0]
	var events: Array = pair[1]
	g.start()
	HELPERS.clear_board(g)
	# T in rot=1 at x=4,y=37: cells (5,37),(5,38),(6,38),(5,39). Clears row 39 only.
	for c in range(ENGINE.BOARD_WIDTH):
		if c != 5:
			g.board[39][c] = "X" # gap at col 5
	g.board[37][6] = "X" # TR corner filled -> corners: TR, BL(4,39), BR(6,39) = 3
	HELPERS.set_piece(g, "T", 4, 37, 1)
	TK.eq(g.is_t_spin(), false, "front corners (TL,TR) are not both filled")
	g._last_move_was_kick = true # last successful move was a kick -> mini T-spin

	g.hard_drop()
	var clear := {}
	for e in events:
		if e["type"] == "clear":
			clear = e
	TK.check(not clear.is_empty(), "a clear event must be emitted")
	TK.eq(int(clear["lines"]), 1, "mini T-spin single clears one row")
	TK.eq(bool(clear["tSpin"]), false, "must not be flagged as a full T-spin")
	TK.eq(bool(clear["miniTSpin"]), true, "must be flagged mini")
	TK.eq(int(clear["points"]), 100 * g.level, "mini single: no b2b multiplier")
	TK.eq(g.b2b, false, "mini T-spins must not start a b2b chain")
	TK.end()
