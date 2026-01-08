extends RefCounted

const StateUpdaterClass = preload("res://core/state/state_updater.gd")
const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")

func register(registrar) -> Result:
	# Milestone effects.type handlers（严格模式：缺失则 init fail）
	var r = registrar.register_milestone_effect("gain_card", Callable(self, "_milestone_effect_gain_card"))
	if not r.ok:
		return r
	r = registrar.register_milestone_effect("gain_cards", Callable(self, "_milestone_effect_gain_cards"))
	if not r.ok:
		return r
	r = registrar.register_milestone_effect("peek_reserve_cards", Callable(self, "_milestone_effect_peek_reserve_cards"))
	if not r.ok:
		return r
	r = registrar.register_milestone_effect("ban_card", Callable(self, "_milestone_effect_ban_card"))
	if not r.ok:
		return r
	r = registrar.register_milestone_effect("multi_trainer_on_one", Callable(self, "_milestone_effect_multi_trainer_on_one"))
	if not r.ok:
		return r
	r = registrar.register_milestone_effect("base_price_delta", Callable(self, "_milestone_effect_noop"))
	if not r.ok:
		return r
	r = registrar.register_milestone_effect("sell_bonus", Callable(self, "_milestone_effect_noop"))
	if not r.ok:
		return r
	r = registrar.register_milestone_effect("salary_total_delta", Callable(self, "_milestone_effect_noop"))
	if not r.ok:
		return r
	r = registrar.register_milestone_effect("gain_fridge", Callable(self, "_milestone_effect_noop"))
	if not r.ok:
		return r
	r = registrar.register_milestone_effect("waitress_tips", Callable(self, "_milestone_effect_noop"))
	if not r.ok:
		return r
	r = registrar.register_milestone_effect("procure_plus_one", Callable(self, "_milestone_effect_noop"))
	if not r.ok:
		return r
	r = registrar.register_milestone_effect("drinks_per_source_delta", Callable(self, "_milestone_effect_noop"))
	if not r.ok:
		return r
	r = registrar.register_milestone_effect("distance_plus_one", Callable(self, "_milestone_effect_noop"))
	if not r.ok:
		return r
	r = registrar.register_milestone_effect("marketing_no_salary", Callable(self, "_milestone_effect_noop"))
	if not r.ok:
		return r
	r = registrar.register_milestone_effect("marketing_permanent", Callable(self, "_milestone_effect_noop"))
	if not r.ok:
		return r
	r = registrar.register_milestone_effect("turnorder_empty_slots", Callable(self, "_milestone_effect_noop"))
	if not r.ok:
		return r
	r = registrar.register_milestone_effect("ceo_get_cfo", Callable(self, "_milestone_effect_ceo_get_cfo"))
	if not r.ok:
		return r
	r = registrar.register_milestone_effect("extra_marketing", Callable(self, "_milestone_effect_noop"))
	if not r.ok:
		return r
	r = registrar.register_milestone_effect("noop", Callable(self, "_milestone_effect_noop"))
	if not r.ok:
		return r

	return Result.success()

func _milestone_effect_noop(_state: GameState, _player_id: int, _milestone_id: String, _effect: Dictionary) -> Result:
	return Result.success()

func _milestone_effect_gain_card(state: GameState, player_id: int, milestone_id: String, effect: Dictionary) -> Result:
	var value_val = effect.get("value", null)
	if not (value_val is String):
		return Result.failure("MilestoneEffect.gain_card: %s.value 类型错误（期望 String）" % milestone_id)
	var employee_id: String = str(value_val)
	if employee_id.is_empty():
		return Result.failure("MilestoneEffect.gain_card: %s.value 不能为空" % milestone_id)
	return _grant_employee_cards_to_reserve(state, player_id, milestone_id, [employee_id])

func _milestone_effect_gain_cards(state: GameState, player_id: int, milestone_id: String, effect: Dictionary) -> Result:
	var value_val = effect.get("value", null)
	if not (value_val is Array):
		return Result.failure("MilestoneEffect.gain_cards: %s.value 类型错误（期望 Array[String]）" % milestone_id)
	var value: Array = value_val
	if value.is_empty():
		return Result.failure("MilestoneEffect.gain_cards: %s.value 不能为空" % milestone_id)
	var ids: Array[String] = []
	for i in range(value.size()):
		var item = value[i]
		if not (item is String):
			return Result.failure("MilestoneEffect.gain_cards: %s.value[%d] 类型错误（期望 String）" % [milestone_id, i])
		var employee_id: String = str(item)
		if employee_id.is_empty():
			return Result.failure("MilestoneEffect.gain_cards: %s.value[%d] 不能为空" % [milestone_id, i])
		ids.append(employee_id)
	return _grant_employee_cards_to_reserve(state, player_id, milestone_id, ids)

func _milestone_effect_peek_reserve_cards(state: GameState, player_id: int, _milestone_id: String, _effect: Dictionary) -> Result:
	if state == null:
		return Result.failure("MilestoneEffect.peek_reserve_cards: state 为空")
	if not (state.players is Array):
		return Result.failure("MilestoneEffect.peek_reserve_cards: state.players 类型错误（期望 Array）")
	if player_id < 0 or player_id >= state.players.size():
		return Result.failure("MilestoneEffect.peek_reserve_cards: player_id 越界: %d" % player_id)

	var player_val = state.players[player_id]
	if not (player_val is Dictionary):
		return Result.failure("MilestoneEffect.peek_reserve_cards: players[%d] 类型错误（期望 Dictionary）" % player_id)
	var player: Dictionary = player_val
	player["can_peek_all_reserve_cards"] = true
	state.players[player_id] = player
	return Result.success()

func _milestone_effect_ban_card(state: GameState, player_id: int, milestone_id: String, effect: Dictionary) -> Result:
	if state == null:
		return Result.failure("MilestoneEffect.ban_card: state 为空")
	if not (state.players is Array):
		return Result.failure("MilestoneEffect.ban_card: state.players 类型错误（期望 Array）")
	if not (state.employee_pool is Dictionary):
		return Result.failure("MilestoneEffect.ban_card: state.employee_pool 类型错误（期望 Dictionary）")
	if player_id < 0 or player_id >= state.players.size():
		return Result.failure("MilestoneEffect.ban_card: player_id 越界: %d" % player_id)

	var target_val = effect.get("target", null)
	if not (target_val is String):
		return Result.failure("MilestoneEffect.ban_card: %s.target 类型错误（期望 String）" % milestone_id)
	var target: String = str(target_val)
	if target.is_empty():
		return Result.failure("MilestoneEffect.ban_card: %s.target 不能为空" % milestone_id)

	if not state.employee_pool.has(target):
		return Result.failure("MilestoneEffect.ban_card: %s 不在 employee_pool（不应出现）" % target)

	var player_val = state.players[player_id]
	if not (player_val is Dictionary):
		return Result.failure("MilestoneEffect.ban_card: players[%d] 类型错误（期望 Dictionary）" % player_id)
	var player: Dictionary = player_val

	var banned_val = player.get("banned_employee_ids", [])
	if not (banned_val is Array):
		return Result.failure("MilestoneEffect.ban_card: player.banned_employee_ids 类型错误（期望 Array[String]）")
	var banned: Array = banned_val
	for i in range(banned.size()):
		if not (banned[i] is String):
			return Result.failure("MilestoneEffect.ban_card: banned_employee_ids[%d] 类型错误（期望 String）" % i)
	if not banned.has(target):
		banned.append(target)
	player["banned_employee_ids"] = banned

	var removed := 0
	removed += _remove_all_from_array(player, "employees", target)
	removed += _remove_all_from_array(player, "reserve_employees", target)
	removed += _remove_all_from_array(player, "busy_marketers", target)

	state.players[player_id] = player

	if removed > 0:
		var back := StateUpdaterClass.return_to_pool(state, target, removed)
		if not back.ok:
			return back

	return Result.success({"removed": removed})

func _milestone_effect_multi_trainer_on_one(state: GameState, player_id: int, _milestone_id: String, _effect: Dictionary) -> Result:
	if state == null:
		return Result.failure("MilestoneEffect.multi_trainer_on_one: state 为空")
	if not (state.players is Array):
		return Result.failure("MilestoneEffect.multi_trainer_on_one: state.players 类型错误（期望 Array）")
	if player_id < 0 or player_id >= state.players.size():
		return Result.failure("MilestoneEffect.multi_trainer_on_one: player_id 越界: %d" % player_id)

	var player_val = state.players[player_id]
	if not (player_val is Dictionary):
		return Result.failure("MilestoneEffect.multi_trainer_on_one: players[%d] 类型错误（期望 Dictionary）" % player_id)
	var player: Dictionary = player_val
	player["multi_trainer_on_one"] = true
	state.players[player_id] = player
	return Result.success()

func _milestone_effect_ceo_get_cfo(state: GameState, player_id: int, _milestone_id: String, _effect: Dictionary) -> Result:
	if state == null:
		return Result.failure("MilestoneEffect.ceo_get_cfo: state 为空")
	if not (state.players is Array):
		return Result.failure("MilestoneEffect.ceo_get_cfo: state.players 类型错误（期望 Array）")
	if player_id < 0 or player_id >= state.players.size():
		return Result.failure("MilestoneEffect.ceo_get_cfo: player_id 越界: %d" % player_id)

	var player_val = state.players[player_id]
	if not (player_val is Dictionary):
		return Result.failure("MilestoneEffect.ceo_get_cfo: players[%d] 类型错误（期望 Dictionary）" % player_id)
	var player: Dictionary = player_val
	player["ceo_cfo_ability_start_round"] = state.round_number + 1
	state.players[player_id] = player
	return Result.success()

func _remove_all_from_array(player: Dictionary, key: String, item) -> int:
	assert(player.has(key) and (player[key] is Array), "MilestoneEffect: player.%s 缺失或类型错误（期望 Array）" % key)
	var removed := 0
	while StateUpdaterClass.remove_from_array(player, key, item):
		removed += 1
	return removed

func _grant_employee_cards_to_reserve(state: GameState, player_id: int, milestone_id: String, employee_ids: Array[String]) -> Result:
	if state == null:
		return Result.failure("MilestoneEffect.gain_cards: state 为空")
	if not (state.players is Array):
		return Result.failure("MilestoneEffect.gain_cards: state.players 类型错误（期望 Array）")
	if not (state.employee_pool is Dictionary):
		return Result.failure("MilestoneEffect.gain_cards: state.employee_pool 类型错误（期望 Dictionary）")
	if player_id < 0 or player_id >= state.players.size():
		return Result.failure("MilestoneEffect.gain_cards: player_id 越界: %d" % player_id)
	if employee_ids.is_empty():
		return Result.failure("MilestoneEffect.gain_cards: employee_ids 不能为空")

	var player_val = state.players[player_id]
	if not (player_val is Dictionary):
		return Result.failure("MilestoneEffect.gain_cards: players[%d] 类型错误（期望 Dictionary）" % player_id)
	var player: Dictionary = player_val

	var banned_val = player.get("banned_employee_ids", [])
	if not (banned_val is Array):
		return Result.failure("MilestoneEffect.gain_cards: player.banned_employee_ids 类型错误（期望 Array[String]）")
	var banned: Array = banned_val

	for i in range(employee_ids.size()):
		var employee_id: String = employee_ids[i]
		if employee_id.is_empty():
			return Result.failure("MilestoneEffect.gain_cards: employee_ids[%d] 不能为空" % i)
		if banned.has(employee_id):
			return Result.failure("MilestoneEffect.gain_cards: %s 禁止获得员工: %s" % [milestone_id, employee_id])
		if not state.employee_pool.has(employee_id):
			return Result.failure("MilestoneEffect.gain_cards: %s 不在 employee_pool（不应出现）" % employee_id)

		var def_val = EmployeeRegistryClass.get_def(employee_id)
		if def_val == null:
			return Result.failure("MilestoneEffect.gain_cards: 未知员工定义: %s" % employee_id)
		if not (def_val is EmployeeDef):
			return Result.failure("MilestoneEffect.gain_cards: 员工定义类型错误（期望 EmployeeDef）: %s" % employee_id)
		var def: EmployeeDef = def_val
		if def.unique:
			var owned := _count_employee_in_player(player, employee_id)
			if owned > 0:
				return Result.failure("MilestoneEffect.gain_cards: unique 员工已存在，不能重复获得: %s" % employee_id)

		var take := StateUpdaterClass.take_from_pool(state, employee_id, 1)
		if not take.ok:
			return Result.failure("MilestoneEffect.gain_cards: 从员工池取出失败（不应缺货）: %s: %s" % [employee_id, take.error])
		StateUpdaterClass.append_to_array(player, "reserve_employees", employee_id)

	state.players[player_id] = player
	return Result.success({"count": employee_ids.size()})

func _count_employee_in_player(player: Dictionary, employee_id: String) -> int:
	var total := 0
	for key in ["employees", "reserve_employees", "busy_marketers"]:
		assert(player.has(key) and (player[key] is Array), "MilestoneEffect: player.%s 缺失或类型错误（期望 Array）" % key)
		var list: Array = player[key]
		for i in range(list.size()):
			if list[i] is String and str(list[i]) == employee_id:
				total += 1
	return total

