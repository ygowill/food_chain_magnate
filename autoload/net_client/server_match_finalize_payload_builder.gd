extends RefCounted

const EventHistoryRebuildClass = preload("res://core/engine/game_engine/event_history_rebuild.gd")
const ServerLogFormatClass = preload("res://autoload/net_client/server_log_format.gd")

static func build_match_summary_payload(state) -> Dictionary:
	var modules: Array[String] = []
	if state != null and (state.modules is Array):
		for module_val in Array(state.modules):
			var module_id := str(module_val).strip_edges()
			if module_id.is_empty():
				continue
			modules.append(module_id)

	var bank: Dictionary = {}
	if state != null and (state.bank is Dictionary):
		var b: Dictionary = Dictionary(state.bank)
		bank = {
			"total": int(b.get("total", 0)),
			"broke_count": int(b.get("broke_count", 0)),
			"reserve_added_total": int(b.get("reserve_added_total", 0)),
		}

	var marketing_instances: Array = []
	if state != null and (state.marketing_instances is Array):
		marketing_instances = Array(state.marketing_instances).duplicate(true)

	return {
		"modules": modules,
		"round_number": int(state.round_number) if state != null else 0,
		"bank": bank,
		"marketing_instances": marketing_instances,
	}

static func build_finalize_participants(room, state, winner_player_id: int) -> Array:
	var participants: Array = []
	if room == null:
		return participants
	if not (room._seat_profile_by_seat_index is Dictionary):
		return participants

	var seat_indices: Array[int] = []
	for seat_key in room._seat_profile_by_seat_index.keys():
		seat_indices.append(int(seat_key))
	seat_indices.sort()

	for seat_index in seat_indices:
		var user_id := ""
		if room._user_id_by_seat_index is Dictionary:
			user_id = str(room._user_id_by_seat_index.get(seat_index, "")).strip_edges()
		if user_id.is_empty():
			GameLog.warn(
				"NetClient",
				"Finalize skip participant without user_id room=%s seat=%d"
					% [ServerLogFormatClass.safe_text(str(room.room_code)), seat_index]
			)
			continue

		var score_payload := build_participant_score_payload(room, state, seat_index)
		var player_ordinal := _resolve_player_ordinal(room, state, seat_index)
		var forfeited := bool(score_payload.get("forfeited", false))
		var result := "lose"
		if forfeited:
			result = "forfeit"
		elif winner_player_id < 0:
			result = "draw"
		elif player_ordinal == winner_player_id:
			result = "win"

		participants.append({
			"user_id": user_id,
			"role": "player",
			"seat_index": seat_index,
			"result": result,
			"score_json": JSON.stringify(score_payload),
		})

	return participants

static func _get_ordered_seat_indices(room) -> Array[int]:
	var ordered_seat_indices: Array[int] = []
	if room != null and (room._seat_profile_by_seat_index is Dictionary):
		for seat_key in room._seat_profile_by_seat_index.keys():
			ordered_seat_indices.append(int(seat_key))
	elif room != null and (room._user_id_by_seat_index is Dictionary):
		for seat_key in room._user_id_by_seat_index.keys():
			ordered_seat_indices.append(int(seat_key))
	ordered_seat_indices.sort()
	return ordered_seat_indices

static func _resolve_player_ordinal(room, state, seat_index: int) -> int:
	if state == null or not (state.players is Array):
		return -1
	var ordered_seat_indices := _get_ordered_seat_indices(room)
	if ordered_seat_indices.size() == state.players.size():
		return ordered_seat_indices.find(seat_index)
	if seat_index >= 0 and seat_index < state.players.size():
		return seat_index
	return -1

static func _resolve_player_dict(room, state, seat_index: int) -> Dictionary:
	if state == null or not (state.players is Array):
		return {}
	var ordinal := _resolve_player_ordinal(room, state, seat_index)
	if ordinal < 0 or ordinal >= state.players.size():
		return {}
	var fallback_val = state.players[ordinal]
	if fallback_val is Dictionary:
		return Dictionary(fallback_val)
	return {}

static func _canonicalize_product_key(product_id: String) -> String:
	var normalized := str(product_id).strip_edges().to_lower()
	if normalized == "coke" or normalized == "cola":
		return "soda"
	return normalized

static func _append_count(target: Dictionary, key: String, amount: int = 1) -> void:
	var stat_key := str(key).strip_edges()
	if stat_key.is_empty():
		return
	var delta := int(amount)
	if delta == 0:
		return
	target[stat_key] = int(target.get(stat_key, 0)) + delta

static func _build_participant_stats_payload(room, state, seat_index: int) -> Dictionary:
	if room == null or state == null:
		return {}
	if room.game_engine == null:
		return {}

	var player_ordinal := _resolve_player_ordinal(room, state, seat_index)
	if player_ordinal < 0:
		return {}

	var history_r := EventHistoryRebuildClass.build(room.game_engine, int(room.game_engine.current_command_index))
	if not history_r.ok:
		GameLog.warn(
			"NetClient",
			"Finalize stats rebuild failed room=%s seat=%d err=%s"
				% [ServerLogFormatClass.safe_text(str(room.room_code)), seat_index, str(history_r.error)]
		)
		return {}
	if not (history_r.value is Array):
		return {}

	var marketing_by_type: Dictionary = {}
	var produced: Dictionary = {}
	var sold: Dictionary = {}
	var metrics: Dictionary = {}
	var marketing_actions := 0
	var hired_employees := 0
	var trained_employees := 0

	for event_val in Array(history_r.value):
		if not (event_val is Dictionary):
			continue
		var event: Dictionary = event_val
		var event_type := str(event.get("type", "")).strip_edges()
		if event_type.is_empty():
			continue
		var data_val = event.get("data", null)
		var data: Dictionary = data_val if (data_val is Dictionary) else {}
		var event_player_id := int(data.get("player_id", data.get("actor", -1)))
		if event_player_id != player_ordinal:
			continue

		match event_type:
			"employee_recruited":
				hired_employees += 1
			"employee_trained":
				trained_employees += 1
			"marketing_placed":
				marketing_actions += 1
				_append_count(marketing_by_type, str(data.get("marketing_type", "")).strip_edges())
			"food_produced":
				var produced_key := _canonicalize_product_key(str(data.get("food_type", "")))
				if not produced_key.is_empty():
					_append_count(produced, produced_key, int(data.get("amount", 0)))
			"food_sold":
				var quantity := maxi(1, int(data.get("quantity", 1)))
				var required_val = data.get("required", null)
				if required_val is Dictionary:
					var required: Dictionary = required_val
					for product_key in required.keys():
						var sold_key := _canonicalize_product_key(str(product_key))
						if sold_key.is_empty():
							continue
						_append_count(sold, sold_key, int(required.get(product_key, 0)) * quantity)
			"house_placed":
				_append_count(metrics, "house_built")
			"garden_added":
				_append_count(metrics, "garden_built")
			"restaurant_placed":
				_append_count(metrics, "restaurant_built")
			"restaurant_moved":
				_append_count(metrics, "restaurant_moved")
			"drinks_procured":
				_append_count(metrics, "procurement_actions")
			"command_executed":
				var action_id := str(data.get("action_id", "")).strip_edges()
				if action_id == "place_lobbyists_road" or action_id == "place_lobbyists_park":
					_append_count(metrics, "lobbyists_actions")

	return {
		"marketing_actions": marketing_actions,
		"billboard_placements": int(marketing_by_type.get("billboard", 0)),
		"hired_employees": hired_employees,
		"trained_employees": trained_employees,
		"marketing_by_type": marketing_by_type,
		"metrics": metrics,
		"produced": produced,
		"sold": sold,
	}

static func build_participant_score_payload(room, state, seat_index: int) -> Dictionary:
	var seat_profile: Dictionary = {}
	if room != null and (room._seat_profile_by_seat_index is Dictionary):
		seat_profile = Dictionary(room._seat_profile_by_seat_index.get(seat_index, {}))

	var player: Dictionary = _resolve_player_dict(room, state, seat_index)

	var employees: Array = []
	var employees_val = player.get("employees", null)
	if employees_val is Array:
		employees = Array(employees_val).duplicate(true)

	var reserve_employees: Array = []
	var reserve_val = player.get("reserve_employees", null)
	if reserve_val is Array:
		reserve_employees = Array(reserve_val).duplicate(true)

	var busy_marketers: Array = []
	var busy_val = player.get("busy_marketers", null)
	if busy_val is Array:
		busy_marketers = Array(busy_val).duplicate(true)

	var restaurants: Array = []
	var restaurants_val = player.get("restaurants", null)
	if restaurants_val is Array:
		restaurants = Array(restaurants_val).duplicate(true)

	var milestones: Array = []
	var milestones_val = player.get("milestones", null)
	if milestones_val is Array:
		milestones = Array(milestones_val).duplicate(true)

	var inventory: Dictionary = {}
	var inventory_val = player.get("inventory", null)
	if inventory_val is Dictionary:
		inventory = Dictionary(inventory_val).duplicate(true)

	var restaurant_logo_id := -1
	var player_logo_val = player.get("restaurant_logo_id", null)
	if player_logo_val is int:
		restaurant_logo_id = int(player_logo_val)
	elif player_logo_val is float:
		var player_logo_float: float = float(player_logo_val)
		if player_logo_float == floor(player_logo_float):
			restaurant_logo_id = int(player_logo_float)
	if restaurant_logo_id < 0:
		restaurant_logo_id = int(seat_profile.get("restaurant_logo_id", -1))

	var stats_payload := _build_participant_stats_payload(room, state, seat_index)

	return {
		"display_name": str(seat_profile.get("name", "Player %d" % [seat_index + 1])),
		"restaurant_logo_id": restaurant_logo_id,
		"cash": int(player.get("cash", 0)),
		"forfeited": bool(player.get("forfeited", false)),
		"employees": employees,
		"reserve_employees": reserve_employees,
		"busy_marketers": busy_marketers,
		"restaurants": restaurants,
		"milestones": milestones,
		"inventory": inventory,
		"stats": stats_payload,
	}
