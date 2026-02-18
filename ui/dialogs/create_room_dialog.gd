# 创建房间弹窗（全屏遮罩 + 居中面板 + 密码 + RoomConfigEditor + 创建按钮）
class_name CreateRoomDialog
extends ModalDialogBase

signal create_requested(desired_player_count: int, room_password: String, config_patch: Dictionary)
signal cancelled()

const RoomConfigEditorClass = preload("res://ui/components/room_config_editor/room_config_editor.gd")
const UiStylesClass = preload("res://ui/utils/ui_styles.gd")

var _dialog_panel: PanelContainer = null
var _inner_border: PanelContainer = null
var _title_label: Label = null
var _password_edit: LineEdit = null
var _room_config_editor = null
var _error_label: Label = null
var _create_button: Button = null
var _cancel_button: Button = null

func _ready() -> void:
	super._ready()
	_build_ui()

func open_dialog() -> void:
	if _password_edit != null and is_instance_valid(_password_edit):
		_password_edit.text = ""
	_clear_error()
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
	_dialog_panel.custom_minimum_size = Vector2(1200, 600)
	UiStylesClass.apply_dialog_surface(_dialog_panel)
	_dialog_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	center.add_child(_dialog_panel)

	var outer_margin := MarginContainer.new()
	outer_margin.add_theme_constant_override("margin_left", 6)
	outer_margin.add_theme_constant_override("margin_top", 6)
	outer_margin.add_theme_constant_override("margin_right", 6)
	outer_margin.add_theme_constant_override("margin_bottom", 6)
	_dialog_panel.add_child(outer_margin)

	_inner_border = PanelContainer.new()
	UiStylesClass.apply_poster_inner_border(_inner_border)
	outer_margin.add_child(_inner_border)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	_inner_border.add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)

	# 标题
	_title_label = Label.new()
	_title_label.text = "创建房间"
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 24)
	UiStylesClass.apply_label_dark(_title_label)
	root.add_child(_title_label)

	# 装饰线
	var line := ColorRect.new()
	line.custom_minimum_size = Vector2(320, 2)
	line.color = Color(0.73, 0.23, 0.18, 0.5)
	line.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	root.add_child(line)

	# 密码行
	var pw_row := HBoxContainer.new()
	pw_row.add_theme_constant_override("separation", 8)
	root.add_child(pw_row)

	var pw_label := Label.new()
	pw_label.text = "房间密码（可空）"
	UiStylesClass.apply_label_dark(pw_label)
	pw_row.add_child(pw_label)

	_password_edit = LineEdit.new()
	_password_edit.secret = true
	_password_edit.secret_character = "*"
	_password_edit.placeholder_text = "留空则无密码"
	_password_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_password_edit.custom_minimum_size = Vector2(200, 0)
	UiStylesClass.apply_line_edit_field(_password_edit)
	pw_row.add_child(_password_edit)

	# 装饰线 2
	var line2 := ColorRect.new()
	line2.custom_minimum_size = Vector2(320, 2)
	line2.color = Color(0.73, 0.23, 0.18, 0.5)
	line2.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	root.add_child(line2)

	# RoomConfigEditor
	_room_config_editor = RoomConfigEditorClass.new()
	_room_config_editor.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_room_config_editor)

	# 错误标签
	_error_label = Label.new()
	_error_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_error_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_error_label.visible = false
	UiStylesClass.apply_label_error(_error_label)
	root.add_child(_error_label)

	# 按钮行
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 12)
	root.add_child(btn_row)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_row.add_child(spacer)

	_cancel_button = Button.new()
	_cancel_button.text = "取消"
	UiStylesClass.apply_button_secondary(_cancel_button)
	_cancel_button.pressed.connect(_on_cancel_pressed)
	btn_row.add_child(_cancel_button)

	_create_button = Button.new()
	_create_button.text = "创建并进入"
	UiStylesClass.apply_button_primary(_create_button)
	_create_button.pressed.connect(_on_create_pressed)
	btn_row.add_child(_create_button)

func _grab_default_focus() -> void:
	if _password_edit != null and is_instance_valid(_password_edit):
		_password_edit.grab_focus()

func _on_create_pressed() -> void:
	_clear_error()
	if _room_config_editor == null or not is_instance_valid(_room_config_editor):
		_set_error("配置编辑器缺失。")
		return
	var vr: Result = _room_config_editor.validate()
	if not vr.ok:
		_set_error(vr.error)
		return
	var patch: Dictionary = _room_config_editor.get_config_patch()
	var desired: int = int(patch.get("desired_player_count", Globals.MIN_PLAYERS))
	var password := str(_password_edit.text) if (_password_edit != null and is_instance_valid(_password_edit)) else ""
	close()
	create_requested.emit(desired, password, patch)

func _on_cancel_pressed() -> void:
	close()
	cancelled.emit()

func _set_error(message: String) -> void:
	if _error_label == null or not is_instance_valid(_error_label):
		return
	_error_label.text = str(message).strip_edges()
	_error_label.visible = not str(message).strip_edges().is_empty()

func _clear_error() -> void:
	if _error_label == null or not is_instance_valid(_error_label):
		return
	_error_label.text = ""
	_error_label.visible = false

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey:
		var e: InputEventKey = event
		if e.pressed and not e.echo and e.keycode == KEY_ESCAPE:
			_on_cancel_pressed()
			get_viewport().set_input_as_handled()
