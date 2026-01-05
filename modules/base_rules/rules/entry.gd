extends RefCounted

const PhaseDefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const PhaseManagerClass = preload("res://core/engine/phase_manager.gd")
const SettlementRegistryClass = preload("res://core/rules/settlement_registry.gd")

const PaydaySettlementClass = preload("res://core/rules/phase/payday_settlement.gd")
const CleanupSettlementClass = preload("res://core/rules/phase/cleanup_settlement.gd")
const DinnertimeSettlementClass = preload("res://core/rules/phase/dinnertime_settlement.gd")
const MarketingSettlementClass = preload("res://core/rules/phase/marketing_settlement.gd")
const MilestoneSystemClass = preload("res://core/rules/milestone_system.gd")
const MilestoneRegistryClass = preload("res://core/data/milestone_registry.gd")
const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")
const StateUpdaterClass = preload("res://core/state/state_updater.gd")
const MapDefClass = preload("res://core/map/map_def.gd")
const MapOptionDefClass = preload("res://core/map/map_option_def.gd")
const WorkingFlowClass = preload("res://core/engine/phase_manager/working_flow.gd")
const EmployeeRulesClass = preload("res://core/rules/employee_rules.gd")
const MandatoryActionsRulesClass = preload("res://core/rules/working/mandatory_actions_rules.gd")

const Phase = PhaseDefsClass.Phase
const WorkingSubPhase = PhaseDefsClass.WorkingSubPhase
const HookType = PhaseManagerClass.HookType

func register(registrar) -> Result:
	var r = registrar.register_primary_settlement(Phase.DINNERTIME, SettlementRegistryClass.Point.ENTER, Callable(self, "_on_dinnertime_enter"))
	if not r.ok:
		return r
	r = registrar.register_primary_settlement(Phase.PAYDAY, SettlementRegistryClass.Point.EXIT, Callable(self, "_on_payday_exit"))
	if not r.ok:
		return r
	r = registrar.register_primary_settlement(Phase.MARKETING, SettlementRegistryClass.Point.ENTER, Callable(self, "_on_marketing_enter"))
	if not r.ok:
		return r
	r = registrar.register_primary_settlement(Phase.CLEANUP, SettlementRegistryClass.Point.ENTER, Callable(self, "_on_cleanup_enter"))
	if not r.ok:
		return r
	r = registrar.register_primary_map_generator(Callable(self, "_generate_map_def"))
	if not r.ok:
		return r
	r = registrar.register_effect("base_rules:dinnertime:tiebreaker:waitress", Callable(self, "_effect_dinnertime_tiebreaker_waitress"))
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

	# Phase/SubPhase hooks（避免 PhaseManager 中写死规则分支）
	r = registrar.register_phase_hook(Phase.RESTRUCTURING, HookType.BEFORE_ENTER, Callable(self, "_on_restructuring_before_enter"))
	if not r.ok:
		return r
	r = registrar.register_phase_hook(Phase.ORDER_OF_BUSINESS, HookType.BEFORE_ENTER, Callable(self, "_on_order_of_business_before_enter"))
	if not r.ok:
		return r
	r = registrar.register_phase_hook(Phase.WORKING, HookType.BEFORE_ENTER, Callable(self, "_on_working_before_enter"))
	if not r.ok:
		return r
	r = registrar.register_phase_hook(Phase.WORKING, HookType.BEFORE_EXIT, Callable(self, "_on_working_before_exit"))
	if not r.ok:
		return r
	r = registrar.register_sub_phase_hook(WorkingSubPhase.TRAIN, HookType.BEFORE_EXIT, Callable(self, "_on_train_before_exit"))
	if not r.ok:
		return r
	r = registrar.register_phase_hook(Phase.DINNERTIME, HookType.BEFORE_EXIT, Callable(self, "_on_dinnertime_before_exit"))
	if not r.ok:
		return r

	# Milestone effects.type handlers（严格模式：缺失则 init fail）
	r = registrar.register_milestone_effect("gain_card", Callable(self, "_milestone_effect_gain_card"))
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

	# 以下 effect types 当前由现有规则代码读取（非一次性应用），仍需注册以满足 Strict Mode 校验
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

func _on_restructuring_before_enter(state: GameState) -> Result:
	if state == null:
		return Result.failure("base_rules:restructuring_before_enter: state 为空")
	if not (state.round_state is Dictionary):
		return Result.failure("base_rules:restructuring_before_enter: state.round_state 类型错误（期望 Dictionary）")
	var rs: Dictionary = state.round_state
	var prev_phase: String = str(rs.get("prev_phase", ""))
	if prev_phase == "Setup" or prev_phase == "Cleanup":
		WorkingFlowClass.start_new_round(state)
		WorkingFlowClass.auto_activate_reserve_employees(state)
	return Result.success()

func _on_order_of_business_before_enter(state: GameState) -> Result:
	if state == null:
		return Result.failure("base_rules:order_of_business_before_enter: state 为空")
	WorkingFlowClass.start_order_of_business(state)
	return Result.success()

func _on_working_before_enter(state: GameState) -> Result:
	if state == null:
		return Result.failure("base_rules:working_before_enter: state 为空")
	WorkingFlowClass.reset_working_phase_state(state)
	return Result.success()

func _on_working_before_exit(state: GameState) -> Result:
	if state == null:
		return Result.failure("base_rules:working_before_exit: state 为空")

	# 招聘缺货预支约束：若存在待清账的“紧接培训”，则禁止跳过 Working 阶段。
	if EmployeeRulesClass.has_any_immediate_train_pending(state):
		return Result.failure("存在缺货预支待培训员工，必须在 Train 子阶段紧接完成培训")

	# 强制动作检查：离开 Working 阶段前，检查所有玩家是否完成了必须的强制动作
	var mandatory_check := MandatoryActionsRulesClass.check_mandatory_actions_completed(state)
	if not mandatory_check.ok:
		return mandatory_check
	return Result.success()

func _on_train_before_exit(state: GameState) -> Result:
	if state == null:
		return Result.failure("base_rules:train_before_exit: state 为空")
	if EmployeeRulesClass.has_any_immediate_train_pending(state):
		return Result.failure("存在缺货预支待培训员工，无法推进子阶段（需先在 Train 完成培训）")
	return Result.success()

func _on_dinnertime_before_exit(state: GameState) -> Result:
	if state == null:
		return Result.failure("base_rules:dinnertime_before_exit: state 为空")
	if not (state.round_state is Dictionary):
		return Result.failure("base_rules:dinnertime_before_exit: state.round_state 类型错误（期望 Dictionary）")
	if not (state.bank is Dictionary):
		return Result.failure("base_rules:dinnertime_before_exit: state.bank 类型错误（期望 Dictionary）")

	# 银行第二次破产：晚餐阶段结束后立刻终局（跳过 Payday 等后续阶段）
	if int(state.bank.get("broke_count", 0)) >= 2:
		state.round_state["force_next_phase"] = "GameOver"
	return Result.success()

func _on_dinnertime_enter(state: GameState, phase_manager: PhaseManager) -> Result:
	return DinnertimeSettlementClass.apply(state, phase_manager)

func _on_payday_exit(state: GameState, phase_manager: PhaseManager) -> Result:
	return PaydaySettlementClass.apply(state, phase_manager)

func _on_cleanup_enter(state: GameState, _phase_manager: PhaseManager) -> Result:
	return CleanupSettlementClass.apply(state)

func _on_marketing_enter(state: GameState, phase_manager: PhaseManager) -> Result:
	var rounds_read := phase_manager.get_marketing_rounds(state)
	if not rounds_read.ok:
		return rounds_read
	var marketing_rounds: int = int(rounds_read.value)
	return MarketingSettlementClass.apply(state, phase_manager.get_marketing_range_calculator(), marketing_rounds, phase_manager)

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

func _generate_map_def(player_count: int, catalog, map_option, rng_manager) -> Result:
	if player_count <= 0:
		return Result.failure("base_rules:map_generator: player_count 无效: %d" % player_count)
	if player_count == 6:
		return Result.failure("base_rules:map_generator: 6人地图尚未实现（需要后续扩展模块）")
	if rng_manager == null or not rng_manager.has_method("shuffle") or not rng_manager.has_method("randi_range"):
		return Result.failure("base_rules:map_generator: 必须提供可用的 RandomManager（用于确定性地图生成）")
	if catalog == null or not (catalog.tiles is Dictionary):
		return Result.failure("base_rules:map_generator: catalog.tiles 缺失或类型错误（期望 Dictionary）")
	if map_option == null or not (map_option is MapOptionDefClass):
		return Result.failure("base_rules:map_generator: map_option 类型错误（期望 MapOptionDef）")

	var opt = map_option
	var grid := _get_grid_size_for_player_count(player_count)
	if grid.x <= 0 or grid.y <= 0:
		return Result.failure("base_rules:map_generator: grid_size 无效: %s" % str(grid))

	if opt.layout_mode == "fixed":
		var map_def := MapDefClass.create_fixed(opt.id, opt.tiles)
		if map_def == null:
			return Result.failure("base_rules:map_generator: create_fixed 失败")
		if map_def.grid_size != grid:
			return Result.failure("base_rules:map_generator: fixed map grid_size 不符合规则: got=%s expected=%s" % [str(map_def.grid_size), str(grid)])
		map_def.display_name = opt.display_name
		map_def.min_players = opt.min_players
		map_def.max_players = opt.max_players
		return Result.success(map_def)

	if opt.layout_mode != "random_all_tiles":
		return Result.failure("base_rules:map_generator: 未支持的 layout_mode: %s" % opt.layout_mode)

	var required: int = grid.x * grid.y
	var tile_ids: Array[String] = []
	for k in catalog.tiles.keys():
		if not (k is String):
			return Result.failure("base_rules:map_generator: catalog.tiles key 类型错误（期望 String）")
		var tid: String = str(k)
		if tid.is_empty():
			return Result.failure("base_rules:map_generator: catalog.tiles key 不能为空")
		tile_ids.append(tid)
	tile_ids.sort()

	if tile_ids.size() < required:
		return Result.failure("base_rules:map_generator: tile 数量不足：need=%d have=%d" % [required, tile_ids.size()])

	# 规则：pool = catalog 所有 tiles（按文件夹枚举），不放回随机选。
	rng_manager.shuffle(tile_ids)

	var rotations: Array[int] = [0, 90, 180, 270]
	var out := MapDefClass.create_empty(opt.id, grid)
	out.display_name = opt.display_name
	out.min_players = opt.min_players
	out.max_players = opt.max_players

	var index: int = 0
	for y in range(grid.y):
		for x in range(grid.x):
			var tile_id: String = tile_ids[index]
			index += 1
			var rotation: int = 0
			if opt.random_rotation:
				var r_index: int = int(rng_manager.randi_range(0, rotations.size() - 1))
				rotation = int(rotations[r_index])
			out.add_tile(tile_id, Vector2i(x, y), rotation)

	return Result.success(out)

func _get_grid_size_for_player_count(player_count: int) -> Vector2i:
	match player_count:
		2:
			return Vector2i(3, 3)
		3:
			return Vector2i(3, 4)
		4:
			return Vector2i(4, 4)
		5:
			return Vector2i(5, 4)
	return Vector2i.ZERO

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
