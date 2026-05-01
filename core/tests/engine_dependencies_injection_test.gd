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

class MissingBuildRegistryProvider:
	extends RefCounted

class NullRegistryProvider:
	extends RefCounted

	func build_registry(_phase_manager: PhaseManager, _piece_registry: Dictionary = {}):
		return null

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

class StubEventSink:
	extends RefCounted

	var clear_calls: int = 0
	var emitted_types: Array[String] = []

	func clear_history_and_reset_sequence() -> void:
		clear_calls += 1

	func emit_event(event_type: String, _data: Dictionary) -> void:
		emitted_types.append(event_type)

static func run(seed_val: int = 12345) -> Result:
	var action_provider := StubActionSetupProvider.new()
	var event_provider := StubEventBuildProvider.new()
	var logo_provider := StubRestaurantLogoAssignmentProvider.new()
	var event_sink := StubEventSink.new()

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
	engine.set_event_sink(event_sink)

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
	if engine.get_dependencies().event_sink != event_sink:
		return Result.failure("event_sink 未写入 GameEngineDependencies")
	if event_sink.clear_calls <= 0:
		return Result.failure("注入的 event_sink 未参与初始化历史清理")
	if event_sink.emitted_types.is_empty() or event_sink.emitted_types[0] != "game_started":
		return Result.failure("注入的 event_sink 未收到 game_started 事件: %s" % str(event_sink.emitted_types))

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
	if event_sink.emitted_types.find("command_executed") < 0:
		return Result.failure("注入的 event_sink 未收到 command_executed 事件: %s" % str(event_sink.emitted_types))

	var final_salary_cost := engine.state.get_rule_int("salary_cost")
	engine.dispose()
	var short_game_r := _test_short_game_option_overrides(seed_val + 1)
	if not short_game_r.ok:
		return short_game_r
	var invalid_provider_r := _test_invalid_action_setup_provider_fails_fast(seed_val + 2)
	if not invalid_provider_r.ok:
		return invalid_provider_r
	return Result.success({
		"cash_calls": event_provider.cash_calls,
		"milestone_calls": event_provider.milestone_calls,
		"logo_provider_called": logo_provider.called,
		"salary_cost": final_salary_cost,
		"force_execute_ok": true,
		"short_game_verified": true,
		"invalid_action_provider_verified": true,
		"event_sink_events": event_sink.emitted_types.size(),
	})

static func _test_short_game_option_overrides(seed_val: int) -> Result:
	var current_patch := {
		"bank.default_per_player": 75,
		"rules.salary_cost": 0,
		"rules.bankruptcy_max_breaks": 1,
		"rules.bankruptcy_extra_reserve_per_player": 0,
		"setup.auto_select_reserve_cards": true,
	}
	var current_r := _assert_short_game_init_state(current_patch, seed_val, "current")
	if not current_r.ok:
		return current_r

	var legacy_patch := {
		"rules.salary_cost": 0,
		"rules.bankruptcy_max_breaks": 1,
		"rules.bankruptcy_extra_reserve_per_player": 75,
	}
	return _assert_short_game_init_state(legacy_patch, seed_val + 1, "legacy")

static func _assert_short_game_init_state(option_overrides: Dictionary, seed_val: int, label: String) -> Result:
	var engine := GameEngine.new()
	engine.set_game_option_overrides(option_overrides)
	var init_r := engine.initialize(2, seed_val)
	if not init_r.ok:
		engine.dispose()
		return Result.failure("短游戏初始化失败(%s): %s" % [label, init_r.error])

	var state: GameState = engine.get_state()
	if state == null:
		engine.dispose()
		return Result.failure("短游戏初始化后 state 为空(%s)" % label)
	if int(state.bank.get("total", -1)) != 150:
		engine.dispose()
		return Result.failure("短游戏银行初始资金错误(%s): %s" % [label, str(state.bank.get("total", null))])
	if str(state.phase) != "Setup":
		engine.dispose()
		return Result.failure("短游戏阶段错误(%s): %s" % [label, str(state.phase)])
	if str(state.sub_phase) != "":
		engine.dispose()
		return Result.failure("短游戏应跳过储备卡选择(%s): sub_phase=%s" % [label, str(state.sub_phase)])
	if int(state.get_rule_int("bankruptcy_extra_reserve_per_player")) != 0:
		engine.dispose()
		return Result.failure("短游戏不应保留额外储备金规则(%s): %d" % [label, int(state.get_rule_int("bankruptcy_extra_reserve_per_player"))])

	for pid in range(state.players.size()):
		var player: Dictionary = Dictionary(state.players[pid])
		var cards_val = player.get("reserve_cards", null)
		if not (cards_val is Array):
			engine.dispose()
			return Result.failure("短游戏 reserve_cards 类型错误(%s, pid=%d)" % [label, pid])
		var cards: Array = cards_val
		var sel := int(player.get("reserve_card_selected", -1))
		if sel < 0 or sel >= cards.size():
			engine.dispose()
			return Result.failure("短游戏应已自动选择储备卡(%s, pid=%d): %d" % [label, pid, sel])
		if bool(player.get("reserve_card_revealed", true)):
			engine.dispose()
			return Result.failure("短游戏自动选择后不应揭示储备卡(%s, pid=%d)" % [label, pid])

	engine.dispose()
	return Result.success()

static func _test_invalid_action_setup_provider_fails_fast(seed_val: int) -> Result:
	var missing_engine := GameEngine.new()
	missing_engine.set_action_setup_provider(MissingBuildRegistryProvider.new())
	var missing_r := missing_engine.initialize(2, seed_val)
	missing_engine.dispose()
	if missing_r.ok:
		return Result.failure("缺少 build_registry 的 action_setup_provider 应导致初始化失败")
	var missing_err := str(missing_r.error)
	if missing_err.find("ActionRegistry") < 0 or missing_err.find("build_registry") < 0:
		return Result.failure("缺少 build_registry 的错误信息应包含 ActionRegistry/build_registry，实际: %s" % missing_err)

	var null_engine := GameEngine.new()
	null_engine.set_action_setup_provider(NullRegistryProvider.new())
	var null_r := null_engine.initialize(2, seed_val + 1)
	null_engine.dispose()
	if null_r.ok:
		return Result.failure("返回 null 的 action_setup_provider 应导致初始化失败")
	var null_err := str(null_r.error)
	if null_err.find("ActionRegistry") < 0 or null_err.find("build_registry") < 0:
		return Result.failure("返回 null 的错误信息应包含 ActionRegistry/build_registry，实际: %s" % null_err)
	return Result.success()
