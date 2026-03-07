# lobbyists supply 状态访问回归测试
class_name LobbyistsSupplyStateAccessTest
extends RefCounted

const EntryClass = preload("res://modules/lobbyists/rules/entry.gd")

static func run(_player_count: int = 2, _seed_val: int = 12345) -> Result:
	var r := _test_restructuring_initializes_missing_supply_keys()
	if not r.ok:
		return r
	r = _test_restructuring_fails_fast_on_invalid_road_supply_type()
	if not r.ok:
		return r
	r = _test_restructuring_fails_fast_on_negative_park_supply()
	if not r.ok:
		return r
	return Result.success({"cases": 3})

static func _make_state() -> GameState:
	var state := GameState.new()
	state.map = {
		"houses": {},
		"restaurants": {},
		"marketing_placements": {},
		"grid_size": Vector2i(3, 3),
		"cells": [],
		"boundary_index": {},
	}
	var cells := []
	for y in range(3):
		var row := []
		for x in range(3):
			row.append({
				"road_segments": [],
				"structure": {},
				"terrain_type": null,
				"drink_source": null,
				"tile_origin": Vector2i.ZERO,
				"blocked": false,
			})
		cells.append(row)
	state.map["cells"] = cells
	return state

static func _test_restructuring_initializes_missing_supply_keys() -> Result:
	var entry = EntryClass.new()
	var state := _make_state()
	var result := entry._on_restructuring_before_enter(state)
	if not result.ok:
		return Result.failure("_on_restructuring_before_enter 失败: %s" % result.error)
	if int(state.map.get("lobbyists_road_straight_supply_remaining", -1)) != 4:
		return Result.failure("lobbyists_road_straight_supply_remaining 应为 4，实际: %s" % str(state.map.get("lobbyists_road_straight_supply_remaining", null)))
	if int(state.map.get("lobbyists_park_l_supply_remaining", -1)) != 2:
		return Result.failure("lobbyists_park_l_supply_remaining 应为 2，实际: %s" % str(state.map.get("lobbyists_park_l_supply_remaining", null)))
	return Result.success()

static func _test_restructuring_fails_fast_on_invalid_road_supply_type() -> Result:
	var entry = EntryClass.new()
	var state := _make_state()
	state.map["lobbyists_road_straight_supply_remaining"] = "bad"
	var result := entry._on_restructuring_before_enter(state)
	if result.ok:
		return Result.failure("road supply 类型错误时应失败")
	var err := str(result.error)
	if err.find("state.map.lobbyists_road_straight_supply_remaining") < 0:
		return Result.failure("错误信息应包含 state.map.lobbyists_road_straight_supply_remaining，实际: %s" % err)
	return Result.success()

static func _test_restructuring_fails_fast_on_negative_park_supply() -> Result:
	var entry = EntryClass.new()
	var state := _make_state()
	state.map["lobbyists_park_l_supply_remaining"] = -1
	var result := entry._on_restructuring_before_enter(state)
	if result.ok:
		return Result.failure("负数 park supply 时应失败")
	var err := str(result.error)
	if err.find("state.map.lobbyists_park_l_supply_remaining") < 0 or err.find("不能为负数") < 0:
		return Result.failure("错误信息应包含字段路径和负数提示，实际: %s" % err)
	return Result.success()
