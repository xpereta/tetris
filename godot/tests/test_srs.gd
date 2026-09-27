# tests/test_srs.gd — shape/kick table identity vs js/srs.js.
# Expected values were dumped from Node.js running the frozen js/srs.js
# (all 4 rots of all 7 shapes; every CW and CCW kick transition for I, O, T).

extends RefCounted

const TK := preload("res://tests/tk.gd")
const SRS := preload("res://src/srs.gd")

static func run() -> void:
	_test_shapes_match_js_reference()
	_test_kick_tables_match_js_reference()

# SHAPES[type][rot] — verbatim from js/srs.js via Node dump.
const EXPECTED_SHAPES := {
	"I": [
		[[0, 1], [1, 1], [2, 1], [3, 1]],
		[[2, 0], [2, 1], [2, 2], [2, 3]],
		[[0, 2], [1, 2], [2, 2], [3, 2]],
		[[1, 0], [1, 1], [1, 2], [1, 3]],
	],
	"O": [
		[[0, 0], [1, 0], [0, 1], [1, 1]],
		[[0, 0], [1, 0], [0, 1], [1, 1]],
		[[0, 0], [1, 0], [0, 1], [1, 1]],
		[[0, 0], [1, 0], [0, 1], [1, 1]],
	],
	"T": [
		[[1, 0], [0, 1], [1, 1], [2, 1]],
		[[1, 0], [1, 1], [2, 1], [1, 2]],
		[[0, 1], [1, 1], [2, 1], [1, 2]],
		[[1, 0], [0, 1], [1, 1], [1, 2]],
	],
	"S": [
		[[1, 0], [2, 0], [0, 1], [1, 1]],
		[[1, 0], [1, 1], [2, 1], [2, 2]],
		[[1, 1], [2, 1], [0, 2], [1, 2]],
		[[0, 0], [0, 1], [1, 1], [1, 2]],
	],
	"Z": [
		[[0, 0], [1, 0], [1, 1], [2, 1]],
		[[2, 0], [1, 1], [2, 1], [1, 2]],
		[[0, 1], [1, 1], [1, 2], [2, 2]],
		[[1, 0], [0, 1], [1, 1], [0, 2]],
	],
	"J": [
		[[0, 0], [0, 1], [1, 1], [2, 1]],
		[[1, 0], [2, 0], [1, 1], [1, 2]],
		[[0, 1], [1, 1], [2, 1], [2, 2]],
		[[1, 0], [1, 1], [0, 2], [1, 2]],
	],
	"L": [
		[[2, 0], [0, 1], [1, 1], [2, 1]],
		[[1, 0], [1, 1], [1, 2], [2, 2]],
		[[0, 1], [1, 1], [2, 1], [0, 2]],
		[[0, 0], [1, 0], [1, 1], [1, 2]],
	],
}

# Kick transitions: key "TYPE:from->to" -> list of [dx, dy].
const EXPECTED_KICKS := {
	"I:0->1": [[0, 0], [-2, 0], [1, 0], [-2, 1], [1, -2]],
	"I:0->3": [[0, 0], [-1, 0], [2, 0], [-1, -2], [2, 2]],
	"I:1->0": [[0, 0], [2, 0], [-1, 0], [2, -1], [-1, 2]],
	"I:1->2": [[0, 0], [-1, 0], [2, 0], [-1, -2], [2, 1]],
	"I:2->1": [[0, 0], [1, 0], [-2, 0], [1, 2], [-2, -1]],
	"I:2->3": [[0, 0], [2, 0], [-1, 0], [2, -1], [-1, 2]],
	"I:3->0": [[0, 0], [1, 0], [-2, 0], [1, 2], [-2, -2]],
	"I:3->2": [[0, 0], [-2, 0], [1, 0], [-2, 1], [1, -2]],
	"O:0->1": [[0, 0]],
	"O:0->3": [[0, 0]],
	"O:1->0": [[0, 0]],
	"O:1->2": [[0, 0]],
	"O:2->1": [[0, 0]],
	"O:2->3": [[0, 0]],
	"O:3->0": [[0, 0]],
	"O:3->2": [[0, 0]],
	"T:0->1": [[0, 0], [-1, 0], [-1, -1], [0, 2], [-1, 2]],
	"T:0->3": [[0, 0], [1, 0], [1, 1], [0, 2], [1, 2]],
	"T:1->0": [[0, 0], [1, 0], [1, 1], [0, -2], [1, -2]],
	"T:1->2": [[0, 0], [1, 0], [1, -1], [0, -2], [1, -2]],
	"T:2->1": [[0, 0], [-1, 0], [-1, 1], [0, 2], [-1, 2]],
	"T:2->3": [[0, 0], [1, 0], [1, 1], [0, 2], [1, 2]],
	"T:3->0": [[0, 0], [-1, 0], [-1, -1], [0, -2], [-1, -2]],
	"T:3->2": [[0, 0], [-1, 0], [-1, -1], [0, -2], [-1, -2]],
}

static func _test_shapes_match_js_reference() -> void:
	TK.begin("srs: all 7 shapes x 4 rots match the JS reference")
	for t in SRS.PIECE_TYPES:
		var want: Variant = EXPECTED_SHAPES[t]
		var got: Variant = SRS.SHAPES[t]
		TK.check(got.size() == 4, "shape %s: expected 4 rots" % t)
		for r in range(4):
			if got[r].size() != want[r].size():
				TK.check(false, "shape %s rot %d: cell count differs" % [t, r])
				continue
			for i in range(got[r].size()):
				var gc: Variant = got[r][i]
				var wc: Variant = want[r][i]
				TK.check(gc[0] == wc[0] and gc[1] == wc[1], "shape %s rot %d cell %d: got [%d, %d] want [%d, %d]" % [t, r, i, gc[0], gc[1], wc[0], wc[1]])
	TK.end()

static func _test_kick_tables_match_js_reference() -> void:
	TK.begin("srs: kick tables (I/O/T, all 8 transitions each) match the JS reference")
	for key in EXPECTED_KICKS.keys():
		var parts: Variant = key.split(":")
		var t: Variant = parts[0]
		var tr: Variant = parts[1].split("->")
		var from_rot := int(tr[0])
		var to_rot := int(tr[1])
		var want: Variant = EXPECTED_KICKS[key]
		var got: Variant = SRS.get_kicks(t, from_rot, to_rot)
		TK.check(got.size() == want.size(), "kicks %s: count differs (got %d want %d)" % [key, got.size(), want.size()])
		for i in range(mini(got.size(), want.size())):
			var gc: Variant = got[i]
			var wc: Variant = want[i]
			TK.check(gc[0] == wc[0] and gc[1] == wc[1], "kicks %s offset %d: got [%d, %d] want [%d, %d]" % [key, i, gc[0], gc[1], wc[0], wc[1]])
	TK.end()
