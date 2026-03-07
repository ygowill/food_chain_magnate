# add_garden 状态访问回归测试
class_name AddGardenStateAccessTest
extends RefCounted

const ActionClass = preload("res://gameplay/actions/add_garden_action.gd")
const GARDEN_SUPPLY_KEY := "garden_supply_remaining"

class FakeGardenAttachmentValidator:
	extends RefCounted

	var _value

	func _init(value) -> void:
		_value = value

	func validate_garden_attachment(_map_ctx: Dictionary, _house_id: String, _direction: String, _piece_registry: Dictionary, _options: Dictionary) -> Result:
		return Result.success(_value)

static func run(_player_count: int = 2, _seed_val: int = 12345) -> Result:
	var r := _test_apply_changes_updates_house_and_supply()
	if not r.ok:
		return r
	r = _test_apply_changes_fails_fast_on_missing_anchor_pos_without_partial_mutation()
	if not r.ok:
		return r
	r = _test_apply_changes_fails_fast_on_invalid_house_placement_counts_without_partial_mutation()
	if not r.ok:
		return r
	r = _test_apply_changes_fails_fast_on_invalid_attachment_payload_without_partial_mutation()
	if not r.ok:
		return r
	r = _test_apply_changes_fails_fast_on_invalid_merged_cells_without_partial_mutation()
	if not r.ok:
		return r
	return Result.success({"cases": 5})

static func _make_state() -> GameState:
	var state := GameState.new()
	state.players = [{}, {}]
	state.round_state = {}
	state.map = {
		"grid_size": Vector2i(4, 4),
		"cells": _make_cells(),
		"houses": {
			"h1": {
				"house_id": "h1",
				"anchor_pos": Vector2i(1, 1),
				"cells": [Vector2i(1, 1), Vector2i(2, 1)],
				"has_garden": false,
				"house_number": 1,
			}
		},
		"restaurants": {},
		"marketing_placements": {},
		GARDEN_SUPPLY_KEY: 3,
	}
	var anchor_structure := {
		"piece_id": "house",
		"owner": 0,
		"anchor_cell": true,
		"parent_anchor": Vector2i(1, 1),
		"rotation": 0,
		"house_id": "h1",
		"house_number": 1,
		"has_garden": false,
		"dynamic": false,
	}
	var follower_structure := {
		"piece_id": "house",
		"owner": 0,
		"anchor_cell": false,
		"parent_anchor": Vector2i(1, 1),
		"rotation": 0,
		"house_id": "h1",
		"house_number": 1,
		"has_garden": false,
		"dynamic": false,
	}
	state.map["cells"][1][1]["structure"] = anchor_structure
	state.map["cells"][1][2]["structure"] = follower_structure
	return state

static func _make_cells() -> Array:
	var cells := []
	for y in range(4):
		var row := []
		for x in range(4):
			row.append({
				"road_segments": [],
				"structure": {},
				"blocked": false,
				"terrain_type": null,
				"drink_source": null,
				"tile_origin": Vector2i.ZERO,
			})
		cells.append(row)
	return cells

static func _make_command() -> Command:
	return Command.create("add_garden", 0, {"house_id": "h1", "direction": "S"})

static func _test_apply_changes_updates_house_and_supply() -> Result:
	var action = ActionClass.new()
	var state := _make_state()
	var result := action._apply_changes(state, _make_command())
	if not result.ok:
		return Result.failure("_apply_changes 不应失败: %s" % result.error)
	var house: Dictionary = state.map["houses"]["h1"]
	if not bool(house.get("has_garden", false)):
		return Result.failure("成功后 house.has_garden 应为 true")
	if house.get("anchor_pos", null) != Vector2i(2, 1):
		return Result.failure("成功后 anchor_pos 应更新为旋转后的锚点，实际: %s" % str(house.get("anchor_pos", null)))
	if int(state.map.get(GARDEN_SUPPLY_KEY, -1)) != 2:
		return Result.failure("成功后花园供给应减 1，实际: %s" % str(state.map.get(GARDEN_SUPPLY_KEY, null)))
	if _piece_id_at(state, Vector2i(2, 1)) != "house_with_garden":
		return Result.failure("成功后新锚点格应写入 house_with_garden")
	var counts_val = state.round_state.get("house_placement_counts", null)
	if not (counts_val is Dictionary):
		return Result.failure("成功后应写入 round_state.house_placement_counts")
	if int((counts_val as Dictionary).get(0, -1)) != 1:
		return Result.failure("成功后玩家 0 的 house_placement_counts 应为 1")
	return Result.success(true)

static func _test_apply_changes_fails_fast_on_missing_anchor_pos_without_partial_mutation() -> Result:
	var action = ActionClass.new()
	var state := _make_state()
	var house: Dictionary = state.map["houses"]["h1"]
	house.erase("anchor_pos")
	state.map["houses"]["h1"] = house
	var house_before: String = str(state.map["houses"]["h1"])
	var supply_before: int = int(state.map.get(GARDEN_SUPPLY_KEY, -1))
	var result := action._apply_changes(state, _make_command())
	if result.ok:
		return Result.failure("缺失 anchor_pos 时应失败")
	var err := str(result.error)
	if err.find("houses[h1].anchor_pos") < 0:
		return Result.failure("错误信息应包含 houses[h1].anchor_pos，实际: %s" % err)
	if str(state.map["houses"]["h1"]) != house_before:
		return Result.failure("失败时不应提前改写房屋数据")
	if int(state.map.get(GARDEN_SUPPLY_KEY, -1)) != supply_before:
		return Result.failure("失败时不应提前消耗花园供给")
	if _piece_id_at(state, Vector2i(1, 2)) != "" or _piece_id_at(state, Vector2i(2, 2)) != "":
		return Result.failure("失败时不应提前写入花园格子结构")
	return Result.success(true)

static func _test_apply_changes_fails_fast_on_invalid_house_placement_counts_without_partial_mutation() -> Result:
	var action = ActionClass.new()
	var state := _make_state()
	state.round_state["house_placement_counts"] = []
	var house_before: String = str(state.map["houses"]["h1"])
	var supply_before: int = int(state.map.get(GARDEN_SUPPLY_KEY, -1))
	var result := action._apply_changes(state, _make_command())
	if result.ok:
		return Result.failure("house_placement_counts 类型错误时应失败")
	var err := str(result.error)
	if err.find("round_state.house_placement_counts") < 0:
		return Result.failure("错误信息应包含 round_state.house_placement_counts，实际: %s" % err)
	if str(state.map["houses"]["h1"]) != house_before:
		return Result.failure("失败时不应提前改写房屋数据")
	if int(state.map.get(GARDEN_SUPPLY_KEY, -1)) != supply_before:
		return Result.failure("失败时不应提前消耗花园供给")
	if _piece_id_at(state, Vector2i(1, 2)) != "" or _piece_id_at(state, Vector2i(2, 2)) != "":
		return Result.failure("失败时不应提前写入花园格子结构")
	var counts_val = state.round_state.get("house_placement_counts", null)
	if not (counts_val is Array):
		return Result.failure("失败时不应改写非法 house_placement_counts")
	return Result.success(true)

static func _test_apply_changes_fails_fast_on_invalid_attachment_payload_without_partial_mutation() -> Result:
	return _test_apply_changes_fails_fast_on_invalid_attachment_response_without_partial_mutation(
		"bad",
		"validate_garden_attachment 返回值类型错误"
	)

static func _test_apply_changes_fails_fast_on_invalid_merged_cells_without_partial_mutation() -> Result:
	return _test_apply_changes_fails_fast_on_invalid_attachment_response_without_partial_mutation(
		{"garden_cells": [Vector2i(1, 2)], "merged_cells": [Vector2i(1, 1), "bad"]},
		"validate_garden_attachment.merged_cells[1] 类型错误"
	)

static func _test_apply_changes_fails_fast_on_invalid_attachment_response_without_partial_mutation(payload, expected_error: String) -> Result:
	var action = ActionClass.new({}, FakeGardenAttachmentValidator.new(payload))
	var state := _make_state()
	var house_before: String = str(state.map["houses"]["h1"])
	var supply_before: int = int(state.map.get(GARDEN_SUPPLY_KEY, -1))
	var round_state_before := str(state.round_state)
	var result := action._apply_changes(state, _make_command())
	if result.ok:
		return Result.failure("attachment payload 损坏时应失败")
	var err := str(result.error)
	if err.find(expected_error) < 0:
		return Result.failure("错误信息应包含 %s，实际: %s" % [expected_error, err])
	if str(state.map["houses"]["h1"]) != house_before:
		return Result.failure("失败时不应提前改写房屋数据")
	if int(state.map.get(GARDEN_SUPPLY_KEY, -1)) != supply_before:
		return Result.failure("失败时不应提前消耗花园供给")
	if str(state.round_state) != round_state_before:
		return Result.failure("失败时不应提前改写 round_state")
	if _piece_id_at(state, Vector2i(1, 2)) != "" or _piece_id_at(state, Vector2i(2, 2)) != "":
		return Result.failure("失败时不应提前写入花园格子结构")
	return Result.success(true)

static func _piece_id_at(state: GameState, pos: Vector2i) -> String:
	if state == null or not (state.map is Dictionary):
		return ""
	var idx := pos
	var cells_val = state.map.get("cells", null)
	if not (cells_val is Array):
		return ""
	var cells: Array = cells_val
	if idx.y < 0 or idx.y >= cells.size():
		return ""
	var row_val = cells[idx.y]
	if not (row_val is Array):
		return ""
	var row: Array = row_val
	if idx.x < 0 or idx.x >= row.size():
		return ""
	var cell_val = row[idx.x]
	if not (cell_val is Dictionary):
		return ""
	var structure_val = (cell_val as Dictionary).get("structure", null)
	if not (structure_val is Dictionary):
		return ""
	return str((structure_val as Dictionary).get("piece_id", ""))
