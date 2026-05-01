# ActionPanel：板块选择按钮（可视化占地/旋转）
extends Button

const PieceRegistryClass = preload("res://core/map/piece_registry.gd")
const PieceUiHintsRegistryClass = preload("res://core/rules/piece_ui_hints_registry.gd")
const PiecePreviewLayoutClass = preload("res://ui/utils/piece_preview_layout.gd")

var piece_id: String = ""
var piece_rotation: int = 0 # 0/90/180/270
var display_label: String = ""
var preview_texture: Texture2D = null

func _ready() -> void:
	text = ""
	icon = null
	expand_icon = true
	clip_text = true
	toggle_mode = true

	custom_minimum_size = Vector2(56, 56)

	if not resized.is_connected(queue_redraw):
		resized.connect(queue_redraw)
	if not toggled.is_connected(_on_toggled):
		toggled.connect(_on_toggled)
	if not mouse_entered.is_connected(queue_redraw):
		mouse_entered.connect(queue_redraw)
	if not mouse_exited.is_connected(queue_redraw):
		mouse_exited.connect(queue_redraw)

func _on_toggled(_pressed: bool) -> void:
	queue_redraw()

func set_piece_rotation(rot: int) -> void:
	piece_rotation = _normalize_rotation(rot)
	queue_redraw()

func set_preview_texture(tex: Texture2D) -> void:
	preview_texture = tex
	queue_redraw()

func _normalize_rotation(rot: int) -> int:
	var r := int(rot) % 360
	if r < 0:
		r += 360
	if r != 0 and r != 90 and r != 180 and r != 270:
		r = 0
	return r

func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	if r.size.x <= 1.0 or r.size.y <= 1.0:
		return

	var pad := maxf(4.0, minf(r.size.x, r.size.y) * 0.10)
	var preview_rect := Rect2(Vector2(pad, pad), Vector2(r.size.x - pad * 2.0, r.size.y - pad * 2.0))
	if preview_rect.size.x <= 1.0 or preview_rect.size.y <= 1.0:
		return

	var cells: Array[Vector2i] = _get_piece_cells(piece_id, piece_rotation)
	if cells.is_empty():
		_draw_empty(preview_rect)
		return

	var minp := Vector2i(2147483647, 2147483647)
	var maxp := Vector2i(-2147483648, -2147483648)
	for p in cells:
		minp.x = min(minp.x, p.x)
		minp.y = min(minp.y, p.y)
		maxp.x = max(maxp.x, p.x)
		maxp.y = max(maxp.y, p.y)
	var size_cells := (maxp - minp) + Vector2i.ONE
	var w := maxi(1, int(size_cells.x))
	var h := maxi(1, int(size_cells.y))

	var cell_px := minf(preview_rect.size.x / float(w), preview_rect.size.y / float(h))
	cell_px = maxf(2.0, floor(cell_px))

	var board_px := Vector2(float(w) * cell_px, float(h) * cell_px)
	var board_pos := preview_rect.position + (preview_rect.size - board_px) * 0.5
	var board_rect := Rect2(board_pos, board_px)

	var base := Color("#2a2d34")
	var fill := base
	fill.a = 0.30
	var border := base.lightened(0.25)
	border.a = 0.45
	if button_pressed:
		fill = base.lightened(0.10)
		fill.a = 0.42
		border = base.lightened(0.35)
		border.a = 0.85
	elif is_hovered():
		fill.a = 0.38

	draw_rect(board_rect, fill, true)
	draw_rect(board_rect, border, false, 1.0)

	# Grid lines
	for ix in range(w + 1):
		var x := board_pos.x + float(ix) * cell_px
		draw_line(Vector2(x, board_pos.y), Vector2(x, board_pos.y + board_px.y), border, 1.0)
	for iy in range(h + 1):
		var y := board_pos.y + float(iy) * cell_px
		draw_line(Vector2(board_pos.x, y), Vector2(board_pos.x + board_px.x, y), border, 1.0)

	var kind := _infer_kind(piece_id)
	var cell_fill := Color("#c6c9d2") if kind == "road" else Color("#22C55E") if kind == "park" else Color("#60a5fa")
	var cell_border := cell_fill.darkened(0.35)

	for p in cells:
		var lp := p - minp
		var rect := Rect2(board_pos + Vector2(float(lp.x) * cell_px, float(lp.y) * cell_px), Vector2(cell_px, cell_px))
		var cfill := cell_fill
		cfill.a = 0.42 if button_pressed else 0.30
		draw_rect(rect.grow(-1.0), cfill, true)

	if preview_texture != null:
		var mod := Color(1, 1, 1, 0.92 if button_pressed else 0.80)
		var local_cells := PiecePreviewLayoutClass.normalize_cells(cells)
		if kind == "road":
			_draw_road_texture(preview_texture, local_cells, board_pos, cell_px, mod)
		elif kind == "park":
			_draw_park_texture(preview_texture, local_cells, board_pos, cell_px, mod)
		else:
			var dst := _get_texture_aspect_fill_rect(preview_texture, board_rect.grow(-1.0))
			_draw_texture_rect_clipped_by_cells(preview_texture, dst, cells, minp, board_pos, cell_px, mod)

	for p in cells:
		var lp := p - minp
		var rect := Rect2(board_pos + Vector2(float(lp.x) * cell_px, float(lp.y) * cell_px), Vector2(cell_px, cell_px))
		var cb := cell_border
		cb.a = 0.70
		draw_rect(rect.grow(-1.0), cb, false, 1.0)

func _draw_empty(preview_rect: Rect2) -> void:
	var col := Color(1, 1, 1, 0.10)
	draw_rect(preview_rect, col, true)

func _get_texture_aspect_fill_rect(texture: Texture2D, rect: Rect2) -> Rect2:
	if texture == null:
		return Rect2()
	var ts: Vector2 = texture.get_size()
	if ts.x <= 0.0 or ts.y <= 0.0:
		return Rect2()
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return Rect2()

	var scale := maxf(rect.size.x / ts.x, rect.size.y / ts.y)
	var size := ts * scale
	var pos := rect.position + (rect.size - size) * 0.5
	return Rect2(pos, size)

func _draw_road_texture(texture: Texture2D, local_cells: Array[Vector2i], board_pos: Vector2, cell_px: float, modulate: Color) -> void:
	if texture == null or local_cells.is_empty():
		return
	var center: Vector2 = PiecePreviewLayoutClass.get_road_icon_center(local_cells)
	var rect: Rect2 = PiecePreviewLayoutClass.get_centered_rect(center, board_pos, cell_px, 0.90)
	var pad := maxf(1.0, cell_px * 0.06)
	_draw_texture_aspect_fit(texture, rect.grow(-pad), modulate)

func _draw_park_texture(texture: Texture2D, local_cells: Array[Vector2i], board_pos: Vector2, cell_px: float, modulate: Color) -> void:
	if texture == null or local_cells.is_empty():
		return
	var run: Array[Vector2i] = PiecePreviewLayoutClass.get_longest_cell_run(local_cells)
	if run.is_empty():
		return
	var rect: Rect2 = PiecePreviewLayoutClass.get_rect_for_cells(run, board_pos, cell_px)
	var pad := maxf(1.0, cell_px * 0.08)
	rect = rect.grow(-pad)
	if PiecePreviewLayoutClass.is_run_vertical(run):
		_draw_texture_aspect_fit_rotated(texture, rect, modulate, 90.0)
	else:
		_draw_texture_aspect_fit(texture, rect, modulate)

func _draw_texture_aspect_fit(texture: Texture2D, rect: Rect2, modulate: Color) -> void:
	if texture == null:
		return
	var dst := _get_texture_aspect_fit_rect(texture, rect)
	if dst.size.x <= 0.0 or dst.size.y <= 0.0:
		return
	draw_texture_rect(texture, dst, false, modulate)

func _draw_texture_aspect_fit_rotated(texture: Texture2D, rect: Rect2, modulate: Color, rotation_degrees: float) -> void:
	if texture == null:
		return
	var ts: Vector2 = texture.get_size()
	if ts.x <= 0.0 or ts.y <= 0.0 or rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	var effective_size := Vector2(ts.y, ts.x)
	var scale := minf(rect.size.x / effective_size.x, rect.size.y / effective_size.y)
	var draw_size := ts * scale
	var center := rect.position + rect.size * 0.5
	draw_set_transform(center, deg_to_rad(rotation_degrees), Vector2.ONE)
	draw_texture_rect(texture, Rect2(-draw_size * 0.5, draw_size), false, modulate)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _get_texture_aspect_fit_rect(texture: Texture2D, rect: Rect2) -> Rect2:
	if texture == null:
		return Rect2()
	var ts: Vector2 = texture.get_size()
	if ts.x <= 0.0 or ts.y <= 0.0:
		return Rect2()
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return Rect2()

	var scale := minf(rect.size.x / ts.x, rect.size.y / ts.y)
	var size := ts * scale
	var pos := rect.position + (rect.size - size) * 0.5
	return Rect2(pos, size)

func _draw_texture_rect_clipped_by_cells(
	texture: Texture2D,
	dst_rect: Rect2,
	cells: Array[Vector2i],
	minp: Vector2i,
	board_pos: Vector2,
	cell_px: float,
	modulate: Color
) -> void:
	if texture == null:
		return
	if dst_rect.size.x <= 0.0 or dst_rect.size.y <= 0.0:
		return
	var ts: Vector2 = texture.get_size()
	if ts.x <= 0.0 or ts.y <= 0.0:
		return

	var inv_w := 1.0 / dst_rect.size.x
	var inv_h := 1.0 / dst_rect.size.y

	for p in cells:
		var lp := p - minp
		var cell_rect := Rect2(board_pos + Vector2(float(lp.x) * cell_px, float(lp.y) * cell_px), Vector2(cell_px, cell_px))
		var clip := dst_rect.intersection(cell_rect)
		if clip.size.x <= 0.1 or clip.size.y <= 0.1:
			continue

		var u0 := (clip.position.x - dst_rect.position.x) * inv_w
		var v0 := (clip.position.y - dst_rect.position.y) * inv_h
		var u1 := (clip.position.x + clip.size.x - dst_rect.position.x) * inv_w
		var v1 := (clip.position.y + clip.size.y - dst_rect.position.y) * inv_h

		u0 = clampf(u0, 0.0, 1.0)
		v0 = clampf(v0, 0.0, 1.0)
		u1 = clampf(u1, 0.0, 1.0)
		v1 = clampf(v1, 0.0, 1.0)

		var src_pos := Vector2(u0 * ts.x, v0 * ts.y)
		var src_size := Vector2(maxf(0.0, (u1 - u0) * ts.x), maxf(0.0, (v1 - v0) * ts.y))
		if src_size.x <= 0.1 or src_size.y <= 0.1:
			continue
		draw_texture_rect_region(texture, clip, Rect2(src_pos, src_size), modulate)

func _infer_kind(pid: String) -> String:
	var id := str(pid).strip_edges()
	if id.is_empty():
		return ""
	if id == "park":
		return "park"

	var kind := PieceUiHintsRegistryClass.get_kind(id)
	if kind == "road" or kind == "park":
		return kind
	if not PieceUiHintsRegistryClass.get_road_overlay(id).is_empty():
		return "road"
	return ""

func _get_piece_cells(pid: String, rot: int) -> Array[Vector2i]:
	var id := str(pid).strip_edges()
	if id.is_empty():
		return []
	if not PieceRegistryClass.is_loaded():
		return []
	var def_val = PieceRegistryClass.get_def(id)
	if def_val == null or not (def_val is PieceDef):
		return []
	var def: PieceDef = def_val
	var cells: Array[Vector2i] = def.get_world_cells(Vector2i.ZERO, rot)
	return cells
