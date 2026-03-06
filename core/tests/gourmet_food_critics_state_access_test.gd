# gourmet_food_critics 状态访问回归测试
class_name GourmetFoodCriticsStateAccessTest
extends RefCounted

const EntryClass = preload("res://modules/gourmet_food_critics/rules/entry.gd")

static func run(_player_count: int = 2, _seed_val: int = 12345) -> Result:
	var r := _test_get_gourmet_guide_house_ids_returns_sorted_garden_houses()
	if not r.ok:
		return r
	r = _test_get_gourmet_guide_house_ids_fails_fast_on_missing_houses()
	if not r.ok:
		return r
	r = _test_get_gourmet_guide_house_ids_fails_fast_on_invalid_has_garden()
	if not r.ok:
		return r
	return Result.success({"cases": 3})

static func _make_state() -> GameState:
	var state := GameState.new()
	state.map = {
		"houses": {
			"house_2": {"has_garden": false},
			"house_1": {"has_garden": true},
			"house_3": {"has_garden": true},
		}
	}
	return state

static func _test_get_gourmet_guide_house_ids_returns_sorted_garden_houses() -> Result:
	var entry = EntryClass.new()
	var state := _make_state()
	var result := entry._get_gourmet_guide_house_ids(state, {})
	if not result.ok:
		return Result.failure("_get_gourmet_guide_house_ids 失败: %s" % result.error)
	var ids: Array = result.value
	if ids.size() != 2:
		return Result.failure("应返回 2 个带花园房屋，实际: %s" % str(ids))
	if str(ids[0]) != "house_1" or str(ids[1]) != "house_3":
		return Result.failure("房屋顺序应排序为 [house_1, house_3]，实际: %s" % str(ids))
	return Result.success()

static func _test_get_gourmet_guide_house_ids_fails_fast_on_missing_houses() -> Result:
	var entry = EntryClass.new()
	var state := _make_state()
	state.map.erase("houses")
	var result := entry._get_gourmet_guide_house_ids(state, {})
	if result.ok:
		return Result.failure("缺失 houses 时应失败")
	var err := str(result.error)
	if err.find("state.map.houses") < 0:
		return Result.failure("错误信息应包含 state.map.houses，实际: %s" % err)
	return Result.success()

static func _test_get_gourmet_guide_house_ids_fails_fast_on_invalid_has_garden() -> Result:
	var entry = EntryClass.new()
	var state := _make_state()
	state.map["houses"]["house_1"]["has_garden"] = 1
	var result := entry._get_gourmet_guide_house_ids(state, {})
	if result.ok:
		return Result.failure("has_garden 类型错误时应失败")
	var err := str(result.error)
	if err.find("houses[house_1].has_garden") < 0:
		return Result.failure("错误信息应包含 houses[house_1].has_garden，实际: %s" % err)
	return Result.success()
