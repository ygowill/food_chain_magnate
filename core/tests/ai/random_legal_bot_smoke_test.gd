class_name RandomLegalBotSmokeTest
extends RefCounted

const BotControllerClass = preload("res://core/ai/bot/bot_controller.gd")
const RandomLegalBotClass = preload("res://core/ai/bot/random_legal_bot.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")

static func run(_player_count: int = 2, seed_val: int = 12345) -> Result:
	var first := _run_to_working(seed_val)
	if not first.ok:
		return first
	var second := _run_to_working(seed_val)
	if not second.ok:
		return second
	var first_actions: Array = first.value.get("actions", [])
	var second_actions: Array = second.value.get("actions", [])
	if str(first_actions) != str(second_actions):
		return Result.failure("RandomLegalBot should be deterministic for same seed: %s != %s" % [str(first_actions), str(second_actions)])
	return Result.success({
		"steps": int(first.value.get("steps", 0)),
		"actions": first_actions,
	})

static func _run_to_working(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("engine initialize failed: %s" % init.error)

	var controller := BotControllerClass.new()
	var bots := {
		0: RandomLegalBotClass.new(),
		1: RandomLegalBotClass.new(),
	}
	var stop_condition := func(test_engine: GameEngine) -> bool:
		var state := test_engine.get_state()
		return state != null and str(state.phase) == DefsClass.PHASE_WORKING

	var run_result := controller.run_until(engine, bots, stop_condition, 80, 50)
	if not run_result.ok:
		return run_result
	var state := engine.get_state()
	if state == null:
		return Result.failure("engine state is null after bot run")
	if str(state.phase) != DefsClass.PHASE_WORKING:
		return Result.failure("expected Working after RandomLegalBot run, got %s/%s" % [str(state.phase), str(state.sub_phase)])

	var actions := []
	for item in controller.last_trace:
		actions.append({
			"player_id": int(item.get("player_id", -1)),
			"action_id": str(item.get("action_id", "")),
			"params": Dictionary(item.get("params", {})).duplicate(true),
			"phase_before": str(item.get("phase_before", "")),
			"sub_phase_before": str(item.get("sub_phase_before", "")),
		})
	return Result.success({
		"steps": controller.last_trace.size(),
		"actions": actions,
	})
