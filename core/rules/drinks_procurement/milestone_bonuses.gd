extends RefCounted

const MilestoneEffectQueriesClass = preload("res://core/rules/milestone_effect_queries.gd")
const IntValueParseHelpersClass = preload("res://core/utils/int_value_parse_helpers.gd")
const PlayerStateAccessClass = preload("res://core/state/player_state_access.gd")

static func get_drinks_per_source_bonus_from_milestones(state: GameState, player_id: int) -> Result:
	var milestones_read := PlayerStateAccessClass.require_player_milestones(state, player_id, "DrinksProcurement")
	if not milestones_read.ok:
		return milestones_read
	var milestones: Array = milestones_read.value

	return MilestoneEffectQueriesClass.sum_positive_int_values(
		milestones,
		"procure_plus_one",
		"DrinksProcurement: ",
		"milestones"
	)

static func get_drinks_per_source_delta_for_employee_from_milestones(state: GameState, player_id: int, employee_id: String) -> Result:
	if employee_id.is_empty():
		return Result.failure("DrinksProcurement: employee_id 不能为空")

	var milestones_read := PlayerStateAccessClass.require_player_milestones(state, player_id, "DrinksProcurement")
	if not milestones_read.ok:
		return milestones_read
	var milestones: Array = milestones_read.value

	var bonus := 0
	var entries_read := MilestoneEffectQueriesClass.collect_effect_entries(
		milestones,
		"drinks_per_source_delta",
		"DrinksProcurement: ",
		"milestones"
	)
	if not entries_read.ok:
		return entries_read
	var entries: Array = entries_read.value
	for entry_val in entries:
		var entry: Dictionary = entry_val
		var mid: String = str(entry.get("milestone_id", ""))
		var e_i: int = int(entry.get("effect_index", -1))
		var eff_val = entry.get("effect", null)
		var eff: Dictionary = eff_val

		if not eff.has("targets") or not (eff["targets"] is Array):
			return Result.failure("DrinksProcurement: %s.effects[%d].targets 缺失或类型错误（期望 Array）" % [mid, e_i])
		var targets: Array = eff["targets"]
		var hit := false
		for j in range(targets.size()):
			var target_val = targets[j]
			if not (target_val is String):
				return Result.failure("DrinksProcurement: %s.effects[%d].targets[%d] 类型错误（期望 String）" % [mid, e_i, j])
			if str(target_val) == employee_id:
				hit = true
				break
		if not hit:
			continue

		var value_val = eff.get("value", null)
		var v_read := IntValueParseHelpersClass.parse_positive_int_value(value_val, "%s.effects[%d].value" % [mid, e_i])
		if not v_read.ok:
			return Result.failure("DrinksProcurement: %s" % v_read.error)
		bonus += int(v_read.value)

	return Result.success(bonus)

static func get_distance_range_bonus_from_milestones(state: GameState, player_id: int, employee_id: String) -> Result:
	if employee_id.is_empty():
		return Result.failure("DrinksProcurement: employee_id 不能为空")

	var milestones_read := PlayerStateAccessClass.require_player_milestones(state, player_id, "DrinksProcurement")
	if not milestones_read.ok:
		return milestones_read
	var milestones: Array = milestones_read.value

	var bonus := 0
	var entries_read := MilestoneEffectQueriesClass.collect_effect_entries(
		milestones,
		"distance_plus_one",
		"DrinksProcurement: ",
		"milestones"
	)
	if not entries_read.ok:
		return entries_read
	var entries: Array = entries_read.value
	for entry_val in entries:
		var entry: Dictionary = entry_val
		var mid: String = str(entry.get("milestone_id", ""))
		var e_i: int = int(entry.get("effect_index", -1))
		var eff_val = entry.get("effect", null)
		var eff: Dictionary = eff_val

		if not eff.has("targets") or not (eff["targets"] is Array):
			return Result.failure("DrinksProcurement: %s.effects[%d].targets 缺失或类型错误（期望 Array）" % [mid, e_i])
		var targets: Array = eff["targets"]
		for j in range(targets.size()):
			var target_val = targets[j]
			if not (target_val is String):
				return Result.failure("DrinksProcurement: %s.effects[%d].targets[%d] 类型错误（期望 String）" % [mid, e_i, j])
			var target: String = str(target_val)
			if target.is_empty():
				return Result.failure("DrinksProcurement: %s.effects[%d].targets[%d] 不能为空" % [mid, e_i, j])
			if target == employee_id:
				bonus += 1
				break

	return Result.success(bonus)
