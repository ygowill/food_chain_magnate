# PlayerStateAccess 回归测试
class_name PlayerStateAccessTest
extends RefCounted

const PlayerStateAccessClass = preload("res://core/state/player_state_access.gd")

static func run(_player_count: int = 2, _seed_val: int = 12345) -> Result:
	var r := _test_require_int_field_success()
	if not r.ok:
		return r
	r = _test_require_int_field_fails_on_missing_field()
	if not r.ok:
		return r
	r = _test_require_player_int_field_reads_state_player()
	if not r.ok:
		return r
	r = _test_require_player_restaurants_reads_state_player()
	if not r.ok:
		return r
	return Result.success({"cases": 4})

static func _make_state() -> GameState:
	var state := GameState.new()
	state.players = [
		{
			"cash": 12,
			"coffee_shop_tokens_remaining": 3,
			"restaurants": ["rest_0"],
		},
		{
			"cash": 7,
		},
	]
	return state

static func _test_require_int_field_success() -> Result:
	var player := {"coffee_shop_tokens_remaining": 3}
	var read := PlayerStateAccessClass.require_int_field(player, "coffee_shop_tokens_remaining", "player[0]", "PlayerStateAccessTest")
	if not read.ok:
		return Result.failure("require_int_field 失败: %s" % read.error)
	if int(read.value) != 3:
		return Result.failure("coffee_shop_tokens_remaining 应为 3，实际: %s" % str(read.value))
	return Result.success()

static func _test_require_int_field_fails_on_missing_field() -> Result:
	var player := {"cash": 5}
	var read := PlayerStateAccessClass.require_int_field(player, "coffee_shop_tokens_remaining", "player[1]", "PlayerStateAccessTest")
	if read.ok:
		return Result.failure("缺失字段时应失败")
	var err := str(read.error)
	if err.find("player[1].coffee_shop_tokens_remaining") < 0:
		return Result.failure("错误信息应包含字段路径，实际: %s" % err)
	return Result.success()

static func _test_require_player_int_field_reads_state_player() -> Result:
	var state := _make_state()
	var read := PlayerStateAccessClass.require_player_int_field(state, 0, "cash", "PlayerStateAccessTest")
	if not read.ok:
		return Result.failure("require_player_int_field 失败: %s" % read.error)
	if int(read.value) != 12:
		return Result.failure("player[0].cash 应为 12，实际: %s" % str(read.value))
	return Result.success()

static func _test_require_player_restaurants_reads_state_player() -> Result:
	var state := _make_state()
	var read := PlayerStateAccessClass.require_player_restaurants(state, 0, "PlayerStateAccessTest")
	if not read.ok:
		return Result.failure("require_player_restaurants 失败: %s" % read.error)
	var restaurants: Array = read.value
	if restaurants.size() != 1 or str(restaurants[0]) != "rest_0":
		return Result.failure("player[0].restaurants 读取错误: %s" % str(restaurants))
	return Result.success()
