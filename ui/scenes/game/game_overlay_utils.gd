# Game scene：overlay 数据 helpers（仅 UI 用）
extends RefCounted

static func normalize_count_dict(val) -> Dictionary:
	var out: Dictionary = {}
	if not (val is Dictionary):
		return out
	var d: Dictionary = val
	for k in d.keys():
		var key := str(k)
		if key.is_empty():
			continue
		out[key] = coerce_int(d.get(k, 0))
	return out

static func coerce_int(v) -> int:
	if v is int:
		return int(v)
	if v is float:
		var f: float = float(v)
		return int(floor(f))
	if v is String:
		var s := str(v)
		if s.is_valid_int():
			return int(s)
	return 0

static func get_house_anchor_world_pos(state: GameState, house_id: String) -> Vector2i:
	if state == null:
		return Vector2i(-1, -1)
	if house_id.is_empty():
		return Vector2i(-1, -1)
	if not (state.map is Dictionary):
		return Vector2i(-1, -1)
	var houses_val = (state.map as Dictionary).get("houses", null)
	if not (houses_val is Dictionary):
		return Vector2i(-1, -1)
	var house_val = (houses_val as Dictionary).get(house_id, null)
	if not (house_val is Dictionary):
		return Vector2i(-1, -1)
	var anchor_val = (house_val as Dictionary).get("anchor_pos", null)
	if anchor_val is Vector2i:
		return anchor_val
	var cells_val = (house_val as Dictionary).get("cells", null)
	if cells_val is Array and not (cells_val as Array).is_empty():
		var first = (cells_val as Array)[0]
		if first is Vector2i:
			return first
	return Vector2i(-1, -1)

static func build_house_demand_counts_from_map(state: GameState, house_id: String) -> Dictionary:
	var out: Dictionary = {}
	if state == null:
		return out
	if house_id.is_empty():
		return out
	if not (state.map is Dictionary):
		return out
	var houses_val = (state.map as Dictionary).get("houses", null)
	if not (houses_val is Dictionary):
		return out
	var house_val = (houses_val as Dictionary).get(house_id, null)
	if not (house_val is Dictionary):
		return out
	var demands_val = (house_val as Dictionary).get("demands", null)
	if not (demands_val is Array):
		return out

	for d_val in demands_val:
		if not (d_val is Dictionary):
			continue
		var d: Dictionary = d_val
		var product_id := str(d.get("product", ""))
		if product_id.is_empty():
			continue
		out[product_id] = int(out.get(product_id, 0)) + 1

	return out

