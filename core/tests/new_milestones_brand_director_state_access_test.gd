# new_milestones brand_director 状态访问回归测试
class_name NewMilestonesBrandDirectorStateAccessTest
extends RefCounted

const EntryClass = preload("res://modules/new_milestones/rules/marketing_initiation.gd")
const MILESTONE_ID := "first_brand_director_used"

static func run(_player_count: int = 2, _seed_val: int = 12345) -> Result:
	var r := _test_brand_director_radio_updates_marketing_placement_when_present()
	if not r.ok:
		return r
	r = _test_brand_director_radio_is_fail_soft_without_marketing_placements()
	if not r.ok:
		return r
	r = _test_brand_director_radio_is_fail_soft_on_invalid_marketing_placements_type()
	if not r.ok:
		return r
	return Result.success({"cases": 3})

static func _make_state() -> GameState:
	var state := GameState.new()
	state.players = [
		{"milestones": [MILESTONE_ID]},
		{"milestones": []},
	]
	state.map = {
		"marketing_placements": {
			"1": {
				"board_number": 1,
				"remaining_duration": 1,
			}
		}
	}
	return state

static func _make_command() -> Command:
	return Command.create("initiate_marketing", 0, {})

static func _make_marketing_instance() -> Dictionary:
	return {
		"type": "radio",
		"board_number": 1,
		"remaining_duration": 1,
		"employee_type": "brand_director",
	}

static func _test_brand_director_radio_updates_marketing_placement_when_present() -> Result:
	var entry = EntryClass.new()
	var state := _make_state()
	var marketing_instance := _make_marketing_instance()
	var result := entry._on_marketing_initiated_brand_director(state, _make_command(), marketing_instance)
	if not result.ok:
		return Result.failure("_on_marketing_initiated_brand_director 不应失败: %s" % result.error)
	if int(marketing_instance.get("remaining_duration", 0)) != -1:
		return Result.failure("marketing_instance.remaining_duration 应更新为 -1，实际: %s" % str(marketing_instance.get("remaining_duration", null)))
	if not bool(marketing_instance.get("no_release", false)):
		return Result.failure("brand_director 应标记 no_release")
	var placements: Dictionary = state.map["marketing_placements"]
	var placement: Dictionary = placements.get("1", {})
	if int(placement.get("remaining_duration", 0)) != -1:
		return Result.failure("marketing_placements#1.remaining_duration 应更新为 -1，实际: %s" % str(placement.get("remaining_duration", null)))
	return Result.success()

static func _test_brand_director_radio_is_fail_soft_without_marketing_placements() -> Result:
	var entry = EntryClass.new()
	var state := _make_state()
	state.map.erase("marketing_placements")
	var marketing_instance := _make_marketing_instance()
	var result := entry._on_marketing_initiated_brand_director(state, _make_command(), marketing_instance)
	if not result.ok:
		return Result.failure("缺失 marketing_placements 时应保持 fail-soft，实际: %s" % result.error)
	if int(marketing_instance.get("remaining_duration", 0)) != -1:
		return Result.failure("缺失 marketing_placements 时仍应让 radio 永久，实际: %s" % str(marketing_instance.get("remaining_duration", null)))
	if not bool(marketing_instance.get("no_release", false)):
		return Result.failure("缺失 marketing_placements 时仍应标记 no_release")
	return Result.success()

static func _test_brand_director_radio_is_fail_soft_on_invalid_marketing_placements_type() -> Result:
	var entry = EntryClass.new()
	var state := _make_state()
	state.map["marketing_placements"] = []
	var marketing_instance := _make_marketing_instance()
	var result := entry._on_marketing_initiated_brand_director(state, _make_command(), marketing_instance)
	if not result.ok:
		return Result.failure("marketing_placements 类型错误时应保持 fail-soft，实际: %s" % result.error)
	if int(marketing_instance.get("remaining_duration", 0)) != -1:
		return Result.failure("marketing_placements 类型错误时仍应让 radio 永久，实际: %s" % str(marketing_instance.get("remaining_duration", null)))
	if not bool(marketing_instance.get("no_release", false)):
		return Result.failure("marketing_placements 类型错误时仍应标记 no_release")
	return Result.success()
