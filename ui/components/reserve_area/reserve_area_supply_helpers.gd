# ReserveAreaFullScreenView：供给数据提取辅助
# 用途：抽取“从 GameState.map 和模块 UI metadata 读取供给”的逻辑，避免 UI 脚本过大。
class_name ReserveAreaSupplyHelpers
extends RefCounted

const ModuleUiMetadataClass = preload("res://gameplay/module_ui_metadata.gd")

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

	_merge_module_supply_provider_counts(state, module_ids, out, seen_keys)
	return out

static func _merge_module_supply_provider_counts(state: GameState, module_ids: Array[String], supply_counts: Dictionary, seen_keys: Dictionary) -> void:
	if not ModuleUiMetadataClass.is_loaded():
		return
	var providers := ModuleUiMetadataClass.get_reserve_supply_provider_entries()
	for item_val in providers:
		if not (item_val is Dictionary):
			continue
		var item: Dictionary = item_val
		var source := str(item.get("source", "")).strip_edges()
		if not source.is_empty() and not module_ids.has(source):
			continue
		var cb: Callable = item.get("callback", Callable())
		if not cb.is_valid():
			push_error("ReserveAreaSupplyHelpers: reserve supply provider callback 无效: %s" % str(item.get("id", "")))
			continue
		var r = cb.call(state)
		if not (r is Dictionary):
			push_error("ReserveAreaSupplyHelpers: reserve supply provider 必须返回 Dictionary: %s" % str(item.get("id", "")))
			continue
		var counts: Dictionary = r
		for key_val in counts.keys():
			var count := int(counts.get(key_val, 0))
			_append_supply_count_if_missing(supply_counts, seen_keys, str(key_val), count)

static func _append_supply_count_if_missing(supply_counts: Dictionary, seen_keys: Dictionary, key: String, count: int) -> void:
	if key.is_empty() or count <= 0:
		return
	if supply_counts.has(key) or seen_keys.has(key):
		return
	supply_counts[key] = count

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
