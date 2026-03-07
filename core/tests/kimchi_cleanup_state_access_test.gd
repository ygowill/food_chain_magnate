# kimchi cleanup pending 状态访问回归测试
class_name KimchiCleanupStateAccessTest
extends RefCounted

const RulesClass = preload("res://modules/kimchi/rules/entry.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")

static func run(_player_count: int = 2, _seed_val: int = 12345) -> Result:
	var r := _test_cleanup_promotes_kimchi_pending_over_legacy_fridge_pending()
	if not r.ok:
		return r
	r = _test_cleanup_fails_fast_on_invalid_pending_item_without_partial_mutation()
	if not r.ok:
		return r
	return Result.success({"cases": 2})

static func _make_state() -> GameState:
	var state := GameState.new()
	state.players = [{}, {}]
	state.turn_order = [0, 1]
	state.current_player_index = 1
	state.round_state = {
		"cleanup": {
			"fridge_choice_pending": true,
			"pending_choice_kind": "fridge",
		},
	}
	return state

static func _test_cleanup_promotes_kimchi_pending_over_legacy_fridge_pending() -> Result:
	var rules = RulesClass.new()
	var state := _make_state()
	state.round_state["pending_phase_actions"] = {
		DefsClass.PHASE_CLEANUP: [1],
	}
	state.round_state["kimchi"] = {
		"carried_over_before_cleanup": {0: 1, 1: 2},
		"planned_produced_by_player": {},
	}
	var result := rules._on_cleanup_enter_after_primary(state, null)
	if not result.ok:
		return Result.failure("kimchi cleanup 不应失败: %s" % result.error)
	var cleanup_val = state.round_state.get("cleanup", null)
	if not (cleanup_val is Dictionary):
		return Result.failure("cleanup 应为 Dictionary")
	var cleanup: Dictionary = cleanup_val
	if str(cleanup.get("pending_choice_kind", "")) != "kimchi":
		return Result.failure("pending_choice_kind 应切到 kimchi，实际: %s" % str(cleanup.get("pending_choice_kind", null)))
	if str(cleanup.get("fridge_pending_players", [])) != str([1]):
		return Result.failure("fridge_pending_players 应保留 legacy fridge pending，实际: %s" % str(cleanup.get("fridge_pending_players", null)))
	if str(cleanup.get("kimchi_pending_players", [])) != str([0, 1]):
		return Result.failure("kimchi_pending_players 应按 turn_order 排序，实际: %s" % str(cleanup.get("kimchi_pending_players", null)))
	var ppa_val = state.round_state.get("pending_phase_actions", null)
	if not (ppa_val is Dictionary):
		return Result.failure("pending_phase_actions 应为 Dictionary")
	var cleanup_pending = (ppa_val as Dictionary).get(DefsClass.PHASE_CLEANUP, null)
	if str(cleanup_pending) != str([0, 1]):
		return Result.failure("Cleanup pending 应切换为 kimchi 玩家列表，实际: %s" % str(cleanup_pending))
	if state.current_player_index != 0:
		return Result.failure("current_player_index 应对齐到首个 kimchi 待处理玩家")
	return Result.success()

static func _test_cleanup_fails_fast_on_invalid_pending_item_without_partial_mutation() -> Result:
	var rules = RulesClass.new()
	var state := _make_state()
	state.round_state["pending_phase_actions"] = {
		DefsClass.PHASE_CLEANUP: ["oops"],
	}
	state.round_state["kimchi"] = {
		"carried_over_before_cleanup": {0: 1},
		"planned_produced_by_player": {},
	}
	var cleanup_before: String = str(state.round_state.get("cleanup", null))
	var ppa_before: String = str(state.round_state.get("pending_phase_actions", null))
	var result := rules._on_cleanup_enter_after_primary(state, null)
	if result.ok:
		return Result.failure("非法 pending item 时应失败")
	var err := str(result.error)
	if err.find("pending_phase_actions[Cleanup][0]") < 0:
		return Result.failure("错误信息应包含 pending_phase_actions[Cleanup][0]，实际: %s" % err)
	if str(state.round_state.get("cleanup", null)) != cleanup_before:
		return Result.failure("失败时不应提前改写 cleanup")
	if str(state.round_state.get("pending_phase_actions", null)) != ppa_before:
		return Result.failure("失败时不应提前改写 pending_phase_actions")
	var kimchi_val = state.round_state.get("kimchi", null)
	if kimchi_val is Dictionary and ((kimchi_val as Dictionary).has("available_by_player") or (kimchi_val as Dictionary).has("pending_players")):
		return Result.failure("失败时不应提前写入 kimchi cleanup 结果")
	return Result.success()
