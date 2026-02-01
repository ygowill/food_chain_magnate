# 房间密码输入弹窗（联机加入/观战）
class_name PasswordDialog
extends ModalDialogBase

signal submitted(password: String)
signal cancelled()

const UiStylesClass = preload("res://ui/utils/ui_styles.gd")

var _title_label: Label = null
var _message_label: Label = null
var _password_edit: LineEdit = null
var _confirm_button: Button = null
var _cancel_button: Button = null
var _dialog_panel: PanelContainer = null

func _ready() -> void:
	super._ready()
	_build_ui()

func open_for_room(room_code: String, confirm_text: String = "加入/观战") -> void:
	if _title_label != null and is_instance_valid(_title_label):
		_title_label.text = "输入房间密码"
	if _message_label != null and is_instance_valid(_message_label):
		var code := str(room_code).strip_edges().to_upper()
		_message_label.text = "房间 %s 需要密码才能加入/观战。\n（若房间密码为空，可直接留空）" % (code if not code.is_empty() else "-")
	if _confirm_button != null and is_instance_valid(_confirm_button):
		_confirm_button.text = str(confirm_text).strip_edges()
	if _password_edit != null and is_instance_valid(_password_edit):
		_password_edit.text = ""
	open()

func _build_ui() -> void:
	var overlay_rect := ColorRect.new()
	overlay_rect.name = "Overlay"
	overlay_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, 0)
	overlay_rect.color = overlay_color
	overlay_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay_rect)

	var center := CenterContainer.new()
	center.name = "Center"
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, 0)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	_dialog_panel = PanelContainer.new()
	_dialog_panel.custom_minimum_size = Vector2(460, 240)
	UiStylesClass.apply_dialog_surface(_dialog_panel)
	center.add_child(_dialog_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	_dialog_panel.add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)

	_title_label = Label.new()
	_title_label.text = "输入房间密码"
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 18)
	root.add_child(_title_label)

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

func _grab_default_focus() -> void:
	if _password_edit != null and is_instance_valid(_password_edit):
		_password_edit.grab_focus()

func _on_confirm_pressed() -> void:
	var pw := ""
	if _password_edit != null and is_instance_valid(_password_edit):
		pw = str(_password_edit.text)
	close()
	submitted.emit(pw)

func _on_cancel_pressed() -> void:
	close()
	cancelled.emit()

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey:
		var e: InputEventKey = event
		if e.pressed and not e.echo and e.keycode == KEY_ESCAPE:
			_on_cancel_pressed()
			get_viewport().set_input_as_handled()
