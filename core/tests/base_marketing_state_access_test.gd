# base marketing 状态访问回归测试
class_name BaseMarketingStateAccessTest
extends RefCounted

const EntryClass = preload("res://modules/base_marketing/rules/entry.gd")

static func run(_player_count: int = 2, _seed_val: int = 12345) -> Result:
	var r := _test_billboard_range_succeeds_with_valid_map()
	if not r.ok:
		return r
	r = _test_billboard_range_uses_full_rotated_footprint()
	if not r.ok:
		return r
	r = _test_billboard_range_fails_fast_on_missing_grid_size()
	if not r.ok:
		return r
	r = _test_mailbox_range_fails_fast_on_missing_boundary_index()
	if not r.ok:
		return r
	r = _test_radio_range_fails_fast_on_missing_tile_grid_size()
	if not r.ok:
		return r
	r = _test_airplane_range_fails_fast_on_missing_cells()
	if not r.ok:
		return r
	return Result.success({"cases": 6})

static func _make_state(grid_size: Vector2i = Vector2i(3, 3)) -> GameState:
	var state := GameState.new()
	state.map = {
		"grid_size": grid_size,
		"tile_grid_size": Vector2i(1, 1),
		"boundary_index": {},
		"cells": [],
	}
	for y in range(grid_size.y):
		var row: Array = []
		for x in range(grid_size.x):
			row.append({
				"structure": {},
				"road_segments": [],
				"blocked": false,
			})
		state.map["cells"].append(row)
	return state

static func _make_world_pos_instance() -> Dictionary:
	return {"world_pos": Vector2i(1, 1)}

static func _test_billboard_range_succeeds_with_valid_map() -> Result:
	var entry = EntryClass.new()
	var result := entry._get_billboard_house_ids(_make_state(), _make_world_pos_instance())
	if not result.ok:
		return Result.failure("billboard 合法 map 不应失败: %s" % result.error)
	return Result.success()

static func _test_billboard_range_uses_full_rotated_footprint() -> Result:
	var entry = EntryClass.new()
	var state := _make_state(Vector2i(5, 5))

	_set_house(state, "left_house", [Vector2i(0, 1), Vector2i(0, 2)])
	_set_house(state, "right_house", [Vector2i(3, 2), Vector2i(3, 3)])

	var result := entry._get_billboard_house_ids(state, {
		"world_pos": Vector2i(1, 1),
		"footprint_size": Vector2i(3, 2),
		"rotation": 90,
	})
	if not result.ok:
		return Result.failure("billboard rotated footprint 不应失败: %s" % result.error)
	var house_ids: Array = result.value
	if house_ids.size() != 2:
		return Result.failure("billboard rotated footprint 应命中两个房屋，实际: %s" % str(house_ids))
	if not house_ids.has("left_house") or not house_ids.has("right_house"):
		return Result.failure("billboard rotated footprint 命中房屋错误: %s" % str(house_ids))
	return Result.success()

static func _test_billboard_range_fails_fast_on_missing_grid_size() -> Result:
	var entry = EntryClass.new()
	var state := _make_state()
	state.map.erase("grid_size")
	var result := entry._get_billboard_house_ids(state, _make_world_pos_instance())
	if result.ok:
		return Result.failure("缺失 grid_size 时应失败")
	var err := str(result.error)
	if err.find("state.map.grid_size") < 0:
		return Result.failure("错误信息应包含 state.map.grid_size，实际: %s" % err)
	return Result.success()

static func _test_mailbox_range_fails_fast_on_missing_boundary_index() -> Result:
	var entry = EntryClass.new()
	var state := _make_state()
	state.map.erase("boundary_index")
	var result := entry._get_mailbox_house_ids(state, _make_world_pos_instance())
	if result.ok:
		return Result.failure("缺失 boundary_index 时应失败")
	var err := str(result.error)
	if err.find("state.map.boundary_index") < 0:
		return Result.failure("错误信息应包含 state.map.boundary_index，实际: %s" % err)
	return Result.success()

static func _test_radio_range_fails_fast_on_missing_tile_grid_size() -> Result:
	var entry = EntryClass.new()
	var state := _make_state()
	state.map.erase("tile_grid_size")
	var result := entry._get_radio_house_ids(state, _make_world_pos_instance())
	if result.ok:
		return Result.failure("缺失 tile_grid_size 时应失败")
	var err := str(result.error)
	if err.find("state.map.tile_grid_size") < 0:
		return Result.failure("错误信息应包含 state.map.tile_grid_size，实际: %s" % err)
	return Result.success()

static func _test_airplane_range_fails_fast_on_missing_cells() -> Result:
	var entry = EntryClass.new()
	var state := _make_state()
	state.map.erase("cells")
	var result := entry._get_airplane_house_ids(state, {
		"world_pos": Vector2i(0, 0),
		"axis": "row",
		"footprint_size": Vector2i(1, 2),
	})
	if result.ok:
		return Result.failure("缺失 cells 时应失败")
	var err := str(result.error)
	if err.find("state.map.cells") < 0:
		return Result.failure("错误信息应包含 state.map.cells，实际: %s" % err)
	return Result.success()

static func _set_house(state: GameState, house_id: String, cells: Array[Vector2i]) -> void:
	for pos in cells:
		state.map["cells"][pos.y][pos.x]["structure"] = {
			"house_id": house_id,
		}
