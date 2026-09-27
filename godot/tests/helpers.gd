# tests/helpers.gd — port of tests/helpers.js (white-box setup helpers).

extends RefCounted


const ENGINE := preload("res://src/engine.gd")


# Create a deterministic game that records every event in `events`.
static func make_game(opts: Dictionary = {}) -> Array:
	var events := []
	var o := {
		"seed": 42,
		"gravity_ms": 100,
		"lock_delay_ms": 500,
	}
	for k in opts.keys():
		o[k] = opts[k]
	var game = ENGINE.new(o)
	game.connect("event_emitted", func(e: Dictionary): events.append(e))
	return [game, events]


# Place a piece directly (white-box helper for deterministic setups).
static func set_piece(game, type: String, x: int, y: int, rot := 0) -> void:
	game.current = {"type": type, "x": x, "y": y, "rot": rot}
	game._last_move_was_kick = false
	game._gravity_accum_ms = 0.0
	game._lock_timer_ms = null
	game._grounded = game.is_on_ground()


static func clear_board(game) -> void:
	for r in range(game.board.size()):
		var row := []
		for c in range(ENGINE.BOARD_WIDTH):
			row.append(null)
		game.board[r] = row


# Fill `row` in every column except the listed ones.
static func fill_row(game, row: int, except_cols: Array = []) -> void:
	for c in range(10):
		if not except_cols.has(c):
			game.board[row][c] = "X"


# Put specific piece types at the front of the upcoming queue.
static func force_next(game, types: Array) -> void:
	# JS: game.queue.unshift(...types) — insert each type at the front, in order.
	var q := []
	for t in types:
		q.push_front(t)
	queue_unshift(game.queue, q)


static func queue_unshift(queue: Array, items: Array) -> void:
	for i in range(items.size()):
		queue.push_front(items[i])
