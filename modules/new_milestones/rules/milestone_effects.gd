extends RefCounted

const UtilsClass = preload("res://modules/new_milestones/rules/utils.gd")

const PhaseManagerClass = preload("res://core/engine/phase_manager.gd")
const PhaseDefsClass = preload("res://core/engine/phase_manager/definitions.gd")

const Phase = PhaseDefsClass.Phase
const HookType = PhaseManagerClass.HookType

func register(registrar) -> Result:
	# === 里程碑 effects.type（Strict Mode：缺失则 init fail）===
	var r = registrar.register_milestone_effect("train_from_active_same_color", Callable(self, "_milestone_effect_train_from_active_same_color"))
	if not r.ok:
		return r
	r = registrar.register_milestone_effect("salary_pay_with_tokens", Callable(self, "_milestone_effect_salary_pay_with_tokens"))
	if not r.ok:
		return r
	r = registrar.register_milestone_effect("salary_allow_unpaid", Callable(self, "_milestone_effect_salary_allow_unpaid"))
	if not r.ok:
		return r
	r = registrar.register_milestone_effect("salary_cost_override", Callable(self, "_milestone_effect_salary_cost_override"))
	if not r.ok:
		return r
	r = registrar.register_milestone_effect("employee_no_salary", Callable(self, "_milestone_effect_employee_no_salary"))
	if not r.ok:
		return r
	r = registrar.register_milestone_effect("bank_burn_on_discount_ge_3", Callable(self, "_milestone_effect_bank_burn_on_discount_ge_3"))
	if not r.ok:
		return r

	# FIRST DISCOUNT MANAGER USED：在下回合 Restructuring 结束时移除银行资金
	r = registrar.register_phase_hook(Phase.RESTRUCTURING, HookType.BEFORE_EXIT, Callable(self, "_on_restructuring_before_exit"), 150)
	if not r.ok:
		return r

	return Result.success()

func _milestone_effect_train_from_active_same_color(state: GameState, player_id: int, _milestone_id: String, _effect: Dictionary) -> Result:
	if state == null:
		return Result.failure("new_milestones:train_from_active_same_color: state 为空")
	if not (state.players is Array):
		return Result.failure("new_milestones:train_from_active_same_color: state.players 类型错误（期望 Array）")
	if player_id < 0 or player_id >= state.players.size():
		return Result.failure("new_milestones:train_from_active_same_color: player_id 越界: %d" % player_id)
	var p_val = state.players[player_id]
	if not (p_val is Dictionary):
		return Result.failure("new_milestones:train_from_active_same_color: players[%d] 类型错误（期望 Dictionary）" % player_id)
	var p: Dictionary = p_val
	p["train_from_active_same_color"] = true
	state.players[player_id] = p
	return Result.success()

func _milestone_effect_salary_pay_with_tokens(state: GameState, player_id: int, _milestone_id: String, _effect: Dictionary) -> Result:
	if state == null:
		return Result.failure("new_milestones:salary_pay_with_tokens: state 为空")
	if not (state.players is Array):
		return Result.failure("new_milestones:salary_pay_with_tokens: state.players 类型错误（期望 Array）")
	if player_id < 0 or player_id >= state.players.size():
		return Result.failure("new_milestones:salary_pay_with_tokens: player_id 越界: %d" % player_id)
	var p_val = state.players[player_id]
	if not (p_val is Dictionary):
		return Result.failure("new_milestones:salary_pay_with_tokens: players[%d] 类型错误（期望 Dictionary）" % player_id)
	var p: Dictionary = p_val
	p["salary_pay_with_tokens"] = true
	state.players[player_id] = p
	return Result.success()

func _milestone_effect_salary_allow_unpaid(state: GameState, player_id: int, _milestone_id: String, _effect: Dictionary) -> Result:
	if state == null:
		return Result.failure("new_milestones:salary_allow_unpaid: state 为空")
	if not (state.players is Array):
		return Result.failure("new_milestones:salary_allow_unpaid: state.players 类型错误（期望 Array）")
	if player_id < 0 or player_id >= state.players.size():
		return Result.failure("new_milestones:salary_allow_unpaid: player_id 越界: %d" % player_id)
	var p_val = state.players[player_id]
	if not (p_val is Dictionary):
		return Result.failure("new_milestones:salary_allow_unpaid: players[%d] 类型错误（期望 Dictionary）" % player_id)
	var p: Dictionary = p_val
	p["salary_allow_unpaid"] = true
	state.players[player_id] = p
	return Result.success()

func _milestone_effect_salary_cost_override(state: GameState, player_id: int, milestone_id: String, effect: Dictionary) -> Result:
	if state == null:
		return Result.failure("new_milestones:salary_cost_override: state 为空")
	if not (state.players is Array):
		return Result.failure("new_milestones:salary_cost_override: state.players 类型错误（期望 Array）")
	if player_id < 0 or player_id >= state.players.size():
		return Result.failure("new_milestones:salary_cost_override: player_id 越界: %d" % player_id)

	var value_val = effect.get("value", null)
	var v := 0
	if value_val is int:
		v = int(value_val)
	elif value_val is float:
		var f: float = float(value_val)
		if f != floor(f):
			return Result.failure("new_milestones:salary_cost_override: %s.value 类型错误（期望 int）" % milestone_id)
		v = int(f)
	else:
		return Result.failure("new_milestones:salary_cost_override: %s.value 类型错误（期望 int）" % milestone_id)
	if v < 0:
		return Result.failure("new_milestones:salary_cost_override: %s.value 不能为负数: %d" % [milestone_id, v])

	var p_val = state.players[player_id]
	if not (p_val is Dictionary):
		return Result.failure("new_milestones:salary_cost_override: players[%d] 类型错误（期望 Dictionary）" % player_id)
	var p: Dictionary = p_val
	p["salary_cost_override"] = v
	state.players[player_id] = p
	return Result.success()

func _milestone_effect_employee_no_salary(state: GameState, player_id: int, milestone_id: String, effect: Dictionary) -> Result:
	if state == null:
		return Result.failure("new_milestones:employee_no_salary: state 为空")
	if not (state.players is Array):
		return Result.failure("new_milestones:employee_no_salary: state.players 类型错误（期望 Array）")
	if player_id < 0 or player_id >= state.players.size():
		return Result.failure("new_milestones:employee_no_salary: player_id 越界: %d" % player_id)

	var target_val = effect.get("target", null)
	if not (target_val is String):
		return Result.failure("new_milestones:employee_no_salary: %s.target 类型错误（期望 String）" % milestone_id)
	var target: String = str(target_val)
	if target.is_empty():
		return Result.failure("new_milestones:employee_no_salary: %s.target 不能为空" % milestone_id)

	var p_val = state.players[player_id]
	if not (p_val is Dictionary):
		return Result.failure("new_milestones:employee_no_salary: players[%d] 类型错误（期望 Dictionary）" % player_id)
	var p: Dictionary = p_val
	var list_val = p.get("no_salary_employee_ids", [])
	if not (list_val is Array):
		return Result.failure("new_milestones:employee_no_salary: player.no_salary_employee_ids 类型错误（期望 Array[String]）")
	var ids: Array = list_val
	if not ids.has(target):
		ids.append(target)
	p["no_salary_employee_ids"] = ids
	state.players[player_id] = p
	return Result.success()

func _milestone_effect_bank_burn_on_discount_ge_3(state: GameState, player_id: int, _milestone_id: String, _effect: Dictionary) -> Result:
	if state == null:
		return Result.failure("new_milestones:bank_burn_on_discount_ge_3: state 为空")
	if not (state.players is Array):
		return Result.failure("new_milestones:bank_burn_on_discount_ge_3: state.players 类型错误（期望 Array）")
	if player_id < 0 or player_id >= state.players.size():
		return Result.failure("new_milestones:bank_burn_on_discount_ge_3: player_id 越界: %d" % player_id)
	var p_val = state.players[player_id]
	if not (p_val is Dictionary):
		return Result.failure("new_milestones:bank_burn_on_discount_ge_3: players[%d] 类型错误（期望 Dictionary）" % player_id)
	var p: Dictionary = p_val
	p["bank_burn_on_discount_ge_3"] = true
	state.players[player_id] = p
	return Result.success()

func _on_restructuring_before_exit(state: GameState) -> Result:
	if state == null:
		return Result.failure("new_milestones:bank_burn: state 为空")
	if not (state.bank is Dictionary):
		return Result.failure("new_milestones:bank_burn: state.bank 类型错误（期望 Dictionary）")
	if not (state.players is Array):
		return Result.failure("new_milestones:bank_burn: state.players 类型错误（期望 Array）")
	if not (state.round_state is Dictionary):
		return Result.failure("new_milestones:bank_burn: state.round_state 类型错误（期望 Dictionary）")

	var removed: Array[Dictionary] = []
	for pid in range(state.players.size()):
		var p_val = state.players[pid]
		if not (p_val is Dictionary):
			return Result.failure("new_milestones:bank_burn: players[%d] 类型错误（期望 Dictionary）" % pid)
		var p: Dictionary = p_val
		if not bool(p.get("bank_burn_on_discount_ge_3", false)):
			continue
		if not bool(p.get("bank_burn_pending", false)):
			continue

		var bank_total := int(state.bank.get("total", 0))
		var burn := mini(100, maxi(0, bank_total))
		state.bank["total"] = bank_total - burn
		state.bank["removed_total"] = int(state.bank.get("removed_total", 0)) + burn
		p["bank_burn_pending"] = false
		state.players[pid] = p
		removed.append({"player_id": pid, "amount": burn})

	if not removed.is_empty():
		state.round_state["new_milestones_bank_burn"] = removed

	return Result.success()

