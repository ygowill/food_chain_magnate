# Dinnertime 结算（从 PhaseManager 抽离）
# 目标：聚合 Dinnertime 阶段“选店/售卖/里程碑/银行破产”逻辑，便于测试与复用。
class_name DinnertimeSettlement
extends RefCounted

const ImplClass = preload("res://modules/base_rules/rules/phase/dinnertime/dinnertime_settlement_impl.gd")
const DinnertimeEffectsClass = preload("res://modules/base_rules/rules/phase/dinnertime/dinnertime_effects.gd")

static func apply(state: GameState, phase_manager = null) -> Result:
	return ImplClass.apply(state, phase_manager)

static func _apply_employee_effects_by_segment(
	state: GameState,
	player_id: int,
	effect_registry,
	segment: String,
	ctx: Dictionary
) -> Result:
	return DinnertimeEffectsClass.apply_employee_effects_by_segment(state, player_id, effect_registry, segment, ctx)

static func _apply_milestone_effects_by_segment(
	state: GameState,
	player_id: int,
	effect_registry,
	segment: String,
	ctx: Dictionary
) -> Result:
	return DinnertimeEffectsClass.apply_milestone_effects_by_segment(state, player_id, effect_registry, segment, ctx)

static func _apply_global_effects_by_segment(
	state: GameState,
	player_id_for_ctx: int,
	effect_registry,
	segment: String,
	ctx: Dictionary
) -> Result:
	return DinnertimeEffectsClass.apply_global_effects_by_segment(state, player_id_for_ctx, effect_registry, segment, ctx)
