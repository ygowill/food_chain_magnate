# 通用信息弹窗（单按钮关闭）
class_name InfoDialog
extends ModalDialogBase

signal closed()

const UiStylesClass = preload("res://ui/utils/ui_styles.gd")

var _title_label: Label = null
var _message_label: Label = null
var _close_button: Button = null
var _dialog_panel: PanelContainer = null

func _ready() -> void:
	super._ready()
	_build_ui()

func show_info(title_text: String, message: String, min_size: Vector2i = Vector2i(520, 360), close_text: String = "关闭") -> void:
	if min_size.x > 0 and min_size.y > 0:
		if _dialog_panel != null and is_instance_valid(_dialog_panel):
			_dialog_panel.custom_minimum_size = Vector2(min_size.x, min_size.y)
	if _title_label != null and is_instance_valid(_title_label):
		_title_label.text = str(title_text)
	if _message_label != null and is_instance_valid(_message_label):
		_message_label.text = str(message)
	if _close_button != null and is_instance_valid(_close_button):
		_close_button.text = str(close_text)

	open()

func _build_ui() -> void:
	var overlay_rect := ColorRect.new()
	overlay_rect.name = "Overlay"
	overlay_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay_rect.color = overlay_color
	overlay_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay_rect)

	var center := CenterContainer.new()
	center.name = "Center"
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	_dialog_panel = PanelContainer.new()
	_dialog_panel.custom_minimum_size = Vector2(520, 360)
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
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_title_label.add_theme_font_size_override("font_size", 18)
	root.add_child(_title_label)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)

	var msg_wrap := MarginContainer.new()
	msg_wrap.add_theme_constant_override("margin_left", 6)
	msg_wrap.add_theme_constant_override("margin_top", 2)
	msg_wrap.add_theme_constant_override("margin_right", 6)
	msg_wrap.add_theme_constant_override("margin_bottom", 2)
	msg_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(msg_wrap)

	_message_label = Label.new()
	_message_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_message_label.add_theme_font_size_override("font_size", 14)
	_message_label.add_theme_color_override("font_color", Color(0.17, 0.13, 0.09, 1))
	_message_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	msg_wrap.add_child(_message_label)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.alignment = BoxContainer.ALIGNMENT_END
	root.add_child(row)

	_close_button = Button.new()
	_close_button.text = "关闭"
	UiStylesClass.apply_button_primary(_close_button)
	_close_button.pressed.connect(_on_close_pressed)
	row.add_child(_close_button)

func _grab_default_focus() -> void:
	if _close_button != null and is_instance_valid(_close_button):
		_close_button.grab_focus()

func _on_close_pressed() -> void:
	close()
	closed.emit()

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey:
		var e: InputEventKey = event
		if e.pressed and not e.echo and e.keycode == KEY_ESCAPE:
			_on_close_pressed()
			get_viewport().set_input_as_handled()
