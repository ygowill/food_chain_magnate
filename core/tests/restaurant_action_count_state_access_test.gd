# restaurant action_count 状态访问回归测试
class_name RestaurantActionCountStateAccessTest
extends RefCounted

const TestPhaseUtilsClass = preload("res://core/tests/test_phase_utils.gd")
const StateUpdaterClass = preload("res://core/state/state_updater.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const ActionIdsClass = preload("res://core/actions/action_ids.gd")

static func run(player_count: int = 2, seed_val: int = 12345) -> Result:
	var r := _test_place_can_initiate_fails_closed_on_invalid_action_counts(player_count, seed_val)
	if not r.ok:
		return r
	r = _test_place_validate_fails_fast_on_invalid_action_counts_without_partial_mutation(player_count, seed_val)
	if not r.ok:
		return r
	r = _test_place_apply_fails_fast_on_invalid_action_counts_without_partial_mutation(player_count, seed_val)
	if not r.ok:
		return r
	r = _test_move_can_initiate_fails_closed_on_invalid_action_counts(player_count, seed_val)
	if not r.ok:
		return r
	r = _test_move_validate_fails_fast_on_invalid_action_counts_without_partial_mutation(player_count, seed_val)
	if not r.ok:
		return r
	r = _test_move_apply_fails_fast_on_invalid_action_counts_without_partial_mutation(player_count, seed_val)
	if not r.ok:
		return r
	return Result.success({"cases": 6})

static func _build_place_restaurant_working_engine(player_count: int, seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(player_count, seed_val)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)
	var state := engine.get_state()
	for pid in range(player_count):
		var grant := StateUpdaterClass.player_receive_from_bank(state, pid, 20)
		if not grant.ok:
			return Result.failure("发放测试现金失败: %s" % grant.error)
	var to_working := TestPhaseUtilsClass.advance_until_phase(engine, DefsClass.PHASE_WORKING, 30)
	if not to_working.ok:
		return to_working
	state = engine.get_state()
	state.sub_phase = DefsClass.SUB_PHASE_PLACE_RESTAURANTS
	var actor := state.get_current_player_id()
	if actor < 0:
		return Result.failure("无法获取当前玩家")
	var take := StateUpdaterClass.take_from_pool(state, "local_manager", 1)
	if not take.ok:
		return Result.failure("从员工池取出 local_manager 失败: %s" % take.error)
	var add := StateUpdaterClass.add_employee(state, actor, "local_manager", false)
	if not add.ok:
		return Result.failure("添加 local_manager 失败: %s" % add.error)
	return Result.success(engine)

static func _build_move_restaurant_working_engine(player_count: int, seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(player_count, seed_val)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)
	var setup := _place_initial_restaurants(engine)
	if not setup.ok:
		return setup
	var to_working := TestPhaseUtilsClass.advance_until_phase(engine, DefsClass.PHASE_WORKING, 40)
	if not to_working.ok:
		return to_working
	var state := engine.get_state()
	state.sub_phase = DefsClass.SUB_PHASE_PLACE_RESTAURANTS
	var actor := state.get_current_player_id()
	if actor < 0:
		return Result.failure("无法获取当前玩家")
	var take_local := StateUpdaterClass.take_from_pool(state, "local_manager", 1)
	if not take_local.ok:
		return Result.failure("从员工池取出 local_manager 失败: %s" % take_local.error)
	var add_local := StateUpdaterClass.add_employee(state, actor, "local_manager", false)
	if not add_local.ok:
		return Result.failure("添加 local_manager 失败: %s" % add_local.error)
	var take_regional := StateUpdaterClass.take_from_pool(state, "regional_manager", 1)
	if not take_regional.ok:
		return Result.failure("从员工池取出 regional_manager 失败: %s" % take_regional.error)
	var add_regional := StateUpdaterClass.add_employee(state, actor, "regional_manager", false)
	if not add_regional.ok:
		return Result.failure("添加 regional_manager 失败: %s" % add_regional.error)
	return Result.success(engine)

static func _test_place_can_initiate_fails_closed_on_invalid_action_counts(player_count: int, seed_val: int) -> Result:
	var built := _build_place_restaurant_working_engine(player_count, seed_val)
	if not built.ok:
		return built
	var engine: GameEngine = built.value
	var state := engine.get_state()
	var actor := state.get_current_player_id()
	state.round_state["action_counts"] = {
		str(actor): {"place_restaurant": 1},
	}
	var executor = engine.action_registry.get_executor("place_restaurant")
	if executor == null:
		return Result.failure("place_restaurant executor 不存在")
	if executor.can_initiate(state, actor):
		return Result.failure("action_counts 使用字符串玩家 key 时 place_restaurant can_initiate 应 fail-closed")
	return Result.success()

static func _test_place_validate_fails_fast_on_invalid_action_counts_without_partial_mutation(player_count: int, seed_val: int) -> Result:
	var built := _build_place_restaurant_working_engine(player_count, seed_val)
	if not built.ok:
		return built
	var engine: GameEngine = built.value
	var state := engine.get_state()
	var actor := state.get_current_player_id()
	var cmd := _find_first_valid_place(engine, actor, {"employee_type": "local_manager"})
	if cmd == null:
		return Result.failure("找不到合法的餐厅放置点")
	state.round_state["action_counts"] = {
		str(actor): {"place_restaurant": 1},
	}
	var player_before := str(state.players[actor])
	var map_before := str(state.map)
	var round_state_before := str(state.round_state)
	var executor = engine.action_registry.get_executor("place_restaurant")
	var result := executor._validate_specific(state, cmd)
	if result.ok:
		return Result.failure("action_counts 使用字符串玩家 key 时 place_restaurant validate 应失败")
	var err := str(result.error)
	if err.find("action_counts") < 0 or err.find("字符串玩家 key") < 0:
		return Result.failure("错误信息应包含 action_counts 与 字符串玩家 key，实际: %s" % err)
	if str(state.players[actor]) != player_before:
		return Result.failure("失败时不应提前改写玩家状态")
	if str(state.map) != map_before:
		return Result.failure("失败时不应提前改写 map")
	if str(state.round_state) != round_state_before:
		return Result.failure("失败时不应提前改写 round_state")
	return Result.success()

static func _test_place_apply_fails_fast_on_invalid_action_counts_without_partial_mutation(player_count: int, seed_val: int) -> Result:
	var built := _build_place_restaurant_working_engine(player_count, seed_val)
	if not built.ok:
		return built
	var engine: GameEngine = built.value
	var state := engine.get_state()
	var actor := state.get_current_player_id()
	var cmd := _find_first_valid_place(engine, actor, {"employee_type": "local_manager"})
	if cmd == null:
		return Result.failure("找不到合法的餐厅放置点")
	state.round_state["action_counts"] = {
		str(actor): {"place_restaurant": 1},
	}
	var player_before := str(state.players[actor])
	var map_before := str(state.map)
	var round_state_before := str(state.round_state)
	var result := engine.execute_command(cmd)
	if result.ok:
		return Result.failure("action_counts 使用字符串玩家 key 时 place_restaurant apply 应失败")
	var err := str(result.error)
	if err.find("action_counts") < 0 or err.find("字符串玩家 key") < 0:
		return Result.failure("错误信息应包含 action_counts 与 字符串玩家 key，实际: %s" % err)
	state = engine.get_state()
	if str(state.players[actor]) != player_before:
		return Result.failure("失败时不应提前改写玩家状态")
	if str(state.map) != map_before:
		return Result.failure("失败时不应提前改写 map")
	if str(state.round_state) != round_state_before:
		return Result.failure("失败时不应提前改写 round_state")
	return Result.success()

static func _test_move_can_initiate_fails_closed_on_invalid_action_counts(player_count: int, seed_val: int) -> Result:
	var built := _build_move_restaurant_working_engine(player_count, seed_val)
	if not built.ok:
		return built
	var engine: GameEngine = built.value
	var state := engine.get_state()
	var actor := state.get_current_player_id()
	state.round_state["action_counts"] = {
		str(actor): {"move_restaurant": 1},
	}
	var executor = engine.action_registry.get_executor("move_restaurant")
	if executor == null:
		return Result.failure("move_restaurant executor 不存在")
	if executor.can_initiate(state, actor):
		return Result.failure("action_counts 使用字符串玩家 key 时 move_restaurant can_initiate 应 fail-closed")
	return Result.success()

static func _test_move_validate_fails_fast_on_invalid_action_counts_without_partial_mutation(player_count: int, seed_val: int) -> Result:
	var built := _build_move_restaurant_working_engine(player_count, seed_val)
	if not built.ok:
		return built
	var engine: GameEngine = built.value
	var state := engine.get_state()
	var actor := state.get_current_player_id()
	var restaurants: Array = Array(state.players[actor].get("restaurants", []))
	if restaurants.is_empty():
		return Result.failure("玩家没有可移动餐厅")
	var rest_id := str(restaurants[0])
	var rest_val = state.map.get("restaurants", {}).get(rest_id, {})
	if not (rest_val is Dictionary):
		return Result.failure("map.restaurants[%s] 类型错误" % rest_id)
	var rest: Dictionary = rest_val
	var old_anchor: Vector2i = rest.get("anchor_pos", Vector2i(-1, -1))
	var old_rotation: int = int(rest.get("rotation", 0))
	var cmd := _find_first_valid_move(engine, actor, rest_id, old_anchor, old_rotation)
	if cmd == null:
		return Result.failure("找不到合法的餐厅移动点")
	state.round_state["action_counts"] = {
		str(actor): {"move_restaurant": 1},
	}
	var player_before := str(state.players[actor])
	var map_before := str(state.map)
	var round_state_before := str(state.round_state)
	var executor = engine.action_registry.get_executor("move_restaurant")
	var result := executor._validate_specific(state, cmd)
	if result.ok:
		return Result.failure("action_counts 使用字符串玩家 key 时 move_restaurant validate 应失败")
	var err := str(result.error)
	if err.find("action_counts") < 0 or err.find("字符串玩家 key") < 0:
		return Result.failure("错误信息应包含 action_counts 与 字符串玩家 key，实际: %s" % err)
	if str(state.players[actor]) != player_before:
		return Result.failure("失败时不应提前改写玩家状态")
	if str(state.map) != map_before:
		return Result.failure("失败时不应提前改写 map")
	if str(state.round_state) != round_state_before:
		return Result.failure("失败时不应提前改写 round_state")
	return Result.success()

static func _test_move_apply_fails_fast_on_invalid_action_counts_without_partial_mutation(player_count: int, seed_val: int) -> Result:
	var built := _build_move_restaurant_working_engine(player_count, seed_val)
	if not built.ok:
		return built
	var engine: GameEngine = built.value
	var state := engine.get_state()
	var actor := state.get_current_player_id()
	var restaurants: Array = Array(state.players[actor].get("restaurants", []))
	if restaurants.is_empty():
		return Result.failure("玩家没有可移动餐厅")
	var rest_id := str(restaurants[0])
	var rest_val = state.map.get("restaurants", {}).get(rest_id, {})
	if not (rest_val is Dictionary):
		return Result.failure("map.restaurants[%s] 类型错误" % rest_id)
	var rest: Dictionary = rest_val
	var old_anchor: Vector2i = rest.get("anchor_pos", Vector2i(-1, -1))
	var old_rotation: int = int(rest.get("rotation", 0))
	var cmd := _find_first_valid_move(engine, actor, rest_id, old_anchor, old_rotation)
	if cmd == null:
		return Result.failure("找不到合法的餐厅移动点")
	state.round_state["action_counts"] = {
		str(actor): {"move_restaurant": 1},
	}
	var player_before := str(state.players[actor])
	var map_before := str(state.map)
	var round_state_before := str(state.round_state)
	var result := engine.execute_command(cmd)
	if result.ok:
		return Result.failure("action_counts 使用字符串玩家 key 时 move_restaurant apply 应失败")
	var err := str(result.error)
	if err.find("action_counts") < 0 or err.find("字符串玩家 key") < 0:
		return Result.failure("错误信息应包含 action_counts 与 字符串玩家 key，实际: %s" % err)
	state = engine.get_state()
	if str(state.players[actor]) != player_before:
		return Result.failure("失败时不应提前改写玩家状态")
	if str(state.map) != map_before:
		return Result.failure("失败时不应提前改写 map")
	if str(state.round_state) != round_state_before:
		return Result.failure("失败时不应提前改写 round_state")
	return Result.success()

static func _place_initial_restaurants(engine: GameEngine) -> Result:
	var placed := {}
	for p in range(engine.get_state().players.size()):
		placed[p] = false

	var safety := 0
	while true:
		var done := true
		for p in placed.keys():
			if not placed[p]:
				done = false
				break
		if done:
			break

		safety += 1
		if safety > 60:
			return Result.failure("Setup 放置餐厅循环超出安全上限")

		var state := engine.get_state()
		var current_player := state.get_current_player_id()
		if str(state.sub_phase) == DefsClass.SUB_PHASE_RESERVE_CARDS:
			var pick := engine.execute_command(Command.create("select_reserve_card", current_player, {"selected_index": 0}))
			if not pick.ok:
				return Result.failure("选择储备卡失败: %s" % pick.error)
			continue

		if not placed[current_player]:
			var cmd_place := _find_first_valid_place(engine, current_player)
			if cmd_place == null:
				return Result.failure("找不到玩家 %d 的合法餐厅放置点" % current_player)
			var exec_place := engine.execute_command(cmd_place)
			if not exec_place.ok:
				return Result.failure("放置餐厅失败: %s (%s)" % [exec_place.error, str(cmd_place)])
			placed[current_player] = true

		var cmd_skip := Command.create(ActionIdsClass.SKIP, current_player)
		var exec_skip := engine.execute_command(cmd_skip)
		if not exec_skip.ok:
			return Result.failure("skip 失败: %s (%s)" % [exec_skip.error, str(cmd_skip)])

	return Result.success()

static func _find_first_valid_place(engine: GameEngine, actor: int, extra_params: Dictionary = {}) -> Command:
	var state := engine.get_state()
	var executor := engine.action_registry.get_executor("place_restaurant")
	if executor == null:
		return null
	var grid_size: Vector2i = state.map.get("grid_size", Vector2i.ZERO)
	var rotations := [0, 90, 180, 270]
	for y in range(grid_size.y):
		for x in range(grid_size.x):
			for rot in rotations:
				var params := {"position": [x, y], "rotation": rot}
				if extra_params != null and not extra_params.is_empty():
					for k in extra_params.keys():
						params[k] = extra_params[k]
				var cmd := Command.create("place_restaurant", actor, params)
				var vr := executor.validate(state, cmd)
				if vr.ok:
					return cmd
	return null

static func _find_first_valid_move(engine: GameEngine, actor: int, restaurant_id: String, old_anchor: Vector2i, old_rotation: int) -> Command:
	var state := engine.get_state()
	var executor := engine.action_registry.get_executor("move_restaurant")
	if executor == null:
		return null
	var grid_size: Vector2i = state.map.get("grid_size", Vector2i.ZERO)
	var rotations := [0, 90, 180, 270]
	for y in range(grid_size.y):
		for x in range(grid_size.x):
			for rot in rotations:
				if Vector2i(x, y) == old_anchor and rot == old_rotation:
					continue
				var cmd := Command.create("move_restaurant", actor, {
					"restaurant_id": restaurant_id,
					"position": [x, y],
					"rotation": rot,
					"employee_type": "regional_manager",
				})
				var vr := executor.validate(state, cmd)
				if vr.ok:
					return cmd
	return null
