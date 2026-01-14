# 状态相关调试命令
class_name DebugStateCommands
extends RefCounted

static func register_all(registry: DebugCommandRegistry) -> void:
	registry.register("state", _cmd_state.bind(registry), "打印当前状态摘要", "state")
	registry.register("dump", _cmd_dump.bind(registry), "导出完整状态", "dump")
	registry.register("hash", _cmd_hash.bind(registry), "显示状态哈希", "hash")
	registry.register("players", _cmd_players.bind(registry), "显示所有玩家信息", "players")
	registry.register("player", _cmd_player.bind(registry), "显示指定玩家信息", "player <id>", ["player_id"])
	registry.register("bank", _cmd_bank.bind(registry), "显示银行状态", "bank")
	registry.register("map", _cmd_map.bind(registry), "显示地图状态", "map")
	registry.register("marketing_list", _cmd_marketing.bind(registry), "显示营销实例", "marketing_list")

static func _cmd_state(args: Array, registry: DebugCommandRegistry) -> Result:
	var engine := registry.get_game_engine()
	if engine == null:
		return Result.failure("游戏引擎未初始化")

	var state := engine.get_state()
	if state == null:
		return Result.failure("游戏状态为空")

	var lines: Array[String] = [
		"=== 游戏状态 ===",
		"回合: %d" % state.round_number,
		"阶段: %s" % state.phase,
		"子阶段: %s" % state.sub_phase,
		"当前玩家: %d" % state.get_current_player_id(),
		"玩家数: %d" % state.players.size(),
		"银行总额: $%d" % state.bank.get("total", 0),
		"命令数: %d" % engine.get_command_history().size(),
		"哈希: %s" % state.compute_hash().substr(0, 16),
	]
	return Result.success("\n".join(lines))

static func _cmd_dump(args: Array, registry: DebugCommandRegistry) -> Result:
	var engine := registry.get_game_engine()
	if engine == null:
		return Result.failure("游戏引擎未初始化")

	return Result.success(engine.dump())

static func _cmd_hash(args: Array, registry: DebugCommandRegistry) -> Result:
	var engine := registry.get_game_engine()
	if engine == null:
		return Result.failure("游戏引擎未初始化")

	var state := engine.get_state()
	if state == null:
		return Result.failure("游戏状态为空")

	return Result.success("状态哈希: %s" % state.compute_hash())

static func _cmd_players(args: Array, registry: DebugCommandRegistry) -> Result:
	var engine := registry.get_game_engine()
	if engine == null:
		return Result.failure("游戏引擎未初始化")

	var state := engine.get_state()
	if state == null:
		return Result.failure("游戏状态为空")

	var lines: Array[String] = ["=== 玩家列表 ==="]
	for i in range(state.players.size()):
		var player: Dictionary = state.players[i]
		var cash: int = int(player.get("cash", 0))
		var employees = player.get("employees", [])
		var employee_count: int = employees.size() if employees is Array else 0
		lines.append("玩家 %d: $%d, 员工数: %d" % [i, cash, employee_count])

	return Result.success("\n".join(lines))

static func _cmd_player(args: Array, registry: DebugCommandRegistry) -> Result:
	var engine := registry.get_game_engine()
	if engine == null:
		return Result.failure("游戏引擎未初始化")

	if args.is_empty():
		return Result.failure("用法: player <id>")

	var player_id := int(args[0])
	var state := engine.get_state()
	if state == null:
		return Result.failure("游戏状态为空")

	if player_id < 0 or player_id >= state.players.size():
		return Result.failure("无效的玩家 ID: %d" % player_id)

	var player: Dictionary = state.players[player_id]
	var lines: Array[String] = [
		"=== 玩家 %d ===" % player_id,
		"现金: $%d" % int(player.get("cash", 0)),
	]

	var employees_val = player.get("employees", [])
	if employees_val is Array:
		var employees: Array = employees_val
		lines.append("在职员工数: %d" % employees.size())
		for emp in employees:
			if emp is String:
				lines.append("  - %s" % str(emp))
			elif emp is Dictionary:
				# 兼容旧格式
				var emp_id := str(Dictionary(emp).get("employee_id", "?"))
				lines.append("  - %s" % emp_id)

	var reserve_val = player.get("reserve_employees", [])
	if reserve_val is Array:
		var reserve: Array = reserve_val
		lines.append("手牌/储备: %d" % reserve.size())

	var busy_val = player.get("busy_marketers", [])
	if busy_val is Array:
		var busy: Array = busy_val
		lines.append("忙碌营销员: %d" % busy.size())

	return Result.success("\n".join(lines))

static func _cmd_bank(args: Array, registry: DebugCommandRegistry) -> Result:
	var engine := registry.get_game_engine()
	if engine == null:
		return Result.failure("游戏引擎未初始化")

	var state := engine.get_state()
	if state == null:
		return Result.failure("游戏状态为空")

	var bank: Dictionary = state.bank
	var lines: Array[String] = [
		"=== 银行状态 ===",
		"总额: $%d" % int(bank.get("total", 0)),
		"已注入: $%d" % int(bank.get("reserve_added_total", 0)),
		"已移除: $%d" % int(bank.get("removed_total", 0)),
	]

	var denominations = bank.get("denominations", {})
	if denominations is Dictionary and not denominations.is_empty():
		lines.append("面额:")
		for denom in denominations.keys():
			lines.append("  $%s: %d 张" % [str(denom), int(denominations[denom])])

	return Result.success("\n".join(lines))

static func _cmd_map(args: Array, registry: DebugCommandRegistry) -> Result:
	var engine := registry.get_game_engine()
	if engine == null:
		return Result.failure("游戏引擎未初始化")

	var state := engine.get_state()
	if state == null:
		return Result.failure("游戏状态为空")

	var map_data = state.map
	if not (map_data is Dictionary):
		return Result.failure("地图数据无效")

	var grid_size_val = map_data.get("grid_size", null)
	var grid_size_str := str(grid_size_val) if (grid_size_val is Vector2i) else str(grid_size_val)

	var tile_placements_val = map_data.get("tile_placements", [])
	var tile_count: int = tile_placements_val.size() if tile_placements_val is Array else 0

	var houses_val = map_data.get("houses", {})
	var house_count: int = houses_val.size() if houses_val is Dictionary else 0

	var restaurants_val = map_data.get("restaurants", {})
	var restaurant_count: int = restaurants_val.size() if restaurants_val is Dictionary else 0

	var marketing_places_val = map_data.get("marketing_placements", {})
	var marketing_place_count: int = marketing_places_val.size() if marketing_places_val is Dictionary else 0

	var lines: Array[String] = [
		"=== 地图状态 ===",
		"grid_size: %s" % grid_size_str,
		"tile_placements: %d" % tile_count,
		"houses: %d" % house_count,
		"restaurants: %d" % restaurant_count,
		"marketing_placements: %d" % marketing_place_count,
	]

	if restaurants_val is Dictionary and not Dictionary(restaurants_val).is_empty():
		lines.append("餐厅（最多显示 8 个）:")
		var ids: Array = Dictionary(restaurants_val).keys()
		ids.sort()
		var shown := 0
		for rid_val in ids:
			if shown >= 8:
				break
			var rid := str(rid_val).strip_edges()
			if rid.is_empty():
				continue
			var r_val = Dictionary(restaurants_val).get(rid, null)
			if not (r_val is Dictionary):
				continue
			var r: Dictionary = r_val
			var owner := int(r.get("owner", -1))
			var anchor = r.get("anchor_pos", null)
			lines.append("  - %s owner=%d anchor=%s" % [rid, owner, str(anchor)])
			shown += 1

	return Result.success("\n".join(lines))

static func _cmd_marketing(args: Array, registry: DebugCommandRegistry) -> Result:
	var engine := registry.get_game_engine()
	if engine == null:
		return Result.failure("游戏引擎未初始化")

	var state := engine.get_state()
	if state == null:
		return Result.failure("游戏状态为空")

	var instances = state.marketing_instances
	if not (instances is Array):
		return Result.failure("营销实例数据无效")

	var lines: Array[String] = [
		"=== 营销实例 ===",
		"数量: %d" % instances.size(),
	]

	for inst in instances:
		if inst is Dictionary:
			var type_str := str(inst.get("type", "?"))
			var owner := int(inst.get("owner", -1))
			var product := str(inst.get("product", ""))
			var wp = inst.get("world_pos", null)
			var pos_str := "(%d,%d)" % [wp.x, wp.y] if (wp is Vector2i) else str(wp)
			var bn := int(inst.get("board_number", -1))
			var rem := int(inst.get("remaining_duration", 0))
			lines.append("  %s #%d %s @ %s (玩家 %d, 剩余 %d)" % [type_str, bn, product, pos_str, owner, rem])

	return Result.success("\n".join(lines))
