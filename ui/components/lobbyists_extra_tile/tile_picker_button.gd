# Lobbyists extra tile: tile 선택 버튼（带预览/可旋转）
extends Button

const TileRegistryClass = preload("res://core/map/tile_registry.gd")
const MapUtilsClass = preload("res://core/map/map_utils.gd")

var tile_id: String = ""
var tile_rotation: int = 0 # 0/90/180/270

func _ready() -> void:
	text = ""
	icon = null
	expand_icon = true
	clip_text = true
	toggle_mode = true

	custom_minimum_size = Vector2(62, 62)

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

func set_tile_rotation(rot: int) -> void:
	tile_rotation = _normalize_rotation(rot)
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

	var tile_size := int(MapUtilsClass.TILE_SIZE)
	if tile_size <= 0:
		return

	var cell_px := minf(preview_rect.size.x / float(tile_size), preview_rect.size.y / float(tile_size))
	cell_px = maxf(2.0, floor(cell_px))

	var board_px := Vector2(float(tile_size) * cell_px, float(tile_size) * cell_px)
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

	# Grid lines（轻一点，避免压住道路）
	for ix in range(tile_size + 1):
		var x := board_pos.x + float(ix) * cell_px
		draw_line(Vector2(x, board_pos.y), Vector2(x, board_pos.y + board_px.y), Color(border, 0.28), 1.0)
	for iy in range(tile_size + 1):
		var y := board_pos.y + float(iy) * cell_px
		draw_line(Vector2(board_pos.x, y), Vector2(board_pos.x + board_px.x, y), Color(border, 0.28), 1.0)

	if tile_id.is_empty():
		return
	if not TileRegistryClass.is_loaded():
		return
	var def_val = TileRegistryClass.get_def(tile_id)
	if def_val == null or not (def_val is TileDef):
		return
	var tile_def: TileDef = def_val

	# blocked cells
	var blocked_col := Color(1, 1, 1, 0.10)
	for ly in range(tile_size):
		for lx in range(tile_size):
			var local_pos := Vector2i(lx, ly)
			if not tile_def.is_blocked_at(local_pos):
				continue
			var wp := MapUtilsClass.local_to_world(local_pos, Vector2i.ZERO, tile_rotation)
			var rect := Rect2(board_pos + Vector2(float(wp.x) * cell_px, float(wp.y) * cell_px), Vector2(cell_px, cell_px))
			draw_rect(rect.grow(-1.0), blocked_col, true)

	# roads（只画道路，结构细节在大预览里展示）
	var road_col := Color(1, 1, 1, 0.85)
	var road_w := maxf(2.0, cell_px * 0.14)
	for ly2 in range(tile_size):
		for lx2 in range(tile_size):
			var local_pos2 := Vector2i(lx2, ly2)
			var segs: Array = tile_def.get_road_segments_at(local_pos2)
			if segs.is_empty():
				continue
			var wp2 := MapUtilsClass.local_to_world(local_pos2, Vector2i.ZERO, tile_rotation)
			var cell_origin := board_pos + Vector2(float(wp2.x) * cell_px, float(wp2.y) * cell_px)
			var c := cell_origin + Vector2(cell_px * 0.5, cell_px * 0.5)
			for seg_val in segs:
				if not (seg_val is Dictionary):
					continue
				var rotated := MapUtilsClass.rotate_segment(seg_val, tile_rotation)
				var dirs_val = (rotated as Dictionary).get("dirs", null)
				if not (dirs_val is Array):
					continue
				for d_val in Array(dirs_val):
					var d := str(d_val).strip_edges()
					var p := c
					match d:
						"N":
							p = cell_origin + Vector2(cell_px * 0.5, 0.0)
						"E":
							p = cell_origin + Vector2(cell_px, cell_px * 0.5)
						"S":
							p = cell_origin + Vector2(cell_px * 0.5, cell_px)
						"W":
							p = cell_origin + Vector2(0.0, cell_px * 0.5)
						_:
							continue
					draw_line(c, p, road_col, road_w)

	_draw_tile_label(r, board_rect)

func _draw_tile_label(r: Rect2, board_rect: Rect2) -> void:
	var label := str(tile_id).strip_edges()
	if label.begins_with("tile_"):
		label = label.trim_prefix("tile_")
	label = label.to_upper()
	if label.is_empty():
		return

	var font: Font = ThemeDB.fallback_font
	var font_size := maxi(10, int(round(minf(r.size.x, r.size.y) * 0.22)))
	var pad := maxf(2.0, minf(r.size.x, r.size.y) * 0.06)

	var pos := Vector2(board_rect.position.x + board_rect.size.x - pad, board_rect.position.y + board_rect.size.y - pad)
	# Right-bottom text: use RIGHT alignment with small width
	draw_string(font, pos + Vector2(1, 1), label, HORIZONTAL_ALIGNMENT_RIGHT, board_rect.size.x, font_size, Color(0, 0, 0, 0.75))
	draw_string(font, pos, label, HORIZONTAL_ALIGNMENT_RIGHT, board_rect.size.x, font_size, Color(1, 1, 1, 0.95))

