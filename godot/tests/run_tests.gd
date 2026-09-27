# tests/run_tests.gd — headless test runner: godot --headless -s res://tests/run_tests.gd
# Runs every test_*.gd module (each exposes static func run()), prints per-test
# PASS/FAIL lines and a final summary, exits non-zero on any failure.

extends SceneTree


const TK := preload("res://tests/tk.gd")

const MODULES := [
	preload("res://tests/test_rng.gd"),
	preload("res://tests/test_srs.gd"),
	preload("res://tests/test_bag.gd"),
	preload("res://tests/test_gameover.gd"),
	preload("res://tests/test_ghost.gd"),
	preload("res://tests/test_gravity.gd"),
	preload("res://tests/test_hold.gd"),
	preload("res://tests/test_rotation.gd"),
	preload("res://tests/test_scoring.gd"),
	preload("res://tests/test_tspin.gd"),
	preload("res://tests/test_autoplayer.gd"),
]


func _initialize() -> void:
	print("== Godot Tetris port — test run ==")
	for m in MODULES:
		m.run()

	var total := TK.passed + TK.failed
	print("")
	print("SUMMARY: %d passed, %d failed, %d total" % [TK.passed, TK.failed, total])
	if TK.failed > 0:
		printerr("RESULT: FAIL")
	else:
		print("RESULT: OK")
	quit(TK.failed)
