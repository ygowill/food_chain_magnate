# MapStateAccess 回归测试
class_name MapStateAccessTest
extends RefCounted

const MapStateAccessClass = preload("res://core/state/map_state_access.gd")

static func run(_player_count: int = 2, _seed_val: int = 12345) -> Result:
	var r := _test_require_dict_field_success()
	if not r.ok:
		return r
	r = _test_require_int_field_success()
	if not r.ok:
		return r
	r = _test_require_int_field_fails_on_wrong_type()
	if not r.ok:
		return r
	r = _test_require_optional_dict_field_returns_empty_when_missing()
	if not r.ok:
		return r
	r = _test_require_optional_array_field_fails_on_wrong_type()
	if not r.ok:
		return r
	return Result.success({"cases": 5})

static func _make_state() -> GameState:
	var state := GameState.new()
	state.map = {
		"coffee_shops": {},
		"next_coffee_shop_id": 4,
	}
	return state

static func _test_require_dict_field_success() -> Result:
	var state := _make_state()
	var read := MapStateAccessClass.require_dict_field(state, "coffee_shops", "MapStateAccessTest")
	if not read.ok:
		return Result.failure("require_dict_field 失败: %s" % read.error)
	if not (read.value is Dictionary):
		return Result.failure("coffee_shops 应为 Dictionary")
	return Result.success()

static func _test_require_int_field_success() -> Result:
	var state := _make_state()
	var read := MapStateAccessClass.require_int_field(state, "next_coffee_shop_id", "MapStateAccessTest")
	if not read.ok:
		return Result.failure("require_int_field 失败: %s" % read.error)
	if int(read.value) != 4:
		return Result.failure("next_coffee_shop_id 应为 4，实际: %s" % str(read.value))
	return Result.success()

static func _test_require_int_field_fails_on_wrong_type() -> Result:
	var state := _make_state()
	state.map["next_coffee_shop_id"] = "bad"
	var read := MapStateAccessClass.require_int_field(state, "next_coffee_shop_id", "MapStateAccessTest")
	if read.ok:
		return Result.failure("错误类型时应失败")
	var err := str(read.error)
	if err.find("state.map.next_coffee_shop_id") < 0:
		return Result.failure("错误信息应包含字段路径，实际: %s" % err)
	return Result.success()

static func _test_require_optional_dict_field_returns_empty_when_missing() -> Result:
	var state := _make_state()
	var read := MapStateAccessClass.require_optional_dict_field_or_empty(state, "external_cells", "MapStateAccessTest")
	if not read.ok:
		return Result.failure("缺失 optional dict 时不应失败: %s" % read.error)
	if not (read.value is Dictionary):
		return Result.failure("optional dict 缺失时应返回空 Dictionary")
	if not (read.value as Dictionary).is_empty():
		return Result.failure("optional dict 缺失时应返回空 Dictionary，实际: %s" % str(read.value))
	return Result.success()

static func _test_require_optional_array_field_fails_on_wrong_type() -> Result:
	var state := _make_state()
	state.map["rural_marketeers_offramps"] = {}
	var read := MapStateAccessClass.require_optional_array_field_or_empty(state, "rural_marketeers_offramps", "MapStateAccessTest")
	if read.ok:
		return Result.failure("optional array 类型错误时应失败")
	var err := str(read.error)
	if err.find("state.map.rural_marketeers_offramps") < 0:
		return Result.failure("错误信息应包含字段路径，实际: %s" % err)
	return Result.success()
