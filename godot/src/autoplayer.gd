# src/autoplayer.gd — simple heuristic AI that drives a Game instance using ONLY
# its public API (cells_of/collides/move_left/move_right/rotate_cw/rotate_ccw/hard_drop).
# Port of js/autoplayer.js.
#
# Heuristic per CONTRACT.md: for the current piece, evaluate every candidate
# placement (x position x rotation state) by
#   score = -(holes*100 + height*20 + aggregateHeight*5 - clears*800)
# pick the best, execute moves/rotations to reach it, then hard_drop().

class_name AutoPlayer extends RefCounted


const ENGINE := preload("res://src/engine.gd")

const W_HOLES := 100
const W_HEIGHT := 20
const W_AGGREGATE := 5
const W_CLEARS := 800

var game: Variant = null # a Game instance (duck-typed on its public API)


func _init(g: Variant) -> void:
	game = g


# One decision: place the current piece (rotate/move to target, then hard drop).
func step() -> void:
	var g := game
	if g.state != "playing" or g.current == null:
		return
	var piece: Variant = g.current

	var best := evaluate(piece["type"])
	if best.is_empty():
		# No legal candidate found (shouldn't happen): just drop where we are.
		g.hard_drop()
		return

	# Rotate toward the target rotation state (bounded loop; failed rotations
	# simply leave us in place and we proceed with what we have).
	var guard := 0
	while int(piece["rot"]) != int(best["rot"]) and guard < 4:
		guard += 1
		var diff := (int(best["rot"]) - int(piece["rot"]) + 4) % 4
		if diff == 3:
			g.rotate_ccw()
		else:
			g.rotate_cw() # diff 1 or 2: one CW step, re-evaluate next iteration

	# Slide horizontally toward the target column.
	guard = 0
	while int(piece["x"]) < int(best["x"]) and guard <= ENGINE.BOARD_WIDTH + 2:
		if not g.move_right():
			break
		guard += 1
	guard = 0
	while int(piece["x"]) > int(best["x"]) and guard <= ENGINE.BOARD_WIDTH + 2:
		if not g.move_left():
			break
		guard += 1

	g.hard_drop()


# Evaluate all candidate placements for `type`; return {rot, x} of the best ({} if none).
func evaluate(type: String) -> Dictionary:
	var g := game
	var best := {}
	var best_score := -INF

	for rot in range(4):
		for x in range(-2, ENGINE.BOARD_WIDTH + 2): # JS: for (let x = -2; x <= BOARD_WIDTH + 1; x++)
			# Find the resting row: fall from above until the next step collides.
			var gy := -6 # safely above the board (negative rows are open space)
			while not g.collides(g.cells_of(type, x, gy + 1, rot)):
				gy += 1

			var cells: Variant = g.cells_of(type, x, gy, rot)

			# Validity: within horizontal bounds and at least partially on the board.
			var valid := true
			var max_row := -INF
			for cell in cells:
				var cx := int(cell[0])
				var cy := int(cell[1])
				if cx < 0 or cx >= ENGINE.BOARD_WIDTH or cy > ENGINE.BOARD_HEIGHT - 1:
					valid = false
					break
				if float(cy) > max_row:
					max_row = float(cy)
			if not valid or max_row < 0.0:
				continue # degenerate: rests entirely above row 0

			var metrics := board_metrics(cells, type)
			var score := -(
				float(W_HOLES * int(metrics["holes"]))
				+ float(W_HEIGHT * int(metrics["height"]))
				+ float(W_AGGREGATE * int(metrics["aggregateHeight"]))
				- float(W_CLEARS * int(metrics["clears"]))
			)
			if score > best_score:
				best_score = score
				best = {"rot": rot, "x": x}

	return best


# Simulate placing `cells` on a copy of the board; compute heuristic metrics.
func board_metrics(cells: Array, type: String) -> Dictionary:
	var g := game
	# Deep-copy the board (rows are Arrays).
	var b := []
	for row in g.board:
		b.append(row.duplicate())
	for cell in cells:
		var cx := int(cell[0])
		var cy := int(cell[1])
		if cy >= 0 and cy < ENGINE.BOARD_HEIGHT:
			b[cy][cx] = type

	# Remove full rows (bottom-up so indices stay valid).
	var clears := 0
	for r in range(ENGINE.BOARD_HEIGHT - 1, -1, -1):
		var full := true
		for c in range(ENGINE.BOARD_WIDTH):
			if b[r][c] == null:
				full = false
				break
		if full:
			b.remove_at(r)
			var empty_row := []
			for i in range(ENGINE.BOARD_WIDTH):
				empty_row.append(null)
			b.push_front(empty_row)
			clears += 1

	var holes := 0
	var aggregate_height := 0
	var height := 0 # max column height (distance from floor to topmost block)
	for c in range(ENGINE.BOARD_WIDTH):
		var seen := false
		var top_row := -1
		for r in range(ENGINE.BOARD_HEIGHT):
			if b[r][c] != null:
				if not seen:
					seen = true
					top_row = r
			elif seen:
				holes += 1 # empty cell with a block above it in the same column
		var h := 0 if top_row == -1 else ENGINE.BOARD_HEIGHT - top_row
		aggregate_height += h
		if h > height:
			height = h

	return {"holes": holes, "height": height, "aggregateHeight": aggregate_height, "clears": clears}
