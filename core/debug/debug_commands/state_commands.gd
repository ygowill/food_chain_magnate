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
	registry.register("marketing", _cmd_marketing.bind(registry), "显示营销实例", "marketing")

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

	var employees = player.get("employees", [])
	if employees is Array:
		lines.append("员工数: %d" % employees.size())
		for emp in employees:
			if emp is Dictionary:
				var emp_id := str(emp.get("employee_id", "?"))
				var trained := bool(emp.get("trained", false))
				var acted := bool(emp.get("acted_this_round", false))
				lines.append("  - %s (训练: %s, 已行动: %s)" % [emp_id, str(trained), str(acted)])

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

	var buildings = map_data.get("buildings", [])
	var building_count: int = buildings.size() if buildings is Array else 0

	var lines: Array[String] = [
		"=== 地图状态 ===",
		"建筑数: %d" % building_count,
	]

	if buildings is Array:
		for b in buildings:
			if b is Dictionary:
				var pos = b.get("position", {})
				var pos_str := "(%d,%d)" % [int(pos.get("x", 0)), int(pos.get("y", 0))] if pos is Dictionary else "?"
				var type_str := str(b.get("type", "?"))
				var owner_id = b.get("owner_id", -1)
				lines.append("  %s @ %s (玩家 %s)" % [type_str, pos_str, str(owner_id)])

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
			var owner := int(inst.get("owner_id", -1))
			var pos = inst.get("position", {})
			var pos_str := "(%d,%d)" % [int(pos.get("x", 0)), int(pos.get("y", 0))] if pos is Dictionary else "?"
			var range_val := int(inst.get("range", 0))
			lines.append("  %s @ %s (玩家 %d, 范围 %d)" % [type_str, pos_str, owner, range_val])

	return Result.success("\n".join(lines))
