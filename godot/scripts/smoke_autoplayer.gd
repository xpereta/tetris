# scripts/smoke_autoplayer.gd — headless smoke test. Run either way:
#   godot --headless --path . -s res://scripts/smoke_autoplayer.gd
#   godot --headless --path . res://tests/smoke_autoplayer.tscn
# Creates Game (seed 7) + AutoPlayer, plays to game over ticking at fixed 16ms
# steps (ap.step() once per piece), then saves a PNG of the final board and
# prints "SMOKE OK: <score> pts, <level> level". Extends SceneTree so it can be
# run with -s; builds a board_view inside a SubViewport for the screenshot when
# a real renderer is available (Xvfb), else falls back to CPU rendering.
extends SceneTree

const GameScript := preload("res://src/engine.gd")
const AutoPlayerScript := preload("res://src/autoplayer.gd")
const BoardViewScript := preload("res://scripts/board_view.gd")

const STEP_MS := 16.0
const MAX_ITERS := 200000
const OUT_PNG := "/tmp/tetris_godot_smoke.png"

# Bevel palette (mirrors board_view / web COLORS).
const COLORS := {
	"I": Color("#3fd8f0"), "O": Color("#ffd54a"), "T": Color("#b06ef2"),
	"S": Color("#59d97e"), "Z": Color("#ff5c5c"), "J": Color("#5b8cff"), "L": Color("#ffa14e"),
}


func _initialize() -> void:
	var g: Variant = play_game()
	if g == null:
		push_error("SMOKE FAIL: game did not reach 'over' within %d iterations" % MAX_ITERS)
		quit(1)
		return
	var img: Image = await capture_final_board(g)
	if img == null or img.is_empty():
		push_error("SMOKE FAIL: could not render final board image")
		quit(1)
		return
	img.save_png(OUT_PNG)
	print("SMOKE OK: %d pts, %d level" % [g.score, g.level])
	quit(0)


# Synchronous: play a full seeded game to game over. Returns the Game (state
# "over") or null if the iteration budget was exceeded.
static func play_game() -> Variant:
	var g = GameScript.new({"seed": 7})
	var ap = AutoPlayerScript.new(g)
	g.start()

	# Fixed 16ms time steps; one ap.step() per piece (dict identity changes on spawn).
	# acc is in MILLISECONDS; gravity_ms() returns ms — keep the units matched.
	var acc := 0.0
	var iters := 0
	var last_current: Variant = null # dict of the most recently PLACED piece
	while g.state != "over" and iters < MAX_ITERS:
		if g.current != null and g.current != last_current:
			var cur = g.current # identity of the piece about to be placed
			ap.step() # place + hard drop (spawns the next piece)
			last_current = cur
		acc += STEP_MS
		while acc >= g.gravity_ms() and iters < MAX_ITERS:
			g.tick()
			acc -= g.gravity_ms()
		iters += 1
	if g.state != "over":
		return null
	return g


# Try the SubViewport texture path (real renderer / Xvfb); under --headless the
# dummy renderer yields no usable texture (verified: get_image() errors), so go
# straight to CPU rendering there.
func capture_final_board(g: Variant) -> Image:
	if DisplayServer.get_name() == "headless":
		return render_board_manual(g)
	var vp := SubViewport.new()
	vp.size = Vector2i(300, 580)
	root.add_child(vp)
	var bv = BoardViewScript.new() as Node2D
	bv.game = g
	bv.position = Vector2(10, 10)
	vp.add_child(bv)
	for i in range(4):
		await process_frame
	var img: Image = null
	if vp.get_texture():
		img = vp.get_texture().get_image()
	vp.queue_free()
	if img == null or img.is_empty():
		img = render_board_manual(g)
	return img


# CPU fallback (also used by the .tscn entry point): draw the visible 10x20
# board (rows 20..39) with the web bevel recipe directly into an Image.
# Cell size 28 -> 280x560 px.
static func render_board_manual(g: Variant) -> Image:
	const CELL := 28
	const COLS := 10
	const ROWS := 20
	var img := Image.create_empty(COLS * CELL, ROWS * CELL, false, Image.FORMAT_RGBA8)
	_fill_rect(img, 0, 0, COLS * CELL, ROWS * CELL, Color("#1a1d27"), 1.0)
	for vr in range(ROWS):
		var row: Array = g.board[20 + vr]
		for c in range(COLS):
			var t = row[c]
			if t != null and t != "":
				_draw_cell_img(img, c * CELL, vr * CELL, CELL, COLORS[str(t)])
	return img


static func _draw_cell_img(img: Image, px: int, py: int, cell: int, color: Color) -> void:
	var inset := maxi(1, int(floor(cell * 0.06)))
	_fill_rect(img, px + inset, py + inset, cell - inset * 2, cell - inset * 2, color, 1.0)
	var strip := maxi(1, int(floor(cell * 0.16)))
	_fill_rect(img, px + inset, py + inset, cell - inset * 2, strip, Color(1, 1, 1), 0.28)
	_fill_rect(img, px + inset, py + cell - inset - strip, cell - inset * 2, strip, Color(0, 0, 0), 0.28)


static func _fill_rect(img: Image, x: int, y: int, w: int, h: int, color: Color, alpha: float) -> void:
	var W := img.get_width()
	var H := img.get_height()
	for j in range(h):
		var yy := y + j
		if yy < 0 or yy >= H:
			continue
		for i in range(w):
			var xx := x + i
			if xx < 0 or xx >= W:
				continue
			img.set_pixel(xx, yy, img.get_pixel(xx, yy).lerp(color, alpha))
