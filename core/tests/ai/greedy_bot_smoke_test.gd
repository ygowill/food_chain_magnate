class_name GreedyBotSmokeTest
extends RefCounted

const BotControllerClass = preload("res://core/ai/bot/bot_controller.gd")
const GreedyBotClass = preload("res://core/ai/bot/greedy_bot.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")

static func run(_player_count: int = 2, seed_val: int = 12345) -> Result:
	var first := _run_to_working(seed_val)
	if not first.ok:
		return first
	var second := _run_to_working(seed_val)
	if not second.ok:
		return second
	if str(first.value.get("actions", [])) != str(second.value.get("actions", [])):
		return Result.failure("GreedyBot should be deterministic for same seed")
	return Result.success({
		"steps": int(first.value.get("steps", 0)),
	})

static func _run_to_working(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("engine initialize failed: %s" % init.error)

	var controller := BotControllerClass.new()
	var bots := {
		0: GreedyBotClass.new(),
		1: GreedyBotClass.new(),
	}
	var stop_condition := func(test_engine: GameEngine) -> bool:
		var state := test_engine.get_state()
		return state != null and int(state.round_number) >= 2 and str(state.phase) == DefsClass.PHASE_WORKING
	var run_result := controller.run_until(engine, bots, stop_condition, 360, 80)
	if not run_result.ok:
		return run_result

	var state := engine.get_state()
	if state == null:
		return Result.failure("engine state is null after GreedyBot run")
	if int(state.round_number) < 2 or str(state.phase) != DefsClass.PHASE_WORKING:
		return Result.failure("expected round 2 Working after GreedyBot run, got round=%d %s/%s" % [int(state.round_number), str(state.phase), str(state.sub_phase)])

	var actions := []
	for item in controller.last_trace:
		actions.append({
			"player_id": int(item.get("player_id", -1)),
			"action_id": str(item.get("action_id", "")),
			"params": Dictionary(item.get("params", {})).duplicate(true),
			"macro_action_id": str(item.get("macro_action_id", "")),
			"phase_before": str(item.get("phase_before", "")),
			"sub_phase_before": str(item.get("sub_phase_before", "")),
		})
	return Result.success({
		"steps": controller.last_trace.size(),
		"actions": actions,
	})
