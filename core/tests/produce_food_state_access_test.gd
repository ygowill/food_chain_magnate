# produce_food inventory payload 状态访问回归测试
class_name ProduceFoodStateAccessTest
extends RefCounted

class FakeInventoryAdder:
	var _payload

	func _init(payload):
		_payload = payload

	func add_inventory(_state: GameState, _player_id: int, _food_type: String, _amount: int) -> Result:
		return Result.success(_payload)

const ActionClass = preload("res://gameplay/actions/produce_food_action.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")

static func run(player_count: int = 2, seed_val: int = 12345) -> Result:
	var r := _test_apply_changes_fails_fast_on_invalid_add_inventory_payload_without_partial_mutation(player_count, seed_val)
	if not r.ok:
		return r
	r = _test_apply_changes_fails_fast_on_missing_new_amount_without_partial_mutation(player_count, seed_val)
	if not r.ok:
		return r
	r = _test_apply_changes_fails_fast_on_invalid_new_amount_type_without_partial_mutation(player_count, seed_val)
	if not r.ok:
		return r
	r = _test_generate_specific_events_returns_empty_on_missing_employee_type(player_count, seed_val)
	if not r.ok:
		return r
	r = _test_generate_specific_events_returns_empty_on_unknown_employee_type(player_count, seed_val)
	if not r.ok:
		return r
	r = _test_generate_specific_events_returns_empty_on_missing_food_type_for_flexible_producer(player_count, seed_val)
	if not r.ok:
		return r
	return Result.success({"cases": 6})

static func _build_state(player_count: int, seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(player_count, seed_val)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)
	var state := engine.get_state()
	state.phase = DefsClass.PHASE_WORKING
	state.sub_phase = DefsClass.SUB_PHASE_GET_FOOD
	state.current_player_index = 0
	state.turn_order = [0, 1]
	state.players[0]["employees"] = ["burger_cook"]
	return Result.success(state)

static func _test_apply_changes_fails_fast_on_invalid_add_inventory_payload_without_partial_mutation(player_count: int, seed_val: int) -> Result:
	return _test_apply_changes_fails_fast_on_invalid_payload(player_count, seed_val, "bad", "StateUpdater.add_inventory 返回值类型错误")

static func _test_apply_changes_fails_fast_on_missing_new_amount_without_partial_mutation(player_count: int, seed_val: int) -> Result:
	return _test_apply_changes_fails_fast_on_invalid_payload(player_count, seed_val, {}, "StateUpdater.add_inventory 缺少字段 new_amount")

static func _test_apply_changes_fails_fast_on_invalid_new_amount_type_without_partial_mutation(player_count: int, seed_val: int) -> Result:
	return _test_apply_changes_fails_fast_on_invalid_payload(player_count, seed_val, {"new_amount": "bad"}, "StateUpdater.add_inventory.new_amount 类型错误")

static func _test_apply_changes_fails_fast_on_invalid_payload(player_count: int, seed_val: int, payload, expected_error: String) -> Result:
	var built := _build_state(player_count, seed_val)
	if not built.ok:
		return built
	var state: GameState = built.value
	var inventory_before := str(state.players[0].get("inventory", {}))
	var round_state_before := str(state.round_state)
	var action = ActionClass.new(FakeInventoryAdder.new(payload))
	var result := action._apply_changes(state, Command.create("produce_food", 0, {"employee_type": "burger_cook"}))
	if result.ok:
		return Result.failure("inventory payload 损坏时应失败")
	var err := str(result.error)
	if err.find(expected_error) < 0:
		return Result.failure("错误信息应包含 %s，实际: %s" % [expected_error, err])
	if str(state.players[0].get("inventory", {})) != inventory_before:
		return Result.failure("失败时不应提前改写 inventory")
	if str(state.round_state) != round_state_before:
		return Result.failure("失败时不应提前改写 round_state")
	return Result.success()

static func _test_generate_specific_events_returns_empty_on_missing_employee_type(player_count: int, seed_val: int) -> Result:
	var built := _build_state(player_count, seed_val)
	if not built.ok:
		return built
	var state: GameState = built.value
	var action = ActionClass.new()
	var events := action._generate_specific_events(state, state, Command.create("produce_food", 0, {}))
	if not events.is_empty():
		return Result.failure("缺失 employee_type 时应返回空事件列表")
	return Result.success()

static func _test_generate_specific_events_returns_empty_on_unknown_employee_type(player_count: int, seed_val: int) -> Result:
	var built := _build_state(player_count, seed_val)
	if not built.ok:
		return built
	var state: GameState = built.value
	var action = ActionClass.new()
	var events := action._generate_specific_events(state, state, Command.create("produce_food", 0, {"employee_type": "bad"}))
	if not events.is_empty():
		return Result.failure("未知 employee_type 时应返回空事件列表")
	return Result.success()

static func _test_generate_specific_events_returns_empty_on_missing_food_type_for_flexible_producer(player_count: int, seed_val: int) -> Result:
	var built := _build_state(player_count, seed_val)
	if not built.ok:
		return built
	var state: GameState = built.value
	var action = ActionClass.new()
	var events := action._generate_specific_events(state, state, Command.create("produce_food", 0, {"employee_type": "kitchen_trainee"}))
	if not events.is_empty():
		return Result.failure("灵活生产者缺失 food_type 时应返回空事件列表")
	return Result.success()
