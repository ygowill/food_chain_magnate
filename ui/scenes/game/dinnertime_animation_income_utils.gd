# 晚餐结算动画：收入与事件构建辅助
class_name DinnertimeAnimationIncomeUtils
extends RefCounted

static func build_post_house_income_events(settlement_data: Dictionary, game_state: GameState) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if game_state == null:
		return events
	if not (game_state.players is Array):
		return events

	var tips_by_player := _read_income_by_player(settlement_data, "income_tips")
	var cfo_by_player := _read_income_by_player(settlement_data, "income_cfo_bonus")
	var order := _get_income_animation_player_order(game_state)

	for player_id in order:
		if player_id < 0 or player_id >= game_state.players.size():
			continue
		var tips_amount := int(tips_by_player.get(player_id, 0))
		if tips_amount > 0:
			events.append({
				"player_id": player_id,
				"employee_id": "waitress",
				"kind": "tips",
				"amount": tips_amount,
				"show_card": _player_has_active_employee(game_state, player_id, "waitress"),
			})

		var cfo_amount := int(cfo_by_player.get(player_id, 0))
		if cfo_amount > 0:
			events.append({
				"player_id": player_id,
				"employee_id": "cfo",
				"kind": "cfo",
				"amount": cfo_amount,
				"show_card": _player_has_active_employee(game_state, player_id, "cfo"),
			})

	return events

static func sum_post_income_by_player(events: Array[Dictionary]) -> Dictionary:
	var out: Dictionary = {}
	for event in events:
		var player_id := int(event.get("player_id", -1))
		var amount := int(event.get("amount", 0))
		if player_id < 0 or amount <= 0:
			continue
		out[player_id] = int(out.get(player_id, 0)) + amount
	return out

static func sum_income_dict(income: Dictionary) -> int:
	var total := 0
	for k in income.keys():
		total += int(income.get(k, 0))
	return total

static func get_order_income_amount(order: Dictionary) -> int:
	var revenue := int(order.get("revenue", 0))
	var house_bonus := int(order.get("house_bonus", 0))
	return revenue + house_bonus

static func get_employee_card_name(employee_id: String) -> String:
	match employee_id:
		"waitress":
			return "女服务员"
		"cfo":
			return "CFO"
		_:
			return employee_id

static func _read_income_by_player(settlement_data: Dictionary, key: String) -> Dictionary:
	var out: Dictionary = {}
	if key.is_empty():
		return out
	var val = settlement_data.get(key, null)
	if val is Array:
		var arr: Array = val
		for i in range(arr.size()):
			out[i] = int(arr[i])
		return out
	if val is Dictionary:
		var d: Dictionary = val
		for k in d.keys():
			var pid := int(k)
			if pid < 0:
				continue
			out[pid] = int(d.get(k, 0))
	return out

static func _get_income_animation_player_order(game_state: GameState) -> Array[int]:
	var out: Array[int] = []
	if game_state == null or not (game_state.players is Array):
		return out
	var seen: Dictionary = {}
	if game_state.turn_order is Array:
		for pid_val in game_state.turn_order:
			var pid := int(pid_val)
			if pid < 0 or pid >= game_state.players.size():
				continue
			if seen.has(pid):
				continue
			seen[pid] = true
			out.append(pid)
	for i in range(game_state.players.size()):
		if seen.has(i):
			continue
		out.append(i)
	return out

static func _player_has_active_employee(game_state: GameState, player_id: int, employee_id: String) -> bool:
	if game_state == null:
		return false
	if employee_id.is_empty():
		return false
	if not (game_state.players is Array):
		return false
	if player_id < 0 or player_id >= game_state.players.size():
		return false
	var player_val = game_state.players[player_id]
	if not (player_val is Dictionary):
		return false
	var player: Dictionary = player_val
	var employees_val = player.get("employees", null)
	if not (employees_val is Array):
		return false
	for e in employees_val:
		if str(e).strip_edges() == employee_id:
			return true
	return false
