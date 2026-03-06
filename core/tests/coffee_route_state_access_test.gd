# Coffee 路由状态访问回归测试
class_name CoffeeRouteStateAccessTest
extends RefCounted

const CoffeeDinnertimeRouteClass = preload("res://modules/coffee/rules/coffee_dinnertime_route.gd")

static func run(_player_count: int = 2, _seed_val: int = 12345) -> Result:
	var r := _test_build_stop_index_requires_restaurants_dict()
	if not r.ok:
		return r
	r = _test_build_stop_index_requires_coffee_shops_dict()
	if not r.ok:
		return r
	r = _test_simulate_coffee_purchases_requires_inventory_dict()
	if not r.ok:
		return r
	return Result.success({"cases": 3})

static func _test_build_stop_index_requires_restaurants_dict() -> Result:
	var state := GameState.new()
	state.map = {
		"coffee_shops": {},
	}
	var read := CoffeeDinnertimeRouteClass._build_coffee_stop_index(state, "")
	if read.ok:
		return Result.failure("缺失 restaurants 时应失败")
	var err := str(read.error)
	if err.find("state.map.restaurants") < 0:
		return Result.failure("错误信息应包含 restaurants 路径，实际: %s" % err)
	return Result.success()

static func _test_build_stop_index_requires_coffee_shops_dict() -> Result:
	var state := GameState.new()
	state.map = {
		"restaurants": {},
		"coffee_shops": "bad",
	}
	var read := CoffeeDinnertimeRouteClass._build_coffee_stop_index(state, "")
	if read.ok:
		return Result.failure("错误类型 coffee_shops 时应失败")
	var err := str(read.error)
	if err.find("state.map.coffee_shops") < 0:
		return Result.failure("错误信息应包含 coffee_shops 路径，实际: %s" % err)
	return Result.success()

static func _test_simulate_coffee_purchases_requires_inventory_dict() -> Result:
	var state := GameState.new()
	state.players = [
		{"cash": 10},
	]
	var path: Array[Vector2i] = [Vector2i(1, 1)]
	var stop_index := {
		CoffeeDinnertimeRouteClass._pos_key(Vector2i(1, 1)): [
			{"kind": "coffee_shop", "id": "shop_1", "owner": 0},
		],
	}
	var cup_breakdowns := {
		0: {"revenue": 5},
	}
	var read := CoffeeDinnertimeRouteClass._simulate_coffee_purchases(state, path, stop_index, cup_breakdowns)
	if read.ok:
		return Result.failure("缺失 inventory 时应失败")
	var err := str(read.error)
	if err.find("player[0].inventory") < 0:
		return Result.failure("错误信息应包含 inventory 路径，实际: %s" % err)
	return Result.success()
