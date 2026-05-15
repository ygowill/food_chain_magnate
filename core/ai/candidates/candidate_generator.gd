class_name CandidateGenerator
extends RefCounted

const MacroActionClass = preload("res://core/ai/candidates/macro_action.gd")
const ActionIdsClass = preload("res://core/actions/action_ids.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const DrinkRouteAnalyzerClass = preload("res://core/ai/analysis/drink_route_analyzer.gd")
const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")
const EmployeeRulesClass = preload("res://core/rules/employee_rules.gd")
const MarketingRegistryClass = preload("res://core/data/marketing_registry.gd")
const MarketingRangeCalculatorClass = preload("res://core/rules/marketing_range_calculator.gd")
const MarketingRulesClass = preload("res://core/rules/marketing_rules.gd")
const MarketingTypeRegistryClass = preload("res://core/rules/marketing_type_registry.gd")
const ProductRegistryClass = preload("res://core/data/product_registry.gd")
const MilestoneEffectQueriesClass = preload("res://core/rules/milestone_effect_queries.gd")
const MarketingPressureAnalyzerClass = preload("res://core/ai/analysis/marketing_pressure_analyzer.gd")
const BoardAnalyzerClass = preload("res://core/ai/analysis/board_analyzer.gd")
const StrategyIncomeAnalyzerClass = preload("res://core/ai/strategy/strategy_income_analyzer.gd")
const StrategyRoutePlannerClass = preload("res://core/ai/strategy/strategy_route_planner.gd")
const CellsClass = preload("res://core/map/map_runtime/cells.gd")
const CoordsClass = preload("res://core/map/map_runtime/coords.gd")
const MapUtilsClass = preload("res://core/map/map_utils.gd")

const DEFAULT_MAX_VALID_PER_ACTION := 12
const TRAIN_ACTION_MIN_PRIOR := 0.75
const TRAINING_PRESERVE_MIN_PRIOR := 2.5
const MARKETING_TRAINING_ROUTE_CHECK_LIMIT := 1200
const ROUTE_DRINK_SEARCH_MULTIPLIER := 4
const MARKETING_POSITION_LOST_SCORE := -100000.0
const WORKING_MANDATORY_ACTION_IDS := [
	"set_discount",
	"set_luxury_price",
	"set_price",
]

static func generate(
	observation: ObservationState,
	context: AiDecisionContext,
	legal_action_ids: Array[String],
	validate_command: Callable = Callable(),
	options: Dictionary = {}
) -> Result:
	if observation == null:
		return Result.failure("CandidateGenerator.generate: observation is null")
	if context == null:
		return Result.failure("CandidateGenerator.generate: context is null")
	if context.player_id != observation.viewer_player_id:
		return Result.failure("CandidateGenerator.generate: context player does not match observation")
	var max_valid_per_action := maxi(1, int(options.get("max_valid_per_action", DEFAULT_MAX_VALID_PER_ACTION)))

	var out: Array[MacroAction] = []
	var discarded: Array[String] = []
	_generate_pending_confirmation(out, discarded, observation, context, legal_action_ids, validate_command, max_valid_per_action)
	if not out.is_empty():
		return Result.success(_payload(out, discarded))

	match str(observation.phase):
		DefsClass.PHASE_SETUP:
			_generate_setup(out, discarded, observation, context, legal_action_ids, validate_command, max_valid_per_action, options)
		DefsClass.PHASE_RESTRUCTURING:
			_generate_restructuring(out, discarded, observation, context, legal_action_ids, validate_command, max_valid_per_action, options)
		DefsClass.PHASE_ORDER_OF_BUSINESS:
			_generate_order_of_business(out, discarded, observation, context, legal_action_ids, validate_command, max_valid_per_action)
		DefsClass.PHASE_WORKING:
			_generate_working(out, discarded, observation, context, legal_action_ids, validate_command, max_valid_per_action, options)
		DefsClass.PHASE_PAYDAY:
			_generate_payday(out, discarded, observation, context, legal_action_ids, validate_command, max_valid_per_action)
		DefsClass.PHASE_CLEANUP:
			_generate_cleanup(out, discarded, observation, context, legal_action_ids, validate_command, max_valid_per_action)
		_:
			_generate_phase_skip(out, discarded, context, legal_action_ids, validate_command, max_valid_per_action)

	return Result.success(_payload(out, discarded))

static func _payload(candidates: Array[MacroAction], discarded: Array[String]) -> Dictionary:
	return {
		"candidates": candidates,
		"discarded_reasons": discarded.duplicate(),
	}

static func _generate_setup(
	out: Array[MacroAction],
	discarded: Array[String],
	observation: ObservationState,
	context: AiDecisionContext,
	legal_action_ids: Array[String],
	validate_command: Callable,
	max_valid_per_action: int,
	options: Dictionary
) -> void:
	if str(observation.sub_phase) == DefsClass.SUB_PHASE_RESERVE_CARDS:
		if legal_action_ids.has("select_reserve_card"):
			_generate_reserve_choices(out, discarded, observation, context, validate_command, max_valid_per_action)
		return
	if legal_action_ids.has("place_restaurant"):
		_generate_restaurant_placements(out, discarded, observation, context, validate_command, max_valid_per_action, "initial_restaurant")
	if legal_action_ids.has(ActionIdsClass.SKIP):
		_append_valid_command(out, discarded, context, ActionIdsClass.SKIP, {}, validate_command, "setup_skip", ["setup"], 0.0, max_valid_per_action)

static func _generate_reserve_choices(
	out: Array[MacroAction],
	discarded: Array[String],
	observation: ObservationState,
	context: AiDecisionContext,
	validate_command: Callable,
	max_valid_per_action: int
) -> void:
	var cards_val = observation.own_player.get("reserve_cards", [])
	if not (cards_val is Array):
		discarded.append("reserve_card: own_player.reserve_cards is not Array")
		return
	var cards: Array = cards_val
	for i in range(cards.size()):
		_append_valid_command(
			out,
			discarded,
			context,
			"select_reserve_card",
			{"selected_index": i},
			validate_command,
			"reserve_card_%d" % i,
			["setup", "reserve"],
			0.0,
			max_valid_per_action
		)

static func _generate_restaurant_placements(
	out: Array[MacroAction],
	discarded: Array[String],
	observation: ObservationState,
	context: AiDecisionContext,
	validate_command: Callable,
	max_valid_per_action: int,
	id_prefix: String
) -> void:
	var grid_size := _read_grid_size(observation.map_public)
	if grid_size.x <= 0 or grid_size.y <= 0:
		discarded.append("%s: invalid grid_size %s" % [id_prefix, str(grid_size)])
		return
	var rotations := [0, 90, 180, 270]
	var employee_options := _restaurant_place_employee_options(observation)
	var use_competition_order := _has_competitor_restaurants(observation)
	var positions := _restaurant_placement_positions(observation, grid_size)
	var rotation_quota := _restaurant_position_rotation_quota(id_prefix, use_competition_order)
	for pos in positions:
		var x := pos.x
		var y := pos.y
		for employee_id in employee_options:
			var added_for_position := 0
			for rotation in rotations:
				if _count_action(out, "place_restaurant") >= max_valid_per_action:
					return
				if added_for_position >= rotation_quota:
					break
				var params := {
					"position": [x, y],
					"rotation": int(rotation),
				}
				var macro_suffix := "%d_%d_%d" % [x, y, int(rotation)]
				var tags: Array[String] = ["setup", "restaurant"]
				if not employee_id.is_empty():
					params["employee_type"] = employee_id
					macro_suffix = "%s_%s" % [employee_id, macro_suffix]
					tags = ["working", "restaurant", employee_id]
				var count_before := _count_action(out, "place_restaurant")
				_append_valid_command(
					out,
					discarded,
					context,
					"place_restaurant",
					params,
					validate_command,
					"%s_%s" % [id_prefix, macro_suffix],
					tags,
					0.0,
					max_valid_per_action
				)
				if _count_action(out, "place_restaurant") > count_before:
					added_for_position += 1

static func _generate_restructuring(
	out: Array[MacroAction],
	discarded: Array[String],
	observation: ObservationState,
	context: AiDecisionContext,
	legal_action_ids: Array[String],
	validate_command: Callable,
	max_valid_per_action: int,
	options: Dictionary
) -> void:
	if legal_action_ids.has("restructure_employee"):
		_generate_training_reserve_moves(out, discarded, observation, context, validate_command, max_valid_per_action, options)
	if legal_action_ids.has("set_company_structure_direct"):
		_generate_direct_structure_assignments(out, discarded, observation, context, validate_command, max_valid_per_action, options)
	if legal_action_ids.has("set_company_structure_report"):
		_generate_report_structure_assignments(out, discarded, observation, context, validate_command, max_valid_per_action, options)
	if legal_action_ids.has("submit_restructuring"):
		_append_valid_command(out, discarded, context, "submit_restructuring", {}, validate_command, "submit_restructuring", ["restructuring"], _submit_restructuring_prior(observation), max_valid_per_action)

static func _generate_training_reserve_moves(
	out: Array[MacroAction],
	discarded: Array[String],
	observation: ObservationState,
	context: AiDecisionContext,
	validate_command: Callable,
	max_valid_per_action: int,
	options: Dictionary
) -> void:
	if not EmployeeRegistryClass.is_loaded():
		discarded.append("restructuring: EmployeeRegistry is not loaded")
		return
	for employee_id in _sorted_unique_strings(observation.own_player.get("employees", [])):
		if _is_train_provider_employee(employee_id):
			continue
		if not _should_preserve_for_training(employee_id, observation, context, validate_command, options):
			continue
		_append_valid_command(
			out,
			discarded,
			context,
			"restructure_employee",
			{
				"employee_id": employee_id,
				"to_reserve": true,
			},
			validate_command,
			"restructure_to_reserve_%s" % employee_id,
			["restructuring", "reserve", "train"],
			_training_reserve_move_prior(employee_id, observation, context, validate_command, options),
			max_valid_per_action
		)

static func _generate_direct_structure_assignments(
	out: Array[MacroAction],
	discarded: Array[String],
	observation: ObservationState,
	context: AiDecisionContext,
	validate_command: Callable,
	max_valid_per_action: int,
	options: Dictionary
) -> void:
	var cs_val = observation.own_player.get("company_structure", {})
	if not (cs_val is Dictionary):
		discarded.append("restructuring: own_player.company_structure is not Dictionary")
		return
	var cs: Dictionary = cs_val
	var ceo_slots := int(cs.get("ceo_slots", 0))
	if ceo_slots <= 0:
		discarded.append("restructuring: ceo_slots is invalid")
		return
	var structure_val = cs.get("structure", [])
	var structure: Array = structure_val if structure_val is Array else []
	var assigned_counts := _count_assigned_employees(structure)
	var owned_counts := _count_owned_employees(observation.own_player)
	var employee_ids := _sorted_string_keys(owned_counts)
	_sort_structure_employee_ids(employee_ids, observation, options)
	var empty_slots := _empty_direct_slots(structure, ceo_slots)
	for employee_id in employee_ids:
		if employee_id == "ceo":
			continue
		if _should_preserve_for_training(employee_id, observation, context, validate_command, options):
			continue
		var remaining := int(owned_counts.get(employee_id, 0)) - int(assigned_counts.get(employee_id, 0))
		if remaining <= 0:
			continue
		for slot_index in empty_slots:
			_append_valid_command(
				out,
				discarded,
				context,
				"set_company_structure_direct",
				{
					"slot_index": int(slot_index),
					"employee_id": employee_id,
				},
				validate_command,
				"restructure_direct_%d_%s" % [int(slot_index), employee_id],
				["restructuring", "direct"],
				_structure_assignment_prior(employee_id, observation, context, validate_command, options),
				max_valid_per_action
			)

static func _generate_report_structure_assignments(
	out: Array[MacroAction],
	discarded: Array[String],
	observation: ObservationState,
	context: AiDecisionContext,
	validate_command: Callable,
	max_valid_per_action: int,
	options: Dictionary
) -> void:
	if not EmployeeRegistryClass.is_loaded():
		discarded.append("restructuring: EmployeeRegistry is not loaded")
		return
	var cs_val = observation.own_player.get("company_structure", {})
	if not (cs_val is Dictionary):
		discarded.append("restructuring: own_player.company_structure is not Dictionary")
		return
	var cs: Dictionary = cs_val
	var ceo_slots := int(cs.get("ceo_slots", 0))
	if ceo_slots <= 0:
		discarded.append("restructuring: ceo_slots is invalid")
		return
	var structure_val = cs.get("structure", [])
	if not (structure_val is Array):
		discarded.append("restructuring: company_structure.structure is not Array")
		return
	var structure: Array = structure_val
	var active_counts := _count_employees_in_list(observation.own_player.get("employees", []))
	var assigned_counts := _count_assigned_employees(structure)
	var owned_counts := _count_owned_employees(observation.own_player)
	var employee_ids := _sorted_string_keys(owned_counts)
	_sort_structure_employee_ids(employee_ids, observation, options)
	for slot_index in range(mini(ceo_slots, structure.size())):
		var entry_val = structure[slot_index]
		if not (entry_val is Dictionary):
			continue
		var entry: Dictionary = entry_val
		var manager_id := str(entry.get("employee_id", ""))
		if manager_id.is_empty() or int(active_counts.get(manager_id, 0)) <= 0:
			continue
		var manager_def_val = EmployeeRegistryClass.get_def(manager_id)
		if not (manager_def_val is EmployeeDef):
			continue
		var manager_def: EmployeeDef = manager_def_val
		var capacity := maxi(0, int(manager_def.manager_slots))
		if capacity <= 0:
			continue
		var report_count := _valid_report_count(entry, active_counts)
		if report_count >= capacity:
			continue
		for employee_id in employee_ids:
			if employee_id == "ceo" or _is_manager_employee(employee_id):
				continue
			if _should_preserve_for_training(employee_id, observation, context, validate_command, options):
				continue
			var remaining := int(owned_counts.get(employee_id, 0)) - int(assigned_counts.get(employee_id, 0))
			if remaining <= 0:
				continue
			_append_valid_command(
				out,
				discarded,
				context,
				"set_company_structure_report",
				{
					"manager_slot_index": int(slot_index),
					"employee_id": employee_id,
				},
				validate_command,
				"restructure_report_%d_%s" % [int(slot_index), employee_id],
				["restructuring", "report"],
				_structure_assignment_prior(employee_id, observation, context, validate_command, options),
				max_valid_per_action
			)

static func _generate_order_of_business(
	out: Array[MacroAction],
	discarded: Array[String],
	observation: ObservationState,
	context: AiDecisionContext,
	legal_action_ids: Array[String],
	validate_command: Callable,
	max_valid_per_action: int
) -> void:
	if not legal_action_ids.has("choose_turn_order"):
		return
	var oob_val = observation.round_state_public.get("order_of_business", {})
	if not (oob_val is Dictionary):
		discarded.append("turn_order: round_state.order_of_business is missing")
		return
	var picks_val = Dictionary(oob_val).get("picks", [])
	if not (picks_val is Array):
		discarded.append("turn_order: order_of_business.picks is missing")
		return
	var picks: Array = picks_val
	for i in range(picks.size()):
		if int(picks[i]) != -1:
			continue
		_append_valid_command(
			out,
			discarded,
			context,
			"choose_turn_order",
			{"position": i},
			validate_command,
			"turn_order_%d" % i,
			["order_of_business"],
			0.0,
			max_valid_per_action
		)

static func _generate_working(
	out: Array[MacroAction],
	discarded: Array[String],
	observation: ObservationState,
	context: AiDecisionContext,
	legal_action_ids: Array[String],
	validate_command: Callable,
	max_valid_per_action: int,
	options: Dictionary
) -> void:
	_generate_working_mandatory_actions(out, discarded, context, legal_action_ids, validate_command, max_valid_per_action)
	match str(observation.sub_phase):
		DefsClass.SUB_PHASE_RECRUIT:
			if legal_action_ids.has("recruit"):
				_generate_recruit(out, discarded, observation, context, validate_command, max_valid_per_action, options)
		DefsClass.SUB_PHASE_TRAIN:
			if legal_action_ids.has("train"):
				_generate_train(out, discarded, observation, context, validate_command, max_valid_per_action, options)
		DefsClass.SUB_PHASE_MARKETING:
			if legal_action_ids.has("initiate_marketing"):
				_generate_marketing(out, discarded, observation, context, validate_command, max_valid_per_action, options)
		DefsClass.SUB_PHASE_GET_FOOD:
			if legal_action_ids.has("produce_food"):
				_generate_produce_food(out, discarded, observation, context, validate_command, max_valid_per_action, options)
		DefsClass.SUB_PHASE_GET_DRINKS:
			if legal_action_ids.has("procure_drinks"):
				_generate_errand_boy_drinks(out, discarded, observation, context, validate_command, max_valid_per_action, options)
				_generate_route_drinks(out, discarded, observation, context, validate_command, max_valid_per_action, options)
		DefsClass.SUB_PHASE_PLACE_HOUSES:
			if legal_action_ids.has("place_house"):
				_generate_house_placements(out, discarded, observation, context, validate_command, max_valid_per_action)
			if legal_action_ids.has("add_garden"):
				_generate_garden_additions(out, discarded, observation, context, validate_command, max_valid_per_action)
		DefsClass.SUB_PHASE_PLACE_RESTAURANTS:
			if legal_action_ids.has("place_restaurant"):
				_generate_restaurant_placements(out, discarded, observation, context, validate_command, max_valid_per_action, "working_restaurant")
			if legal_action_ids.has("move_restaurant"):
				_generate_restaurant_moves(out, discarded, observation, context, validate_command, max_valid_per_action)

	if legal_action_ids.has(ActionIdsClass.SKIP_SUB_PHASE):
		_append_valid_command(out, discarded, context, ActionIdsClass.SKIP_SUB_PHASE, {}, validate_command, "working_skip_sub_phase", ["working", "fallback"], -0.1, max_valid_per_action)
	if legal_action_ids.has(ActionIdsClass.SKIP):
		_append_valid_command(out, discarded, context, ActionIdsClass.SKIP, {}, validate_command, "working_skip", ["working", "fallback"], -0.1, max_valid_per_action)

static func _generate_working_mandatory_actions(
	out: Array[MacroAction],
	discarded: Array[String],
	context: AiDecisionContext,
	legal_action_ids: Array[String],
	validate_command: Callable,
	max_valid_per_action: int
) -> void:
	for action_id in WORKING_MANDATORY_ACTION_IDS:
		if not legal_action_ids.has(action_id):
			continue
		_append_valid_command(
			out,
			discarded,
			context,
			action_id,
			{},
			validate_command,
			"mandatory_%s" % action_id,
			["working", "mandatory"],
			0.0,
			max_valid_per_action
		)

static func _generate_marketing(
	out: Array[MacroAction],
	discarded: Array[String],
	observation: ObservationState,
	context: AiDecisionContext,
	validate_command: Callable,
	max_valid_per_action: int,
	options: Dictionary
) -> void:
	if not EmployeeRegistryClass.is_loaded():
		discarded.append("marketing: EmployeeRegistry is not loaded")
		return
	if not MarketingRegistryClass.is_loaded():
		discarded.append("marketing: MarketingRegistry is not loaded")
		return
	if not ProductRegistryClass.is_loaded():
		discarded.append("marketing: ProductRegistry is not loaded")
		return
	var plan_hints := _plan_hints_dict(options)
	var products := _sorted_marketable_product_ids_for_observation(observation, plan_hints)
	if products.is_empty():
		discarded.append("marketing: no marketable products")
		return
	var grid_size := _read_grid_size(observation.map_public)
	if grid_size.x <= 0 or grid_size.y <= 0:
		discarded.append("marketing: invalid grid_size %s" % str(grid_size))
		return
	var source_state := _source_state_from_options(options)
	var source_analysis := _source_board_analysis(source_state, options)
	if source_state != null:
		_sort_marketing_products_for_source_state(products, observation, source_state, source_analysis, plan_hints)
	for employee_id in _sorted_employee_ids_for_plan_hints(_sorted_unique_strings(observation.own_player.get("employees", [])), observation, options, "initiate_marketing"):
		var marketing_types := _marketing_types_for_employee(employee_id)
		if marketing_types.is_empty():
			continue
		var board_numbers := _available_marketing_board_numbers(marketing_types, observation, discarded)
		_sort_marketing_board_numbers_for_hints(board_numbers, plan_hints)
		var board_quota := _marketing_board_candidate_quota(max_valid_per_action, board_numbers.size(), options)
		for board_number in board_numbers:
			var board_def = MarketingRegistryClass.get_def(int(board_number))
			if not (board_def is MarketingDef):
				continue
			var marketing_type := str((board_def as MarketingDef).type)
			var added_for_board := 0
			var board_full := false
			var rotations := _marketing_rotations_for_board(board_def as MarketingDef, marketing_type)
			var positions_by_rotation := {}
			for rotation in rotations:
				positions_by_rotation[int(rotation)] = _marketing_candidate_positions_for_board_rotation(
					observation,
					grid_size,
					board_def as MarketingDef,
					marketing_type,
					int(rotation),
					source_state
				)
			for product_id in products:
				if board_full:
					break
				for rotation in rotations:
					if board_full:
						break
					var candidate_positions_val = positions_by_rotation.get(int(rotation), [])
					if not (candidate_positions_val is Array):
						continue
					var candidate_positions: Array = _rank_marketing_candidate_positions(
						observation,
						context,
						candidate_positions_val,
						product_id,
						source_state,
						source_analysis,
						board_def as MarketingDef,
						marketing_type,
						int(rotation),
						discarded,
						plan_hints
					)
					if candidate_positions.is_empty():
						continue
					for pos_val in candidate_positions:
						var pos := _read_vector2i(pos_val)
						if _budget_expired(options):
							discarded.append("marketing: budget expired")
							return
						if _count_action(out, "initiate_marketing") >= max_valid_per_action:
							return
						if added_for_board >= board_quota:
							board_full = true
							break
						var x := pos.x
						var y := pos.y
						var params := {
							"employee_type": employee_id,
							"board_number": int(board_number),
							"product": product_id,
							"position": [x, y],
							"rotation": int(rotation),
						}
						if marketing_type == "airplane":
							params["axis"] = "row" if x == 0 or x == grid_size.x - 1 else "col"
						var macro_id := "marketing_%s_%d_%s_%d_%d_%d" % [employee_id, int(board_number), product_id, x, y, int(rotation)]
						var precheck_reason := _marketing_geometry_precheck(source_state, params, board_def as MarketingDef, marketing_type)
						if not precheck_reason.is_empty():
							discarded.append("%s: %s" % [macro_id, precheck_reason])
							continue
						var count_before := _count_action(out, "initiate_marketing")
						_append_valid_marketing_command(
							out,
							discarded,
							context,
							observation,
							params,
							validate_command,
							macro_id,
							["working", "marketing"],
							_marketing_product_prior(product_id, observation, plan_hints),
							max_valid_per_action,
							source_state,
							source_analysis,
							board_def as MarketingDef,
							marketing_type
						)
						var count_after := _count_action(out, "initiate_marketing")
						if count_after > count_before:
							added_for_board += count_after - count_before
							if added_for_board >= board_quota:
								board_full = true
								break

static func _generate_house_placements(
	out: Array[MacroAction],
	discarded: Array[String],
	observation: ObservationState,
	context: AiDecisionContext,
	validate_command: Callable,
	max_valid_per_action: int
) -> void:
	var grid_size := _read_grid_size(observation.map_public)
	if grid_size.x <= 0 or grid_size.y <= 0:
		discarded.append("place_house: invalid grid_size %s" % str(grid_size))
		return
	var house_numbers := _read_remaining_house_numbers(observation.map_public)
	if house_numbers.is_empty():
		discarded.append("place_house: no remaining house numbers")
		return
	var house_number := int(house_numbers[0])
	var rotations := [0, 90, 180, 270]
	var positions := _house_placement_positions(observation, grid_size)
	for pos in positions:
		for rotation in rotations:
			if _count_action(out, "place_house") >= max_valid_per_action:
				return
			_append_valid_command(
				out,
				discarded,
				context,
				"place_house",
				{
					"position": [pos.x, pos.y],
					"rotation": int(rotation),
					"house_number": house_number,
				},
				validate_command,
				"place_house_%d_%d_%d_%d" % [house_number, pos.x, pos.y, int(rotation)],
				["working", "place_house"],
				_house_placement_prior(observation, pos),
				max_valid_per_action
			)

static func _generate_garden_additions(
	out: Array[MacroAction],
	discarded: Array[String],
	observation: ObservationState,
	context: AiDecisionContext,
	validate_command: Callable,
	max_valid_per_action: int
) -> void:
	var houses_val = observation.map_public.get("houses", {})
	if not (houses_val is Dictionary):
		discarded.append("add_garden: map_public.houses is not Dictionary")
		return
	var houses: Dictionary = houses_val
	var directions := ["N", "E", "S", "W"]
	for house_id in _sorted_string_keys(houses):
		var house_val = houses.get(house_id, null)
		if not (house_val is Dictionary):
			continue
		var house: Dictionary = house_val
		if bool(house.get("has_garden", false)):
			continue
		for direction in directions:
			if _count_action(out, "add_garden") >= max_valid_per_action:
				return
			_append_valid_command(
				out,
				discarded,
				context,
				"add_garden",
				{
					"house_id": house_id,
					"direction": direction,
				},
				validate_command,
				"add_garden_%s_%s" % [house_id, direction],
				["working", "add_garden"],
				0.05,
				max_valid_per_action
			)

static func _generate_restaurant_moves(
	out: Array[MacroAction],
	discarded: Array[String],
	observation: ObservationState,
	context: AiDecisionContext,
	validate_command: Callable,
	max_valid_per_action: int
) -> void:
	var grid_size := _read_grid_size(observation.map_public)
	if grid_size.x <= 0 or grid_size.y <= 0:
		discarded.append("move_restaurant: invalid grid_size %s" % str(grid_size))
		return
	var restaurants_val = observation.map_public.get("restaurants", {})
	if not (restaurants_val is Dictionary):
		discarded.append("move_restaurant: map_public.restaurants is not Dictionary")
		return
	var restaurants: Dictionary = restaurants_val
	var restaurant_ids := _sorted_owned_restaurant_ids(observation.own_player, restaurants)
	if restaurant_ids.is_empty():
		discarded.append("move_restaurant: own player has no restaurants")
		return
	var rotations := [0, 90, 180, 270]
	var use_competition_order := _has_competitor_restaurants(observation)
	var positions := _restaurant_placement_positions(observation, grid_size)
	var rotation_quota := _restaurant_position_rotation_quota("move_restaurant", use_competition_order)
	for restaurant_id in restaurant_ids:
		var rest: Dictionary = restaurants.get(restaurant_id, {})
		var current_anchor := _read_vector2i(rest.get("anchor_pos", Vector2i(-9999, -9999)))
		for pos in positions:
			var x := pos.x
			var y := pos.y
			if pos == current_anchor:
				continue
			var added_for_position := 0
			for rotation in rotations:
				if _count_action(out, "move_restaurant") >= max_valid_per_action:
					return
				if added_for_position >= rotation_quota:
					break
				var count_before := _count_action(out, "move_restaurant")
				_append_valid_command(
					out,
					discarded,
					context,
					"move_restaurant",
					{
						"restaurant_id": restaurant_id,
						"position": [x, y],
						"rotation": int(rotation),
					},
					validate_command,
					"move_restaurant_%s_%d_%d_%d" % [restaurant_id, x, y, int(rotation)],
					["working", "move_restaurant"],
					0.0,
					max_valid_per_action
				)
				if _count_action(out, "move_restaurant") > count_before:
					added_for_position += 1
				if _count_action(out, "move_restaurant") >= max_valid_per_action:
					return

static func _generate_recruit(
	out: Array[MacroAction],
	discarded: Array[String],
	observation: ObservationState,
	context: AiDecisionContext,
	validate_command: Callable,
	max_valid_per_action: int,
	options: Dictionary = {}
) -> void:
	var route_plan := _recruit_route_plan(observation, options)
	for employee_id in _sorted_recruit_pool_ids(observation, route_plan):
		_append_valid_command(
			out,
			discarded,
			context,
			"recruit",
			{"employee_type": employee_id},
			validate_command,
			"recruit_%s" % employee_id,
			["working", "recruit"],
			_recruit_prior_with_route_plan(employee_id, observation, route_plan),
			max_valid_per_action
		)

static func _generate_train(
	out: Array[MacroAction],
	discarded: Array[String],
	observation: ObservationState,
	context: AiDecisionContext,
	validate_command: Callable,
	max_valid_per_action: int,
	options: Dictionary = {}
) -> void:
	if not EmployeeRegistryClass.is_loaded():
		discarded.append("train: EmployeeRegistry is not loaded")
		return
	for from_employee in _sorted_unique_strings(observation.own_player.get("reserve_employees", [])):
		var def_val = EmployeeRegistryClass.get_def(from_employee)
		if not (def_val is EmployeeDef):
			continue
		var def: EmployeeDef = def_val
		var train_targets := _sorted_train_targets(def.train_to, from_employee, observation, context, validate_command, options)
		for to_employee in train_targets:
			var target := str(to_employee)
			if target.is_empty():
				continue
			if int(observation.employee_pool_public.get(target, 0)) <= 0:
				continue
			var prior := _train_prior(from_employee, target, observation, context, validate_command, options)
			if prior < TRAIN_ACTION_MIN_PRIOR:
				continue
			_append_valid_command(
				out,
				discarded,
				context,
				"train",
				{
					"from_employee": from_employee,
					"to_employee": target,
				},
				validate_command,
				"train_%s_to_%s" % [from_employee, target],
				["working", "train"],
				prior,
				max_valid_per_action
			)

static func _generate_produce_food(
	out: Array[MacroAction],
	discarded: Array[String],
	observation: ObservationState,
	context: AiDecisionContext,
	validate_command: Callable,
	max_valid_per_action: int,
	options: Dictionary = {}
) -> void:
	if not EmployeeRegistryClass.is_loaded():
		discarded.append("produce_food: EmployeeRegistry is not loaded")
		return
	for employee_id in _sorted_employee_ids_for_plan_hints(_sorted_unique_strings(observation.own_player.get("employees", [])), observation, options, "produce_food"):
		var def_val = EmployeeRegistryClass.get_def(employee_id)
		if not (def_val is EmployeeDef):
			continue
		var def: EmployeeDef = def_val
		if not def.can_produce():
			continue
		var food_options := _sorted_products_for_plan_hints(def.get_production_food_options(), observation, options)
		for food_type in food_options:
			_append_valid_command(
				out,
				discarded,
				context,
				"produce_food",
				{
					"employee_type": employee_id,
					"food_type": food_type,
				},
				validate_command,
				"produce_%s_%s" % [employee_id, food_type],
				["working", "produce_food"],
				_product_pipeline_prior(str(food_type), observation, options),
				max_valid_per_action
			)

static func _generate_errand_boy_drinks(
	out: Array[MacroAction],
	discarded: Array[String],
	observation: ObservationState,
	context: AiDecisionContext,
	validate_command: Callable,
	max_valid_per_action: int,
	options: Dictionary = {}
) -> void:
	var active := _sorted_employee_ids_for_plan_hints(_sorted_unique_strings(observation.own_player.get("employees", [])), observation, options, "procure_drinks")
	if not active.has("errand_boy"):
		return
	if not ProductRegistryClass.is_loaded():
		discarded.append("procure_drinks: ProductRegistry is not loaded")
		return
	var product_ids: Array[String] = []
	for product_id_val in ProductRegistryClass.get_all_ids():
		var product_id := str(product_id_val)
		if ProductRegistryClass.is_drink(product_id):
			product_ids.append(product_id)
	product_ids = _sorted_products_for_plan_hints(product_ids, observation, options)
	for product_id in product_ids:
		_append_valid_command(
			out,
			discarded,
			context,
			"procure_drinks",
			{
				"employee_type": "errand_boy",
				"drink_type": product_id,
			},
			validate_command,
			"errand_boy_%s" % product_id,
			["working", "procure_drinks", "errand_boy"],
			_product_pipeline_prior(product_id, observation, options),
			max_valid_per_action
		)

static func _generate_route_drinks(
	out: Array[MacroAction],
	discarded: Array[String],
	observation: ObservationState,
	context: AiDecisionContext,
	validate_command: Callable,
	max_valid_per_action: int,
	options: Dictionary = {}
) -> void:
	if not EmployeeRegistryClass.is_loaded():
		discarded.append("procure_drinks: EmployeeRegistry is not loaded")
		return
	var active := _sorted_employee_ids_for_plan_hints(_sorted_unique_strings(observation.own_player.get("employees", [])), observation, options, "procure_drinks")
	for employee_id in active:
		if _count_action(out, "procure_drinks") >= max_valid_per_action:
			return
		if employee_id == "errand_boy" or not EmployeeRegistryClass.has(employee_id):
			continue
		var def_val = EmployeeRegistryClass.get_def(employee_id)
		if not (def_val is EmployeeDef):
			continue
		var def: EmployeeDef = def_val
		if not def.can_procure():
			continue
		var route_search_limit := maxi(max_valid_per_action, max_valid_per_action * ROUTE_DRINK_SEARCH_MULTIPLIER)
		var routes_read := DrinkRouteAnalyzerClass.generate_routes(observation, employee_id, route_search_limit)
		if not routes_read.ok:
			discarded.append("procure_drinks:%s: %s" % [employee_id, routes_read.error])
			continue
		var routes: Array = routes_read.value
		if routes.is_empty():
			discarded.append("procure_drinks:%s: no route candidates" % employee_id)
			continue
		_sort_route_drinks_for_observation(routes, observation, options)
		for route_val in routes:
			if _count_action(out, "procure_drinks") >= max_valid_per_action:
				return
			if not (route_val is Dictionary):
				continue
			var route: Dictionary = route_val
			var params_val = route.get("params", null)
			if not (params_val is Dictionary):
				continue
			var params: Dictionary = params_val
			var range_type := str(route.get("range_type", "route"))
			var source_count := int(route.get("source_count", 0))
			var route_index := _count_action(out, "procure_drinks")
			var route_prior := _route_drink_prior(route, observation, options)
			_append_valid_command(
				out,
				discarded,
				context,
				"procure_drinks",
				params.duplicate(true),
				validate_command,
				"procure_%s_%s_%d_%d" % [employee_id, range_type, source_count, route_index],
				["working", "procure_drinks", range_type],
				route_prior,
				max_valid_per_action
			)

static func _generate_cleanup(
	out: Array[MacroAction],
	discarded: Array[String],
	observation: ObservationState,
	context: AiDecisionContext,
	legal_action_ids: Array[String],
	validate_command: Callable,
	max_valid_per_action: int
) -> void:
	if legal_action_ids.has("choose_fridge_keep"):
		var keep := _build_fridge_keep(observation)
		_append_valid_command(out, discarded, context, "choose_fridge_keep", {"keep": keep}, validate_command, "fridge_keep_inventory", ["cleanup"], 0.0, max_valid_per_action)
	else:
		_generate_phase_skip(out, discarded, context, legal_action_ids, validate_command, max_valid_per_action)

static func _generate_payday(
	out: Array[MacroAction],
	discarded: Array[String],
	observation: ObservationState,
	context: AiDecisionContext,
	legal_action_ids: Array[String],
	validate_command: Callable,
	max_valid_per_action: int
) -> void:
	if legal_action_ids.has("fire"):
		_generate_fire_candidates(out, discarded, observation, context, validate_command, max_valid_per_action)
	_generate_phase_skip(out, discarded, context, legal_action_ids, validate_command, max_valid_per_action)

static func _generate_fire_candidates(
	out: Array[MacroAction],
	discarded: Array[String],
	observation: ObservationState,
	context: AiDecisionContext,
	validate_command: Callable,
	max_valid_per_action: int
) -> void:
	if not EmployeeRegistryClass.is_loaded():
		discarded.append("fire: EmployeeRegistry is not loaded")
		return
	if not _has_estimated_payday_salary_shortfall(observation):
		discarded.append("fire: no estimated payday salary shortfall")
		return
	for zone_info in [
		{"key": "employees", "location": "active"},
		{"key": "reserve_employees", "location": "reserve"},
		{"key": "busy_marketers", "location": "busy"},
	]:
		var key := str(zone_info.get("key", ""))
		var location := str(zone_info.get("location", ""))
		for employee_id in _sorted_unique_strings(observation.own_player.get(key, [])):
			if not _can_employee_be_fired(employee_id):
				continue
			if not EmployeeRulesClass.requires_salary(employee_id, observation.own_player):
				continue
			_append_valid_command(
				out,
				discarded,
				context,
				"fire",
				{
					"employee_id": employee_id,
					"location": location,
				},
				validate_command,
				"fire_%s_%s" % [location, employee_id],
				["payday", "fire"],
				0.0,
				max_valid_per_action
			)

static func _generate_phase_skip(
	out: Array[MacroAction],
	discarded: Array[String],
	context: AiDecisionContext,
	legal_action_ids: Array[String],
	validate_command: Callable,
	max_valid_per_action: int
) -> void:
	if legal_action_ids.has(ActionIdsClass.SKIP):
		_append_valid_command(out, discarded, context, ActionIdsClass.SKIP, {}, validate_command, "phase_skip", ["fallback"], 0.0, max_valid_per_action)

static func _generate_pending_confirmation(
	out: Array[MacroAction],
	discarded: Array[String],
	observation: ObservationState,
	context: AiDecisionContext,
	legal_action_ids: Array[String],
	validate_command: Callable,
	max_valid_per_action: int
) -> void:
	if _has_pending_player_action(observation, DefsClass.PHASE_DINNERTIME, context.player_id, "confirm_dinnertime") and legal_action_ids.has("confirm_dinnertime"):
		_append_valid_command(out, discarded, context, "confirm_dinnertime", {}, validate_command, "confirm_dinnertime", ["confirm"], 0.0, max_valid_per_action)
	if _has_pending_player_action(observation, DefsClass.PHASE_MARKETING, context.player_id, "confirm_marketing") and legal_action_ids.has("confirm_marketing"):
		_append_valid_command(out, discarded, context, "confirm_marketing", {}, validate_command, "confirm_marketing", ["confirm"], 0.0, max_valid_per_action)

static func _append_valid_command(
	out: Array[MacroAction],
	discarded: Array[String],
	context: AiDecisionContext,
	action_id: String,
	params: Dictionary,
	validate_command: Callable,
	macro_id: String,
	tags: Array[String],
	prior_score: float,
	max_valid_per_action: int
) -> void:
	if _count_action(out, action_id) >= max_valid_per_action:
		return
	var command := Command.create(action_id, context.player_id, params.duplicate(true))
	var validate := _validate_command(command, validate_command)
	if not validate.ok:
		discarded.append("%s: %s" % [macro_id, validate.error])
		return
	var commands: Array[Command] = []
	commands.append(command)
	out.append(MacroActionClass.create(macro_id, commands, prior_score, tags, {
		"action_id": action_id,
		"validation": "passed" if validate_command.is_valid() else "skipped",
	}))

static func _append_valid_marketing_command(
	out: Array[MacroAction],
	discarded: Array[String],
	context: AiDecisionContext,
	observation: ObservationState,
	params: Dictionary,
	validate_command: Callable,
	macro_id: String,
	tags: Array[String],
	prior_score: float,
	max_valid_per_action: int,
	source_state: GameState,
	source_analysis: Dictionary,
	board_def: MarketingDef,
	marketing_type: String
) -> void:
	var action_id := "initiate_marketing"
	if _count_action(out, action_id) >= max_valid_per_action:
		return
	var command := Command.create(action_id, context.player_id, params.duplicate(true))
	var affected: Array = []
	var service_features := {}
	if source_state != null:
		var affected_read := _marketing_command_affected_house_ids(source_state, context.player_id, command, board_def, marketing_type)
		if not affected_read.ok:
			discarded.append("%s: affected house check failed: %s" % [macro_id, affected_read.error])
			return
		affected = affected_read.value
		if affected.is_empty():
			discarded.append("%s: affects no houses" % macro_id)
			return
		var affected_ids := _string_array(affected)
		service_features = MarketingPressureAnalyzerClass.analyze_candidate(observation, affected_ids, str(params.get("product", "")), source_state, source_analysis)
		var discard_reason := _marketing_serviceability_discard_reason(service_features)
		if not discard_reason.is_empty():
			discarded.append("%s: %s" % [macro_id, discard_reason])
			return
	var validate := _validate_command(command, validate_command)
	if not validate.ok:
		discarded.append("%s: %s" % [macro_id, validate.error])
		return
	var commands: Array[Command] = []
	commands.append(command)
	out.append(MacroActionClass.create(macro_id, commands, prior_score, tags, {
		"action_id": action_id,
		"validation": "passed" if validate_command.is_valid() else "skipped",
		"affected_house_ids": affected.duplicate(),
		"marketing_service_features": service_features.duplicate(true),
	}))

static func _marketing_serviceability_discard_reason(service_features: Dictionary) -> String:
	return MarketingPressureAnalyzerClass.discard_reason(service_features)

static func _marketing_geometry_precheck(
	state: GameState,
	params: Dictionary,
	board_def: MarketingDef,
	marketing_type: String
) -> String:
	if state == null or board_def == null:
		return ""
	if marketing_type == "airplane":
		return ""
	var world_pos := _read_vector2i(params.get("position", Vector2i.ZERO))
	var rotation := int(params.get("rotation", 0))
	var size_read := MarketingRulesClass.get_rotated_footprint_size(Vector2i(board_def.footprint_size), rotation)
	if not size_read.ok:
		return size_read.error
	var size: Vector2i = size_read.value
	var footprint_cells: Array[Vector2i] = MarketingRulesClass.build_footprint_cells(world_pos, size)
	if footprint_cells.is_empty():
		return "marketing footprint is empty"
	for cell_pos in footprint_cells:
		if not CoordsClass.is_world_pos_in_grid(state, cell_pos):
			return "position 越界: %s" % str(cell_pos)
		var cell := CellsClass.get_cell(state, cell_pos)
		if cell.is_empty():
			return "position 无效: %s" % str(cell_pos)
		var structure_val = cell.get("structure", null)
		if structure_val is Dictionary and not Dictionary(structure_val).is_empty():
			return "该位置已有建筑，无法放置营销: %s" % str(cell_pos)
		var drink_source_val = cell.get("drink_source", null)
		if drink_source_val != null and (not (drink_source_val is Dictionary) or not Dictionary(drink_source_val).is_empty()):
			return "该位置是饮品进货点，无法放置营销: %s" % str(cell_pos)

	var requires_edge := MarketingTypeRegistryClass.requires_edge(marketing_type)
	if requires_edge:
		var minp := CoordsClass.get_world_min(state)
		var maxp := CoordsClass.get_world_max(state)
		var left := world_pos.x
		var right := world_pos.x + size.x - 1
		var top := world_pos.y
		var bottom := world_pos.y + size.y - 1
		if left != minp.x and right != maxp.x and top != minp.y and bottom != maxp.y:
			return "该营销必须有一条边完全贴地图边缘: %s" % str(world_pos)
		return ""

	var footprint_set := {}
	for cell_pos2 in footprint_cells:
		var cell2 := CellsClass.get_cell(state, cell_pos2)
		if bool(cell2.get("blocked", false)):
			return "该位置被阻塞: %s" % str(cell_pos2)
		var road_segments_val = cell2.get("road_segments", [])
		if road_segments_val is Array and not Array(road_segments_val).is_empty():
			return "营销必须放置在空格（非道路）上: %s (anchor=%s board=#%d)" % [str(cell_pos2), str(world_pos), int(board_def.board_number)]
		footprint_set[cell_pos2] = true
	var has_adjacent_road := false
	for cell_pos3 in footprint_cells:
		for dir in MapUtilsClass.DIRECTIONS:
			var neighbor := MapUtilsClass.get_neighbor_pos(cell_pos3, dir)
			if footprint_set.has(neighbor):
				continue
			if not CoordsClass.is_world_pos_in_grid(state, neighbor):
				continue
			if CellsClass.has_road_at(state, neighbor):
				has_adjacent_road = true
				break
		if has_adjacent_road:
			break
	if not has_adjacent_road:
		return "营销必须邻接道路: %s" % str(world_pos)
	return ""

static func _validate_command(command: Command, validate_command: Callable) -> Result:
	if not validate_command.is_valid():
		return Result.success()
	var validated = validate_command.call(command)
	if validated is Result:
		return validated
	return Result.failure("validator returned non-Result")

static func _marketing_command_affected_house_ids(
	state: GameState,
	player_id: int,
	command: Command,
	board_def: MarketingDef,
	marketing_type: String
) -> Result:
	if state == null:
		return Result.failure("source_state is null")
	if command == null:
		return Result.failure("command is null")
	if board_def == null:
		return Result.failure("board_def is null")
	var params := command.params
	var world_pos := _read_vector2i(params.get("position", Vector2i.ZERO))
	var instance := {
		"board_number": int(board_def.board_number),
		"type": marketing_type,
		"owner": player_id,
		"employee_type": str(params.get("employee_type", "")),
		"product": str(params.get("product", "")),
		"world_pos": world_pos,
		"rotation": int(params.get("rotation", 0)),
		"footprint_size": Vector2i(board_def.footprint_size),
		"remaining_duration": 1,
		"axis": str(params.get("axis", "")),
		"tile_index": -1,
		"created_round": int(state.round_number),
	}
	var calculator = MarketingRangeCalculatorClass.new()
	var affected_read: Result = calculator.get_affected_house_ids(state, instance)
	if not affected_read.ok:
		return affected_read
	if not (affected_read.value is Array):
		return Result.failure("affected house result is not Array")
	var affected: Array = affected_read.value
	return Result.success(affected)

static func _count_action(candidates: Array[MacroAction], action_id: String) -> int:
	var count := 0
	for macro in candidates:
		if macro == null:
			continue
		for command in macro.commands:
			if command != null and command.action_id == action_id:
				count += 1
	return count

static func _sorted_positive_pool_ids(pool: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for key in pool.keys():
		if not (key is String):
			continue
		var id := str(key)
		if id.is_empty():
			continue
		if int(pool.get(id, 0)) <= 0:
			continue
		out.append(id)
	out.sort()
	return out

static func _sorted_recruit_pool_ids(observation: ObservationState, route_plan: Dictionary = {}) -> Array[String]:
	if observation == null:
		return []
	var out: Array[String] = []
	for employee_id in _sorted_positive_pool_ids(observation.employee_pool_public):
		if not EmployeeRulesClass.is_entry_level(employee_id):
			continue
		out.append(employee_id)
	var priorities := {}
	for employee_id in out:
		priorities[employee_id] = _recruit_prior_with_route_plan(employee_id, observation, route_plan)
	out.sort_custom(func(a: String, b: String) -> bool:
		var prior_a := float(priorities.get(a, 0.0))
		var prior_b := float(priorities.get(b, 0.0))
		if not is_equal_approx(prior_a, prior_b):
			return prior_a > prior_b
		return a < b
	)
	return out

static func _sorted_string_keys(dict: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for key in dict.keys():
		if key is String:
			out.append(str(key))
	out.sort()
	return out

static func _sorted_unique_strings(value) -> Array[String]:
	var set := {}
	if value is Array:
		for item in Array(value):
			var id := str(item)
			if id.is_empty():
				continue
			set[id] = true
	var out: Array[String] = []
	for key in set.keys():
		if key is String:
			out.append(str(key))
	out.sort()
	return out

static func _string_array(value) -> Array[String]:
	var out: Array[String] = []
	if value is Array:
		for item in Array(value):
			var id := str(item)
			if id.is_empty():
				continue
			out.append(id)
	return out

static func _plan_hints_dict(options: Dictionary) -> Dictionary:
	var value = options.get("plan_hints", null)
	if value is Object:
		var obj: Object = value
		if obj.has_method("to_dict"):
			var dict_val = obj.call("to_dict")
			if dict_val is Dictionary:
				return Dictionary(dict_val)
	if value is Dictionary:
		return Dictionary(value)
	if options.has("preferred_products") or options.has("preferred_actions") or options.has("execution_sequence"):
		return options
	return {}

static func _options_without_plan_hints(options: Dictionary) -> Dictionary:
	if options.is_empty():
		return {}
	var stripped := options.duplicate(true)
	stripped.erase("plan_hints")
	stripped.erase("preferred_products")
	stripped.erase("preferred_actions")
	stripped.erase("execution_sequence")
	stripped.erase("preferred_employee_ids")
	stripped.erase("preferred_employee_roles")
	stripped.erase("preferred_marketing_house_ids")
	stripped.erase("preferred_marketing_board_numbers")
	stripped.erase("preferred_price_actions")
	stripped.erase("avoid_actions")
	stripped.erase("cash_floor")
	stripped.erase("growth_bias")
	stripped.erase("plan_id")
	return stripped

static func _plan_hints_action_bonus(plan_hints: Dictionary, action_id: String) -> float:
	if action_id.is_empty() or plan_hints.is_empty():
		return 0.0
	var sequence := _string_array(plan_hints.get("execution_sequence", []))
	var sequence_index := sequence.find(action_id)
	if sequence_index >= 0:
		return maxf(0.0, 1.4 - float(sequence_index) * 0.15)
	var preferred_actions := _string_array(plan_hints.get("preferred_actions", []))
	if preferred_actions.has(action_id):
		return 0.6
	return 0.0

static func _plan_hints_product_bonus(plan_hints: Dictionary, product_id: String) -> float:
	if product_id.is_empty() or plan_hints.is_empty():
		return 0.0
	var preferred_products := _string_array(plan_hints.get("preferred_products", []))
	return 4.0 if preferred_products.has(product_id) else 0.0

static func _plan_hints_employee_bonus(plan_hints: Dictionary, employee_id: String, role: String = "", action_id: String = "") -> float:
	if plan_hints.is_empty():
		return 0.0
	var bonus := _plan_hints_action_bonus(plan_hints, action_id)
	var preferred_employee_ids := _string_array(plan_hints.get("preferred_employee_ids", []))
	if not employee_id.is_empty() and preferred_employee_ids.has(employee_id):
		bonus += 3.5
	var preferred_roles := _string_array(plan_hints.get("preferred_employee_roles", []))
	if not role.is_empty() and preferred_roles.has(role):
		bonus += 2.0
	return bonus

static func _route_plan_employee_hint_bonus(route_plan: Dictionary, employee_id: String, role: String, action_id: String) -> float:
	if route_plan.is_empty():
		return 0.0
	return _plan_hints_employee_bonus({
		"preferred_employee_ids": _string_array(route_plan.get("preferred_employee_ids", [])),
		"preferred_employee_roles": _string_array(route_plan.get("preferred_employee_roles", [])),
		"preferred_actions": _string_array(route_plan.get("preferred_actions", [])),
		"execution_sequence": _string_array(route_plan.get("execution_sequence", [])),
	}, employee_id, role, action_id)

static func _plan_hints_house_bonus(plan_hints: Dictionary, affected_house_ids: Array) -> float:
	if plan_hints.is_empty() or affected_house_ids.is_empty():
		return 0.0
	var preferred_houses := _string_array(plan_hints.get("preferred_marketing_house_ids", []))
	if preferred_houses.is_empty():
		return 0.0
	var hits := 0
	for house_id_val in affected_house_ids:
		if preferred_houses.has(str(house_id_val)):
			hits += 1
	return float(hits) * 600.0

static func _sort_marketing_board_numbers_for_hints(board_numbers: Array[int], plan_hints: Dictionary) -> void:
	if board_numbers.size() <= 1 or plan_hints.is_empty():
		return
	var preferred_boards: Array[int] = []
	var preferred_val = plan_hints.get("preferred_marketing_board_numbers", [])
	if preferred_val is Array:
		for item in Array(preferred_val):
			var board_number := int(item)
			if board_number > 0 and not preferred_boards.has(board_number):
				preferred_boards.append(board_number)
	board_numbers.sort_custom(func(a: int, b: int) -> bool:
		var a_pref := preferred_boards.has(int(a))
		var b_pref := preferred_boards.has(int(b))
		if a_pref != b_pref:
			return a_pref
		return int(a) < int(b)
	)

static func _sorted_products_for_plan_hints(value, observation: ObservationState, options: Dictionary = {}) -> Array[String]:
	var out: Array[String] = []
	if value is Array:
		for item in Array(value):
			var product_id := str(item).strip_edges()
			if not product_id.is_empty() and not out.has(product_id):
				out.append(product_id)
	out.sort_custom(func(a: String, b: String) -> bool:
		var prior_a := _product_pipeline_prior(a, observation, options)
		var prior_b := _product_pipeline_prior(b, observation, options)
		if not is_equal_approx(prior_a, prior_b):
			return prior_a > prior_b
		return a < b
	)
	return out

static func _sorted_train_targets(value, from_employee: String, observation: ObservationState, context: AiDecisionContext, validate_command: Callable, options: Dictionary = {}) -> Array[String]:
	var out: Array[String] = []
	if value is Array:
		for item in Array(value):
			var employee_id := str(item).strip_edges()
			if not employee_id.is_empty() and not out.has(employee_id):
				out.append(employee_id)
	out.sort_custom(func(a: String, b: String) -> bool:
		var prior_a := _train_prior(from_employee, a, observation, context, validate_command, options)
		var prior_b := _train_prior(from_employee, b, observation, context, validate_command, options)
		if not is_equal_approx(prior_a, prior_b):
			return prior_a > prior_b
		return a < b
		)
	return out

static func _sorted_employee_ids_for_plan_hints(employee_ids: Array[String], observation: ObservationState, options: Dictionary = {}, action_id: String = "") -> Array[String]:
	if employee_ids.size() <= 1:
		return employee_ids
	var plan_hints := _plan_hints_dict(options)
	var priorities := {}
	for employee_id in employee_ids:
		var role := _employee_role(employee_id)
		var prior := _plan_hints_employee_bonus(plan_hints, employee_id, role, action_id)
		if action_id == "produce_food":
			prior += _employee_production_hint_bonus(employee_id, observation, options)
		priorities[employee_id] = prior
	var out := employee_ids.duplicate()
	out.sort_custom(func(a: String, b: String) -> bool:
		var prior_a := float(priorities.get(a, 0.0))
		var prior_b := float(priorities.get(b, 0.0))
		if not is_equal_approx(prior_a, prior_b):
			return prior_a > prior_b
		return a < b
	)
	return out

static func _employee_production_hint_bonus(employee_id: String, observation: ObservationState, options: Dictionary = {}) -> float:
	if employee_id.is_empty() or not EmployeeRegistryClass.is_loaded() or not EmployeeRegistryClass.has(employee_id):
		return 0.0
	var def_val = EmployeeRegistryClass.get_def(employee_id)
	if not (def_val is EmployeeDef):
		return 0.0
	var def: EmployeeDef = def_val
	if not def.can_produce():
		return 0.0
	var best := 0.0
	for product_id in def.get_production_food_options():
		best = maxf(best, _product_pipeline_prior(str(product_id), observation, options))
	return best

static func _sort_route_drinks_for_observation(routes: Array, observation: ObservationState, options: Dictionary = {}) -> void:
	routes.sort_custom(func(a, b) -> bool:
		var route_a: Dictionary = a if a is Dictionary else {}
		var route_b: Dictionary = b if b is Dictionary else {}
		var prior_a := _route_drink_prior(route_a, observation, options)
		var prior_b := _route_drink_prior(route_b, observation, options)
		if not is_equal_approx(prior_a, prior_b):
			return prior_a > prior_b
		var source_a := int(route_a.get("source_count", 0))
		var source_b := int(route_b.get("source_count", 0))
		if source_a != source_b:
			return source_a > source_b
		var distance_a := int(route_a.get("distance", 999999))
		var distance_b := int(route_b.get("distance", 999999))
		if distance_a != distance_b:
			return distance_a < distance_b
		var steps_a := int(route_a.get("steps", 999999))
		var steps_b := int(route_b.get("steps", 999999))
		if steps_a != steps_b:
			return steps_a < steps_b
		var rest_a := str(route_a.get("restaurant_id", ""))
		var rest_b := str(route_b.get("restaurant_id", ""))
		if rest_a != rest_b:
			return rest_a < rest_b
		return str(route_a.get("range_type", "")) < str(route_b.get("range_type", ""))
	)

static func _route_drink_prior(route: Dictionary, observation: ObservationState, options: Dictionary = {}) -> float:
	if route.is_empty():
		return 0.0
	var prior := float(maxi(0, int(route.get("source_count", 0)))) * 0.05
	for product_id in _route_drink_source_types(route):
		prior += _product_pipeline_prior(product_id, observation, options)
	return prior

static func _route_drink_source_types(route: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var source_types_val = route.get("source_types", [])
	if source_types_val is Array:
		for product_val in Array(source_types_val):
			var product_id := str(product_val)
			if product_id.is_empty() or out.has(product_id):
				continue
			out.append(product_id)
	var params_val = route.get("params", {})
	if out.is_empty() and params_val is Dictionary:
		var drink_type := str(Dictionary(params_val).get("drink_type", ""))
		if not drink_type.is_empty():
			out.append(drink_type)
	out.sort()
	return out

static func _sort_structure_employee_ids(employee_ids: Array[String], observation: ObservationState, options: Dictionary = {}) -> void:
	employee_ids.sort_custom(func(a: String, b: String) -> bool:
		var priority_a := _structure_assignment_prior(a, observation, null, Callable(), options)
		var priority_b := _structure_assignment_prior(b, observation, null, Callable(), options)
		if not is_equal_approx(priority_a, priority_b):
			return priority_a > priority_b
		return a < b
	)

static func _sorted_marketable_product_ids() -> Array[String]:
	var out: Array[String] = []
	for product_id in ProductRegistryClass.get_all_ids():
		var def_val = ProductRegistryClass.get_def(product_id)
		if not (def_val is ProductDef):
			continue
		var def: ProductDef = def_val
		if def.has_tag("no_marketing"):
			continue
		out.append(str(product_id))
	out.sort()
	return out

static func _sorted_marketable_product_ids_for_observation(observation: ObservationState, plan_hints: Dictionary = {}) -> Array[String]:
	var out := _sorted_marketable_product_ids()
	out.sort_custom(func(a: String, b: String) -> bool:
		var prior_a := _marketing_product_prior(a, observation, plan_hints)
		var prior_b := _marketing_product_prior(b, observation, plan_hints)
		if not is_equal_approx(prior_a, prior_b):
			return prior_a > prior_b
		return a < b
	)
	return out

static func _sort_marketing_products_for_source_state(products: Array[String], observation: ObservationState, source_state: GameState, source_analysis: Dictionary = {}, plan_hints: Dictionary = {}) -> void:
	if products.is_empty() or observation == null or source_state == null:
		return
	var pressure_by_product := {}
	var supply_by_product := {}
	for product_id in products:
		var supply_rank := _marketing_product_supply_rank(product_id, observation)
		supply_by_product[product_id] = supply_rank
		pressure_by_product[product_id] = MarketingPressureAnalyzerClass.product_pressure_prior(source_state, observation, product_id, source_analysis) if supply_rank > 0 else 0
	products.sort_custom(func(a: String, b: String) -> bool:
		var supply_a := int(supply_by_product.get(a, 0))
		var supply_b := int(supply_by_product.get(b, 0))
		if supply_a != supply_b:
			return supply_a > supply_b
		var gap_a := int(pressure_by_product.get(a, 0))
		var gap_b := int(pressure_by_product.get(b, 0))
		if gap_a != gap_b:
			return gap_a > gap_b
		var prior_a := _marketing_product_prior(a, observation, plan_hints)
		var prior_b := _marketing_product_prior(b, observation, plan_hints)
		if not is_equal_approx(prior_a, prior_b):
			return prior_a > prior_b
		return a < b
	)

static func _marketing_types_for_employee(employee_id: String) -> Array[String]:
	var out: Array[String] = []
	if employee_id.is_empty() or not EmployeeRegistryClass.has(employee_id):
		return out
	var def_val = EmployeeRegistryClass.get_def(employee_id)
	if not (def_val is EmployeeDef):
		return out
	var def: EmployeeDef = def_val
	for tag_val in def.usage_tags:
		var tag := str(tag_val)
		if not tag.begins_with("use:marketing:"):
			continue
		var marketing_type := tag.substr("use:marketing:".length()).strip_edges()
		if marketing_type.is_empty() or out.has(marketing_type):
			continue
		out.append(marketing_type)
	out.sort()
	return out

static func _sorted_marketing_board_numbers(marketing_types: Array[String], observation: ObservationState = null) -> Array[int]:
	var out: Array[int] = []
	for board_number in MarketingRegistryClass.get_all_board_numbers():
		var def_val = MarketingRegistryClass.get_def(int(board_number))
		if not (def_val is MarketingDef):
			continue
		var def: MarketingDef = def_val
		if not marketing_types.has(str(def.type)):
			continue
		out.append(int(board_number))
	out.sort()
	return out

static func _available_marketing_board_numbers(marketing_types: Array[String], observation: ObservationState, discarded: Array[String]) -> Array[int]:
	var out: Array[int] = []
	for board_number in _sorted_marketing_board_numbers(marketing_types, observation):
		var board_def = MarketingRegistryClass.get_def(int(board_number))
		if not (board_def is MarketingDef):
			continue
		if not _marketing_board_available_for_observation(board_def as MarketingDef, observation):
			continue
		if _marketing_board_occupied(observation, int(board_number)):
			discarded.append("marketing_board_%d: board already occupied" % int(board_number))
			continue
		out.append(int(board_number))
	return out

static func _marketing_board_candidate_quota(max_valid_per_action: int, board_count: int, options: Dictionary = {}) -> int:
	var budget_val = options.get("budget", null)
	if budget_val is TimeBudget:
		return 1
	if max_valid_per_action <= 0:
		return 1
	if board_count <= 1:
		return max_valid_per_action
	var quota := int(max_valid_per_action / board_count)
	if max_valid_per_action % board_count != 0:
		quota += 1
	return maxi(1, quota)

static func _marketing_board_available_for_observation(board_def: MarketingDef, observation: ObservationState) -> bool:
	if board_def == null:
		return false
	var player_count := 0
	if observation != null:
		player_count = Array(observation.public_players).size()
		if player_count <= 0:
			player_count = Array(observation.turn_order).size()
	if player_count <= 0:
		player_count = 2
	if board_def.has_method("is_available_for_player_count"):
		return bool(board_def.is_available_for_player_count(player_count))
	return true

static func _marketing_board_occupied(observation: ObservationState, board_number: int) -> bool:
	if observation == null or board_number <= 0:
		return false
	for inst_val in observation.marketing_instances_public:
		if not (inst_val is Dictionary):
			continue
		if int(Dictionary(inst_val).get("board_number", -1)) == board_number:
			return true
	var placements_val = observation.map_public.get("marketing_placements", {})
	if placements_val is Dictionary:
		var placements: Dictionary = placements_val
		if placements.has(str(board_number)) or placements.has(board_number):
			return true
	return false

static func _marketing_rotations(marketing_type: String) -> Array[int]:
	if marketing_type == "airplane":
		return [0]
	return [0, 90, 180, 270]

static func _marketing_rotations_for_board(board_def: MarketingDef, marketing_type: String) -> Array[int]:
	if board_def == null:
		return _marketing_rotations(marketing_type)
	if marketing_type == "airplane":
		return [0]
	var out: Array[int] = []
	var seen := {}
	for rotation in _marketing_rotations(marketing_type):
		var size_read := MarketingRulesClass.get_rotated_footprint_size(Vector2i(board_def.footprint_size), int(rotation))
		if not size_read.ok:
			continue
		var size: Vector2i = size_read.value
		var key := "%d,%d" % [size.x, size.y]
		if seen.has(key):
			continue
		seen[key] = true
		out.append(int(rotation))
	return out if not out.is_empty() else _marketing_rotations(marketing_type)

static func _marketing_type_search_priority(marketing_type: String) -> int:
	match marketing_type:
		"billboard":
			return 0
		"mailbox":
			return 1
		"radio":
			return 2
		"airplane":
			return 3
		_:
			return 10

static func _marketing_board_search_priority(marketing_type: String, observation: ObservationState) -> int:
	var priority := _marketing_type_search_priority(marketing_type)
	if observation == null:
		return priority
	var pool := _sorted_unique_strings(observation.milestone_pool_public)
	if marketing_type == "airplane" and pool.has("first_airplane"):
		return priority - 20
	if marketing_type == "radio" and pool.has("first_radio"):
		return priority - 20
	if marketing_type == "billboard" and pool.has("first_billboard"):
		return priority - 20
	return priority

static func _marketing_candidate_positions(observation: ObservationState, grid_size: Vector2i) -> Array[Vector2i]:
	var seen := {}
	var out: Array[Vector2i] = []
	var houses_val = observation.map_public.get("houses", {})
	if houses_val is Dictionary:
		var houses: Dictionary = houses_val
		var house_ids := _sorted_house_ids_by_restaurant_distance(observation, houses)
		for house_id in house_ids:
			var house_val = houses.get(house_id, null)
			if not (house_val is Dictionary):
				continue
			for cell in _house_candidate_cells(house_val):
				for radius in range(1, 4):
					for dy in range(-radius, radius + 1):
						for dx in range(-radius, radius + 1):
							if maxi(absi(dx), absi(dy)) != radius:
								continue
							_append_marketing_position(out, seen, cell + Vector2i(dx, dy), grid_size)
	for y in range(grid_size.y):
		for x in range(grid_size.x):
			_append_marketing_position(out, seen, Vector2i(x, y), grid_size)
	return out

static func _marketing_candidate_positions_for_board_rotation(
	observation: ObservationState,
	grid_size: Vector2i,
	board_def: MarketingDef,
	marketing_type: String,
	rotation: int,
	source_state: GameState = null
) -> Array[Vector2i]:
	if observation == null or board_def == null:
		return []
	var positions: Array[Vector2i] = []
	match marketing_type:
		"billboard":
			positions = _billboard_candidate_positions_for_rotation(observation, grid_size, board_def, rotation)
		"airplane":
			positions = _edge_marketing_positions(grid_size)
		_:
			positions = _marketing_candidate_positions(observation, grid_size)
	if source_state == null or marketing_type == "airplane":
		return positions
	return _filter_marketing_geometry_positions(source_state, positions, grid_size, board_def, marketing_type, rotation)

static func _rank_marketing_candidate_positions(
	observation: ObservationState,
	context: AiDecisionContext,
	positions: Array,
	product_id: String,
	source_state: GameState,
	source_analysis: Dictionary,
	board_def: MarketingDef,
	marketing_type: String,
	rotation: int,
	discarded: Array[String] = [],
	plan_hints: Dictionary = {}
) -> Array:
	if observation == null or context == null or source_state == null or board_def == null or product_id.is_empty() or positions.size() <= 1:
		return positions.duplicate()
	var ranked: Array[Dictionary] = []
	var order := 0
	var viable_count := 0
	for pos_val in positions:
		var pos := _read_vector2i(pos_val)
		var params := {
			"employee_type": "",
			"board_number": int(board_def.board_number),
			"product": product_id,
			"position": [pos.x, pos.y],
			"rotation": int(rotation),
		}
		if marketing_type == "airplane":
			var grid_size := _read_grid_size(observation.map_public)
			params["axis"] = "row" if pos.x == 0 or pos.x == grid_size.x - 1 else "col"
		var command := Command.create("initiate_marketing", context.player_id, params)
		var score := MARKETING_POSITION_LOST_SCORE
		var discard_reason := ""
		var affected_read := _marketing_command_affected_house_ids(source_state, context.player_id, command, board_def, marketing_type)
		if affected_read.ok:
			var affected_ids := _string_array(affected_read.value)
			if not affected_ids.is_empty():
				var service_features := MarketingPressureAnalyzerClass.analyze_candidate(observation, affected_ids, product_id, source_state, source_analysis)
				score = _marketing_position_service_score(service_features)
				score += _plan_hints_house_bonus(plan_hints, affected_ids)
				if score <= MARKETING_POSITION_LOST_SCORE:
					discard_reason = MarketingPressureAnalyzerClass.discard_reason(service_features)
			else:
				discard_reason = "affects no houses"
		elif not affected_read.error.is_empty():
			discard_reason = affected_read.error
		if score <= MARKETING_POSITION_LOST_SCORE and not discard_reason.is_empty():
			discarded.append("marketing_position_%d_%s_%d_%d_%d: %s" % [
				int(board_def.board_number),
				product_id,
				pos.x,
				pos.y,
				int(rotation),
				discard_reason,
			])
		ranked.append({
			"position": pos,
			"score": score,
			"order": order,
		})
		if score > MARKETING_POSITION_LOST_SCORE:
			viable_count += 1
		order += 1
	if viable_count <= 0:
		return []
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var score_a := float(a.get("score", MARKETING_POSITION_LOST_SCORE))
		var score_b := float(b.get("score", MARKETING_POSITION_LOST_SCORE))
		if not is_equal_approx(score_a, score_b):
			return score_a > score_b
		return int(a.get("order", 0)) < int(b.get("order", 0))
	)
	var out: Array = []
	for item in ranked:
		if float(item.get("score", MARKETING_POSITION_LOST_SCORE)) <= MARKETING_POSITION_LOST_SCORE:
			continue
		out.append(item.get("position", Vector2i.ZERO))
	return out

static func _marketing_position_service_score(features: Dictionary) -> float:
	if features.is_empty():
		return MARKETING_POSITION_LOST_SCORE
	var affected := int(features.get("affected_houses", 0))
	if affected <= 0:
		return MARKETING_POSITION_LOST_SCORE
	var strategic := int(features.get("strategic_houses", 0))
	if strategic <= 0:
		return MARKETING_POSITION_LOST_SCORE
	var self_capture := int(features.get("self_capture_houses", features.get("competitive_houses", 0)))
	var opponent_pressure := int(features.get("opponent_pressure_houses", features.get("opponent_capacity_gap_houses", 0)))
	var serviceable := int(features.get("serviceable_houses", 0))
	var competitive := int(features.get("competitive_houses", serviceable))
	var blocked := int(features.get("self_supply_blocked_houses", 0))
	var lost := int(features.get("lost_to_competitor_houses", 0))
	var dominated := int(features.get("restaurant_dominated_houses", 0))
	var closest := int(features.get("closest_distance", -1))
	var value := float(self_capture) * 1400.0
	value += float(opponent_pressure) * 1100.0
	value += float(competitive) * 220.0
	value += float(serviceable) * 40.0
	value += float(affected) * 8.0
	value -= float(blocked) * 900.0
	value -= float(lost) * 760.0
	value -= float(dominated) * 640.0
	if closest >= 0:
		value += maxf(0.0, 80.0 - float(closest) * 4.0)
	return value

static func _filter_marketing_geometry_positions(
	state: GameState,
	positions: Array[Vector2i],
	grid_size: Vector2i,
	board_def: MarketingDef,
	marketing_type: String,
	rotation: int
) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var seen := {}
	for pos in positions:
		var params := {
			"position": [pos.x, pos.y],
			"rotation": int(rotation),
		}
		var precheck_reason := _marketing_geometry_precheck(state, params, board_def, marketing_type)
		if not precheck_reason.is_empty():
			continue
		_append_marketing_position(out, seen, pos, grid_size)
	return out

static func _billboard_candidate_positions_for_rotation(
	observation: ObservationState,
	grid_size: Vector2i,
	board_def: MarketingDef,
	rotation: int
) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var seen := {}
	if grid_size.x <= 0 or grid_size.y <= 0:
		return out
	var size_read := MarketingRulesClass.get_rotated_footprint_size(Vector2i(board_def.footprint_size), rotation)
	if not size_read.ok:
		return out
	var size: Vector2i = size_read.value
	var houses_val = observation.map_public.get("houses", {})
	if not (houses_val is Dictionary):
		return out
	var houses: Dictionary = houses_val
	for house_id in _sorted_house_ids_by_restaurant_distance(observation, houses):
		var house_val = houses.get(house_id, null)
		if not (house_val is Dictionary):
			continue
		for house_cell in _house_candidate_cells(house_val):
			for dy in range(size.y):
				for dx in range(size.x):
					for dir in MapUtilsClass.DIRECTIONS:
						var footprint_cell := MapUtilsClass.get_neighbor_pos(house_cell, dir)
						var anchor := footprint_cell - Vector2i(dx, dy)
						_append_marketing_position(out, seen, anchor, grid_size)
	return out

static func _edge_marketing_positions(grid_size: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var seen := {}
	if grid_size.x <= 0 or grid_size.y <= 0:
		return out
	for y in range(grid_size.y):
		for x in range(grid_size.x):
			if x != 0 and x != grid_size.x - 1 and y != 0 and y != grid_size.y - 1:
				continue
			_append_marketing_position(out, seen, Vector2i(x, y), grid_size)
	return out

static func _restaurant_placement_positions(observation: ObservationState, grid_size: Vector2i) -> Array[Vector2i]:
	var entries: Array[Dictionary] = []
	for y in range(grid_size.y):
		for x in range(grid_size.x):
			var pos := Vector2i(x, y)
			entries.append({
				"pos": pos,
				"prior": _restaurant_position_prior(observation, pos, grid_size),
			})
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var prior_a := float(a.get("prior", 0.0))
		var prior_b := float(b.get("prior", 0.0))
		if not is_equal_approx(prior_a, prior_b):
			return prior_a > prior_b
		var pos_a := Vector2i(a.get("pos", Vector2i.ZERO))
		var pos_b := Vector2i(b.get("pos", Vector2i.ZERO))
		if pos_a.y != pos_b.y:
			return pos_a.y < pos_b.y
		return pos_a.x < pos_b.x
	)
	var out: Array[Vector2i] = []
	for entry in entries:
		out.append(Vector2i(entry.get("pos", Vector2i.ZERO)))
	return out

static func _restaurant_row_major_positions(grid_size: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in range(grid_size.y):
		for x in range(grid_size.x):
			out.append(Vector2i(x, y))
	return out

static func _restaurant_position_rotation_quota(id_prefix: String, use_competition_order: bool) -> int:
	if use_competition_order and id_prefix.begins_with("initial_restaurant"):
		return 1
	if use_competition_order:
		return 2
	return 4

static func _has_competitor_restaurants(observation: ObservationState) -> bool:
	if observation == null:
		return false
	var restaurants_val = observation.map_public.get("restaurants", {})
	if not (restaurants_val is Dictionary):
		return false
	var own_ids := _sorted_unique_strings(observation.own_player.get("restaurants", []))
	var player_id := int(observation.viewer_player_id)
	for restaurant_id_val in Dictionary(restaurants_val).keys():
		var restaurant_id := str(restaurant_id_val)
		if own_ids.has(restaurant_id):
			continue
		var rest_val = Dictionary(restaurants_val).get(restaurant_id_val, null)
		if not (rest_val is Dictionary):
			continue
		var owner := int(Dictionary(rest_val).get("owner", -1))
		if owner >= 0 and owner != player_id:
			return true
	return false

static func _restaurant_position_prior(observation: ObservationState, pos: Vector2i, grid_size: Vector2i) -> float:
	var value := 0.0
	if grid_size.x > 1 and grid_size.y > 1:
		var center := Vector2(float(grid_size.x - 1) * 0.5, float(grid_size.y - 1) * 0.5)
		var center_distance := absf(float(pos.x) - center.x) + absf(float(pos.y) - center.y)
		value -= center_distance * 0.08
	var houses_val = observation.map_public.get("houses", {})
	if not (houses_val is Dictionary):
		return value
	for house_val in Dictionary(houses_val).values():
		if not (house_val is Dictionary):
			continue
		var house_anchor := _read_vector2i(Dictionary(house_val).get("anchor_pos", Vector2i.ZERO))
		var distance := absi(pos.x - house_anchor.x) + absi(pos.y - house_anchor.y)
		var house_base := maxf(0.0, float(8 - distance))
		if house_base <= 0.0:
			continue
		var competitor_distance := _nearest_competitor_restaurant_anchor_distance(observation, house_anchor)
		if competitor_distance >= 0 and competitor_distance < distance:
			value -= house_base * 1.5
			if distance <= 4:
				value -= 2.0
		elif competitor_distance == distance:
			value -= house_base * 0.5
			if distance <= 4:
				value -= 1.0
		else:
			value += house_base
			if distance <= 4:
				value += 2.0
	return value

static func _house_placement_positions(observation: ObservationState, grid_size: Vector2i) -> Array[Vector2i]:
	var seen := {}
	var out: Array[Vector2i] = []
	for anchor in _owned_restaurant_anchors(observation):
		for radius in range(1, maxi(grid_size.x, grid_size.y) + 1):
			for dy in range(-radius, radius + 1):
				for dx in range(-radius, radius + 1):
					if maxi(absi(dx), absi(dy)) != radius:
						continue
					_append_house_placement_position(out, seen, anchor + Vector2i(dx, dy), grid_size)
	var houses_val = observation.map_public.get("houses", {})
	if houses_val is Dictionary:
		var houses: Dictionary = houses_val
		for house_id in _sorted_house_ids_by_restaurant_distance(observation, houses):
			var house_val = houses.get(house_id, null)
			if not (house_val is Dictionary):
				continue
			for cell in _house_candidate_cells(house_val):
				for radius2 in range(1, 5):
					for dy2 in range(-radius2, radius2 + 1):
						for dx2 in range(-radius2, radius2 + 1):
							if maxi(absi(dx2), absi(dy2)) != radius2:
								continue
							_append_house_placement_position(out, seen, cell + Vector2i(dx2, dy2), grid_size)
	for y in range(grid_size.y):
		for x in range(grid_size.x):
			_append_house_placement_position(out, seen, Vector2i(x, y), grid_size)
	return out

static func _append_house_placement_position(out: Array[Vector2i], seen: Dictionary, pos: Vector2i, grid_size: Vector2i) -> void:
	if pos.x < 0 or pos.y < 0 or pos.x >= grid_size.x or pos.y >= grid_size.y:
		return
	var key := "%d,%d" % [pos.x, pos.y]
	if seen.has(key):
		return
	seen[key] = true
	out.append(pos)

static func _house_placement_prior(observation: ObservationState, pos: Vector2i) -> float:
	var value := 0.0
	var restaurant_distance := _position_distance_to_anchors(pos, _owned_restaurant_anchors(observation))
	if restaurant_distance >= 0:
		value += maxf(0.0, 8.0 - float(restaurant_distance)) * 0.7
		if restaurant_distance <= 4:
			value += 1.5
	var houses_val = observation.map_public.get("houses", {})
	if houses_val is Dictionary:
		var house_cells: Array[Vector2i] = []
		for house_val in Dictionary(houses_val).values():
			for cell in _house_candidate_cells(house_val):
				if not house_cells.has(cell):
					house_cells.append(cell)
		var house_distance := _position_distance_to_anchors(pos, house_cells)
		if house_distance >= 0:
			value += maxf(0.0, 6.0 - float(house_distance)) * 0.25
	return value

static func _position_distance_to_anchors(pos: Vector2i, anchors: Array[Vector2i]) -> int:
	if anchors.is_empty():
		return -1
	var best := 2147483647
	for anchor in anchors:
		best = mini(best, absi(pos.x - anchor.x) + absi(pos.y - anchor.y))
	return best if best < 2147483647 else -1

static func _nearest_competitor_restaurant_anchor_distance(observation: ObservationState, pos: Vector2i) -> int:
	if observation == null:
		return -1
	var restaurants_val = observation.map_public.get("restaurants", {})
	if not (restaurants_val is Dictionary):
		return -1
	var own_ids := _sorted_unique_strings(observation.own_player.get("restaurants", []))
	var player_id := int(observation.viewer_player_id)
	var best := 2147483647
	for restaurant_id_val in Dictionary(restaurants_val).keys():
		var restaurant_id := str(restaurant_id_val)
		if own_ids.has(restaurant_id):
			continue
		var rest_val = Dictionary(restaurants_val).get(restaurant_id_val, null)
		if not (rest_val is Dictionary):
			continue
		var rest: Dictionary = rest_val
		var owner := int(rest.get("owner", -1))
		if owner < 0 or owner == player_id:
			continue
		var rest_anchor := _read_vector2i(rest.get("anchor_pos", Vector2i.ZERO))
		best = mini(best, absi(pos.x - rest_anchor.x) + absi(pos.y - rest_anchor.y))
	return best if best < 2147483647 else -1

static func _source_state_from_options(options: Dictionary) -> GameState:
	var state_val = options.get("source_state", null)
	if state_val is GameState:
		return state_val
	var engine_val = options.get("engine", null)
	if engine_val is GameEngine:
		return engine_val.get_state()
	return null

static func _source_board_analysis(source_state: GameState, options: Dictionary = {}) -> Dictionary:
	var cached_val = options.get("source_analysis", null)
	if cached_val is Dictionary and not Dictionary(cached_val).is_empty():
		return Dictionary(cached_val).duplicate(true)
	if source_state == null:
		return {}
	var analysis_read := BoardAnalyzerClass.analyze_state(source_state)
	if not analysis_read.ok or not (analysis_read.value is Dictionary):
		return {}
	return Dictionary(analysis_read.value).duplicate(true)

static func _sorted_house_ids_by_restaurant_distance(observation: ObservationState, houses: Dictionary) -> Array[String]:
	var out := _sorted_string_keys(houses)
	var restaurant_anchors := _owned_restaurant_anchors(observation)
	out.sort_custom(func(a: String, b: String) -> bool:
		var da := _house_distance_to_anchors(Dictionary(houses.get(a, {})), restaurant_anchors)
		var db := _house_distance_to_anchors(Dictionary(houses.get(b, {})), restaurant_anchors)
		if da != db:
			return da < db
		return a < b
	)
	return out

static func _owned_restaurant_anchors(observation: ObservationState) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var restaurants_val = observation.map_public.get("restaurants", {})
	if not (restaurants_val is Dictionary):
		return out
	var restaurants: Dictionary = restaurants_val
	for restaurant_id in _sorted_unique_strings(observation.own_player.get("restaurants", [])):
		var rest_val = restaurants.get(restaurant_id, null)
		if not (rest_val is Dictionary):
			continue
		out.append(_read_vector2i(Dictionary(rest_val).get("anchor_pos", Vector2i.ZERO)))
	return out

static func _house_distance_to_anchors(house: Dictionary, anchors: Array[Vector2i]) -> int:
	if anchors.is_empty():
		return 2147483647
	var cells := _house_candidate_cells(house)
	var best := 2147483647
	for cell in cells:
		for anchor in anchors:
			best = mini(best, absi(cell.x - anchor.x) + absi(cell.y - anchor.y))
	return best

static func _house_candidate_cells(house_val) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if not (house_val is Dictionary):
		return out
	var house: Dictionary = house_val
	var cells_val = house.get("cells", [])
	if cells_val is Array:
		for cell_val in Array(cells_val):
			var cell := _read_vector2i(cell_val)
			if not out.has(cell):
				out.append(cell)
	var anchor := _read_vector2i(house.get("anchor_pos", Vector2i.ZERO))
	if not out.has(anchor):
		out.append(anchor)
	return out

static func _append_marketing_position(out: Array[Vector2i], seen: Dictionary, pos: Vector2i, grid_size: Vector2i) -> void:
	if pos.x < 0 or pos.y < 0 or pos.x >= grid_size.x or pos.y >= grid_size.y:
		return
	var key := "%d,%d" % [pos.x, pos.y]
	if seen.has(key):
		return
	seen[key] = true
	out.append(pos)

static func _restaurant_place_employee_options(observation: ObservationState) -> Array[String]:
	if observation == null or str(observation.phase) != DefsClass.PHASE_WORKING:
		return [""]
	if not EmployeeRegistryClass.is_loaded():
		return [""]
	var out: Array[String] = []
	for employee_id in _sorted_unique_strings(observation.own_player.get("employees", [])):
		if not EmployeeRegistryClass.has(employee_id):
			continue
		var def_val = EmployeeRegistryClass.get_def(employee_id)
		if not (def_val is EmployeeDef):
			continue
		var def: EmployeeDef = def_val
		if def.has_usage_tag("use:place_restaurant"):
			out.append(employee_id)
	if out.is_empty():
		out.append("")
	return out

static func _count_owned_employees(player: Dictionary) -> Dictionary:
	var counts := {}
	for key in ["employees", "reserve_employees"]:
		var list_val = player.get(key, [])
		if not (list_val is Array):
			continue
		for item in Array(list_val):
			var employee_id := str(item)
			if employee_id.is_empty():
				continue
			counts[employee_id] = int(counts.get(employee_id, 0)) + 1
	return counts

static func _recruit_prior(employee_id: String, observation: ObservationState, options: Dictionary = {}) -> float:
	return _recruit_prior_with_route_plan(employee_id, observation, _recruit_route_plan(observation, options))

static func _recruit_prior_with_route_plan(employee_id: String, observation: ObservationState, route_plan: Dictionary) -> float:
	if observation == null or employee_id.is_empty():
		return 0.0
	var owned := _count_owned_employees(observation.own_player)
	var role := _employee_role(employee_id)
	var stable_income_ready := bool(route_plan.get("stable_income_ready", false))
	var price_route_ready := bool(route_plan.get("price_route_ready", false))
	var owns_price := bool(route_plan.get("owns_price", false))
	var waitress_ready := bool(route_plan.get("waitress_support_ready", false))
	var base := 0.0
	match employee_id:
		"kitchen_trainee":
			base = 3.0 if int(owned.get("kitchen_trainee", 0)) <= 0 and not _owns_employee_role(observation.own_player, "produce_food") else 0.25
		"marketing_trainee":
			base = 2.8 if int(owned.get("marketing_trainee", 0)) <= 0 and not _owns_employee_role(observation.own_player, "marketing") else 0.25
		"management_trainee":
			if int(owned.get("new_business_developer", 0)) <= 0 and int(owned.get("management_trainee", 0)) <= 0:
				if bool(route_plan.get("house_growth_ready", false)):
					base = 3.2
				elif bool(route_plan.get("stable_income_ready", false)) and bool(route_plan.get("house_growth_space", false)):
					base = 2.4
				else:
					base = 0.25
			else:
				base = 0.2
		"pricing_manager":
			if price_route_ready and not owns_price and int(owned.get("pricing_manager", 0)) <= 0:
				base = 2.7
			else:
				base = 0.2
		"waitress":
			if stable_income_ready and waitress_ready and int(owned.get("waitress", 0)) <= 0:
				base = 2.4
			else:
				base = 0.2
		"trainer":
			if int(owned.get("trainer", 0)) <= 0 and _has_trainable_owned_employee(observation):
				base = 3.2
			else:
				base = 0.7 if int(owned.get("trainer", 0)) <= 0 else 0.2
		"recruiting_girl":
			if stable_income_ready and int(owned.get("recruiting_girl", 0)) <= 0:
				base = 1.4
			else:
				base = 0.2
		"errand_boy":
			base = 2.2 if not _can_supply_any_drink(observation) else 0.2
		_:
			if role == "price":
				base = 1.5 if price_route_ready and not owns_price else 0.2
			else:
				base = 0.5
	return base + _route_plan_employee_hint_bonus(route_plan, employee_id, role, "recruit")

static func _recruit_route_plan(observation: ObservationState, options: Dictionary = {}) -> Dictionary:
	if observation == null:
		return {}
	var income_analysis := StrategyIncomeAnalyzerClass.analyze(observation, null, _source_state_from_options(options))
	var route_plan := StrategyRoutePlannerClass.analyze(observation, income_analysis, null)
	var plan_hints := _plan_hints_dict(options)
	route_plan["preferred_employee_ids"] = _string_array(plan_hints.get("preferred_employee_ids", []))
	route_plan["preferred_employee_roles"] = _string_array(plan_hints.get("preferred_employee_roles", []))
	route_plan["preferred_actions"] = _string_array(plan_hints.get("preferred_actions", []))
	route_plan["execution_sequence"] = _string_array(plan_hints.get("execution_sequence", []))
	return route_plan

static func _employee_role(employee_id: String) -> String:
	if employee_id.is_empty() or not EmployeeRegistryClass.is_loaded() or not EmployeeRegistryClass.has(employee_id):
		return ""
	var def_val = EmployeeRegistryClass.get_def(employee_id)
	if def_val is EmployeeDef:
		return str((def_val as EmployeeDef).role)
	return ""

static func _structure_assignment_prior(
	employee_id: String,
	observation: ObservationState,
	context: AiDecisionContext = null,
	validate_command: Callable = Callable(),
	options: Dictionary = {}
) -> float:
	if observation == null or employee_id.is_empty():
		return 0.0
	var hint_bonus := _plan_hints_employee_bonus(_plan_hints_dict(options), employee_id, _employee_role(employee_id), "restructure_employee")
	if _is_train_provider_employee(employee_id) and _has_trainable_reserve_employee(observation):
		return 5.0 + hint_bonus
	if _should_preserve_for_training(employee_id, observation, context, validate_command, options):
		return -5.0
	return hint_bonus

static func _submit_restructuring_prior(observation: ObservationState) -> float:
	if _has_active_train_provider(observation) and _has_trainable_reserve_employee(observation):
		return 5.0
	return 0.0

static func _training_reserve_move_prior(
	employee_id: String,
	observation: ObservationState,
	context: AiDecisionContext = null,
	validate_command: Callable = Callable(),
	options: Dictionary = {}
) -> float:
	return 6.5 + _best_train_target_prior(employee_id, observation, context, validate_command, _options_without_plan_hints(options))

static func _train_prior(
	from_employee: String,
	target_employee: String,
	observation: ObservationState,
	context: AiDecisionContext = null,
	validate_command: Callable = Callable(),
	options: Dictionary = {}
) -> float:
	if target_employee.is_empty():
		return 0.0
	var base := 0.0
	match target_employee:
		"new_business_developer":
			base = 3.0
		"burger_cook", "pizza_cook":
			base = 1.0 + _product_pipeline_prior(_food_for_cook(target_employee), observation, options)
		"campaign_manager":
			var unblock_prior := _marketing_training_unblock_prior(from_employee, target_employee, observation, context, validate_command, options)
			if unblock_prior > 0.0:
				base = unblock_prior
			else:
				base = 0.8
		_:
			if not EmployeeRegistryClass.is_loaded() or not EmployeeRegistryClass.has(target_employee):
				base = 0.2 if not from_employee.is_empty() else 0.0
			else:
				var target_def_val = EmployeeRegistryClass.get_def(target_employee)
				if not (target_def_val is EmployeeDef):
					base = 0.2 if not from_employee.is_empty() else 0.0
				else:
					var target_def: EmployeeDef = target_def_val
					base = _generic_train_prior(from_employee, target_employee, target_def, observation, options)
	var plan_hints := _plan_hints_dict(options)
	return base + _plan_hints_employee_bonus(plan_hints, target_employee, _employee_role(target_employee), "train")

static func _generic_train_prior(from_employee: String, target_employee: String, target_def: EmployeeDef, observation: ObservationState, options: Dictionary = {}) -> float:
	if target_def == null:
		return 0.0
	match str(target_def.role):
		"produce_food":
			var production_prior := _best_production_target_prior(target_def, observation, options)
			return 0.9 + production_prior if production_prior >= 0.5 else 0.65
		"procure_drink":
			return 1.0 + _best_drink_pipeline_prior(observation, options) + float(maxi(0, int(target_def.range_value))) * 0.02
		"manager":
			return 1.0 + float(clampi(int(target_def.manager_slots), 0, 10)) * 0.08
		"recruit_train":
			var recruit_train_prior := 0.9
			if int(target_def.recruit_capacity) > 0:
				recruit_train_prior += float(clampi(int(target_def.recruit_capacity), 0, 4)) * 0.18
			if int(target_def.train_capacity) > 0:
				recruit_train_prior += 0.4
			return recruit_train_prior
		"new_shop":
			return 1.1 + float(_total_public_demand(observation)) * 0.08
		"price":
			return 0.95 + float(_total_public_demand(observation)) * 0.06
		"marketing":
			if from_employee == "campaign_manager" and target_employee == "brand_manager":
				return 0.65
			return 0.9 + float(_total_public_demand(observation)) * 0.08
		"special":
			return _special_train_prior(target_def, observation)
	return 0.75 if not from_employee.is_empty() else 0.0

static func _best_production_target_prior(target_def: EmployeeDef, observation: ObservationState, options: Dictionary = {}) -> float:
	if target_def == null:
		return 0.0
	var best := 0.0
	for product_id in target_def.get_production_food_options():
		best = maxf(best, _product_pipeline_prior(str(product_id), observation, options))
	return best

static func _best_drink_pipeline_prior(observation: ObservationState, options: Dictionary = {}) -> float:
	if observation == null or not ProductRegistryClass.is_loaded():
		return 0.0
	var best := 0.0
	for product_id in ProductRegistryClass.get_all_ids():
		if ProductRegistryClass.is_drink(product_id):
			best = maxf(best, _product_pipeline_prior(product_id, observation, options))
	return best

static func _special_train_prior(target_def: EmployeeDef, observation: ObservationState) -> float:
	if target_def == null:
		return 0.0
	if target_def.has_tag("income_50pct"):
		return 0.9 + float(_total_public_demand(observation)) * 0.12
	if target_def.has_tag("place_house_or_garden"):
		return 1.1 + float(_total_public_demand(observation)) * 0.08
	return 0.8

static func _best_train_target_prior(
	from_employee: String,
	observation: ObservationState,
	context: AiDecisionContext = null,
	validate_command: Callable = Callable(),
	options: Dictionary = {}
) -> float:
	if observation == null or from_employee.is_empty() or not EmployeeRegistryClass.is_loaded():
		return 0.0
	if not EmployeeRegistryClass.has(from_employee):
		return 0.0
	var def_val = EmployeeRegistryClass.get_def(from_employee)
	if not (def_val is EmployeeDef):
		return 0.0
	var def: EmployeeDef = def_val
	var best := 0.0
	for target_val in def.train_to:
		var target := str(target_val)
		if target.is_empty() or int(observation.employee_pool_public.get(target, 0)) <= 0:
			continue
		best = maxf(best, _train_prior(from_employee, target, observation, context, validate_command, options))
	return best

static func _marketing_training_unblock_prior(
	from_employee: String,
	target_employee: String,
	observation: ObservationState,
	context: AiDecisionContext,
	validate_command: Callable,
	options: Dictionary
) -> float:
	if from_employee != "marketing_trainee" or target_employee != "campaign_manager":
		return 0.0
	if observation == null or context == null or not validate_command.is_valid():
		return 0.0
	if _source_state_from_options(options) == null:
		return 0.0
	var source_types := _marketing_types_for_employee(from_employee)
	var target_types := _marketing_types_for_employee(target_employee)
	if source_types.is_empty() or target_types.is_empty():
		return 0.0
	var unlocks_marketing_type := false
	for target_type in target_types:
		if not source_types.has(target_type):
			unlocks_marketing_type = true
			break
	if not unlocks_marketing_type:
		return 0.0
	var source_has_effective_candidate := _marketing_employee_has_effective_candidate(from_employee, observation, context, validate_command, options)
	if not source_has_effective_candidate:
		return 2.8
	var mailbox_upgrade_prior := _marketing_mailbox_route_upgrade_prior(source_types, target_types, observation)
	if mailbox_upgrade_prior > 0.0:
		return mailbox_upgrade_prior
	return 0.0

static func _marketing_mailbox_route_upgrade_prior(source_types: Array[String], target_types: Array[String], observation: ObservationState) -> float:
	if observation == null:
		return 0.0
	if source_types.has("mailbox") or not target_types.has("mailbox"):
		return 0.0
	if _sorted_unique_strings(observation.own_player.get("milestones", [])).has("first_billboard"):
		return 0.0
	if _sorted_unique_strings(observation.milestone_pool_public).has("first_billboard"):
		return 0.0
	return 2.65

static func _marketing_employee_has_effective_candidate(
	employee_id: String,
	observation: ObservationState,
	context: AiDecisionContext,
	validate_command: Callable,
	options: Dictionary
) -> bool:
	var cache_key := "%d:%s" % [context.player_id if context != null else -1, employee_id]
	var cache_val = options.get("_marketing_effective_candidate_cache", null)
	if cache_val is Dictionary:
		var cache: Dictionary = cache_val
		if cache.has(cache_key):
			return bool(cache.get(cache_key, true))
	else:
		options["_marketing_effective_candidate_cache"] = {}
	var result := _compute_marketing_employee_has_effective_candidate(employee_id, observation, context, validate_command, options)
	var writable_cache_val = options.get("_marketing_effective_candidate_cache", null)
	if writable_cache_val is Dictionary:
		var writable_cache: Dictionary = writable_cache_val
		writable_cache[cache_key] = result
	return result

static func _compute_marketing_employee_has_effective_candidate(
	employee_id: String,
	observation: ObservationState,
	context: AiDecisionContext,
	validate_command: Callable,
	options: Dictionary
) -> bool:
	if employee_id.is_empty() or observation == null or context == null or not validate_command.is_valid():
		return true
	var source_state := _source_state_from_options(options)
	if source_state == null:
		return true
	if not MarketingRegistryClass.is_loaded() or not ProductRegistryClass.is_loaded():
		return true
	var grid_size := _read_grid_size(observation.map_public)
	if grid_size.x <= 0 or grid_size.y <= 0:
		return true
	var products := _sorted_marketable_product_ids_for_observation(observation, _plan_hints_dict(options))
	if products.is_empty():
		return false
	var product_id := str(products[0])
	var marketing_types := _marketing_types_for_employee(employee_id)
	if marketing_types.is_empty():
		return false
	var positions := _marketing_candidate_positions(observation, grid_size)
	var checked := 0
	for board_number in _sorted_marketing_board_numbers(marketing_types, observation):
		var board_def = MarketingRegistryClass.get_def(int(board_number))
		if not (board_def is MarketingDef):
			continue
		var marketing_def: MarketingDef = board_def
		if not _marketing_board_available_for_observation(marketing_def, observation):
			continue
		if _marketing_board_occupied(observation, int(board_number)):
			continue
		var marketing_type := str(marketing_def.type)
		for pos in positions:
			for rotation in _marketing_rotations(marketing_type):
				checked += 1
				if checked > MARKETING_TRAINING_ROUTE_CHECK_LIMIT:
					return true
				var params := {
					"employee_type": employee_id,
					"board_number": int(board_number),
					"product": product_id,
					"position": [pos.x, pos.y],
					"rotation": int(rotation),
				}
				if marketing_type == "airplane":
					params["axis"] = "row" if pos.x == 0 or pos.x == grid_size.x - 1 else "col"
				var command := Command.create("initiate_marketing", context.player_id, params)
				var validate := _validate_command(command, validate_command)
				if not validate.ok:
					continue
				var affected_read := _marketing_command_affected_house_ids(source_state, context.player_id, command, marketing_def, marketing_type)
				if not affected_read.ok:
					continue
				var affected: Array = affected_read.value
				if not affected.is_empty():
					return true
	return false

static func _marketing_product_prior(product_id: String, observation: ObservationState, plan_hints: Dictionary = {}) -> float:
	if product_id.is_empty() or observation == null:
		return 0.0
	var prior := 0.2
	var inventory_val = observation.own_player.get("inventory", {})
	if inventory_val is Dictionary:
		var inventory: Dictionary = inventory_val
		if _read_non_negative_int(inventory.get(product_id, 0), 0) > 0:
			prior += 0.8
	if _can_actively_supply_product(product_id, observation):
		prior += 0.5
	elif _can_supply_product(product_id, observation):
		prior += 0.35
	prior += float(_public_demand_count_for_product(observation, product_id)) * 0.25
	prior += _plan_hints_product_bonus(plan_hints, product_id)
	return prior

static func _marketing_product_supply_rank(product_id: String, observation: ObservationState) -> int:
	if product_id.is_empty() or observation == null:
		return 0
	var inventory_val = observation.own_player.get("inventory", {})
	if inventory_val is Dictionary and _read_non_negative_int(Dictionary(inventory_val).get(product_id, 0), 0) > 0:
		return 3
	if _can_actively_supply_product(product_id, observation):
		return 2
	if _can_supply_product(product_id, observation):
		return 1
	return 0

static func _product_pipeline_prior(product_id: String, observation: ObservationState, options: Dictionary = {}) -> float:
	if product_id.is_empty() or observation == null:
		return 0.0
	var demand := _public_demand_count_for_product(observation, product_id)
	var prior := float(demand) * 0.6
	var inventory_val = observation.own_player.get("inventory", {})
	if inventory_val is Dictionary:
		var inventory: Dictionary = inventory_val
		var inventory_count := _read_non_negative_int(inventory.get(product_id, 0), 0)
		if demand > 0 and inventory_count < demand:
			prior += 0.5
		elif inventory_count <= 0:
			prior += 0.1
	var plan_hints := _plan_hints_dict(options)
	prior += _plan_hints_product_bonus(plan_hints, product_id)
	return prior

static func _public_demand_count_for_product(observation: ObservationState, product_id: String) -> int:
	if observation == null or product_id.is_empty():
		return 0
	var houses_val = observation.map_public.get("houses", {})
	if not (houses_val is Dictionary):
		return 0
	var count := 0
	var houses: Dictionary = houses_val
	for house_val in houses.values():
		if not (house_val is Dictionary):
			continue
		var house: Dictionary = house_val
		var demands_val = house.get("demands", [])
		if not (demands_val is Array):
			continue
		for demand_val in Array(demands_val):
			if demand_val is Dictionary and str(Dictionary(demand_val).get("product", "")) == product_id:
				count += 1
	return count

static func _total_public_demand(observation: ObservationState) -> int:
	if observation == null:
		return 0
	var houses_val = observation.map_public.get("houses", {})
	if not (houses_val is Dictionary):
		return 0
	var count := 0
	for house_val in Dictionary(houses_val).values():
		if not (house_val is Dictionary):
			continue
		var demands_val = Dictionary(house_val).get("demands", [])
		if demands_val is Array:
			count += Array(demands_val).size()
	return count

static func _has_trainable_reserve_employee(observation: ObservationState) -> bool:
	if observation == null or not EmployeeRegistryClass.is_loaded():
		return false
	var reserve_val = observation.own_player.get("reserve_employees", [])
	if not (reserve_val is Array):
		return false
	for employee_val in Array(reserve_val):
		var employee_id := str(employee_val)
		if _best_train_target_prior(employee_id, observation) >= TRAIN_ACTION_MIN_PRIOR:
			return true
	return false

static func _has_trainable_owned_employee(observation: ObservationState) -> bool:
	if observation == null:
		return false
	for key in ["employees", "reserve_employees"]:
		var employees_val = observation.own_player.get(key, [])
		if not (employees_val is Array):
			continue
		for employee_val in Array(employees_val):
			if _best_train_target_prior(str(employee_val), observation) >= TRAIN_ACTION_MIN_PRIOR:
				return true
	return false

static func _is_trainable_source_employee(employee_id: String, observation: ObservationState) -> bool:
	if observation == null or employee_id.is_empty() or not EmployeeRegistryClass.is_loaded():
		return false
	if not EmployeeRegistryClass.has(employee_id):
		return false
	var def_val = EmployeeRegistryClass.get_def(employee_id)
	if not (def_val is EmployeeDef):
		return false
	var def: EmployeeDef = def_val
	for target_val in def.train_to:
		var target := str(target_val)
		if not target.is_empty() and int(observation.employee_pool_public.get(target, 0)) > 0:
			return true
	return false

static func _should_preserve_for_training(
	employee_id: String,
	observation: ObservationState,
	context: AiDecisionContext = null,
	validate_command: Callable = Callable(),
	options: Dictionary = {}
) -> bool:
	if employee_id.is_empty() or employee_id == "ceo":
		return false
	if _is_train_provider_employee(employee_id):
		return false
	if not _has_owned_train_provider(observation):
		return false
	if _should_activate_for_supply(employee_id, observation):
		return false
	return _best_train_target_prior(employee_id, observation, context, validate_command, _options_without_plan_hints(options)) >= TRAINING_PRESERVE_MIN_PRIOR

static func _should_activate_for_supply(employee_id: String, observation: ObservationState) -> bool:
	if observation == null or employee_id.is_empty() or not EmployeeRegistryClass.is_loaded() or not EmployeeRegistryClass.has(employee_id):
		return false
	var def_val = EmployeeRegistryClass.get_def(employee_id)
	if not (def_val is EmployeeDef):
		return false
	var def: EmployeeDef = def_val
	if def.can_procure():
		return _should_activate_for_drink_supply(employee_id, observation)
	if not def.can_produce():
		return false
	var active := _sorted_unique_strings(observation.own_player.get("employees", [])).has(employee_id)
	for product_val in def.get_production_food_options():
		var product_id := str(product_val)
		if product_id.is_empty():
			continue
		if _product_inventory_gap(product_id, observation) > 0:
			return true
		if _marketing_pipeline_needs_food_supply(product_id, observation):
			if active or not _can_actively_supply_product(product_id, observation):
				return true
	return false

static func _should_activate_for_drink_supply(employee_id: String, observation: ObservationState) -> bool:
	if observation == null or employee_id.is_empty() or not ProductRegistryClass.is_loaded():
		return false
	if employee_id == "errand_boy":
		for product_id in ProductRegistryClass.get_all_ids():
			if ProductRegistryClass.is_drink(product_id) and _product_inventory_gap(product_id, observation) > 0:
				return true
		return false
	var routes_read := DrinkRouteAnalyzerClass.generate_routes(observation, employee_id, 6)
	if not routes_read.ok:
		return false
	for route_val in Array(routes_read.value):
		if not (route_val is Dictionary):
			continue
		for product_id in _route_drink_source_types(Dictionary(route_val)):
			if ProductRegistryClass.has(product_id) and ProductRegistryClass.is_drink(product_id) and _product_inventory_gap(product_id, observation) > 0:
				return true
	return false

static func _product_inventory_gap(product_id: String, observation: ObservationState) -> int:
	if observation == null or product_id.is_empty():
		return 0
	var demand := _public_demand_count_for_product(observation, product_id)
	var inventory_val = observation.own_player.get("inventory", {})
	var inventory := 0
	if inventory_val is Dictionary:
		inventory = _read_non_negative_int(Dictionary(inventory_val).get(product_id, 0), 0)
	return maxi(0, demand - inventory)

static func _marketing_pipeline_needs_food_supply(product_id: String, observation: ObservationState) -> bool:
	if observation == null or product_id.is_empty():
		return false
	if not _owns_employee_role(observation.own_player, "marketing"):
		return false
	if _sorted_unique_strings(observation.own_player.get("restaurants", [])).is_empty():
		return false
	if not _is_marketable_product(product_id):
		return false
	var inventory_val = observation.own_player.get("inventory", {})
	if inventory_val is Dictionary and _read_non_negative_int(Dictionary(inventory_val).get(product_id, 0), 0) > 0:
		return false
	return true

static func _has_owned_train_provider(observation: ObservationState) -> bool:
	if observation == null:
		return false
	for employee_id in _owned_employee_ids(observation.own_player):
		if _is_train_provider_employee(employee_id):
			return true
	return false

static func _has_active_train_provider(observation: ObservationState) -> bool:
	if observation == null:
		return false
	for employee_id in _sorted_unique_strings(observation.own_player.get("employees", [])):
		if _is_train_provider_employee(employee_id):
			return true
	return false

static func _is_train_provider_employee(employee_id: String) -> bool:
	if employee_id.is_empty() or not EmployeeRegistryClass.is_loaded() or not EmployeeRegistryClass.has(employee_id):
		return false
	var def_val = EmployeeRegistryClass.get_def(employee_id)
	if not (def_val is EmployeeDef):
		return false
	var def: EmployeeDef = def_val
	return int(def.train_capacity) > 0 and def.has_usage_tag("use:train")

static func _can_supply_any_drink(observation: ObservationState) -> bool:
	if observation == null or not ProductRegistryClass.is_loaded():
		return false
	for product_id in ProductRegistryClass.get_all_ids():
		if ProductRegistryClass.is_drink(product_id) and _can_supply_product(product_id, observation):
			return true
	return false

static func _can_supply_product(product_id: String, observation: ObservationState) -> bool:
	if observation == null or product_id.is_empty():
		return false
	var inventory_val = observation.own_player.get("inventory", {})
	if inventory_val is Dictionary and _read_non_negative_int(Dictionary(inventory_val).get(product_id, 0), 0) > 0:
		return true
	if not EmployeeRegistryClass.is_loaded() or not ProductRegistryClass.is_loaded():
		return false
	for employee_id in _owned_employee_ids(observation.own_player):
		if not EmployeeRegistryClass.has(employee_id):
			continue
		var def_val = EmployeeRegistryClass.get_def(employee_id)
		if not (def_val is EmployeeDef):
			continue
		var def: EmployeeDef = def_val
		if def.can_produce() and def.get_production_food_options().has(product_id):
			return true
		if def.can_procure() and ProductRegistryClass.is_drink(product_id):
			return true
		if employee_id == "errand_boy" and ProductRegistryClass.is_drink(product_id):
			return true
	return false

static func _can_actively_supply_product(product_id: String, observation: ObservationState) -> bool:
	if observation == null or product_id.is_empty():
		return false
	if not EmployeeRegistryClass.is_loaded() or not ProductRegistryClass.is_loaded():
		return false
	for employee_id in _sorted_unique_strings(observation.own_player.get("employees", [])):
		if not EmployeeRegistryClass.has(employee_id):
			continue
		var def_val = EmployeeRegistryClass.get_def(employee_id)
		if not (def_val is EmployeeDef):
			continue
		var def: EmployeeDef = def_val
		if def.can_produce() and def.get_production_food_options().has(product_id):
			return true
		if ProductRegistryClass.is_drink(product_id) and (def.can_procure() or employee_id == "errand_boy"):
			return true
	return false

static func _owns_employee_role(player: Dictionary, role: String) -> bool:
	if role.is_empty() or not EmployeeRegistryClass.is_loaded():
		return false
	for employee_id in _owned_employee_ids(player):
		if not EmployeeRegistryClass.has(employee_id):
			continue
		var def_val = EmployeeRegistryClass.get_def(employee_id)
		if def_val is EmployeeDef and str((def_val as EmployeeDef).role) == role:
			return true
	return false

static func _owned_employee_ids(player: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var seen := {}
	for key in ["employees", "reserve_employees", "busy_marketers"]:
		var list_val = player.get(key, [])
		if not (list_val is Array):
			continue
		for item in Array(list_val):
			var employee_id := str(item)
			if employee_id.is_empty() or seen.has(employee_id):
				continue
			seen[employee_id] = true
			out.append(employee_id)
	out.sort()
	return out

static func _food_for_cook(employee_id: String) -> String:
	if employee_id.find("burger") >= 0:
		return "burger"
	if employee_id.find("pizza") >= 0:
		return "pizza"
	return ""

static func _count_employees_in_list(value) -> Dictionary:
	var counts := {}
	if not (value is Array):
		return counts
	for item in Array(value):
		var employee_id := str(item)
		if employee_id.is_empty():
			continue
		counts[employee_id] = int(counts.get(employee_id, 0)) + 1
	return counts

static func _count_assigned_employees(structure: Array) -> Dictionary:
	var counts := {}
	for entry_val in structure:
		if not (entry_val is Dictionary):
			continue
		var entry: Dictionary = entry_val
		var direct := str(entry.get("employee_id", ""))
		if not direct.is_empty():
			counts[direct] = int(counts.get(direct, 0)) + 1
		var reports_val = entry.get("reports", [])
		if not (reports_val is Array):
			continue
		for report_val in Array(reports_val):
			var report_id := str(report_val)
			if report_id.is_empty():
				continue
			counts[report_id] = int(counts.get(report_id, 0)) + 1
	return counts

static func _valid_report_count(entry: Dictionary, active_counts: Dictionary) -> int:
	var reports_val = entry.get("reports", [])
	if not (reports_val is Array):
		return 0
	var count := 0
	for report_val in Array(reports_val):
		var report_id := str(report_val)
		if report_id.is_empty() or report_id == "ceo":
			continue
		if int(active_counts.get(report_id, 0)) <= 0:
			continue
		if _is_manager_employee(report_id):
			continue
		count += 1
	return count

static func _is_manager_employee(employee_id: String) -> bool:
	if employee_id.is_empty() or not EmployeeRegistryClass.is_loaded() or not EmployeeRegistryClass.has(employee_id):
		return false
	var def_val = EmployeeRegistryClass.get_def(employee_id)
	if not (def_val is EmployeeDef):
		return false
	var def: EmployeeDef = def_val
	return str(def.role) == "manager" or maxi(0, int(def.manager_slots)) > 0

static func _can_employee_be_fired(employee_id: String) -> bool:
	if employee_id.is_empty() or not EmployeeRegistryClass.is_loaded() or not EmployeeRegistryClass.has(employee_id):
		return false
	var def_val = EmployeeRegistryClass.get_def(employee_id)
	if not (def_val is EmployeeDef):
		return false
	var def: EmployeeDef = def_val
	return bool(def.can_be_fired)

static func _build_fridge_keep(observation: ObservationState) -> Dictionary:
	if observation == null:
		return {}
	var inventory_val = observation.own_player.get("inventory", {})
	if not (inventory_val is Dictionary):
		return {}
	var inventory: Dictionary = inventory_val
	var milestones_val = observation.own_player.get("milestones", [])
	if not (milestones_val is Array):
		return {}
	var fridge := _get_fridge_capacity_from_milestones(Array(milestones_val))
	if not bool(fridge.get("has_fridge", false)):
		return {}
	var remaining := maxi(0, int(fridge.get("capacity", 0)))
	if remaining <= 0:
		return {}
	var strategy_keep := StrategyIncomeAnalyzerClass.build_fridge_keep(observation, remaining)
	if not strategy_keep.is_empty():
		return strategy_keep
	var product_ids: Array[String] = []
	for product_key in inventory.keys():
		var product_id := str(product_key)
		if product_id.is_empty() or not _is_storable_food_or_drink(product_id):
			continue
		if _read_non_negative_int(inventory.get(product_key, 0), 0) <= 0:
			continue
		product_ids.append(product_id)
	product_ids.sort_custom(func(a: String, b: String) -> bool:
		var amount_a := _read_non_negative_int(inventory.get(a, 0), 0)
		var amount_b := _read_non_negative_int(inventory.get(b, 0), 0)
		if amount_a != amount_b:
			return amount_a > amount_b
		return a < b
	)
	var keep := {}
	for product_id in product_ids:
		if remaining <= 0:
			break
		var available := _read_non_negative_int(inventory.get(product_id, 0), 0)
		var amount := mini(available, remaining)
		if amount <= 0:
			continue
		keep[product_id] = amount
		remaining -= amount
	return keep

static func _get_fridge_capacity_from_milestones(milestones: Array) -> Dictionary:
	return StrategyIncomeAnalyzerClass.fridge_capacity_from_milestones(milestones, "CandidateGenerator: ", "own_player.milestones")

static func _is_storable_food_or_drink(product_id: String) -> bool:
	if product_id.is_empty() or not ProductRegistryClass.is_loaded():
		return false
	var def_val = ProductRegistryClass.get_def(product_id)
	if def_val == null or not (def_val is ProductDef):
		return false
	var def: ProductDef = def_val
	if def.has_tag("no_storage"):
		return false
	return def.has_tag("food") or def.has_tag("drink")

static func _is_marketable_product(product_id: String) -> bool:
	if product_id.is_empty():
		return false
	if not ProductRegistryClass.is_loaded() or not ProductRegistryClass.has(product_id):
		return true
	var def_val = ProductRegistryClass.get_def(product_id)
	if def_val == null or not (def_val is ProductDef):
		return true
	var def: ProductDef = def_val
	return not def.has_tag("no_marketing")

static func _has_estimated_payday_salary_shortfall(observation: ObservationState) -> bool:
	if observation == null:
		return false
	var player := observation.own_player
	var paid_count := EmployeeRulesClass.count_paid_employees(player)
	if paid_count <= 0:
		return false
	var salary_cost := _read_non_negative_int(player.get("salary_cost_override", observation.rules_public.get("salary_cost", 5)), 5)
	var due := maxi(0, paid_count * salary_cost + _salary_total_delta(player))
	var cash := _read_non_negative_int(player.get("cash", 0), 0)
	return cash < due

static func _salary_total_delta(player: Dictionary) -> int:
	var milestones_val = player.get("milestones", [])
	if not (milestones_val is Array):
		return 0
	var milestones: Array = milestones_val
	var delta_read := MilestoneEffectQueriesClass.sum_int_values(
		milestones,
		"salary_total_delta",
		"CandidateGenerator: ",
		"own_player.milestones"
	)
	if not delta_read.ok:
		return 0
	return int(delta_read.value)

static func _read_non_negative_int(value, fallback: int) -> int:
	if value is int:
		return maxi(0, int(value))
	if value is float:
		var f: float = float(value)
		if f == floor(f):
			return maxi(0, int(f))
	return maxi(0, int(fallback))

static func _empty_direct_slots(structure: Array, ceo_slots: int) -> Array[int]:
	var out: Array[int] = []
	for i in range(maxi(0, ceo_slots)):
		var employee_id := ""
		if i < structure.size() and structure[i] is Dictionary:
			employee_id = str(Dictionary(structure[i]).get("employee_id", ""))
		if employee_id.is_empty():
			out.append(i)
	return out

static func _read_grid_size(map_public: Dictionary) -> Vector2i:
	var value = map_public.get("grid_size", Vector2i.ZERO)
	return _read_vector2i(value)

static func _read_vector2i(value) -> Vector2i:
	if value is Vector2i:
		return value
	if value is Vector2:
		return Vector2i(int(value.x), int(value.y))
	if value is Dictionary:
		var dict: Dictionary = value
		return Vector2i(int(dict.get("x", 0)), int(dict.get("y", 0)))
	if value is Array:
		var arr: Array = value
		if arr.size() >= 2:
			return Vector2i(int(arr[0]), int(arr[1]))
	return Vector2i.ZERO

static func _budget_expired(options: Dictionary) -> bool:
	var budget_val = options.get("budget", null)
	if budget_val is TimeBudget:
		return (budget_val as TimeBudget).expired()
	return false

static func _sorted_owned_restaurant_ids(player: Dictionary, restaurants: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var ids_val = player.get("restaurants", [])
	if not (ids_val is Array):
		return out
	for id_val in Array(ids_val):
		var restaurant_id := str(id_val)
		if restaurant_id.is_empty() or not restaurants.has(restaurant_id):
			continue
		out.append(restaurant_id)
	out.sort()
	return out

static func _read_remaining_house_numbers(map_public: Dictionary) -> Array[int]:
	var value = map_public.get("house_number_supply_remaining", [])
	var out: Array[int] = []
	if value is Array:
		for item in Array(value):
			if item is int:
				out.append(int(item))
			elif item is float:
				var f: float = float(item)
				if f == floor(f):
					out.append(int(f))
	out.sort()
	var dedup: Array[int] = []
	for n in out:
		if dedup.has(int(n)):
			continue
		dedup.append(int(n))
	return dedup

static func _has_pending_player_action(
	observation: ObservationState,
	phase_name: String,
	player_id: int,
	action_id: String
) -> bool:
	var ppa_val = observation.round_state_public.get("pending_phase_actions", null)
	if not (ppa_val is Dictionary):
		return false
	var pending_val = Dictionary(ppa_val).get(phase_name, null)
	if not (pending_val is Array):
		return false
	for item in Array(pending_val):
		if not (item is Dictionary):
			continue
		var dict: Dictionary = item
		if str(dict.get("kind", "")) == action_id and int(dict.get("player_id", -1)) == player_id:
			return true
	return false
