# rural_marketeers marketing 状态访问回归测试
class_name RuralMarketeersMarketingStateAccessTest
extends RefCounted

const EntryClass = preload("res://modules/rural_marketeers/rules/entry.gd")

static func run(_player_count: int = 2, _seed_val: int = 12345) -> Result:
	var r := _test_marketing_enter_succeeds_without_billboards()
	if not r.ok:
		return r
	r = _test_marketing_enter_fails_fast_on_missing_houses()
	if not r.ok:
		return r
	r = _test_marketing_enter_fails_fast_on_invalid_demands_type()
	if not r.ok:
		return r
	return Result.success({"cases": 3})

static func _make_state() -> GameState:
	var state := GameState.new()
	state.map = {
		"houses": {
			"rural_area": {
				"house_id": "rural_area",
				"demands": [],
			}
		}
	}
	return state

static func _test_marketing_enter_succeeds_without_billboards() -> Result:
	var entry = EntryClass.new()
	var state := _make_state()
	var result := entry._on_marketing_enter_extension(state, null)
	if not result.ok:
		return Result.failure("_on_marketing_enter_extension 失败: %s" % result.error)
	var rural: Dictionary = state.map["houses"]["rural_area"]
	if not rural.has("demands") or not (rural["demands"] is Array):
		return Result.failure("rural_area.demands 应保持为 Array")
	return Result.success()

static func _test_marketing_enter_fails_fast_on_missing_houses() -> Result:
	var entry = EntryClass.new()
	var state := _make_state()
	state.map.erase("houses")
	var result := entry._on_marketing_enter_extension(state, null)
	if result.ok:
		return Result.failure("缺失 houses 时应失败")
	var err := str(result.error)
	if err.find("state.map.houses") < 0:
		return Result.failure("错误信息应包含 state.map.houses，实际: %s" % err)
	return Result.success()

static func _test_marketing_enter_fails_fast_on_invalid_demands_type() -> Result:
	var entry = EntryClass.new()
	var state := _make_state()
	state.map["houses"]["rural_area"]["demands"] = {}
	var result := entry._on_marketing_enter_extension(state, null)
	if result.ok:
		return Result.failure("demands 类型错误时应失败")
	var err := str(result.error)
	if err.find("rural_area.demands") < 0:
		return Result.failure("错误信息应包含 rural_area.demands，实际: %s" % err)
	return Result.success()
