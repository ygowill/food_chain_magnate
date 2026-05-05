class_name CandidateGenerator
extends RefCounted

const MacroActionClass = preload("res://core/ai/candidates/macro_action.gd")
const ActionIdsClass = preload("res://core/actions/action_ids.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const DrinkRouteAnalyzerClass = preload("res://core/ai/analysis/drink_route_analyzer.gd")
const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")
const MarketingRegistryClass = preload("res://core/data/marketing_registry.gd")
const ProductRegistryClass = preload("res://core/data/product_registry.gd")

const DEFAULT_MAX_VALID_PER_ACTION := 12
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
			_generate_setup(out, discarded, observation, context, legal_action_ids, validate_command, max_valid_per_action)
		DefsClass.PHASE_RESTRUCTURING:
			_generate_restructuring(out, discarded, observation, context, legal_action_ids, validate_command, max_valid_per_action)
		DefsClass.PHASE_ORDER_OF_BUSINESS:
			_generate_order_of_business(out, discarded, observation, context, legal_action_ids, validate_command, max_valid_per_action)
		DefsClass.PHASE_WORKING:
			_generate_working(out, discarded, observation, context, legal_action_ids, validate_command, max_valid_per_action)
		DefsClass.PHASE_PAYDAY:
			_generate_payday(out, discarded, observation, context, legal_action_ids, validate_command, max_valid_per_action)
		DefsClass.PHASE_CLEANUP:
			_generate_cleanup(out, discarded, context, legal_action_ids, validate_command, max_valid_per_action)
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
	max_valid_per_action: int
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
	for y in range(grid_size.y):
		for x in range(grid_size.x):
			for rotation in rotations:
				if _count_action(out, "place_restaurant") >= max_valid_per_action:
					return
				_append_valid_command(
					out,
					discarded,
					context,
					"place_restaurant",
					{
						"position": [x, y],
						"rotation": int(rotation),
					},
					validate_command,
					"%s_%d_%d_%d" % [id_prefix, x, y, int(rotation)],
					["setup", "restaurant"],
					0.0,
					max_valid_per_action
				)

static func _generate_restructuring(
	out: Array[MacroAction],
	discarded: Array[String],
	observation: ObservationState,
	context: AiDecisionContext,
	legal_action_ids: Array[String],
	validate_command: Callable,
	max_valid_per_action: int
) -> void:
	if legal_action_ids.has("set_company_structure_direct"):
		_generate_direct_structure_assignments(out, discarded, observation, context, validate_command, max_valid_per_action)
	if legal_action_ids.has("set_company_structure_report"):
		_generate_report_structure_assignments(out, discarded, observation, context, validate_command, max_valid_per_action)
	if legal_action_ids.has("submit_restructuring"):
		_append_valid_command(out, discarded, context, "submit_restructuring", {}, validate_command, "submit_restructuring", ["restructuring"], 0.0, max_valid_per_action)

static func _generate_direct_structure_assignments(
	out: Array[MacroAction],
	discarded: Array[String],
	observation: ObservationState,
	context: AiDecisionContext,
	validate_command: Callable,
	max_valid_per_action: int
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
	var empty_slots := _empty_direct_slots(structure, ceo_slots)
	for employee_id in employee_ids:
		if employee_id == "ceo":
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
				0.0,
				max_valid_per_action
			)

static func _generate_report_structure_assignments(
	out: Array[MacroAction],
	discarded: Array[String],
	observation: ObservationState,
	context: AiDecisionContext,
	validate_command: Callable,
	max_valid_per_action: int
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
				0.0,
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
	max_valid_per_action: int
) -> void:
	_generate_working_mandatory_actions(out, discarded, context, legal_action_ids, validate_command, max_valid_per_action)
	match str(observation.sub_phase):
		DefsClass.SUB_PHASE_RECRUIT:
			if legal_action_ids.has("recruit"):
				_generate_recruit(out, discarded, observation, context, validate_command, max_valid_per_action)
		DefsClass.SUB_PHASE_TRAIN:
			if legal_action_ids.has("train"):
				_generate_train(out, discarded, observation, context, validate_command, max_valid_per_action)
		DefsClass.SUB_PHASE_MARKETING:
			if legal_action_ids.has("initiate_marketing"):
				_generate_marketing(out, discarded, observation, context, validate_command, max_valid_per_action)
		DefsClass.SUB_PHASE_GET_FOOD:
			if legal_action_ids.has("produce_food"):
				_generate_produce_food(out, discarded, observation, context, validate_command, max_valid_per_action)
		DefsClass.SUB_PHASE_GET_DRINKS:
			if legal_action_ids.has("procure_drinks"):
				_generate_errand_boy_drinks(out, discarded, observation, context, validate_command, max_valid_per_action)
				_generate_route_drinks(out, discarded, observation, context, validate_command, max_valid_per_action)
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
	max_valid_per_action: int
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
	var products := _sorted_marketable_product_ids()
	if products.is_empty():
		discarded.append("marketing: no marketable products")
		return
	var grid_size := _read_grid_size(observation.map_public)
	if grid_size.x <= 0 or grid_size.y <= 0:
		discarded.append("marketing: invalid grid_size %s" % str(grid_size))
		return
	for employee_id in _sorted_unique_strings(observation.own_player.get("employees", [])):
		var marketing_types := _marketing_types_for_employee(employee_id)
		if marketing_types.is_empty():
			continue
		var board_numbers := _sorted_marketing_board_numbers(marketing_types)
		for board_number in board_numbers:
			var board_def = MarketingRegistryClass.get_def(int(board_number))
			if not (board_def is MarketingDef):
				continue
			var marketing_type := str((board_def as MarketingDef).type)
			for product_id in products:
				for y in range(grid_size.y):
					for x in range(grid_size.x):
						for rotation in _marketing_rotations(marketing_type):
							if _count_action(out, "initiate_marketing") >= max_valid_per_action:
								return
							var params := {
								"employee_type": employee_id,
								"board_number": int(board_number),
								"product": product_id,
								"position": [x, y],
								"rotation": int(rotation),
							}
							if marketing_type == "airplane":
								params["axis"] = "row" if x == 0 or x == grid_size.x - 1 else "col"
							_append_valid_command(
								out,
								discarded,
								context,
								"initiate_marketing",
								params,
								validate_command,
								"marketing_%s_%d_%s_%d_%d_%d" % [employee_id, int(board_number), product_id, x, y, int(rotation)],
								["working", "marketing"],
								0.0,
								max_valid_per_action
							)

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
	for y in range(grid_size.y):
		for x in range(grid_size.x):
			for rotation in rotations:
				if _count_action(out, "place_house") >= max_valid_per_action:
					return
				_append_valid_command(
					out,
					discarded,
					context,
					"place_house",
					{
						"position": [x, y],
						"rotation": int(rotation),
						"house_number": house_number,
					},
					validate_command,
					"place_house_%d_%d_%d_%d" % [house_number, x, y, int(rotation)],
					["working", "place_house"],
					0.0,
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
	for restaurant_id in restaurant_ids:
		var rest: Dictionary = restaurants.get(restaurant_id, {})
		var current_anchor := _read_vector2i(rest.get("anchor_pos", Vector2i(-9999, -9999)))
		for y in range(grid_size.y):
			for x in range(grid_size.x):
				if Vector2i(x, y) == current_anchor:
					continue
				for rotation in rotations:
					if _count_action(out, "move_restaurant") >= max_valid_per_action:
						return
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

static func _generate_recruit(
	out: Array[MacroAction],
	discarded: Array[String],
	observation: ObservationState,
	context: AiDecisionContext,
	validate_command: Callable,
	max_valid_per_action: int
) -> void:
	for employee_id in _sorted_positive_pool_ids(observation.employee_pool_public):
		_append_valid_command(
			out,
			discarded,
			context,
			"recruit",
			{"employee_type": employee_id},
			validate_command,
			"recruit_%s" % employee_id,
			["working", "recruit"],
			0.0,
			max_valid_per_action
		)

static func _generate_train(
	out: Array[MacroAction],
	discarded: Array[String],
	observation: ObservationState,
	context: AiDecisionContext,
	validate_command: Callable,
	max_valid_per_action: int
) -> void:
	if not EmployeeRegistryClass.is_loaded():
		discarded.append("train: EmployeeRegistry is not loaded")
		return
	for from_employee in _sorted_unique_strings(observation.own_player.get("reserve_employees", [])):
		var def_val = EmployeeRegistryClass.get_def(from_employee)
		if not (def_val is EmployeeDef):
			continue
		var def: EmployeeDef = def_val
		for to_employee in def.train_to:
			var target := str(to_employee)
			if target.is_empty():
				continue
			if int(observation.employee_pool_public.get(target, 0)) <= 0:
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
				0.0,
				max_valid_per_action
			)

static func _generate_produce_food(
	out: Array[MacroAction],
	discarded: Array[String],
	observation: ObservationState,
	context: AiDecisionContext,
	validate_command: Callable,
	max_valid_per_action: int
) -> void:
	if not EmployeeRegistryClass.is_loaded():
		discarded.append("produce_food: EmployeeRegistry is not loaded")
		return
	for employee_id in _sorted_unique_strings(observation.own_player.get("employees", [])):
		var def_val = EmployeeRegistryClass.get_def(employee_id)
		if not (def_val is EmployeeDef):
			continue
		var def: EmployeeDef = def_val
		if not def.can_produce():
			continue
		var options := def.get_production_food_options()
		for food_type in options:
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
				0.0,
				max_valid_per_action
			)

static func _generate_errand_boy_drinks(
	out: Array[MacroAction],
	discarded: Array[String],
	observation: ObservationState,
	context: AiDecisionContext,
	validate_command: Callable,
	max_valid_per_action: int
) -> void:
	var active := _sorted_unique_strings(observation.own_player.get("employees", []))
	if not active.has("errand_boy"):
		return
	if not ProductRegistryClass.is_loaded():
		discarded.append("procure_drinks: ProductRegistry is not loaded")
		return
	for product_id in ProductRegistryClass.get_all_ids():
		if not ProductRegistryClass.is_drink(product_id):
			continue
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
			0.0,
			max_valid_per_action
		)

static func _generate_route_drinks(
	out: Array[MacroAction],
	discarded: Array[String],
	observation: ObservationState,
	context: AiDecisionContext,
	validate_command: Callable,
	max_valid_per_action: int
) -> void:
	if not EmployeeRegistryClass.is_loaded():
		discarded.append("procure_drinks: EmployeeRegistry is not loaded")
		return
	var active := _sorted_unique_strings(observation.own_player.get("employees", []))
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
		var routes_read := DrinkRouteAnalyzerClass.generate_routes(observation, employee_id, max_valid_per_action)
		if not routes_read.ok:
			discarded.append("procure_drinks:%s: %s" % [employee_id, routes_read.error])
			continue
		var routes: Array = routes_read.value
		if routes.is_empty():
			discarded.append("procure_drinks:%s: no route candidates" % employee_id)
			continue
		for route_val in routes:
			if _count_action(out, "procure_drinks") >= max_valid_per_action:
				return
			if not (route_val is Dictionary):
				continue
			var route: Dictionary = route_val
			var params_val = route.get("params", null)
			if not (params_val is Dictionary):
				continue
			var range_type := str(route.get("range_type", "route"))
			var source_count := int(route.get("source_count", 0))
			var route_index := _count_action(out, "procure_drinks")
			_append_valid_command(
				out,
				discarded,
				context,
				"procure_drinks",
				Dictionary(params_val).duplicate(true),
				validate_command,
				"procure_%s_%s_%d_%d" % [employee_id, range_type, source_count, route_index],
				["working", "procure_drinks", range_type],
				float(source_count) * 0.05,
				max_valid_per_action
			)

static func _generate_cleanup(
	out: Array[MacroAction],
	discarded: Array[String],
	context: AiDecisionContext,
	legal_action_ids: Array[String],
	validate_command: Callable,
	max_valid_per_action: int
) -> void:
	if legal_action_ids.has("choose_fridge_keep"):
		_append_valid_command(out, discarded, context, "choose_fridge_keep", {"keep": {}}, validate_command, "fridge_keep_none", ["cleanup"], 0.0, max_valid_per_action)
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

static func _validate_command(command: Command, validate_command: Callable) -> Result:
	if not validate_command.is_valid():
		return Result.success()
	var validated = validate_command.call(command)
	if validated is Result:
		return validated
	return Result.failure("validator returned non-Result")

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

static func _sorted_marketing_board_numbers(marketing_types: Array[String]) -> Array[int]:
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

static func _marketing_rotations(marketing_type: String) -> Array[int]:
	if marketing_type == "airplane":
		return [0]
	return [0, 90, 180, 270]

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
