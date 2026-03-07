# new milestones marketing initiation 状态访问回归测试
class_name NewMilestonesMarketingInitiationStateAccessTest
extends RefCounted

const RulesClass = preload("res://modules/new_milestones/rules/marketing_initiation.gd")

const CM_PENDING_KEY := "new_milestones_campaign_manager_pending"
const CM_USED_KEY := "new_milestones_campaign_manager_used_this_turn"
const BM_PENDING_KEY := "new_milestones_brand_manager_airplane_pending"
const BM_USED_KEY := "new_milestones_brand_manager_airplane_used_this_turn"
const MILESTONE_ID_CAMPAIGN_MANAGER := "first_campaign_manager_used"
const MILESTONE_ID_BRAND_MANAGER := "first_brand_manager_used"

static func run(_player_count: int = 2, _seed_val: int = 12345) -> Result:
	var r := _test_campaign_manager_sets_used_flag_and_pending()
	if not r.ok:
		return r
	r = _test_campaign_manager_fails_fast_on_string_used_key()
	if not r.ok:
		return r
	r = _test_brand_manager_sets_used_flag_and_pending()
	if not r.ok:
		return r
	r = _test_brand_manager_fails_fast_on_string_used_key()
	if not r.ok:
		return r
	return Result.success({"cases": 4})

static func _make_state(milestone_id: String) -> GameState:
	var state := GameState.new()
	state.round_number = 3
	state.round_state = {
		"milestones_auto_awarded": [{
			"player_id": 0,
			"milestone_id": milestone_id,
		}],
	}
	return state

static func _make_campaign_command() -> Command:
	return Command.create("initiate_marketing", 0, {"employee_type": "campaign_manager"})

static func _make_brand_command() -> Command:
	return Command.create("initiate_marketing", 0, {"employee_type": "brand_manager"})

static func _make_campaign_instance() -> Dictionary:
	return {
		"type": "mailbox",
		"board_number": 7,
		"product": "burger",
		"remaining_duration": 2,
	}

static func _make_brand_instance() -> Dictionary:
	return {
		"type": "airplane",
		"board_number": 11,
		"product": "pizza",
	}

static func _test_campaign_manager_sets_used_flag_and_pending() -> Result:
	var rules = RulesClass.new()
	var state := _make_state(MILESTONE_ID_CAMPAIGN_MANAGER)
	var result := rules._on_marketing_initiated_campaign_manager(state, _make_campaign_command(), _make_campaign_instance())
	if not result.ok:
		return Result.failure("campaign_manager 发起营销不应失败: %s" % result.error)
	var used_val = state.round_state.get(CM_USED_KEY, null)
	if not (used_val is Dictionary) or not bool((used_val as Dictionary).get(0, false)):
		return Result.failure("应写入 round_state.%s[0]=true，实际: %s" % [CM_USED_KEY, str(used_val)])
	var pending_val = state.round_state.get(CM_PENDING_KEY, null)
	if not (pending_val is Dictionary):
		return Result.failure("应写入 round_state.%s" % CM_PENDING_KEY)
	var pending: Dictionary = pending_val
	if not pending.has(0):
		return Result.failure("pending 应包含玩家 0")
	var info_val = pending.get(0, null)
	if not (info_val is Dictionary):
		return Result.failure("pending[0] 类型错误（期望 Dictionary）")
	var info: Dictionary = info_val
	if str(info.get("employee_type", "")) != "campaign_manager":
		return Result.failure("pending[0].employee_type 应为 campaign_manager，实际: %s" % str(info.get("employee_type", "")))
	if str(info.get("link_id", "")).is_empty():
		return Result.failure("pending[0].link_id 不应为空")
	return Result.success()

static func _test_campaign_manager_fails_fast_on_string_used_key() -> Result:
	var rules = RulesClass.new()
	var state := _make_state(MILESTONE_ID_CAMPAIGN_MANAGER)
	state.round_state[CM_USED_KEY] = {"0": true}
	var result := rules._on_marketing_initiated_campaign_manager(state, _make_campaign_command(), _make_campaign_instance())
	if result.ok:
		return Result.failure("string used key 时应失败")
	var err := str(result.error)
	if err.find("round_state.%s" % CM_USED_KEY) < 0:
		return Result.failure("错误信息应包含 round_state.%s，实际: %s" % [CM_USED_KEY, err])
	if state.round_state.has(CM_PENDING_KEY):
		return Result.failure("失败时不应提前写入 campaign manager pending")
	return Result.success()

static func _test_brand_manager_sets_used_flag_and_pending() -> Result:
	var rules = RulesClass.new()
	var state := _make_state(MILESTONE_ID_BRAND_MANAGER)
	var result := rules._on_marketing_initiated_brand_manager(state, _make_brand_command(), _make_brand_instance())
	if not result.ok:
		return Result.failure("brand_manager 发起营销不应失败: %s" % result.error)
	var used_val = state.round_state.get(BM_USED_KEY, null)
	if not (used_val is Dictionary) or not bool((used_val as Dictionary).get(0, false)):
		return Result.failure("应写入 round_state.%s[0]=true，实际: %s" % [BM_USED_KEY, str(used_val)])
	var pending_val = state.round_state.get(BM_PENDING_KEY, null)
	if not (pending_val is Dictionary):
		return Result.failure("应写入 round_state.%s" % BM_PENDING_KEY)
	var pending: Dictionary = pending_val
	if not pending.has(0):
		return Result.failure("pending 应包含玩家 0")
	var info_val = pending.get(0, null)
	if not (info_val is Dictionary):
		return Result.failure("pending[0] 类型错误（期望 Dictionary）")
	var info: Dictionary = info_val
	if int(info.get("board_number", -1)) != 11:
		return Result.failure("pending[0].board_number 应为 11，实际: %s" % str(info.get("board_number", null)))
	if str(info.get("product_a", "")) != "pizza":
		return Result.failure("pending[0].product_a 应为 pizza，实际: %s" % str(info.get("product_a", "")))
	return Result.success()

static func _test_brand_manager_fails_fast_on_string_used_key() -> Result:
	var rules = RulesClass.new()
	var state := _make_state(MILESTONE_ID_BRAND_MANAGER)
	state.round_state[BM_USED_KEY] = {"0": true}
	var result := rules._on_marketing_initiated_brand_manager(state, _make_brand_command(), _make_brand_instance())
	if result.ok:
		return Result.failure("string used key 时应失败")
	var err := str(result.error)
	if err.find("round_state.%s" % BM_USED_KEY) < 0:
		return Result.failure("错误信息应包含 round_state.%s，实际: %s" % [BM_USED_KEY, err])
	if state.round_state.has(BM_PENDING_KEY):
		return Result.failure("失败时不应提前写入 brand manager pending")
	return Result.success()
