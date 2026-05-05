class_name RandomLegalBot
extends "res://core/ai/bot/fcm_bot.gd"

const BasicCandidateHelpersClass = preload("res://core/ai/candidates/basic_candidate_helpers.gd")
const ActionIdsClass = preload("res://core/actions/action_ids.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const EmployeeRulesClass = preload("res://core/rules/employee_rules.gd")

const WORKING_MANDATORY_ACTION_IDS := [
	"set_discount",
	"set_luxury_price",
	"set_price",
]

func choose_command(
	observation: ObservationState,
	context: AiDecisionContext,
	legal_action_ids: Array[String],
	validate_command: Callable = Callable(),
	budget: TimeBudget = null
) -> BotDecision:
	if observation == null:
		return BotDecision.failure("observation is null")
	if context == null:
		return BotDecision.failure("context is null")
	if budget != null and budget.expired():
		return BotDecision.failure("decision budget expired")

	var pending := _choose_pending_confirmation(observation, context, legal_action_ids, validate_command)
	if not pending.is_failure():
		return pending

	match str(observation.phase):
		DefsClass.PHASE_SETUP:
			return _choose_setup(observation, context, legal_action_ids, validate_command)
		DefsClass.PHASE_RESTRUCTURING:
			return _choose_restructuring(context, legal_action_ids, validate_command)
		DefsClass.PHASE_ORDER_OF_BUSINESS:
			return _choose_order_of_business(observation, context, legal_action_ids, validate_command)
		DefsClass.PHASE_WORKING:
			return _choose_working(context, legal_action_ids, validate_command)
		DefsClass.PHASE_PAYDAY:
			return _choose_payday(observation, context, legal_action_ids, validate_command)
		DefsClass.PHASE_CLEANUP:
			return _choose_cleanup(context, legal_action_ids, validate_command)
		_:
			return _choose_phase_skip(context, legal_action_ids, validate_command)

func _choose_setup(
	observation: ObservationState,
	context: AiDecisionContext,
	legal_action_ids: Array[String],
	validate_command: Callable
) -> BotDecision:
	if str(observation.sub_phase) == DefsClass.SUB_PHASE_RESERVE_CARDS and legal_action_ids.has("select_reserve_card"):
		return BasicCandidateHelpersClass.first_valid_reserve_choice(observation, context, validate_command)
	if legal_action_ids.has("place_restaurant"):
		return BasicCandidateHelpersClass.first_valid_restaurant_placement(observation, context, validate_command)
	if legal_action_ids.has(ActionIdsClass.SKIP):
		return BasicCandidateHelpersClass.simple_command(context, ActionIdsClass.SKIP, {}, validate_command, "setup_skip")
	return BotDecision.failure("no legal setup action")

func _choose_restructuring(
	context: AiDecisionContext,
	legal_action_ids: Array[String],
	validate_command: Callable
) -> BotDecision:
	if legal_action_ids.has("submit_restructuring"):
		return BasicCandidateHelpersClass.simple_command(context, "submit_restructuring", {}, validate_command, "submit_restructuring")
	return BotDecision.failure("no legal restructuring action")

func _choose_order_of_business(
	observation: ObservationState,
	context: AiDecisionContext,
	legal_action_ids: Array[String],
	validate_command: Callable
) -> BotDecision:
	if legal_action_ids.has("choose_turn_order"):
		return BasicCandidateHelpersClass.first_valid_turn_order_choice(observation, context, validate_command)
	return BotDecision.failure("no legal order-of-business action")

func _choose_working(
	context: AiDecisionContext,
	legal_action_ids: Array[String],
	validate_command: Callable
) -> BotDecision:
	for action_id in WORKING_MANDATORY_ACTION_IDS:
		if legal_action_ids.has(action_id):
			return BasicCandidateHelpersClass.simple_command(context, action_id, {}, validate_command, "mandatory_%s" % action_id)
	if legal_action_ids.has(ActionIdsClass.SKIP_SUB_PHASE):
		return BasicCandidateHelpersClass.simple_command(context, ActionIdsClass.SKIP_SUB_PHASE, {}, validate_command, "working_skip_sub_phase")
	if legal_action_ids.has(ActionIdsClass.SKIP):
		return BasicCandidateHelpersClass.simple_command(context, ActionIdsClass.SKIP, {}, validate_command, "working_skip")
	return BotDecision.failure("no legal working action")

func _choose_payday(
	observation: ObservationState,
	context: AiDecisionContext,
	legal_action_ids: Array[String],
	validate_command: Callable
) -> BotDecision:
	if legal_action_ids.has("fire") and _has_estimated_payday_salary_shortfall(observation):
		var commands: Array[Command] = []
		for zone_info in [
			{"key": "employees", "location": "active"},
			{"key": "reserve_employees", "location": "reserve"},
		]:
			var key := str(zone_info.get("key", ""))
			var location := str(zone_info.get("location", ""))
			var seen := {}
			var employees_val = observation.own_player.get(key, [])
			if not (employees_val is Array):
				continue
			for employee_val in Array(employees_val):
				var employee_id := str(employee_val)
				if employee_id.is_empty() or employee_id == "ceo" or seen.has(employee_id):
					continue
				if not EmployeeRulesClass.requires_salary(employee_id, observation.own_player):
					continue
				seen[employee_id] = true
				commands.append(Command.create("fire", context.player_id, {
					"employee_id": employee_id,
					"location": location,
				}))
		var fire := BasicCandidateHelpersClass.first_valid_command(commands, validate_command, "fire")
		if not fire.is_failure():
			return fire
	return _choose_phase_skip(context, legal_action_ids, validate_command)

func _choose_cleanup(
	context: AiDecisionContext,
	legal_action_ids: Array[String],
	validate_command: Callable
) -> BotDecision:
	if legal_action_ids.has("choose_fridge_keep"):
		return BasicCandidateHelpersClass.simple_command(context, "choose_fridge_keep", {"keep": {}}, validate_command, "fridge_keep_none")
	return _choose_phase_skip(context, legal_action_ids, validate_command)

func _choose_phase_skip(
	context: AiDecisionContext,
	legal_action_ids: Array[String],
	validate_command: Callable
) -> BotDecision:
	if legal_action_ids.has(ActionIdsClass.SKIP):
		return BasicCandidateHelpersClass.simple_command(context, ActionIdsClass.SKIP, {}, validate_command, "phase_skip")
	return BotDecision.failure("no legal phase action")

func _has_estimated_payday_salary_shortfall(observation: ObservationState) -> bool:
	if observation == null:
		return false
	var player := observation.own_player
	var paid_count := EmployeeRulesClass.count_paid_employees(player)
	if paid_count <= 0:
		return false
	var salary_cost := _read_non_negative_int(player.get("salary_cost_override", observation.rules_public.get("salary_cost", 5)), 5)
	var due := paid_count * salary_cost
	var cash := _read_non_negative_int(player.get("cash", 0), 0)
	return cash < due

func _read_non_negative_int(value, fallback: int) -> int:
	if value is int:
		return maxi(0, int(value))
	if value is float:
		var f: float = float(value)
		if f == floor(f):
			return maxi(0, int(f))
	return maxi(0, int(fallback))

func _choose_pending_confirmation(
	observation: ObservationState,
	context: AiDecisionContext,
	legal_action_ids: Array[String],
	validate_command: Callable
) -> BotDecision:
	if _has_pending_player_action(observation, DefsClass.PHASE_DINNERTIME, context.player_id, "confirm_dinnertime") and legal_action_ids.has("confirm_dinnertime"):
		return BasicCandidateHelpersClass.simple_command(context, "confirm_dinnertime", {}, validate_command, "confirm_dinnertime")
	if _has_pending_player_action(observation, DefsClass.PHASE_MARKETING, context.player_id, "confirm_marketing") and legal_action_ids.has("confirm_marketing"):
		return BasicCandidateHelpersClass.simple_command(context, "confirm_marketing", {}, validate_command, "confirm_marketing")
	return BotDecision.failure("no pending confirmation")

func _has_pending_player_action(
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
	var pending: Array = pending_val
	for item in pending:
		if item is Dictionary:
			var dict: Dictionary = item
			if str(dict.get("kind", "")) == action_id and int(dict.get("player_id", -1)) == player_id:
				return true
	return false
