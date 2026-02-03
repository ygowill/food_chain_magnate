extends "res://tools/manual_test_saves/builders/manual_test_save_placement_support.gd"

func get_registry() -> Dictionary:
	return {
		"employee_place_restaurant": Callable(self, "_build_employee_place_restaurant"),
		"employee_move_restaurant": Callable(self, "_build_employee_move_restaurant"),
		"employee_place_house": Callable(self, "_build_employee_place_house"),
		"employee_add_garden": Callable(self, "_build_employee_add_garden"),
		"employee_lobbyist_place_road": Callable(self, "_build_employee_lobbyist_place_road"),
		"employee_lobbyist_place_park": Callable(self, "_build_employee_lobbyist_place_park"),

		# milestone wrappers / placements
		"milestone_first_lobbyist_used": Callable(self, "_build_milestone_first_lobbyist_used"),
		"milestone_first_lobbyist_used_multi_player_same_round": Callable(self, "_build_milestone_first_lobbyist_used_multi_player_same_round"),
		"milestone_first_house_built": Callable(self, "_build_milestone_first_house_built"),
		"milestone_first_new_restaurant": Callable(self, "_build_milestone_first_new_restaurant"),
	}

func _build_employee_place_restaurant(engine: GameEngine, c: Dictionary) -> Result:
	var adv := _advance_to_working_sub_phase(engine, "PlaceRestaurants")
	if not adv.ok:
		return adv

	var params: Dictionary = c.get("builder_params", {}) if c.get("builder_params", null) is Dictionary else {}
	var employee_type := str(params.get("employee_type", "")).strip_edges()
	if employee_type.is_empty():
		return Result.failure("builder_params.employee_type is empty")

	var state := engine.get_state()
	var actor := state.get_current_player_id()
	if actor < 0:
		return Result.failure("cannot resolve current player")

	var ensure := _ensure_employee(state, actor, employee_type, false, 1)
	if not ensure.ok:
		return ensure

	var find := _find_first_valid_place_restaurant(engine, actor)
	if not find.ok:
		return find
	return Result.success({
		"suggested_command": find.value
	})

func _build_employee_move_restaurant(engine: GameEngine, c: Dictionary) -> Result:
	var adv := _advance_to_working_sub_phase(engine, "PlaceRestaurants")
	if not adv.ok:
		return adv

	var params: Dictionary = c.get("builder_params", {}) if c.get("builder_params", null) is Dictionary else {}
	var employee_type := str(params.get("employee_type", "")).strip_edges()
	if employee_type.is_empty():
		return Result.failure("builder_params.employee_type is empty")

	var state := engine.get_state()
	var actor := state.get_current_player_id()
	if actor < 0:
		return Result.failure("cannot resolve current player")

	var ensure := _ensure_employee(state, actor, employee_type, false, 1)
	if not ensure.ok:
		return ensure

	var player := state.get_player(actor)
	var restaurants_val = player.get("restaurants", [])
	if not (restaurants_val is Array) or restaurants_val.is_empty():
		return Result.failure("player has no restaurants to move")
	var restaurant_id := str(restaurants_val[0])
	if restaurant_id.is_empty():
		return Result.failure("invalid restaurant_id")

	var find := _find_first_valid_move_restaurant(engine, actor, restaurant_id)
	if not find.ok:
		return find
	return Result.success({
		"suggested_command": find.value
	})

func _build_employee_place_house(engine: GameEngine, c: Dictionary) -> Result:
	var adv := _advance_to_working_sub_phase(engine, "PlaceHouses")
	if not adv.ok:
		return adv

	var params: Dictionary = c.get("builder_params", {}) if c.get("builder_params", null) is Dictionary else {}
	var employee_type := str(params.get("employee_type", "")).strip_edges()
	var employee_count := int(params.get("employee_count", 1))
	if employee_type.is_empty():
		return Result.failure("builder_params.employee_type is empty")
	if employee_count <= 0:
		employee_count = 1

	var state := engine.get_state()
	var actor := state.get_current_player_id()
	if actor < 0:
		return Result.failure("cannot resolve current player")

	var ensure := _ensure_employee(state, actor, employee_type, false, employee_count)
	if not ensure.ok:
		return ensure

	var numbers := _get_remaining_house_numbers_from_state(state)
	if numbers.is_empty():
		return Result.failure("no remaining house numbers")
	var house_number := int(numbers[0])

	var find := _find_first_valid_place_house(engine, actor, house_number)
	if not find.ok:
		return find
	return Result.success({
		"suggested_command": find.value
	})

func _build_employee_add_garden(engine: GameEngine, c: Dictionary) -> Result:
	var adv := _advance_to_working_sub_phase(engine, "PlaceHouses")
	if not adv.ok:
		return adv

	var params: Dictionary = c.get("builder_params", {}) if c.get("builder_params", null) is Dictionary else {}
	var employee_type := str(params.get("employee_type", "")).strip_edges()
	var employee_count := int(params.get("employee_count", 1))
	if employee_type.is_empty():
		return Result.failure("builder_params.employee_type is empty")
	if employee_count <= 0:
		employee_count = 1

	var state := engine.get_state()
	var actor := state.get_current_player_id()
	if actor < 0:
		return Result.failure("cannot resolve current player")

	var ensure := _ensure_employee(state, actor, employee_type, false, employee_count)
	if not ensure.ok:
		return ensure

	var find := _find_first_valid_add_garden(engine, actor)
	if not find.ok:
		return find
	return Result.success({
		"suggested_command": find.value
	})

func _build_employee_lobbyist_place_road(engine: GameEngine, _c: Dictionary) -> Result:
	var adv := _advance_to_working_sub_phase(engine, "Lobbyists")
	if not adv.ok:
		return adv

	var state := engine.get_state()
	var actor := state.get_current_player_id()
	if actor < 0:
		return Result.failure("cannot resolve current player")

	var ensure := _ensure_employee(state, actor, "lobbyist", false, 1)
	if not ensure.ok:
		return ensure

	var find := _find_first_valid_lobbyists_road(engine, actor)
	if not find.ok:
		return find
	return Result.success({
		"suggested_command": find.value
	})

func _build_employee_lobbyist_place_park(engine: GameEngine, _c: Dictionary) -> Result:
	var adv := _advance_to_working_sub_phase(engine, "Lobbyists")
	if not adv.ok:
		return adv

	var state := engine.get_state()
	var actor := state.get_current_player_id()
	if actor < 0:
		return Result.failure("cannot resolve current player")

	var ensure := _ensure_employee(state, actor, "lobbyist", false, 1)
	if not ensure.ok:
		return ensure

	var find := _find_first_valid_lobbyists_park(engine, actor)
	if not find.ok:
		return find
	return Result.success({
		"suggested_command": find.value
	})

func _build_milestone_first_lobbyist_used(engine: GameEngine, c: Dictionary) -> Result:
	return _build_employee_lobbyist_place_road(engine, c)

func _build_milestone_first_lobbyist_used_multi_player_same_round(engine: GameEngine, _c: Dictionary) -> Result:
	var adv := _advance_to_working_sub_phase(engine, "Lobbyists")
	if not adv.ok:
		return adv

	var state := engine.get_state()
	if state == null:
		return Result.failure("state is null")

	# Ensure all players have a lobbyist (matches "multi-player same round" scenario).
	for pid in range(state.players.size()):
		var ensure := _ensure_employee(state, pid, "lobbyist", false, 1)
		if not ensure.ok:
			return ensure

	# This save should start BEFORE anyone used a lobbyist.
	# Players should earn the milestone by actually placing a lobbyists road/park in-game.
	if state.round_state is Dictionary:
		var pending := {}
		for i in range(state.players.size()):
			pending[i] = false
		state.round_state["lobbyists_extra_tile_pending"] = pending
		var last := []
		for i in range(state.players.size()):
			last.append(null)
		state.round_state["lobbyists_extra_tile_last_placed"] = last

	for pid2 in range(state.players.size()):
		var p := state.get_player(pid2)
		if p.has("milestones") and (p["milestones"] is Array):
			var ms: Array = (p["milestones"] as Array).duplicate()
			while ms.has("first_lobbyist_used"):
				ms.erase("first_lobbyist_used")
			p["milestones"] = ms

	# Provide a suggested command for player 0 to trigger the milestone quickly.
	var actor := 0
	if actor >= 0 and actor < state.players.size():
		var find := _find_first_valid_lobbyists_road(engine, actor)
		if find.ok:
			return Result.success({"suggested_command": find.value})
		var find2 := _find_first_valid_lobbyists_park(engine, actor)
		if find2.ok:
			return Result.success({"suggested_command": find2.value})

	return Result.success({})

func _build_milestone_first_house_built(engine: GameEngine, c: Dictionary) -> Result:
	return _build_employee_place_house(engine, c)

func _build_milestone_first_new_restaurant(engine: GameEngine, c: Dictionary) -> Result:
	var adv := _advance_to_working_sub_phase(engine, "PlaceRestaurants")
	if not adv.ok:
		return adv

	var params: Dictionary = c.get("builder_params", {}) if c.get("builder_params", null) is Dictionary else {}
	var employee_type := str(params.get("employee_type", "")).strip_edges()
	if employee_type.is_empty():
		return Result.failure("builder_params.employee_type is empty")

	var state := engine.get_state()
	_force_turn_order(state)

	# 为“首个新餐厅”准备一个确定性小地图：
	# - 方便后续手工复核 place_new_restaurant_mailbox（推荐 position=[0,2]）
	# - 用竖向道路 x=3 将地图分成左右两个 mailbox block
	_apply_test_map_new_restaurant_mailbox(state)

	var actor := state.get_current_player_id()
	if actor < 0:
		return Result.failure("cannot resolve current player")

	var ensure := _ensure_employee(state, actor, employee_type, false, 1)
	if not ensure.ok:
		return ensure

	var find := _find_first_valid_place_restaurant(engine, actor)
	if not find.ok:
		return find
	return Result.success({
		"suggested_command": find.value
	})
