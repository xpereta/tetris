# tests/test_bag.gd — port of tests/bag.test.js (7-bag randomizer).

extends RefCounted

const TK := preload("res://tests/tk.gd")
const ENGINE := preload("res://src/engine.gd")
const HELPERS := preload("res://tests/helpers.gd")


static func run() -> void:
	_test_first_bag_contains_each_piece_exactly_once()
	_test_queue_always_holds_at_least_5_upcoming_pieces()
	_test_same_seed_produces_identical_sequence()
	_test_different_seeds_produce_different_sequences()
	_test_every_bag_of_7_is_a_permutation_over_4_bags()


# Play `n` pieces and return the sequence of piece types. The board is wiped
# after every lock so the game can never block out — this isolates the pure
# 7-bag randomizer output, which is what these tests are about.
static func _play_sequence(seed: int, n: int) -> Array:
	var g = ENGINE.new({"seed": seed})
	g.start()
	var out := []
	for i in range(n):
		if g.state != "playing":
			break
		out.append(g.current["type"])
		g.hard_drop()
		HELPERS.clear_board(g)
	return out


static func _test_first_bag_contains_each_piece_exactly_once() -> void:
	TK.begin("7-bag: first 7 pieces of a fresh game contain each piece exactly once")
	var seq := _play_sequence(123, 7)
	TK.eq(seq.size(), 7, "sequence length must be 7")
	var counts := {}
	for t in seq:
		counts[t] = int(counts.get(t, 0)) + 1
	for t in ["I", "O", "T", "S", "Z", "J", "L"]:
		TK.eq(int(counts.get(t, 0)), 1, "piece %s should appear exactly once in the first bag" % t)
	TK.end()


static func _test_queue_always_holds_at_least_5_upcoming_pieces() -> void:
	TK.begin("7-bag: queue always holds at least 5 upcoming pieces")
	var g = ENGINE.new({"seed": 7})
	g.start()
	for i in range(20):
		if g.state != "playing":
			break
		TK.check(g.queue.size() >= 5, "queue length %d < 5 after piece %d" % [g.queue.size(), i])
		g.hard_drop()
		HELPERS.clear_board(g)
	TK.end()


static func _test_same_seed_produces_identical_sequence() -> void:
	TK.begin("7-bag: same seed produces the identical sequence")
	var a := "".join(_play_sequence(99, 21))
	var b := "".join(_play_sequence(99, 21))
	TK.eq(a.length(), 21, "sequence length must be 21")
	TK.eq(a, b, "same seed must produce the identical sequence")
	TK.end()


static func _test_different_seeds_produce_different_sequences() -> void:
	TK.begin("7-bag: different seeds produce different sequences")
	var a := "".join(_play_sequence(1, 21))
	var b := "".join(_play_sequence(2, 21))
	TK.neq(a, b, "seeds 1 and 2 must produce different sequences")
	TK.end()


static func _test_every_bag_of_7_is_a_permutation_over_4_bags() -> void:
	TK.begin("7-bag: every bag of 7 is a permutation (checked over 4 bags)")
	var seq := _play_sequence(5, 28)
	TK.eq(seq.size(), 28, "sequence length must be 28")
	for bag in range(4):
		var seven := []
		for i in range(bag * 7, bag * 7 + 7):
			seven.append(seq[i])
		seven.sort()
		TK.eq(seven, ["I", "J", "L", "O", "S", "T", "Z"], "bag %d must be a permutation of the 7 pieces" % (bag + 1))
	TK.end()
