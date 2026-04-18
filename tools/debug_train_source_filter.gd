extends SceneTree

const Support = preload("res://core/tests/milestone_system/milestone_system_test_support.gd")
const StateUpdaterClass = preload("res://core/state/state_updater.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const ControllerClass = preload("res://ui/scenes/game/panel/working/train_controller.gd")
const TrainActionClass = preload("res://gameplay/actions/train_action.gd")

func _initialize() -> void:
	var engine := GameEngine.new()
	var init := engine.initialize(2, 12345)
	if not init.ok:
		print("init fail", init.error)
		quit(1)
		return
	var state := engine.get_state()
	Support._force_turn_order(state)
	state.phase = DefsClass.PHASE_WORKING
	state.sub_phase = DefsClass.SUB_PHASE_TRAIN
	state.players[0]["multi_trainer_on_one"] = true
	for _i in range(2):
		print(StateUpdaterClass.take_from_pool(state, "trainer", 1))
		print(StateUpdaterClass.add_employee(state, 0, "trainer", false))
	print(StateUpdaterClass.take_from_pool(state, "marketing_trainee", 1))
	print(StateUpdaterClass.add_employee(state, 0, "marketing_trainee", true))
	var t1 := engine.execute_command(Command.create("train", 0, {"from_employee": "marketing_trainee", "to_employee": "campaign_manager"}))
	print("t1 ok=", t1.ok, " err=", t1.error)
	state = engine.get_state()
	print("phase=", state.phase, " sub=", state.sub_phase, " current=", state.get_current_player_id())
	print("reserve=", state.players[0].get("reserve_employees", []))
	print("employees=", state.players[0].get("employees", []))
	print("action_counts=", state.round_state.get("action_counts", {}))
	print("locks=", state.round_state.get("train_employee_locks", null))
	var action := TrainActionClass.new()
	var v := action.validate(state, Command.create("train", 0, {"from_employee": "campaign_manager", "to_employee": "brand_manager"}))
	print("validate campaign->brand ok=", v.ok, " err=", v.error)
	var controller = ControllerClass.new(null, Callable(), Callable(), Callable())
	var source_items: Array = controller._build_trainable_source_items_from_staff(state, 0)
	print("source_items=", source_items)
	print("filtered=", controller._filter_source_items_with_valid_targets(state, 0, source_items))
	engine.dispose()
	quit()
