# 游戏动作调试命令
# 将游戏中的所有动作接入调试命令系统
class_name DebugActionCommands
extends RefCounted

static func register_all(registry: DebugCommandRegistry) -> void:
	# 阶段管理
	registry.register("skip_sub", _cmd_skip_sub_phase.bind(registry), "跳过子阶段", "skip_sub")
	registry.register("choose_order", _cmd_choose_order.bind(registry), "选择顺序位置", "choose_order <position>", ["position"])
	registry.register("end_turn", _cmd_end_turn.bind(registry), "结束回合", "end_turn")

	# 员工管理
	registry.register("recruit", _cmd_recruit.bind(registry), "招聘员工", "recruit <employee_type>", ["employee_type"])
	registry.register("train", _cmd_train.bind(registry), "培训员工", "train <from_type> <to_type>", ["from_type", "to_type"])
	registry.register("fire", _cmd_fire.bind(registry), "解雇员工", "fire <employee_id>", ["employee_id"])

	# 资源生产
	registry.register("produce", _cmd_produce.bind(registry), "生产食物", "produce <employee_type>", ["employee_type"])
	registry.register("procure", _cmd_procure.bind(registry), "采购饮料", "procure <employee_type>", ["employee_type"])

	# 地图操作
	registry.register("place_restaurant", _cmd_place_restaurant.bind(registry), "放置餐厅", "place_restaurant <x> <y> [rotation]", ["x", "y", "rotation"])
	registry.register("place_house", _cmd_place_house.bind(registry), "放置房屋", "place_house <x> <y> [rotation]", ["x", "y", "rotation"])
	registry.register("move_restaurant", _cmd_move_restaurant.bind(registry), "移动餐厅", "move_restaurant <restaurant_id> <x> <y> [rotation]", ["restaurant_id", "x", "y", "rotation"])
	registry.register("add_garden", _cmd_add_garden.bind(registry), "添加花园", "add_garden <house_id> <direction>", ["house_id", "direction"])

	# 营销系统
	registry.register("marketing", _cmd_marketing.bind(registry), "发起营销", "marketing <employee_type> <board_number> <product> <x> <y>", ["employee_type", "board_number", "product", "x", "y"])

	# 价格设定
	registry.register("set_price", _cmd_set_price.bind(registry), "设定价格（-$1）", "set_price")
	registry.register("set_discount", _cmd_set_discount.bind(registry), "设定折扣（-$3）", "set_discount")
	registry.register("set_luxury", _cmd_set_luxury.bind(registry), "设定奢侈品价格（+$10）", "set_luxury")

static func _mark_debug_force(cmd: Command) -> void:
	if not DebugFlags.is_debug_mode():
		return
	if not DebugFlags.force_execute_commands:
		return
	if not (cmd.metadata is Dictionary):
		cmd.metadata = {}
	cmd.metadata["debug_force"] = true

# === 阶段管理 ===

static func _cmd_skip_sub_phase(args: Array, registry: DebugCommandRegistry) -> Result:
	var engine := registry.get_game_engine()
	if engine == null:
		return Result.failure("游戏引擎未初始化")

	var state := engine.get_state()
	var cmd := Command.create("skip_sub_phase", state.get_current_player_id())
	_mark_debug_force(cmd)
	var result := engine.execute_command(cmd)

	if not result.ok:
		return result

	return Result.success("已跳过子阶段")

static func _cmd_choose_order(args: Array, registry: DebugCommandRegistry) -> Result:
	var engine := registry.get_game_engine()
	if engine == null:
		return Result.failure("游戏引擎未初始化")

	if args.is_empty():
		return Result.failure("用法: choose_order <position>")

	var position := int(args[0])
	var state := engine.get_state()
	var cmd := Command.create("choose_turn_order", state.get_current_player_id(), {"position": position})
	_mark_debug_force(cmd)
	var result := engine.execute_command(cmd)

	if not result.ok:
		return result

	return Result.success("已选择顺序位置: %d" % position)

static func _cmd_end_turn(args: Array, registry: DebugCommandRegistry) -> Result:
	var engine := registry.get_game_engine()
	if engine == null:
		return Result.failure("游戏引擎未初始化")

	var state := engine.get_state()
	var cmd := Command.create("end_turn", state.get_current_player_id())
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

	if args.is_empty():
		return Result.failure("用法: recruit <employee_type>")

	var employee_type := str(args[0])
	var state := engine.get_state()
	var cmd := Command.create("recruit", state.get_current_player_id(), {"employee_type": employee_type})
	_mark_debug_force(cmd)
	var result := engine.execute_command(cmd)

	if not result.ok:
		return result

	return Result.success("已招聘: %s" % employee_type)

static func _cmd_train(args: Array, registry: DebugCommandRegistry) -> Result:
	var engine := registry.get_game_engine()
	if engine == null:
		return Result.failure("游戏引擎未初始化")

	if args.size() < 2:
		return Result.failure("用法: train <from_type> <to_type>")

	var from_type := str(args[0])
	var to_type := str(args[1])
	var state := engine.get_state()
	var cmd := Command.create("train", state.get_current_player_id(), {
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

	if args.is_empty():
		return Result.failure("用法: fire <employee_id>")

	var employee_id := str(args[0])
	var state := engine.get_state()
	var cmd := Command.create("fire", state.get_current_player_id(), {"employee_id": employee_id})
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

	if args.is_empty():
		return Result.failure("用法: produce <employee_type>")

	var employee_type := str(args[0])
	var state := engine.get_state()
	var cmd := Command.create("produce_food", state.get_current_player_id(), {"employee_type": employee_type})
	_mark_debug_force(cmd)
	var result := engine.execute_command(cmd)

	if not result.ok:
		return result

	return Result.success("已生产食物: %s" % employee_type)

static func _cmd_procure(args: Array, registry: DebugCommandRegistry) -> Result:
	var engine := registry.get_game_engine()
	if engine == null:
		return Result.failure("游戏引擎未初始化")

	if args.is_empty():
		return Result.failure("用法: procure <employee_type>")

	var employee_type := str(args[0])
	var state := engine.get_state()
	var cmd := Command.create("procure_drinks", state.get_current_player_id(), {"employee_type": employee_type})
	_mark_debug_force(cmd)
	var result := engine.execute_command(cmd)

	if not result.ok:
		return result

	return Result.success("已采购饮料: %s" % employee_type)

# === 地图操作 ===

static func _cmd_place_restaurant(args: Array, registry: DebugCommandRegistry) -> Result:
	var engine := registry.get_game_engine()
	if engine == null:
		return Result.failure("游戏引擎未初始化")

	if args.size() < 2:
		return Result.failure("用法: place_restaurant <x> <y> [rotation]")

	var x := int(args[0])
	var y := int(args[1])
	var rotation := int(args[2]) if args.size() > 2 else 0

	var state := engine.get_state()
	var cmd := Command.create("place_restaurant", state.get_current_player_id(), {
		"position": {"x": x, "y": y},
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

	if args.size() < 2:
		return Result.failure("用法: place_house <x> <y> [rotation]")

	var x := int(args[0])
	var y := int(args[1])
	var rotation := int(args[2]) if args.size() > 2 else 0

	var state := engine.get_state()
	var cmd := Command.create("place_house", state.get_current_player_id(), {
		"position": {"x": x, "y": y},
		"rotation": rotation
	})
	_mark_debug_force(cmd)
	var result := engine.execute_command(cmd)

	if not result.ok:
		return result

	return Result.success("已放置房屋: (%d, %d) 旋转: %d" % [x, y, rotation])

static func _cmd_move_restaurant(args: Array, registry: DebugCommandRegistry) -> Result:
	var engine := registry.get_game_engine()
	if engine == null:
		return Result.failure("游戏引擎未初始化")

	if args.size() < 3:
		return Result.failure("用法: move_restaurant <restaurant_id> <x> <y> [rotation]")

	var restaurant_id := str(args[0])
	var x := int(args[1])
	var y := int(args[2])
	var rotation := int(args[3]) if args.size() > 3 else 0

	var state := engine.get_state()
	var cmd := Command.create("move_restaurant", state.get_current_player_id(), {
		"restaurant_id": restaurant_id,
		"position": {"x": x, "y": y},
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

	if args.size() < 2:
		return Result.failure("用法: add_garden <house_id> <direction>")

	var house_id := str(args[0])
	var direction := str(args[1]).to_upper()

	var state := engine.get_state()
	var cmd := Command.create("add_garden", state.get_current_player_id(), {
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

	if args.size() < 5:
		return Result.failure("用法: marketing <employee_type> <board_number> <product> <x> <y>")

	var employee_type := str(args[0])
	var board_number := int(args[1])
	var product := str(args[2])
	var x := int(args[3])
	var y := int(args[4])

	var state := engine.get_state()
	var cmd := Command.create("initiate_marketing", state.get_current_player_id(), {
		"employee_type": employee_type,
		"board_number": board_number,
		"product": product,
		"position": {"x": x, "y": y}
	})
	_mark_debug_force(cmd)
	var result := engine.execute_command(cmd)

	if not result.ok:
		return result

	return Result.success("已发起营销: %s 在 (%d, %d)" % [product, x, y])

# === 价格设定 ===

static func _cmd_set_price(args: Array, registry: DebugCommandRegistry) -> Result:
	var engine := registry.get_game_engine()
	if engine == null:
		return Result.failure("游戏引擎未初始化")

	var state := engine.get_state()
	var cmd := Command.create("set_price", state.get_current_player_id())
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
	var cmd := Command.create("set_discount", state.get_current_player_id())
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
	var cmd := Command.create("set_luxury_price", state.get_current_player_id())
	_mark_debug_force(cmd)
	var result := engine.execute_command(cmd)

	if not result.ok:
		return result

	return Result.success("已设定奢侈品价格（+$10）")
