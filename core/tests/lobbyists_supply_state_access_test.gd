# lobbyists supply 状态访问回归测试
class_name LobbyistsSupplyStateAccessTest
extends RefCounted

const EntryClass = preload("res://modules/lobbyists/rules/entry.gd")

static func run(_player_count: int = 2, _seed_val: int = 12345) -> Result:
	var r := _test_init_state_initializes_missing_module_state()
	if not r.ok:
		return r
	r = _test_restructuring_fails_fast_on_missing_supply_key()
	if not r.ok:
		return r
	r = _test_restructuring_fails_fast_on_invalid_road_supply_type()
	if not r.ok:
		return r
	r = _test_restructuring_fails_fast_on_negative_park_supply()
	if not r.ok:
		return r
	r = _test_restructuring_fails_fast_on_missing_pending_roads()
	if not r.ok:
		return r
	r = _test_restructuring_fails_fast_on_missing_roadwork_markers()
	if not r.ok:
		return r
	r = _test_restructuring_fails_fast_on_disabled_parallel_lanes()
	if not r.ok:
		return r
	return Result.success({"cases": 7})

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

static func _test_init_state_initializes_missing_module_state() -> Result:
	var entry = EntryClass.new()
	var state := _make_state()
	var result := entry._init_state(state, null)
	if not result.ok:
		return Result.failure("_init_state 失败: %s" % result.error)
	if not bool(state.map.get("road_graph_connect_parallel_lanes", false)):
		return Result.failure("road_graph_connect_parallel_lanes 应初始化为 true")
	if int(state.map.get("lobbyists_road_straight_supply_remaining", -1)) != 4:
		return Result.failure("lobbyists_road_straight_supply_remaining 应为 4，实际: %s" % str(state.map.get("lobbyists_road_straight_supply_remaining", null)))
	if int(state.map.get("lobbyists_park_l_supply_remaining", -1)) != 2:
		return Result.failure("lobbyists_park_l_supply_remaining 应为 2，实际: %s" % str(state.map.get("lobbyists_park_l_supply_remaining", null)))
	if not (state.map.get("lobbyists_pending_roads", null) is Array):
		return Result.failure("lobbyists_pending_roads 应初始化为 Array")
	if not (state.map.get("lobbyists_roadworks_markers", null) is Dictionary):
		return Result.failure("lobbyists_roadworks_markers 应初始化为 Dictionary")
	return Result.success()

static func _test_restructuring_fails_fast_on_missing_supply_key() -> Result:
	var entry = EntryClass.new()
	var state := _make_state()
	var init_result := entry._init_state(state, null)
	if not init_result.ok:
		return init_result
	state.map.erase("lobbyists_road_straight_supply_remaining")
	var result := entry._on_restructuring_before_enter(state)
	if result.ok:
		return Result.failure("重组 hook 缺失 road supply 时应失败")
	var err := str(result.error)
	if err.find("state.map.lobbyists_road_straight_supply_remaining") < 0:
		return Result.failure("错误信息应包含 state.map.lobbyists_road_straight_supply_remaining，实际: %s" % err)
	return Result.success()

static func _test_restructuring_fails_fast_on_invalid_road_supply_type() -> Result:
	var entry = EntryClass.new()
	var state := _make_state()
	var init_result := entry._init_state(state, null)
	if not init_result.ok:
		return init_result
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
	var init_result := entry._init_state(state, null)
	if not init_result.ok:
		return init_result
	state.map["lobbyists_park_l_supply_remaining"] = -1
	var result := entry._on_restructuring_before_enter(state)
	if result.ok:
		return Result.failure("负数 park supply 时应失败")
	var err := str(result.error)
	if err.find("state.map.lobbyists_park_l_supply_remaining") < 0 or err.find("不能为负数") < 0:
		return Result.failure("错误信息应包含字段路径和负数提示，实际: %s" % err)
	return Result.success()

static func _test_restructuring_fails_fast_on_missing_pending_roads() -> Result:
	var entry = EntryClass.new()
	var state := _make_initialized_state(entry)
	if state == null:
		return Result.failure("初始化 state 失败")
	state.map.erase("lobbyists_pending_roads")
	var result := entry._on_restructuring_before_enter(state)
	if result.ok:
		return Result.failure("缺失 lobbyists_pending_roads 时应失败")
	var err := str(result.error)
	if err.find("state.map.lobbyists_pending_roads") < 0:
		return Result.failure("错误信息应包含 state.map.lobbyists_pending_roads，实际: %s" % err)
	return Result.success()

static func _test_restructuring_fails_fast_on_missing_roadwork_markers() -> Result:
	var entry = EntryClass.new()
	var state := _make_initialized_state(entry)
	if state == null:
		return Result.failure("初始化 state 失败")
	state.map.erase("lobbyists_roadworks_markers")
	var result := entry._on_restructuring_before_enter(state)
	if result.ok:
		return Result.failure("缺失 lobbyists_roadworks_markers 时应失败")
	var err := str(result.error)
	if err.find("state.map.lobbyists_roadworks_markers") < 0:
		return Result.failure("错误信息应包含 state.map.lobbyists_roadworks_markers，实际: %s" % err)
	return Result.success()

static func _test_restructuring_fails_fast_on_disabled_parallel_lanes() -> Result:
	var entry = EntryClass.new()
	var state := _make_initialized_state(entry)
	if state == null:
		return Result.failure("初始化 state 失败")
	state.map["road_graph_connect_parallel_lanes"] = false
	var result := entry._on_restructuring_before_enter(state)
	if result.ok:
		return Result.failure("road_graph_connect_parallel_lanes=false 时应失败")
	var err := str(result.error)
	if err.find("state.map.road_graph_connect_parallel_lanes") < 0:
		return Result.failure("错误信息应包含 state.map.road_graph_connect_parallel_lanes，实际: %s" % err)
	return Result.success()

static func _make_initialized_state(entry) -> GameState:
	var state := _make_state()
	var init_result: Result = entry._init_state(state, null)
	if init_result.ok:
		return state
	return null
