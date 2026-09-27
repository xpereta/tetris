# tests/test_scoring.gd — port of tests/scoring.test.js.

extends RefCounted

const TK := preload("res://tests/tk.gd")
const ENGINE := preload("res://src/engine.gd")
const HELPERS := preload("res://tests/helpers.gd")


static func run() -> void:
	_test_single_clear_100_times_level()
	_test_double_clear_300_times_level()
	_test_tetris_800_times_level()
	_test_level_up_at_10_total_lines()
	_test_combo_increments_and_resets()
	_test_back_to_back_applies_only_to_tetrises_and_tspins()
	_test_soft_drop_plus_1_hard_drop_plus_2_per_cell()


static func _find_clear(events: Array) -> Dictionary:
	for e in events:
		if e["type"] == "clear":
			return e
	return {}


static func _last_clear(events: Array) -> Dictionary:
	var found := {}
	for e in events:
		if e["type"] == "clear":
			found = e
	return found


static func _test_single_clear_100_times_level() -> void:
	TK.begin("line clears: single = 100*level via hardDrop (drop bonus not multiplied)")
	var pair := HELPERS.make_game()
	var g = pair[0]
	var events: Array = pair[1]
	g.start()
	HELPERS.clear_board(g)
	HELPERS.fill_row(g, 39, [4]) # one full row with a gap at col 4
	HELPERS.set_piece(g, "I", 2, 30, 1) # vertical I in col x+2 = 4; falls to y=36 (rows 36-39), filling the gap

	g.hard_drop()
	var clear := _find_clear(events)
	TK.check(not clear.is_empty(), "a clear event must be emitted")
	TK.eq(int(clear["lines"]), 1, "clear.lines")
	TK.eq(bool(clear["tSpin"]), false, "clear.tSpin")
	TK.eq(int(clear["points"]), 100 * g.level, "clear.points (level is still 1)")
	var drop_distance := 36 - 30
	TK.eq(g.score, 100 + 2 * drop_distance, "score = clear points + hard drop bonus (+2/cell)")
	TK.eq(g.lines, 1, "lines after single")
	TK.end()


static func _test_double_clear_300_times_level() -> void:
	TK.begin("line clears: double = 300*level")
	var pair := HELPERS.make_game()
	var g = pair[0]
	var events: Array = pair[1]
	g.start()
	HELPERS.clear_board(g)
	HELPERS.fill_row(g, 38, [4])
	HELPERS.fill_row(g, 39, [4])
	# Vertical I in col x+2 = 4 (x=2), covering rows y..y+3; place it so it fills col 4 of both rows.
	HELPERS.set_piece(g, "I", 2, 36, 1)

	g.hard_drop()
	var clear := _find_clear(events)
	TK.check(not clear.is_empty(), "a clear event must be emitted")
	TK.eq(int(clear["lines"]), 2, "clear.lines")
	TK.eq(int(clear["points"]), 300 * g.level, "clear.points for a double")
	TK.end()


static func _test_tetris_800_times_level() -> void:
	TK.begin("line clears: tetris (4 rows) = 800*level")
	var pair := HELPERS.make_game()
	var g = pair[0]
	var events: Array = pair[1]
	g.start()
	HELPERS.clear_board(g)
	for r in range(36, 40):
		HELPERS.fill_row(g, r, [4]) # four full rows with a vertical gap at col 4
	HELPERS.set_piece(g, "I", 2, 20, 1) # vertical I in col 4

	g.hard_drop()
	var clear := _find_clear(events)
	TK.check(not clear.is_empty(), "a clear event must be emitted")
	TK.eq(int(clear["lines"]), 4, "clear.lines")
	TK.eq(int(clear["points"]), 800 * g.level, "clear.points for a tetris")
	TK.end()


static func _test_level_up_at_10_total_lines() -> void:
	TK.begin("level up at 10 total lines (level = floor(lines/10)+1)")
	var pair := HELPERS.make_game()
	var g = pair[0]
	var events: Array = pair[1]
	g.start()
	HELPERS.clear_board(g)
	# Simulate 9 prior lines without disturbing the board.
	g.lines = 9
	for r in range(36, 40):
		HELPERS.fill_row(g, r, [4])
	HELPERS.set_piece(g, "I", 2, 20, 1) # vertical I in col 4

	g.hard_drop()
	TK.eq(g.lines, 13, "lines after tetris")
	TK.eq(g.level, 2, "level after crossing 10 lines")
	var found := false
	for e in events:
		if e["type"] == "levelup":
			found = true
			TK.eq(int(e["level"]), 2, "levelup event level")
	TK.check(found, "a levelup event must be emitted")
	TK.end()


static func _test_combo_increments_and_resets() -> void:
	TK.begin("combo: increments across consecutive clears and resets to -1 after a non-clearing lock")
	var pair := HELPERS.make_game()
	var g = pair[0]
	var events: Array = pair[1]
	g.start()
	HELPERS.clear_board(g)

	# Lock #1: single (row 39 full except col 4; vertical I in col 4 fills it).
	HELPERS.fill_row(g, 39, [4])
	HELPERS.set_piece(g, "I", 2, 36, 1)
	g.hard_drop()
	var clear := _find_clear(events)
	TK.eq(int(clear["combo"]), 0, "first clearing lock has combo 0 (no bonus)")

	# Lock #2: another single -> combo should be 1 and add 50*combo*level.
	HELPERS.clear_board(g)
	HELPERS.fill_row(g, 39, [4])
	HELPERS.set_piece(g, "I", 2, 36, 1)
	g.hard_drop()
	clear = _last_clear(events)
	TK.eq(int(clear["combo"]), 1, "second consecutive clear has combo 1")
	TK.eq(int(clear["points"]), 100 + 50 * 1 * g.level, "clear.points with combo bonus")

	# Lock #3: non-clearing lock -> combo resets to -1.
	HELPERS.clear_board(g)
	HELPERS.set_piece(g, "O", 4, 38)
	g.hard_drop()
	TK.eq(g.combo, -1, "combo must reset to -1 after a non-clearing lock")

	# Lock #4: clearing again -> combo back to 0.
	HELPERS.clear_board(g)
	HELPERS.fill_row(g, 39, [4])
	HELPERS.set_piece(g, "I", 2, 36, 1)
	g.hard_drop()
	clear = _last_clear(events)
	TK.eq(int(clear["combo"]), 0, "combo back to 0 after the chain broke")
	TK.end()


static func _test_back_to_back_applies_only_to_tetrises_and_tspins() -> void:
	TK.begin("back-to-back: applies only to Tetrises and T-spin line clears")
	var pair := HELPERS.make_game()
	var g = pair[0]
	g.start()
	HELPERS.clear_board(g)

	# A double does NOT qualify for b2b.
	HELPERS.fill_row(g, 38, [4])
	HELPERS.fill_row(g, 39, [4])
	HELPERS.set_piece(g, "I", 2, 36, 1) # vertical I in col 4 filling both rows
	g.hard_drop()
	TK.eq(g.b2b, false, "a double must not start a b2b chain")

	# A Tetris qualifies.
	HELPERS.clear_board(g)
	for r in range(36, 40):
		HELPERS.fill_row(g, r, [4])
	HELPERS.set_piece(g, "I", 2, 20, 1)
	g.hard_drop()
	TK.eq(g.b2b, true, "a Tetris must start a b2b chain")

	# A following Tetris gets the x1.5 multiplier (level at lock time = 1: lines=6).
	HELPERS.clear_board(g)
	for r in range(36, 40):
		HELPERS.fill_row(g, r, [4])
	HELPERS.set_piece(g, "I", 2, 20, 1)
	var L: Variant = g.level # level at lock time (lines=6 -> level 1)
	var score_before: Variant = g.score
	g.hard_drop()
	TK.eq(g.b2b, true, "chain stays alive")
	# Combo is now 2 (double->0, first Tetris->1, this one->2): base 800*L*1.5 + 50*2*L.
	var expected: Variant = int(floor(800 * L * 1.5)) + 50 * 2 * L
	TK.eq(g.score - score_before, expected + 2 * (36 - 20), "score delta = b2b tetris points + hard drop bonus (16 cells)")

	# A single after the chain does NOT get b2b and breaks the chain.
	HELPERS.clear_board(g)
	HELPERS.fill_row(g, 39, [4])
	HELPERS.set_piece(g, "I", 2, 36, 1) # vertical I in col 4; already resting on row 39 (drop distance 0)
	var L2: Variant = g.level # lines=10 -> level 2 at lock time
	var score_before2: Variant = g.score
	g.hard_drop()
	TK.eq(g.b2b, false, "a single must break the b2b chain")
	# No multiplier: 100*L2 + combo (now 3): 50*3*L2. Drop distance is 0.
	var expected2: Variant = 100 * L2 + 50 * 3 * L2
	TK.eq(g.score - score_before2, expected2, "score delta for the non-b2b single")
	TK.end()


static func _test_soft_drop_plus_1_hard_drop_plus_2_per_cell() -> void:
	TK.begin("soft drop adds +1 per cell; hard drop adds +2 per cell (not multiplied by level)")
	var pair := HELPERS.make_game()
	var g = pair[0]
	g.start()
	HELPERS.clear_board(g)
	HELPERS.set_piece(g, "O", 4, 21) # O occupies rows 21-22; floor at row 39 -> lands at y=38 (rows 38-39)

	var dist := 38 - 21
	for i in range(dist):
		TK.eq(g.soft_drop(), true, "softDrop %d must succeed" % (i + 1))
	TK.eq(g.score, dist * 1, "score after soft drops = dist * 1")
	g.hard_drop() # already on the ground: +0 drop cells, locks
	TK.eq(g.score, dist * 1, "hardDrop from the floor adds no drop bonus")

	var pair2 := HELPERS.make_game()
	var g2 = pair2[0]
	g2.start()
	HELPERS.clear_board(g2)
	HELPERS.set_piece(g2, "O", 4, 21)
	g2.hard_drop()
	TK.eq(g2.score, dist * 2, "hard drop from spawn adds +2 per cell")
	TK.end()
