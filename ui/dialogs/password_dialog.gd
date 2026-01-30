# 房间密码输入弹窗（联机加入/观战）
class_name PasswordDialog
extends Window

signal submitted(password: String)
signal cancelled()

const UiStylesClass = preload("res://ui/utils/ui_styles.gd")

var _message_label: Label = null
var _password_edit: LineEdit = null
var _confirm_button: Button = null
var _cancel_button: Button = null

func _ready() -> void:
	title = "输入房间密码"
	size = Vector2i(460, 220)
	visible = false
	transient = true

	_build_ui()
	close_requested.connect(_on_cancel_pressed)

func open_for_room(room_code: String, confirm_text: String = "加入/观战") -> void:
	title = "输入房间密码"
	if _message_label != null and is_instance_valid(_message_label):
		var code := str(room_code).strip_edges().to_upper()
		_message_label.text = "房间 %s 需要密码才能加入/观战。\n（若房间密码为空，可直接留空）" % (code if not code.is_empty() else "-")
	if _confirm_button != null and is_instance_valid(_confirm_button):
		_confirm_button.text = str(confirm_text).strip_edges()
	if _password_edit != null and is_instance_valid(_password_edit):
		_password_edit.text = ""
	popup_centered()
	if _password_edit != null and is_instance_valid(_password_edit):
		_password_edit.grab_focus()

func _build_ui() -> void:
	var bg := Panel.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	UiStylesClass.apply_dialog_surface(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)

	_message_label = Label.new()
	_message_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_message_label.add_theme_color_override("font_color", Color(0.92, 0.94, 0.98))
	_message_label.text = "该房间需要密码才能加入/观战。"
	root.add_child(_message_label)

	_password_edit = LineEdit.new()
	_password_edit.secret = true
	_password_edit.placeholder_text = "房间密码"
	_password_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_password_edit.text_submitted.connect(func(_t: String) -> void:
		_on_confirm_pressed()
	)
	root.add_child(_password_edit)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	root.add_child(row)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	_cancel_button = Button.new()
	_cancel_button.text = "取消"
	UiStylesClass.apply_button_secondary(_cancel_button)
	_cancel_button.pressed.connect(_on_cancel_pressed)
	row.add_child(_cancel_button)

	_confirm_button = Button.new()
	_confirm_button.text = "加入/观战"
	UiStylesClass.apply_button_primary(_confirm_button)
	_confirm_button.pressed.connect(_on_confirm_pressed)
	row.add_child(_confirm_button)

func _on_confirm_pressed() -> void:
	var pw := ""
	if _password_edit != null and is_instance_valid(_password_edit):
		pw = str(_password_edit.text)
	hide()
	submitted.emit(pw)

func _on_cancel_pressed() -> void:
	hide()
	cancelled.emit()

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey:
		var e: InputEventKey = event
		if e.pressed and not e.echo and e.keycode == KEY_ESCAPE:
			_on_cancel_pressed()
			get_viewport().set_input_as_handled()
