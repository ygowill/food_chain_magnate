# 弃权（联机：掉线玩家）
# - 移除玩家资产（餐厅/营销板件/员工/库存/里程碑/现金等）
# - 保留：房屋/花园（地图自带需求源）
# - 约束：为避免破坏引擎不变量与规则假设，保留 CEO（不可移除）
class_name ForfeitPlayerAction
extends ActionExecutor

const CoordsClass = preload("res://core/map/map_runtime/coords.gd")
const RoadGraphCacheClass = preload("res://core/map/map_runtime/road_graph_cache.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const BankStateAccessClass = preload("res://core/state/bank_state_access.gd")
const ONLINE_DINNERTIME_CONFIRMED_PLAYERS_KEY := "online_dinnertime_confirmed_players"

func _init() -> void:
	action_id = "forfeit_player"
	display_name = "弃权"
	description = "弃权并移除玩家资产（联机掉线）"
	requires_actor = true
	is_mandatory = false
	is_internal = true

func _validate_specific(state: GameState, command: Command) -> Result:
	if state == null:
		return Result.failure("state 为空")
	if str(state.phase) == DefsClass.PHASE_GAME_OVER:
		return Result.failure("游戏已结束")
	if command.actor < 0 or command.actor >= state.players.size():
		return Result.failure("玩家不存在: %d" % command.actor)
	return Result.success()

func _apply_changes(state: GameState, command: Command) -> Result:
	var player_id := int(command.actor)
	var player_val = state.players[player_id]
	if not (player_val is Dictionary):
		return Result.failure("players[%d] 类型错误（期望 Dictionary）" % player_id)
	var player: Dictionary = player_val

	if bool(player.get("forfeited", false)):
		return Result.success().with_warning("玩家已弃权: %d" % player_id)

	var pending_update := _plan_pending_phase_actions_after_forfeit(state, player_id)
	if not pending_update.ok:
		return pending_update
	var confirmed_update := _plan_online_dinnertime_confirmed_players_after_forfeit(state, player_id)
	if not confirmed_update.ok:
		return confirmed_update

	player["forfeited"] = true

	var remove_cash := _remove_player_cash(state, player)
	if not remove_cash.ok:
		return remove_cash
	_remove_player_employees(state, player)
	_remove_player_inventory(player)
	_remove_player_milestones(player)
	_remove_player_restaurants(state, player)
	_remove_player_marketing(state, player_id)
	_clear_player_misc_assets(player)

	state.players[player_id] = player
	if pending_update.value != null:
		state.round_state["pending_phase_actions"] = pending_update.value
	if confirmed_update.value != null:
		state.round_state[ONLINE_DINNERTIME_CONFIRMED_PLAYERS_KEY] = confirmed_update.value
	_maybe_finish_game_if_last_active_player_remains(state, player_id)
	return Result.success({"player_id": player_id})

static func _remove_player_cash(state: GameState, player: Dictionary) -> Result:
	var cash := int(player.get("cash", 0))
	if cash < 0:
		cash = 0
	player["cash"] = 0

	if cash <= 0:
		return Result.success()

	var removed := BankStateAccessClass.add_removed_total(state, cash, "forfeit_player")
	if not removed.ok:
		return removed
	return Result.success()

static func _remove_player_employees(state: GameState, player: Dictionary) -> void:
	var removed_counts: Dictionary = {}

	var active: Array = player.get("employees", []) if (player.get("employees", null) is Array) else []
	var reserve: Array = player.get("reserve_employees", []) if (player.get("reserve_employees", null) is Array) else []
	var busy: Array = player.get("busy_marketers", []) if (player.get("busy_marketers", null) is Array) else []

	# CEO 不可移除：若 CEO 在待命区，纠正回在岗。
	var keep_ceo := active.has("ceo") or reserve.has("ceo")
	if keep_ceo:
		for emp_val in reserve:
			var emp_id := str(emp_val)
			if emp_id == "ceo":
				continue
			removed_counts[emp_id] = int(removed_counts.get(emp_id, 0)) + 1
		for emp_val2 in active:
			var emp_id2 := str(emp_val2)
			if emp_id2 == "ceo":
				continue
			removed_counts[emp_id2] = int(removed_counts.get(emp_id2, 0)) + 1
		for emp_val3 in busy:
			var emp_id3 := str(emp_val3)
			if emp_id3 == "ceo":
				continue
			removed_counts[emp_id3] = int(removed_counts.get(emp_id3, 0)) + 1
	else:
		# 容错：若 CEO 丢失，仍保留一个 CEO 以维持规则/阶段钩子约束。
		for emp_val4 in reserve:
			removed_counts[str(emp_val4)] = int(removed_counts.get(str(emp_val4), 0)) + 1
		for emp_val5 in active:
			removed_counts[str(emp_val5)] = int(removed_counts.get(str(emp_val5), 0)) + 1
		for emp_val6 in busy:
			removed_counts[str(emp_val6)] = int(removed_counts.get(str(emp_val6), 0)) + 1

	if state != null and (state.employee_pool is Dictionary):
		for k in removed_counts.keys():
			var emp_type := str(k)
			if emp_type.is_empty() or emp_type == "ceo":
				continue
			var add_n := int(removed_counts.get(emp_type, 0))
			if add_n <= 0:
				continue
			var current := int(state.employee_pool.get(emp_type, 0))
			state.employee_pool[emp_type] = current + add_n

	player["employees"] = ["ceo"]
	player["reserve_employees"] = []
	player["busy_marketers"] = []

static func _remove_player_inventory(player: Dictionary) -> void:
	if not (player.get("inventory", null) is Dictionary):
		player["inventory"] = {}
		return
	var inv: Dictionary = player["inventory"]
	for k in inv.keys():
		inv[k] = 0
	player["inventory"] = inv

static func _remove_player_milestones(player: Dictionary) -> void:
	player["milestones"] = []

static func _remove_player_restaurants(state: GameState, player: Dictionary) -> void:
	var player_id := int(player.get("id", -1))
	if state == null or not (state.map is Dictionary):
		player["restaurants"] = []
		return
	var map: Dictionary = state.map
	if not map.has("restaurants") or not (map["restaurants"] is Dictionary):
		player["restaurants"] = []
		return
	if not map.has("cells") or not (map["cells"] is Array):
		player["restaurants"] = []
		return
	var cells: Array = map["cells"]

	var restaurants: Dictionary = map["restaurants"]
	var to_remove: Array[String] = []
	for rid_val in restaurants.keys():
		var rid := str(rid_val)
		var rest_val = restaurants.get(rid_val, null)
		if not (rest_val is Dictionary):
			continue
		var rest: Dictionary = rest_val
		if int(rest.get("owner", -1)) != player_id:
			continue
		to_remove.append(rid)

	for rid in to_remove:
		var rest_val2 = restaurants.get(rid, null)
		if rest_val2 is Dictionary:
			var rest2: Dictionary = rest_val2
			var cells_val = rest2.get("cells", null)
			if cells_val is Array:
				for world_pos_val in Array(cells_val):
					if not (world_pos_val is Vector2i):
						continue
					var idx := CoordsClass.world_to_index(state, Vector2i(world_pos_val))
					if idx.y < 0 or idx.y >= cells.size():
						continue
					var row_val = cells[idx.y]
					if not (row_val is Array):
						continue
					var row: Array = row_val
					if idx.x < 0 or idx.x >= row.size():
						continue
					if not (row[idx.x] is Dictionary):
						continue
					var cell: Dictionary = row[idx.x]
					cell["structure"] = {}
					row[idx.x] = cell
					cells[idx.y] = row
		restaurants.erase(rid)

	map["restaurants"] = restaurants
	map["cells"] = cells
	state.map = map
	RoadGraphCacheClass.invalidate_road_graph(state)
	player["restaurants"] = []

static func _remove_player_marketing(state: GameState, player_id: int) -> void:
	if state == null:
		return
	if state.marketing_instances is Array:
		var remaining: Array[Dictionary] = []
		for inst_val in state.marketing_instances:
			if not (inst_val is Dictionary):
				continue
			var inst: Dictionary = inst_val
			if int(inst.get("owner", -1)) == player_id:
				continue
			remaining.append(inst.duplicate(true))
		state.marketing_instances = remaining

	if state.map is Dictionary:
		var map: Dictionary = state.map
		if map.has("marketing_placements") and (map["marketing_placements"] is Dictionary):
			var places: Dictionary = map["marketing_placements"]
			var keys: Array = places.keys()
			for k in keys:
				var p_val = places.get(k, null)
				if not (p_val is Dictionary):
					continue
				var p: Dictionary = p_val
				if int(p.get("owner", -1)) == player_id:
					places.erase(k)
			map["marketing_placements"] = places
			state.map = map

static func _clear_player_misc_assets(player: Dictionary) -> void:
	player["banned_employee_ids"] = []
	player["can_peek_all_reserve_cards"] = false
	player["multi_trainer_on_one"] = false
	player["ceo_cfo_ability_start_round"] = -1

static func _plan_pending_phase_actions_after_forfeit(state: GameState, player_id: int) -> Result:
	if state == null or not (state.round_state is Dictionary):
		return Result.success(null)
	var rs: Dictionary = state.round_state
	if not rs.has("pending_phase_actions"):
		return Result.success(null)
	var ppa_val = rs.get("pending_phase_actions", null)
	if not (ppa_val is Dictionary):
		return Result.failure("forfeit_player: round_state.pending_phase_actions 类型错误（期望 Dictionary）")
	var ppa: Dictionary = ppa_val
	var filtered_all: Dictionary = {}
	for phase_name in ppa.keys():
		var arr_val = ppa.get(phase_name, null)
		if not (arr_val is Array):
			return Result.failure("forfeit_player: round_state.pending_phase_actions[%s] 类型错误（期望 Array）" % str(phase_name))
		var arr: Array = arr_val
		var filtered: Array = []
		for i in range(arr.size()):
			var item_val = arr[i]
			if item_val is int:
				if int(item_val) != player_id:
					filtered.append(int(item_val))
				continue
			if item_val is float:
				var f: float = float(item_val)
				if f != floor(f):
					return Result.failure("forfeit_player: round_state.pending_phase_actions[%s][%d] 类型错误（期望 int/float 整数）" % [str(phase_name), i])
				if int(f) != player_id:
					filtered.append(int(f))
				continue
			if item_val is Dictionary:
				var item: Dictionary = item_val
				var pid_val = item.get("player_id", null)
				if not (pid_val is int or pid_val is float):
					return Result.failure("forfeit_player: round_state.pending_phase_actions[%s][%d].player_id 类型错误（期望 int/float）" % [str(phase_name), i])
				if int(pid_val) != player_id:
					filtered.append(item)
				continue
			return Result.failure("forfeit_player: round_state.pending_phase_actions[%s][%d] 类型错误（期望 int/float/Dictionary）" % [str(phase_name), i])
		filtered_all[phase_name] = filtered
	return Result.success(filtered_all)

static func _plan_online_dinnertime_confirmed_players_after_forfeit(state: GameState, player_id: int) -> Result:
	if state == null or not (state.round_state is Dictionary):
		return Result.success(null)
	var rs: Dictionary = state.round_state
	if not rs.has(ONLINE_DINNERTIME_CONFIRMED_PLAYERS_KEY):
		return Result.success(null)
	var confirmed_val = rs.get(ONLINE_DINNERTIME_CONFIRMED_PLAYERS_KEY, null)
	if not (confirmed_val is Array):
		return Result.failure("forfeit_player: round_state.%s 类型错误（期望 Array）" % ONLINE_DINNERTIME_CONFIRMED_PLAYERS_KEY)
	var confirmed: Array = Array(confirmed_val).duplicate(true)
	if player_id >= 0 and player_id < confirmed.size():
		confirmed[player_id] = true
	return Result.success(confirmed)

static func _maybe_finish_game_if_last_active_player_remains(state: GameState, forfeited_player_id: int) -> void:
	if state == null or not (state.players is Array):
		return

	var active_player_ids: Array[int] = []
	for pid in range(state.players.size()):
		var player_val = state.players[pid]
		if not (player_val is Dictionary):
			continue
		var live_player: Dictionary = player_val
		if bool(live_player.get("forfeited", false)):
			continue
		active_player_ids.append(pid)
		if active_player_ids.size() > 1:
			return

	var phase_before := str(state.phase)
	state.phase = DefsClass.PHASE_GAME_OVER
	state.sub_phase = ""
	if not (state.round_state is Dictionary):
		state.round_state = {}

	var winner_player_id := -1
	if active_player_ids.size() == 1:
		winner_player_id = int(active_player_ids[0])
		var winner_turn_index := state.turn_order.find(winner_player_id)
		if winner_turn_index >= 0:
			state.current_player_index = winner_turn_index
	elif not state.turn_order.is_empty():
		state.current_player_index = clampi(int(state.current_player_index), 0, state.turn_order.size() - 1)

	var game_over: Dictionary = {}
	if state.round_state.has("game_over") and (state.round_state["game_over"] is Dictionary):
		game_over = Dictionary(state.round_state["game_over"]).duplicate(true)
	game_over["reason"] = "last_player_standing"
	game_over["round"] = int(state.round_number)
	game_over["phase"] = phase_before
	game_over["forfeited_player_id"] = int(forfeited_player_id)
	if winner_player_id >= 0:
		game_over["winner_player_id"] = winner_player_id
	else:
		game_over.erase("winner_player_id")
	state.round_state["game_over"] = game_over
