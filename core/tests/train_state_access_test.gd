# train 状态访问回归测试
class_name TrainStateAccessTest
extends RefCounted

const ActionClass = preload("res://gameplay/actions/train_action.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const StateUpdaterClass = preload("res://core/state/state_updater.gd")

static func run(player_count: int = 2, seed_val: int = 12345) -> Result:
	var r := _test_apply_changes_fails_fast_on_invalid_train_events_without_partial_mutation(player_count, seed_val)
	if not r.ok:
		return r
	return Result.success({"cases": 1})

static func _test_apply_changes_fails_fast_on_invalid_train_events_without_partial_mutation(player_count: int, seed_val: int) -> Result:
	var built := _build_train_state(player_count, seed_val)
	if not built.ok:
		return built
	var state: GameState = built.value
	var player_before := str(state.players[0])
	var pool_before := str(state.employee_pool)
	var round_state_before := str(state.round_state)

	var action = ActionClass.new()
	var result := action._apply_changes(state, Command.create("train", 0, {
		"from_employee": "management_trainee",
		"to_employee": "new_business_developer",
	}))
	if result.ok:
		return Result.failure("train_events 类型错误时应失败")
	var err := str(result.error)
	if err.find("train_events") < 0:
		return Result.failure("错误信息应包含 train_events，实际: %s" % err)
	if str(state.players[0]) != player_before:
		return Result.failure("失败时不应提前改写玩家员工状态")
	if str(state.employee_pool) != pool_before:
		return Result.failure("失败时不应提前改写 employee_pool")
	if str(state.round_state) != round_state_before:
		return Result.failure("失败时不应提前改写 round_state")
	return Result.success()

static func _build_train_state(player_count: int, seed_val: int) -> Result:
	if player_count < 2:
		player_count = 2
	var engine := GameEngine.new()
	var init := engine.initialize(player_count, seed_val)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)
	var state: GameState = engine.get_state()
	state.turn_order = [0, 1]
	state.current_player_index = 0
	state.phase = DefsClass.PHASE_WORKING
	state.sub_phase = DefsClass.SUB_PHASE_TRAIN

	var take_trainer := StateUpdaterClass.take_from_pool(state, "trainer", 1)
	if not take_trainer.ok:
		return Result.failure("从员工池取出 trainer 失败: %s" % take_trainer.error)
	var add_trainer := StateUpdaterClass.add_employee(state, 0, "trainer", false)
	if not add_trainer.ok:
		return Result.failure("添加 trainer 失败: %s" % add_trainer.error)
	var take_trainee := StateUpdaterClass.take_from_pool(state, "management_trainee", 1)
	if not take_trainee.ok:
		return Result.failure("从员工池取出 management_trainee 失败: %s" % take_trainee.error)
	var add_trainee := StateUpdaterClass.add_employee(state, 0, "management_trainee", true)
	if not add_trainee.ok:
		return Result.failure("添加 management_trainee 失败: %s" % add_trainee.error)
	state.round_state["train_events"] = {}
	return Result.success(state)
