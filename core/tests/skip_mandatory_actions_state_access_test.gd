# skip / skip_sub_phase 强制动作状态访问回归测试
class_name SkipMandatoryActionsStateAccessTest
extends RefCounted

const ActionIdsClass = preload("res://core/actions/action_ids.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const SkipActionClass = preload("res://gameplay/actions/skip_action.gd")
const SkipSubPhaseActionClass = preload("res://gameplay/actions/skip_sub_phase_action.gd")

static func run(player_count: int = 2, seed_val: int = 12345) -> Result:
	var r := _test_skip_rejects_string_player_key_in_mandatory_actions_completed(player_count, seed_val)
	if not r.ok:
		return r
	r = _test_skip_sub_phase_rejects_string_player_key_in_mandatory_actions_completed(player_count, seed_val)
	if not r.ok:
		return r
	return Result.success({"cases": 2})

static func _test_skip_rejects_string_player_key_in_mandatory_actions_completed(player_count: int, seed_val: int) -> Result:
	var setup_read := _build_working_state_with_pricing_manager(player_count, seed_val)
	if not setup_read.ok:
		return setup_read
	var payload: Dictionary = setup_read.value
	var state: GameState = payload["state"]
	var player_id := int(payload["player_id"])
	var action = SkipActionClass.new(payload["phase_manager"])
	var result := action._validate_specific(state, Command.create(ActionIdsClass.SKIP, player_id, {}))
	if result.ok:
		return Result.failure("skip 在 mandatory_actions_completed 使用字符串玩家 key 时应失败")
	var err := str(result.error)
	if err.find("mandatory_actions_completed") < 0 or err.find("字符串玩家 key") < 0:
		return Result.failure("skip 错误信息应包含 mandatory_actions_completed 与 字符串玩家 key，实际: %s" % err)
	return Result.success()

static func _test_skip_sub_phase_rejects_string_player_key_in_mandatory_actions_completed(player_count: int, seed_val: int) -> Result:
	var setup_read := _build_working_state_with_pricing_manager(player_count, seed_val)
	if not setup_read.ok:
		return setup_read
	var payload: Dictionary = setup_read.value
	var state: GameState = payload["state"]
	var player_id := int(payload["player_id"])
	var action = SkipSubPhaseActionClass.new(payload["phase_manager"])
	var result := action._validate_specific(state, Command.create(ActionIdsClass.SKIP_SUB_PHASE, player_id, {}))
	if result.ok:
		return Result.failure("skip_sub_phase 在 mandatory_actions_completed 使用字符串玩家 key 时应失败")
	var err := str(result.error)
	if err.find("mandatory_actions_completed") < 0 or err.find("字符串玩家 key") < 0:
		return Result.failure("skip_sub_phase 错误信息应包含 mandatory_actions_completed 与 字符串玩家 key，实际: %s" % err)
	return Result.success()

static func _build_working_state_with_pricing_manager(player_count: int, seed_val: int) -> Result:
	if player_count < 2:
		player_count = 2
	var engine := GameEngine.new()
	var init := engine.initialize(player_count, seed_val)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)
	var state: GameState = engine.get_state()
	var phase_manager = engine.phase_manager
	if phase_manager == null:
		return Result.failure("phase_manager 未注入")
	var order := phase_manager.get_working_sub_phase_order_names()
	if order.is_empty():
		return Result.failure("working_sub_phase_order 未初始化")
	var last_sub_phase: String = str(order[order.size() - 1])
	var player_id := state.get_current_player_id()
	if player_id < 0:
		return Result.failure("无法获取当前玩家")
	var pool_before := int(state.employee_pool.get("pricing_manager", 0))
	if pool_before <= 0:
		return Result.failure("员工池中 pricing_manager 数量不足")

	state.phase = DefsClass.PHASE_WORKING
	state.sub_phase = last_sub_phase
	state.employee_pool["pricing_manager"] = pool_before - 1
	state.players[player_id]["employees"].append("pricing_manager")
	state.round_state["mandatory_actions_completed"] = {
		str(player_id): [],
	}
	return Result.success({
		"state": state,
		"player_id": player_id,
		"phase_manager": phase_manager,
	})
