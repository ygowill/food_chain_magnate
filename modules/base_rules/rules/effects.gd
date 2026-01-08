extends RefCounted

const MilestoneSystemClass = preload("res://core/rules/milestone_system.gd")
const MilestoneRegistryClass = preload("res://core/data/milestone_registry.gd")
const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")

func register(registrar) -> Result:
	var r = registrar.register_effect("base_rules:dinnertime:tiebreaker:waitress", Callable(self, "_effect_dinnertime_tiebreaker_waitress"))
	if not r.ok:
		return r
	r = registrar.register_effect("base_rules:dinnertime:tips:waitress", Callable(self, "_effect_dinnertime_tips_waitress"))
	if not r.ok:
		return r
	r = registrar.register_effect("base_rules:dinnertime:income_bonus:cfo", Callable(self, "_effect_dinnertime_income_bonus_cfo"))
	if not r.ok:
		return r
	r = registrar.register_effect("base_rules:dinnertime:income_bonus:ceo_get_cfo", Callable(self, "_effect_dinnertime_income_bonus_ceo_get_cfo"))
	if not r.ok:
		return r
	r = registrar.register_effect("base_rules:payday:salary_discount:recruiting_manager", Callable(self, "_effect_payday_salary_discount_recruiting_manager"))
	if not r.ok:
		return r
	r = registrar.register_effect("base_rules:payday:salary_discount:hr_director", Callable(self, "_effect_payday_salary_discount_hr_director"))
	if not r.ok:
		return r
	r = registrar.register_effect("base_rules:marketing:demand_amount:first_radio", Callable(self, "_effect_marketing_demand_amount_first_radio"))
	if not r.ok:
		return r
	return Result.success()

func _effect_dinnertime_tiebreaker_waitress(_state: GameState, _player_id: int, ctx: Dictionary) -> Result:
	if not ctx.has("score") or not (ctx["score"] is int):
		return Result.failure("base_rules:tiebreaker: ctx.score 缺失或类型错误（期望 int）")
	ctx["score"] = int(ctx["score"]) + 1
	return Result.success()

func _effect_dinnertime_tips_waitress(state: GameState, player_id: int, ctx: Dictionary) -> Result:
	if not ctx.has("tips") or not (ctx["tips"] is int):
		return Result.failure("base_rules:tips: ctx.tips 缺失或类型错误（期望 int）")
	if not ctx.has("use_employee_triggered") or not (ctx["use_employee_triggered"] is bool):
		return Result.failure("base_rules:tips: ctx.use_employee_triggered 缺失或类型错误（期望 bool）")

	var warnings: Array[String] = []

	if not bool(ctx["use_employee_triggered"]):
		var ms := MilestoneSystemClass.process_event(state, "UseEmployee", {
			"player_id": player_id,
			"id": "waitress"
		})
		if not ms.ok:
			warnings.append("里程碑触发失败(UseEmployee/waitress)：%s" % ms.error)
		ctx["use_employee_triggered"] = true

	var player_val = state.players[player_id]
	if not (player_val is Dictionary):
		return Result.failure("base_rules:tips: player 类型错误: players[%d]（期望 Dictionary）" % player_id)
	var player: Dictionary = player_val
	var milestones_val = player.get("milestones", null)
	if not (milestones_val is Array):
		return Result.failure("base_rules:tips: player[%d].milestones 类型错误（期望 Array）" % player_id)
	var milestones: Array = milestones_val

	var tips_per := state.get_rule_int("waitress_tips")
	var tips_override_read := _get_waitress_tips_override_from_milestones(milestones)
	if not tips_override_read.ok:
		return tips_override_read
	var tips_override: Dictionary = tips_override_read.value
	if bool(tips_override.get("found", false)):
		tips_per = int(tips_override.get("value", tips_per))

	ctx["tips"] = int(ctx["tips"]) + int(tips_per)
	return Result.success().with_warnings(warnings)

func _effect_dinnertime_income_bonus_cfo(state: GameState, _player_id: int, ctx: Dictionary) -> Result:
	if not ctx.has("base_gain") or not (ctx["base_gain"] is int):
		return Result.failure("base_rules:income_bonus: ctx.base_gain 缺失或类型错误（期望 int）")
	if not ctx.has("extra") or not (ctx["extra"] is int):
		return Result.failure("base_rules:income_bonus: ctx.extra 缺失或类型错误（期望 int）")
	if not ctx.has("once") or not (ctx["once"] is Dictionary):
		return Result.failure("base_rules:income_bonus: ctx.once 缺失或类型错误（期望 Dictionary）")

	var once: Dictionary = ctx["once"]
	if once.has("base_rules:dinnertime:income_bonus:cfo"):
		return Result.success()

	var base_gain: int = int(ctx["base_gain"])
	if base_gain <= 0:
		return Result.success()

	var bonus_percent := state.get_rule_int("cfo_bonus_percent")
	var denom := 100
	var extra := int((base_gain * bonus_percent + denom - 1) / denom)  # ceil(base_gain * percent / 100)
	if extra <= 0:
		once["base_rules:dinnertime:income_bonus:cfo"] = true
		ctx["once"] = once
		return Result.success()

	ctx["extra"] = int(ctx["extra"]) + extra
	once["base_rules:dinnertime:income_bonus:cfo"] = true
	ctx["once"] = once
	return Result.success()

func _effect_dinnertime_income_bonus_ceo_get_cfo(state: GameState, player_id: int, ctx: Dictionary) -> Result:
	if not ctx.has("base_gain") or not (ctx["base_gain"] is int):
		return Result.failure("base_rules:income_bonus: ctx.base_gain 缺失或类型错误（期望 int）")
	if not ctx.has("extra") or not (ctx["extra"] is int):
		return Result.failure("base_rules:income_bonus: ctx.extra 缺失或类型错误（期望 int）")
	if not ctx.has("once") or not (ctx["once"] is Dictionary):
		return Result.failure("base_rules:income_bonus: ctx.once 缺失或类型错误（期望 Dictionary）")

	var once: Dictionary = ctx["once"]
	if once.has("base_rules:dinnertime:income_bonus:cfo"):
		return Result.success()

	if player_id < 0 or player_id >= state.players.size():
		return Result.failure("base_rules:income_bonus: player_id 越界: %d" % player_id)
	var player_val = state.players[player_id]
	if not (player_val is Dictionary):
		return Result.failure("base_rules:income_bonus: player 类型错误: players[%d]（期望 Dictionary）" % player_id)
	var player: Dictionary = player_val
	var start_round_val = player.get("ceo_cfo_ability_start_round", null)
	if not (start_round_val is int):
		return Result.failure("base_rules:income_bonus: player.ceo_cfo_ability_start_round 缺失或类型错误（期望 int）")
	var start_round: int = int(start_round_val)
	if start_round < 0:
		return Result.failure("base_rules:income_bonus: ceo_cfo_ability_start_round 不能为负数: %d" % start_round)
	if state.round_number < start_round:
		return Result.success()

	var base_gain: int = int(ctx["base_gain"])
	if base_gain <= 0:
		return Result.success()

	var bonus_percent := state.get_rule_int("cfo_bonus_percent")
	var denom := 100
	var extra := int((base_gain * bonus_percent + denom - 1) / denom)  # ceil(base_gain * percent / 100)
	if extra <= 0:
		once["base_rules:dinnertime:income_bonus:cfo"] = true
		ctx["once"] = once
		return Result.success()

	ctx["extra"] = int(ctx["extra"]) + extra
	once["base_rules:dinnertime:income_bonus:cfo"] = true
	ctx["once"] = once
	return Result.success()

func _effect_payday_salary_discount_recruiting_manager(_state: GameState, _player_id: int, ctx: Dictionary, employee_id: String) -> Result:
	if not ctx.has("salary_discount_recruit_capacity") or not (ctx["salary_discount_recruit_capacity"] is int):
		return Result.failure("base_rules:payday:salary_discount: ctx.salary_discount_recruit_capacity 缺失或类型错误（期望 int）")
	if employee_id.is_empty():
		return Result.failure("base_rules:payday:salary_discount: employee_id 不能为空")
	var def_val = EmployeeRegistryClass.get_def(employee_id)
	if def_val == null:
		return Result.failure("base_rules:payday:salary_discount: 未知员工定义: %s" % employee_id)
	if not (def_val is EmployeeDef):
		return Result.failure("base_rules:payday:salary_discount: 员工定义类型错误（期望 EmployeeDef）: %s" % employee_id)
	var def: EmployeeDef = def_val
	var cap := int(def.recruit_capacity)
	if cap <= 0:
		return Result.failure("base_rules:payday:salary_discount: %s.recruit_capacity 必须 > 0" % employee_id)
	ctx["salary_discount_recruit_capacity"] = int(ctx["salary_discount_recruit_capacity"]) + cap
	return Result.success()

func _effect_payday_salary_discount_hr_director(_state: GameState, _player_id: int, ctx: Dictionary, employee_id: String) -> Result:
	if not ctx.has("salary_discount_recruit_capacity") or not (ctx["salary_discount_recruit_capacity"] is int):
		return Result.failure("base_rules:payday:salary_discount: ctx.salary_discount_recruit_capacity 缺失或类型错误（期望 int）")
	if employee_id.is_empty():
		return Result.failure("base_rules:payday:salary_discount: employee_id 不能为空")
	var def_val = EmployeeRegistryClass.get_def(employee_id)
	if def_val == null:
		return Result.failure("base_rules:payday:salary_discount: 未知员工定义: %s" % employee_id)
	if not (def_val is EmployeeDef):
		return Result.failure("base_rules:payday:salary_discount: 员工定义类型错误（期望 EmployeeDef）: %s" % employee_id)
	var def: EmployeeDef = def_val
	var cap := int(def.recruit_capacity)
	if cap <= 0:
		return Result.failure("base_rules:payday:salary_discount: %s.recruit_capacity 必须 > 0" % employee_id)
	ctx["salary_discount_recruit_capacity"] = int(ctx["salary_discount_recruit_capacity"]) + cap
	return Result.success()

func _effect_marketing_demand_amount_first_radio(_state: GameState, _player_id: int, ctx: Dictionary) -> Result:
	if not ctx.has("marketing_type") or not (ctx["marketing_type"] is String):
		return Result.failure("base_rules:marketing:demand_amount:first_radio: ctx.marketing_type 缺失或类型错误（期望 String）")
	if not ctx.has("demand_amount") or not (ctx["demand_amount"] is int):
		return Result.failure("base_rules:marketing:demand_amount:first_radio: ctx.demand_amount 缺失或类型错误（期望 int）")

	var marketing_type: String = str(ctx["marketing_type"])
	if marketing_type != "radio":
		return Result.success()

	var current: int = int(ctx["demand_amount"])
	ctx["demand_amount"] = maxi(current, 2)
	return Result.success()

func _get_waitress_tips_override_from_milestones(milestones: Array) -> Result:
	var found := false
	var best := 0

	for i in range(milestones.size()):
		var mid_val = milestones[i]
		if not (mid_val is String):
			return Result.failure("base_rules:tips: milestones[%d] 类型错误（期望 String）" % i)
		var mid: String = str(mid_val)
		if mid.is_empty():
			return Result.failure("base_rules:tips: milestones 不应包含空字符串")

		var def_val = MilestoneRegistryClass.get_def(mid)
		if def_val == null:
			return Result.failure("base_rules:tips: 未知里程碑定义: %s" % mid)
		if not (def_val is MilestoneDef):
			return Result.failure("base_rules:tips: 里程碑定义类型错误（期望 MilestoneDef）: %s" % mid)
		var def: MilestoneDef = def_val

		for e_i in range(def.effects.size()):
			var eff_val = def.effects[e_i]
			if not (eff_val is Dictionary):
				return Result.failure("base_rules:tips: %s.effects[%d] 类型错误（期望 Dictionary）" % [mid, e_i])
			var eff: Dictionary = eff_val
			var type_val = eff.get("type", null)
			if not (type_val is String):
				return Result.failure("base_rules:tips: %s.effects[%d].type 类型错误（期望 String）" % [mid, e_i])
			var t: String = str(type_val)
			if t != "waitress_tips":
				continue

			var value_val = eff.get("value", null)
			var v_read := _parse_non_negative_int_value(value_val, "%s.effects[%d].value" % [mid, e_i])
			if not v_read.ok:
				return Result.failure("base_rules:tips: %s" % v_read.error)
			found = true
			best = maxi(best, int(v_read.value))

	return Result.success({
		"found": found,
		"value": best,
	})

func _parse_non_negative_int_value(value, path: String) -> Result:
	if value is int:
		if int(value) < 0:
			return Result.failure("%s 必须 >= 0，实际: %d" % [path, int(value)])
		return Result.success(int(value))
	if value is float:
		var f: float = float(value)
		if f == int(f):
			var i: int = int(f)
			if i < 0:
				return Result.failure("%s 必须 >= 0，实际: %d" % [path, i])
			return Result.success(i)
		return Result.failure("%s 必须为整数（不允许小数）" % path)
	return Result.failure("%s 必须为非负整数" % path)

