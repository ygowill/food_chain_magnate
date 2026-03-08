# GameEngineDependencies 注入回归测试
class_name EngineDependenciesInjectionTest
extends RefCounted

const GameplayActionSetupClass = preload("res://gameplay/action_setup.gd")
const TestPhaseUtilsClass = preload("res://core/tests/test_phase_utils.gd")

class StubActionSetupProvider:
	extends RefCounted

	var called: bool = false
	var last_piece_registry: Dictionary = {}

	func build_registry(phase_manager: PhaseManager, piece_registry: Dictionary = {}) -> ActionRegistry:
		called = true
		last_piece_registry = piece_registry.duplicate(true)
		return GameplayActionSetupClass.build_registry(phase_manager, piece_registry)

class StubEventBuildProvider:
	extends RefCounted

	var cash_calls: int = 0
	var milestone_calls: int = 0

	func build_player_cash_changed_events(_old_state: GameState, _new_state: GameState, _command: Command) -> Array[Dictionary]:
		cash_calls += 1
		return []

	func build_milestone_achieved_events(_old_state: GameState, _new_state: GameState, _command: Command) -> Array[Dictionary]:
		milestone_calls += 1
		return []

class StubRestaurantLogoAssignmentProvider:
	extends RefCounted

	var called: bool = false
	var last_player_count: int = -1
	var last_seed: int = -1

	func assign_logo_ids(player_count: int, rng_seed: int, _restaurant_logo_choices_by_player) -> Result:
		called = true
		last_player_count = player_count
		last_seed = rng_seed
		var ids: Array[int] = []
		for i in range(player_count):
			ids.append((i + 3) % 6)
		return Result.success(ids)

static func run(seed_val: int = 12345) -> Result:
	var action_provider := StubActionSetupProvider.new()
	var event_provider := StubEventBuildProvider.new()
	var logo_provider := StubRestaurantLogoAssignmentProvider.new()

	var engine := GameEngine.new()
	engine.set_action_setup_provider(action_provider)
	engine.set_command_runner_event_build_provider(event_provider)
	engine.set_restaurant_logo_assignment_provider(logo_provider)
	engine.set_game_config_overrides({
		"rules.salary_cost": 8,
	})
	engine.set_game_option_overrides({
		"player.starting_cash": 42,
	})
	engine.set_command_runner_debug_options({
		"debug_mode": true,
		"force_execute_commands": true,
	})

	var init_r := engine.initialize(2, seed_val)
	if not init_r.ok:
		return Result.failure("initialize 失败: %s" % init_r.error)
	if not action_provider.called:
		return Result.failure("注入的 action_setup_provider 未被调用")
	if not logo_provider.called:
		return Result.failure("注入的 restaurant_logo_assignment_provider 未被调用")
	if logo_provider.last_player_count != 2 or logo_provider.last_seed != seed_val:
		return Result.failure("restaurant_logo_assignment_provider 入参不正确: count=%d seed=%d" % [logo_provider.last_player_count, logo_provider.last_seed])
	var p0 := Dictionary(engine.state.players[0])
	var p1 := Dictionary(engine.state.players[1])
	if int(p0.get("restaurant_logo_id", -1)) != 3:
		return Result.failure("注入的 restaurant_logo_assignment_provider 结果未写入 pid=0")
	if int(p1.get("restaurant_logo_id", -1)) != 4:
		return Result.failure("注入的 restaurant_logo_assignment_provider 结果未写入 pid=1")
	if engine.state.get_rule_int("salary_cost") != 8:
		return Result.failure("注入的 game_config_overrides 未生效: salary_cost=%d" % engine.state.get_rule_int("salary_cost"))
	if int(p0.get("cash", -1)) != 42 or int(p1.get("cash", -1)) != 42:
		return Result.failure("注入的 game_option_overrides 未生效: cash=%s/%s" % [str(p0.get("cash", -1)), str(p1.get("cash", -1))])

	var state: GameState = engine.get_state()
	state.current_player_index = 1
	var force_cmd := Command.create("select_reserve_card", 0, {"selected_index": 0})
	force_cmd.metadata = {"debug_force": true}
	var force_r := engine.execute_command(force_cmd)
	if not force_r.ok:
		return Result.failure("注入的 command_runner_debug_options 未使 debug_force 生效: %s" % force_r.error)

	var setup_r := TestPhaseUtilsClass.complete_setup(engine)
	if not setup_r.ok:
		return Result.failure("complete_setup 失败: %s" % setup_r.error)

	var give_r: Result = engine.execute_command(Command.create("debug_give_money", -1, {"player_id": 0, "amount": 5}))
	if not give_r.ok:
		return Result.failure("debug_give_money 失败: %s" % give_r.error)
	if event_provider.cash_calls <= 0:
		return Result.failure("注入的 command_runner_event_build_provider 未参与现金事件构建")
	if event_provider.milestone_calls <= 0:
		return Result.failure("注入的 command_runner_event_build_provider 未参与里程碑事件构建")

	var final_salary_cost := engine.state.get_rule_int("salary_cost")
	engine.dispose()
	return Result.success({
		"cash_calls": event_provider.cash_calls,
		"milestone_calls": event_provider.milestone_calls,
		"logo_provider_called": logo_provider.called,
		"salary_cost": final_salary_cost,
		"force_execute_ok": true,
	})
