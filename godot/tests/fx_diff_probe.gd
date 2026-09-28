# tests/fx_diff_probe.gd — proves particles are actually DRAWN: plays an
# autoplayer game; at t≈0.9 s (particles alive) captures frame A, then culls
# ALL particles and captures frame B ~2 frames later. Same board in both
# frames → any pixel difference is particle FX. Run under Xvfb:
#   xvfb-run -a ~/.local/bin/godot --path . res://tests/fx_diff_probe.tscn
extends Node

const MainScene := preload("res://scenes/main.tscn")
const AutoPlayerScript := preload("res://src/autoplayer.gd")

var main: Node2D
var ap: Variant = null
var _last_placed: Variant = null
var _t := 0.0
var _phase := 0 # 0=playing, 1=captured A (particles alive), 2=captured B (culled)


func _ready() -> void:
	main = MainScene.instantiate() as Node2D
	add_child(main)


func _process(delta: float) -> void:
	_t += delta
	var g: Variant = main.game
	if g.state == "idle":
		g.start()
	elif g.state == "playing" and not bool(main.settings_menu.visible):
		if ap == null:
			ap = AutoPlayerScript.new(g)
		if g.current != null and g.current != _last_placed:
			var cur = g.current
			ap.step()
			_last_placed = cur

	if _phase == 0 and _t >= 0.9:
		var img := get_viewport().get_texture().get_image()
		img.save_png("/tmp/fx_on.png")
		print("FX_DIFF frame A (particles alive): count=%d" % main.particles_fx.count())
		main.particles_fx.update(1e9) # cull every live particle (age > life)
		_phase = 1

	elif _phase == 1:
		# wait one more rendered frame so the empty state is what's on screen,
		# then capture B. Board unchanged: level-1 gravity (~800 ms) can't tick
		# within ~32 ms and autoplayer only acts on a new piece.
		var img := get_viewport().get_texture().get_image()
		img.save_png("/tmp/fx_off.png")
		print("FX_DIFF frame B (particles culled): count=%d" % main.particles_fx.count())
		_diff_and_quit()


# Pixel-diff the board region between the two frames using Godot as sampler.
func _diff_and_quit() -> void:
	var on_img := Image.new()
	if on_img.load_png_from_buffer(FileAccess.get_file_as_bytes("/tmp/fx_on.png")) != OK:
		print("FX_DIFF FAIL: could not load fx_on.png")
		get_tree().quit(1)
		return
	var off_img := Image.new()
	if off_img.load_png_from_buffer(FileAccess.get_file_as_bytes("/tmp/fx_off.png")) != OK:
		print("FX_DIFF FAIL: could not load fx_off.png")
		get_tree().quit(1)
		return
	# board region in viewport coords: BOARD_POS (16,40), 280x560 px.
	var diff := 0
	for y in range(40, 40 + 560):
		for x in range(16, 16 + 280):
			var a: Color = on_img.get_pixel(x, y)
			var b: Color = off_img.get_pixel(x, y)
			if absf(a.r - b.r) > 0.05 or absf(a.g - b.g) > 0.05 or absf(a.b - b.b) > 0.05:
				diff += 1
	print("FX_DIFF pixels differing in board region: %d" % diff)
	if diff > 200:
		print("RESULT: OK — particles are being drawn (frame A has extra FX pixels)")
		get_tree().quit(0)
	else:
		print("RESULT: FAIL — no visible particle difference")
		get_tree().quit(1)
