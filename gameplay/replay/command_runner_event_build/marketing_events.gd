# CommandRunnerEventBuild：Marketing 事件拆分
# 用途：从 round_state.marketing.processed 中推导营销需求/到期事件（日志/展示语义）。
extends RefCounted

const HouseNumberManagerClass = preload("res://core/map/house_number_manager.gd")

static func build_marketing_demand_generated_events(marketing_state: GameState) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if marketing_state == null:
		return out
	if not (marketing_state.round_state is Dictionary):
		return out

	var marketing_val = Dictionary(marketing_state.round_state).get("marketing", null)
	if not (marketing_val is Dictionary):
		return out
	var marketing: Dictionary = marketing_val
	var processed_val = marketing.get("processed", null)
	if not (processed_val is Array):
		return out

	var houses_by_id: Dictionary = {}
	if marketing_state.map is Dictionary:
		var houses_val = Dictionary(marketing_state.map).get("houses", null)
		if houses_val is Dictionary:
			houses_by_id = houses_val

	for p_val in Array(processed_val):
		if not (p_val is Dictionary):
			continue
		var p: Dictionary = p_val

		var board_number := int(p.get("board_number", 0))
		var owner := int(p.get("owner", -1))
		var marketing_type := str(p.get("type", "")).strip_edges()
		var employee_type := str(p.get("employee_type", "")).strip_edges()
		var product := str(p.get("product", "")).strip_edges()
		var demands_added := int(p.get("demands_added", 0))

		var affected_ids: Array[String] = []
		var affected_numbers: Array[String] = []
		var affected_val = p.get("affected_houses", null)
		if affected_val is Array:
			for hid_val in Array(affected_val):
				var hid := str(hid_val).strip_edges()
				if hid.is_empty():
					continue
				affected_ids.append(hid)
				var hn := _try_get_house_number(houses_by_id, hid)
				if not hn.is_empty():
					affected_numbers.append(hn)

		var pos_arr: Array = []
		var wp_val = p.get("world_pos", null)
		if wp_val is Vector2i:
			var wp: Vector2i = wp_val
			pos_arr = [wp.x, wp.y]
		elif wp_val is Array:
			pos_arr = Array(wp_val)

		out.append({
			"type": EventBus.EventType.DEMAND_GENERATED,
			"data": {
				"round": int(marketing_state.round_number),
				"player_id": owner,
				"board_number": board_number,
				"marketing_type": marketing_type,
				"employee_type": employee_type,
				"product": product,
				"demands_added": demands_added,
				"affected_houses": affected_ids,
				"affected_house_numbers": affected_numbers,
				"position": pos_arr,
			}
		})

	return out

static func build_marketing_expired_events(marketing_state: GameState) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if marketing_state == null:
		return out
	if not (marketing_state.round_state is Dictionary):
		return out

	var marketing_val = Dictionary(marketing_state.round_state).get("marketing", null)
	if not (marketing_val is Dictionary):
		return out
	var marketing: Dictionary = marketing_val
	var processed_val = marketing.get("processed", null)
	if not (processed_val is Array):
		return out

	var round := int(marketing_state.round_number)

	for p_val in Array(processed_val):
		if not (p_val is Dictionary):
			continue
		var p: Dictionary = p_val
		if not bool(p.get("expired", false)):
			continue

		var board_number := int(p.get("board_number", 0))
		var owner := int(p.get("owner", -1))
		if owner < 0:
			continue
		var marketing_type := str(p.get("type", "")).strip_edges()
		var employee_type := str(p.get("employee_type", "")).strip_edges()
		var product := str(p.get("product", "")).strip_edges()

		var pos_arr: Array = []
		var wp_val = p.get("world_pos", null)
		if wp_val is Vector2i:
			var wp: Vector2i = wp_val
			pos_arr = [wp.x, wp.y]
		elif wp_val is Array:
			pos_arr = Array(wp_val)

		out.append({
			"type": EventBus.EventType.MARKETING_EXPIRED,
			"data": {
				"round": round,
				"player_id": owner,
				"board_number": board_number,
				"marketing_type": marketing_type,
				"employee_type": employee_type,
				"product": product,
				"position": pos_arr,
				"duration_before": int(p.get("duration_before", 0)),
				"duration_after": int(p.get("duration_after", 0)),
			}
		})

	return out

static func _try_get_house_number(houses_by_id: Dictionary, house_id: String) -> String:
	if houses_by_id == null or houses_by_id.is_empty():
		return ""
	var hid := str(house_id).strip_edges()
	if hid.is_empty():
		return ""
	if not houses_by_id.has(hid):
		return ""
	var h_val = houses_by_id.get(hid, null)
	if not (h_val is Dictionary):
		return ""
	var h: Dictionary = h_val
	return HouseNumberManagerClass.format_display_label(h.get("house_number", null), hid, "")
