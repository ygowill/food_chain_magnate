# rural_marketeers 状态访问回归测试
class_name RuralMarketeersStateAccessTest
extends RefCounted

const EntryClass = preload("res://modules/rural_marketeers/rules/entry.gd")

static func run(_player_count: int = 2, _seed_val: int = 12345) -> Result:
	var r := _test_restructuring_initializes_rural_area_and_supply()
	if not r.ok:
		return r
	r = _test_restructuring_fails_fast_on_missing_houses()
	if not r.ok:
		return r
	r = _test_restructuring_fails_fast_on_invalid_rural_area_type()
	if not r.ok:
		return r
	return Result.success({"cases": 3})

static func _make_state() -> GameState:
	var state := GameState.new()
	state.map = {
		"houses": {
			"house_1": {"house_id": "house_1", "has_garden": false},
		}
	}
	return state

static func _test_restructuring_initializes_rural_area_and_supply() -> Result:
	var entry = EntryClass.new()
	var state := _make_state()
	var result := entry._on_restructuring_before_enter(state)
	if not result.ok:
		return Result.failure("_on_restructuring_before_enter 失败: %s" % result.error)
	if not state.map.has("houses") or not (state.map["houses"] is Dictionary):
		return Result.failure("执行后 state.map.houses 应存在")
	var houses: Dictionary = state.map["houses"]
	if not houses.has("rural_area") or not (houses["rural_area"] is Dictionary):
		return Result.failure("应初始化 houses[rural_area]")
	var rural: Dictionary = houses["rural_area"]
	if str(rural.get("house_number", "")) != "zzzz_rural_area":
		return Result.failure("rural_area.house_number 应为 zzzz_rural_area，实际: %s" % str(rural))
	if int(state.map.get("rural_marketeers_offramp_supply_remaining", -1)) != 3:
		return Result.failure("offramp supply 应初始化为 3，实际: %s" % str(state.map.get("rural_marketeers_offramp_supply_remaining", null)))
	return Result.success()

static func _test_restructuring_fails_fast_on_missing_houses() -> Result:
	var entry = EntryClass.new()
	var state := _make_state()
	state.map.erase("houses")
	var result := entry._on_restructuring_before_enter(state)
	if result.ok:
		return Result.failure("缺失 houses 时应失败")
	var err := str(result.error)
	if err.find("state.map.houses") < 0:
		return Result.failure("错误信息应包含 state.map.houses，实际: %s" % err)
	return Result.success()

static func _test_restructuring_fails_fast_on_invalid_rural_area_type() -> Result:
	var entry = EntryClass.new()
	var state := _make_state()
	state.map["houses"]["rural_area"] = []
	var result := entry._on_restructuring_before_enter(state)
	if result.ok:
		return Result.failure("rural_area 类型错误时应失败")
	var err := str(result.error)
	if err.find("houses[rural_area]") < 0:
		return Result.failure("错误信息应包含 houses[rural_area]，实际: %s" % err)
	return Result.success()
