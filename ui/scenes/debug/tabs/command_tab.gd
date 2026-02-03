# 命令标签页
# 提供常用调试命令的快捷按钮
extends MarginContainer

const ParamDialogScene = preload("res://ui/scenes/debug/components/param_dialog.tscn")

var _registry: DebugCommandRegistry = null
var _execute_callback: Callable
var _param_dialog: Window = null

@onready var command_content: VBoxContainer = $ScrollContainer/CommandContent

func init(registry: DebugCommandRegistry, execute_callback: Callable) -> void:
	_registry = registry
	_execute_callback = execute_callback

func _ready() -> void:
	_setup_param_dialog()
	refresh()

func refresh() -> void:
	_build_ui()

func _setup_param_dialog() -> void:
	_param_dialog = ParamDialogScene.instantiate()
	add_child(_param_dialog)
	_param_dialog.hide()
	_param_dialog.command_submitted.connect(_on_param_dialog_submitted)

func _on_param_dialog_submitted(command: String) -> void:
	if _execute_callback.is_valid():
		_execute_callback.call(command)

func _build_ui() -> void:
	if not is_instance_valid(command_content):
		return

	# 清空现有内容
	for child in command_content.get_children():
		child.queue_free()

	# 阶段控制
	_create_section("阶段控制", [
		{"text": "推进阶段", "command": "advance"},
		{"text": "推进子阶段", "command": "advance sub_phase"},
		{"text": "跳到下一回合", "command": "next_round"},
		{"text": "跳过...", "command": "skip", "params": [
			_get_player_param()
		]},
		{"text": "跳过子阶段...", "command": "skip_sub", "params": [
			_get_player_param()
		]},
		{"text": "结束回合...", "command": "end_turn", "params": [
			_get_player_param()
		]},
	])

	# 顺序选择
	_create_section("顺序选择", [
		{"text": "选择顺序位置...", "command": "choose_order", "params": [
			_get_player_param(),
			{"name": "position", "label": "位置", "hint": "0, 1, 2..."}
		]},
	])

	# 员工管理
	var employee_options := _get_employee_options()
	_create_section("员工管理", [
		{"text": "招聘...", "command": "recruit", "params": [
			_get_player_param(),
			{"name": "employee_type", "label": "员工类型", "hint": "如: management_trainee", "options": employee_options}
		]},
		{"text": "培训...", "command": "train", "params": [
			_get_player_param(),
			{"name": "from_type", "label": "源类型", "hint": "如: management_trainee", "options": employee_options},
			{"name": "to_type", "label": "目标类型", "hint": "如: ceo", "options": employee_options}
		]},
		{"text": "解雇...", "command": "fire", "params": [
			_get_player_param(),
			{"name": "employee_id", "label": "员工ID", "hint": "员工的唯一标识"}
		]},
	])

	# 资源生产
	var food_options := _get_food_product_options()
	var drink_options := _get_drink_product_options()
	_create_section("资源生产", [
		{"text": "生产食物...", "command": "produce", "params": [
			_get_player_param(),
			{"name": "product", "label": "食物", "hint": "如: burger, pizza", "options": food_options},
			{"name": "amount", "label": "数量", "hint": "1, 2, 3...", "default": "1"},
		]},
		{"text": "采购饮料...", "command": "procure", "params": [
			_get_player_param(),
			{"name": "product", "label": "饮料", "hint": "如: soda, beer", "options": drink_options},
			{"name": "amount", "label": "数量", "hint": "1, 2, 3...", "default": "1"},
		]},
	])

	# 地图操作
	var rotation_options: Array[String] = ["0", "90", "180", "270"]
	var dir_options: Array[String] = ["N", "E", "S", "W"]
	var house_options := _get_house_options()
	_create_section("地图操作", [
		{"text": "放置餐厅...", "command": "place_restaurant", "params": [
			_get_player_param(),
			{"name": "x", "label": "X坐标", "hint": "0-14"},
			{"name": "y", "label": "Y坐标", "hint": "0-14"},
			{"name": "rotation", "label": "旋转", "hint": "0, 90, 180, 270", "default": "0", "options": rotation_options}
		]},
		{"text": "放置房屋...", "command": "place_house", "params": [
			_get_player_param(),
			{"name": "x", "label": "X坐标", "hint": "0-14"},
			{"name": "y", "label": "Y坐标", "hint": "0-14"},
			{"name": "rotation", "label": "旋转", "hint": "0, 90, 180, 270", "default": "0", "options": rotation_options}
		]},
		{"text": "移动餐厅...", "command": "move_restaurant", "params": [
			_get_player_param(),
			{"name": "restaurant_id", "label": "餐厅ID", "hint": "餐厅的唯一标识"},
			{"name": "x", "label": "X坐标", "hint": "0-14"},
			{"name": "y", "label": "Y坐标", "hint": "0-14"},
			{"name": "rotation", "label": "旋转", "hint": "0, 90, 180, 270", "default": "0", "options": rotation_options}
		]},
		{"text": "添加花园...", "command": "add_garden", "params": [
			_get_player_param(),
			{"name": "house_id", "label": "房屋", "hint": "房屋的唯一标识", "options": house_options},
			{"name": "direction", "label": "方向", "hint": "N, E, S, W", "options": dir_options}
		]},
	])

	# 营销系统
	var product_options := _get_product_options()
	var marketing_board_options := _get_marketing_board_options()
	var from_player_options := _get_optional_player_options()
	_create_section("营销系统", [
		{"text": "发起营销...", "command": "marketing", "params": [
			_get_player_param(),
			{"name": "employee_type", "label": "员工类型", "hint": "如: billboard_guy", "options": employee_options},
			{"name": "board_number", "label": "板件编号", "hint": "1, 2, 3...", "options": marketing_board_options},
			{"name": "product", "label": "产品", "hint": "如: burger, pizza", "options": product_options},
			{"name": "x", "label": "X坐标", "hint": "0-14"},
			{"name": "y", "label": "Y坐标", "hint": "0-14"}
		]},
		{"text": "给房屋加需求...", "command": "add_house_demand", "params": [
			{"name": "house_id", "label": "房屋", "hint": "如: house_1", "options": house_options},
			{"name": "product", "label": "产品", "hint": "如: burger, pizza", "options": product_options},
			{"name": "amount", "label": "数量", "hint": "1, 2, 3...", "default": "1"},
			{"name": "from_player", "label": "来源玩家(可选)", "hint": "留空表示无(-1)，也可输入 id:<player_id>", "options": from_player_options, "allow_custom": true},
		]},
	])

	# 价格设定
	_create_section("价格设定", [
		{"text": "设定价格 (-$1)...", "command": "set_price", "params": [
			_get_player_param()
		]},
		{"text": "设定折扣 (-$3)...", "command": "set_discount", "params": [
			_get_player_param()
		]},
		{"text": "设定奢侈品 (+$10)...", "command": "set_luxury", "params": [
			_get_player_param()
		]},
	])

	# 资源操作
	_create_section("资源操作", [
		{"text": "给玩家加钱...", "command": "give_money", "params": [
			_get_player_param(),
			{"name": "amount", "label": "金额", "hint": "如: 50", "default": "50"}
		]},
		{"text": "查看银行", "command": "bank"},
	])

	# 状态查看
	_create_section("状态查看", [
		{"text": "查看状态", "command": "state"},
		{"text": "查看玩家", "command": "players"},
		{"text": "查看地图", "command": "map"},
		{"text": "查看营销", "command": "marketing_list"},
	])

	# 状态操作
	_create_section("状态操作", [
		{"text": "保存快照", "command": "snapshot"},
		{"text": "加载快照", "command": "restore"},
		{"text": "保存游戏", "command": "save"},
	])

	# 调试工具
	_create_section("调试工具", [
		{"text": "导出状态", "command": "dump"},
		{"text": "验证不变量", "command": "validate"},
		{"text": "命令历史", "command": "history 20"},
		{"text": "可用动作", "command": "actions"},
		{"text": "帮助", "command": "help"},
	])

	# 撤销/重做
	_create_section("撤销/重做", [
		{"text": "撤销 1 步", "command": "undo"},
		{"text": "撤销 5 步", "command": "undo 5"},
		{"text": "重做 1 步", "command": "redo"},
		{"text": "重做 5 步", "command": "redo 5"},
	])

func _create_section(title: String, buttons: Array) -> void:
	# 分隔线
	var separator := HSeparator.new()
	command_content.add_child(separator)

	# 标题
	var title_label := Label.new()
	title_label.text = "═══ %s ═══" % title
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	command_content.add_child(title_label)

	# 按钮容器
	var button_container := HFlowContainer.new()
	button_container.add_theme_constant_override("h_separation", 8)
	button_container.add_theme_constant_override("v_separation", 4)
	command_content.add_child(button_container)

	# 创建按钮
	for btn_data in buttons:
		var btn := Button.new()
		btn.text = btn_data["text"]

		if btn_data.has("params"):
			# 带参数的按钮
			btn.pressed.connect(_on_param_button_pressed.bind(btn_data["text"], btn_data["command"], btn_data["params"]))
		else:
			# 直接执行的按钮
			btn.pressed.connect(_on_button_pressed.bind(btn_data["command"]))

		button_container.add_child(btn)

func _on_button_pressed(command: String) -> void:
	GameLog.debug("DebugPanel", "按钮点击: %s" % command)
	if _execute_callback.is_valid():
		GameLog.debug("DebugPanel", "执行命令: %s" % command)
		_execute_callback.call(command)
	else:
		GameLog.warn("DebugPanel", "命令回调无效，无法执行: %s" % command)
		push_error("DebugPanel: _execute_callback 无效")

func _on_param_button_pressed(title: String, command: String, params: Array) -> void:
	GameLog.debug("DebugPanel", "参数按钮点击: %s" % command)
	if _param_dialog != null:
		var typed_params: Array[Dictionary] = []
		for p in params:
			typed_params.append(p)
		_param_dialog.show_dialog(title, command, typed_params)

func _get_player_param() -> Dictionary:
	return {
		"name": "player",
		"label": "玩家",
		"hint": "玩家顺位 1..N（也可输入 id:<player_id>）",
		"options": _get_player_options(),
		"allow_custom": true,
	}

func _get_player_options() -> Array[Dictionary]:
	var state: GameState = _get_state()
	var player_count := Globals.player_count
	if state != null:
		player_count = state.players.size()

	var items: Array[Dictionary] = []
	for pid in range(player_count):
		var name := Globals.get_player_name(pid)
		var pnum := pid + 1
		items.append({
			"text": "玩家%d (id=%d): %s" % [pnum, pid, name],
			"value": pnum,
		})
	return items

func _get_optional_player_options() -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	items.append({"text": "(无)", "value": ""})
	items.append_array(_get_player_options())
	return items

func _get_house_options() -> Array[Dictionary]:
	var state: GameState = _get_state()
	if state == null or not (state.map is Dictionary):
		return []
	if not state.map.has("houses") or not (state.map["houses"] is Dictionary):
		return []
	var houses: Dictionary = state.map["houses"]

	var ids: Array[String] = []
	for hid_val in houses.keys():
		var hid := str(hid_val).strip_edges()
		if hid.is_empty():
			continue
		ids.append(hid)
	ids.sort()

	var items: Array[Dictionary] = []
	for hid in ids:
		var house_val = houses.get(hid, null)
		if not (house_val is Dictionary):
			continue
		var house: Dictionary = house_val
		var house_number := str(house.get("house_number", "?")).strip_edges()
		var anchor_val = house.get("anchor_pos", null)
		var pos_text := "?"
		if anchor_val is Vector2i:
			var p: Vector2i = anchor_val
			pos_text = "%d,%d" % [p.x, p.y]
		items.append({
			"text": "房号%s house_id=%s 坐标=(%s)" % [house_number, hid, pos_text],
			"value": hid,
		})
	return items

func _get_marketing_board_options() -> Array[Dictionary]:
	var state: GameState = _get_state()
	var player_count := Globals.player_count
	if state != null:
		player_count = state.players.size()

	if not MarketingRegistry.is_loaded():
		return []

	var removed := MarketingRules.get_removed_board_numbers(player_count)
	var placements: Dictionary = {}
	if state != null and (state.map is Dictionary) and (state.map.get("marketing_placements", null) is Dictionary):
		placements = Dictionary(state.map.get("marketing_placements", {}))

	var items: Array[Dictionary] = []
	for bn in MarketingRegistry.get_all_board_numbers():
		var board_number := int(bn)
		if removed.has(board_number):
			continue
		if placements.has(str(board_number)):
			continue
		var def_val = MarketingRegistry.get_def(board_number)
		if not (def_val is MarketingDef):
			continue
		var def: MarketingDef = def_val
		if not def.is_available_for_player_count(player_count):
			continue
		items.append({
			"text": "#%d %s (%dx%d)" % [board_number, def.type, def.footprint_size.x, def.footprint_size.y],
			"value": board_number,
		})
	return items

func _get_state() -> GameState:
	if _registry == null:
		return null
	var engine := _registry.get_game_engine()
	if engine == null:
		return null
	return engine.get_state()

func _get_employee_options() -> Array[String]:
	if not EmployeeRegistry.is_loaded():
		return []
	return EmployeeRegistry.get_all_ids()

func _get_product_options() -> Array[String]:
	if not ProductRegistry.is_loaded():
		return []
	return ProductRegistry.get_all_ids()

func _get_food_product_options() -> Array[String]:
	if not ProductRegistry.is_loaded():
		return []
	var out: Array[String] = []
	for pid in ProductRegistry.get_all_ids():
		if not ProductRegistry.is_drink(pid):
			out.append(pid)
	return out

func _get_drink_product_options() -> Array[String]:
	if not ProductRegistry.is_loaded():
		return []
	var out: Array[String] = []
	for pid in ProductRegistry.get_all_ids():
		if ProductRegistry.is_drink(pid):
			out.append(pid)
	return out
