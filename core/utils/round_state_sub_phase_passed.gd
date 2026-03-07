# RoundState：sub_phase_passed 读写工具（Fail Fast）
class_name RoundStateSubPhasePassed
extends RefCounted

static func _prefix(label: String) -> String:
	if label.is_empty():
		return ""
	if label.ends_with(": "):
		return label
	if label.ends_with("： "):
		return label
	if label.ends_with(":"):
		return "%s " % label
	if label.ends_with("："):
		return "%s " % label
	return "%s: " % label

static func require_sub_phase_passed(round_state: Dictionary, prefix_label: String) -> Result:
	var prefix := _prefix(prefix_label)
	if not (round_state is Dictionary):
		return Result.failure("%sround_state 类型错误（期望 Dictionary）" % prefix)
	if not round_state.has("sub_phase_passed") or not (round_state["sub_phase_passed"] is Dictionary):
		return Result.failure("%sround_state.sub_phase_passed 缺失或类型错误（期望 Dictionary）" % prefix)
	return Result.success(round_state["sub_phase_passed"])

static func require_all_player_flags(round_state: Dictionary, player_count: int, prefix_label: String) -> Result:
	var prefix := _prefix(prefix_label)
	if player_count < 0:
		return Result.failure("%splayer_count 不能为负数: %d" % [prefix, player_count])
	var passed_read := require_sub_phase_passed(round_state, prefix_label)
	if not passed_read.ok:
		return passed_read
	var passed: Dictionary = passed_read.value
	for pid in range(player_count):
		if not passed.has(pid) or not (passed[pid] is bool):
			return Result.failure("%sround_state.sub_phase_passed[%d] 缺失或类型错误（期望 bool）" % [prefix, pid])
	return Result.success(passed)

static func set_player_passed(round_state: Dictionary, player_id: int, passed_value: bool, prefix_label: String) -> Result:
	var prefix := _prefix(prefix_label)
	if player_id < 0:
		return Result.failure("%splayer_id 不能为负数: %d" % [prefix, player_id])
	var passed_read := require_sub_phase_passed(round_state, prefix_label)
	if not passed_read.ok:
		return passed_read
	var passed: Dictionary = passed_read.value
	if not passed.has(player_id) or not (passed[player_id] is bool):
		return Result.failure("%sround_state.sub_phase_passed[%d] 缺失或类型错误（期望 bool）" % [prefix, player_id])
	passed[player_id] = passed_value
	round_state["sub_phase_passed"] = passed
	return Result.success(passed)

static func reset_flags(round_state: Dictionary, player_count: int, prefix_label: String) -> Result:
	var prefix := _prefix(prefix_label)
	if not (round_state is Dictionary):
		return Result.failure("%sround_state 类型错误（期望 Dictionary）" % prefix)
	if player_count < 0:
		return Result.failure("%splayer_count 不能为负数: %d" % [prefix, player_count])
	var passed := {}
	for pid in range(player_count):
		passed[pid] = false
	round_state["sub_phase_passed"] = passed
	return Result.success(passed)

static func get_flags_or_empty(round_state) -> Dictionary:
	if not (round_state is Dictionary):
		return {}
	var passed_read := require_sub_phase_passed(round_state, "")
	if not passed_read.ok:
		return {}
	return passed_read.value
