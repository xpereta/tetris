# tests/ui_probe.gd — visual verification tool (Phase 3/5).
# Loads scenes/main.tscn, starts an autoplayer game at real speed for ~30 s,
# then saves a screenshot of the live viewport and quits. Run under Xvfb:
#   xvfb-run -a ~/.local/bin/godot --path . res://tests/ui_probe.tscn
extends Node

const MainScene := preload("res://scenes/main.tscn")
const AutoPlayerScript := preload("res://src/autoplayer.gd")

var main: Node2D
var ap: Variant = null
var _last_placed: Variant = null # dict of the most recently PLACED piece (value compare, like smoke)
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
	elif g.state == "playing":
		if ap == null:
			ap = AutoPlayerScript.new(g)
		if g.current != null and g.current != _last_placed:
			var cur = g.current # identity of the piece about to be placed
			ap.step() # place + hard drop (spawns the next piece)
			_last_placed = cur
	if _t >= 1.2 and not _shot1:
		_shot1 = true
		var img := get_viewport().get_texture().get_image()
		img.save_png("/tmp/tetris_ui_mid.png")
		print("UI_SHOT MID: score=%d level=%d state=%s" % [g.score, g.level, g.state])
	if _t >= 30.0:
		var img := get_viewport().get_texture().get_image()
		img.save_png("/tmp/tetris_ui.png")
		print("UI_SHOT OK: score=%d level=%d lines=%d" % [g.score, g.level, g.lines])
		get_tree().quit(0)
