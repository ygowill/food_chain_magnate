# RoundState：player-bool helper 回归测试
class_name RoundStatePlayerBoolFlagsTest
extends RefCounted

const RoundStatePlayerBoolFlagsClass = preload("res://core/utils/round_state_player_bool_flags.gd")

static func run(_player_count: int = 2, _seed_val: int = 12345) -> Result:
	var r := _test_set_and_get_direct_flag()
	if not r.ok:
		return r
	r = _test_strict_string_player_key_fails_fast()
	if not r.ok:
		return r
	r = _test_normalize_nested_flags()
	if not r.ok:
		return r
	r = _test_list_true_players()
	if not r.ok:
		return r
	return Result.success({"cases": 4})

static func _test_set_and_get_direct_flag() -> Result:
	var round_state := {}
	var set_r := RoundStatePlayerBoolFlagsClass.set_player_flag(round_state, ["lobbyists_extra_tile_pending"], 1, true, "RoundStatePlayerBoolFlagsTest")
	if not set_r.ok:
		return Result.failure("set_player_flag 失败: %s" % set_r.error)
	var get_r := RoundStatePlayerBoolFlagsClass.get_player_flag(round_state, ["lobbyists_extra_tile_pending"], 1, "RoundStatePlayerBoolFlagsTest")
	if not get_r.ok:
		return Result.failure("get_player_flag(1) 失败: %s" % get_r.error)
	if not bool(get_r.value):
		return Result.failure("player 1 flag 应为 true")
	var miss_r := RoundStatePlayerBoolFlagsClass.get_player_flag(round_state, ["lobbyists_extra_tile_pending"], 0, "RoundStatePlayerBoolFlagsTest")
	if not miss_r.ok:
		return Result.failure("get_player_flag(0) 失败: %s" % miss_r.error)
	if bool(miss_r.value):
		return Result.failure("缺失 player flag 应返回默认 false")
	return Result.success()

static func _test_strict_string_player_key_fails_fast() -> Result:
	var round_state := {"restructuring": {"submitted": {"0": true}}}
	var get_r := RoundStatePlayerBoolFlagsClass.get_player_flag(round_state, ["restructuring", "submitted"], 0, "RoundStatePlayerBoolFlagsTest")
	if get_r.ok:
		return Result.failure("字符串玩家 key 应触发失败，但返回 ok")
	var err := str(get_r.error)
	if err.find("字符串玩家 key") < 0:
		return Result.failure("错误信息应包含 字符串玩家 key，实际: %s" % err)
	return Result.success()

static func _test_normalize_nested_flags() -> Result:
	var round_state := {"restructuring": {"submitted": {"0": true, 1: false, 99: true}}}
	var normalize_r := RoundStatePlayerBoolFlagsClass.normalize_player_flags(round_state, ["restructuring", "submitted"], 2, "RoundStatePlayerBoolFlagsTest")
	if not normalize_r.ok:
		return Result.failure("normalize_player_flags 失败: %s" % normalize_r.error)
	var restructuring_val = round_state.get("restructuring", null)
	if not (restructuring_val is Dictionary):
		return Result.failure("restructuring 类型错误（期望 Dictionary）")
	var restructuring: Dictionary = restructuring_val
	var submitted_val = restructuring.get("submitted", null)
	if not (submitted_val is Dictionary):
		return Result.failure("submitted 类型错误（期望 Dictionary）")
	var submitted: Dictionary = submitted_val
	if submitted.has("0") or submitted.has("1"):
		return Result.failure("normalize 后不应保留字符串玩家 key")
	if not submitted.has(0) or not submitted.has(1):
		return Result.failure("normalize 后应补齐 int 玩家 key")
	if not bool(submitted.get(0, false)):
		return Result.failure("submitted[0] 应为 true")
	if bool(submitted.get(1, true)):
		return Result.failure("submitted[1] 应为 false")
	if submitted.has(99):
		return Result.failure("超范围玩家 key 不应保留")
	return Result.success()

static func _test_list_true_players() -> Result:
	var round_state := {"lobbyists_extra_tile_pending": {0: false, 1: true, 2: true}}
	var list_r := RoundStatePlayerBoolFlagsClass.list_true_players(round_state, ["lobbyists_extra_tile_pending"], 3, "RoundStatePlayerBoolFlagsTest")
	if not list_r.ok:
		return Result.failure("list_true_players 失败: %s" % list_r.error)
	var players: Array = list_r.value
	if players.size() != 2 or int(players[0]) != 1 or int(players[1]) != 2:
		return Result.failure("true 玩家列表错误: %s" % str(players))
	var empty_r := RoundStatePlayerBoolFlagsClass.list_true_players({}, ["lobbyists_extra_tile_pending"], 2, "RoundStatePlayerBoolFlagsTest")
	if not empty_r.ok:
		return Result.failure("list_true_players(empty) 失败: %s" % empty_r.error)
	if (empty_r.value as Array).size() != 0:
		return Result.failure("缺失字段时应返回空列表")
	return Result.success()
