# ReserveAreaFullScreenView：供给数据提取辅助
# 用途：抽取“从 GameState.map 读取供给/模块兜底供给”的逻辑，避免 UI 脚本过大。
class_name ReserveAreaSupplyHelpers
extends RefCounted

const ModuleSupplyFallbacksClass = preload("res://core/rules/module_supply_fallbacks.gd")

static func get_enabled_module_ids(state: GameState) -> Array[String]:
	var out: Array[String] = []
	if state == null:
		return out
	if state.modules is Array:
		out = Array(state.modules, TYPE_STRING, "", null)
	return out

static func collect_module_supply_counts(state: GameState, module_ids: Array[String]) -> Dictionary:
	var out := {}
	if state == null or not (state.map is Dictionary):
		return out

	var seen_keys := {}
	for k in state.map.keys():
		var key := str(k)
		if not key.ends_with("_supply_remaining"):
			continue
		if key == "house_number_supply_remaining" or key == "garden_supply_remaining" or key == "tile_supply_remaining":
			continue
		seen_keys[key] = true
		var v = state.map.get(k, null)
		if v is int:
			if int(v) > 0:
				out[key] = int(v)
		elif v is float:
			var f: float = float(v)
			if f == floor(f) and int(f) > 0:
				out[key] = int(f)

	_merge_module_supply_fallback_counts(state, module_ids, out, seen_keys)
	return out

static func _merge_module_supply_fallback_counts(state: GameState, module_ids: Array[String], supply_counts: Dictionary, seen_keys: Dictionary) -> void:
	if module_ids.has("lobbyists"):
		var fallback_counts := ModuleSupplyFallbacksClass.get_lobbyists_supply_fallbacks()
		for key in fallback_counts.keys():
			var count := int(fallback_counts.get(key, 0))
			_append_supply_count_if_missing(supply_counts, seen_keys, str(key), count)

	if module_ids.has("rural_marketeers"):
		_append_supply_count_if_missing(
			supply_counts,
			seen_keys,
			ModuleSupplyFallbacksClass.get_rural_offramp_supply_fallback_key(),
			ModuleSupplyFallbacksClass.get_rural_offramp_supply_fallback_total()
		)
		var billboard_remaining := _get_rural_billboard_supply_remaining(state)
		_append_supply_count_if_missing(
			supply_counts,
			seen_keys,
			ModuleSupplyFallbacksClass.get_rural_billboard_supply_pseudo_key(),
			billboard_remaining
		)

static func _append_supply_count_if_missing(supply_counts: Dictionary, seen_keys: Dictionary, key: String, count: int) -> void:
	if key.is_empty() or count <= 0:
		return
	if supply_counts.has(key) or seen_keys.has(key):
		return
	supply_counts[key] = count

static func _get_rural_billboard_supply_remaining(state: GameState) -> int:
	var occupied := 0
	if state != null and (state.map is Dictionary):
		var houses_val = state.map.get("houses", null)
		if houses_val is Dictionary:
			var rural_val = Dictionary(houses_val).get("rural_area", null)
			if rural_val is Dictionary:
				var boards_val = Dictionary(rural_val).get("giant_billboards", null)
				if boards_val is Dictionary:
					for side in ["N", "E", "S", "W"]:
						if Dictionary(boards_val).has(side):
							occupied += 1
	return maxi(0, ModuleSupplyFallbacksClass.get_rural_billboard_supply_total() - occupied)

static func collect_module_tile_supply_entries(state: GameState, _module_ids: Array[String] = []) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if state == null or not (state.map is Dictionary):
		return out
	var remaining_val = state.map.get("tile_supply_remaining", null)
	if not (remaining_val is Array):
		return out
	var remaining: Array = remaining_val
	if remaining.is_empty():
		return out

	var counts := {}
	for v in remaining:
		var tile_id := str(v).strip_edges()
		if tile_id.is_empty():
			continue
		counts[tile_id] = int(counts.get(tile_id, 0)) + 1

	var ids: Array[String] = []
	for k in counts.keys():
		ids.append(str(k))
	ids.sort()
	for tid in ids:
		var c := int(counts.get(tid, 0))
		if c > 0:
			out.append({"tile_id": tid, "count": c})
	return out

