# MarketingPanel：营销类型按钮构建（纯数据层）
# 用途：从可用员工/板件推导营销类型列表，减少 MarketingPanel 内部重复/臃肿逻辑。
class_name MarketingPanelTypeSpecsBuilder
extends RefCounted

static func build_type_specs(
	available_marketers: Array[Dictionary],
	available_boards_by_type: Dictionary,
	base_type_defs: Array[Dictionary],
	type_name_overrides: Dictionary
) -> Dictionary:
	var marketers_by_type: Dictionary = {}
	var counted_marketer_keys_by_type: Dictionary = {}
	var marketer_index := 0
	for marketer in available_marketers:
		marketer_index += 1
		var type_ids := _extract_marketing_type_ids(marketer)
		if type_ids.is_empty():
			continue
		var staff_id := int(marketer.get("staff_id", -1))
		var emp_id := str(marketer.get("employee_type", marketer.get("id", ""))).strip_edges()
		var marketer_key := "staff:%d" % staff_id if staff_id > 0 else "%s#%d" % [emp_id, marketer_index]
		for m_type in type_ids:
			if not marketers_by_type.has(m_type):
				marketers_by_type[m_type] = []
				counted_marketer_keys_by_type[m_type] = {}
			var seen_for_type: Dictionary = counted_marketer_keys_by_type[m_type]
			if seen_for_type.has(marketer_key):
				continue
			seen_for_type[marketer_key] = true
			marketers_by_type[m_type].append(marketer)
			counted_marketer_keys_by_type[m_type] = seen_for_type

	var base_defs_by_id: Dictionary = {}
	var ordered_type_ids: Array[String] = []
	for type_def in base_type_defs:
		var tid := str(type_def.get("id", "")).strip_edges()
		if tid.is_empty():
			continue
		base_defs_by_id[tid] = type_def
		ordered_type_ids.append(tid)

	var extra_ids_set: Dictionary = {}
	for k in marketers_by_type.keys():
		var tid2 := str(k).strip_edges()
		if tid2.is_empty():
			continue
		if base_defs_by_id.has(tid2):
			continue
		extra_ids_set[tid2] = true
	for k2 in available_boards_by_type.keys():
		var tid3 := str(k2).strip_edges()
		if tid3.is_empty():
			continue
		if base_defs_by_id.has(tid3):
			continue
		extra_ids_set[tid3] = true

	var extra_ids: Array[String] = []
	for k3 in extra_ids_set.keys():
		extra_ids.append(str(k3))
	extra_ids.sort()
	ordered_type_ids.append_array(extra_ids)

	var specs: Array[Dictionary] = []
	var available_type_ids: Array[String] = []

	for type_id in ordered_type_ids:
		var marketer_count: int = Array(marketers_by_type.get(type_id, [])).size()
		var board_count: int = Array(available_boards_by_type.get(type_id, [])).size()
		var is_available := marketer_count > 0 and board_count > 0
		if is_available:
			available_type_ids.append(type_id)

		var type_def_use: Dictionary = {}
		var known_def = base_defs_by_id.get(type_id, null)
		if known_def is Dictionary:
			type_def_use = known_def
		else:
			var display_name := str(type_name_overrides.get(type_id, type_id))
			var fallback_icon := "?"
			if not type_id.is_empty():
				fallback_icon = type_id.substr(0, 1).to_upper()
			type_def_use = {
				"id": type_id,
				"name": display_name,
				"icon": fallback_icon,
				"color": Color("#9aa3ad"),
				"range": 0,
			}

		specs.append({
			"type_id": type_id,
			"type_def": type_def_use,
			"marketer_count": marketer_count,
			"board_count": board_count,
			"is_available": is_available,
		})

	return {
		"specs": specs,
		"available_type_ids": available_type_ids,
	}

static func _extract_marketing_type_ids(marketer: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var seen := {}
	var marketing_types_val = marketer.get("marketing_types", [])
	if marketing_types_val is Array:
		for type_val in Array(marketing_types_val):
			var type_id := str(type_val).strip_edges()
			if type_id.is_empty() or seen.has(type_id):
				continue
			seen[type_id] = true
			out.append(type_id)

	var legacy_type := str(marketer.get("type", "")).strip_edges()
	if not legacy_type.is_empty() and not seen.has(legacy_type):
		seen[legacy_type] = true
		out.append(legacy_type)

	out.sort()
	return out
