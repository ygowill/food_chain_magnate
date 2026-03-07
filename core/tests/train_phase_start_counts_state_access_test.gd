# train_phase_start_counts 状态访问回归测试
class_name TrainPhaseStartCountsStateAccessTest
extends RefCounted

const ActionClass = preload("res://gameplay/actions/train/train_phase_start_counts.gd")

static func run(_player_count: int = 2, _seed_val: int = 12345) -> Result:
	var r := _test_ensure_fails_fast_on_string_player_key_without_backfill_int_key()
	if not r.ok:
		return r
	r = _test_get_fails_fast_on_string_player_key()
	if not r.ok:
		return r
	return Result.success({"cases": 2})

static func _test_ensure_fails_fast_on_string_player_key_without_backfill_int_key() -> Result:
	var state := GameState.new()
	state.players = [{
		"employees": ["trainer"],
		"reserve_employees": ["management_trainee"],
	}]
	state.round_state = {
		"train_phase_start_counts": {
			"0": {"management_trainee": 1},
		},
	}
	var reserve: Array = ["management_trainee"]
	var result := ActionClass._ensure_train_phase_start_counts(state, 0, reserve)
	if result.ok:
		return Result.failure("字符串玩家 key 时 _ensure_train_phase_start_counts 应失败")
	var err := str(result.error)
	if err.find("train_phase_start_counts") < 0 or err.find("字符串玩家 key") < 0:
		return Result.failure("错误信息应包含 train_phase_start_counts 与 字符串玩家 key，实际: %s" % err)
	var all_val = state.round_state.get("train_phase_start_counts", null)
	if not (all_val is Dictionary):
		return Result.failure("失败后 train_phase_start_counts 应保持为 Dictionary")
	var all: Dictionary = all_val
	if all.has(0):
		return Result.failure("失败时不应补写 int 玩家 key")
	return Result.success()

static func _test_get_fails_fast_on_string_player_key() -> Result:
	var state := GameState.new()
	state.players = [{
		"employees": ["trainer"],
		"reserve_employees": ["management_trainee"],
	}]
	state.round_state = {
		"train_phase_start_counts": {
			"0": {"management_trainee": 1},
		},
	}
	var reserve: Array = ["management_trainee"]
	var result := ActionClass._get_train_phase_start_count(state, 0, reserve, "management_trainee")
	if result.ok:
		return Result.failure("字符串玩家 key 时 _get_train_phase_start_count 应失败")
	var err := str(result.error)
	if err.find("train_phase_start_counts") < 0 or err.find("字符串玩家 key") < 0:
		return Result.failure("错误信息应包含 train_phase_start_counts 与 字符串玩家 key，实际: %s" % err)
	return Result.success()
