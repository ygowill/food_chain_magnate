# 里程碑 effects 查询辅助（Result 风格）
# 用途：收敛多处重复的 “遍历 milestones -> MilestoneDef.effects -> type/value” 解析样板。
class_name MilestoneEffectQueries
extends RefCounted

const MilestoneRegistryClass = preload("res://core/data/milestone_registry.gd")
const MilestoneDefClass = preload("res://core/data/milestone_def.gd")
const IntValueParseHelpersClass = preload("res://core/utils/int_value_parse_helpers.gd")

static func collect_effect_entries(milestones: Array, effect_type: String, prefix: String, milestones_path: String) -> Result:
	if effect_type.is_empty():
		return Result.failure("%seffect_type 不能为空" % prefix)
	if milestones_path.is_empty():
		milestones_path = "milestones"

	if not MilestoneRegistryClass.is_loaded():
		return Result.failure("%sMilestoneRegistry 未初始化" % prefix)

	var out: Array[Dictionary] = []

	for i in range(milestones.size()):
		var mid_val = milestones[i]
		if not (mid_val is String):
			return Result.failure("%s%s[%d] 类型错误（期望 String）" % [prefix, milestones_path, i])
		var mid: String = str(mid_val)
		if mid.is_empty():
			return Result.failure("%s%s 不应包含空字符串" % [prefix, milestones_path])

		var def_val = MilestoneRegistryClass.get_def(mid)
		if def_val == null:
			return Result.failure("%s未知里程碑定义: %s" % [prefix, mid])
		if not (def_val is MilestoneDefClass):
			return Result.failure("%s里程碑定义类型错误（期望 MilestoneDef）: %s" % [prefix, mid])
		var def: MilestoneDef = def_val

		for e_i in range(def.effects.size()):
			var eff_val = def.effects[e_i]
			if not (eff_val is Dictionary):
				return Result.failure("%s%s.effects[%d] 类型错误（期望 Dictionary）" % [prefix, mid, e_i])
			var eff: Dictionary = eff_val
			var type_val = eff.get("type", null)
			if not (type_val is String):
				return Result.failure("%s%s.effects[%d].type 类型错误（期望 String）" % [prefix, mid, e_i])
			var t: String = str(type_val)
			if t != effect_type:
				continue

			out.append({
				"milestone_id": mid,
				"effect_index": e_i,
				"effect": eff,
			})

	return Result.success(out)

static func sum_int_values(milestones: Array, effect_type: String, prefix: String, milestones_path: String) -> Result:
	var total := 0
	var entries_read := collect_effect_entries(milestones, effect_type, prefix, milestones_path)
	if not entries_read.ok:
		return entries_read
	var entries: Array = entries_read.value
	for entry_val in entries:
		var entry: Dictionary = entry_val
		var mid: String = str(entry.get("milestone_id", ""))
		var e_i: int = int(entry.get("effect_index", -1))
		var eff_val = entry.get("effect", null)
		var eff: Dictionary = eff_val

		var value_val = eff.get("value", null)
		var v_read := IntValueParseHelpersClass.parse_int_value(value_val, "%s.effects[%d].value" % [mid, e_i])
		if not v_read.ok:
			return Result.failure("%s%s" % [prefix, v_read.error])
		total += int(v_read.value)

	return Result.success(total)

static func sum_non_negative_int_values(milestones: Array, effect_type: String, prefix: String, milestones_path: String) -> Result:
	var total := 0
	var entries_read := collect_effect_entries(milestones, effect_type, prefix, milestones_path)
	if not entries_read.ok:
		return entries_read
	var entries: Array = entries_read.value
	for entry_val in entries:
		var entry: Dictionary = entry_val
		var mid: String = str(entry.get("milestone_id", ""))
		var e_i: int = int(entry.get("effect_index", -1))
		var eff_val = entry.get("effect", null)
		var eff: Dictionary = eff_val

		var value_val = eff.get("value", null)
		var v_read := IntValueParseHelpersClass.parse_non_negative_int_value(value_val, "%s.effects[%d].value" % [mid, e_i])
		if not v_read.ok:
			return Result.failure("%s%s" % [prefix, v_read.error])
		total += int(v_read.value)

	return Result.success(total)

static func sum_positive_int_values(milestones: Array, effect_type: String, prefix: String, milestones_path: String) -> Result:
	var total := 0
	var entries_read := collect_effect_entries(milestones, effect_type, prefix, milestones_path)
	if not entries_read.ok:
		return entries_read
	var entries: Array = entries_read.value
	for entry_val in entries:
		var entry: Dictionary = entry_val
		var mid: String = str(entry.get("milestone_id", ""))
		var e_i: int = int(entry.get("effect_index", -1))
		var eff_val = entry.get("effect", null)
		var eff: Dictionary = eff_val

		var value_val = eff.get("value", null)
		var v_read := IntValueParseHelpersClass.parse_positive_int_value(value_val, "%s.effects[%d].value" % [mid, e_i])
		if not v_read.ok:
			return Result.failure("%s%s" % [prefix, v_read.error])
		total += int(v_read.value)

	return Result.success(total)

static func max_non_negative_int_value(milestones: Array, effect_type: String, prefix: String, milestones_path: String) -> Result:
	var found := false
	var best := 0

	var entries_read := collect_effect_entries(milestones, effect_type, prefix, milestones_path)
	if not entries_read.ok:
		return entries_read
	var entries: Array = entries_read.value
	for entry_val in entries:
		var entry: Dictionary = entry_val
		var mid: String = str(entry.get("milestone_id", ""))
		var e_i: int = int(entry.get("effect_index", -1))
		var eff_val = entry.get("effect", null)
		var eff: Dictionary = eff_val

		var value_val = eff.get("value", null)
		var v_read := IntValueParseHelpersClass.parse_non_negative_int_value(value_val, "%s.effects[%d].value" % [mid, e_i])
		if not v_read.ok:
			return Result.failure("%s%s" % [prefix, v_read.error])
		found = true
		best = maxi(best, int(v_read.value))

	return Result.success({
		"found": found,
		"value": best,
	})
