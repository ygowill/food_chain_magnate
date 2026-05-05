class_name StrategyBotTest
extends RefCounted

const BotControllerClass = preload("res://core/ai/bot/bot_controller.gd")
const StrategyBotClass = preload("res://core/ai/bot/strategy_bot.gd")
const StrategyCandidateFilterClass = preload("res://core/ai/strategy/strategy_candidate_filter.gd")
const StrategyProfileClass = preload("res://core/ai/strategy/strategy_profile.gd")
const StrategyScorerClass = preload("res://core/ai/strategy/strategy_scorer.gd")
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
	var filter_case := _test_marketing_filter_discards_no_house_candidate()
	if not filter_case.ok:
		return filter_case
	var marketing_score := _test_marketing_score_prefers_affected_serviceable_houses(seed_val)
	if not marketing_score.ok:
		return marketing_score
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

static func _test_marketing_filter_discards_no_house_candidate() -> Result:
	var profile = StrategyProfileClass.new()
	profile.configure_base_revenue()
	var observation := _synthetic_marketing_observation()
	var bad_macro := MacroAction.create(
		"marketing_no_house",
		[Command.create("initiate_marketing", 0, {"product": "burger"})],
		0.0,
		["working", "marketing"],
		{"affected_house_ids": []}
	)
	var skip_macro := MacroAction.create(
		"skip_sub_phase",
		[Command.create("skip_sub_phase", 0, {})],
		0.0,
		["working", "fallback"],
		{}
	)
	var filtered: Dictionary = StrategyCandidateFilterClass.filter_candidates(observation, [bad_macro, skip_macro], profile)
	var kept_val = filtered.get("candidates", [])
	if not (kept_val is Array):
		return Result.failure("StrategyCandidateFilter should return candidate Array")
	var kept: Array = kept_val
	if kept.size() != 1:
		return Result.failure("StrategyCandidateFilter should keep only fallback candidate, got %d" % kept.size())
	if kept[0] != skip_macro:
		return Result.failure("StrategyCandidateFilter kept wrong candidate")
	var stats: Dictionary = Dictionary(filtered.get("stats", {}))
	if int(stats.get("discarded_marketing_no_affected_houses", 0)) != 1:
		return Result.failure("StrategyCandidateFilter should count no-house marketing discard: %s" % str(stats))
	return Result.success()

static func _test_marketing_score_prefers_affected_serviceable_houses(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("engine initialize failed: %s" % init.error)
	var profile = StrategyProfileClass.new()
	profile.configure_base_revenue()
	var observation := _synthetic_marketing_observation()
	var serviceable_macro := MacroAction.create(
		"marketing_serviceable",
		[Command.create("initiate_marketing", 0, {"product": "burger"})],
		0.0,
		["working", "marketing"],
		{"affected_house_ids": ["house_near"]}
	)
	var no_house_macro := MacroAction.create(
		"marketing_no_house",
		[Command.create("initiate_marketing", 0, {"product": "burger"})],
		0.0,
		["working", "marketing"],
		{"affected_house_ids": []}
	)
	var good_score: Dictionary = StrategyScorerClass.score_macro(observation, serviceable_macro, profile)
	var bad_score: Dictionary = StrategyScorerClass.score_macro(observation, no_house_macro, profile)
	if float(good_score.get("score", 0.0)) <= float(bad_score.get("score", 0.0)):
		return Result.failure("StrategyScorer should prefer marketing that affects serviceable houses: good=%s bad=%s" % [str(good_score), str(bad_score)])
	var features: Dictionary = Dictionary(good_score.get("features", {}))
	if int(features.get("marketing_serviceable_houses", 0)) <= 0:
		return Result.failure("StrategyScorer should expose marketing_serviceable_houses: %s" % str(features))
	if int(features.get("marketing_inventory_units", 0)) <= 0:
		return Result.failure("StrategyScorer should expose marketing inventory support: %s" % str(features))
	return Result.success()

static func _synthetic_marketing_observation() -> ObservationState:
	var observation := ObservationState.new()
	observation.viewer_player_id = 0
	observation.round_number = 1
	observation.phase = DefsClass.PHASE_WORKING
	observation.sub_phase = DefsClass.SUB_PHASE_MARKETING
	observation.own_player = {
		"id": 0,
		"cash": 20,
		"employees": ["campaign_manager"],
		"reserve_employees": [],
		"busy_marketers": [],
		"restaurants": ["rest_near"],
		"inventory": {"burger": 1},
	}
	observation.map_public = {
		"houses": {
			"house_near": {
				"house_number": 1,
				"anchor_pos": Vector2i(2, 2),
				"demands": [],
			},
		},
		"restaurants": {
			"rest_near": {
				"restaurant_id": "rest_near",
				"owner": 0,
				"anchor_pos": Vector2i(3, 2),
			},
		},
	}
	return observation
