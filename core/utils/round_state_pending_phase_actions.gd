# RoundState：pending_phase_actions 读写工具（Fail Fast）
# 用途：统一 round_state.pending_phase_actions 的读取/校验/写入，减少重复样板。
class_name RoundStatePendingPhaseActions
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

static func is_phase_blocked(round_state: Dictionary, phase_name: String, prefix_label: String) -> Result:
	var prefix := _prefix(prefix_label)
	if not (round_state is Dictionary):
		return Result.failure("%sround_state 类型错误（期望 Dictionary）" % prefix)
	if phase_name.is_empty():
		return Result.failure("%sphase_name 不能为空" % prefix)

	if not round_state.has("pending_phase_actions"):
		return Result.success(false)

	var ppa_val = round_state.get("pending_phase_actions", null)
	if not (ppa_val is Dictionary):
		return Result.failure("%sround_state.pending_phase_actions 类型错误（期望 Dictionary）" % prefix)
	var ppa: Dictionary = ppa_val

	if not ppa.has(phase_name):
		return Result.success(false)

	var list_val = ppa.get(phase_name, null)
	if not (list_val is Array):
		return Result.failure("%sround_state.pending_phase_actions[%s] 类型错误（期望 Array）" % [prefix, phase_name])
	var list: Array = list_val
	return Result.success(not list.is_empty())

static func set_phase_pending_players(round_state: Dictionary, phase_name: String, pending: Array, prefix_label: String) -> Result:
	var prefix := _prefix(prefix_label)
	if not (round_state is Dictionary):
		return Result.failure("%sround_state 类型错误（期望 Dictionary）" % prefix)
	if phase_name.is_empty():
		return Result.failure("%sphase_name 不能为空" % prefix)
	if not (pending is Array):
		return Result.failure("%spending 类型错误（期望 Array）" % prefix)

	if not round_state.has("pending_phase_actions"):
		round_state["pending_phase_actions"] = {}

	var ppa_val = round_state.get("pending_phase_actions", null)
	if not (ppa_val is Dictionary):
		return Result.failure("%sround_state.pending_phase_actions 类型错误（期望 Dictionary）" % prefix)
	var ppa: Dictionary = ppa_val

	if pending.is_empty():
		ppa.erase(phase_name)
	else:
		ppa[phase_name] = pending

	round_state["pending_phase_actions"] = ppa
	return Result.success()
