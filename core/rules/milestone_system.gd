# 里程碑系统（M5 起步）
# 通过“事件名 + 上下文”触发里程碑，并写入 state.players[*].milestones（延迟到 Cleanup 再从 supply 移除）。
class_name MilestoneSystem
extends RefCounted

const MilestoneRegistryClass = preload("res://core/data/milestone_registry.gd")
const StateUpdaterClass = preload("res://core/state/state_updater.gd")
const ProductRegistryClass = preload("res://core/data/product_registry.gd")
const MilestoneEffectRegistryClass = preload("res://core/rules/milestone_effect_registry.gd")

static func process_event(state: GameState, event_name: String, context: Dictionary) -> Result:
	if state == null:
		return Result.failure("state 为空")
	if event_name.is_empty():
		return Result.success()
	if not (context is Dictionary):
		return Result.failure("context 必须为 Dictionary")

	var player_id := int(context.get("player_id", -1))
	if player_id < 0:
		return Result.success()

	var effect_registry = MilestoneEffectRegistryClass.get_current()
	if effect_registry == null:
		return Result.failure("MilestoneEffectRegistry 未设置")

	var ctx: Dictionary = context.duplicate(true)
	var normalize := _normalize_context(ctx)
	if not normalize.ok:
		return normalize

	var candidates: Array[String] = []
	for mid in state.milestone_pool:
		candidates.append(str(mid))
	candidates.sort()

	var claimed: Array[String] = []
	for milestone_id in candidates:
		if StateUpdaterClass.player_has_milestone(state, player_id, milestone_id):
			continue
		var def = MilestoneRegistryClass.get_def(milestone_id)
		if def == null:
			continue
		if not def.matches(event_name, ctx):
			continue

		var claim := StateUpdaterClass.claim_milestone(state, player_id, milestone_id)
		if claim.ok:
			var apply := _apply_milestone_effects(effect_registry, state, player_id, milestone_id, def)
			if not apply.ok:
				return apply
			claimed.append(milestone_id)

	if state.round_state is Dictionary and not claimed.is_empty():
		if not state.round_state.has("milestones_auto_awarded"):
			state.round_state["milestones_auto_awarded"] = []
		var log: Array = state.round_state["milestones_auto_awarded"]
		for mid in claimed:
			log.append({
				"player_id": player_id,
				"milestone_id": mid,
				"event": event_name,
				"context": ctx
			})
		state.round_state["milestones_auto_awarded"] = log

	return Result.success({"claimed": claimed})

static func _apply_milestone_effects(effect_registry, state: GameState, player_id: int, milestone_id: String, def: MilestoneDef) -> Result:
	assert(effect_registry != null, "MilestoneSystem._apply_milestone_effects: effect_registry 为空")
	assert(state != null, "MilestoneSystem._apply_milestone_effects: state 为空")
	assert(player_id >= 0 and player_id < state.players.size(), "MilestoneSystem._apply_milestone_effects: player_id 越界: %d" % player_id)
	assert(def != null, "MilestoneSystem._apply_milestone_effects: def 为空")

	var warnings: Array[String] = []

	for i in range(def.effects.size()):
		var eff_val = def.effects[i]
		if not (eff_val is Dictionary):
			return Result.failure("MilestoneSystem: %s.effects[%d] 类型错误（期望 Dictionary）" % [milestone_id, i])
		var eff: Dictionary = eff_val
		var type_val = eff.get("type", null)
		if not (type_val is String):
			return Result.failure("MilestoneSystem: %s.effects[%d].type 类型错误（期望 String）" % [milestone_id, i])
		var t: String = str(type_val)
		if t.is_empty():
			return Result.failure("MilestoneSystem: %s.effects[%d].type 不能为空" % [milestone_id, i])

		var r = effect_registry.invoke(t, [state, player_id, milestone_id, eff])
		if not r.ok:
			return r
		warnings.append_array(r.warnings)

	return Result.success().with_warnings(warnings)

static func _normalize_context(ctx: Dictionary) -> Result:
	# 支持里程碑 JSON 中用 "drink" 作为饮品类筛选（而不是 soda/lemonade/beer）。
	if not ctx.has("product"):
		return Result.success()

	var product_val = ctx.get("product", null)
	if not (product_val is String):
		return Result.failure("context.product 类型错误（期望 String）")
	var p: String = str(product_val)
	if p.is_empty():
		return Result.failure("context.product 不能为空")

	if p == "drink":
		return Result.success()

	if not ProductRegistryClass.is_loaded():
		return Result.failure("ProductRegistry 未初始化")
	if ProductRegistryClass.get_def(p) == null:
		return Result.failure("未知产品: %s" % p)
	if ProductRegistryClass.is_drink(p):
		ctx["product_id"] = p
		ctx["product"] = "drink"

	return Result.success()
