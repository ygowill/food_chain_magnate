# 参数输入弹窗
# 用于需要参数的调试命令
class_name DebugParamDialog
extends Window

signal command_submitted(command: String)

var _command_template: String = ""
var _param_controls: Array[Dictionary] = [] # [{kind: "text"|"select", control: Control}]

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
	params: Array[Dictionary]
) -> void:
	_command_template = command_template
	_param_controls.clear()

	# 设置标题
	title_label.text = title
	self.title = title

	# 清空参数容器
	for child in params_container.get_children():
		child.queue_free()

	# 创建参数输入
	for param in params:
		var hbox := HBoxContainer.new()
		params_container.add_child(hbox)

		var label := Label.new()
		label.text = param.get("label", param.get("name", "参数")) + ":"
		label.custom_minimum_size.x = 120
		hbox.add_child(label)

		var options_val = param.get("options", null)
		var allow_custom := bool(param.get("allow_custom", false))
		if options_val is Array and not Array(options_val).is_empty():
			if allow_custom:
				var option := OptionButton.new()
				option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				option.clear()
				option.add_item("(手动输入)")
				option.set_item_metadata(0, "")
				for o in Array(options_val):
					var opt_label := ""
					var value = null
					if o is Dictionary:
						var d: Dictionary = o
						opt_label = str(d.get("text", d.get("label", ""))).strip_edges()
						value = d.get("value", d.get("id", opt_label))
					else:
						opt_label = str(o).strip_edges()
						value = o
					if opt_label.is_empty():
						continue
					option.add_item(opt_label)
					var idx := option.get_item_count() - 1
					option.set_item_metadata(idx, value)
				if param.has("default"):
					_select_option_by_default(option, param["default"])
				else:
					option.select(0)

				var input := LineEdit.new()
				input.placeholder_text = param.get("hint", "")
				input.custom_minimum_size.x = 160
				if param.has("default_text"):
					input.text = str(param["default_text"])

				hbox.add_child(option)
				hbox.add_child(input)
				_param_controls.append({"kind": "select_custom", "option": option, "input": input})
			else:
				var option := OptionButton.new()
				option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				_build_option_items(option, Array(options_val))
				if param.has("default"):
					_select_option_by_default(option, param["default"])
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

func _build_option_items(option: OptionButton, options: Array) -> void:
	if option == null:
		return
	option.clear()
	for o in options:
		var label := ""
		var value = null
		if o is Dictionary:
			var d: Dictionary = o
			label = str(d.get("text", d.get("label", ""))).strip_edges()
			value = d.get("value", d.get("id", label))
		else:
			label = str(o).strip_edges()
			value = o
		if label.is_empty():
			continue
		option.add_item(label)
		var idx := option.get_item_count() - 1
		option.set_item_metadata(idx, value)

func _select_option_by_default(option: OptionButton, want_val) -> void:
	if option == null:
		return
	var want := str(want_val).strip_edges()
	if want.is_empty():
		return
	for i in range(option.item_count):
		var meta = option.get_item_metadata(i)
		if str(meta).strip_edges() == want:
			option.select(i)
			return
		if option.get_item_text(i).strip_edges() == want:
			option.select(i)
			return

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
				var meta = ob.get_item_metadata(ob.selected)
				value = str(meta).strip_edges() if meta != null else str(ob.get_item_text(ob.selected)).strip_edges()
		elif kind == "select_custom":
			var ob2 = d.get("option", null)
			var le = d.get("input", null)
			if le is LineEdit:
				value = str((le as LineEdit).text).strip_edges()
			if value.is_empty() and ob2 is OptionButton:
				var obc: OptionButton = ob2
				if obc.selected >= 0:
					var meta2 = obc.get_item_metadata(obc.selected)
					value = str(meta2).strip_edges() if meta2 != null else str(obc.get_item_text(obc.selected)).strip_edges()
		elif c is LineEdit:
			value = str(c.text).strip_edges()
		if value.is_empty():
			continue
		parts.append(value)

	command_submitted.emit(" ".join(parts).strip_edges())
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
