# coffee first_coffee_sold cleanup pending 状态访问回归测试
class_name CoffeeFirstCoffeeSoldStateAccessTest
extends RefCounted

const RulesClass = preload("res://modules/coffee/rules/coffee_first_coffee_sold.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")

static func run(_player_count: int = 2, _seed_val: int = 12345) -> Result:
	var r := _test_cleanup_merges_bonus_after_existing_pending()
	if not r.ok:
		return r
	r = _test_cleanup_fails_fast_on_invalid_pending_item_without_partial_mutation()
	if not r.ok:
		return r
	r = _test_cleanup_fails_fast_on_bonus_pending_player_out_of_range()
	if not r.ok:
		return r
	r = _test_dinnertime_fails_fast_on_missing_report()
	if not r.ok:
		return r
	r = _test_dinnertime_fails_fast_on_bad_route_purchase()
	if not r.ok:
		return r
	return Result.success({"cases": 5})

static func _make_state() -> GameState:
	var state := GameState.new()
	state.players = [
		{},
		{},
	]
	state.turn_order = [0, 1]
	state.current_player_index = 0
	state.round_state = {}
	return state

static func _test_cleanup_merges_bonus_after_existing_pending() -> Result:
	var rules = RulesClass.new()
	var state := _make_state()
	state.round_state["pending_phase_actions"] = {
		DefsClass.PHASE_CLEANUP: [{
			"kind": "fridge_keep",
			"player_id": 0,
		}],
	}
	state.round_state["coffee_first_coffee_sold_bonus_pending_players"] = [1]
	var result := rules._on_cleanup_enter_after_primary(state, null)
	if not result.ok:
		return Result.failure("cleanup merge 不应失败: %s" % result.error)
	var ppa_val = state.round_state.get("pending_phase_actions", null)
	if not (ppa_val is Dictionary):
		return Result.failure("pending_phase_actions 应为 Dictionary")
	var cleanup_val = (ppa_val as Dictionary).get(DefsClass.PHASE_CLEANUP, null)
	if not (cleanup_val is Array):
		return Result.failure("pending_phase_actions[Cleanup] 应为 Array")
	var cleanup_pending: Array = cleanup_val
	if cleanup_pending.size() != 2:
		return Result.failure("合并后应有 2 个 cleanup pending，实际: %s" % str(cleanup_pending))
	if not (cleanup_pending[0] is Dictionary) or not (cleanup_pending[1] is Dictionary):
		return Result.failure("合并后 cleanup pending 项应为 Dictionary，实际: %s" % str(cleanup_pending))
	var first: Dictionary = cleanup_pending[0]
	var second: Dictionary = cleanup_pending[1]
	if str(first.get("kind", "")) != "fridge_keep" or int(first.get("player_id", -1)) != 0:
		return Result.failure("第一个 pending 应为 fridge_keep(player=0)，实际: %s" % str(first))
	if str(second.get("kind", "")) != "coffee_first_coffee_sold_bonus_coffee_shop" or int(second.get("player_id", -1)) != 1:
		return Result.failure("第二个 pending 应为 coffee bonus(player=1)，实际: %s" % str(second))
	if state.current_player_index != 0:
		return Result.failure("current_player_index 应保持指向第一个待处理玩家，实际: %d" % state.current_player_index)
	if state.round_state.has("coffee_first_coffee_sold_bonus_pending_players"):
		return Result.failure("成功后应清除 bonus pending players")
	return Result.success()

static func _test_cleanup_fails_fast_on_invalid_pending_item_without_partial_mutation() -> Result:
	var rules = RulesClass.new()
	var state := _make_state()
	state.current_player_index = 1
	state.round_state["pending_phase_actions"] = {
		DefsClass.PHASE_CLEANUP: ["oops"],
	}
	state.round_state["coffee_first_coffee_sold_bonus_pending_players"] = [0]
	var before_pending: String = str(state.round_state.get("pending_phase_actions", null))
	var result := rules._on_cleanup_enter_after_primary(state, null)
	if result.ok:
		return Result.failure("非法 pending item 时应失败")
	var err := str(result.error)
	if err.find("pending_phase_actions[Cleanup][0]") < 0:
		return Result.failure("错误信息应包含 pending_phase_actions[Cleanup][0]，实际: %s" % err)
	if str(state.round_state.get("pending_phase_actions", null)) != before_pending:
		return Result.failure("失败时不应改写 pending_phase_actions")
	if not state.round_state.has("coffee_first_coffee_sold_bonus_pending_players"):
		return Result.failure("失败时不应提前清除 bonus pending players")
	if state.current_player_index != 1:
		return Result.failure("失败时不应提前改写 current_player_index")
	return Result.success()

static func _test_cleanup_fails_fast_on_bonus_pending_player_out_of_range() -> Result:
	var rules = RulesClass.new()
	var state := _make_state()
	state.round_state["coffee_first_coffee_sold_bonus_pending_players"] = [9]
	var result := rules._on_cleanup_enter_after_primary(state, null)
	if result.ok:
		return Result.failure("bonus pending 玩家越界时应失败")
	var err := str(result.error)
	if err.find("coffee_first_coffee_sold_bonus_pending_players[0]") < 0:
		return Result.failure("错误信息应包含 pending players key，实际: %s" % err)
	return Result.success()

static func _test_dinnertime_fails_fast_on_missing_report() -> Result:
	var rules = RulesClass.new()
	var state := _make_state()
	var result := rules._after_dinnertime_primary(state, null)
	if result.ok:
		return Result.failure("缺失 round_state.dinnertime 时应失败")
	var err := str(result.error)
	if err.find("round_state.dinnertime") < 0:
		return Result.failure("错误信息应包含 round_state.dinnertime，实际: %s" % err)
	return Result.success()

static func _test_dinnertime_fails_fast_on_bad_route_purchase() -> Result:
	var rules = RulesClass.new()
	var state := _make_state()
	state.round_state["dinnertime"] = {
		"sales": [{
			"route_purchases": ["bad"],
		}],
	}
	var result := rules._after_dinnertime_primary(state, null)
	if result.ok:
		return Result.failure("route_purchases entry 类型错误时应失败")
	var err := str(result.error)
	if err.find("route_purchases[0]") < 0:
		return Result.failure("错误信息应包含 route_purchases[0]，实际: %s" % err)
	return Result.success()
