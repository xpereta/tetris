# scripts/settings_menu.gd — v3 §2 settings overlay (web parity): particles +
# trail toggles, Low/Med/High intensity (spawn multipliers 0.5/1/2), persisted
# to user://tetris_settings.json (same shape as the web localStorage JSON).
# S opens/closes; Esc closes. While open, main.gd pauses the game and the input
# controller swallows all other keys — exactly like the web menu (§2).
extends Control

signal setting_changed(key: String, value: Variant) # main re-applies live FX state

const SETTINGS_PATH := "user://tetris_settings.json"
const INTENSITY_STEPS := [0.5, 1.0, 2.0] # Low / Med / High (§2 table)
const INTENSITY_LABELS := ["Low", "Med", "High"]

var settings: Dictionary = {"particles": true, "trail": true, "intensity": 1} # defaults (web §2)

var _rows: Array = [] # [key, label] for the two toggles
var _intensity_btns: Array[Button] = []


func load_settings() -> void:
	if not FileAccess.file_exists(SETTINGS_PATH):
		return
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY: # corrupt → defaults (web §2 fallback)
		return
	if "particles" in parsed:
		settings["particles"] = bool(parsed["particles"])
	if "trail" in parsed:
		settings["trail"] = bool(parsed["trail"])
	if "intensity" in parsed:
		var i := int(parsed["intensity"])
		settings["intensity"] = clampi(i, 0, 2)


func save_settings() -> void:
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(settings))
	f.close()


func _ready() -> void:
	load_settings()
	set_anchors_preset(PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP # backdrop swallows clicks (web §2)

	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.6)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var panel := PanelContainer.new()
	panel.position = Vector2(140, 170)
	panel.size = Vector2(200, 300)
	add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "SETTINGS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color("#ffd54a"))
	vbox.add_child(title)

	for key in ["particles", "trail"]:
		var row := HBoxContainer.new()
		var lbl := Label.new()
		lbl.text = ("Particles" if key == "particles" else "Trail") + ": "
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(lbl)
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(64, 0)
		btn.pressed.connect(_on_toggle_pressed.bind(key))
		row.add_child(btn)
		vbox.add_child(row)
		_rows.append([key, lbl, btn])

	var int_row := HBoxContainer.new()
	int_row.add_theme_constant_override("separation", 6)
	var int_lbl := Label.new()
	int_lbl.text = "Intensity: "
	int_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	int_row.add_child(int_lbl)
	for i in range(3):
		var b := Button.new()
		b.text = INTENSITY_LABELS[i]
		b.pressed.connect(_on_intensity_pressed.bind(i))
		int_row.add_child(b)
		_intensity_btns.append(b)
	vbox.add_child(int_row)

	var hint := Label.new()
	hint.text = "S or Esc to close"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85))
	vbox.add_child(hint)

	sync_ui()


func _on_toggle_pressed(key: String) -> void:
	settings[key] = not bool(settings[key])
	_apply_and_sync()


func _on_intensity_pressed(i: int) -> void:
	if i != int(settings["intensity"]):
		settings["intensity"] = i
		_apply_and_sync()


# Persist + notify main (which re-applies live FX state, like web syncSettingsUI).
func _apply_and_sync() -> void:
	save_settings()
	sync_ui()
	setting_changed.emit("settings", settings.duplicate())


func sync_ui() -> void:
	for row in _rows:
		var key: String = row[0]
		row[2].text = "ON" if bool(settings[key]) else "OFF"
	for i in range(_intensity_btns.size()):
		_intensity_btns[i].disabled = false
		# highlight the active step (web: #26406b background)
		if i == int(settings["intensity"]):
			var s := _intensity_btns[i].get_theme_stylebox("normal")
			_intensity_btns[i].add_theme_stylebox_override("normal", _highlight_box())
		else:
			_intensity_btns[i].remove_theme_stylebox_override("normal")


func _highlight_box() -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = Color("#26406b") # web active-step color (§2)
	return b
