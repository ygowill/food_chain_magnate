# Marketing 结算（从 PhaseManager 抽离）
# 目标：聚合 Marketing 阶段“营销实例结算/需求生成/到期清理”逻辑，便于测试与复用。
class_name MarketingSettlement
extends RefCounted

const MarketingRangeCalculatorClass = preload("res://core/rules/marketing_range_calculator.gd")
const MilestoneSystemClass = preload("res://core/rules/milestone_system.gd")
const HelpersClass = preload("res://modules/base_rules/rules/phase/marketing/settlement_helpers.gd")
const MarketingInstancesValidationClass = preload("res://modules/base_rules/rules/phase/marketing/marketing_instances_validation.gd")
const MapStateAccessClass = preload("res://core/state/map_state_access.gd")

static func apply(state: GameState, marketing_range_calculator = null, rounds: int = 1, phase_manager = null) -> Result:
	# 对齐 docs/rules.md / docs/design.md：
	# - Marketing 阶段按 board_number 升序结算营销实例，产生需求
	# - 结算后持续时间 -1；到 0 则收回板件并释放忙碌营销员
	if state == null:
		return Result.failure("MarketingSettlement: state 为空")
	if rounds <= 0:
		return Result.failure("MarketingSettlement: rounds 必须 > 0，实际: %d" % rounds)
	if not (state.players is Array):
		return Result.failure("MarketingSettlement: state.players 类型错误（期望 Array）")
	if not (state.round_state is Dictionary):
		return Result.failure("MarketingSettlement: state.round_state 类型错误（期望 Dictionary）")
	var placements_read := MapStateAccessClass.require_marketing_placements(state, "MarketingSettlement")
	if not placements_read.ok:
		return placements_read
	var placements: Dictionary = placements_read.value

	var effect_registry = null
	if phase_manager != null and phase_manager.has_method("get_effect_registry"):
		effect_registry = phase_manager.get_effect_registry()
	if effect_registry == null:
		return Result.failure("MarketingSettlement: EffectRegistry 未设置")

	var warnings: Array[String] = []

	if state.marketing_instances.is_empty():
		if not placements.is_empty():
			return Result.failure("MarketingSettlement: marketing_instances 为空但 marketing_placements 非空")
		state.round_state["marketing"] = {
			"rounds": rounds,
			"processed": [],
			"expired": []
		}
		return Result.success()

	var instances_read := MarketingInstancesValidationClass.build_sorted_instances(state, placements)
	if not instances_read.ok:
		return instances_read
	var instances: Array[Dictionary] = instances_read.value

	# 多轮结算（模块扩展点）：
	# - 每轮按 board_number 升序结算全部实例
	# - 所有轮次结束后统一 -1 持续时间（permanent=-1 不递减）
	var calculator = marketing_range_calculator
	if calculator == null:
		calculator = MarketingRangeCalculatorClass.new()

	var affected_by_board_number := {}
	var demand_amount_by_board_number := {}
	var demands_added_by_board_number := {}

	for inst_val in instances:
		var inst: Dictionary = inst_val
		var board_number: int = inst["board_number"]

		var affected_result: Result = calculator.get_affected_house_ids(state, inst)
		if not affected_result.ok:
			return affected_result
		var affected: Array = affected_result.value
		var sorted_read := _sort_house_ids_by_number(state, affected)
		if not sorted_read.ok:
			return sorted_read
		affected_by_board_number[board_number] = sorted_read.value

		var marketing_type: String = inst["type"]
		var owner: int = inst["owner"]

		var demand_amount_read := _get_demand_amount_for_instance(state, inst, effect_registry)
		if not demand_amount_read.ok:
			return demand_amount_read
		warnings.append_array(demand_amount_read.warnings)
		var demand_amount: int = int(demand_amount_read.value)

		demand_amount_by_board_number[board_number] = demand_amount
		demands_added_by_board_number[board_number] = 0

	for _round_index in range(rounds):
		for inst_val in instances:
			var inst: Dictionary = inst_val
			var board_number: int = inst["board_number"]
			var marketing_type: String = inst["type"]
			var owner: int = inst["owner"]
			var products_in_order_r := _get_products_in_order(inst)
			if not products_in_order_r.ok:
				return products_in_order_r
			var products_in_order: Array = products_in_order_r.value
			var affected: Array = affected_by_board_number.get(board_number, [])
			var demand_amount: int = int(demand_amount_by_board_number.get(board_number, 1))

			var added_this_round := 0
			var added_by_product := {}
			for p in products_in_order:
				var added_for_product := 0
				for house_id in affected:
					var add_result := _add_house_demand(state, house_id, p, owner, board_number, marketing_type, demand_amount)
					if not add_result.ok:
						return add_result
					added_for_product += int(add_result.value)
				added_by_product[p] = added_for_product
				added_this_round += added_for_product

			demands_added_by_board_number[board_number] = int(demands_added_by_board_number.get(board_number, 0)) + added_this_round

			if added_this_round > 0:
				var cash_r := _apply_marketing_demand_cash_effects(state, effect_registry, inst, added_this_round)
				if not cash_r.ok:
					return cash_r
				warnings.append_array(cash_r.warnings)

			for p in products_in_order:
				var added_for_product := int(added_by_product.get(p, 0))
				if added_for_product <= 0:
					continue
				var ms := MilestoneSystemClass.process_event(state, "DemandMarked", {
					"player_id": owner,
					"product": p
				})
				if not ms.ok:
					warnings.append("里程碑触发失败(DemandMarked)：%s" % ms.error)

	var processed: Array[Dictionary] = []
	var expired: Array[Dictionary] = []
	var remaining_instances: Array[Dictionary] = []

	for inst_val in instances:
		var inst: Dictionary = inst_val
		var board_number: int = inst["board_number"]
		var marketing_type: String = inst["type"]
		var owner: int = inst["owner"]
		var employee_type: String = inst["employee_type"]
		var product: String = inst["product"]
		var world_pos: Vector2i = inst["world_pos"]
		var before_duration: int = inst["remaining_duration"]

		var affected: Array = affected_by_board_number.get(board_number, [])
		var demands_added: int = int(demands_added_by_board_number.get(board_number, 0))

		var after_duration: int = before_duration
		var expired_now: bool = false
		if before_duration > 0:
			after_duration = maxi(0, before_duration - 1)
			expired_now = after_duration == 0

		processed.append({
			"board_number": board_number,
			"type": marketing_type,
			"owner": owner,
			"employee_type": employee_type,
			"product": product,
			"world_pos": world_pos,
			"affected_houses": affected,
			"demands_added": demands_added,
			"rounds": rounds,
			"duration_before": before_duration,
			"duration_after": after_duration,
			"expired": expired_now
		})

		if expired_now:
			var expire_r := _expire_marketing_instance(state, inst)
			if not expire_r.ok:
				return expire_r
			warnings.append_array(expire_r.warnings)
			expired.append({
				"board_number": board_number,
				"owner": owner,
				"employee_type": employee_type
			})
		else:
			inst["remaining_duration"] = after_duration
			remaining_instances.append(inst)

	# 写回 remaining（保持确定性排序）
	remaining_instances.sort_custom(func(a, b) -> bool:
		return int(a["board_number"]) < int(b["board_number"])
	)
	state.marketing_instances = remaining_instances

	# 同步 map.marketing_placements 的剩余持续时间
	for inst in remaining_instances:
		var bn: int = inst["board_number"]
		var key := str(bn)
		if not placements.has(key):
			return Result.failure("MarketingSettlement: marketing_placements 缺少 board_number: #%d" % bn)
		if not (placements[key] is Dictionary):
			return Result.failure("MarketingSettlement: marketing_placements[%s] 类型错误（期望 Dictionary）" % key)
		placements[key]["remaining_duration"] = int(inst["remaining_duration"])
	state.map["marketing_placements"] = placements

	state.round_state["marketing"] = {
		"rounds": rounds,
		"processed": processed,
		"expired": expired
	}

	return Result.success().with_warnings(warnings)

static func _expire_marketing_instance(state: GameState, inst: Dictionary) -> Result:
	return HelpersClass.expire_marketing_instance(state, inst)

static func _get_products_in_order(inst: Dictionary) -> Result:
	return HelpersClass.get_products_in_order(inst)

static func _add_house_demand(
	state: GameState,
	house_id: String,
	product: String,
	from_player: int,
	board_number: int,
	marketing_type: String,
	amount: int
) -> Result:
	return HelpersClass.add_house_demand(state, house_id, product, from_player, board_number, marketing_type, amount)

static func _get_demand_amount_for_instance(state: GameState, inst: Dictionary, effect_registry) -> Result:
	return HelpersClass.get_demand_amount_for_instance(state, inst, effect_registry)

static func _apply_marketing_demand_cash_effects(state: GameState, effect_registry, inst: Dictionary, demands_added: int) -> Result:
	return HelpersClass.apply_marketing_demand_cash_effects(state, effect_registry, inst, demands_added)

static func _sort_house_ids_by_number(state: GameState, house_ids: Array) -> Result:
	return HelpersClass.sort_house_ids_by_number(state, house_ids)
