# 游戏动作调试命令（UI/开发工具）
# 将游戏中的所有动作接入调试命令系统
extends RefCounted

const ActionIdsClass = preload("res://core/actions/action_ids.gd")

static func register_all(registry: DebugCommandRegistry) -> void:
	# 阶段管理
	registry.register("skip_sub", _cmd_skip_sub_phase.bind(registry), "跳过子阶段", "skip_sub <player>", ["player"])
	registry.register("choose_order", _cmd_choose_order.bind(registry), "选择顺序位置", "choose_order <player> <position>", ["player", "position"])
	registry.register("end_turn", _cmd_end_turn.bind(registry), "结束回合", "end_turn <player>", ["player"])

	# 员工管理
	registry.register("recruit", _cmd_recruit.bind(registry), "招聘员工", "recruit <player> <employee_type>", ["player", "employee_type"])
	registry.register("train", _cmd_train.bind(registry), "培训员工", "train <player> <from_type> <to_type>", ["player", "from_type", "to_type"])
	registry.register("fire", _cmd_fire.bind(registry), "解雇员工", "fire <player> <employee_id>", ["player", "employee_id"])

	# 资源生产
	registry.register("produce", _cmd_produce.bind(registry), "增加食物库存（调试）", "produce <player> <product> [amount]", ["player", "product", "amount"])
	registry.register("procure", _cmd_procure.bind(registry), "增加饮料库存（调试）", "procure <player> <product> [amount]", ["player", "product", "amount"])

	# 地图操作
	registry.register("place_restaurant", _cmd_place_restaurant.bind(registry), "放置餐厅", "place_restaurant <player> <x> <y> [rotation]", ["player", "x", "y", "rotation"])
	registry.register("place_house", _cmd_place_house.bind(registry), "放置房屋", "place_house <player> <x> <y> [house_number] [rotation]", ["player", "x", "y", "house_number", "rotation"])
	registry.register("move_restaurant", _cmd_move_restaurant.bind(registry), "移动餐厅", "move_restaurant <player> <restaurant_id> <x> <y> [rotation]", ["player", "restaurant_id", "x", "y", "rotation"])
	registry.register("add_garden", _cmd_add_garden.bind(registry), "添加花园", "add_garden <player> <house_id> <direction>", ["player", "house_id", "direction"])

	# 营销系统
	registry.register("marketing", _cmd_marketing.bind(registry), "发起营销", "marketing <player> <employee_type> <board_number> <product> <x> <y>", ["player", "employee_type", "board_number", "product", "x", "y"])
	registry.register("add_house_demand", _cmd_add_house_demand.bind(registry), "给房屋增加需求", "add_house_demand <house_id> <product> [amount] [from_player] [marketing_type] [board_number]", ["house_id", "product", "amount", "from_player", "marketing_type", "board_number"])

	# 价格设定
	registry.register("set_price", _cmd_set_price.bind(registry), "设定价格（-$1）", "set_price <player>", ["player"])
	registry.register("set_discount", _cmd_set_discount.bind(registry), "设定折扣（-$3）", "set_discount <player>", ["player"])
	registry.register("set_luxury", _cmd_set_luxury.bind(registry), "设定奢侈品价格（+$10）", "set_luxury <player>", ["player"])

static func _mark_debug_force(cmd: Command) -> void:
	if not DebugFlags.is_debug_mode():
		return
	if not DebugFlags.force_execute_commands:
		return
	if not (cmd.metadata is Dictionary):
		cmd.metadata = {}
	cmd.metadata["debug_force"] = true

static func _parse_player_id_arg(arg, state: GameState) -> Result:
	if state == null:
		return Result.failure("游戏状态为空")
	var player_count := state.players.size()
	if player_count <= 0:
		return Result.failure("玩家数量无效: %d" % player_count)

	var token := str(arg).strip_edges()
	if token.is_empty():
		return Result.failure("player 不能为空")

	var lower := token.to_lower()
	if lower.begins_with("id:"):
		var id_str := token.substr(3).strip_edges()
		if not id_str.is_valid_int():
			return Result.failure("player_id 格式错误: %s" % token)
		var pid := int(id_str)
		if pid < 0 or pid >= player_count:
			return Result.failure("无效的 player_id: %d（有效范围 0..%d）" % [pid, player_count - 1])
		return Result.success(pid)

	if lower.begins_with("pid:"):
		var id_str2 := token.substr(4).strip_edges()
		if not id_str2.is_valid_int():
			return Result.failure("player_id 格式错误: %s" % token)
		var pid2 := int(id_str2)
		if pid2 < 0 or pid2 >= player_count:
			return Result.failure("无效的 player_id: %d（有效范围 0..%d）" % [pid2, player_count - 1])
		return Result.success(pid2)

	# 默认按玩家顺位 1..N 解析（不允许“当前玩家”隐式行为）
	if not token.is_valid_int():
		return Result.failure("player 必须为 1..%d（或使用 id:<player_id>）" % player_count)
	var pnum := int(token)
	if pnum < 1 or pnum > player_count:
		return Result.failure("无效的玩家顺位: %d（有效范围 1..%d）" % [pnum, player_count])
	return Result.success(pnum - 1)

# === 阶段管理 ===

static func _cmd_skip_sub_phase(args: Array, registry: DebugCommandRegistry) -> Result:
	var engine := registry.get_game_engine()
	if engine == null:
		return Result.failure("游戏引擎未初始化")

	if args.is_empty():
		return Result.failure("用法: skip_sub <player>")

	var state := engine.get_state()
	var player_id_r := _parse_player_id_arg(args[0], state)
	if not player_id_r.ok:
		return player_id_r
	var player_id := int(player_id_r.value)
	var cmd := Command.create(ActionIdsClass.SKIP_SUB_PHASE, player_id)
	_mark_debug_force(cmd)
	var result := engine.execute_command(cmd)

	if not result.ok:
		return result

	return Result.success("已跳过子阶段")

static func _cmd_choose_order(args: Array, registry: DebugCommandRegistry) -> Result:
	var engine := registry.get_game_engine()
	if engine == null:
		return Result.failure("游戏引擎未初始化")

	if args.size() < 2:
		return Result.failure("用法: choose_order <player> <position>")

	var state := engine.get_state()
	var player_id_r := _parse_player_id_arg(args[0], state)
	if not player_id_r.ok:
		return player_id_r
	var player_id := int(player_id_r.value)

	var position := int(args[1])
	var cmd := Command.create("choose_turn_order", player_id, {"position": position})
	_mark_debug_force(cmd)
	var result := engine.execute_command(cmd)

	if not result.ok:
		return result

	return Result.success("已选择顺序位置: %d" % position)

static func _cmd_end_turn(args: Array, registry: DebugCommandRegistry) -> Result:
	var engine := registry.get_game_engine()
	if engine == null:
		return Result.failure("游戏引擎未初始化")

	if args.is_empty():
		return Result.failure("用法: end_turn <player>")

	var state := engine.get_state()
	var player_id_r := _parse_player_id_arg(args[0], state)
	if not player_id_r.ok:
		return player_id_r
	var player_id := int(player_id_r.value)
	var cmd := Command.create(ActionIdsClass.END_TURN, player_id)
	_mark_debug_force(cmd)
	var result := engine.execute_command(cmd)

	if not result.ok:
		return result

	return Result.success("已结束回合")

# === 员工管理 ===

static func _cmd_recruit(args: Array, registry: DebugCommandRegistry) -> Result:
	var engine := registry.get_game_engine()
	if engine == null:
		return Result.failure("游戏引擎未初始化")

	if args.size() < 2:
		return Result.failure("用法: recruit <player> <employee_type>")

	var state := engine.get_state()
	var player_id_r := _parse_player_id_arg(args[0], state)
	if not player_id_r.ok:
		return player_id_r
	var player_id := int(player_id_r.value)

	var employee_type := str(args[1])
	var cmd := Command.create("recruit", player_id, {"employee_type": employee_type})
	_mark_debug_force(cmd)
	var result := engine.execute_command(cmd)

	if not result.ok:
		return result

	return Result.success("已招聘: %s" % employee_type)

static func _cmd_train(args: Array, registry: DebugCommandRegistry) -> Result:
	var engine := registry.get_game_engine()
	if engine == null:
		return Result.failure("游戏引擎未初始化")

	if args.size() < 3:
		return Result.failure("用法: train <player> <from_type> <to_type>")

	var state := engine.get_state()
	var player_id_r := _parse_player_id_arg(args[0], state)
	if not player_id_r.ok:
		return player_id_r
	var player_id := int(player_id_r.value)

	var from_type := str(args[1])
	var to_type := str(args[2])
	var cmd := Command.create("train", player_id, {
		"from_employee": from_type,
		"to_employee": to_type
	})
	_mark_debug_force(cmd)
	var result := engine.execute_command(cmd)

	if not result.ok:
		return result

	return Result.success("已培训: %s -> %s" % [from_type, to_type])

static func _cmd_fire(args: Array, registry: DebugCommandRegistry) -> Result:
	var engine := registry.get_game_engine()
	if engine == null:
		return Result.failure("游戏引擎未初始化")

	if args.size() < 2:
		return Result.failure("用法: fire <player> <employee_id>")

	var state := engine.get_state()
	var player_id_r := _parse_player_id_arg(args[0], state)
	if not player_id_r.ok:
		return player_id_r
	var player_id := int(player_id_r.value)

	var employee_id := str(args[1])
	var cmd := Command.create("fire", player_id, {"employee_id": employee_id})
	_mark_debug_force(cmd)
	var result := engine.execute_command(cmd)

	if not result.ok:
		return result

	return Result.success("已解雇: %s" % employee_id)

# === 资源生产 ===

static func _cmd_produce(args: Array, registry: DebugCommandRegistry) -> Result:
	var engine := registry.get_game_engine()
	if engine == null:
		return Result.failure("游戏引擎未初始化")

	if args.size() < 2:
		return Result.failure("用法: produce <player> <product> [amount]")

	var state := engine.get_state()
	var player_id_r := _parse_player_id_arg(args[0], state)
	if not player_id_r.ok:
		return player_id_r
	var player_id := int(player_id_r.value)

	var product := str(args[1]).strip_edges()
	if product.is_empty():
		return Result.failure("product 不能为空")
	var amount := 1
	if args.size() > 2 and not str(args[2]).is_empty():
		amount = int(args[2])
	if amount < 0:
		return Result.failure("amount 不能为负: %d" % amount)

	# 通过 internal debug action 修改状态（保持命令历史/回放/不变量）
	var cmd := Command.create_system("debug_add_inventory", {"player_id": player_id, "product": product, "amount": amount})
	_mark_debug_force(cmd)
	var result := engine.execute_command(cmd)

	if not result.ok:
		return result

	return Result.success("已增加库存: %s x%d (玩家 %d)" % [product, amount, player_id])

static func _cmd_procure(args: Array, registry: DebugCommandRegistry) -> Result:
	var engine := registry.get_game_engine()
	if engine == null:
		return Result.failure("游戏引擎未初始化")

	if args.size() < 2:
		return Result.failure("用法: procure <player> <product> [amount]")

	var state := engine.get_state()
	var player_id_r := _parse_player_id_arg(args[0], state)
	if not player_id_r.ok:
		return player_id_r
	var player_id := int(player_id_r.value)

	var product := str(args[1]).strip_edges()
	if product.is_empty():
		return Result.failure("product 不能为空")
	var amount := 1
	if args.size() > 2 and not str(args[2]).is_empty():
		amount = int(args[2])
	if amount < 0:
		return Result.failure("amount 不能为负: %d" % amount)

	# 通过 internal debug action 修改状态（保持命令历史/回放/不变量）
	var cmd := Command.create_system("debug_add_inventory", {"player_id": player_id, "product": product, "amount": amount})
	_mark_debug_force(cmd)
	var result := engine.execute_command(cmd)

	if not result.ok:
		return result

	return Result.success("已增加库存: %s x%d (玩家 %d)" % [product, amount, player_id])

# === 地图操作 ===

static func _cmd_place_restaurant(args: Array, registry: DebugCommandRegistry) -> Result:
	var engine := registry.get_game_engine()
	if engine == null:
		return Result.failure("游戏引擎未初始化")

	if args.size() < 3:
		return Result.failure("用法: place_restaurant <player> <x> <y> [rotation]")

	var state := engine.get_state()
	var player_id_r := _parse_player_id_arg(args[0], state)
	if not player_id_r.ok:
		return player_id_r
	var player_id := int(player_id_r.value)

	var x := int(args[1])
	var y := int(args[2])
	var rotation := int(args[3]) if args.size() > 3 else 0

	var cmd := Command.create("place_restaurant", player_id, {
		"position": [x, y],
		"rotation": rotation
	})
	_mark_debug_force(cmd)
	var result := engine.execute_command(cmd)

	if not result.ok:
		return result

	return Result.success("已放置餐厅: (%d, %d) 旋转: %d" % [x, y, rotation])

static func _cmd_place_house(args: Array, registry: DebugCommandRegistry) -> Result:
	var engine := registry.get_game_engine()
	if engine == null:
		return Result.failure("游戏引擎未初始化")

	if args.size() < 3:
		return Result.failure("用法: place_house <player> <x> <y> [house_number] [rotation]")

	var state := engine.get_state()
	var player_id_r := _parse_player_id_arg(args[0], state)
	if not player_id_r.ok:
		return player_id_r
	var player_id := int(player_id_r.value)

	var x := int(args[1])
	var y := int(args[2])
	var house_number := -1
	var rotation := 0
	if args.size() > 3:
		var a3 := int(args[3])
		# Backward compatible: old usage was place_house <x> <y> [rotation]
		if a3 in [0, 90, 180, 270]:
			rotation = a3
		else:
			house_number = a3
			rotation = int(args[4]) if args.size() > 4 else 0
	if house_number <= 0:
		# Debug fallback: choose the smallest remaining house_number when not provided.
		var supply_val = state.map.get("house_number_supply_remaining", null) if state != null and (state.map is Dictionary) else null
		var supply: Array[int] = []
		if supply_val is Array:
			for v in Array(supply_val):
				if v is int:
					supply.append(int(v))
				elif v is float:
					var f: float = float(v)
					if f == floor(f):
						supply.append(int(f))
		else:
			supply = [1, 3, 6, 9, 11, 14, 17, 19]
		supply.sort()
		if supply.is_empty():
			return Result.failure("可放置房屋编号已用完")
		house_number = int(supply[0])

	var cmd := Command.create("place_house", player_id, {
		"position": [x, y],
		"rotation": rotation,
		"house_number": house_number
	})
	_mark_debug_force(cmd)
	var result := engine.execute_command(cmd)

	if not result.ok:
		return result

	return Result.success("已放置房屋: 编号=%d 位置=(%d,%d) 旋转=%d" % [house_number, x, y, rotation])

static func _cmd_move_restaurant(args: Array, registry: DebugCommandRegistry) -> Result:
	var engine := registry.get_game_engine()
	if engine == null:
		return Result.failure("游戏引擎未初始化")

	if args.size() < 4:
		return Result.failure("用法: move_restaurant <player> <restaurant_id> <x> <y> [rotation]")

	var state := engine.get_state()
	var player_id_r := _parse_player_id_arg(args[0], state)
	if not player_id_r.ok:
		return player_id_r
	var player_id := int(player_id_r.value)

	var restaurant_id := str(args[1])
	var x := int(args[2])
	var y := int(args[3])
	var rotation := int(args[4]) if args.size() > 4 else 0

	var cmd := Command.create("move_restaurant", player_id, {
		"restaurant_id": restaurant_id,
		"position": [x, y],
		"rotation": rotation
	})
	_mark_debug_force(cmd)
	var result := engine.execute_command(cmd)

	if not result.ok:
		return result

	return Result.success("已移动餐厅 %s 到: (%d, %d)" % [restaurant_id, x, y])

static func _cmd_add_garden(args: Array, registry: DebugCommandRegistry) -> Result:
	var engine := registry.get_game_engine()
	if engine == null:
		return Result.failure("游戏引擎未初始化")

	if args.size() < 3:
		return Result.failure("用法: add_garden <player> <house_id> <direction>")

	var state := engine.get_state()
	var player_id_r := _parse_player_id_arg(args[0], state)
	if not player_id_r.ok:
		return player_id_r
	var player_id := int(player_id_r.value)

	var house_id := str(args[1])
	var direction := str(args[2]).to_upper()

	var cmd := Command.create("add_garden", player_id, {
		"house_id": house_id,
		"direction": direction
	})
	_mark_debug_force(cmd)
	var result := engine.execute_command(cmd)

	if not result.ok:
		return result

	return Result.success("已为房屋 %s 添加花园: %s" % [house_id, direction])

# === 营销系统 ===

static func _cmd_marketing(args: Array, registry: DebugCommandRegistry) -> Result:
	var engine := registry.get_game_engine()
	if engine == null:
		return Result.failure("游戏引擎未初始化")

	if args.size() < 6:
		return Result.failure("用法: marketing <player> <employee_type> <board_number> <product> <x> <y>")

	var state := engine.get_state()
	var player_id_r := _parse_player_id_arg(args[0], state)
	if not player_id_r.ok:
		return player_id_r
	var player_id := int(player_id_r.value)

	var employee_type := str(args[1])
	var board_number := int(args[2])
	var product := str(args[3])
	var x := int(args[4])
	var y := int(args[5])

	var cmd := Command.create("initiate_marketing", player_id, {
		"employee_type": employee_type,
		"board_number": board_number,
		"product": product,
		"position": [x, y]
	})
	_mark_debug_force(cmd)
	var result := engine.execute_command(cmd)

	if not result.ok:
		return result

	return Result.success("已发起营销: %s 在 (%d, %d)" % [product, x, y])

static func _cmd_add_house_demand(args: Array, registry: DebugCommandRegistry) -> Result:
	var engine := registry.get_game_engine()
	if engine == null:
		return Result.failure("游戏引擎未初始化")

	if args.size() < 2:
		return Result.failure("用法: add_house_demand <house_id> <product> [amount] [from_player] [marketing_type] [board_number]")

	var house_id := str(args[0])
	var product := str(args[1])

	var amount := 1
	if args.size() > 2 and not str(args[2]).is_empty():
		amount = int(args[2])

	var state := engine.get_state()
	var from_player := -1
	if args.size() > 3 and not str(args[3]).is_empty():
		var from_player_r := _parse_player_id_arg(args[3], state)
		if not from_player_r.ok:
			return from_player_r
		from_player = int(from_player_r.value)

	var marketing_type := "debug"
	if args.size() > 4 and not str(args[4]).is_empty():
		marketing_type = str(args[4])

	var board_number := 0
	if args.size() > 5 and not str(args[5]).is_empty():
		board_number = int(args[5])

	var cmd := Command.create_system("debug_add_house_demand", {
		"house_id": house_id,
		"product": product,
		"amount": amount,
		"from_player": from_player,
		"marketing_type": marketing_type,
		"board_number": board_number,
	})
	_mark_debug_force(cmd)
	var result := engine.execute_command(cmd)

	if not result.ok:
		return result

	var added := int(result.value) if (result.value is int or result.value is float) else 0
	return Result.success("已为房屋 %s 增加需求: %s x%d (added=%d, from_player=%d, type=%s, board=%d)" % [house_id, product, amount, added, from_player, marketing_type, board_number])

# === 价格设定 ===

static func _cmd_set_price(args: Array, registry: DebugCommandRegistry) -> Result:
	var engine := registry.get_game_engine()
	if engine == null:
		return Result.failure("游戏引擎未初始化")

	var state := engine.get_state()
	if args.is_empty():
		return Result.failure("用法: set_price <player>")
	var player_id_r := _parse_player_id_arg(args[0], state)
	if not player_id_r.ok:
		return player_id_r
	var player_id := int(player_id_r.value)
	var cmd := Command.create("set_price", player_id)
	_mark_debug_force(cmd)
	var result := engine.execute_command(cmd)

	if not result.ok:
		return result

	return Result.success("已设定价格（-$1）")

static func _cmd_set_discount(args: Array, registry: DebugCommandRegistry) -> Result:
	var engine := registry.get_game_engine()
	if engine == null:
		return Result.failure("游戏引擎未初始化")

	var state := engine.get_state()
	if args.is_empty():
		return Result.failure("用法: set_discount <player>")
	var player_id_r := _parse_player_id_arg(args[0], state)
	if not player_id_r.ok:
		return player_id_r
	var player_id := int(player_id_r.value)
	var cmd := Command.create("set_discount", player_id)
	_mark_debug_force(cmd)
	var result := engine.execute_command(cmd)

	if not result.ok:
		return result

	return Result.success("已设定折扣（-$3）")

static func _cmd_set_luxury(args: Array, registry: DebugCommandRegistry) -> Result:
	var engine := registry.get_game_engine()
	if engine == null:
		return Result.failure("游戏引擎未初始化")

	var state := engine.get_state()
	if args.is_empty():
		return Result.failure("用法: set_luxury <player>")
	var player_id_r := _parse_player_id_arg(args[0], state)
	if not player_id_r.ok:
		return player_id_r
	var player_id := int(player_id_r.value)
	var cmd := Command.create("set_luxury_price", player_id)
	_mark_debug_force(cmd)
	var result := engine.execute_command(cmd)

	if not result.ok:
		return result

	return Result.success("已设定奢侈品价格（+$10）")
