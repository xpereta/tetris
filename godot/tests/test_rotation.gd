# tests/test_rotation.gd — port of tests/rotation.test.js.

extends RefCounted

const TK := preload("res://tests/tk.gd")
const ENGINE := preload("res://src/engine.gd")
const HELPERS := preload("res://tests/helpers.gd")


static func run() -> void:
	_test_t_piece_cw_ccw_returns_to_spawn_cells()
	_test_i_vertical_against_right_wall_kicks_left()
	_test_o_piece_stays_in_place_on_rotate()
	_test_jlstz_t_right_wall_uses_kick2_of_3to0()
	_test_jlstz_t_slot_uses_kick2_of_0to1()
	_test_jlstz_t_slot_uses_kick1_of_1to2()
	_test_i_against_left_wall_uses_kick3_of_1to2()
	_test_rotation_fails_when_all_five_kicks_collide()


# JS: sorted(cells) with comparator a[0]-b[0] || a[1]-b[1].
static func _sorted(cells: Array) -> Array:
	var out := []
	for c in cells:
		out.append([int(c[0]), int(c[1])])
	out.sort_custom(func(a, b):
		if a[0] != b[0]:
			return a[0] < b[0]
		return a[1] < b[1])
	return out


static func _cells_at(g) -> Array:
	return _sorted(g.cells_of(g.current["type"], int(g.current["x"]), int(g.current["y"]), int(g.current["rot"])))


# JS assert.deepEqual on the current piece dict.
static func _check_current(g, expected: Dictionary, msg := "") -> void:
	var c: Variant = g.current
	TK.check(c != null and c.size() == 4, "%s (current is %s)" % [msg, str(c)])
	if c == null:
		return
	TK.eq(str(c["type"]), str(expected["type"]), msg + " field type")
	TK.eq(int(c["x"]), int(expected["x"]), msg + " field x")
	TK.eq(int(c["y"]), int(expected["y"]), msg + " field y")
	TK.eq(int(c["rot"]), int(expected["rot"]), msg + " field rot")


static func _test_t_piece_cw_ccw_returns_to_spawn_cells() -> void:
	TK.begin("SRS: T-piece spawn -> CW -> CCW returns to the exact spawn cells")
	var g = ENGINE.new({"seed": 1})
	g.start()
	HELPERS.set_piece(g, "T", 3, 21) # standard T spawn position
	_check_current(g, {"type": "T", "x": 3, "y": 21, "rot": 0}, "current after setPiece")

	var spawn_cells := _cells_at(g)
	TK.eq(spawn_cells, [[3, 22], [4, 21], [4, 22], [5, 22]], "spawn cells of T at (3,21)")

	TK.eq(g.rotate_cw(), true, "rotateCW must succeed")
	TK.eq(int(g.current["rot"]), 1, "rot after CW")
	TK.eq(_cells_at(g), [[4, 21], [4, 22], [4, 23], [5, 22]], "cells at rot=1")

	TK.eq(g.rotate_ccw(), true, "rotateCCW must succeed")
	TK.eq(int(g.current["rot"]), 0, "rot after CCW")
	TK.eq(_cells_at(g), spawn_cells, "CW then CCW must restore the exact spawn cells")
	TK.end()


static func _test_i_vertical_against_right_wall_kicks_left() -> void:
	TK.begin("SRS: I-piece vertical against the right wall kicks left (kick #3 of 3->0)")
	var g = ENGINE.new({"seed": 1})
	g.start()
	HELPERS.clear_board(g)
	# Vertical I in rot=3 occupies column x+1. Flush against the right wall: col 9 -> x=8.
	HELPERS.set_piece(g, "I", 8, 20, 3)
	var cols := []
	for c in g.cells_of("I", 8, 20, 3):
		cols.append(int(c[0]))
	TK.eq(cols, [9, 9, 9, 9], "rot=3 I at x=8 must occupy col 9")

	var ok: Variant = g.rotate_cw() # 3 -> 0
	TK.eq(ok, true, "rotateCW must succeed")
	TK.eq(int(g.current["rot"]), 0, "rot after CW")
	# Kick #3 (-2,0) applies: x=6, cells cols 6-9 in row y+1 = 21.
	TK.eq(int(g.current["x"]), 6, "kicked x")
	TK.eq(int(g.current["y"]), 20, "kicked y")
	TK.eq(_cells_at(g), [[6, 21], [7, 21], [8, 21], [9, 21]], "final cells after kick")
	TK.end()


static func _test_o_piece_stays_in_place_on_rotate() -> void:
	TK.begin("SRS: O piece stays in place on rotate (no effective kicks)")
	var g = ENGINE.new({"seed": 1})
	g.start()
	HELPERS.set_piece(g, "O", 4, 21)
	TK.eq(g.rotate_cw(), true, "rotateCW must succeed")
	_check_current(g, {"type": "O", "x": 4, "y": 21, "rot": 1}, "current after CW")
	TK.eq(g.rotate_ccw(), true, "rotateCCW must succeed")
	_check_current(g, {"type": "O", "x": 4, "y": 21, "rot": 0}, "current after CCW")
	TK.end()


static func _test_jlstz_t_right_wall_uses_kick2_of_3to0() -> void:
	TK.begin("wall kicks (JLSTZ): T against right wall uses kick #2 of 3->0 (dx=-1), exact x/y/rot")
	var g = ENGINE.new({"seed": 1})
	g.start()
	HELPERS.clear_board(g)
	# T in rot=3 at x=8: cells (9,30),(8,31),(9,31),(9,32) — flush against the right wall.
	HELPERS.set_piece(g, "T", 8, 30, 3)
	var ok: Variant = g.rotate_cw() # 3 -> 0
	TK.eq(ok, true, "rotateCW must succeed")
	TK.eq(int(g.current["rot"]), 0, "rot after CW")
	# Kick #2 (-1,0) applies.
	TK.eq(int(g.current["x"]), 7, "kicked x")
	TK.eq(int(g.current["y"]), 30, "kicked y")
	TK.eq(_cells_at(g), [[7, 31], [8, 30], [8, 31], [9, 31]], "final cells after kick")
	TK.end()


static func _test_jlstz_t_slot_uses_kick2_of_0to1() -> void:
	TK.begin("wall kicks (JLSTZ): T in a slot uses kick #2 of 0->1 (dx=-1), exact x/y/rot")
	var g = ENGINE.new({"seed": 1})
	g.start()
	HELPERS.clear_board(g)
	# T rot=0 at x=4,y=30: cells (5,30),(4,31),(5,31),(6,31).
	HELPERS.set_piece(g, "T", 4, 30)
	# Block the base rot=1 cell that is not part of rot=0: (x+1,y+2) = (5,32).
	g.board[32][5] = "X"
	var ok: Variant = g.rotate_cw() # 0 -> 1
	TK.eq(ok, true, "rotateCW must succeed")
	TK.eq(int(g.current["rot"]), 1, "rot after CW")
	# Kick #2 (-1,0): x=3,y=30: cells (4,30),(4,31),(5,31),(4,32) — all free.
	TK.eq(int(g.current["x"]), 3, "kicked x")
	TK.eq(int(g.current["y"]), 30, "kicked y")
	TK.end()


static func _test_jlstz_t_slot_uses_kick1_of_1to2() -> void:
	TK.begin("wall kicks (JLSTZ): T in a slot uses kick #1 of 1->2 (dx=+1), exact x/y/rot")
	var g = ENGINE.new({"seed": 1})
	g.start()
	HELPERS.clear_board(g)
	# T rot=1 at x=4,y=30: cells (5,30),(5,31),(6,31),(5,32).
	HELPERS.set_piece(g, "T", 4, 30, 1)
	# Block the base rot=2 cell that is not part of rot=1: (x,y+1) = (4,31).
	g.board[31][4] = "X"
	var ok: Variant = g.rotate_cw() # 1 -> 2
	TK.eq(ok, true, "rotateCW must succeed")
	TK.eq(int(g.current["rot"]), 2, "rot after CW")
	# Kick #1 (+1,0): x=5,y=30: cells (5,31),(6,31),(7,31),(6,32) — all free.
	TK.eq(int(g.current["x"]), 5, "kicked x")
	TK.eq(int(g.current["y"]), 30, "kicked y")
	TK.end()


static func _test_i_against_left_wall_uses_kick3_of_1to2() -> void:
	TK.begin("wall kicks (I): I against left wall uses kick #3 of 1->2 (dx=+2), exact x/y/rot")
	var g = ENGINE.new({"seed": 1})
	g.start()
	HELPERS.clear_board(g)
	# Vertical I in rot=1 occupies column x+2. Flush against the left wall: col 0 -> x=-2.
	HELPERS.set_piece(g, "I", -2, 30, 1)
	var cols := []
	for c in g.cells_of("I", -2, 30, 1):
		cols.append(int(c[0]))
	TK.eq(cols, [0, 0, 0, 0], "rot=1 I at x=-2 must occupy col 0")

	var ok: Variant = g.rotate_cw() # 1 -> 2
	TK.eq(ok, true, "rotateCW must succeed")
	TK.eq(int(g.current["rot"]), 2, "rot after CW")
	# Kick #3 (+2,0) applies.
	TK.eq(int(g.current["x"]), 0, "kicked x")
	TK.eq(int(g.current["y"]), 30, "kicked y")
	TK.eq(_cells_at(g), [[0, 32], [1, 32], [2, 32], [3, 32]], "final cells after kick")
	TK.end()


static func _test_rotation_fails_when_all_five_kicks_collide() -> void:
	TK.begin("rotation fails when all five kick tests collide")
	var g = ENGINE.new({"seed": 1})
	g.start()
	HELPERS.clear_board(g)
	set_piece_setup(g)
	TK.eq(g.rotate_cw(), false, "rotateCW must fail with all kicks blocked")
	# Piece unchanged.
	_check_current(g, {"type": "T", "x": 4, "y": 30, "rot": 0}, "piece must be unchanged after failed rotation")
	TK.end()


static func set_piece_setup(g) -> void:
	HELPERS.set_piece(g, "T", 4, 30)
	g.board[32][5] = "X"
	g.board[30][4] = "X"
	g.board[29][4] = "X"
	g.board[32][4] = "X"
