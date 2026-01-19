# 参数输入弹窗
# 用于需要参数的调试命令
class_name DebugParamDialog
extends Window

signal command_submitted(command: String, selected_player_id: int)

var _command_template: String = ""
var _param_controls: Array[Dictionary] = [] # [{kind: "text"|"select", control: Control}]
var _player_option: OptionButton = null
var _selected_player_id: int = -1

@onready var title_label: Label = $VBoxContainer/TitleLabel
@onready var params_container: VBoxContainer = $VBoxContainer/ParamsContainer
@onready var submit_button: Button = $VBoxContainer/ButtonContainer/SubmitButton
@onready var cancel_button: Button = $VBoxContainer/ButtonContainer/CancelButton

func _ready() -> void:
	submit_button.pressed.connect(_on_submit)
	cancel_button.pressed.connect(_on_cancel)
	close_requested.connect(_on_cancel)

func show_dialog(
	title: String,
	command_template: String,
	params: Array[Dictionary],
	player_items: Array[Dictionary] = [],
	selected_player_id: int = -1
) -> void:
	_command_template = command_template
	_param_controls.clear()
	_player_option = null
	_selected_player_id = selected_player_id

	# 设置标题
	title_label.text = title
	self.title = title

	# 清空参数容器
	for child in params_container.get_children():
		child.queue_free()

	# 玩家选择（让“弹窗内就能切换目标玩家”，避免只在面板顶部可切换带来的不便）
	if not player_items.is_empty():
		var hbox_p := HBoxContainer.new()
		params_container.add_child(hbox_p)

		var p_label := Label.new()
		p_label.text = "目标玩家:"
		p_label.custom_minimum_size.x = 120
		hbox_p.add_child(p_label)

		_player_option = OptionButton.new()
		_player_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for item_val in player_items:
			if not (item_val is Dictionary):
				continue
			var item: Dictionary = item_val
			var text := str(item.get("text", "")).strip_edges()
			var pid := int(item.get("id", -1))
			if text.is_empty():
				continue
			_player_option.add_item(text, pid)
		_player_option.item_selected.connect(_on_player_option_selected)
		hbox_p.add_child(_player_option)

		# 设置初始选中
		var select_index := 0
		for i in range(_player_option.item_count):
			if int(_player_option.get_item_id(i)) == _selected_player_id:
				select_index = i
				break
		_player_option.select(select_index)
		_selected_player_id = int(_player_option.get_item_id(select_index))

	# 创建参数输入
	for param in params:
		var hbox := HBoxContainer.new()
		params_container.add_child(hbox)

		var label := Label.new()
		label.text = param.get("label", param.get("name", "参数")) + ":"
		label.custom_minimum_size.x = 120
		hbox.add_child(label)

		var options_val = param.get("options", null)
		if options_val is Array and not Array(options_val).is_empty():
			var option := OptionButton.new()
			option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var options: Array = options_val
			for o in options:
				option.add_item(str(o))
			if param.has("default"):
				var want := str(param["default"])
				for i in range(option.item_count):
					if option.get_item_text(i) == want:
						option.select(i)
						break
			hbox.add_child(option)
			_param_controls.append({"kind": "select", "control": option})
		else:
			var input := LineEdit.new()
			input.placeholder_text = param.get("hint", "")
			input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			if param.has("default"):
				input.text = str(param["default"])
			hbox.add_child(input)
			_param_controls.append({"kind": "text", "control": input})

	# 显示弹窗
	popup_centered()

	# 聚焦第一个输入框
	if not _param_controls.is_empty():
		var c = _param_controls[0].get("control", null)
		if c is Control:
			c.grab_focus()

func _on_player_option_selected(index: int) -> void:
	if _player_option == null:
		return
	if index < 0:
		return
	_selected_player_id = int(_player_option.get_item_id(index))

func _on_submit() -> void:
	var parts: Array[String] = [_command_template]
	for item in _param_controls:
		if not (item is Dictionary):
			continue
		var d: Dictionary = item
		var kind := str(d.get("kind", "text"))
		var c = d.get("control", null)
		var value := ""
		if kind == "select" and c is OptionButton:
			var ob: OptionButton = c
			if ob.selected >= 0:
				value = str(ob.get_item_text(ob.selected)).strip_edges()
		elif c is LineEdit:
			value = str(c.text).strip_edges()
		if value.is_empty():
			continue
		parts.append(value)

	command_submitted.emit(" ".join(parts).strip_edges(), _selected_player_id)
	hide()

func _on_cancel() -> void:
	hide()

func _input(event: InputEvent) -> void:
	if not visible:
		return

	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ENTER:
			_on_submit()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE:
			_on_cancel()
			get_viewport().set_input_as_handled()
