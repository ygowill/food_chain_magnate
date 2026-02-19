# 弃权（联机：掉线玩家）
# - 移除玩家资产（餐厅/营销板件/员工/库存/里程碑/现金等）
# - 保留：房屋/花园（地图自带需求源）
# - 约束：为避免破坏引擎不变量与规则假设，保留 CEO（不可移除）
class_name ForfeitPlayerAction
extends ActionExecutor

const CoordsClass = preload("res://core/map/map_runtime/coords.gd")
const RoadGraphCacheClass = preload("res://core/map/map_runtime/road_graph_cache.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
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

	player["forfeited"] = true

	_remove_player_cash(state, player)
	_remove_player_employees(state, player)
	_remove_player_inventory(player)
	_remove_player_milestones(player)
	_remove_player_restaurants(state, player)
	_remove_player_marketing(state, player_id)
	_clear_player_misc_assets(player)
	_remove_player_from_pending_phase_actions(state, player_id)

	state.players[player_id] = player
	return Result.success({"player_id": player_id})

static func _remove_player_cash(state: GameState, player: Dictionary) -> void:
	var cash := int(player.get("cash", 0))
	if cash < 0:
		cash = 0
	player["cash"] = 0

	if state != null and (state.bank is Dictionary):
		var bank: Dictionary = state.bank
		var removed := int(bank.get("removed_total", 0))
		bank["removed_total"] = removed + cash
		state.bank = bank

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

static func _remove_player_from_pending_phase_actions(state: GameState, player_id: int) -> void:
	if state == null or not (state.round_state is Dictionary):
		return
	var rs: Dictionary = state.round_state
	if not rs.has("pending_phase_actions") or not (rs["pending_phase_actions"] is Dictionary):
		return
	var ppa: Dictionary = rs["pending_phase_actions"]
	for phase_name in ppa.keys():
		var arr_val = ppa.get(phase_name, null)
		if not (arr_val is Array):
			continue
		var arr: Array = arr_val
		var filtered: Array = []
		for item_val in arr:
			if item_val is int and int(item_val) == player_id:
				continue
			if item_val is float and float(item_val) == floor(float(item_val)) and int(item_val) == player_id:
				continue
			if item_val is Dictionary:
				var item: Dictionary = item_val
				var pid_val = item.get("player_id", null)
				if pid_val is int and int(pid_val) == player_id:
					continue
				if pid_val is float and float(pid_val) == floor(float(pid_val)) and int(pid_val) == player_id:
					continue
			filtered.append(item_val)
		ppa[phase_name] = filtered
	rs["pending_phase_actions"] = ppa
	if rs.has(ONLINE_DINNERTIME_CONFIRMED_PLAYERS_KEY):
		var confirmed_val = rs.get(ONLINE_DINNERTIME_CONFIRMED_PLAYERS_KEY, null)
		if confirmed_val is Array:
			var confirmed: Array = Array(confirmed_val)
			if player_id >= 0 and player_id < confirmed.size():
				confirmed[player_id] = true
				rs[ONLINE_DINNERTIME_CONFIRMED_PLAYERS_KEY] = confirmed
	state.round_state = rs
