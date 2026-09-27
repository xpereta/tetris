# tests/test_ghost.gd — port of tests/ghost.test.js.

extends RefCounted

const TK := preload("res://tests/tk.gd")
const ENGINE := preload("res://src/engine.gd")
const HELPERS := preload("res://tests/helpers.gd")


static func run() -> void:
	_test_empty_board_o_piece_ghost_lands_on_floor()
	_test_empty_board_i_piece_rot0_ghost_lands_on_floor()
	_test_vertical_i_piece_ghost_lands_on_floor()
	_test_ghost_lands_on_top_of_a_stack()
	_test_piece_already_resting_has_ghost_y_equal_to_current_y()
	_test_t_piece_ghost_lands_in_a_slot()


static func _test_empty_board_o_piece_ghost_lands_on_floor() -> void:
	TK.begin("ghost: empty board — O piece ghost lands on the floor")
	var g = ENGINE.new({"seed": 1})
	g.start()
	HELPERS.clear_board(g)
	HELPERS.set_piece(g, "O", 4, 21) # occupies rows y..y+1; floor is row 39 -> ghost at y=38
	TK.eq(int(g.ghost_y()), 38, "ghostY for O on empty board")
	TK.end()


static func _test_empty_board_i_piece_rot0_ghost_lands_on_floor() -> void:
	TK.begin("ghost: empty board — I piece (rot=0) ghost lands on the floor")
	var g = ENGINE.new({"seed": 1})
	g.start()
	HELPERS.clear_board(g)
	HELPERS.set_piece(g, "I", 3, 21, 0) # occupies row y+1; ghost at y=38 (row 39)
	TK.eq(int(g.ghost_y()), 38, "ghostY for I rot=0 on empty board")
	TK.end()


static func _test_vertical_i_piece_ghost_lands_on_floor() -> void:
	TK.begin("ghost: vertical I piece ghost lands on the floor")
	var g = ENGINE.new({"seed": 1})
	g.start()
	HELPERS.clear_board(g)
	HELPERS.set_piece(g, "I", 4, 20, 1) # occupies rows y..y+3; ghost at y=36 (rows 36-39)
	TK.eq(int(g.ghost_y()), 36, "ghostY for vertical I on empty board")
	TK.end()


static func _test_ghost_lands_on_top_of_a_stack() -> void:
	TK.begin("ghost: lands on top of a stack")
	var g = ENGINE.new({"seed": 1})
	g.start()
	HELPERS.clear_board(g)
	# Stack: col 5 filled in rows 37-39.
	for r in range(37, 40):
		g.board[r][5] = "X"
	HELPERS.set_piece(g, "O", 4, 21) # O spans cols 4-5 -> must land on top of col 5's stack: y=35.
	TK.eq(int(g.ghost_y()), 35, "ghostY for O resting on a 3-high stack")
	TK.end()


static func _test_piece_already_resting_has_ghost_y_equal_to_current_y() -> void:
	TK.begin("ghost: piece already resting on the ground has ghostY == current.y")
	var g = ENGINE.new({"seed": 1})
	g.start()
	HELPERS.clear_board(g)
	HELPERS.set_piece(g, "O", 4, 38) # rows 38-39: on the floor
	TK.eq(int(g.ghost_y()), 38, "ghostY must equal current.y when resting")
	TK.end()


static func _test_t_piece_ghost_lands_in_a_slot() -> void:
	TK.begin("ghost: T piece ghost lands in a slot")
	var g = ENGINE.new({"seed": 1})
	g.start()
	HELPERS.clear_board(g)
	# Slot for a rot=2 T at x=4,y=37: cells (4,38),(5,38),(6,38),(5,39).
	# Fill row 39 except col 5; fill row 38 cols 0-3 and 7-9.
	for c in range(ENGINE.BOARD_WIDTH):
		if c != 5:
			g.board[39][c] = "X"
	for c in [0, 1, 2, 3, 7, 8, 9]:
		g.board[38][c] = "X"
	HELPERS.set_piece(g, "T", 4, 20, 2) # rot=2 cells: (x,y+1),(x+1,y+1),(x+2,y+1),(x+1,y+2)
	TK.eq(int(g.ghost_y()), 37, "ghostY for T dropping into the slot")
	TK.end()
