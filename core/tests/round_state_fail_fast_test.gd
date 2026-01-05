# RoundState 序列化/反序列化 Fail Fast 回归测试（T1）
# 覆盖：
# - GameState.to_dict -> from_dict 后 round_state 的玩家 key 必须归一化为 int（禁止字符串玩家 key）
# - round_state 字段类型/数值非法时必须失败（无容错）
class_name RoundStateFailFastTest
extends RefCounted

const GameStateClass = preload("res://core/state/game_state.gd")

static func run(_player_count: int = 2, _seed_val: int = 12345) -> Result:
	var state := GameStateClass.new()
	state.rules = {"dummy_rule": 1}

	state.round_state = {
		"mandatory_actions_completed": {0: ["set_price"], 1: []},
		"actions_this_round": [],
		"action_counts": {0: {"recruit": 2}, 1: {}},
		"sub_phase_passed": {0: true, 1: false},
		"price_modifiers": {0: {"pricing_manager": -1}, 1: {"discount_manager": -2}},
		"immediate_train_pending": {0: {"recruiter": 1}},
		"recruit_used": {0: 1, 1: 0},
		"house_placement_counts": {0: 2, 1: 0},
		"production_counts": {0: {"burger_cook": 1}},
		"procurement_counts": {0: {"beer": 1}},
		"marketing_used": {0: {"airplane": 1}},
	}

	var data: Dictionary = state.to_dict()

	var ok_read := GameStateClass.from_dict(data)
	if not ok_read.ok:
		return Result.failure("from_dict(正常数据) 失败: %s" % ok_read.error)
	var restored: GameState = ok_read.value

	var r1 := _assert_round_state_normalized(restored.round_state)
	if not r1.ok:
		return r1

	var r2 := _case_reject_bad_action_counts_key(data)
	if not r2.ok:
		return r2
	var r3 := _case_reject_negative_action_count(data)
	if not r3.ok:
		return r3
	var r4 := _case_reject_non_integer_price_modifier(data)
	if not r4.ok:
		return r4
	var r5 := _case_reject_negative_recruit_used(data)
	if not r5.ok:
		return r5

	return Result.success({"cases": 5})

static func _assert_round_state_normalized(round_state: Dictionary) -> Result:
	for key in ["mandatory_actions_completed", "actions_this_round", "action_counts", "sub_phase_passed"]:
		if not round_state.has(key):
			return Result.failure("round_state 缺少字段: %s" % key)

	var mac_val = round_state.get("mandatory_actions_completed", null)
	if not (mac_val is Dictionary):
		return Result.failure("mandatory_actions_completed 类型错误（期望 Dictionary）")
	var mac: Dictionary = mac_val
	if mac.has("0") or mac.has("1"):
		return Result.failure("mandatory_actions_completed 不应包含字符串玩家 key")
	for pid in [0, 1]:
		if not mac.has(pid):
			return Result.failure("mandatory_actions_completed 缺少玩家 key: %d" % pid)
		var completed_val = mac.get(pid, null)
		if not (completed_val is Array):
			return Result.failure("mandatory_actions_completed[%d] 类型错误（期望 Array）" % pid)
		for i in range(completed_val.size()):
			if not (completed_val[i] is String):
				return Result.failure("mandatory_actions_completed[%d][%d] 类型错误（期望 String）" % [pid, i])

	var sp_val = round_state.get("sub_phase_passed", null)
	if not (sp_val is Dictionary):
		return Result.failure("sub_phase_passed 类型错误（期望 Dictionary）")
	var sp: Dictionary = sp_val
	if sp.has("0") or sp.has("1"):
		return Result.failure("sub_phase_passed 不应包含字符串玩家 key")
	for pid in [0, 1]:
		if not sp.has(pid):
			return Result.failure("sub_phase_passed 缺少玩家 key: %d" % pid)
		var passed = sp.get(pid, null)
		if not (passed is bool):
			return Result.failure("sub_phase_passed[%d] 类型错误（期望 bool）" % pid)

	var ac_val = round_state.get("action_counts", null)
	if not (ac_val is Dictionary):
		return Result.failure("action_counts 类型错误（期望 Dictionary）")
	var ac: Dictionary = ac_val
	if ac.has("0") or ac.has("1"):
		return Result.failure("action_counts 不应包含字符串玩家 key")
	for pid in [0, 1]:
		if not ac.has(pid):
			return Result.failure("action_counts 缺少玩家 key: %d" % pid)
		var per_val = ac.get(pid, null)
		if not (per_val is Dictionary):
			return Result.failure("action_counts[%d] 类型错误（期望 Dictionary）" % pid)
		var per: Dictionary = per_val
		for action_id in per.keys():
			if not (action_id is String):
				return Result.failure("action_counts[%d] key 类型错误（期望 String）" % pid)
			var v = per.get(action_id, null)
			if not (v is int):
				return Result.failure("action_counts[%d].%s 类型错误（期望 int）" % [pid, str(action_id)])
			if int(v) < 0:
				return Result.failure("action_counts[%d].%s 不能为负数" % [pid, str(action_id)])

	for counter_key in [
		"price_modifiers",
		"immediate_train_pending",
		"recruit_used",
		"house_placement_counts",
		"production_counts",
		"procurement_counts",
		"marketing_used",
	]:
		if not round_state.has(counter_key):
			return Result.failure("round_state 缺少字段: %s" % counter_key)
		var v = round_state.get(counter_key, null)
		if not (v is Dictionary):
			return Result.failure("round_state.%s 类型错误（期望 Dictionary）" % counter_key)
		var d: Dictionary = v
		if d.has("0") or d.has("1"):
			return Result.failure("round_state.%s 不应包含字符串玩家 key" % counter_key)

	return Result.success()

static func _case_reject_bad_action_counts_key(base: Dictionary) -> Result:
	var d := base.duplicate(true)
	var rs: Dictionary = d.get("round_state", {})
	rs["action_counts"] = {"bad": {}}
	d["round_state"] = rs

	var r := GameStateClass.from_dict(d)
	if r.ok:
		return Result.failure("action_counts key 非数字字符串时应失败，但返回 ok")
	var err := str(r.error)
	if err.find("action_counts") < 0 or err.find("必须为数字字符串") < 0:
		return Result.failure("错误信息应包含 action_counts 与 必须为数字字符串，实际: %s" % err)
	return Result.success()

static func _case_reject_negative_action_count(base: Dictionary) -> Result:
	var d := base.duplicate(true)
	var rs: Dictionary = d.get("round_state", {})
	rs["action_counts"] = {"0": {"recruit": -1}}
	d["round_state"] = rs

	var r := GameStateClass.from_dict(d)
	if r.ok:
		return Result.failure("action_counts 出现负数时应失败，但返回 ok")
	var err := str(r.error)
	if err.find("action_counts") < 0 or err.find("不能为负数") < 0:
		return Result.failure("错误信息应包含 action_counts 与 不能为负数，实际: %s" % err)
	return Result.success()

static func _case_reject_non_integer_price_modifier(base: Dictionary) -> Result:
	var d := base.duplicate(true)
	var rs: Dictionary = d.get("round_state", {})
	rs["price_modifiers"] = {"0": {"pricing_manager": 1.5}}
	d["round_state"] = rs

	var r := GameStateClass.from_dict(d)
	if r.ok:
		return Result.failure("price_modifiers 出现非整数 float 时应失败，但返回 ok")
	var err := str(r.error)
	if err.find("price_modifiers") < 0 or err.find("必须为整数") < 0:
		return Result.failure("错误信息应包含 price_modifiers 与 必须为整数，实际: %s" % err)
	return Result.success()

static func _case_reject_negative_recruit_used(base: Dictionary) -> Result:
	var d := base.duplicate(true)
	var rs: Dictionary = d.get("round_state", {})
	rs["recruit_used"] = {"0": -1}
	d["round_state"] = rs

	var r := GameStateClass.from_dict(d)
	if r.ok:
		return Result.failure("recruit_used 出现负数时应失败，但返回 ok")
	var err := str(r.error)
	if err.find("recruit_used") < 0 or err.find("不能为负数") < 0:
		return Result.failure("错误信息应包含 recruit_used 与 不能为负数，实际: %s" % err)
	return Result.success()

