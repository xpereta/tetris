# tests/smoke_scene_entry.gd — Node entry point for tests/smoke_autoplayer.tscn.
# Same contract as scripts/smoke_autoplayer.gd (SceneTree/-s mode): plays a full
# seeded game to game over, saves the final board PNG, prints SMOKE OK, quits.
extends Node

const Smoke := preload("res://scripts/smoke_autoplayer.gd")


func _ready() -> void:
	var g: Variant = Smoke.play_game()
	if g == null:
		push_error("SMOKE FAIL: game did not reach 'over' within the iteration budget")
		get_tree().quit(1)
		return
	var img := Smoke.render_board_manual(g) # CPU render; works headless (no renderer needed)
	img.save_png(Smoke.OUT_PNG)
	print("SMOKE OK: %d pts, %d level" % [g.score, g.level])
	get_tree().quit(0)
