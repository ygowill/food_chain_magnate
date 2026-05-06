class_name StrategyBotScenarioBenchmarkTest
extends RefCounted

const CandidateGeneratorClass = preload("res://core/ai/candidates/candidate_generator.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const StrategyProfileClass = preload("res://core/ai/strategy/strategy_profile.gd")
const StrategyScorerClass = preload("res://core/ai/strategy/strategy_scorer.gd")

static func run(_player_count: int = 2, seed_val: int = 12345) -> Result:
	var registry_read := _load_registries(seed_val)
	if not registry_read.ok:
		return registry_read

	var names: Array[String] = []
	var marketing_pipeline := _scenario_marketing_pipeline_requires_active_food_supply()
	if not marketing_pipeline.ok:
		return _scenario_failure("marketing_pipeline_requires_active_food_supply", marketing_pipeline)
	names.append("marketing_pipeline_requires_active_food_supply")

	var trainable_supply := _scenario_trainable_supply_stays_structure_candidate(seed_val)
	if not trainable_supply.ok:
		return _scenario_failure("trainable_supply_stays_structure_candidate", trainable_supply)
	names.append("trainable_supply_stays_structure_candidate")

	var pending_drinks := _scenario_pending_marketing_drink_supply_targets_product()
	if not pending_drinks.ok:
		return _scenario_failure("pending_marketing_drink_supply_targets_product", pending_drinks)
	names.append("pending_marketing_drink_supply_targets_product")

	return Result.success({
		"scenarios": names.size(),
		"names": names.duplicate(),
	})

static func _load_registries(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("engine initialize failed while loading registries: %s" % init.error)
	return Result.success()

static func _scenario_failure(name: String, result: Result) -> Result:
	return Result.failure("%s failed: %s" % [name, result.error])

static func _scenario_marketing_pipeline_requires_active_food_supply() -> Result:
	var profile = StrategyProfileClass.new()
	profile.configure_base_revenue()
	var observation := _synthetic_food_income_observation()
	observation.phase = DefsClass.PHASE_RESTRUCTURING
	observation.sub_phase = ""
	observation.own_player["cash"] = 20
	observation.own_player["employees"] = ["campaign_manager"]
	observation.own_player["reserve_employees"] = ["kitchen_trainee", "errand_boy"]
	observation.own_player["inventory"] = {}
	_set_observation_house_demand_count(observation, "house_near", "burger", 0)

	var kitchen_macro := MacroAction.create(
		"structure_kitchen_for_marketing",
		[Command.create("set_company_structure_direct", 0, {"slot_index": 0, "employee_id": "kitchen_trainee"})],
		0.0,
		["restructuring", "direct"],
		{}
	)
	var errand_macro := MacroAction.create(
		"structure_errand_without_food",
		[Command.create("set_company_structure_direct", 0, {"slot_index": 0, "employee_id": "errand_boy"})],
		0.0,
		["restructuring", "direct"],
		{}
	)
	var submit_macro := MacroAction.create(
		"submit_without_food_supply",
		[Command.create("submit_restructuring", 0, {})],
		0.0,
		["restructuring"],
		{}
	)

	var kitchen_score: Dictionary = StrategyScorerClass.score_macro(observation, kitchen_macro, profile)
	var errand_score: Dictionary = StrategyScorerClass.score_macro(observation, errand_macro, profile)
	var submit_score: Dictionary = StrategyScorerClass.score_macro(observation, submit_macro, profile)
	if float(kitchen_score.get("score", 0.0)) <= float(errand_score.get("score", 0.0)):
		return Result.failure("expected active burger supply to beat unrelated drink supply: kitchen=%s errand=%s" % [str(kitchen_score), str(errand_score)])
	if float(kitchen_score.get("score", 0.0)) <= float(submit_score.get("score", 0.0)):
		return Result.failure("expected active burger supply to beat submitting structure: kitchen=%s submit=%s" % [str(kitchen_score), str(submit_score)])
	var features: Dictionary = Dictionary(kitchen_score.get("features", {}))
	var marketing_products: Array = Array(features.get("structure_marketing_supply_products", []))
	if not marketing_products.has("burger"):
		return Result.failure("expected burger in structure_marketing_supply_products: %s" % str(features))
	return Result.success()

static func _scenario_trainable_supply_stays_structure_candidate(seed_val: int) -> Result:
	var observation := _synthetic_food_income_observation()
	observation.phase = DefsClass.PHASE_RESTRUCTURING
	observation.sub_phase = ""
	observation.own_player["employees"] = ["trainer", "campaign_manager"]
	observation.own_player["reserve_employees"] = ["burger_cook", "errand_boy"]
	observation.own_player["inventory"] = {}
	observation.own_player["company_structure"] = {
		"ceo_slots": 3,
		"structure": [{}, {}, {}],
	}
	observation.employee_pool_public = {
		"burger_chef": 2,
		"cart_operator": 2,
	}
	_set_observation_house_demand_count(observation, "house_near", "burger", 4)

	var context := AiDecisionContext.create(
		0,
		DefsClass.PHASE_RESTRUCTURING,
		"",
		1,
		seed_val,
		[]
	)
	var generated := CandidateGeneratorClass.generate(
		observation,
		context,
		["set_company_structure_direct", "submit_restructuring"],
		Callable(),
		{"max_valid_per_action": 12}
	)
	if not generated.ok:
		return generated
	var candidates: Array = Array(Dictionary(generated.value).get("candidates", []))
	var candidate_ids: Array[String] = []
	for candidate_val in candidates:
		if not (candidate_val is MacroAction):
			continue
		var candidate: MacroAction = candidate_val
		candidate_ids.append(str(candidate.id))
		if str(candidate.id).find("burger_cook") >= 0:
			return Result.success()
	return Result.failure("expected burger_cook direct structure candidate while trainer exists: %s" % str(candidate_ids))

static func _scenario_pending_marketing_drink_supply_targets_product() -> Result:
	var profile = StrategyProfileClass.new()
	profile.configure_base_revenue()
	var observation := _synthetic_drink_route_observation()
	_set_observation_house_demand_count(observation, "house_near", "soda", 0)
	observation.marketing_instances_public = [
		{"owner": 0, "product": "beer", "remaining_duration": 2},
	]

	var soda_macro := MacroAction.create(
		"procure_route_soda_without_pending",
		[Command.create("procure_drinks", 0, {"employee_type": "truck_driver", "restaurant_id": "rest_near", "route": [[3, 2], [4, 2]], "selected_sources": [[4, 2]]})],
		0.0,
		["working", "procure_drinks"],
		{}
	)
	var beer_macro := MacroAction.create(
		"procure_route_beer_for_pending",
		[Command.create("procure_drinks", 0, {"employee_type": "truck_driver", "restaurant_id": "rest_near", "route": [[3, 2], [8, 2]], "selected_sources": [[8, 2]]})],
		0.0,
		["working", "procure_drinks"],
		{}
	)

	var soda_score: Dictionary = StrategyScorerClass.score_macro(observation, soda_macro, profile)
	var beer_score: Dictionary = StrategyScorerClass.score_macro(observation, beer_macro, profile)
	if float(beer_score.get("score", 0.0)) <= float(soda_score.get("score", 0.0)):
		return Result.failure("expected beer route to beat soda route for pending beer marketing: beer=%s soda=%s" % [str(beer_score), str(soda_score)])
	var beer_features: Dictionary = Dictionary(beer_score.get("features", {}))
	if int(beer_features.get("product_pending_marketing_demand", 0)) != 1:
		return Result.failure("expected product_pending_marketing_demand=1: %s" % str(beer_features))
	if int(beer_features.get("product_supply_future_covered_units", 0)) != 1:
		return Result.failure("expected pending beer supply to cover one future unit: %s" % str(beer_features))
	return Result.success()

static func _synthetic_food_income_observation() -> ObservationState:
	var observation := ObservationState.new()
	observation.viewer_player_id = 0
	observation.current_player_id = 0
	observation.round_number = 4
	observation.phase = DefsClass.PHASE_WORKING
	observation.sub_phase = DefsClass.SUB_PHASE_GET_FOOD
	observation.rules_public = {
		"salary_cost": 5,
	}
	observation.own_player = {
		"id": 0,
		"cash": 20,
		"employees": ["burger_cook", "pizza_cook"],
		"reserve_employees": [],
		"busy_marketers": [],
		"restaurants": ["rest_near"],
		"inventory": {},
		"company_structure": {
			"ceo_slots": 3,
			"structure": [{}, {}, {}],
		},
	}
	observation.map_public = {
		"grid_size": Vector2i(12, 12),
		"houses": {
			"house_near": {
				"house_number": 1,
				"anchor_pos": Vector2i(2, 2),
				"demands": [
					{"product": "burger"},
					{"product": "burger"},
				],
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

static func _synthetic_drink_route_observation() -> ObservationState:
	var observation := ObservationState.new()
	observation.viewer_player_id = 0
	observation.current_player_id = 0
	observation.round_number = 4
	observation.phase = DefsClass.PHASE_WORKING
	observation.sub_phase = DefsClass.SUB_PHASE_GET_DRINKS
	observation.rules_public = {
		"salary_cost": 5,
	}
	observation.own_player = {
		"id": 0,
		"cash": 20,
		"employees": ["truck_driver"],
		"reserve_employees": [],
		"busy_marketers": [],
		"restaurants": ["rest_near"],
		"inventory": {},
		"milestones": [],
	}
	observation.map_public = {
		"grid_size": Vector2i(12, 12),
		"houses": {
			"house_near": {
				"house_number": 1,
				"anchor_pos": Vector2i(2, 2),
				"demands": [
					{"product": "soda"},
					{"product": "soda"},
				],
			},
		},
		"restaurants": {
			"rest_near": {
				"restaurant_id": "rest_near",
				"owner": 0,
				"anchor_pos": Vector2i(3, 2),
			},
		},
		"drink_sources": [
			{"world_pos": Vector2i(4, 2), "type": "soda"},
			{"world_pos": Vector2i(8, 2), "type": "beer"},
		],
	}
	return observation

static func _set_observation_house_demand_count(observation: ObservationState, house_id: String, product_id: String, count: int) -> void:
	if observation == null or house_id.is_empty() or product_id.is_empty():
		return
	var houses: Dictionary = Dictionary(observation.map_public.get("houses", {})).duplicate(true)
	var house: Dictionary = Dictionary(houses.get(house_id, {})).duplicate(true)
	var demands: Array = []
	for _i in range(maxi(0, count)):
		demands.append({"product": product_id})
	house["demands"] = demands
	houses[house_id] = house
	observation.map_public["houses"] = houses
