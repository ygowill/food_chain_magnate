# base_rules phase_and_map 状态访问回归测试
class_name BaseRulesPhaseAndMapStateAccessTest
extends RefCounted

const EntryClass = preload("res://modules/base_rules/rules/phase_and_map.gd")

static func run(_player_count: int = 2, _seed_val: int = 12345) -> Result:
	var r := _test_working_before_exit_fails_fast_on_invalid_immediate_train_pending_string_player_key()
	if not r.ok:
		return r
	r = _test_train_before_exit_fails_fast_on_invalid_immediate_train_pending_string_player_key()
	if not r.ok:
		return r
	return Result.success({"cases": 2})

static func _test_working_before_exit_fails_fast_on_invalid_immediate_train_pending_string_player_key() -> Result:
	var state := GameState.new()
	state.round_state = {
		"immediate_train_pending": {
			"0": {"management_trainee": 1},
		},
	}
	var entry = EntryClass.new()
	var result := entry._on_working_before_exit(state)
	if result.ok:
		return Result.failure("working_before_exit 遇到字符串玩家 key 时应失败")
	var err := str(result.error)
	if err.find("immediate_train_pending") < 0 or err.find("字符串玩家 key") < 0:
		return Result.failure("错误信息应包含 immediate_train_pending 与 字符串玩家 key，实际: %s" % err)
	return Result.success()

static func _test_train_before_exit_fails_fast_on_invalid_immediate_train_pending_string_player_key() -> Result:
	var state := GameState.new()
	state.round_state = {
		"immediate_train_pending": {
			"0": {"management_trainee": 1},
		},
	}
	var entry = EntryClass.new()
	var result := entry._on_train_before_exit(state)
	if result.ok:
		return Result.failure("train_before_exit 遇到字符串玩家 key 时应失败")
	var err := str(result.error)
	if err.find("immediate_train_pending") < 0 or err.find("字符串玩家 key") < 0:
		return Result.failure("错误信息应包含 immediate_train_pending 与 字符串玩家 key，实际: %s" % err)
	return Result.success()
