extends RefCounted

# 手工复核存档 builder 共用 helper。
#
# 注意：避免在脚本编译期 preload core/tests 或依赖 autoload 的脚本，
# 否则在 `--script` 模式下可能出现“Identifier not found: GameLog/EventBus”的噪音编译报错。
# 这里优先使用 class_name（TestPhaseUtils/StateUpdater/MapUtils），以及在运行期 load() 无 class_name 的脚本（Coords）。

const CoordsScriptPath := "res://core/map/map_runtime/coords.gd"

var _coords_script_cache = null

func _get_coords_script():
	if _coords_script_cache == null:
		_coords_script_cache = load(CoordsScriptPath)
	return _coords_script_cache

func _advance_to_phase(engine: GameEngine, target_phase: String, force_turn_order: bool = true) -> Result:
	var adv := TestPhaseUtils.advance_until_phase(engine, target_phase, 80)
	if not adv.ok:
		return adv
	var state := engine.get_state()
	if force_turn_order:
		_force_turn_order(state)
	if str(state.phase) != target_phase:
		return Result.failure("expected phase=%s, got: %s" % [target_phase, str(state.phase)])
	return Result.success()

func _force_turn_order(state: GameState) -> void:
	if state == null:
		return
	var count := state.players.size()
	state.turn_order.clear()
	for i in range(count):
		state.turn_order.append(i)
	state.current_player_index = 0

func _reset_sub_phase_passed(state: GameState) -> void:
	if state == null:
		return
	if not (state.round_state is Dictionary):
		return
	var passed := {}
	for i in range(state.players.size()):
		passed[i] = false
	state.round_state["sub_phase_passed"] = passed

func _advance_to_working(engine: GameEngine) -> Result:
	var to_working := TestPhaseUtils.advance_until_phase(engine, "Working", 60)
	if not to_working.ok:
		return to_working

	var state := engine.get_state()
	_force_turn_order(state)
	if state.phase != "Working":
		return Result.failure("expected Working, got: %s" % str(state.phase))
	return Result.success()

func _advance_to_working_sub_phase(engine: GameEngine, target_sub_phase: String) -> Result:
	var adv := _advance_to_working(engine)
	if not adv.ok:
		return adv
	var to_target := TestPhaseUtils.advance_until_working_sub_phase(engine, target_sub_phase, 60)
	if not to_target.ok:
		# fallback：直接设置子阶段（子阶段顺序可能因模块插入/跳过策略变化而失败）
		engine.get_state().sub_phase = target_sub_phase
	var state := engine.get_state()
	_force_turn_order(state)
	state.sub_phase = target_sub_phase
	_reset_sub_phase_passed(state)
	if state.phase != "Working" or state.sub_phase != target_sub_phase:
		return Result.failure("expected Working/%s, got: %s/%s" % [target_sub_phase, str(state.phase), str(state.sub_phase)])
	return Result.success()

func _ensure_employee(state: GameState, player_id: int, employee_id: String, to_reserve: bool, count: int = 1) -> Result:
	if state == null:
		return Result.failure("state is null")
	if employee_id.is_empty():
		return Result.failure("employee_id is empty")
	if count <= 0:
		return Result.failure("count must be > 0")

	var player := state.get_player(player_id)
	var key := "reserve_employees" if to_reserve else "employees"
	var arr_val = player.get(key, [])
	if not (arr_val is Array):
		return Result.failure("player.%s is not an Array" % key)
	var arr: Array = arr_val

	var existing := 0
	for v in arr:
		if v is String and str(v) == employee_id:
			existing += 1
	if existing >= count:
		return Result.success()

	var need := count - existing
	# 起始 CEO 不在 employee_pool；其余员工必须从池中取，避免写入无效状态。
	if employee_id != "ceo":
		if not (state.employee_pool is Dictionary) or not state.employee_pool.has(employee_id):
			return Result.failure("employee_id not in employee_pool: %s (module missing?)" % employee_id)
		var take := StateUpdater.take_from_pool(state, employee_id, need)
		if not take.ok:
			return Result.failure("take_from_pool(%s) failed: %s" % [employee_id, take.error])

	for _i in range(need):
		var add := StateUpdater.add_employee(state, player_id, employee_id, to_reserve)
		if not add.ok:
			return Result.failure("add_employee(%s) failed: %s" % [employee_id, add.error])
	return Result.success()

func _exec_system(engine: GameEngine, action_id: String, params: Dictionary) -> Result:
	if engine == null:
		return Result.failure("engine is null")
	if action_id.is_empty():
		return Result.failure("action_id is empty")
	var cmd := Command.create_system(action_id, params)
	var r := engine.execute_command(cmd)
	if not r.ok:
		return Result.failure("%s failed: %s" % [action_id, r.error])
	return Result.success(r.value).with_warnings(r.warnings)

func _get_road_graph(state: GameState):
	var rg_cache_script = load("res://core/map/map_runtime/road_graph_cache.gd")
	if rg_cache_script == null:
		return null
	return rg_cache_script.get_road_graph(state)

func _get_player_first_restaurant_id(state: GameState, player_id: int) -> Result:
	if state == null:
		return Result.failure("state is null")
	if not (state.players is Array):
		return Result.failure("state.players is not an Array")
	if player_id < 0 or player_id >= state.players.size():
		return Result.failure("invalid player_id: %d" % player_id)
	var p_val = state.players[player_id]
	if not (p_val is Dictionary):
		return Result.failure("players[%d] is not a Dictionary" % player_id)
	var p: Dictionary = p_val
	var restaurants_val = p.get("restaurants", [])
	if not (restaurants_val is Array) or restaurants_val.is_empty():
		return Result.failure("player %d has no restaurants" % player_id)
	var rid := str(restaurants_val[0])
	if rid.is_empty():
		return Result.failure("invalid restaurant_id for player %d" % player_id)
	return Result.success(rid)

func _get_distance_rest_to_house(road_graph, state: GameState, grid_size: Vector2i, rest_id: String, rest: Dictionary, house_id: String, house: Dictionary) -> Result:
	var r := DinnertimeDistance.get_restaurant_to_house_distance(road_graph, state, grid_size, rest_id, rest, house_id, house)
	if not r.ok:
		return r
	if not (r.value is Dictionary):
		return Result.success(-1)
	var v: Dictionary = r.value
	if not v.has("distance") or not (v["distance"] is int):
		return Result.success(-1)
	return Result.success(int(v["distance"]))

func _freeze_engine_as_initial(engine: GameEngine) -> void:
	if engine == null:
		return
	engine.command_history.clear()
	engine.checkpoints.clear()
	engine.current_command_index = -1
	engine.create_checkpoint(0)
