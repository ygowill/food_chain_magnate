extends "res://tools/manual_test_saves/builders/manual_test_save_map_support.gd"

func _find_first_valid_place_restaurant(engine: GameEngine, actor: int) -> Result:
	if engine == null:
		return Result.failure("engine is null")
	var state := engine.get_state()
	if state == null:
		return Result.failure("state is null")

	var ex := engine.action_registry.get_executor("place_restaurant")
	if ex == null:
		return Result.failure("cannot find executor: place_restaurant")

	var coords_script = _get_coords_script()
	if coords_script == null:
		return Result.failure("cannot load Coords: %s" % CoordsScriptPath)
	var minp: Vector2i = coords_script.get_world_min(state)
	var maxp: Vector2i = coords_script.get_world_max(state)
	for y in range(minp.y, maxp.y + 1):
		for x in range(minp.x, maxp.x + 1):
			for rot in MapUtils.VALID_ROTATIONS:
				var cmd := Command.create("place_restaurant", actor, {
					"position": [x, y],
					"rotation": int(rot),
				})
				var vr := ex.validate(state, cmd)
				if vr.ok:
					return Result.success({
						"action_id": "place_restaurant",
						"actor": actor,
						"params": cmd.params.duplicate(true),
					})
	return Result.failure("no valid place_restaurant placement found")

func _find_first_valid_move_restaurant(engine: GameEngine, actor: int, restaurant_id: String) -> Result:
	if engine == null:
		return Result.failure("engine is null")
	if restaurant_id.is_empty():
		return Result.failure("restaurant_id is empty")
	var state := engine.get_state()
	if state == null:
		return Result.failure("state is null")

	var ex := engine.action_registry.get_executor("move_restaurant")
	if ex == null:
		return Result.failure("cannot find executor: move_restaurant")

	var coords_script = _get_coords_script()
	if coords_script == null:
		return Result.failure("cannot load Coords: %s" % CoordsScriptPath)
	var minp: Vector2i = coords_script.get_world_min(state)
	var maxp: Vector2i = coords_script.get_world_max(state)
	for y in range(minp.y, maxp.y + 1):
		for x in range(minp.x, maxp.x + 1):
			for rot in MapUtils.VALID_ROTATIONS:
				var cmd := Command.create("move_restaurant", actor, {
					"restaurant_id": restaurant_id,
					"position": [x, y],
					"rotation": int(rot),
				})
				var vr := ex.validate(state, cmd)
				if vr.ok:
					return Result.success({
						"action_id": "move_restaurant",
						"actor": actor,
						"params": cmd.params.duplicate(true),
					})
	return Result.failure("no valid move_restaurant placement found (restaurant_id=%s)" % restaurant_id)

func _get_remaining_house_numbers_from_state(state: GameState) -> Array[int]:
	var default_list: Array[int] = [1, 3, 6, 9, 11, 14, 17, 19]
	if state == null or not (state.map is Dictionary):
		return default_list
	var map: Dictionary = state.map
	var list_val = map.get("house_number_supply_remaining", null)
	if list_val is Array:
		var out: Array[int] = []
		for v in Array(list_val):
			if v is int:
				out.append(int(v))
			elif v is float:
				var f: float = float(v)
				if f == floor(f):
					out.append(int(f))
		out.sort()
		var dedup: Array[int] = []
		for n in out:
			if dedup.has(n):
				continue
			dedup.append(n)
		return dedup

	# fallback：默认列表扣掉已存在 house_number（兼容旧存档逻辑）
	var used := {}
	var houses_val = map.get("houses", null)
	if houses_val is Dictionary:
		var houses: Dictionary = houses_val
		for hid in houses.keys():
			var h_val = houses.get(hid, null)
			if not (h_val is Dictionary):
				continue
			var h: Dictionary = h_val
			var hn_val = h.get("house_number", null)
			if hn_val is int:
				used[int(hn_val)] = true
			elif hn_val is float:
				var f2: float = float(hn_val)
				if f2 == floor(f2):
					used[int(f2)] = true

	var remaining: Array[int] = []
	for n in default_list:
		if used.has(int(n)):
			continue
		remaining.append(int(n))
	return remaining

func _find_first_valid_place_house(engine: GameEngine, actor: int, house_number: int) -> Result:
	if engine == null:
		return Result.failure("engine is null")
	var state := engine.get_state()
	if state == null:
		return Result.failure("state is null")

	var ex := engine.action_registry.get_executor("place_house")
	if ex == null:
		return Result.failure("cannot find executor: place_house")

	var coords_script = _get_coords_script()
	if coords_script == null:
		return Result.failure("cannot load Coords: %s" % CoordsScriptPath)
	var minp: Vector2i = coords_script.get_world_min(state)
	var maxp: Vector2i = coords_script.get_world_max(state)
	for y in range(minp.y, maxp.y + 1):
		for x in range(minp.x, maxp.x + 1):
			for rot in MapUtils.VALID_ROTATIONS:
				var cmd := Command.create("place_house", actor, {
					"position": [x, y],
					"rotation": int(rot),
					"house_number": int(house_number),
				})
				var vr := ex.validate(state, cmd)
				if vr.ok:
					return Result.success({
						"action_id": "place_house",
						"actor": actor,
						"params": cmd.params.duplicate(true),
					})
	return Result.failure("no valid place_house placement found (house_number=%d)" % house_number)

func _find_first_valid_place_house_then_add_garden(engine: GameEngine, actor: int, house_number: int) -> Result:
	# 用于 logs 构造：寻找一个“放房屋后仍能添加花园”的组合，避免二者互相占位导致生成失败。
	if engine == null:
		return Result.failure("engine is null")
	var state := engine.get_state()
	if state == null:
		return Result.failure("state is null")

	var ex_house := engine.action_registry.get_executor("place_house")
	if ex_house == null:
		return Result.failure("cannot find executor: place_house")
	var ex_garden := engine.action_registry.get_executor("add_garden")
	if ex_garden == null:
		return Result.failure("cannot find executor: add_garden")

	var coords_script = _get_coords_script()
	if coords_script == null:
		return Result.failure("cannot load Coords: %s" % CoordsScriptPath)
	var minp: Vector2i = coords_script.get_world_min(state)
	var maxp: Vector2i = coords_script.get_world_max(state)

	for y in range(minp.y, maxp.y + 1):
		for x in range(minp.x, maxp.x + 1):
			for rot in MapUtils.VALID_ROTATIONS:
				var place_cmd := Command.create("place_house", actor, {
					"position": [x, y],
					"rotation": int(rot),
					"house_number": int(house_number),
				})
				var next_r := ex_house.compute_new_state(state, place_cmd)
				if not next_r.ok:
					continue
				var next_state: GameState = next_r.value

				var garden_r := _find_first_valid_add_garden_on_state(ex_garden, next_state, actor)
				if not garden_r.ok:
					continue
				var garden_cmd: Dictionary = garden_r.value if (garden_r.value is Dictionary) else {}
				var garden_params: Dictionary = garden_cmd.get("params", {}) if (garden_cmd.get("params", null) is Dictionary) else {}

				return Result.success({
					"place_house_params": place_cmd.params.duplicate(true),
					"add_garden_params": garden_params.duplicate(true),
				})

	return Result.failure("no valid (place_house -> add_garden) combo found (house_number=%d)" % house_number)

func _find_first_valid_add_garden(engine: GameEngine, actor: int) -> Result:
	if engine == null:
		return Result.failure("engine is null")
	var state := engine.get_state()
	if state == null:
		return Result.failure("state is null")

	var ex := engine.action_registry.get_executor("add_garden")
	if ex == null:
		return Result.failure("cannot find executor: add_garden")
	return _find_first_valid_add_garden_on_state(ex, state, actor)

func _find_first_valid_add_garden_on_state(ex: ActionExecutor, state: GameState, actor: int) -> Result:
	if ex == null:
		return Result.failure("executor is null: add_garden")
	if state == null:
		return Result.failure("state is null")

	var houses_val = state.map.get("houses", null) if (state.map is Dictionary) else null
	if not (houses_val is Dictionary):
		return Result.failure("state.map.houses missing or invalid")
	var houses: Dictionary = houses_val
	var house_ids: Array[String] = []
	for k in houses.keys():
		if k is String:
			house_ids.append(str(k))
	house_ids.sort()

	for house_id in house_ids:
		for dir in ["N", "E", "S", "W"]:
			var cmd := Command.create("add_garden", actor, {
				"house_id": house_id,
				"direction": dir,
			})
			var vr := ex.validate(state, cmd)
			if vr.ok:
				return Result.success({
					"action_id": "add_garden",
					"actor": actor,
					"params": cmd.params.duplicate(true),
				})

	return Result.failure("no valid add_garden target found")

func _find_first_valid_lobbyists_road(engine: GameEngine, actor: int) -> Result:
	if engine == null:
		return Result.failure("engine is null")
	var state := engine.get_state()
	if state == null:
		return Result.failure("state is null")
	var ex := engine.action_registry.get_executor("place_lobbyists_road")
	if ex == null:
		return Result.failure("cannot find executor: place_lobbyists_road")

	var coords_script = _get_coords_script()
	if coords_script == null:
		return Result.failure("cannot load Coords: %s" % CoordsScriptPath)
	var minp: Vector2i = coords_script.get_world_min(state)
	var maxp: Vector2i = coords_script.get_world_max(state)
	for piece_id in ["lobbyists_road_straight", "lobbyists_road_long", "lobbyists_road_l"]:
		for y in range(minp.y, maxp.y + 1):
			for x in range(minp.x, maxp.x + 1):
				for rot in MapUtils.VALID_ROTATIONS:
					var cmd := Command.create("place_lobbyists_road", actor, {
						"piece_id": piece_id,
						"anchor_pos": [x, y],
						"rotation": int(rot),
					})
					var vr := ex.validate(state, cmd)
					if vr.ok:
						return Result.success({
							"action_id": "place_lobbyists_road",
							"actor": actor,
							"params": cmd.params.duplicate(true),
						})
	return Result.failure("no valid place_lobbyists_road placement found")

func _find_first_valid_lobbyists_park(engine: GameEngine, actor: int) -> Result:
	if engine == null:
		return Result.failure("engine is null")
	var state := engine.get_state()
	if state == null:
		return Result.failure("state is null")
	var ex := engine.action_registry.get_executor("place_lobbyists_park")
	if ex == null:
		return Result.failure("cannot find executor: place_lobbyists_park")

	var coords_script = _get_coords_script()
	if coords_script == null:
		return Result.failure("cannot load Coords: %s" % CoordsScriptPath)
	var minp: Vector2i = coords_script.get_world_min(state)
	var maxp: Vector2i = coords_script.get_world_max(state)
	for piece_id in ["lobbyists_park_line", "lobbyists_park_t", "lobbyists_park_l"]:
		for y in range(minp.y, maxp.y + 1):
			for x in range(minp.x, maxp.x + 1):
				for rot in MapUtils.VALID_ROTATIONS:
					var cmd := Command.create("place_lobbyists_park", actor, {
						"piece_id": piece_id,
						"anchor_pos": [x, y],
						"rotation": int(rot),
					})
					var vr := ex.validate(state, cmd)
					if vr.ok:
						return Result.success({
							"action_id": "place_lobbyists_park",
							"actor": actor,
							"params": cmd.params.duplicate(true),
						})
	return Result.failure("no valid place_lobbyists_park placement found")

