# tests/fx_probe.gd — visual verification of v3 particles + §2 settings menu.
# Loads main.tscn, plays an autoplayer game briefly (lock bursts + trail dots),
# then opens the settings menu and captures both states. Run under Xvfb:
#   xvfb-run -a ~/.local/bin/godot --path . res://tests/fx_probe.tscn
extends Node

const MainScene := preload("res://scenes/main.tscn")
const AutoPlayerScript := preload("res://src/autoplayer.gd")

var main: Node2D
var ap: Variant = null
var _last_placed: Variant = null
var _t := 0.0
var _shot1 := false


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
			ap.step() # place + hard drop (lock bursts fire on the 'lock' event)
			_last_placed = cur

	# Shot 1: mid-game — particles should be visible around recent locks.
	if _t >= 0.9 and not _shot1:
		_shot1 = true
		var img := get_viewport().get_texture().get_image()
		img.save_png("/tmp/tetris_fx_mid.png")
		print("FX_SHOT MID: score=%d state=%s particles_in_tree=%d" % [g.score, g.state, main.particles_fx.count()])

	# Shot 2: settings menu open (game paused by the menu).
	if _t >= 1.6 and not bool(main.settings_menu.visible):
		main.toggle_settings() # S-key path — pauses the game + shows the overlay
	if _t >= 2.0:
		var img := get_viewport().get_texture().get_image()
		img.save_png("/tmp/tetris_fx_settings.png")
		print("FX_SHOT SETTINGS: menu_visible=%s state=%s" % [str(bool(main.settings_menu.visible)), g.state])
		get_tree().quit(0)
