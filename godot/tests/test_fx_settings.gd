# tests/test_fx_settings.gd — v3 particle system + §2 settings parity checks.
# Standalone (needs a live node tree): godot --headless -s res://tests/test_fx_settings.gd
extends SceneTree

const ParticlesFxScript := preload("res://scripts/particles_fx.gd")
const SettingsMenuScript := preload("res://scripts/settings_menu.gd")

var _pass := 0
var _fail := 0


func check(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		printerr("FAIL: " + label)


func _process(_d: float) -> bool:
	var ps := ParticlesFxScript.new() as Node2D
	root.add_child(ps)

	# --- spawn_burst: n particles, all alive after one small update ---
	ps.spawn_burst(100.0, 100.0, Color.WHITE, 8)
	check(ps.count() == 8, "burst spawns 8")
	ps.update(16.0)
	check(ps.count() == 8, "burst alive after 16 ms")

	# --- spawn_trail: exactly one dot, straight down (vx=0), no gravity ---
	var before: int = ps.count()
	ps.spawn_trail(50.0, 20.0, 300.0)
	check(ps.count() == before + 1, "trail spawns exactly 1")
	# find the trail dot (grav=false) and verify it falls straight at its speed
	var trail = null
	for p in ps._parts:
		if not p["grav"]:
			trail = p
	check(trail != null, "trail dot present")
	if trail != null:
		ps.update(100.0) # 0.1 s at 300 px/s → +30 px straight down
		var moved = null
		for p in ps._parts:
			if not p["grav"]:
				moved = p
		check(absf(float(moved["x"]) - 50.0) < 0.01, "trail x unchanged (no spread)")
		check(absf(float(moved["y"]) - (20.0 + 30.0)) < 0.5, "trail fell at piece speed")

	# --- kill_trails removes ONLY trail dots; bursts survive ---
	ps.kill_trails()
	var survivors := 0
	for p in ps._parts:
		if p["grav"]:
			survivors += 1
	check(survivors == 8, "kill_trails keeps all 8 burst sparks")

	# --- clamp_trails_above: stragglers snap just above the line (v3.1.1) ---
	ps.spawn_trail(0.0, 500.0, 0.0) # dot far below the piece's top edge
	ps.clamp_trails_above(420.0)
	var clamped = null
	for p in ps._parts:
		if not p["grav"]:
			clamped = p
	check(clamped != null and float(clamped["y"]) <= 418.0, "trail snapped above the line")

	# --- hard cap 600: spawning beyond drops the oldest ---
	for i in range(700):
		ps.spawn_burst(0.0, 0.0, Color.WHITE, 1)
	check(ps.count() == 600, "hard cap at 600")

	# --- update culls dead particles (life 400–800 ms → all gone by 900 ms) ---
	ps.update(2000.0)
	check(ps.count() == 0, "all culled after their lifetimes")

	# --- spawn_clear_row: count override + width spread ---
	ps.spawn_clear_row(140.0, 10, 28, [], 30)
	check(ps.count() == 30, "clear row spawns requested count (30)")
	var xs_ok := true
	for p in ps._parts:
		if float(p["x"]) < -5.0 or float(p["x"]) > 10 * 28 + 5.0:
			xs_ok = false
	check(xs_ok, "clear row spread within board width")

	root.remove_child(ps)
	ps.queue_free()

	# --- settings menu: persistence round-trip (web §2 shape) ---
	var sm := SettingsMenuScript.new() as Control
	root.add_child(sm)
	sm.settings["particles"] = false
	sm.settings["trail"] = true
	sm.settings["intensity"] = 2
	sm.save_settings()

	var sm2 := SettingsMenuScript.new() as Control
	root.add_child(sm2) # fresh instance must load the persisted values
	check(bool(sm2.settings["particles"]) == false, "settings: particles=false persisted")
	check(bool(sm2.settings["trail"]) == true, "settings: trail=true persisted")
	check(int(sm2.settings["intensity"]) == 2, "settings: intensity=2 persisted")

	# corrupt file → defaults (web §2 fallback)
	var f := FileAccess.open(SettingsMenuScript.SETTINGS_PATH, FileAccess.WRITE)
	f.store_string("{not json!!")
	f.close()
	var sm3 := SettingsMenuScript.new() as Control
	root.add_child(sm3)
	check(bool(sm3.settings["particles"]) == true and int(sm3.settings["intensity"]) == 1, "corrupt settings → defaults")

	# restore sane defaults for later runs
	sm3.save_settings()
	root.remove_child(sm); sm.queue_free()
	root.remove_child(sm2); sm2.queue_free()
	root.remove_child(sm3); sm3.queue_free()

	print("FX/SETTINGS: %d passed, %d failed" % [_pass, _fail])
	if _fail == 0:
		print("RESULT: OK")
	else:
		print("RESULT: FAIL")
	quit(_fail)
	return true
