# 晚餐结算动画：地图几何与 token 构建辅助
class_name DinnertimeAnimationMapHelpers
extends RefCounted

const MapUtilsClass = preload("res://core/map/map_utils.gd")
const TextureUtilsClass = preload("res://ui/scenes/game/map/drawer/texture_utils.gd")

static func compute_structure_rect_from_index(cell_size: float, info: Dictionary) -> Rect2:
	var min_pos_val = info.get("min", null)
	var max_pos_val = info.get("max", null)
	if not (min_pos_val is Vector2i) or not (max_pos_val is Vector2i):
		return Rect2()
	var min_pos: Vector2i = min_pos_val
	var max_pos: Vector2i = max_pos_val
	var size_cells := (max_pos - min_pos) + Vector2i.ONE
	return Rect2(
		Vector2(float(min_pos.x) * cell_size, float(min_pos.y) * cell_size),
		Vector2(float(size_cells.x) * cell_size, float(size_cells.y) * cell_size)
	)

static func compute_house_rect_from_anchor(cell_size: float, anchor: Vector2i, rotation: int, world_origin: Vector2i) -> Rect2:
	if anchor == Vector2i(-1, -1):
		return Rect2()

	var house_mask := [[1, 1], [1, 1]]
	var house_cells_world: Array[Vector2i] = MapUtilsClass.get_footprint_cells(house_mask, Vector2i.ZERO, anchor, rotation)
	if house_cells_world.is_empty():
		return Rect2()

	var hmin := Vector2i(2147483647, 2147483647)
	var hmax := Vector2i(-2147483648, -2147483648)
	for wpos in house_cells_world:
		var vpos: Vector2i = wpos - world_origin
		hmin.x = min(hmin.x, vpos.x)
		hmin.y = min(hmin.y, vpos.y)
		hmax.x = max(hmax.x, vpos.x)
		hmax.y = max(hmax.y, vpos.y)
	var hsize_cells := (hmax - hmin) + Vector2i.ONE
	return Rect2(
		Vector2(float(hmin.x) * cell_size, float(hmin.y) * cell_size),
		Vector2(float(hsize_cells.x) * cell_size, float(hsize_cells.y) * cell_size)
	)

static func compute_house_rects_from_map_cells(game_state: GameState, world_origin: Vector2i, house_id: String, cell_size: float) -> Dictionary:
	if house_id.is_empty() or game_state == null:
		return {}
	if not (game_state.map is Dictionary):
		return {}

	var map: Dictionary = game_state.map
	var map_origin := Vector2i.ZERO
	var origin_val = map.get("map_origin", null)
	if origin_val is Vector2i:
		map_origin = origin_val

	var cells_val = map.get("cells", null)
	if not (cells_val is Array):
		return {}
	var cells: Array = cells_val

	var found_any := false
	var vmin := Vector2i(2147483647, 2147483647)
	var vmax := Vector2i(-2147483648, -2147483648)
	var anchor := Vector2i(-1, -1)
	var rotation := 0
	var piece_id := ""
	var has_garden := false

	for y in range(cells.size()):
		var row_val = cells[y]
		if not (row_val is Array):
			continue
		var row: Array = row_val
		for x in range(row.size()):
			var cell_val = row[x]
			if not (cell_val is Dictionary):
				continue
			var cell: Dictionary = cell_val
			var s_val = cell.get("structure", null)
			if not (s_val is Dictionary):
				continue
			var structure: Dictionary = s_val
			if str(structure.get("house_id", "")).strip_edges() != house_id:
				continue

			found_any = true
			var world_pos := Vector2i(x, y) - map_origin
			var view_pos := world_pos - world_origin
			vmin.x = min(vmin.x, view_pos.x)
			vmin.y = min(vmin.y, view_pos.y)
			vmax.x = max(vmax.x, view_pos.x)
			vmax.y = max(vmax.y, view_pos.y)

			if anchor == Vector2i(-1, -1):
				var a_val = structure.get("parent_anchor", null)
				if a_val is Vector2i:
					anchor = a_val
				var r_val = structure.get("rotation", null)
				if r_val is int:
					rotation = int(r_val)
				elif r_val is float:
					var f: float = float(r_val)
					if f == floor(f):
						rotation = int(f)
				piece_id = str(structure.get("piece_id", "")).strip_edges()
				var hg_val = structure.get("has_garden", null)
				if hg_val is bool:
					has_garden = bool(hg_val)

	if not found_any:
		return {}

	var size_cells := (vmax - vmin) + Vector2i.ONE
	var structure_rect := Rect2(Vector2(float(vmin.x) * cell_size, float(vmin.y) * cell_size), Vector2(float(size_cells.x) * cell_size, float(size_cells.y) * cell_size))
	if piece_id == "house_with_garden":
		has_garden = true
	elif piece_id == "house":
		has_garden = false

	var house_rect := Rect2()
	if anchor != Vector2i(-1, -1):
		var house_mask := [[1, 1], [1, 1]]
		var house_cells_world: Array[Vector2i] = MapUtilsClass.get_footprint_cells(house_mask, Vector2i.ZERO, anchor, rotation)
		if not house_cells_world.is_empty():
			var hmin := Vector2i(2147483647, 2147483647)
			var hmax := Vector2i(-2147483648, -2147483648)
			for wpos in house_cells_world:
				var vpos: Vector2i = wpos - world_origin
				hmin.x = min(hmin.x, vpos.x)
				hmin.y = min(hmin.y, vpos.y)
				hmax.x = max(hmax.x, vpos.x)
				hmax.y = max(hmax.y, vpos.y)
			var hsize_cells := (hmax - hmin) + Vector2i.ONE
			house_rect = Rect2(
				Vector2(float(hmin.x) * cell_size, float(hmin.y) * cell_size),
				Vector2(float(hsize_cells.x) * cell_size, float(hsize_cells.y) * cell_size)
			)

	if house_rect.size == Vector2.ZERO:
		house_rect = structure_rect

	return {
		"house_rect": house_rect,
		"structure_rect": structure_rect,
		"has_garden": has_garden,
	}

static func create_demand_token_nodes(map_anim_layer: Control, skin, order: Dictionary, house_id: String, house_rect: Rect2, structure_rect: Rect2, has_garden: bool, cell_size: float, state_seed: int) -> Array[Control]:
	var out: Array[Control] = []
	if not is_instance_valid(map_anim_layer) or skin == null:
		return out
	var demands_val = order.get("demands", null)
	if not (demands_val is Dictionary):
		return out
	var demands: Dictionary = demands_val
	if demands.is_empty():
		return out

	var product_ids: Array[String] = []
	for k in demands.keys():
		var count := int(demands.get(k, 0))
		if count <= 0:
			continue
		var pid := str(k)
		if pid == "cola":
			pid = "soda"
		for _i in range(count):
			product_ids.append(pid)
	if product_ids.is_empty():
		return out
	product_ids.sort()
	var draw_count: int = min(product_ids.size(), 6)
	var draw_product_ids: Array[String] = product_ids.slice(0, draw_count)

	var demand_key := ",".join(product_ids)
	var seed := compute_demand_scatter_seed(state_seed, house_id)
	seed = int((seed ^ hash_string_32(demand_key)) & 0x7FFFFFFF)

	var reserved: Array[Rect2] = []
	var demand_area_rect := house_rect
	if has_garden and structure_rect.size != Vector2.ZERO:
		demand_area_rect = structure_rect
	if demand_area_rect.size == Vector2.ZERO:
		demand_area_rect = structure_rect

	var house_id_rect_target := house_rect if house_rect.size != Vector2.ZERO else demand_area_rect
	reserved.append(compute_house_id_rect(cell_size, house_id_rect_target))

	var base_icon_size := cell_size * 0.90
	var base_min_spacing := maxf(1.0, cell_size * 0.04)

	var slots: Array[Rect2] = []
	var icon_size := base_icon_size
	var min_spacing := base_min_spacing
	var scales := [1.0, 0.86, 0.74, 0.62, 0.50]
	for scale in scales:
		icon_size = base_icon_size * float(scale)
		min_spacing = base_min_spacing * float(scale)
		var scatter_area_rect := demand_area_rect.grow(-cell_size * 0.05)
		slots = build_demand_token_slots(scatter_area_rect, icon_size, min_spacing, reserved)
		if slots.size() < draw_count:
			slots = build_demand_token_slots(demand_area_rect, icon_size, min_spacing, reserved)
		if slots.size() >= draw_count:
			break
	if slots.is_empty():
		return out
	var actual_draw_count: int = min(draw_count, slots.size())

	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	rng.state = int(seed)
	shuffle_rect2_array(rng, slots)

	for i in range(actual_draw_count):
		var pid2: String = str(draw_product_ids[i])
		if pid2.is_empty():
			continue
		var tex: Texture2D = skin.get_product_icon_texture(pid2)
		if tex == null:
			continue
		var rect := slots[i]
		var token := Control.new()
		token.set_anchors_preset(Control.PRESET_TOP_LEFT)
		token.position = rect.position
		token.size = rect.size
		token.custom_minimum_size = rect.size
		token.pivot_offset = rect.size * 0.5
		token.modulate = Color(1, 1, 1, 0.95)
		token.mouse_filter = Control.MOUSE_FILTER_IGNORE
		map_anim_layer.add_child(token)

		var fit_rect := TextureUtilsClass.get_texture_aspect_fit_rect(tex, Rect2(Vector2.ZERO, rect.size))
		if fit_rect.size == Vector2.ZERO:
			fit_rect = Rect2(Vector2.ZERO, rect.size)

		var icon := TextureRect.new()
		icon.set_anchors_preset(Control.PRESET_TOP_LEFT)
		icon.position = fit_rect.position
		icon.size = fit_rect.size
		icon.custom_minimum_size = fit_rect.size
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_SCALE
		icon.texture = tex
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		token.add_child(icon)

		out.append(token)
	return out

static func create_restaurant_demand_token_nodes(map_anim_layer: Control, skin, order: Dictionary, restaurant_rect: Rect2, cell_size: float, state_seed: int) -> Array[Control]:
	var out: Array[Control] = []
	if not is_instance_valid(map_anim_layer) or skin == null:
		return out
	if restaurant_rect.size == Vector2.ZERO:
		return out
	var demands_val = order.get("demands", null)
	if not (demands_val is Dictionary):
		return out
	var demands: Dictionary = demands_val
	if demands.is_empty():
		return out

	var product_ids: Array[String] = []
	for k in demands.keys():
		var count := int(demands.get(k, 0))
		if count <= 0:
			continue
		var pid := str(k)
		if pid == "cola":
			pid = "soda"
		for _i in range(count):
			product_ids.append(pid)
	if product_ids.is_empty():
		return out
	product_ids.sort()
	var draw_count: int = min(product_ids.size(), 6)
	var draw_product_ids: Array[String] = product_ids.slice(0, draw_count)

	var house_id := str(order.get("house_id", ""))
	var restaurant_id := str(order.get("matched_restaurant", order.get("winner_restaurant_id", ""))).strip_edges()
	var demand_key := ",".join(product_ids)
	var seed := compute_demand_scatter_seed(state_seed, "%s:%s:restaurant" % [house_id, restaurant_id])
	seed = int((seed ^ hash_string_32(demand_key)) & 0x7FFFFFFF)

	var reserved: Array[Rect2] = []
	var base_icon_size := cell_size * 0.90
	var base_min_spacing := maxf(1.0, cell_size * 0.04)

	var slots: Array[Rect2] = []
	var icon_size := base_icon_size
	var min_spacing := base_min_spacing
	var scales := [1.0, 0.86, 0.74, 0.62, 0.50]
	for scale in scales:
		icon_size = base_icon_size * float(scale)
		min_spacing = base_min_spacing * float(scale)
		var scatter_area_rect := restaurant_rect.grow(-cell_size * 0.08)
		slots = build_demand_token_slots(scatter_area_rect, icon_size, min_spacing, reserved)
		if slots.size() < draw_count:
			slots = build_demand_token_slots(restaurant_rect, icon_size, min_spacing, reserved)
		if slots.size() >= draw_count:
			break
	if slots.is_empty():
		return out
	var actual_draw_count: int = min(draw_count, slots.size())

	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	rng.state = int(seed)
	shuffle_rect2_array(rng, slots)

	for i in range(actual_draw_count):
		var pid2: String = str(draw_product_ids[i])
		if pid2.is_empty():
			continue
		var tex: Texture2D = skin.get_product_icon_texture(pid2)
		if tex == null:
			continue
		var rect := slots[i]
		var token := Control.new()
		token.set_anchors_preset(Control.PRESET_TOP_LEFT)
		token.position = rect.position
		token.size = rect.size
		token.custom_minimum_size = rect.size
		token.pivot_offset = rect.size * 0.5
		token.modulate = Color(1, 1, 1, 0.95)
		token.visible = false
		token.set_meta("show_on_float_only", true)
		token.mouse_filter = Control.MOUSE_FILTER_IGNORE
		map_anim_layer.add_child(token)

		var fit_rect := TextureUtilsClass.get_texture_aspect_fit_rect(tex, Rect2(Vector2.ZERO, rect.size))
		if fit_rect.size == Vector2.ZERO:
			fit_rect = Rect2(Vector2.ZERO, rect.size)

		var icon := TextureRect.new()
		icon.set_anchors_preset(Control.PRESET_TOP_LEFT)
		icon.position = fit_rect.position
		icon.size = fit_rect.size
		icon.custom_minimum_size = fit_rect.size
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_SCALE
		icon.texture = tex
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		token.add_child(icon)

		out.append(token)
	return out

static func get_restaurant_cells(game_state: GameState, restaurant_id: String) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if restaurant_id.is_empty() or game_state == null:
		return out
	if not (game_state.map is Dictionary):
		return out
	var map: Dictionary = game_state.map

	var restaurants_val = map.get("restaurants", null)
	if restaurants_val is Dictionary:
		var rest_val = (restaurants_val as Dictionary).get(restaurant_id, null)
		if rest_val is Dictionary:
			var rest: Dictionary = rest_val
			var cells_val = rest.get("cells", null)
			if cells_val is Array:
				for c in cells_val:
					if c is Vector2i:
						out.append(c)
	if not out.is_empty():
		return out

	var map_origin := Vector2i.ZERO
	var origin_val = map.get("map_origin", null)
	if origin_val is Vector2i:
		map_origin = origin_val

	var cells_rows_val = map.get("cells", null)
	if not (cells_rows_val is Array):
		return out
	var cells_rows: Array = cells_rows_val

	var seen: Dictionary = {}
	for y in range(cells_rows.size()):
		var row_val = cells_rows[y]
		if not (row_val is Array):
			continue
		var row: Array = row_val
		for x in range(row.size()):
			var cell_val = row[x]
			if not (cell_val is Dictionary):
				continue
			var cell: Dictionary = cell_val
			var s_val = cell.get("structure", null)
			if not (s_val is Dictionary):
				continue
			var structure: Dictionary = s_val
			if str(structure.get("restaurant_id", "")).strip_edges() != restaurant_id:
				continue
			var world_pos := Vector2i(x, y) - map_origin
			if not seen.has(world_pos):
				seen[world_pos] = true
				out.append(world_pos)

	return out

static func hash_string_32(text: String) -> int:
	var h: int = 2166136261
	for i in range(text.length()):
		h ^= text.unicode_at(i)
		h = int((h * 16777619) & 0xFFFFFFFF)
	return h

static func compute_demand_scatter_seed(state_seed: int, key: String) -> int:
	var seed := hash_string_32(key)
	return int((seed ^ int(state_seed)) & 0x7FFFFFFF)

static func is_scatter_rect_free(candidate: Rect2, taken: Array[Rect2], min_spacing: float) -> bool:
	var grow := maxf(min_spacing, 0.0)
	var cand := candidate.grow(grow)
	for r in taken:
		if cand.intersects(r.grow(grow)):
			return false
	return true

static func shuffle_rect2_array(rng: RandomNumberGenerator, arr: Array[Rect2]) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := arr[i]
		arr[i] = arr[j]
		arr[j] = tmp

static func build_demand_token_slots(area: Rect2, icon_size: float, min_spacing: float, reserved: Array[Rect2]) -> Array[Rect2]:
	var margin := maxf(1.0, min_spacing)
	var min_x := area.position.x + margin
	var min_y := area.position.y + margin
	var max_x := area.position.x + area.size.x - icon_size - margin
	var max_y := area.position.y + area.size.y - icon_size - margin
	if max_x < min_x:
		max_x = min_x
	if max_y < min_y:
		max_y = min_y

	var step := maxf(icon_size + min_spacing, 1.0)
	var cols := maxi(1, int(floor(maxf(0.0, max_x - min_x) / step)) + 1)
	var rows := maxi(1, int(floor(maxf(0.0, max_y - min_y) / step)) + 1)

	var slots: Array[Rect2] = []
	for row in range(rows):
		for col in range(cols):
			var x := min_x + float(col) * step
			var y := min_y + float(row) * step
			x = clampf(x, min_x, max_x)
			y = clampf(y, min_y, max_y)
			var rect := Rect2(Vector2(x, y), Vector2(icon_size, icon_size))
			if is_scatter_rect_free(rect, reserved, min_spacing):
				slots.append(rect)
	return slots

static func compute_house_id_rect(cell_size: float, structure_rect: Rect2) -> Rect2:
	var pad := maxf(3.0, cell_size * 0.10)
	var bg_size := Vector2(cell_size * 0.90, cell_size * 0.58)
	var pos := structure_rect.position + Vector2(structure_rect.size.x - bg_size.x - pad, pad)
	return Rect2(pos, bg_size)

static func get_structure_rotation_at(game_state: GameState, world_anchor: Vector2i) -> int:
	if game_state == null or not (game_state.map is Dictionary):
		return 0
	var map: Dictionary = game_state.map

	var map_origin := Vector2i.ZERO
	var origin_val = map.get("map_origin", null)
	if origin_val is Vector2i:
		map_origin = origin_val

	var cells_val = map.get("cells", null)
	if not (cells_val is Array):
		return 0
	var cells: Array = cells_val
	var idx := world_anchor + map_origin
	if idx.y < 0 or idx.y >= cells.size():
		return 0
	var row_val = cells[idx.y]
	if not (row_val is Array):
		return 0
	var row: Array = row_val
	if idx.x < 0 or idx.x >= row.size():
		return 0
	var cell_val = row[idx.x]
	if not (cell_val is Dictionary):
		return 0
	var cell: Dictionary = cell_val
	var s_val = cell.get("structure", null)
	if not (s_val is Dictionary):
		return 0
	var structure: Dictionary = s_val
	var r_val = structure.get("rotation", 0)
	if r_val is int:
		return int(r_val)
	if r_val is float:
		var f: float = float(r_val)
		if f == floor(f):
			return int(f)
	return 0

static func get_structure_piece_id_at(game_state: GameState, world_anchor: Vector2i) -> String:
	if game_state == null or not (game_state.map is Dictionary):
		return ""
	var map: Dictionary = game_state.map

	var map_origin := Vector2i.ZERO
	var origin_val = map.get("map_origin", null)
	if origin_val is Vector2i:
		map_origin = origin_val

	var cells_val = map.get("cells", null)
	if not (cells_val is Array):
		return ""
	var cells: Array = cells_val
	var idx := world_anchor + map_origin
	if idx.y < 0 or idx.y >= cells.size():
		return ""
	var row_val = cells[idx.y]
	if not (row_val is Array):
		return ""
	var row: Array = row_val
	if idx.x < 0 or idx.x >= row.size():
		return ""
	var cell_val = row[idx.x]
	if not (cell_val is Dictionary):
		return ""
	var cell: Dictionary = cell_val
	var s_val = cell.get("structure", null)
	if not (s_val is Dictionary):
		return ""
	var structure: Dictionary = s_val
	return str(structure.get("piece_id", "")).strip_edges()

static func place_persistent_x_mark(map_anim_layer: Control, rect: Rect2, cell_size: float) -> void:
	if not is_instance_valid(map_anim_layer):
		return
	if rect.size == Vector2.ZERO:
		return

	var pos := rect.position + rect.size * 0.5
	var fs := int(round(maxf(46.0, cell_size * 1.25)))
	var box := Vector2(float(fs) * 1.15, float(fs) * 1.15)

	var shadow := Label.new()
	shadow.text = "✕"
	shadow.add_theme_font_size_override("font_size", fs)
	shadow.add_theme_color_override("font_color", Color(0, 0, 0, 0.75))
	shadow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	shadow.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	shadow.size = box
	shadow.position = pos - box * 0.5 + Vector2(3, 3)
	shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map_anim_layer.add_child(shadow)

	var mark := Label.new()
	mark.text = "✕"
	mark.add_theme_font_size_override("font_size", fs)
	mark.add_theme_color_override("font_color", Color(0.95, 0.25, 0.18, 1))
	mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mark.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	mark.size = box
	mark.position = pos - box * 0.5
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map_anim_layer.add_child(mark)
