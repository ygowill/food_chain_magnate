# 营销结算动画：从结算数据构建自动播放的广告序列
class_name MarketingAnimationOrdersBuilder
extends RefCounted

static func build_orders_from_settlement(marketing: Dictionary) -> Array[Dictionary]:
	var events_val = marketing.get("timeline_events", [])
	if events_val is Array and not (events_val as Array).is_empty():
		return _build_orders_from_timeline(events_val as Array)
	return _build_orders_from_processed(marketing)

static func _build_orders_from_timeline(events: Array) -> Array[Dictionary]:
	var orders: Array[Dictionary] = []
	var order_by_key: Dictionary = {}
	var last_key_by_board: Dictionary = {}

	for evt_val in events:
		if not (evt_val is Dictionary):
			continue
		var evt: Dictionary = evt_val
		var kind := str(evt.get("kind", "")).strip_edges()
		if kind == "campaign_start":
			var key := _campaign_key(evt)
			if not order_by_key.has(key):
				var order := _base_order_from_event(evt)
				order["house_events"] = []
				orders.append(order)
				order_by_key[key] = order
			last_key_by_board[int(evt.get("board_number", 0))] = key
		elif kind == "house_demand":
			var key2 := _campaign_key(evt)
			if not order_by_key.has(key2):
				var order2 := _base_order_from_event(evt)
				order2["house_events"] = []
				orders.append(order2)
				order_by_key[key2] = order2
				last_key_by_board[int(evt.get("board_number", 0))] = key2
			var order_for_house: Dictionary = order_by_key[key2]
			var house_events: Array = order_for_house.get("house_events", [])
			house_events.append(evt.duplicate(true))
			order_for_house["house_events"] = house_events
		elif kind == "duration_tick":
			var board_number := int(evt.get("board_number", 0))
			var duration_key := str(last_key_by_board.get(board_number, ""))
			if duration_key.is_empty() or not order_by_key.has(duration_key):
				duration_key = _campaign_key(evt)
				if not order_by_key.has(duration_key):
					var order3 := _base_order_from_event(evt)
					order3["house_events"] = []
					orders.append(order3)
					order_by_key[duration_key] = order3
			var order_for_duration: Dictionary = order_by_key[duration_key]
			order_for_duration["duration_before"] = int(evt.get("duration_before", order_for_duration.get("duration_before", 0)))
			order_for_duration["duration_after"] = int(evt.get("duration_after", order_for_duration.get("duration_after", 0)))
			order_for_duration["expired"] = bool(evt.get("expired", false))

	return orders

static func _build_orders_from_processed(marketing: Dictionary) -> Array[Dictionary]:
	var orders: Array[Dictionary] = []
	var processed_val = marketing.get("processed", [])
	if not (processed_val is Array):
		return orders
	var processed: Array = processed_val
	for item_val in processed:
		if not (item_val is Dictionary):
			continue
		var item: Dictionary = item_val
		var order := _base_order_from_event(item)
		order["round_index"] = 0
		order["house_events"] = _build_fallback_house_events(item)
		order["duration_before"] = int(item.get("duration_before", 0))
		order["duration_after"] = int(item.get("duration_after", 0))
		order["expired"] = bool(item.get("expired", false))
		orders.append(order)
	return orders

static func _base_order_from_event(evt: Dictionary) -> Dictionary:
	return {
		"round_index": int(evt.get("round_index", 0)),
		"board_number": int(evt.get("board_number", 0)),
		"type": str(evt.get("type", "")),
		"owner": int(evt.get("owner", -1)),
		"employee_type": str(evt.get("employee_type", "")),
		"product": str(evt.get("product", "")),
		"products": _read_products(evt),
		"world_pos": _read_vec2_array(evt.get("world_pos", [0, 0])),
		"footprint_size": _read_vec2_array(evt.get("footprint_size", [1, 1])),
		"rotation": int(evt.get("rotation", 0)),
		"axis": str(evt.get("axis", "")),
		"affected_houses": _read_array(evt.get("affected_houses", [])),
		"demand_amount": int(evt.get("demand_amount", 1)),
		"duration_before": int(evt.get("duration_before", 0)),
		"duration_after": int(evt.get("duration_after", 0)),
		"expired": bool(evt.get("expired", false)),
	}

static func _build_fallback_house_events(item: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var houses := _read_array(item.get("affected_houses", []))
	var remaining_added := int(item.get("demands_added", 0))
	for h_val in houses:
		var house_id := str(h_val)
		if house_id.is_empty():
			continue
		var added := 0
		if remaining_added > 0:
			added = 1
			remaining_added -= 1
		out.append({
			"kind": "house_demand",
			"round_index": 0,
			"board_number": int(item.get("board_number", 0)),
			"type": str(item.get("type", "")),
			"owner": int(item.get("owner", -1)),
			"product": str(item.get("product", "")),
			"house_id": house_id,
			"house_number": house_id,
			"amount_requested": 1,
			"amount_added": added,
			"demand_before": 0,
			"demand_after": added,
			"cap": 0,
		})
	return out

static func _campaign_key(evt: Dictionary) -> String:
	return "%d:%d" % [int(evt.get("round_index", 0)), int(evt.get("board_number", 0))]

static func _read_products(evt: Dictionary) -> Array:
	var products_val = evt.get("products", null)
	if products_val is Array:
		return (products_val as Array).duplicate(true)
	var product := str(evt.get("product", "")).strip_edges()
	if product.is_empty():
		return []
	return [product]

static func _read_array(value) -> Array:
	if value is Array:
		return (value as Array).duplicate(true)
	return []

static func _read_vec2_array(value) -> Array:
	if value is Vector2i:
		var v: Vector2i = value
		return [int(v.x), int(v.y)]
	if value is Vector2:
		var v2: Vector2 = value
		return [int(v2.x), int(v2.y)]
	if value is Array:
		var arr: Array = value
		if arr.size() == 2:
			return [int(arr[0]), int(arr[1])]
	return [0, 0]
