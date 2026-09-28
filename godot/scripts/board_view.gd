# scripts/board_view.gd — renders the visible 10x20 board (rows 20..39) with the
# web game's bevel recipe, ghost piece, and v2 animations: line-clear flash+wipe
# (250ms), lock pop outline (60ms), level-up golden border tint (600ms).
extends Node2D

const CELL := 28
const COLS := 10
const ROWS := 20
const VISIBLE_TOP_ROW := 20
const CLEAR_MS := 250.0
const LOCKPOP_MS := 60.0
const LEVEL_BORDER_MS := 600.0

const COLORS := {
	"I": Color("#3fd8f0"), "O": Color("#ffd54a"), "T": Color("#b06ef2"),
	"S": Color("#59d97e"), "Z": Color("#ff5c5c"), "J": Color("#5b8cff"), "L": Color("#ffa14e"),
}

var game: Variant = null # Game instance, set by main.gd

# Animation state (time-based, like the web rAF loop).
var _clear_rows: Array = [] # visible rows to flash/wipe
var _clear_t0 := -1.0
var _pop_cells: Array = [] # [col, vis_row] of just-locked cells
var _pop_t0 := -1.0
var _border_t0 := -1.0


func size_px() -> Vector2:
	return Vector2(COLS * CELL, ROWS * CELL)


# Called by main on the "lock" event (emitted BEFORE rows are removed).
func note_lock(piece_type: String, x: int, y: int, rot: int) -> void:
	if game == null:
		return
	_pop_cells = []
	for cell in game.cells_of(piece_type, x, y, rot):
		var cy := int(cell[1])
		if cy >= VISIBLE_TOP_ROW and cy < VISIBLE_TOP_ROW + ROWS:
			_pop_cells.append([int(cell[0]), cy - VISIBLE_TOP_ROW])
	_pop_t0 = Time.get_ticks_msec() as float


# Called by main right after the "lock" event, while full rows still exist.
func note_full_rows() -> void:
	if game == null:
		return
	var full := []
	for r in range(VISIBLE_TOP_ROW, VISIBLE_TOP_ROW + ROWS):
		var is_full := true
		for c in range(COLS):
			if _is_empty(game.board[r][c]):
				is_full = false
				break
		if is_full:
			full.append(r - VISIBLE_TOP_ROW)
	_clear_rows = full


# Called by main on the "clear" event (rows already removed — purely visual).
func start_clear() -> void:
	if not _clear_rows.is_empty():
		_clear_t0 = Time.get_ticks_msec() as float


func note_levelup() -> void:
	_border_t0 = Time.get_ticks_msec() as float


static func _is_empty(v: Variant) -> bool:
	return v == null or v == ""


func _process(_delta: float) -> void:
	queue_redraw() # animations are wall-clock driven; redraw every frame (simplest faithful)


func _draw() -> void:
	var w := COLS * CELL
	var h := ROWS * CELL
	draw_rect(Rect2(0, 0, w, h), Color("#1a1d27"))
	# subtle grid lines
	for c in range(COLS + 1):
		draw_line(Vector2(c * CELL, 0), Vector2(c * CELL, h), Color(1, 1, 1, 0.05))
	for r in range(ROWS + 1):
		draw_line(Vector2(0, r * CELL), Vector2(w, r * CELL), Color(1, 1, 1, 0.05))
	if game == null:
		return

	# Settled cells (visible rows only).
	for vr in range(ROWS):
		var row: Array = game.board[VISIBLE_TOP_ROW + vr]
		for c in range(COLS):
			var t = row[c]
			if not _is_empty(t):
				draw_cell(c * CELL, vr * CELL, COLORS[str(t)])

	var show_piece: bool = game.current != null and (game.state == "playing" or game.state == "paused")
	if show_piece:
		# Ghost piece under the current one (web: plain fill inset 2px, alpha 0.32).
		var gy = game.ghost_y()
		if gy != null:
			for cell in game.cells_of(game.current["type"], int(game.current["x"]), int(gy), int(game.current["rot"])):
				var cy := int(cell[1])
				if cy >= VISIBLE_TOP_ROW and cy < VISIBLE_TOP_ROW + ROWS:
					draw_rect(Rect2(int(cell[0]) * CELL + 2, (cy - VISIBLE_TOP_ROW) * CELL + 2, CELL - 4, CELL - 4), Color(COLORS[str(game.current["type"])], 0.32))
		# Current piece with bevel.
		for cell in game.cells_of(game.current["type"], int(game.current["x"]), int(game.current["y"]), int(game.current["rot"])):
			var cy := int(cell[1])
			if cy >= VISIBLE_TOP_ROW and cy < VISIBLE_TOP_ROW + ROWS:
				draw_cell(int(cell[0]) * CELL, (cy - VISIBLE_TOP_ROW) * CELL, COLORS[str(game.current["type"])])

	var now := Time.get_ticks_msec() as float

	# v2 line-clear flash + left->right wipe over the cleared rows.
	if _clear_t0 >= 0.0 and not _clear_rows.is_empty():
		var p := minf(1.0, (now - _clear_t0) / CLEAR_MS)
		if p < 1.0:
			for vr in _clear_rows:
				draw_rect(Rect2(0, vr * CELL, w, CELL), Color(1, 1, 1, 0.85))
			var x := p * (w + 60) - 30 # bright band sweeps across the rows
			draw_rect(Rect2(x - 45, _clear_rows[0] * CELL, 60, _clear_rows.size() * CELL), Color(1, 1, 1, 0.9 * (1.0 - p)))
		else:
			_clear_t0 = -1.0
			_clear_rows = []

	# v2 lock pop: white outline alpha 0.5 -> 0 over LOCKPOP_MS on settled cells.
	if _pop_t0 >= 0.0 and not _pop_cells.is_empty():
		var p := minf(1.0, (now - _pop_t0) / LOCKPOP_MS)
		if p < 1.0:
			for cc in _pop_cells:
				draw_rect(Rect2(cc[0] * CELL + 1.5, cc[1] * CELL + 1.5, CELL - 3, CELL - 3), Color(1, 1, 1, 0.5 * (1.0 - p)), false, 2.0)
		else:
			_pop_t0 = -1.0
			_pop_cells = []

	# v2 level-up: golden board border tint fading over LEVEL_BORDER_MS.
	if _border_t0 >= 0.0:
		var p := minf(1.0, (now - _border_t0) / LEVEL_BORDER_MS)
		if p < 1.0:
			draw_rect(Rect2(0, 0, w, h), Color("#ffd54a", 0.35 * (1.0 - p)), false, 4.0)
		else:
			_border_t0 = -1.0


# Web drawCell recipe: inset = max(1, floor(cell*0.06)); main fill; top strip
# rgba(255,255,255,0.28); bottom strip rgba(0,0,0,0.28), height max(1, floor(cell*0.16)).
func draw_cell(px: int, py: int, color: Color) -> void:
	var inset := maxi(1, int(floor(CELL * 0.06)))
	draw_rect(Rect2(px + inset, py + inset, CELL - inset * 2, CELL - inset * 2), color)
	var strip := maxi(1, int(floor(CELL * 0.16)))
	draw_rect(Rect2(px + inset, py + inset, CELL - inset * 2, strip), Color(1, 1, 1, 0.28))
	draw_rect(Rect2(px + inset, py + CELL - inset - strip, CELL - inset * 2, strip), Color(0, 0, 0, 0.28))
