# cleanup_settlement opening-soon 状态访问回归测试
class_name CleanupSettlementOpeningSoonStateAccessTest
extends RefCounted

const CleanupSettlementClass = preload("res://modules/base_rules/rules/phase/cleanup_settlement.gd")

static func run(_player_count: int = 2, _seed_val: int = 12345) -> Result:
	var r := _test_open_opening_soon_restaurants_reads_player_and_map_restaurants()
	if not r.ok:
		return r
	r = _test_open_opening_soon_restaurants_fails_fast_on_missing_player_restaurants()
	if not r.ok:
		return r
	return Result.success({"cases": 2})

static func _make_state() -> GameState:
	var state := GameState.new()
	state.players = [
		{
			"id": 0,
			"restaurants": [],
		},
	]
	state.map = {
		"grid_size": Vector2i(1, 1),
		"restaurants": {},
		"cells": [
			[
				{
					"structure": {
						"piece_id": "restaurant",
						"restaurant_id": "rest_1",
						"opening_soon": true,
					}
				}
			]
		],
	}
	state.round_state = {
		"opening_soon_restaurants": [
			{
				"restaurant_id": "rest_1",
				"owner": 0,
				"anchor_pos": Vector2i.ZERO,
				"entrance_pos": Vector2i.ZERO,
				"cells": [Vector2i.ZERO],
				"rotation": 0,
			}
		]
	}
	return state

static func _test_open_opening_soon_restaurants_reads_player_and_map_restaurants() -> Result:
	var state := _make_state()
	var result := CleanupSettlementClass._open_opening_soon_restaurants(state)
	if not result.ok:
		return Result.failure("_open_opening_soon_restaurants 失败: %s" % result.error)
	var restaurants: Dictionary = state.map.get("restaurants", {})
	if not restaurants.has("rest_1"):
		return Result.failure("rest_1 应加入 map.restaurants")
	var player_restaurants: Array = state.players[0].get("restaurants", [])
	if not player_restaurants.has("rest_1"):
		return Result.failure("rest_1 应加入 player[0].restaurants")
	var structure: Dictionary = state.map["cells"][0][0].get("structure", {})
	if structure.has("opening_soon"):
		return Result.failure("开业后应移除 structure.opening_soon")
	if state.round_state.has("opening_soon_restaurants"):
		return Result.failure("结算后应清除 opening_soon_restaurants")
	return Result.success()

static func _test_open_opening_soon_restaurants_fails_fast_on_missing_player_restaurants() -> Result:
	var state := _make_state()
	state.players[0].erase("restaurants")
	var result := CleanupSettlementClass._open_opening_soon_restaurants(state)
	if result.ok:
		return Result.failure("缺失 player[0].restaurants 时应失败")
	var err := str(result.error)
	if err.find("player[0].restaurants") < 0:
		return Result.failure("错误信息应包含 player[0].restaurants，实际: %s" % err)
	return Result.success()
