# parity/trace_godot.gd — Godot side of the Phase-2 parity gate.
# Drives src/engine.gd + src/autoplayer.gd with the EXACT same deterministic
# protocol as trace_js.mjs (2 gravity ticks per piece, then autoplayer step)
# and must reproduce res://parity/reference_traces.json BYTE-FOR-BYTE.
#
# Run:  ~/.local/bin/godot --headless --path <godot project dir> -s res://parity/trace_godot.gd

extends SceneTree

const SEEDS := 50
const TICKS_PER_PIECE := 2
const OUT_PATH := "res://parity/traces_godot.json"

var _events: Array = []


func _on_event(ev: Dictionary) -> void:
	_events.append(ev)


func _serialize_board(board: Array) -> String:
	var rows: PackedStringArray = []
	for row in board:
		var s := ""
		for c in row:
			if c == null or c == "":
				s += "."
			else:
				s += str(c)
		rows.append(s)
	return "|".join(rows)


func _run_game(seed: int) -> Dictionary:
	_events.clear()
	var EngineScript := load("res://src/engine.gd")
	var AutoPlayerScript := load("res://src/autoplayer.gd")

	var game = EngineScript.new({"seed": seed})
	game.event_emitted.connect(_on_event)
	var ap = AutoPlayerScript.new(game)
	game.start()

	while game.state == "playing" and game.current != null:
		for i in range(TICKS_PER_PIECE):
			game.tick()
			if game.state != "playing" or game.current == null:
				break
		if game.state != "playing" or game.current == null:
			break
		ap.step()

	var lock_seq: PackedStringArray = []
	var clears: PackedStringArray = []
	for ev in _events:
		if ev.get("type") == "lock":
			lock_seq.append("%s@%d,%d,r%d" % [ev["piece"], int(ev["x"]), int(ev["y"]), int(ev["rot"])])
		elif ev.get("type") == "clear":
			var tag := ""
			if ev.get("tSpin", false):
				tag += "T"
			if ev.get("miniTSpin", false):
				tag += "m"
			var b2b_tag := ",b2b" if ev.get("b2b", false) else ""
			clears.append(
				"c%d%s+%d(combo%d%s)" % [int(ev["lines"]), tag, int(ev["points"]), int(ev["combo"]), b2b_tag]
			)

	return {
		"seed": seed,
		"state": game.state,
		"score": int(game.score),
		"level": int(game.level),
		"lines": int(game.lines),
		"locks": lock_seq.size(),
		"lockSeq": lock_seq,
		"clears": clears,
		"finalBoard": _serialize_board(game.board),
	}


func _initialize() -> void:
	var out := {"protocol": "ticks=2/piece, autoplayer=harddrop", "seeds": []}
	for s in range(1, SEEDS + 1):
		var r := _run_game(s)
		if r["state"] != "over":
			push_error("seed %d: expected game over, got state=%s" % [s, str(r["state"])])
			quit(1)
			return
		out["seeds"].append(r)

	var f := FileAccess.open(OUT_PATH, FileAccess.WRITE)
	if f == null:
		push_error("cannot open %s for writing (err=%d)" % [OUT_PATH, FileAccess.get_open_error()])
		quit(1)
		return
	f.store_string(JSON.stringify(out))
	f.close()

	var total_locks := 0
	for r in out["seeds"]:
		total_locks += int(r["locks"])
	print("traced %d games -> %s; total locks: %d" % [SEEDS, OUT_PATH, total_locks])
	quit(0)
