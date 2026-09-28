# scripts/hud.gd — right-panel HUD: SCORE (big), LEVEL, LINES, HOLD box, NEXT-5
# column. Level-up pulses the level label scale 1 -> 1.4 -> 1 over 400ms (web v2).
extends Control

const MINI_CELL := 16 # next-queue cell size (spec: ~16px)
const LEVEL_PULSE_MS := 400.0

# Inner class: draws a vertical stack of pieces (rot 0), one per slot.
class MiniBox extends Control:
	const SRS := preload("res://src/srs.gd")
	const MINI_CELL := 16
	const COLORS := {
		"I": Color("#3fd8f0"), "O": Color("#ffd54a"), "T": Color("#b06ef2"),
		"S": Color("#59d97e"), "Z": Color("#ff5c5c"), "J": Color("#5b8cff"), "L": Color("#ffa14e"),
	}

	var cell_size := MINI_CELL
	var slot_w := 3 * MINI_CELL + 8
	var pieces: Array = [] # piece types, top to bottom; empty slots stay blank

	func _draw() -> void:
		var slot_h := 2 * MINI_CELL + 8
		draw_rect(Rect2(0, 0, slot_w, pieces.size() * slot_h), Color("#14161f"))
		draw_rect(Rect2(0, 0, slot_w, pieces.size() * slot_h), Color(1, 1, 1, 0.08), false, 1.0)
		for i in range(pieces.size()):
			var type := str(pieces[i])
			if not SRS.SHAPES.has(type):
				continue
			var cells: Array = SRS.SHAPES[type][0]
			var max_c := 0
			var max_r := 0
			for c in cells:
				max_c = maxi(max_c, int(c[0]))
				max_r = maxi(max_r, int(c[1]))
			var ox := (slot_w - (max_c + 1) * cell_size) / 2.0
			var oy := i * slot_h + (slot_h - (max_r + 1) * cell_size) / 2.0
			for c in cells:
				draw_cell(int(ox + int(c[0]) * cell_size), int(oy + int(c[1]) * cell_size), COLORS[type], 1.0)

	func draw_cell(px: int, py: int, color: Color, alpha := 1.0) -> void:
		var inset := maxi(1, int(floor(cell_size * 0.06)))
		draw_rect(Rect2(px + inset, py + inset, cell_size - inset * 2, cell_size - inset * 2), Color(color, alpha))
		var strip := maxi(1, int(floor(cell_size * 0.16)))
		draw_rect(Rect2(px + inset, py + inset, cell_size - inset * 2, strip), Color(1, 1, 1, 0.28 * alpha))
		draw_rect(Rect2(px + inset, py + cell_size - inset - strip, cell_size - inset * 2, strip), Color(0, 0, 0, 0.28 * alpha))

var game: Variant = null # Game instance, set by main.gd
var score_label: Label
var level_label: Label
var lines_label: Label
var hold_box: Control
var next_box: Control
var _pulse_tween: Tween


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	score_label = _make_label("SCORE", 14, Color(0.75, 0.78, 0.85))
	level_label = _make_label("", 26, Color("#ffd54a"))
	lines_label = _make_label("", 14, Color(0.75, 0.78, 0.85))
	hold_box = MiniBox.new()
	next_box = MiniBox.new()
	add_child(hold_box)
	add_child(next_box)
	_layout() # positions set once; children are static after this


func _make_label(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	add_child(l) # parented here; _ready must not add it again
	return l


func _layout() -> void:
	# Right panel starts at x=310 (board occupies 16..296).
	var px := 318.0
	score_label.position = Vector2(px, 44) # "SCORE\nN" font 14 → ends ~y75
	level_label.position = Vector2(px, 80) # "LEVEL\nN" font 26 → ends ~y140
	lines_label.position = Vector2(px, 150) # below the level number (no overlap)
	hold_box.position = Vector2(px - 8, 192)
	next_box.position = Vector2(px + 34, 182)


func _process(_delta: float) -> void:
	if game == null or not is_inside_tree():
		return
	score_label.text = "SCORE\n%d" % game.score
	level_label.text = "LEVEL\n%d" % game.level
	lines_label.text = "LINES\n%d" % game.lines
	var hb := hold_box as MiniBox
	hb.pieces = [game.hold] if game.hold != null else []
	hb.queue_redraw()
	# NEXT-5: queue stacked vertically in one box.
	var nb := next_box as MiniBox
	nb.pieces = game.queue.duplicate().slice(0, 5)
	nb.queue_redraw()


# Web v2: level number scale pulse 1 -> 1.4 -> 1 over LEVEL_PULSE_MS.
func note_levelup(_level: int) -> void:
	if _pulse_tween != null and _pulse_tween.is_valid():
		_pulse_tween.kill()
	level_label.pivot_offset = level_label.size / 2.0
	_pulse_tween = create_tween()
	_pulse_tween.tween_property(level_label, "scale", Vector2(1.4, 1.4), LEVEL_PULSE_MS / 2000.0)
	_pulse_tween.tween_property(level_label, "scale", Vector2.ONE, LEVEL_PULSE_MS / 2000.0)
