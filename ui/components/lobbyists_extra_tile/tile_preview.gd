class_name TilePreview
extends Control

const TileRegistryClass = preload("res://core/map/tile_registry.gd")
const PieceRegistryClass = preload("res://core/map/piece_registry.gd")
const MapUtilsClass = preload("res://core/map/map_utils.gd")

var tile_id: String = ""
var tile_rotation: int = 0 # 0/90/180/270

func _ready() -> void:
	if not resized.is_connected(queue_redraw):
		resized.connect(queue_redraw)

func set_tile(id_str: String, rot: int) -> void:
	tile_id = str(id_str).strip_edges()
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
	if r.size.x <= 4.0 or r.size.y <= 4.0:
		return

	var pad := maxf(4.0, minf(r.size.x, r.size.y) * 0.06)
	var preview_rect := Rect2(Vector2(pad, pad), Vector2(r.size.x - pad * 2.0, r.size.y - pad * 2.0))
	if preview_rect.size.x <= 4.0 or preview_rect.size.y <= 4.0:
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
	fill.a = 0.22
	var border := base.lightened(0.25)
	border.a = 0.65

	draw_rect(board_rect, fill, true)
	draw_rect(board_rect, border, false, 1.0)

	# Grid lines
	for ix in range(tile_size + 1):
		var x := board_pos.x + float(ix) * cell_px
		draw_line(Vector2(x, board_pos.y), Vector2(x, board_pos.y + board_px.y), Color(border, 0.38), 1.0)
	for iy in range(tile_size + 1):
		var y := board_pos.y + float(iy) * cell_px
		draw_line(Vector2(board_pos.x, y), Vector2(board_pos.x + board_px.x, y), Color(border, 0.38), 1.0)

	if tile_id.is_empty():
		return
	if not TileRegistryClass.is_loaded():
		return
	var def_val = TileRegistryClass.get_def(tile_id)
	if def_val == null or not (def_val is TileDef):
		return
	var tile_def: TileDef = def_val

	_draw_blocked_cells(tile_def, board_pos, cell_px)
	_draw_printed_structures(tile_def, board_pos, cell_px)
	_draw_roads(tile_def, board_pos, cell_px)

func _draw_blocked_cells(tile_def: TileDef, board_pos: Vector2, cell_px: float) -> void:
	var tile_size := int(MapUtilsClass.TILE_SIZE)
	var col := Color(1, 1, 1, 0.10)
	for ly in range(tile_size):
		for lx in range(tile_size):
			var local_pos := Vector2i(lx, ly)
			if not tile_def.is_blocked_at(local_pos):
				continue
			var wp := MapUtilsClass.local_to_world(local_pos, Vector2i.ZERO, tile_rotation)
			var rect := Rect2(board_pos + Vector2(float(wp.x) * cell_px, float(wp.y) * cell_px), Vector2(cell_px, cell_px))
			draw_rect(rect.grow(-1.0), col, true)

func _draw_printed_structures(tile_def: TileDef, board_pos: Vector2, cell_px: float) -> void:
	if not PieceRegistryClass.is_loaded():
		return

	for struct_val in tile_def.printed_structures:
		if not (struct_val is Dictionary):
			continue
		var s: Dictionary = struct_val
		var piece_id := str(s.get("piece_id", "")).strip_edges()
		if piece_id.is_empty():
			continue
		var anchor_val = s.get("anchor", null)
		if not (anchor_val is Vector2i):
			continue
		var local_anchor: Vector2i = anchor_val
		var rot0 := int(s.get("rotation", 0))
		var total_rot := _normalize_rotation(rot0 + tile_rotation)

		var piece_def_val = PieceRegistryClass.get_def(piece_id)
		if piece_def_val == null or not (piece_def_val is PieceDef):
			continue
		var piece_def: PieceDef = piece_def_val

		var world_anchor := MapUtilsClass.local_to_world(local_anchor, Vector2i.ZERO, tile_rotation)
		var cells: Array[Vector2i] = piece_def.get_world_cells(world_anchor, total_rot)
		if cells.is_empty():
			continue

		var fill := _structure_fill_color(piece_id)
		var border := fill.darkened(0.35)
		fill.a = 0.26
		border.a = 0.55

		for wp in cells:
			if wp.x < 0 or wp.y < 0 or wp.x >= int(MapUtilsClass.TILE_SIZE) or wp.y >= int(MapUtilsClass.TILE_SIZE):
				continue
			var rect := Rect2(board_pos + Vector2(float(wp.x) * cell_px, float(wp.y) * cell_px), Vector2(cell_px, cell_px))
			draw_rect(rect.grow(-1.0), fill, true)
			draw_rect(rect.grow(-1.0), border, false, 1.0)

func _structure_fill_color(piece_id: String) -> Color:
	var id := str(piece_id).to_lower()
	if id.contains("restaurant"):
		return Color("#ef4444")
	if id.contains("garden"):
		return Color("#22c55e")
	if id.contains("house"):
		return Color("#a16207")
	return Color("#60a5fa")

func _draw_roads(tile_def: TileDef, board_pos: Vector2, cell_px: float) -> void:
	var tile_size := int(MapUtilsClass.TILE_SIZE)
	var road_col := Color(1, 1, 1, 0.80)
	var road_w := maxf(2.0, cell_px * 0.14)

	for ly in range(tile_size):
		for lx in range(tile_size):
			var local_pos := Vector2i(lx, ly)
			var segs: Array = tile_def.get_road_segments_at(local_pos)
			if segs.is_empty():
				continue
				var wp := MapUtilsClass.local_to_world(local_pos, Vector2i.ZERO, tile_rotation)
				var cell_origin := board_pos + Vector2(float(wp.x) * cell_px, float(wp.y) * cell_px)
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
