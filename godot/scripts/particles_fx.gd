# scripts/particles_fx.gd — v3 particle system, faithful port of js/particles.js.
# Pure visual layer: NEVER touches engine timing or input (CONTRACT-V3 §1).
# Local coords = board pixel space ((0,0) = top-left of the visible 10x20 board);
# main.gd positions this node at BOARD_POS so local == web board pixels.
# Physics: position + velocity (px/s), gravity ~600 px/s² for bursts/clears;
# trail dots fall straight with no horizontal spread and NO gravity. Lifetime
# 400–800 ms, alpha fades linearly to 0, size shrinks slightly over life.
# Hard cap: 600 particles (drop oldest on overflow).
extends Node2D

const CAP := 600 # hard particle cap — spawning beyond it drops the oldest
const GRAVITY := 600.0 # px/s²
# Fixed celebratory palette for line clears (§1) — removed-cell colors are not
# recoverable (the engine removes rows before emitting 'clear').
const CLEAR_PALETTE: Array[Color] = [Color("#ffffff"), Color("#ffd75e"), Color("#6ee7ff")]

var _parts: Array = [] # live particles, oldest first (order kept for cap drops)


func count() -> int:
	return _parts.size()


# Reserve room for n new particles, dropping the oldest first when over CAP.
func _make_room(n: int) -> void:
	var excess := _parts.size() + n - CAP
	if excess > 0:
		_parts.resize(_parts.size() - mini(excess, _parts.size()))


# Lock: radial burst at pixel (x,y). ~30% of the sparks are white.
func spawn_burst(x: float, y: float, color: Color, n := 8) -> void:
	if n <= 0:
		return
	_make_room(n)
	for i in range(n):
		var a := randf() * TAU
		var sp := randf_range(80.0, 300.0) # px/s in a random direction
		var p := {
			"x": x, "y": y,
			"vx": cos(a) * sp, "vy": sin(a) * sp,
			"size": randf_range(2.0, 4.0),
			"alpha": randf_range(0.75, 1.0),
			"life": randf_range(400.0, 800.0), # ms
			"age": 0.0,
			"color": Color.WHITE if randf() < 0.3 else color,
			"grav": true,
		}
		_parts.append(p)


# Falling: exactly ONE dot below the piece (alpha ≤ 0.45, ~380 ms).
# fall_speed_px_per_sec should match the piece's CURRENT fall speed so the dot
# stays glued just below it — never running ahead of or overlapping the piece.
func spawn_trail(x: float, y: float, fall_speed_px_per_sec: float) -> void:
	var p := {
		"x": x, "y": y,
		"vx": 0.0, # straight down — no spread
		"vy": maxf(0.0, fall_speed_px_per_sec), # match the piece's speed (v3.1.1)
		"size": randf_range(2.0, 3.0),
		"alpha": randf_range(0.3, 0.45),
		"life": randf_range(320.0, 420.0), # ~380 ms
		"age": 0.0,
		"color": Color.WHITE,
		"grav": false, # constant velocity — falls straight down
	}
	_make_room(1)
	_parts.append(p)


# Line clear: horizontal spray across a row (~widthCells×3 particles).
# colors (optional) tints the sparks with the actual cleared-cell colors;
# otherwise the fixed celebratory palette is used. count overrides n.
func spawn_clear_row(y: float, width_cells: int, cell_px: int, colors: Array = [], count := 0) -> void:
	var n := maxi(1, count if count > 0 else roundi(width_cells * 3))
	if n <= 0:
		return
	_make_room(n)
	var w := maxf(1.0, float(width_cells) * cell_px) # full board width in px
	for i in range(n):
		var t := 0.5 if n == 1 else float(i) / float(n - 1)
		var dir := -1.0 if randf() < 0.5 else 1.0
		var col: Color
		if not colors.is_empty():
			# ~25% white sparks over the real cleared-cell colors (v3.1).
			col = Color.WHITE if randf() < 0.25 else colors[randi() % colors.size()]
		else:
			col = CLEAR_PALETTE[randi() % CLEAR_PALETTE.size()]
		var p := {
			"x": t * w + randf_range(-cell_px * 0.2, cell_px * 0.2), # spread across full width
			"y": y + randf_range(-cell_px * 0.25, cell_px * 0.25),
			"vx": dir * randf_range(40.0, 200.0), # mostly horizontal
			"vy": -randf_range(30.0, 120.0), # upward kick (gravity pulls it back down)
			"size": randf_range(2.0, 4.0),
			"alpha": randf_range(0.75, 1.0),
			"life": randf_range(400.0, 800.0),
			"age": 0.0,
			"color": col,
			"grav": true, # recycled objects may carry grav=false from a trail dot
		}
		_parts.append(p)


# Remove all trail dots (grav=false) — called when a piece locks or is held,
# so stale dots can't drift into the NEXT piece's body. Bursts/clears survive.
func kill_trails() -> void:
	var w := 0
	for i in range(_parts.size()):
		if not _parts[i]["grav"]:
			continue # drop trail dot
		_parts[w] = _parts[i]
		w += 1
	_parts.resize(w)


# Hard invariant for the falling trail (v3.1.1): no trail dot may sit below yPx —
# that would be IN FRONT of a downward-moving piece. Free physics + quantized
# gravity can overshoot at high levels, so stragglers snap back just above the line.
func clamp_trails_above(y_px: float) -> void:
	var limit := y_px - 2.0 # a hair above the piece's top edge (y grows downward)
	for i in range(_parts.size()):
		if not _parts[i]["grav"] and _parts[i]["y"] > limit:
			_parts[i]["y"] = limit


# Advance physics and cull dead particles. dt in ms. O(count), no allocation.
func update(dt_ms: float) -> void:
	if dt_ms <= 0.0 or _parts.is_empty():
		return
	var dt := dt_ms / 1000.0
	var w := 0 # in-place compaction keeps oldest-first order for cap drops
	for i in range(_parts.size()):
		var p = _parts[i]
		p["age"] += dt_ms
		if p["age"] >= p["life"]:
			continue # recycle (drop) the object
		if p["grav"]:
			p["vy"] += GRAVITY * dt
		p["x"] += p["vx"] * dt
		p["y"] += p["vy"] * dt
		_parts[w] = p
		w += 1
	_parts.resize(w)


# Render all particles. Only arc+fill — no shadows/blur/filters (mobile perf).
func _process(_delta: float) -> void:
	if not _parts.is_empty():
		queue_redraw() # Node2D._draw only re-runs when marked dirty (like board_view)


func _draw() -> void:
	for i in range(_parts.size()):
		var p = _parts[i]
		var t := float(p["age"]) / float(p["life"]) # 0 → 1 over life
		var a := float(p["alpha"]) * (1.0 - t) # linear fade to 0
		var col: Color = p["color"]
		col.a = a
		var s := maxf(0.5, float(p["size"]) * (1.0 - 0.4 * t)) # shrink slightly over life
		draw_circle(Vector2(float(p["x"]), float(p["y"])), s, col)
