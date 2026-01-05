# Marketing 结算（从 PhaseManager 抽离）
# 目标：聚合 Marketing 阶段“营销实例结算/需求生成/到期清理”逻辑，便于测试与复用。
class_name MarketingSettlement
extends RefCounted

const StateUpdaterClass = preload("res://core/state/state_updater.gd")
const MarketingRegistryClass = preload("res://core/data/marketing_registry.gd")
const MarketingRangeCalculatorClass = preload("res://core/rules/marketing_range_calculator.gd")
const BankruptcyRulesClass = preload("res://core/rules/economy/bankruptcy_rules.gd")
const MilestoneSystemClass = preload("res://core/rules/milestone_system.gd")
const MilestoneRegistryClass = preload("res://core/data/milestone_registry.gd")
const MapRuntimeClass = preload("res://core/map/map_runtime.gd")
const HouseNumberManagerClass = preload("res://core/map/house_number_manager.gd")

const EFFECT_SEG_MARKETING_DEMAND_AMOUNT := ":marketing:demand_amount:"
const EFFECT_SEG_MARKETING_DEMAND_CASH := ":marketing:demand_cash:"

static func apply(state: GameState, marketing_range_calculator = null, rounds: int = 1, phase_manager = null) -> Result:
	# 对齐 docs/rules.md / docs/design.md：
	# - Marketing 阶段按 board_number 升序结算营销实例，产生需求
	# - 结算后持续时间 -1；到 0 则收回板件并释放忙碌营销员
	if state == null:
		return Result.failure("MarketingSettlement: state 为空")
	if rounds <= 0:
		return Result.failure("MarketingSettlement: rounds 必须 > 0，实际: %d" % rounds)
	if not (state.map is Dictionary):
		return Result.failure("MarketingSettlement: state.map 类型错误（期望 Dictionary）")
	if not (state.players is Array):
		return Result.failure("MarketingSettlement: state.players 类型错误（期望 Array）")
	if not (state.round_state is Dictionary):
		return Result.failure("MarketingSettlement: state.round_state 类型错误（期望 Dictionary）")
	if not state.map.has("marketing_placements") or not (state.map["marketing_placements"] is Dictionary):
		return Result.failure("MarketingSettlement: state.map.marketing_placements 缺失或类型错误（期望 Dictionary）")
	var placements: Dictionary = state.map["marketing_placements"]

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

	var instances: Array[Dictionary] = []
	var seen_board_numbers := {}
	for i in range(state.marketing_instances.size()):
		var inst_val = state.marketing_instances[i]
		if not (inst_val is Dictionary):
			return Result.failure("MarketingSettlement: marketing_instances[%d] 类型错误（期望 Dictionary）" % i)
		var inst: Dictionary = (inst_val as Dictionary).duplicate(true)

		if not inst.has("board_number") or not (inst["board_number"] is int):
			return Result.failure("MarketingSettlement: marketing_instances[%d].board_number 缺失或类型错误（期望 int）" % i)
		var board_number: int = inst["board_number"]
		if board_number <= 0:
			return Result.failure("MarketingSettlement: marketing_instances[%d].board_number 必须 > 0" % i)
		var mk_def = MarketingRegistryClass.get_def(board_number)
		if mk_def == null:
			return Result.failure("MarketingSettlement: marketing_instances[%d].board_number 未知: #%d" % [i, board_number])
		if not mk_def.has_method("is_available_for_player_count") or not mk_def.is_available_for_player_count(state.players.size()):
			return Result.failure("MarketingSettlement: marketing_instances[%d].board_number 在当前玩家数下已移除: #%d" % [i, board_number])
		if seen_board_numbers.has(board_number):
			return Result.failure("MarketingSettlement: marketing_instances 出现重复 board_number: #%d" % board_number)
		seen_board_numbers[board_number] = true

		if not inst.has("type") or not (inst["type"] is String):
			return Result.failure("MarketingSettlement: marketing_instances[%d].type 缺失或类型错误（期望 String）" % i)
		var marketing_type: String = inst["type"]
		if marketing_type.is_empty():
			return Result.failure("MarketingSettlement: marketing_instances[%d].type 不能为空" % i)

		if not inst.has("owner") or not (inst["owner"] is int):
			return Result.failure("MarketingSettlement: marketing_instances[%d].owner 缺失或类型错误（期望 int）" % i)
		var owner: int = inst["owner"]
		if owner < 0 or owner >= state.players.size():
			return Result.failure("MarketingSettlement: marketing_instances[%d].owner 越界: %d" % [i, owner])

		if not inst.has("employee_type") or not (inst["employee_type"] is String):
			return Result.failure("MarketingSettlement: marketing_instances[%d].employee_type 缺失或类型错误（期望 String）" % i)
		var employee_type: String = inst["employee_type"]
		if employee_type.is_empty():
			return Result.failure("MarketingSettlement: marketing_instances[%d].employee_type 不能为空" % i)

		if not inst.has("product") or not (inst["product"] is String):
			return Result.failure("MarketingSettlement: marketing_instances[%d].product 缺失或类型错误（期望 String）" % i)
		var product: String = inst["product"]
		if product.is_empty():
			return Result.failure("MarketingSettlement: marketing_instances[%d].product 不能为空" % i)

		if not inst.has("world_pos") or not (inst["world_pos"] is Vector2i):
			return Result.failure("MarketingSettlement: marketing_instances[%d].world_pos 缺失或类型错误（期望 Vector2i）" % i)

		if not inst.has("remaining_duration") or not (inst["remaining_duration"] is int):
			return Result.failure("MarketingSettlement: marketing_instances[%d].remaining_duration 缺失或类型错误（期望 int）" % i)
		var remaining_duration: int = inst["remaining_duration"]
		if remaining_duration == 0 or remaining_duration < -1:
			return Result.failure("MarketingSettlement: marketing_instances[%d].remaining_duration 必须为 -1(永久) 或 > 0，实际: %d" % [i, remaining_duration])

		if not inst.has("axis") or not (inst["axis"] is String):
			return Result.failure("MarketingSettlement: marketing_instances[%d].axis 缺失或类型错误（期望 String）" % i)
		if not inst.has("tile_index") or not (inst["tile_index"] is int):
			return Result.failure("MarketingSettlement: marketing_instances[%d].tile_index 缺失或类型错误（期望 int）" % i)
		var axis: String = inst["axis"]
		var tile_index: int = inst["tile_index"]
		if marketing_type == "airplane":
			if axis != "row" and axis != "col":
				return Result.failure("MarketingSettlement: airplane marketing_instances[%d].axis 非法（期望 row/col）: %s" % [i, axis])
		else:
			if not axis.is_empty():
				return Result.failure("MarketingSettlement: 非 airplane 的 axis 必须为空，实际: %s" % axis)
			if tile_index != -1:
				return Result.failure("MarketingSettlement: 非 airplane 的 tile_index 必须为 -1，实际: %d" % tile_index)

		if not inst.has("created_round") or not (inst["created_round"] is int):
			return Result.failure("MarketingSettlement: marketing_instances[%d].created_round 缺失或类型错误（期望 int）" % i)

		var placement_key := str(board_number)
		if not placements.has(placement_key):
			return Result.failure("MarketingSettlement: marketing_placements 缺少 board_number: #%d" % board_number)
		if not (placements[placement_key] is Dictionary):
			return Result.failure("MarketingSettlement: marketing_placements[%s] 类型错误（期望 Dictionary）" % placement_key)

		instances.append(inst)

	instances.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["board_number"]) < int(b["board_number"])
	)

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
		affected_by_board_number[board_number] = _sort_house_ids_by_number(state, affected)

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

		var affected: Array[String] = affected_by_board_number.get(board_number, [])
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
			_expire_marketing_instance(state, inst)
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

static func _expire_marketing_instance(state: GameState, inst: Dictionary) -> void:
	assert(inst.has("board_number") and (inst["board_number"] is int), "MarketingSettlement._expire_marketing_instance: 缺少/错误 board_number（期望 int）")
	assert(inst.has("owner") and (inst["owner"] is int), "MarketingSettlement._expire_marketing_instance: 缺少/错误 owner（期望 int）")
	assert(inst.has("employee_type") and (inst["employee_type"] is String), "MarketingSettlement._expire_marketing_instance: 缺少/错误 employee_type（期望 String）")
	var board_number: int = inst["board_number"]
	var owner: int = inst["owner"]
	var employee_type: String = inst["employee_type"]
	var link_id := ""
	if inst.has("link_id") and (inst["link_id"] is String):
		link_id = str(inst["link_id"])

	# 收回营销板件
	assert(state.map.has("marketing_placements") and state.map["marketing_placements"] is Dictionary, "MarketingSettlement._expire_marketing_instance: state.map.marketing_placements 缺失或类型错误（期望 Dictionary）")
	state.map["marketing_placements"].erase(str(board_number))

	# 释放忙碌营销员：仅当该员工仍处于忙碌区（可能在 Payday 被解雇）
	assert(owner >= 0 and owner < state.players.size(), "MarketingSettlement._expire_marketing_instance: owner 越界: %d" % owner)
	assert(not employee_type.is_empty(), "MarketingSettlement._expire_marketing_instance: employee_type 不能为空")

	# 扩展点：某些营销员（例如品牌总监）可被标记为“永不释放”
	if inst.has("no_release"):
		var nr = inst.get("no_release", false)
		if nr is bool and bool(nr):
			return

	# 若该员工链接到多个营销实例（例如 campaign manager 的第二张板件），只在最后一个实例到期时释放。
	if not link_id.is_empty():
		for other_val in state.marketing_instances:
			if not (other_val is Dictionary):
				continue
			var other: Dictionary = other_val
			if int(other.get("board_number", -1)) == board_number:
				continue
			if not (other.get("link_id", "") is String):
				continue
			if str(other.get("link_id", "")) != link_id:
				continue
			var rem = other.get("remaining_duration", null)
			# rem==1：本轮也会到期，因此不应阻止释放
			if rem is int and int(rem) > 1:
				return
			if rem is int and int(rem) == -1:
				return

	var removed := StateUpdaterClass.remove_from_array(state.players[owner], "busy_marketers", employee_type)
	if removed:
		StateUpdaterClass.append_to_array(state.players[owner], "reserve_employees", employee_type)

static func _get_products_in_order(inst: Dictionary) -> Result:
	if inst == null or not (inst is Dictionary):
		return Result.failure("MarketingSettlement: inst 类型错误（期望 Dictionary）")
	if not inst.has("product") or not (inst["product"] is String):
		return Result.failure("MarketingSettlement: inst.product 缺失或类型错误（期望 String）")
	var primary: String = str(inst["product"])
	if primary.is_empty():
		return Result.failure("MarketingSettlement: inst.product 不能为空")

	if not inst.has("products"):
		return Result.success([primary])

	var products_val = inst.get("products", null)
	if products_val == null:
		return Result.success([primary])
	if not (products_val is Array):
		return Result.failure("MarketingSettlement: inst.products 类型错误（期望 Array）")
	var products: Array = products_val
	if products.is_empty():
		return Result.success([primary])

	var out: Array[String] = []
	for i in range(products.size()):
		var v = products[i]
		if not (v is String):
			return Result.failure("MarketingSettlement: inst.products[%d] 类型错误（期望 String）" % i)
		var s: String = str(v)
		if s.is_empty():
			return Result.failure("MarketingSettlement: inst.products[%d] 不能为空" % i)
		out.append(s)

	return Result.success(out)

static func _add_house_demand(
	state: GameState,
	house_id: String,
	product: String,
	from_player: int,
	board_number: int,
	marketing_type: String,
	amount: int
) -> Result:
	if not state.map.has("houses") or not (state.map["houses"] is Dictionary):
		return Result.failure("MarketingSettlement: state.map.houses 类型错误（期望 Dictionary）")
	var houses: Dictionary = state.map["houses"]
	if not houses.has(house_id):
		return Result.failure("MarketingSettlement: houses 缺少 house_id: %s" % house_id)
	var house_val = houses[house_id]
	if not (house_val is Dictionary):
		return Result.failure("MarketingSettlement: houses[%s] 类型错误（期望 Dictionary）" % house_id)
	var house: Dictionary = house_val

	var cap = state.get_rule_int("demand_cap_normal")
	if not house.has("has_garden") or not (house["has_garden"] is bool):
		return Result.failure("MarketingSettlement: houses[%s].has_garden 缺失或类型错误（期望 bool）" % house_id)
	if bool(house["has_garden"]):
		cap = state.get_rule_int("demand_cap_with_garden")

	if house.has("no_demand_cap"):
		var v = house.get("no_demand_cap", false)
		if not (v is bool):
			return Result.failure("MarketingSettlement: houses[%s].no_demand_cap 类型错误（期望 bool）" % house_id)
		if bool(v):
			cap = 2147483647

	if not house.has("demands") or not (house["demands"] is Array):
		return Result.failure("MarketingSettlement: houses[%s].demands 缺失或类型错误（期望 Array）" % house_id)
	var demands: Array = house["demands"]

	# 扩展点：允许房屋声明“营销需求倍增”（例如公寓：每次营销放 2 个 token）
	var demand_multiplier := 1
	if house.has("marketing_demand_multiplier"):
		var m_val = house.get("marketing_demand_multiplier", null)
		if m_val is int:
			demand_multiplier = int(m_val)
		elif m_val is float:
			var f: float = float(m_val)
			if f != floor(f):
				return Result.failure("MarketingSettlement: houses[%s].marketing_demand_multiplier 必须为整数，实际: %s" % [house_id, str(m_val)])
			demand_multiplier = int(f)
		else:
			return Result.failure("MarketingSettlement: houses[%s].marketing_demand_multiplier 类型错误（期望 int/float）" % house_id)
		if demand_multiplier <= 0:
			return Result.failure("MarketingSettlement: houses[%s].marketing_demand_multiplier 必须 > 0，实际: %d" % [house_id, demand_multiplier])

	var effective_amount := amount * demand_multiplier
	if effective_amount < 0:
		return Result.failure("MarketingSettlement: effective_amount 不能为负数: %d" % effective_amount)

	var added := 0
	while added < effective_amount and demands.size() < cap:
		demands.append({
			"product": product,
			"from_player": from_player,
			"board_number": board_number,
			"type": marketing_type
		})
		added += 1

	house["demands"] = demands
	houses[house_id] = house
	state.map["houses"] = houses
	return Result.success(added)

static func _get_demand_amount_for_instance(state: GameState, inst: Dictionary, effect_registry) -> Result:
	assert(state != null, "MarketingSettlement._get_demand_amount_for_instance: state 为空")
	assert(inst != null, "MarketingSettlement._get_demand_amount_for_instance: inst 为空")

	if not inst.has("type") or not (inst["type"] is String):
		return Result.failure("MarketingSettlement: marketing_instances.type 缺失或类型错误（期望 String）")
	if not inst.has("owner") or not (inst["owner"] is int):
		return Result.failure("MarketingSettlement: marketing_instances.owner 缺失或类型错误（期望 int）")
	var marketing_type: String = str(inst["type"])
	var owner: int = int(inst["owner"])

	if effect_registry == null:
		return Result.failure("MarketingSettlement: EffectRegistry 未设置")

	var warnings: Array[String] = []
	var ctx := {
		"marketing_type": marketing_type,
		"demand_amount": 1,
	}
	if inst.has("demand_amount"):
		var base_val = inst.get("demand_amount", null)
		if not (base_val is int):
			return Result.failure("MarketingSettlement: inst.demand_amount 类型错误（期望 int）")
		var base_amount: int = int(base_val)
		if base_amount < 0:
			return Result.failure("MarketingSettlement: inst.demand_amount 不能为负数: %d" % base_amount)
		ctx["demand_amount"] = base_amount

	if owner < 0 or owner >= state.players.size():
		return Result.failure("MarketingSettlement: owner 越界: %d" % owner)
	var player_val = state.players[owner]
	if not (player_val is Dictionary):
		return Result.failure("MarketingSettlement: players[%d] 类型错误（期望 Dictionary）" % owner)
	var player: Dictionary = player_val
	if not player.has("milestones") or not (player["milestones"] is Array):
		return Result.failure("MarketingSettlement: player[%d].milestones 缺失或类型错误（期望 Array）" % owner)
	var milestones: Array = player["milestones"]

	for i in range(milestones.size()):
		var mid_val = milestones[i]
		if not (mid_val is String):
			return Result.failure("MarketingSettlement: player[%d].milestones[%d] 类型错误（期望 String）" % [owner, i])
		var mid: String = str(mid_val)
		if mid.is_empty():
			return Result.failure("MarketingSettlement: player[%d].milestones 不应包含空字符串" % owner)

		var def_val = MilestoneRegistryClass.get_def(mid)
		if def_val == null:
			return Result.failure("MarketingSettlement: 未知里程碑定义: %s" % mid)
		if not (def_val is MilestoneDef):
			return Result.failure("MarketingSettlement: 里程碑定义类型错误（期望 MilestoneDef）: %s" % mid)
		var def: MilestoneDef = def_val

		for eid in def.effect_ids:
			var effect_id: String = eid
			if effect_id.find(EFFECT_SEG_MARKETING_DEMAND_AMOUNT) == -1:
				continue
			var r = effect_registry.invoke(effect_id, [state, owner, ctx])
			if not r.ok:
				return r
			warnings.append_array(r.warnings)

	var v = ctx.get("demand_amount", null)
	if not (v is int):
		return Result.failure("MarketingSettlement: ctx.demand_amount 类型错误（期望 int）")
	var amount: int = int(v)
	if amount < 0:
		return Result.failure("MarketingSettlement: demand_amount 不能为负数: %d" % amount)
	return Result.success(amount).with_warnings(warnings)

static func _apply_marketing_demand_cash_effects(state: GameState, effect_registry, inst: Dictionary, demands_added: int) -> Result:
	assert(state != null, "MarketingSettlement._apply_marketing_demand_cash_effects: state 为空")
	assert(inst != null, "MarketingSettlement._apply_marketing_demand_cash_effects: inst 为空")

	if demands_added <= 0:
		return Result.success()
	if effect_registry == null:
		return Result.failure("MarketingSettlement: EffectRegistry 未设置")

	if not inst.has("owner") or not (inst["owner"] is int):
		return Result.failure("MarketingSettlement: marketing_instances.owner 缺失或类型错误（期望 int）")
	if not inst.has("type") or not (inst["type"] is String):
		return Result.failure("MarketingSettlement: marketing_instances.type 缺失或类型错误（期望 String）")
	if not inst.has("board_number") or not (inst["board_number"] is int):
		return Result.failure("MarketingSettlement: marketing_instances.board_number 缺失或类型错误（期望 int）")
	if not inst.has("product") or not (inst["product"] is String):
		return Result.failure("MarketingSettlement: marketing_instances.product 缺失或类型错误（期望 String）")

	var owner: int = int(inst["owner"])
	var marketing_type: String = str(inst["type"])
	var board_number: int = int(inst["board_number"])
	var product: String = str(inst["product"])

	if owner < 0 or owner >= state.players.size():
		return Result.failure("MarketingSettlement: owner 越界: %d" % owner)
	var player_val = state.players[owner]
	if not (player_val is Dictionary):
		return Result.failure("MarketingSettlement: players[%d] 类型错误（期望 Dictionary）" % owner)
	var player: Dictionary = player_val
	if not player.has("milestones") or not (player["milestones"] is Array):
		return Result.failure("MarketingSettlement: player[%d].milestones 缺失或类型错误（期望 Array）" % owner)
	var milestones: Array = player["milestones"]

	var warnings: Array[String] = []
	var ctx := {
		"marketing_type": marketing_type,
		"board_number": board_number,
		"product": product,
		"demands_added": demands_added,
		"cash_bonus": 0,
		"marketing_instance": inst,
	}

	for i in range(milestones.size()):
		var mid_val = milestones[i]
		if not (mid_val is String):
			return Result.failure("MarketingSettlement: player[%d].milestones[%d] 类型错误（期望 String）" % [owner, i])
		var mid: String = str(mid_val)
		if mid.is_empty():
			return Result.failure("MarketingSettlement: player[%d].milestones 不应包含空字符串" % owner)

		var def_val = MilestoneRegistryClass.get_def(mid)
		if def_val == null:
			return Result.failure("MarketingSettlement: 未知里程碑定义: %s" % mid)
		if not (def_val is MilestoneDef):
			return Result.failure("MarketingSettlement: 里程碑定义类型错误（期望 MilestoneDef）: %s" % mid)
		var def: MilestoneDef = def_val

		for eid in def.effect_ids:
			var effect_id: String = eid
			if effect_id.find(EFFECT_SEG_MARKETING_DEMAND_CASH) == -1:
				continue
			var r = effect_registry.invoke(effect_id, [state, owner, ctx])
			if not r.ok:
				return r
			warnings.append_array(r.warnings)

	var cash_val = ctx.get("cash_bonus", null)
	if not (cash_val is int):
		return Result.failure("MarketingSettlement: ctx.cash_bonus 类型错误（期望 int）")
	var cash_bonus: int = int(cash_val)
	if cash_bonus < 0:
		return Result.failure("MarketingSettlement: ctx.cash_bonus 不能为负数: %d" % cash_bonus)
	if cash_bonus <= 0:
		return Result.success().with_warnings(warnings)

	var pay := BankruptcyRulesClass.pay_bank_to_player(state, owner, cash_bonus, "营销需求奖金")
	if not pay.ok:
		return pay
	warnings.append_array(pay.warnings)
	return Result.success().with_warnings(warnings)

static func _sort_house_ids_by_number(state: GameState, house_ids: Array[String]) -> Array[String]:
	if house_ids.is_empty():
		return []
	assert(state != null, "MarketingSettlement._sort_house_ids_by_number: state 为空")
	assert(state.map is Dictionary, "MarketingSettlement._sort_house_ids_by_number: state.map 类型错误（期望 Dictionary）")
	assert(state.map.has("houses") and (state.map["houses"] is Dictionary), "MarketingSettlement._sort_house_ids_by_number: state.map.houses 缺失或类型错误（期望 Dictionary）")
	var houses: Dictionary = state.map["houses"]

	var subset := {}
	var seen := {}
	for hid in house_ids:
		assert(hid is String and not str(hid).is_empty(), "MarketingSettlement._sort_house_ids_by_number: house_id 不能为空")
		var id: String = str(hid)
		assert(not seen.has(id), "MarketingSettlement._sort_house_ids_by_number: 重复 house_id: %s" % id)
		seen[id] = true
		assert(houses.has(id), "MarketingSettlement._sort_house_ids_by_number: house_id 不存在: %s" % id)
		assert(houses[id] is Dictionary, "MarketingSettlement._sort_house_ids_by_number: houses[%s] 类型错误（期望 Dictionary）" % id)
		subset[id] = houses[id]

	return HouseNumberManagerClass.get_sorted_house_ids(subset)
