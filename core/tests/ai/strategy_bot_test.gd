class_name StrategyBotTest
extends RefCounted

const BotControllerClass = preload("res://core/ai/bot/bot_controller.gd")
const StrategyBotClass = preload("res://core/ai/bot/strategy_bot.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")

static func run(_player_count: int = 2, seed_val: int = 12345) -> Result:
	var first := _run_to_round_or_game_over(seed_val, 3)
	if not first.ok:
		return first
	var second := _run_to_round_or_game_over(seed_val, 3)
	if not second.ok:
		return second
	var first_actions: Array = first.value.get("actions", [])
	var second_actions: Array = second.value.get("actions", [])
	if str(first_actions) != str(second_actions):
		return Result.failure("StrategyBot should be deterministic for same seed")
	if not bool(first.value.get("saw_strategy_trace", false)):
		return Result.failure("StrategyBot should emit strategy trace metadata")
	return Result.success({
		"steps": int(first.value.get("steps", 0)),
		"round": int(first.value.get("round", 0)),
		"phase": str(first.value.get("phase", "")),
	})

static func _run_to_round_or_game_over(seed_val: int, min_round: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("engine initialize failed: %s" % init.error)

	var controller := BotControllerClass.new()
	var bots := {
		0: StrategyBotClass.new(),
		1: StrategyBotClass.new(),
	}
	var stop_condition := func(test_engine: GameEngine) -> bool:
		var state := test_engine.get_state()
		return state != null and (int(state.round_number) >= min_round or str(state.phase) == DefsClass.PHASE_GAME_OVER)
	var run_result := controller.run_until(engine, bots, stop_condition, 720, 80)
	if not run_result.ok:
		return run_result

	var state := engine.get_state()
	if state == null:
		return Result.failure("engine state is null after StrategyBot run")
	if int(state.round_number) < min_round and str(state.phase) != DefsClass.PHASE_GAME_OVER:
		return Result.failure("expected StrategyBot to reach round %d or GameOver, got round=%d %s/%s" % [min_round, int(state.round_number), str(state.phase), str(state.sub_phase)])

	return Result.success({
		"steps": controller.last_trace.size(),
		"round": int(state.round_number),
		"phase": str(state.phase),
		"actions": _action_summary(controller.last_trace),
		"saw_strategy_trace": _saw_strategy_trace(controller.last_trace),
	})

static func _action_summary(trace: Array[Dictionary]) -> Array:
	var actions := []
	for item in trace:
		actions.append({
			"player_id": int(item.get("player_id", -1)),
			"action_id": str(item.get("action_id", "")),
			"params": Dictionary(item.get("params", {})).duplicate(true),
			"macro_action_id": str(item.get("macro_action_id", "")),
			"phase_before": str(item.get("phase_before", "")),
			"sub_phase_before": str(item.get("sub_phase_before", "")),
		})
	return actions

static func _saw_strategy_trace(trace: Array[Dictionary]) -> bool:
	for item in trace:
		var decision_trace: Dictionary = Dictionary(item.get("decision_trace", {}))
		if str(decision_trace.get("bot", "")) == "StrategyBot" and not str(decision_trace.get("strategy_profile", "")).is_empty():
			return true
	return false
