# 参数输入弹窗
# 用于需要参数的调试命令
class_name DebugParamDialog
extends Window

signal command_submitted(command: String)

var _command_template: String = ""
var _param_inputs: Array[LineEdit] = []

@onready var title_label: Label = $VBoxContainer/TitleLabel
@onready var params_container: VBoxContainer = $VBoxContainer/ParamsContainer
@onready var submit_button: Button = $VBoxContainer/ButtonContainer/SubmitButton
@onready var cancel_button: Button = $VBoxContainer/ButtonContainer/CancelButton

func _ready() -> void:
	submit_button.pressed.connect(_on_submit)
	cancel_button.pressed.connect(_on_cancel)
	close_requested.connect(_on_cancel)

func show_dialog(title: String, command_template: String, params: Array[Dictionary]) -> void:
	_command_template = command_template
	_param_inputs.clear()

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

		var input := LineEdit.new()
		input.placeholder_text = param.get("hint", "")
		input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if param.has("default"):
			input.text = str(param["default"])
		hbox.add_child(input)

		_param_inputs.append(input)

	# 显示弹窗
	popup_centered()

	# 聚焦第一个输入框
	if not _param_inputs.is_empty():
		_param_inputs[0].grab_focus()

func _on_submit() -> void:
	var command := _command_template
	for i in range(_param_inputs.size()):
		var value := _param_inputs[i].text.strip_edges()
		command += " " + value

	command_submitted.emit(command.strip_edges())
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
