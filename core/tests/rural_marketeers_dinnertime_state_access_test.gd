# rural_marketeers dinnertime 状态访问回归测试
class_name RuralMarketeersDinnertimeStateAccessTest
extends RefCounted

const EntryClass = preload("res://modules/rural_marketeers/rules/entry.gd")

static func run(_player_count: int = 2, _seed_val: int = 12345) -> Result:
	var r := _test_dinnertime_enter_succeeds_without_offramps()
	if not r.ok:
		return r
	r = _test_dinnertime_enter_fails_fast_on_missing_houses()
	if not r.ok:
		return r
	r = _test_dinnertime_enter_fails_fast_on_invalid_rural_area_type()
	if not r.ok:
		return r
	return Result.success({"cases": 3})

static func _make_state() -> GameState:
	var state := GameState.new()
	state.map = {
		"houses": {
			"rural_area": {
				"house_id": "rural_area",
				"house_number": "zzzz_rural_area",
				"has_garden": false,
				"no_demand_cap": true,
				"cells": [Vector2i(1, 1)],
				"demands": [],
				"giant_billboards": {},
			}
		},
		"rural_marketeers_offramps": [],
	}
	return state

static func _test_dinnertime_enter_succeeds_without_offramps() -> Result:
	var entry = EntryClass.new()
	var state := _make_state()
	var result := entry._on_dinnertime_enter_before_primary(state, null)
	if not result.ok:
		return Result.failure("_on_dinnertime_enter_before_primary 失败: %s" % result.error)
	var rural: Dictionary = state.map["houses"]["rural_area"]
	if not rural.has("cells") or not (rural["cells"] is Array):
		return Result.failure("rural_area.cells 应为 Array")
	var cells: Array = rural["cells"]
	if not cells.is_empty():
		return Result.failure("无 offramp 时 rural_area.cells 应被清空，实际: %s" % str(cells))
	return Result.success()

static func _test_dinnertime_enter_fails_fast_on_missing_houses() -> Result:
	var entry = EntryClass.new()
	var state := _make_state()
	state.map.erase("houses")
	var result := entry._on_dinnertime_enter_before_primary(state, null)
	if result.ok:
		return Result.failure("缺失 houses 时应失败")
	var err := str(result.error)
	if err.find("state.map.houses") < 0:
		return Result.failure("错误信息应包含 state.map.houses，实际: %s" % err)
	return Result.success()

static func _test_dinnertime_enter_fails_fast_on_invalid_rural_area_type() -> Result:
	var entry = EntryClass.new()
	var state := _make_state()
	state.map["houses"]["rural_area"] = []
	var result := entry._on_dinnertime_enter_before_primary(state, null)
	if result.ok:
		return Result.failure("rural_area 类型错误时应失败")
	var err := str(result.error)
	if err.find("缺少 rural_area") < 0:
		return Result.failure("错误信息应提示 rural_area 无效，实际: %s" % err)
	return Result.success()
