class_name BasicCandidateHelpers
extends RefCounted

static func simple_command(
	context: AiDecisionContext,
	action_id: String,
	params: Dictionary,
	validate_command: Callable,
	macro_action_id: String = ""
) -> BotDecision:
	var command := Command.create(action_id, context.player_id, params)
	return first_valid_command([command], validate_command, macro_action_id if not macro_action_id.is_empty() else action_id)

static func first_valid_reserve_choice(
	observation: ObservationState,
	context: AiDecisionContext,
	validate_command: Callable
) -> BotDecision:
	var cards_val = observation.own_player.get("reserve_cards", [])
	var card_count := 0
	if cards_val is Array:
		card_count = Array(cards_val).size()
	if card_count <= 0:
		return BotDecision.failure("reserve_cards is empty")

	var commands: Array[Command] = []
	var first_index := _stable_index(context.decision_seed, card_count)
	for offset in range(card_count):
		var selected_index := (first_index + offset) % card_count
		commands.append(Command.create("select_reserve_card", context.player_id, {
			"selected_index": selected_index,
		}))
	return first_valid_command(commands, validate_command, "reserve_card")

static func first_valid_turn_order_choice(
	observation: ObservationState,
	context: AiDecisionContext,
	validate_command: Callable
) -> BotDecision:
	var oob_val = observation.round_state_public.get("order_of_business", {})
	if not (oob_val is Dictionary):
		return BotDecision.failure("round_state.order_of_business is missing")
	var picks_val = Dictionary(oob_val).get("picks", [])
	if not (picks_val is Array):
		return BotDecision.failure("order_of_business.picks is missing")

	var commands: Array[Command] = []
	var picks: Array = picks_val
	for i in range(picks.size()):
		if int(picks[i]) == -1:
			commands.append(Command.create("choose_turn_order", context.player_id, {
				"position": i,
			}))
	return first_valid_command(commands, validate_command, "turn_order")

static func first_valid_restaurant_placement(
	observation: ObservationState,
	context: AiDecisionContext,
	validate_command: Callable
) -> BotDecision:
	var grid_size := _read_grid_size(observation.map_public)
	if grid_size.x <= 0 or grid_size.y <= 0:
		return BotDecision.failure("map_public.grid_size is invalid: %s" % str(grid_size))

	var commands: Array[Command] = []
	var rotations := [0, 90, 180, 270]
	for y in range(grid_size.y):
		for x in range(grid_size.x):
			for rotation in rotations:
				commands.append(Command.create("place_restaurant", context.player_id, {
					"position": [x, y],
					"rotation": int(rotation),
				}))
	return first_valid_command(commands, validate_command, "initial_restaurant")

static func first_valid_command(
	commands: Array[Command],
	validate_command: Callable,
	macro_action_id: String
) -> BotDecision:
	if commands.is_empty():
		return BotDecision.failure("no candidate commands for %s" % macro_action_id)
	if not validate_command.is_valid():
		return BotDecision.create(commands[0], macro_action_id, 0.0, {
			"validation": "skipped",
		})

	var errors: Array[String] = []
	for command in commands:
		var validated = validate_command.call(command)
		if validated is Result and validated.ok:
			return BotDecision.create(command, macro_action_id, 0.0, {
				"candidate_count": commands.size(),
			})
		if validated is Result:
			errors.append("%s: %s" % [command.action_id, validated.error])
		else:
			errors.append("%s: validator returned non-Result" % command.action_id)
	return BotDecision.failure("no valid command for %s: %s" % [macro_action_id, "; ".join(errors.slice(0, 5))])

static func _stable_index(seed_value: int, size: int) -> int:
	if size <= 0:
		return 0
	var value := int(seed_value) % size
	if value < 0:
		value += size
	return value

static func _read_grid_size(map_public: Dictionary) -> Vector2i:
	var value = map_public.get("grid_size", Vector2i.ZERO)
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
