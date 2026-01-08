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
	_build_ui()
	_setup_param_dialog()

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
		{"text": "跳过", "command": "skip"},
		{"text": "跳过子阶段", "command": "skip_sub"},
		{"text": "结束回合", "command": "end_turn"},
	])

	# 顺序选择
	_create_section("顺序选择", [
		{"text": "选择顺序位置...", "command": "choose_order", "params": [
			{"name": "position", "label": "位置", "hint": "0, 1, 2..."}
		]},
	])

	# 员工管理
	_create_section("员工管理", [
		{"text": "招聘...", "command": "recruit", "params": [
			{"name": "employee_type", "label": "员工类型", "hint": "如: management_trainee"}
		]},
		{"text": "培训...", "command": "train", "params": [
			{"name": "from_type", "label": "源类型", "hint": "如: management_trainee"},
			{"name": "to_type", "label": "目标类型", "hint": "如: ceo"}
		]},
		{"text": "解雇...", "command": "fire", "params": [
			{"name": "employee_id", "label": "员工ID", "hint": "员工的唯一标识"}
		]},
	])

	# 资源生产
	_create_section("资源生产", [
		{"text": "生产食物...", "command": "produce", "params": [
			{"name": "employee_type", "label": "员工类型", "hint": "如: cook, chef"}
		]},
		{"text": "采购饮料...", "command": "procure", "params": [
			{"name": "employee_type", "label": "员工类型", "hint": "如: cart_operator"}
		]},
	])

	# 地图操作
	_create_section("地图操作", [
		{"text": "放置餐厅...", "command": "place_restaurant", "params": [
			{"name": "x", "label": "X坐标", "hint": "0-14"},
			{"name": "y", "label": "Y坐标", "hint": "0-14"},
			{"name": "rotation", "label": "旋转", "hint": "0, 90, 180, 270", "default": "0"}
		]},
		{"text": "放置房屋...", "command": "place_house", "params": [
			{"name": "x", "label": "X坐标", "hint": "0-14"},
			{"name": "y", "label": "Y坐标", "hint": "0-14"},
			{"name": "rotation", "label": "旋转", "hint": "0, 90, 180, 270", "default": "0"}
		]},
		{"text": "移动餐厅...", "command": "move_restaurant", "params": [
			{"name": "restaurant_id", "label": "餐厅ID", "hint": "餐厅的唯一标识"},
			{"name": "x", "label": "X坐标", "hint": "0-14"},
			{"name": "y", "label": "Y坐标", "hint": "0-14"},
			{"name": "rotation", "label": "旋转", "hint": "0, 90, 180, 270", "default": "0"}
		]},
		{"text": "添加花园...", "command": "add_garden", "params": [
			{"name": "house_id", "label": "房屋ID", "hint": "房屋的唯一标识"},
			{"name": "direction", "label": "方向", "hint": "N, E, S, W"}
		]},
	])

	# 营销系统
	_create_section("营销系统", [
		{"text": "发起营销...", "command": "marketing", "params": [
			{"name": "employee_type", "label": "员工类型", "hint": "如: billboard_guy"},
			{"name": "board_number", "label": "板件编号", "hint": "1, 2, 3..."},
			{"name": "product", "label": "产品", "hint": "如: burger, pizza"},
			{"name": "x", "label": "X坐标", "hint": "0-14"},
			{"name": "y", "label": "Y坐标", "hint": "0-14"}
		]},
	])

	# 价格设定
	_create_section("价格设定", [
		{"text": "设定价格 (-$1)", "command": "set_price"},
		{"text": "设定折扣 (-$3)", "command": "set_discount"},
		{"text": "设定奢侈品 (+$10)", "command": "set_luxury"},
	])

	# 资源操作
	_create_section("资源操作", [
		{"text": "给玩家0 +$50", "command": "give_money 0 50"},
		{"text": "给玩家1 +$50", "command": "give_money 1 50"},
		{"text": "查看银行", "command": "bank"},
	])

	# 状态查看
	_create_section("状态查看", [
		{"text": "查看状态", "command": "state"},
		{"text": "查看玩家", "command": "players"},
		{"text": "查看地图", "command": "map"},
		{"text": "查看营销", "command": "marketing"},
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
