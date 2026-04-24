# Marketing 结算（从 PhaseManager 抽离）
# 目标：聚合 Marketing 阶段“营销实例结算/需求生成/到期清理”逻辑，便于测试与复用。
class_name MarketingSettlement
extends RefCounted

const MarketingRangeCalculatorClass = preload("res://core/rules/marketing_range_calculator.gd")
const MilestoneSystemClass = preload("res://core/rules/milestone_system.gd")
const HelpersClass = preload("res://modules/base_rules/rules/phase/marketing/settlement_helpers.gd")
const MarketingInstancesValidationClass = preload("res://modules/base_rules/rules/phase/marketing/marketing_instances_validation.gd")
const MapStateAccessClass = preload("res://core/state/map_state_access.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const RoundStatePendingPhaseActionsClass = preload("res://core/utils/round_state_pending_phase_actions.gd")

const KIND_CONFIRM_MARKETING := "confirm_marketing"
const ONLINE_MARKETING_CONFIRM_KEY := "online_require_marketing_confirm"
const ONLINE_MARKETING_CONFIRMED_PLAYERS_KEY := "online_marketing_confirmed_players"

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
			"expired": [],
			"timeline_events": [],
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
	var timeline_events: Array[Dictionary] = []

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
			timeline_events.append(_build_campaign_start_event(_round_index, inst, products_in_order, affected, demand_amount))
			for p in products_in_order:
				var added_for_product := 0
				for house_id in affected:
					var before_snapshot := _read_house_demand_snapshot(state, str(house_id), demand_amount)
					if not before_snapshot.ok:
						return before_snapshot
					var add_result := _add_house_demand(state, house_id, p, owner, board_number, marketing_type, demand_amount)
					if not add_result.ok:
						return add_result
					var after_snapshot := _read_house_demand_snapshot(state, str(house_id), demand_amount)
					if not after_snapshot.ok:
						return after_snapshot
					timeline_events.append(_build_house_demand_event(
						_round_index,
						inst,
						str(house_id),
						str(p),
						before_snapshot.value,
						after_snapshot.value,
						int(add_result.value)
					))
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
		timeline_events.append(_build_duration_tick_event(inst, before_duration, after_duration, expired_now))

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
		"expired": expired,
		"timeline_events": timeline_events,
	}

	var pending_r := _inject_marketing_confirm_pending_if_needed(state, not processed.is_empty() or not expired.is_empty())
	if not pending_r.ok:
		return pending_r

	return Result.success().with_warnings(warnings)

static func _inject_marketing_confirm_pending_if_needed(state: GameState, has_animation_report: bool) -> Result:
	if state == null:
		return Result.failure("MarketingSettlement: state 为空")
	if not has_animation_report:
		return Result.success()
	if not (state.round_state is Dictionary):
		return Result.failure("MarketingSettlement: state.round_state 类型错误（期望 Dictionary）")

	# 离线/本地 headless 测试继续自动跳过 Marketing；图形界面和联机模式需要等待动画确认。
	var online_marketing_confirm_enabled := _is_online_marketing_confirm_enabled(state)
	var should_inject_pending := (DisplayServer.get_name() != "headless") or online_marketing_confirm_enabled
	if not should_inject_pending:
		return Result.success()

	if online_marketing_confirm_enabled:
		state.round_state[ONLINE_MARKETING_CONFIRMED_PLAYERS_KEY] = _build_online_marketing_confirmed_players(state)
	var pending := _build_marketing_confirm_pending(state)
	return RoundStatePendingPhaseActionsClass.set_phase_pending_players(
		state.round_state, DefsClass.PHASE_MARKETING, pending, "营销结算"
	)

static func _is_online_mode() -> bool:
	if NetContext == null:
		return false
	return NetContext.mode == NetContext.Mode.ONLINE_CLIENT or NetContext.mode == NetContext.Mode.ONLINE_SERVER

static func _is_online_marketing_confirm_enabled(state: GameState) -> bool:
	if _is_online_mode():
		return true

	var v = _read_online_marketing_confirm_marker(state)
	if v is bool:
		return bool(v)
	if v is int:
		return int(v) > 0
	if v is float:
		var f: float = float(v)
		if f == floor(f):
			return int(f) > 0
	return _is_online_mode()

static func _read_online_marketing_confirm_marker(state: GameState):
	if state == null:
		return null
	if state.rules is Dictionary:
		var rules: Dictionary = state.rules
		if rules.has(ONLINE_MARKETING_CONFIRM_KEY):
			return rules.get(ONLINE_MARKETING_CONFIRM_KEY, null)
	if state.round_state is Dictionary:
		var rs: Dictionary = state.round_state
		if rs.has(ONLINE_MARKETING_CONFIRM_KEY):
			return rs.get(ONLINE_MARKETING_CONFIRM_KEY, null)
	return null

static func _build_marketing_confirm_pending(state: GameState) -> Array:
	if state == null or not (state.players is Array):
		return []
	if not _is_online_marketing_confirm_enabled(state):
		return [KIND_CONFIRM_MARKETING]
	var confirmed_players := _read_online_marketing_confirmed_players(state)
	if confirmed_players.is_empty():
		confirmed_players = _build_online_marketing_confirmed_players(state)
	var pending: Array[Dictionary] = []
	for pid in range(state.players.size()):
		var is_confirmed := false
		if pid >= 0 and pid < confirmed_players.size():
			is_confirmed = bool(confirmed_players[pid])
		if is_confirmed:
			continue
		pending.append({
			"kind": KIND_CONFIRM_MARKETING,
			"player_id": pid,
		})
	return pending

static func _build_online_marketing_confirmed_players(state: GameState) -> Array[bool]:
	var confirmed: Array[bool] = []
	if state == null or not (state.players is Array):
		return confirmed
	for pid in range(state.players.size()):
		confirmed.append(_is_player_forfeited(state, pid))
	return confirmed

static func _read_online_marketing_confirmed_players(state: GameState) -> Array[bool]:
	var out: Array[bool] = []
	if state == null or not (state.players is Array):
		return out
	if not (state.round_state is Dictionary):
		return out
	var rs: Dictionary = state.round_state
	var val = rs.get(ONLINE_MARKETING_CONFIRMED_PLAYERS_KEY, null)
	if not (val is Array):
		return out
	var raw: Array = Array(val)
	if raw.size() != state.players.size():
		return out
	for v in raw:
		if v is bool:
			out.append(bool(v))
			continue
		if v is int:
			out.append(int(v) != 0)
			continue
		if v is float:
			var f: float = float(v)
			if f == floor(f):
				out.append(int(f) != 0)
				continue
		return []
	return out

static func _is_player_forfeited(state: GameState, player_id: int) -> bool:
	if state == null or not (state.players is Array):
		return false
	if player_id < 0 or player_id >= state.players.size():
		return false
	var player_val = state.players[player_id]
	if not (player_val is Dictionary):
		return false
	return bool(Dictionary(player_val).get("forfeited", false))

static func _build_campaign_start_event(round_index: int, inst: Dictionary, products_in_order: Array, affected: Array, demand_amount: int) -> Dictionary:
	return {
		"kind": "campaign_start",
		"round_index": int(round_index),
		"board_number": int(inst.get("board_number", 0)),
		"type": str(inst.get("type", "")),
		"owner": int(inst.get("owner", -1)),
		"employee_type": str(inst.get("employee_type", "")),
		"product": str(inst.get("product", "")),
		"products": products_in_order.duplicate(true),
		"world_pos": _vector2i_to_array(inst.get("world_pos", Vector2i.ZERO)),
		"footprint_size": _vector2i_to_array(inst.get("footprint_size", Vector2i.ONE)),
		"rotation": _read_integral(inst.get("rotation", 0), 0),
		"axis": str(inst.get("axis", "")),
		"affected_houses": affected.duplicate(true),
		"demand_amount": int(demand_amount),
	}

static func _build_house_demand_event(
	round_index: int,
	inst: Dictionary,
	house_id: String,
	product: String,
	before_snapshot: Dictionary,
	after_snapshot: Dictionary,
	amount_added: int
) -> Dictionary:
	return {
		"kind": "house_demand",
		"round_index": int(round_index),
		"board_number": int(inst.get("board_number", 0)),
		"type": str(inst.get("type", "")),
		"owner": int(inst.get("owner", -1)),
		"product": product,
		"world_pos": _vector2i_to_array(inst.get("world_pos", Vector2i.ZERO)),
		"house_id": house_id,
		"house_number": before_snapshot.get("house_number", house_id),
		"amount_requested": int(before_snapshot.get("effective_amount", 0)),
		"amount_added": int(amount_added),
		"demand_before": int(before_snapshot.get("demand_count", 0)),
		"demand_after": int(after_snapshot.get("demand_count", 0)),
		"cap": int(before_snapshot.get("cap", 0)),
		"has_garden": bool(before_snapshot.get("has_garden", false)),
	}

static func _build_duration_tick_event(inst: Dictionary, before_duration: int, after_duration: int, expired_now: bool) -> Dictionary:
	return {
		"kind": "duration_tick",
		"board_number": int(inst.get("board_number", 0)),
		"type": str(inst.get("type", "")),
		"owner": int(inst.get("owner", -1)),
		"employee_type": str(inst.get("employee_type", "")),
		"product": str(inst.get("product", "")),
		"world_pos": _vector2i_to_array(inst.get("world_pos", Vector2i.ZERO)),
		"footprint_size": _vector2i_to_array(inst.get("footprint_size", Vector2i.ONE)),
		"rotation": _read_integral(inst.get("rotation", 0), 0),
		"axis": str(inst.get("axis", "")),
		"duration_before": int(before_duration),
		"duration_after": int(after_duration),
		"expired": bool(expired_now),
	}

static func _read_house_demand_snapshot(state: GameState, house_id: String, base_amount: int) -> Result:
	var houses_read := MapStateAccessClass.require_houses(state, "MarketingSettlement.timeline")
	if not houses_read.ok:
		return houses_read
	var houses: Dictionary = houses_read.value
	if not houses.has(house_id):
		return Result.failure("MarketingSettlement.timeline: houses 缺少 house_id: %s" % house_id)
	var house_val = houses[house_id]
	if not (house_val is Dictionary):
		return Result.failure("MarketingSettlement.timeline: houses[%s] 类型错误（期望 Dictionary）" % house_id)
	var house: Dictionary = house_val

	if not house.has("has_garden") or not (house["has_garden"] is bool):
		return Result.failure("MarketingSettlement.timeline: houses[%s].has_garden 缺失或类型错误（期望 bool）" % house_id)
	var has_garden := bool(house["has_garden"])
	var cap := state.get_rule_int("demand_cap_with_garden") if has_garden else state.get_rule_int("demand_cap_normal")
	if house.has("no_demand_cap"):
		var cap_val = house.get("no_demand_cap", false)
		if not (cap_val is bool):
			return Result.failure("MarketingSettlement.timeline: houses[%s].no_demand_cap 类型错误（期望 bool）" % house_id)
		if bool(cap_val):
			cap = 2147483647

	if not house.has("demands") or not (house["demands"] is Array):
		return Result.failure("MarketingSettlement.timeline: houses[%s].demands 缺失或类型错误（期望 Array）" % house_id)
	var demands: Array = house["demands"]
	var demand_multiplier := 1
	if house.has("marketing_demand_multiplier"):
		var m_val = house.get("marketing_demand_multiplier", null)
		if m_val is int:
			demand_multiplier = int(m_val)
		elif m_val is float:
			var f: float = float(m_val)
			if f != floor(f):
				return Result.failure("MarketingSettlement.timeline: houses[%s].marketing_demand_multiplier 必须为整数，实际: %s" % [house_id, str(m_val)])
			demand_multiplier = int(f)
		else:
			return Result.failure("MarketingSettlement.timeline: houses[%s].marketing_demand_multiplier 类型错误（期望 int/float）" % house_id)
		if demand_multiplier <= 0:
			return Result.failure("MarketingSettlement.timeline: houses[%s].marketing_demand_multiplier 必须 > 0，实际: %d" % [house_id, demand_multiplier])

	return Result.success({
		"house_number": house.get("house_number", house_id),
		"demand_count": demands.size(),
		"cap": int(cap),
		"has_garden": has_garden,
		"effective_amount": int(base_amount) * int(demand_multiplier),
	})

static func _vector2i_to_array(value) -> Array:
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

static func _read_integral(value, fallback: int = 0) -> int:
	if value is int:
		return int(value)
	if value is float:
		var f: float = float(value)
		if f == floor(f):
			return int(f)
	return int(fallback)

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
