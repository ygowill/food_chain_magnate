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

static func run(seed_val: int = 12345) -> Result:
	var action_provider := StubActionSetupProvider.new()
	var event_provider := StubEventBuildProvider.new()

	var engine := GameEngine.new()
	engine.set_action_setup_provider(action_provider)
	engine.set_command_runner_event_build_provider(event_provider)

	var init_r := engine.initialize(2, seed_val)
	if not init_r.ok:
		return Result.failure("initialize 失败: %s" % init_r.error)
	if not action_provider.called:
		return Result.failure("注入的 action_setup_provider 未被调用")

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

	engine.dispose()
	return Result.success({
		"cash_calls": event_provider.cash_calls,
		"milestone_calls": event_provider.milestone_calls,
	})
