# tests/test_audio.gd — Phase 4 audio verification (standalone; needs a live
# node tree for AudioStreamPlayer + tweens). Run:
#   godot --headless -s res://tests/test_audio.gd
# Checks on the first process frame (after AudioManager._ready): every committed
# WAV loads, music loop window is sane (samples, ~65 s), all 15 SFX play through
# the pool, unknown SFX is a safe no-op, mute path, start/stop cycle.
extends SceneTree

const AudioMgrScript := preload("res://scripts/audio_manager.gd")

var _fails := 0
var _done := false


func check(cond: bool, label: String) -> void:
	if cond:
		print("PASS ", label)
	else:
		_fails += 1
		printerr("FAIL ", label)


func _process(_delta: float) -> bool:
	if _done:
		return true
	_done = true

	var am := root.get_node_or_null("Audio") as Node
	if am == null: # standalone run — build the manager ourselves (first frame, so _ready fires)
		am = AudioMgrScript.new()
		am.name = "Audio"
		root.add_child(am)
	check(am != null, "audio manager in tree")
	if am == null:
		print("AUDIO RESULT: FAIL (no node)")
		quit(1)
		return true

	# 1. Music stream loaded with a sane loop window (samples, not bytes).
	check(am._music != null and am._music.stream != null, "music stream loaded")
	if am._music != null and am._music.stream is AudioStreamWAV:
		var w := am._music.stream as AudioStreamWAV
		var samples := w.data.size() / 2 # 16-bit mono
		check(w.loop_mode == AudioStreamWAV.LOOP_FORWARD, "loop mode FORWARD")
		check(w.loop_begin == 0 and w.loop_end == samples, "loop window = full stream (samples)")
		var secs := float(samples) / w.mix_rate
		check(absf(secs - 65.0) < 1.0, "music duration ~65 s (got %.2f)" % secs)

	# 2. Every SFX WAV loads through the pool path and plays.
	var names := ["lock", "clear1", "clear2", "clear3", "tetris", "tspin", "hold",
			"levelup", "gameover", "move", "rotate", "harddrop", "softdrop", "start", "pause"]
	for n in names:
		var p: AudioStreamPlayer = am.play_sfx(n) # explicit — am is untyped Node
		check(p != null, "sfx loads+plays: %s" % n)

	# 3. Unknown SFX is a safe no-op (web behavior).
	check(am.play_sfx("does_not_exist") == null, "unknown sfx -> null (no crash)")

	# 4. Mute path: muted play suppressed; unmute restores music volume.
	am.set_muted(true)
	check(am.is_muted(), "mute flag set")
	check(am.play_sfx("lock") == null, "muted sfx suppressed")
	am.set_muted(false)
	check(not am.is_muted() and am._music.volume_db > -10.0, "unmute restores music volume")

	# 5. Music start/stop cycle runs clean (headless: no real audio output).
	am.start_music()
	check(am._music.playing, "start_music plays")
	am.stop_music(0.0) # immediate stop — deterministic under headless
	check(not am._music.playing, "stop_music stops immediately")

	print("AUDIO RESULT: %s (%d failures)" % ["OK" if _fails == 0 else "FAIL", _fails])
	quit(1 if _fails > 0 else 0)
	return true
