class_name MapSnapshotRenderer
extends RefCounted

const VERSION := 1
const DEFAULT_CELL_PX := 24
const DEFAULT_PAD_PX := 18
const MAX_IMAGE_DIMENSION := 1600
const MIN_CELL_PX := 8

const COLOR_BG := Color(0.94, 0.91, 0.84, 1.0)
const COLOR_CELL := Color(0.79, 0.73, 0.61, 1.0)
const COLOR_BLOCKED := Color(0.43, 0.42, 0.39, 1.0)
const COLOR_GRID := Color(0.43, 0.36, 0.27, 0.22)
const COLOR_ROAD := Color(0.24, 0.23, 0.21, 1.0)
const COLOR_HOUSE := Color(0.47, 0.22, 0.18, 1.0)
const COLOR_GARDEN := Color(0.25, 0.53, 0.32, 1.0)
const COLOR_DRINK := Color(0.16, 0.47, 0.71, 1.0)
const COLOR_MARKETING := Color(0.91, 0.64, 0.21, 1.0)
const COLOR_MARKETING_BORDER := Color(0.45, 0.24, 0.08, 1.0)
const COLOR_EMPTY_EXT := Color(0.70, 0.66, 0.56, 1.0)
const PLAYER_COLORS := [
	Color(0.73, 0.23, 0.18, 1.0),
	Color(0.18, 0.49, 0.61, 1.0),
	Color(0.35, 0.54, 0.24, 1.0),
	Color(0.79, 0.63, 0.13, 1.0),
	Color(0.55, 0.36, 0.96, 1.0),
	Color(0.85, 0.47, 0.04, 1.0),
]

static func render_state_png(state, options: Dictionary = {}) -> Result:
	if state == null or not (state.map is Dictionary):
		return Result.failure("map snapshot: state.map 缺失")
	var map_data: Dictionary = state.map
	var grid_size := _read_vector2i(map_data.get("grid_size", null), Vector2i.ZERO)
	if grid_size.x <= 0 or grid_size.y <= 0:
		return Result.failure("map snapshot: grid_size 非法")
	var cells_val = map_data.get("cells", null)
	if not (cells_val is Array):
		return Result.failure("map snapshot: cells 缺失")

	var origin := _read_vector2i(map_data.get("map_origin", null), Vector2i.ZERO)
	var bounds := _compute_bounds(map_data, grid_size, origin)
	var bounds_size: Vector2i = bounds.get("size", Vector2i.ZERO)
	if bounds_size.x <= 0 or bounds_size.y <= 0:
		return Result.failure("map snapshot: bounds 非法")

	var pad_px := maxi(0, int(options.get("pad_px", DEFAULT_PAD_PX)))
	var cell_px := maxi(MIN_CELL_PX, int(options.get("cell_px", DEFAULT_CELL_PX)))
	var max_cells := maxi(bounds_size.x, bounds_size.y)
	var max_dim_without_pad := maxi(1, MAX_IMAGE_DIMENSION - pad_px * 2)
	if max_cells * cell_px > max_dim_without_pad:
		cell_px = maxi(MIN_CELL_PX, int(floor(float(max_dim_without_pad) / float(max_cells))))

	var width := bounds_size.x * cell_px + pad_px * 2
	var height := bounds_size.y * cell_px + pad_px * 2
	var image := Image.create(width, height, false, Image.FORMAT_RGBA8)
	image.fill(COLOR_BG)

	_draw_base_cells(image, map_data, grid_size, origin, bounds, cell_px, pad_px)
	_draw_external_cells(image, map_data, bounds, cell_px, pad_px)
	_draw_drink_sources(image, map_data, bounds, cell_px, pad_px)
	_draw_structures(image, map_data, bounds, cell_px, pad_px)
	_draw_marketing(image, map_data, bounds, cell_px, pad_px)

	var png_bytes := image.save_png_to_buffer()
	if png_bytes.is_empty():
		return Result.failure("map snapshot: png 编码失败")
	return Result.success({
		"version": VERSION,
		"png_bytes": png_bytes,
		"width": width,
		"height": height,
		"cell_px": cell_px,
	})

static func _compute_bounds(map_data: Dictionary, grid_size: Vector2i, origin: Vector2i) -> Dictionary:
	var min_pos := -origin
	var max_pos := Vector2i(grid_size.x - origin.x - 1, grid_size.y - origin.y - 1)
	var bounds := {"min": min_pos, "max": max_pos}

	var external_cells := _parse_external_cells(map_data)
	for pos_val in external_cells.keys():
		if pos_val is Vector2i:
			_include_pos(bounds, pos_val)

	_expand_bounds_for_piece_dict(bounds, map_data.get("houses", null))
	_expand_bounds_for_piece_dict(bounds, map_data.get("restaurants", null))
	_expand_bounds_for_drink_sources(bounds, map_data.get("drink_sources", null))
	_expand_bounds_for_marketing(bounds, map_data.get("marketing_placements", null))

	min_pos = bounds.get("min", min_pos)
	max_pos = bounds.get("max", max_pos)
	bounds["size"] = max_pos - min_pos + Vector2i.ONE
	return bounds

static func _draw_base_cells(image: Image, map_data: Dictionary, grid_size: Vector2i, origin: Vector2i, bounds: Dictionary, cell_px: int, pad_px: int) -> void:
	var cells: Array = map_data.get("cells", [])
	for y in range(grid_size.y):
		if y < 0 or y >= cells.size():
			continue
		var row_val = cells[y]
		if not (row_val is Array):
			continue
		var row: Array = row_val
		for x in range(grid_size.x):
			if x < 0 or x >= row.size():
				continue
			var world_pos := Vector2i(x, y) - origin
			var cell: Dictionary = Dictionary(row[x]) if row[x] is Dictionary else {}
			_draw_cell(image, bounds, world_pos, cell, cell_px, pad_px)

static func _draw_external_cells(image: Image, map_data: Dictionary, bounds: Dictionary, cell_px: int, pad_px: int) -> void:
	var external_cells := _parse_external_cells(map_data)
	for pos_val in external_cells.keys():
		if not (pos_val is Vector2i):
			continue
		var pos: Vector2i = pos_val
		var cell: Dictionary = Dictionary(external_cells.get(pos, {}))
		if cell.is_empty():
			_fill_cell(image, bounds, pos, cell_px, pad_px, COLOR_EMPTY_EXT, 0)
		else:
			_draw_cell(image, bounds, pos, cell, cell_px, pad_px)

static func _draw_cell(image: Image, bounds: Dictionary, world_pos: Vector2i, cell: Dictionary, cell_px: int, pad_px: int) -> void:
	var fill := COLOR_BLOCKED if bool(cell.get("blocked", false)) else COLOR_CELL
	_fill_cell(image, bounds, world_pos, cell_px, pad_px, fill, 0)
	var road_segments_val = cell.get("road_segments", null)
	if road_segments_val is Array and not (road_segments_val as Array).is_empty():
		_draw_road(image, bounds, world_pos, cell_px, pad_px)
	var structure_val = cell.get("structure", null)
	if structure_val is Dictionary and not (structure_val as Dictionary).is_empty():
		var structure: Dictionary = structure_val
		var owner := int(structure.get("owner", -1))
		var piece_id := str(structure.get("piece_id", ""))
		var color := _player_color(owner) if piece_id.contains("restaurant") else COLOR_HOUSE
		_fill_cell(image, bounds, world_pos, cell_px, pad_px, color, maxi(3, cell_px / 6))
	_draw_cell_border(image, bounds, world_pos, cell_px, pad_px, COLOR_GRID, 1)

static func _draw_road(image: Image, bounds: Dictionary, world_pos: Vector2i, cell_px: int, pad_px: int) -> void:
	var rect := _cell_rect(bounds, world_pos, cell_px, pad_px, 0)
	var lane := maxi(3, int(round(float(cell_px) * 0.22)))
	var cx := rect.position.x + int((cell_px - lane) / 2)
	var cy := rect.position.y + int((cell_px - lane) / 2)
	image.fill_rect(Rect2i(Vector2i(cx, rect.position.y), Vector2i(lane, cell_px)), COLOR_ROAD)
	image.fill_rect(Rect2i(Vector2i(rect.position.x, cy), Vector2i(cell_px, lane)), COLOR_ROAD)

static func _draw_structures(image: Image, map_data: Dictionary, bounds: Dictionary, cell_px: int, pad_px: int) -> void:
	var houses_val = map_data.get("houses", null)
	if houses_val is Dictionary:
		for house_key in (houses_val as Dictionary).keys():
			var house_val = (houses_val as Dictionary).get(house_key, null)
			if not (house_val is Dictionary):
				continue
			var house: Dictionary = house_val
			var cells := _read_cells_or_anchor(house)
			for pos in cells:
				_fill_cell(image, bounds, pos, cell_px, pad_px, COLOR_HOUSE, maxi(3, cell_px / 7))
				if bool(house.get("has_garden", false)):
					_fill_cell(image, bounds, pos, cell_px, pad_px, COLOR_GARDEN, maxi(7, cell_px / 3))

	var restaurants_val = map_data.get("restaurants", null)
	if restaurants_val is Dictionary:
		for restaurant_key in (restaurants_val as Dictionary).keys():
			var restaurant_val = (restaurants_val as Dictionary).get(restaurant_key, null)
			if not (restaurant_val is Dictionary):
				continue
			var restaurant: Dictionary = restaurant_val
			var owner := int(restaurant.get("owner", -1))
			var color := _player_color(owner)
			for pos in _read_cells_or_anchor(restaurant):
				_fill_cell(image, bounds, pos, cell_px, pad_px, color, maxi(2, cell_px / 8))

static func _draw_drink_sources(image: Image, map_data: Dictionary, bounds: Dictionary, cell_px: int, pad_px: int) -> void:
	var sources_val = map_data.get("drink_sources", null)
	if not (sources_val is Array):
		return
	for source_val in sources_val:
		if not (source_val is Dictionary):
			continue
		var source: Dictionary = source_val
		var pos_val = _try_vector2i(source.get("world_pos", null))
		if not (pos_val is Vector2i):
			continue
		var color := COLOR_DRINK
		var type_name := str(source.get("type", "")).to_lower()
		if type_name.contains("beer"):
			color = Color(0.75, 0.50, 0.13, 1.0)
		elif type_name.contains("soda") or type_name.contains("cola"):
			color = Color(0.12, 0.43, 0.67, 1.0)
		_fill_cell(image, bounds, pos_val, cell_px, pad_px, color, maxi(5, cell_px / 4))

static func _draw_marketing(image: Image, map_data: Dictionary, bounds: Dictionary, cell_px: int, pad_px: int) -> void:
	var placements_val = map_data.get("marketing_placements", null)
	if not (placements_val is Dictionary):
		return
	for key in (placements_val as Dictionary).keys():
		var placement_val = (placements_val as Dictionary).get(key, null)
		if not (placement_val is Dictionary):
			continue
		var placement: Dictionary = placement_val
		var anchor_val = _try_vector2i(placement.get("world_pos", null))
		if not (anchor_val is Vector2i):
			continue
		var size := _placement_size(placement)
		for dy in range(size.y):
			for dx in range(size.x):
				var pos: Vector2i = anchor_val + Vector2i(dx, dy)
				_fill_cell(image, bounds, pos, cell_px, pad_px, COLOR_MARKETING, maxi(4, cell_px / 5))
				_draw_cell_border(image, bounds, pos, cell_px, pad_px, COLOR_MARKETING_BORDER, 2)

static func _read_cells_or_anchor(piece: Dictionary) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var cells_val = piece.get("cells", null)
	if cells_val is Array:
		for item in cells_val:
			var pos_val = _try_vector2i(item)
			if pos_val is Vector2i:
				out.append(pos_val)
	if out.is_empty():
		var anchor_val = _try_vector2i(piece.get("anchor_pos", piece.get("world_pos", null)))
		if anchor_val is Vector2i:
			out.append(anchor_val)
	return out

static func _placement_size(placement: Dictionary) -> Vector2i:
	var size := _read_vector2i(placement.get("footprint_size", null), Vector2i.ONE)
	if size.x <= 0 or size.y <= 0:
		size = Vector2i.ONE
	var rotation := int(placement.get("rotation", 0))
	if rotation == 90 or rotation == 270:
		size = Vector2i(size.y, size.x)
	return size

static func _fill_cell(image: Image, bounds: Dictionary, world_pos: Vector2i, cell_px: int, pad_px: int, color: Color, inset: int) -> void:
	var rect := _cell_rect(bounds, world_pos, cell_px, pad_px, inset)
	if rect.size.x <= 0 or rect.size.y <= 0:
		return
	image.fill_rect(rect, color)

static func _draw_cell_border(image: Image, bounds: Dictionary, world_pos: Vector2i, cell_px: int, pad_px: int, color: Color, thickness: int) -> void:
	var rect := _cell_rect(bounds, world_pos, cell_px, pad_px, 0)
	_draw_rect_border(image, rect, color, thickness)

static func _draw_rect_border(image: Image, rect: Rect2i, color: Color, thickness: int) -> void:
	var t := maxi(1, int(thickness))
	image.fill_rect(Rect2i(rect.position, Vector2i(rect.size.x, t)), color)
	image.fill_rect(Rect2i(Vector2i(rect.position.x, rect.position.y + rect.size.y - t), Vector2i(rect.size.x, t)), color)
	image.fill_rect(Rect2i(rect.position, Vector2i(t, rect.size.y)), color)
	image.fill_rect(Rect2i(Vector2i(rect.position.x + rect.size.x - t, rect.position.y), Vector2i(t, rect.size.y)), color)

static func _cell_rect(bounds: Dictionary, world_pos: Vector2i, cell_px: int, pad_px: int, inset: int) -> Rect2i:
	var min_pos: Vector2i = bounds.get("min", Vector2i.ZERO)
	var view_pos := world_pos - min_pos
	var px := pad_px + view_pos.x * cell_px + inset
	var py := pad_px + view_pos.y * cell_px + inset
	var size := maxi(1, cell_px - inset * 2)
	return Rect2i(Vector2i(px, py), Vector2i(size, size))

static func _expand_bounds_for_piece_dict(bounds: Dictionary, pieces_val) -> void:
	if not (pieces_val is Dictionary):
		return
	for key in (pieces_val as Dictionary).keys():
		var piece_val = (pieces_val as Dictionary).get(key, null)
		if not (piece_val is Dictionary):
			continue
		for pos in _read_cells_or_anchor(piece_val):
			_include_pos(bounds, pos)

static func _expand_bounds_for_drink_sources(bounds: Dictionary, sources_val) -> void:
	if not (sources_val is Array):
		return
	for source_val in sources_val:
		if not (source_val is Dictionary):
			continue
		var pos_val = _try_vector2i((source_val as Dictionary).get("world_pos", null))
		if pos_val is Vector2i:
			_include_pos(bounds, pos_val)

static func _expand_bounds_for_marketing(bounds: Dictionary, placements_val) -> void:
	if not (placements_val is Dictionary):
		return
	for key in (placements_val as Dictionary).keys():
		var placement_val = (placements_val as Dictionary).get(key, null)
		if not (placement_val is Dictionary):
			continue
		var placement: Dictionary = placement_val
		var anchor_val = _try_vector2i(placement.get("world_pos", null))
		if not (anchor_val is Vector2i):
			continue
		var size := _placement_size(placement)
		for dy in range(size.y):
			for dx in range(size.x):
				_include_pos(bounds, anchor_val + Vector2i(dx, dy))

static func _include_pos(bounds: Dictionary, pos: Vector2i) -> void:
	var min_pos: Vector2i = bounds.get("min", pos)
	var max_pos: Vector2i = bounds.get("max", pos)
	min_pos.x = mini(min_pos.x, pos.x)
	min_pos.y = mini(min_pos.y, pos.y)
	max_pos.x = maxi(max_pos.x, pos.x)
	max_pos.y = maxi(max_pos.y, pos.y)
	bounds["min"] = min_pos
	bounds["max"] = max_pos

static func _parse_external_cells(map_data: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var raw = map_data.get("external_cells", null)
	if not (raw is Dictionary):
		return out
	for key in (raw as Dictionary).keys():
		var pos_val = _try_vector2i(key)
		if not (pos_val is Vector2i):
			pos_val = _try_parse_pos_key(str(key))
		if not (pos_val is Vector2i):
			continue
		var cell_val = (raw as Dictionary).get(key, {})
		out[pos_val] = Dictionary(cell_val) if cell_val is Dictionary else {}
	return out

static func _try_parse_pos_key(key: String):
	var parts := str(key).split(",")
	if parts.size() != 2:
		return null
	if not parts[0].is_valid_int() or not parts[1].is_valid_int():
		return null
	return Vector2i(int(parts[0]), int(parts[1]))

static func _read_vector2i(value, fallback: Vector2i) -> Vector2i:
	var parsed = _try_vector2i(value)
	if parsed is Vector2i:
		return parsed
	return fallback

static func _try_vector2i(value):
	if value is Vector2i:
		return value
	if value is Vector2:
		return Vector2i(int(value.x), int(value.y))
	if value is Array:
		var arr: Array = value
		if arr.size() >= 2:
			return Vector2i(int(arr[0]), int(arr[1]))
	if value is Dictionary:
		var d: Dictionary = value
		if d.has("x") and d.has("y"):
			return Vector2i(int(d.get("x", 0)), int(d.get("y", 0)))
	return null

static func _player_color(owner: int) -> Color:
	if owner < 0:
		return Color(0.38, 0.35, 0.31, 1.0)
	return PLAYER_COLORS[int(owner) % PLAYER_COLORS.size()]
