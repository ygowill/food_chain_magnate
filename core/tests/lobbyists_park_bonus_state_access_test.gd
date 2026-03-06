# lobbyists park bonus 状态访问回归测试
class_name LobbyistsParkBonusStateAccessTest
extends RefCounted

const EntryClass = preload("res://modules/lobbyists/rules/entry.gd")

static func run(_player_count: int = 2, _seed_val: int = 12345) -> Result:
	var r := _test_effect_adds_bonus_with_adjacent_park()
	if not r.ok:
		return r
	r = _test_effect_fails_fast_on_missing_houses()
	if not r.ok:
		return r
	r = _test_effect_fails_fast_on_invalid_house_cells_type()
	if not r.ok:
		return r
	return Result.success({"cases": 3})

static func _make_state() -> GameState:
	var state := GameState.new()
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
	cells[0][1]["structure"] = {"piece_id": "park"}
	state.map = {
		"grid_size": Vector2i(3, 3),
		"cells": cells,
		"boundary_index": {},
		"houses": {
			"h1": {
				"cells": [Vector2i(1, 1)],
			}
		},
	}
	return state

static func _make_ctx() -> Dictionary:
	return {
		"bonus": 0,
		"unit_price": 5,
		"quantity": 2,
		"house_id": "h1",
		"bonus_breakdown": {},
	}

static func _test_effect_adds_bonus_with_adjacent_park() -> Result:
	var entry = EntryClass.new()
	var state := _make_state()
	var ctx := _make_ctx()
	var result := entry._effect_dinnertime_sale_house_bonus_park(state, 0, ctx)
	if not result.ok:
		return Result.failure("_effect_dinnertime_sale_house_bonus_park 不应失败: %s" % result.error)
	if int(ctx.get("bonus", -1)) != 10:
		return Result.failure("bonus 应增加到 10，实际: %s" % str(ctx.get("bonus", null)))
	var breakdown: Dictionary = ctx.get("bonus_breakdown", {})
	if int(breakdown.get("park", -1)) != 10:
		return Result.failure("bonus_breakdown.park 应为 10，实际: %s" % str(breakdown))
	return Result.success()

static func _test_effect_fails_fast_on_missing_houses() -> Result:
	var entry = EntryClass.new()
	var state := _make_state()
	state.map.erase("houses")
	var result := entry._effect_dinnertime_sale_house_bonus_park(state, 0, _make_ctx())
	if result.ok:
		return Result.failure("缺失 houses 时应失败")
	var err := str(result.error)
	if err.find("state.map.houses") < 0:
		return Result.failure("错误信息应包含 state.map.houses，实际: %s" % err)
	return Result.success()

static func _test_effect_fails_fast_on_invalid_house_cells_type() -> Result:
	var entry = EntryClass.new()
	var state := _make_state()
	state.map["houses"]["h1"]["cells"] = "bad"
	var result := entry._effect_dinnertime_sale_house_bonus_park(state, 0, _make_ctx())
	if result.ok:
		return Result.failure("house.cells 类型错误时应失败")
	var err := str(result.error)
	if err.find("houses[h1].cells") < 0:
		return Result.failure("错误信息应包含 houses[h1].cells，实际: %s" % err)
	return Result.success()
