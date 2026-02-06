# MarketingSettlement：营销需求 effects（从 settlement_helpers_impl.gd 抽离）
extends RefCounted

const BankruptcyRulesClass = preload("res://core/rules/economy/bankruptcy_rules.gd")
const MilestoneRegistryClass = preload("res://core/data/milestone_registry.gd")
const EffectIdsSegmentInvokerClass = preload("res://core/rules/effect_ids_segment_invoker.gd")
const PlayerStateAccessClass = preload("res://core/state/player_state_access.gd")

const EFFECT_SEG_MARKETING_DEMAND_AMOUNT := ":marketing:demand_amount:"
const EFFECT_SEG_MARKETING_DEMAND_CASH := ":marketing:demand_cash:"

static func get_demand_amount_for_instance(state: GameState, inst: Dictionary, effect_registry) -> Result:
	if state == null:
		return Result.failure("MarketingSettlement: state 为空")
	if inst == null:
		return Result.failure("MarketingSettlement: inst 为空")

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
	var milestones_read := PlayerStateAccessClass.require_milestones(player, "player[%d]" % owner, "MarketingSettlement")
	if not milestones_read.ok:
		return milestones_read
	var milestones: Array = milestones_read.value

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

		var inv := EffectIdsSegmentInvokerClass.invoke_effect_ids_by_segment(
			effect_registry,
			def.effect_ids,
			EFFECT_SEG_MARKETING_DEMAND_AMOUNT,
			[state, owner, ctx],
			"MarketingSettlement",
			"MilestoneDef[%s].effect_ids" % mid
		)
		if not inv.ok:
			return inv
		warnings.append_array(inv.warnings)

	var v = ctx.get("demand_amount", null)
	if not (v is int):
		return Result.failure("MarketingSettlement: ctx.demand_amount 类型错误（期望 int）")
	var amount: int = int(v)
	if amount < 0:
		return Result.failure("MarketingSettlement: demand_amount 不能为负数: %d" % amount)
	return Result.success(amount).with_warnings(warnings)

static func apply_marketing_demand_cash_effects(state: GameState, effect_registry, inst: Dictionary, demands_added: int) -> Result:
	if state == null:
		return Result.failure("MarketingSettlement: state 为空")
	if inst == null:
		return Result.failure("MarketingSettlement: inst 为空")

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
	var milestones_read := PlayerStateAccessClass.require_milestones(player, "player[%d]" % owner, "MarketingSettlement")
	if not milestones_read.ok:
		return milestones_read
	var milestones: Array = milestones_read.value

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

		var inv := EffectIdsSegmentInvokerClass.invoke_effect_ids_by_segment(
			effect_registry,
			def.effect_ids,
			EFFECT_SEG_MARKETING_DEMAND_CASH,
			[state, owner, ctx],
			"MarketingSettlement",
			"MilestoneDef[%s].effect_ids" % mid
		)
		if not inv.ok:
			return inv
		warnings.append_array(inv.warnings)

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
