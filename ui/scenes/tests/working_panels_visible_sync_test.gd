class_name WorkingPanelsVisibleSyncTest
extends RefCounted

const RecruitControllerClass = preload("res://ui/scenes/game/panel/working/recruit_controller.gd")
const TrainControllerClass = preload("res://ui/scenes/game/panel/working/train_controller.gd")
const EndPanelsClass = preload("res://ui/scenes/game/panel/end_panels.gd")
const StateUpdaterClass = preload("res://core/state/state_updater.gd")
const Support = preload("res://core/tests/milestone_system/milestone_system_test_support.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")

static func run(seed_val: int = 12345) -> Result:
	var r1 := _test_recruit_controller_visible_sync(seed_val)
	if not r1.ok:
		return r1

	var r2 := _test_train_controller_visible_sync(seed_val)
	if not r2.ok:
		return r2

	var r3 := _test_payday_panel_visible_sync(seed_val)
	if not r3.ok:
		return r3

	return Result.success({"cases": 3})

static func _test_recruit_controller_visible_sync(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("Recruit visible sync: 初始化失败: %s" % init.error)

	var state: GameState = engine.get_state()
	Support._force_turn_order(state)
	state.phase = DefsClass.PHASE_WORKING
	state.sub_phase = DefsClass.SUB_PHASE_RECRUIT

	var controller = RecruitControllerClass.new(null, Callable(), Callable(), Callable())
	var panel := _MockRecruitPanel.new()
	controller.recruit_panel = panel

	controller.sync(state, true)
	var initial_pool_calls := panel.set_employee_pool_calls
	var initial_count_calls := panel.set_recruit_count_calls

	state.employee_pool["waitress"] = int(state.employee_pool.get("waitress", 0)) - 1
	if not (state.round_state is Dictionary):
		engine.dispose()
		return Result.failure("Recruit visible sync: round_state 类型错误")
	state.round_state["action_counts"] = {
		0: {"recruit": 1}
	}

	controller.sync(state, false)

	if panel.set_employee_pool_calls <= initial_pool_calls:
		engine.dispose()
		return Result.failure("RecruitPanel 可见时，普通 sync 应刷新 employee_pool")
	if panel.set_recruit_count_calls <= initial_count_calls:
		engine.dispose()
		return Result.failure("RecruitPanel 可见时，普通 sync 应刷新 recruit 次数")
	if int(panel.last_pool.get("waitress", 0)) != int(state.employee_pool.get("waitress", 0)):
		engine.dispose()
		return Result.failure("RecruitPanel 未拿到最新 employee_pool：panel=%s state=%s" % [
			str(panel.last_pool.get("waitress", null)),
			str(state.employee_pool.get("waitress", null)),
		])
	var expected_remaining := maxi(0, int(controller._compute_recruit_counts(state, 0).remaining))
	if panel.last_remaining != expected_remaining:
		engine.dispose()
		return Result.failure("RecruitPanel 未拿到最新 recruit remaining：panel=%d expected=%d" % [
			panel.last_remaining,
			expected_remaining,
		])

	engine.dispose()
	return Result.success({})

static func _test_train_controller_visible_sync(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("Train visible sync: 初始化失败: %s" % init.error)

	var state: GameState = engine.get_state()
	Support._force_turn_order(state)
	state.phase = DefsClass.PHASE_WORKING
	state.sub_phase = DefsClass.SUB_PHASE_TRAIN

	var take_trainer := StateUpdaterClass.take_from_pool(state, "trainer", 1)
	if not take_trainer.ok:
		engine.dispose()
		return Result.failure("Train visible sync: 取出 trainer 失败: %s" % take_trainer.error)
	var add_trainer := StateUpdaterClass.add_employee(state, 0, "trainer", false)
	if not add_trainer.ok:
		engine.dispose()
		return Result.failure("Train visible sync: 添加 trainer 失败: %s" % add_trainer.error)

	var take_trainer2 := StateUpdaterClass.take_from_pool(state, "trainer", 1)
	if not take_trainer2.ok:
		engine.dispose()
		return Result.failure("Train visible sync: 取出第二张 trainer 失败: %s" % take_trainer2.error)
	var add_trainer2 := StateUpdaterClass.add_employee(state, 0, "trainer", false)
	if not add_trainer2.ok:
		engine.dispose()
		return Result.failure("Train visible sync: 添加第二张 trainer 失败: %s" % add_trainer2.error)

	var take_from := StateUpdaterClass.take_from_pool(state, "marketing_trainee", 1)
	if not take_from.ok:
		engine.dispose()
		return Result.failure("Train visible sync: 取出 marketing_trainee 失败: %s" % take_from.error)
	var add_from := StateUpdaterClass.add_employee(state, 0, "marketing_trainee", true)
	if not add_from.ok:
		engine.dispose()
		return Result.failure("Train visible sync: 添加 marketing_trainee 失败: %s" % add_from.error)

	var take_from2 := StateUpdaterClass.take_from_pool(state, "management_trainee", 1)
	if not take_from2.ok:
		engine.dispose()
		return Result.failure("Train visible sync: 取出 management_trainee 失败: %s" % take_from2.error)
	var add_from2 := StateUpdaterClass.add_employee(state, 0, "management_trainee", true)
	if not add_from2.ok:
		engine.dispose()
		return Result.failure("Train visible sync: 添加 management_trainee 失败: %s" % add_from2.error)

	var controller = TrainControllerClass.new(null, Callable(), Callable(), Callable())
	var panel := _MockTrainPanel.new()
	controller.train_panel = panel

	controller.sync(state, true)
	var initial_pool_calls := panel.set_employee_pool_calls
	var initial_sources_calls := panel.set_trainable_sources_calls
	var initial_count_calls := panel.set_train_count_calls

	var exec_train := engine.execute_command(Command.create("train", 0, {
		"from_employee": "marketing_trainee",
		"to_employee": "campaign_manager"
	}))
	if not exec_train.ok:
		engine.dispose()
		return Result.failure("Train visible sync: 执行培训失败: %s" % exec_train.error)
	state = engine.get_state()
	if state.phase != DefsClass.PHASE_WORKING or state.sub_phase != DefsClass.SUB_PHASE_TRAIN:
		engine.dispose()
		return Result.failure("Train visible sync: 预期训练后仍停留在 Working/Train，实际为 %s/%s" % [
			str(state.phase),
			str(state.sub_phase),
		])

	controller.sync(state, false)

	if panel.set_employee_pool_calls <= initial_pool_calls:
		engine.dispose()
		return Result.failure("TrainPanel 可见时，普通 sync 应刷新 employee_pool")
	if panel.set_trainable_sources_calls <= initial_sources_calls:
		engine.dispose()
		return Result.failure("TrainPanel 可见时，普通 sync 应刷新 trainable_sources")
	if panel.set_train_count_calls <= initial_count_calls:
		engine.dispose()
		return Result.failure("TrainPanel 可见时，普通 sync 应刷新 train 次数")
	if int(panel.last_pool.get("campaign_manager", 0)) != int(state.employee_pool.get("campaign_manager", 0)):
		engine.dispose()
		return Result.failure("TrainPanel 未拿到最新 employee_pool：panel=%s state=%s" % [
			str(panel.last_pool.get("campaign_manager", null)),
			str(state.employee_pool.get("campaign_manager", null)),
		])
	if panel.last_sources.has("campaign_manager"):
		engine.dispose()
		return Result.failure("TrainPanel 普通 sync 后不应继续展示刚培训出的 campaign_manager 来源: %s" % str(panel.last_sources))
	var expected_counts: Dictionary = controller._compute_train_counts(state, 0)
	if panel.last_train_remaining != int(expected_counts.get("remaining", -1)):
		engine.dispose()
		return Result.failure("TrainPanel 未拿到最新 train remaining：panel=%d expected=%d" % [
			panel.last_train_remaining,
			int(expected_counts.get("remaining", -1)),
		])

	engine.dispose()
	return Result.success({})

static func _test_payday_panel_visible_sync(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("Payday visible sync: 初始化失败: %s" % init.error)

	var state: GameState = engine.get_state()
	Support._force_turn_order(state)
	state.phase = DefsClass.PHASE_PAYDAY
	state.sub_phase = ""

	var take_waitress := StateUpdaterClass.take_from_pool(state, "waitress", 1)
	if not take_waitress.ok:
		engine.dispose()
		return Result.failure("Payday visible sync: 取出 waitress 失败: %s" % take_waitress.error)
	var add_waitress := StateUpdaterClass.add_employee(state, 0, "waitress", false)
	if not add_waitress.ok:
		engine.dispose()
		return Result.failure("Payday visible sync: 添加 waitress 失败: %s" % add_waitress.error)

	var end_panels = EndPanelsClass.new(null, null, Callable(), Callable(), Callable(), Callable())
	var panel := _MockPaydayPanel.new()
	panel.visible = true
	end_panels.payday_panel = panel

	end_panels._sync_payday_panel(state, true)
	var initial_context_calls := panel.set_context_calls
	var initial_employees_calls := panel.set_employees_calls
	var initial_cash_calls := panel.set_player_cash_calls

	state.players[0]["cash"] = 42
	var removed := StateUpdaterClass.remove_from_array(state.players[0], "employees", "waitress")
	if not removed:
		engine.dispose()
		return Result.failure("Payday visible sync: 从 employees 移除 waitress 失败")
	StateUpdaterClass.return_to_pool(state, "waitress", 1)

	var take_trainer := StateUpdaterClass.take_from_pool(state, "trainer", 1)
	if not take_trainer.ok:
		engine.dispose()
		return Result.failure("Payday visible sync: 取出 trainer 失败: %s" % take_trainer.error)
	var add_trainer := StateUpdaterClass.add_employee(state, 0, "trainer", true)
	if not add_trainer.ok:
		engine.dispose()
		return Result.failure("Payday visible sync: 添加 trainer 到待命区失败: %s" % add_trainer.error)

	end_panels._sync_payday_panel(state, false)

	if panel.set_context_calls <= initial_context_calls:
		engine.dispose()
		return Result.failure("PaydayPanel 可见时，普通 sync 应刷新 context")
	if panel.set_employees_calls <= initial_employees_calls:
		engine.dispose()
		return Result.failure("PaydayPanel 可见时，普通 sync 应刷新 employees")
	if panel.set_player_cash_calls <= initial_cash_calls:
		engine.dispose()
		return Result.failure("PaydayPanel 可见时，普通 sync 应刷新 cash")
	if panel.last_cash != 42:
		engine.dispose()
		return Result.failure("PaydayPanel 未拿到最新 cash：%d" % panel.last_cash)
	if panel.last_active.has("waitress"):
		engine.dispose()
		return Result.failure("PaydayPanel 普通 sync 后不应继续展示已移除的 active waitress: %s" % str(panel.last_active))
	if not panel.last_reserve.has("trainer"):
		engine.dispose()
		return Result.failure("PaydayPanel 普通 sync 后应展示新加入的 reserve trainer: %s" % str(panel.last_reserve))

	engine.dispose()
	return Result.success({})


class _MockRecruitPanel:
	extends RefCounted

	var visible: bool = true
	var set_employee_pool_calls: int = 0
	var set_recruit_count_calls: int = 0
	var last_pool: Dictionary = {}
	var last_remaining: int = -1
	var last_total: int = -1

	func set_employee_pool(pool: Dictionary) -> void:
		set_employee_pool_calls += 1
		last_pool = pool.duplicate(true)

	func set_recruit_count(remaining: int, total: int) -> void:
		set_recruit_count_calls += 1
		last_remaining = remaining
		last_total = total


class _MockTrainPanel:
	extends RefCounted

	var visible: bool = true
	var set_employee_pool_calls: int = 0
	var set_trainable_sources_calls: int = 0
	var set_train_count_calls: int = 0
	var last_pool: Dictionary = {}
	var last_sources: Dictionary = {}
	var last_train_remaining: int = -1
	var last_train_total: int = -1

	func set_employee_pool(pool: Dictionary) -> void:
		set_employee_pool_calls += 1
		last_pool = pool.duplicate(true)

	func set_trainable_employees(_employees: Array[String]) -> void:
		pass

	func set_source_requires_same_color(_map: Dictionary) -> void:
		pass

	func set_source_badges(_map: Dictionary) -> void:
		pass

	func set_trainable_sources(sources: Dictionary, _section_label_text: String = "") -> void:
		set_trainable_sources_calls += 1
		last_sources = sources.duplicate(true)

	func set_train_count(remaining: int, total: int) -> void:
		set_train_count_calls += 1
		last_train_remaining = remaining
		last_train_total = total

	func set_max_steps_one_employee(_max_steps: int) -> void:
		pass


class _MockPaydayPanel:
	extends RefCounted

	var visible: bool = true
	var set_context_calls: int = 0
	var set_employees_calls: int = 0
	var set_player_cash_calls: int = 0
	var last_player_id: int = -1
	var last_active: Array[String] = []
	var last_reserve: Array[String] = []
	var last_busy: Array[String] = []
	var last_cash: int = -1

	func set_context(_state: GameState, player_id: int, _effect_registry = null) -> void:
		set_context_calls += 1
		last_player_id = player_id

	func set_employees(active_employees: Array[String], reserve_employees: Array[String], busy_marketers: Array[String]) -> void:
		set_employees_calls += 1
		last_active = active_employees.duplicate()
		last_reserve = reserve_employees.duplicate()
		last_busy = busy_marketers.duplicate()

	func set_player_cash(cash: int) -> void:
		set_player_cash_calls += 1
		last_cash = cash
