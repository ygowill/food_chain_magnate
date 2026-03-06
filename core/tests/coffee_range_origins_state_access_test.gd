# Coffee range origins 状态访问回归测试
class_name CoffeeRangeOriginsStateAccessTest
extends RefCounted

const CoffeeActionsAndStateClass = preload("res://modules/coffee/rules/coffee_actions_and_state.gd")

static func run(_player_count: int = 2, _seed_val: int = 12345) -> Result:
	var r := _test_missing_coffee_shops_returns_empty()
	if not r.ok:
		return r
	r = _test_wrong_type_coffee_shops_fails_fast()
	if not r.ok:
		return r
	r = _test_uses_anchor_when_entrance_missing()
	if not r.ok:
		return r
	return Result.success({"cases": 3})

static func _test_missing_coffee_shops_returns_empty() -> Result:
	var state := GameState.new()
	state.map = {}
	var host = CoffeeActionsAndStateClass.new()
	var read := host._get_extra_range_origins(state, {"actor": 0})
	if not read.ok:
		return Result.failure("缺失 coffee_shops 时不应失败: %s" % read.error)
	var out: Array = read.value
	if out.size() != 0:
		return Result.failure("缺失 coffee_shops 时应返回空数组，实际: %s" % str(out))
	return Result.success()

static func _test_wrong_type_coffee_shops_fails_fast() -> Result:
	var state := GameState.new()
	state.map = {
		"coffee_shops": "bad",
	}
	var host = CoffeeActionsAndStateClass.new()
	var read := host._get_extra_range_origins(state, {"actor": 0})
	if read.ok:
		return Result.failure("错误类型 coffee_shops 时应失败")
	var err := str(read.error)
	if err.find("state.map.coffee_shops") < 0:
		return Result.failure("错误信息应包含 coffee_shops 路径，实际: %s" % err)
	return Result.success()

static func _test_uses_anchor_when_entrance_missing() -> Result:
	var state := GameState.new()
	state.map = {
		"coffee_shops": {
			"shop_a": {
				"owner": 0,
				"anchor_pos": Vector2i(3, 4),
			},
		},
	}
	var host = CoffeeActionsAndStateClass.new()
	var read := host._get_extra_range_origins(state, {"actor": 0})
	if not read.ok:
		return Result.failure("anchor fallback 失败: %s" % read.error)
	var out: Array = read.value
	if out.size() != 1 or not (out[0] is Vector2i) or Vector2i(out[0]) != Vector2i(3, 4):
		return Result.failure("应回退到 anchor_pos，实际: %s" % str(out))
	return Result.success()
