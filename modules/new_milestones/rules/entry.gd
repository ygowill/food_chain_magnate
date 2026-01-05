extends RefCounted

const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")
const PhaseManagerClass = preload("res://core/engine/phase_manager.gd")
const PhaseDefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const SettlementRegistryClass = preload("res://core/rules/settlement_registry.gd")
const MilestoneSystemClass = preload("res://core/rules/milestone_system.gd")
const RangeUtilsClass = preload("res://core/utils/range_utils.gd")
const MapRuntimeClass = preload("res://core/map/map_runtime.gd")
const MarketingRegistryClass = preload("res://core/data/marketing_registry.gd")
const PlaceNewRestaurantMailboxActionClass = preload("res://modules/new_milestones/actions/place_new_restaurant_mailbox_action.gd")
const PlaceCampaignManagerSecondTileActionClass = preload("res://modules/new_milestones/actions/place_campaign_manager_second_tile_action.gd")
const SetBrandManagerAirplaneSecondGoodActionClass = preload("res://modules/new_milestones/actions/set_brand_manager_airplane_second_good_action.gd")
const PlacePizzaRadioActionClass = preload("res://modules/new_milestones/actions/place_pizza_radio_action.gd")

const Phase = PhaseDefsClass.Phase
const HookType = PhaseManagerClass.HookType

const EFFECT_ID_FIRST_MARKETEER_DISTANCE := "new_milestones:dinnertime:distance_delta:first_marketeer_used"
const EFFECT_ID_FIRST_MARKETEER_DEMAND_CASH := "new_milestones:marketing:demand_cash:first_marketeer_used"

const CM_PROVIDER_ID := "new_milestones:campaign_manager:pending_second_tile"
const CM_PENDING_KEY := "new_milestones_campaign_manager_pending"
const CM_USED_KEY := "new_milestones_campaign_manager_used_this_turn"

const MILESTONE_ID_CAMPAIGN_MANAGER := "first_campaign_manager_used"
const MILESTONE_ID_BRAND_MANAGER := "first_brand_manager_used"
const MILESTONE_ID_BRAND_DIRECTOR := "first_brand_director_used"
const MILESTONE_ID_BURGER_SOLD := "first_burger_sold"
const MILESTONE_ID_PIZZA_SOLD := "first_pizza_sold"

const BM_PROVIDER_ID := "new_milestones:brand_manager:pending_airplane_second_good"
const BM_PENDING_KEY := "new_milestones_brand_manager_airplane_pending"
const BM_USED_KEY := "new_milestones_brand_manager_airplane_used_this_turn"

const BD_PROVIDER_ID := "new_milestones:brand_director:radio_permanent_and_busy_forever"

const PIZZA_PENDING_KEY := "new_milestones_pizza_radios_pending"

func register(registrar) -> Result:
	var r = registrar.register_effect(EFFECT_ID_FIRST_MARKETEER_DISTANCE, Callable(self, "_effect_first_marketeer_distance_minus_two"))
	if not r.ok:
		return r
	r = registrar.register_effect(EFFECT_ID_FIRST_MARKETEER_DEMAND_CASH, Callable(self, "_effect_first_marketeer_demand_cash_bonus"))
	if not r.ok:
		return r

	r = registrar.register_action_executor(PlaceNewRestaurantMailboxActionClass.new())
	if not r.ok:
		return r
	r = registrar.register_action_executor(PlaceCampaignManagerSecondTileActionClass.new())
	if not r.ok:
		return r
	r = registrar.register_action_executor(SetBrandManagerAirplaneSecondGoodActionClass.new())
	if not r.ok:
		return r
	r = registrar.register_action_executor(PlacePizzaRadioActionClass.new())
	if not r.ok:
		return r

	r = registrar.register_marketing_initiation_provider(CM_PROVIDER_ID, Callable(self, "_on_marketing_initiated_campaign_manager"), 120)
	if not r.ok:
		return r
	r = registrar.register_marketing_initiation_provider(BM_PROVIDER_ID, Callable(self, "_on_marketing_initiated_brand_manager"), 121)
	if not r.ok:
		return r
	r = registrar.register_marketing_initiation_provider(BD_PROVIDER_ID, Callable(self, "_on_marketing_initiated_brand_director"), 122)
	if not r.ok:
		return r

	# 晚餐结算后：按售卖记录触发 ProductSold 事件，并处理“首个卖出汉堡” CEO 卡槽修正
	r = registrar.register_extension_settlement(Phase.DINNERTIME, SettlementRegistryClass.Point.ENTER, Callable(self, "_after_dinnertime_primary"), 150)
	if not r.ok:
		return r

	# 不能存到下一回合：离开 Working/Marketing 子阶段时清空 pending
	r = registrar.register_working_sub_phase_hook("Marketing", PhaseManagerClass.HookType.AFTER_EXIT, Callable(self, "_on_working_marketing_after_exit"), 120)
	if not r.ok:
		return r

	# === 里程碑 effects.type（Strict Mode：缺失则 init fail）===
	r = registrar.register_milestone_effect("train_from_active_same_color", Callable(self, "_milestone_effect_train_from_active_same_color"))
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

func _effect_first_marketeer_distance_minus_two(_state: GameState, _player_id: int, ctx: Dictionary) -> Result:
	if ctx == null or not (ctx is Dictionary):
		return Result.failure("new_milestones:first_marketeer_used: ctx 类型错误（期望 Dictionary）")
	if not ctx.has("distance") or not (ctx["distance"] is int):
		return Result.failure("new_milestones:first_marketeer_used: ctx.distance 缺失或类型错误（期望 int）")
	if not ctx.has("allow_negative") or not (ctx["allow_negative"] is bool):
		return Result.failure("new_milestones:first_marketeer_used: ctx.allow_negative 缺失或类型错误（期望 bool）")
	ctx["allow_negative"] = true
	ctx["distance"] = int(ctx["distance"]) - 2
	return Result.success()

func _effect_first_marketeer_demand_cash_bonus(_state: GameState, _player_id: int, ctx: Dictionary) -> Result:
	if ctx == null or not (ctx is Dictionary):
		return Result.failure("new_milestones:first_marketeer_used: ctx 类型错误（期望 Dictionary）")
	if not ctx.has("demands_added") or not (ctx["demands_added"] is int):
		return Result.failure("new_milestones:first_marketeer_used: ctx.demands_added 缺失或类型错误（期望 int）")
	if not ctx.has("cash_bonus") or not (ctx["cash_bonus"] is int):
		return Result.failure("new_milestones:first_marketeer_used: ctx.cash_bonus 缺失或类型错误（期望 int）")
	if not ctx.has("marketing_instance") or not (ctx["marketing_instance"] is Dictionary):
		return Result.failure("new_milestones:first_marketeer_used: ctx.marketing_instance 缺失或类型错误（期望 Dictionary）")
	var inst: Dictionary = ctx["marketing_instance"]
	if not inst.has("employee_type") or not (inst["employee_type"] is String):
		return Result.failure("new_milestones:first_marketeer_used: marketing_instance.employee_type 缺失或类型错误（期望 String）")
	var employee_type: String = str(inst["employee_type"])
	if employee_type.is_empty():
		return Result.failure("new_milestones:first_marketeer_used: marketing_instance.employee_type 不能为空")

	var emp_def = EmployeeRegistryClass.get_def(employee_type)
	if emp_def == null:
		return Result.success()

	var is_marketeer := false
	for t in emp_def.usage_tags:
		if t is String and str(t).begins_with("use:marketing:"):
			is_marketeer = true
			break
	if not is_marketeer:
		return Result.success()

	var demands_added: int = int(ctx["demands_added"])
	if demands_added <= 0:
		return Result.success()

	ctx["cash_bonus"] = int(ctx["cash_bonus"]) + demands_added * 5
	return Result.success()

func _on_marketing_initiated_campaign_manager(state: GameState, command: Command, marketing_instance: Dictionary) -> Result:
	if state == null:
		return Result.failure("new_milestones:campaign_manager: state 为空")
	if command == null:
		return Result.failure("new_milestones:campaign_manager: command 为空")
	if marketing_instance == null or not (marketing_instance is Dictionary):
		return Result.failure("new_milestones:campaign_manager: marketing_instance 类型错误（期望 Dictionary）")
	if not (state.round_state is Dictionary):
		return Result.failure("new_milestones:campaign_manager: state.round_state 类型错误（期望 Dictionary）")

	var employee_type_val = null
	if command.params is Dictionary and command.params.has("employee_type"):
		employee_type_val = command.params.get("employee_type", null)
	if not (employee_type_val is String):
		return Result.failure("new_milestones:campaign_manager: 缺少/错误参数 employee_type（期望 String）")
	var employee_type: String = str(employee_type_val)
	if employee_type.is_empty():
		return Result.failure("new_milestones:campaign_manager: employee_type 不能为空")
	if employee_type != "campaign_manager":
		return Result.success()

	# 只允许在“获得该里程碑的同一回合”使用一次
	if not _was_milestone_awarded_this_turn(state, int(command.actor), MILESTONE_ID_CAMPAIGN_MANAGER):
		return Result.success()

	if not marketing_instance.has("type") or not (marketing_instance["type"] is String):
		return Result.failure("new_milestones:campaign_manager: marketing_instance.type 缺失或类型错误（期望 String）")
	var mk_type: String = str(marketing_instance["type"])
	if mk_type != "billboard" and mk_type != "mailbox":
		return Result.success()

	if not state.round_state.has(CM_USED_KEY):
		state.round_state[CM_USED_KEY] = {}
	var used_val = state.round_state.get(CM_USED_KEY, null)
	if not (used_val is Dictionary):
		return Result.failure("new_milestones:campaign_manager: round_state.%s 类型错误（期望 Dictionary）" % CM_USED_KEY)
	var used: Dictionary = used_val
	if used.has(command.actor):
		return Result.success()

	if not state.round_state.has(CM_PENDING_KEY):
		state.round_state[CM_PENDING_KEY] = {}
	var pending_val = state.round_state.get(CM_PENDING_KEY, null)
	if not (pending_val is Dictionary):
		return Result.failure("new_milestones:campaign_manager: round_state.%s 类型错误（期望 Dictionary）" % CM_PENDING_KEY)
	var pending: Dictionary = pending_val
	if pending.has(command.actor):
		return Result.success()

	var board_number_val = marketing_instance.get("board_number", null)
	if not (board_number_val is int):
		return Result.failure("new_milestones:campaign_manager: marketing_instance.board_number 缺失或类型错误（期望 int）")
	var board_number: int = int(board_number_val)
	var product_val = marketing_instance.get("product", null)
	if not (product_val is String):
		return Result.failure("new_milestones:campaign_manager: marketing_instance.product 缺失或类型错误（期望 String）")
	var product: String = str(product_val)
	var duration_val = marketing_instance.get("remaining_duration", null)
	if not (duration_val is int):
		return Result.failure("new_milestones:campaign_manager: marketing_instance.remaining_duration 缺失或类型错误（期望 int）")
	var duration: int = int(duration_val)

	var link_id := "new_milestones:campaign_manager:%d:%d:%d" % [state.round_number, int(command.actor), board_number]
	marketing_instance["link_id"] = link_id

	pending[int(command.actor)] = {
		"link_id": link_id,
		"employee_type": employee_type,
		"type": mk_type,
		"product": product,
		"remaining_duration": duration,
		"primary_board_number": board_number,
	}
	state.round_state[CM_PENDING_KEY] = pending
	used[int(command.actor)] = true
	state.round_state[CM_USED_KEY] = used
	return Result.success()

func _on_marketing_initiated_brand_manager(state: GameState, command: Command, marketing_instance: Dictionary) -> Result:
	if state == null:
		return Result.failure("new_milestones:brand_manager: state 为空")
	if command == null:
		return Result.failure("new_milestones:brand_manager: command 为空")
	if marketing_instance == null or not (marketing_instance is Dictionary):
		return Result.failure("new_milestones:brand_manager: marketing_instance 类型错误（期望 Dictionary）")
	if not (state.round_state is Dictionary):
		return Result.failure("new_milestones:brand_manager: state.round_state 类型错误（期望 Dictionary）")

	# 只允许在“获得该里程碑的同一回合”使用一次
	if not _was_milestone_awarded_this_turn(state, int(command.actor), MILESTONE_ID_BRAND_MANAGER):
		return Result.success()

	var employee_type_val = null
	if command.params is Dictionary and command.params.has("employee_type"):
		employee_type_val = command.params.get("employee_type", null)
	if not (employee_type_val is String):
		return Result.failure("new_milestones:brand_manager: 缺少/错误参数 employee_type（期望 String）")
	var employee_type: String = str(employee_type_val)
	if employee_type.is_empty():
		return Result.failure("new_milestones:brand_manager: employee_type 不能为空")
	if employee_type != "brand_manager":
		return Result.success()

	if not marketing_instance.has("type") or not (marketing_instance["type"] is String):
		return Result.failure("new_milestones:brand_manager: marketing_instance.type 缺失或类型错误（期望 String）")
	var mk_type: String = str(marketing_instance["type"])
	if mk_type != "airplane":
		return Result.success()

	if not state.round_state.has(BM_USED_KEY):
		state.round_state[BM_USED_KEY] = {}
	var used_val = state.round_state.get(BM_USED_KEY, null)
	if not (used_val is Dictionary):
		return Result.failure("new_milestones:brand_manager: round_state.%s 类型错误（期望 Dictionary）" % BM_USED_KEY)
	var used: Dictionary = used_val
	if used.has(command.actor):
		return Result.success()

	if not state.round_state.has(BM_PENDING_KEY):
		state.round_state[BM_PENDING_KEY] = {}
	var pending_val = state.round_state.get(BM_PENDING_KEY, null)
	if not (pending_val is Dictionary):
		return Result.failure("new_milestones:brand_manager: round_state.%s 类型错误（期望 Dictionary）" % BM_PENDING_KEY)
	var pending: Dictionary = pending_val
	if pending.has(command.actor):
		return Result.success()

	var board_number_val = marketing_instance.get("board_number", null)
	if not (board_number_val is int):
		return Result.failure("new_milestones:brand_manager: marketing_instance.board_number 缺失或类型错误（期望 int）")
	var board_number: int = int(board_number_val)
	var product_val = marketing_instance.get("product", null)
	if not (product_val is String):
		return Result.failure("new_milestones:brand_manager: marketing_instance.product 缺失或类型错误（期望 String）")
	var product_a: String = str(product_val)
	if product_a.is_empty():
		return Result.failure("new_milestones:brand_manager: marketing_instance.product 不能为空")

	pending[int(command.actor)] = {
		"board_number": board_number,
		"product_a": product_a,
	}
	state.round_state[BM_PENDING_KEY] = pending
	used[int(command.actor)] = true
	state.round_state[BM_USED_KEY] = used
	return Result.success()

func _on_marketing_initiated_brand_director(state: GameState, command: Command, marketing_instance: Dictionary) -> Result:
	if state == null:
		return Result.failure("new_milestones:brand_director: state 为空")
	if command == null:
		return Result.failure("new_milestones:brand_director: command 为空")
	if marketing_instance == null or not (marketing_instance is Dictionary):
		return Result.failure("new_milestones:brand_director: marketing_instance 类型错误（期望 Dictionary）")

	# 里程碑获得后：玩家放置的 radio 永久（duration=-1）
	if _player_has_milestone(state, int(command.actor), MILESTONE_ID_BRAND_DIRECTOR):
		if str(marketing_instance.get("type", "")) == "radio":
			marketing_instance["remaining_duration"] = -1
			if state.map is Dictionary and state.map.has("marketing_placements") and state.map["marketing_placements"] is Dictionary:
				var placements: Dictionary = state.map["marketing_placements"]
				var key := str(int(marketing_instance.get("board_number", -1)))
				if placements.has(key) and (placements[key] is Dictionary):
					var p: Dictionary = placements[key]
					p["remaining_duration"] = -1
					placements[key] = p
					state.map["marketing_placements"] = placements

	# 品牌总监：忙碌到游戏结束（即使本次不是 radio）
	if str(marketing_instance.get("employee_type", "")) == "brand_director":
		if _player_has_milestone(state, int(command.actor), MILESTONE_ID_BRAND_DIRECTOR):
			marketing_instance["no_release"] = true

	return Result.success()

func _on_working_marketing_after_exit(state: GameState) -> Result:
	if state == null:
		return Result.failure("new_milestones: after_exit: state 为空")
	if not (state.round_state is Dictionary):
		return Result.failure("new_milestones: after_exit: state.round_state 类型错误（期望 Dictionary）")
	if state.round_state.has(CM_PENDING_KEY):
		state.round_state.erase(CM_PENDING_KEY)
	if state.round_state.has(CM_USED_KEY):
		state.round_state.erase(CM_USED_KEY)
	if state.round_state.has(BM_PENDING_KEY):
		state.round_state.erase(BM_PENDING_KEY)
	if state.round_state.has(BM_USED_KEY):
		state.round_state.erase(BM_USED_KEY)
	return Result.success()

func _after_dinnertime_primary(state: GameState, _phase_manager: PhaseManager) -> Result:
	if state == null:
		return Result.failure("new_milestones:dinnertime: state 为空")
	if not (state.round_state is Dictionary):
		return Result.failure("new_milestones:dinnertime: state.round_state 类型错误（期望 Dictionary）")
	if not (state.players is Array):
		return Result.failure("new_milestones:dinnertime: state.players 类型错误（期望 Array）")

	var ds_val = state.round_state.get("dinnertime", null)
	if not (ds_val is Dictionary):
		return Result.success()
	var ds: Dictionary = ds_val
	var sales_val = ds.get("sales", null)
	if not (sales_val is Array):
		return Result.success()
	var sales: Array = sales_val
	if sales.is_empty():
		return Result.success()

	for s_val in sales:
		if not (s_val is Dictionary):
			continue
		var s: Dictionary = s_val
		var owner_val = s.get("winner_owner", null)
		if not (owner_val is int):
			continue
		var owner: int = int(owner_val)
		if owner < 0 or owner >= state.players.size():
			return Result.failure("new_milestones:dinnertime: winner_owner 越界: %d" % owner)
		var req_val = s.get("required", null)
		if not (req_val is Dictionary):
			continue
		var required: Dictionary = req_val
		for product_id_val in required.keys():
			if not (product_id_val is String):
				continue
			var product_id: String = str(product_id_val)
			if product_id.is_empty():
				continue
			var r := MilestoneSystemClass.process_event(state, "ProductSold", {
				"player_id": owner,
				"product": product_id,
			})
			if not r.ok:
				return r

	# FIRST PIZZA SOLD：本回合前 3 个“买披萨”的房屋，卖家需放置 2 回合 radio(pizza)（玩家选择落点；若无空间则跳过该房屋）
	var pizza_awarded := false
	if state.round_state.has("milestones_auto_awarded"):
		var log_val = state.round_state.get("milestones_auto_awarded", null)
		if log_val is Array:
			for e_val in Array(log_val):
				if e_val is Dictionary and str(Dictionary(e_val).get("milestone_id", "")) == MILESTONE_ID_PIZZA_SOLD:
					pizza_awarded = true
					break
	if pizza_awarded:
		var pending_list: Array = []
		var used_radio_boards := {}
		if state.map is Dictionary and state.map.has("marketing_placements") and state.map["marketing_placements"] is Dictionary:
			for k in Dictionary(state.map["marketing_placements"]).keys():
				if k is String:
					used_radio_boards[str(k)] = true
		for inst_val in state.marketing_instances:
			if inst_val is Dictionary:
				var bn = Dictionary(inst_val).get("board_number", null)
				if bn is int:
					used_radio_boards[str(int(bn))] = true

		var pizza_count := 0
		for s_val in sales:
			if not (s_val is Dictionary):
				continue
			var s: Dictionary = s_val
			if pizza_count >= 3:
				break
			var req_val = s.get("required", null)
			if not (req_val is Dictionary):
				continue
			var required: Dictionary = req_val
			if not required.has("pizza"):
				continue

			var owner_val = s.get("winner_owner", null)
			if not (owner_val is int):
				continue
			var seller: int = int(owner_val)

			var house_id_val = s.get("house_id", null)
			if not (house_id_val is String):
				continue
			var house_id: String = str(house_id_val)
			if house_id.is_empty():
				continue
			if not (state.map is Dictionary and state.map.has("houses") and state.map["houses"] is Dictionary):
				return Result.failure("new_milestones:pizza: state.map.houses 缺失或类型错误")
			var houses: Dictionary = state.map["houses"]
			if not houses.has(house_id):
				return Result.failure("new_milestones:pizza: houses 缺少 house_id: %s" % house_id)
			var house_val = houses[house_id]
			if not (house_val is Dictionary):
				return Result.failure("new_milestones:pizza: houses[%s] 类型错误（期望 Dictionary）" % house_id)
			var house: Dictionary = house_val
			if not house.has("anchor_pos") or not (house["anchor_pos"] is Vector2i):
				return Result.failure("new_milestones:pizza: houses[%s].anchor_pos 缺失或类型错误（期望 Vector2i）" % house_id)
			var anchor: Vector2i = house["anchor_pos"]

			var board_number := _pick_available_radio_board_number(used_radio_boards)
			if board_number <= 0:
				break

			var tile_pos: Vector2i = MapUtils.world_to_tile(anchor).board_pos
			var tile_min := Vector2i(tile_pos.x * MapUtils.TILE_SIZE, tile_pos.y * MapUtils.TILE_SIZE)
			var tile_max := tile_min + Vector2i(MapUtils.TILE_SIZE - 1, MapUtils.TILE_SIZE - 1)

			# “if there is room”：至少存在 1 个合法放置点才进入待处理列表
			if not _has_any_legal_radio_position_in_tile(state, tile_min, tile_max):
				used_radio_boards[str(board_number)] = true
				continue

			pending_list.append({
				"seller": seller,
				"house_id": house_id,
				"house_number": s.get("house_number", -1),
				"tile_min": tile_min,
				"tile_max": tile_max,
				"board_number": board_number,
				"product": "pizza",
				"duration": 2,
			})
			used_radio_boards[str(board_number)] = true
			pizza_count += 1

		if not pending_list.is_empty():
			state.round_state[PIZZA_PENDING_KEY] = pending_list
			if not state.round_state.has("pending_phase_actions"):
				state.round_state["pending_phase_actions"] = {}
			var ppa_val = state.round_state.get("pending_phase_actions", null)
			if not (ppa_val is Dictionary):
				return Result.failure("new_milestones:pizza: round_state.pending_phase_actions 类型错误（期望 Dictionary）")
			var ppa: Dictionary = ppa_val
			ppa["Dinnertime"] = pending_list.duplicate(true)
			state.round_state["pending_phase_actions"] = ppa

	# “FIRST BURGER SOLD”：从此 CEO 卡槽固定至少 4（不受储备卡影响）
	for player_id in range(state.players.size()):
		if not _player_has_milestone(state, player_id, MILESTONE_ID_BURGER_SOLD):
			continue
		var p_val = state.players[player_id]
		if not (p_val is Dictionary):
			return Result.failure("new_milestones:dinnertime: player 类型错误（期望 Dictionary）: %d" % player_id)
		var p: Dictionary = p_val
		var cs_val = p.get("company_structure", null)
		if not (cs_val is Dictionary):
			return Result.failure("new_milestones:dinnertime: player[%d].company_structure 类型错误（期望 Dictionary）" % player_id)
		var cs: Dictionary = cs_val
		if not cs.has("ceo_slots"):
			return Result.failure("new_milestones:dinnertime: player[%d].company_structure.ceo_slots 缺失" % player_id)
		var slots_val = cs.get("ceo_slots", null)
		var current := 0
		if slots_val is int:
			current = int(slots_val)
		elif slots_val is float:
			var f: float = float(slots_val)
			if f != floor(f):
				return Result.failure("new_milestones:dinnertime: player[%d].company_structure.ceo_slots 必须为整数，实际: %s" % [player_id, str(slots_val)])
			current = int(f)
		else:
			return Result.failure("new_milestones:dinnertime: player[%d].company_structure.ceo_slots 类型错误（期望 int/float）" % player_id)
		if current < 4:
			cs["ceo_slots"] = 4
			p["company_structure"] = cs
			state.players[player_id] = p

	return Result.success()

func _pick_available_radio_board_number(used_board_numbers: Dictionary) -> int:
	# base_marketing：radio #1-#3
	for bn in [1, 2, 3]:
		if not used_board_numbers.has(str(bn)):
			var def = MarketingRegistryClass.get_def(bn)
			if def != null and str(def.type) == "radio":
				return bn
	return -1

func _has_any_legal_radio_position_in_tile(state: GameState, tile_min: Vector2i, tile_max: Vector2i) -> bool:
	for y in range(tile_min.y, tile_max.y + 1):
		for x in range(tile_min.x, tile_max.x + 1):
			var pos := Vector2i(x, y)
			if _is_legal_radio_position(state, pos):
				return true
	return false

func _is_legal_radio_position(state: GameState, world_pos: Vector2i) -> bool:
	if state == null or not (state.map is Dictionary):
		return false
	if not MapRuntimeClass.is_world_pos_in_grid(state, world_pos):
		return false

	if not state.map.has("marketing_placements") or not (state.map["marketing_placements"] is Dictionary):
		return false
	var placements: Dictionary = state.map["marketing_placements"]
	for k in placements.keys():
		var p_val = placements[k]
		if not (p_val is Dictionary):
			return false
		var p: Dictionary = p_val
		if not p.has("world_pos") or not (p["world_pos"] is Vector2i):
			return false
		if p["world_pos"] == world_pos:
			return false

	var cell := MapRuntimeClass.get_cell(state, world_pos)
	if cell.is_empty():
		return false
	if not cell.has("structure") or not (cell["structure"] is Dictionary):
		return false
	if not Dictionary(cell["structure"]).is_empty():
		return false
	if not cell.has("blocked") or not (cell["blocked"] is bool):
		return false
	if bool(cell["blocked"]):
		return false
	if not cell.has("road_segments") or not (cell["road_segments"] is Array):
		return false
	if not Array(cell["road_segments"]).is_empty():
		return false

	var adjacent_roads_result := RangeUtilsClass.get_adjacent_road_cells(state, world_pos)
	if not adjacent_roads_result.ok:
		return false
	var adjacent_roads: Array = adjacent_roads_result.value
	return not adjacent_roads.is_empty()

func _player_has_milestone(state: GameState, player_id: int, milestone_id: String) -> bool:
	if state == null:
		return false
	if milestone_id.is_empty():
		return false
	if not (state.players is Array):
		return false
	if player_id < 0 or player_id >= state.players.size():
		return false
	var p_val = state.players[player_id]
	if not (p_val is Dictionary):
		return false
	var player: Dictionary = p_val
	var milestones_val = player.get("milestones", null)
	if not (milestones_val is Array):
		return false
	return Array(milestones_val).has(milestone_id)

func _was_milestone_awarded_this_turn(state: GameState, player_id: int, milestone_id: String) -> bool:
	if state == null:
		return false
	if milestone_id.is_empty():
		return false
	if not (state.round_state is Dictionary):
		return false
	if not state.round_state.has("milestones_auto_awarded"):
		return false
	var log_val = state.round_state.get("milestones_auto_awarded", null)
	if not (log_val is Array):
		return false
	var log: Array = log_val
	for entry_val in log:
		if not (entry_val is Dictionary):
			continue
		var entry: Dictionary = entry_val
		if int(entry.get("player_id", -1)) != player_id:
			continue
		if str(entry.get("milestone_id", "")) != milestone_id:
			continue
		return true
	return false
