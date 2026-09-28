# scripts/audio_manager.gd — Phase 4: plays the offline-rendered WAVs in
# assets/audio/ (rendered by tools/render_audio.py from the same synthesis
# recipes as js/audio.js). Mirrors web behavior: one looping music track,
# named SFX one-shots, master mute. Music loops seamlessly at the wrap via
# AudioStreamWAV loop mode set at load time.
class_name AudioManager
extends Node

const MUSIC_PATH := "res://assets/audio/music_loop.wav"

var _music: AudioStreamPlayer = null
var _sfx: Dictionary = {} # name -> AudioStreamPlayer (pooled, lazy-loaded)
var _muted := false
# softDrop throttle — web plays at most one per 50 ms (audio.js §softDrop).
var _last_soft_drop_at := -1.0


func _ready() -> void:
	_music = AudioStreamPlayer.new()
	add_child(_music)
	var res := load(MUSIC_PATH) as AudioStreamWAV
	if res == null:
		push_error("audio_manager: failed to load " + MUSIC_PATH)
		return
	res.loop_mode = AudioStreamWAV.LOOP_FORWARD # seamless 65 s wrap (Phase 4 gate)
	# loop positions are in SAMPLES; data is interleaved bytes (16-bit mono here).
	var samples := res.data.size() / 2
	res.loop_begin = 0
	res.loop_end = samples
	_music.stream = res


func start_music() -> void:
	if _music != null and not is_muted():
		_music.play()


# Web stopMusic(): quick fade-out (setTargetAtTime tau=0.02). fade_s<=0 stops
# immediately (used by tests / hard cuts).
func stop_music(fade_s: float = 0.05) -> void:
	if _music == null or not _music.playing:
		return
	if fade_s <= 0.0:
		_music.stop()
		return
	var tw := create_tween()
	tw.tween_property(_music, "volume_db", -80.0, fade_s)
	tw.tween_callback(_music.stop)


# name = web SFX id ('lock','clear1'..'clear3','tetris','tspin','hold',
# 'levelup','gameover','move','rotate','harddrop','softdrop','start','pause').
# Returns the pooled player, or null when muted/unknown (tests rely on this).
func play_sfx(name: String) -> AudioStreamPlayer:
	if is_muted():
		return null
	if name == "softdrop":
		var now := Time.get_ticks_msec() / 1000.0
		if now - _last_soft_drop_at < 0.05:
			return null
		_last_soft_drop_at = now
	var p: AudioStreamPlayer = null
	if _sfx.has(name):
		p = _sfx[name]
	else:
		var path := "res://assets/audio/sfx_%s.wav" % name.to_lower()
		if not FileAccess.file_exists(path):
			return null # unknown sfx — safe no-op, like the web version (no load error spam)
		var res := load(path) as AudioStreamWAV
		if res == null:
			return null # unknown sfx — safe no-op, like the web version
		p = AudioStreamPlayer.new()
		add_child(p)
		p.stream = res
		_sfx[name] = p
	p.play()
	return p


func set_muted(m: bool) -> void:
	_muted = m
	if _music != null:
		_music.volume_db = -80.0 if m else 0.0


func is_muted() -> bool:
	return _muted
