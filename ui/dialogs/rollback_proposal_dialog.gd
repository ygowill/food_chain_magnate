# 联机回滚提议目标选择弹窗
class_name RollbackProposalDialog
extends ModalDialogBase

signal target_selected(target_index: int)
signal cancelled()

const UiStylesClass = preload("res://ui/utils/ui_styles.gd")

var _dialog_panel: PanelContainer = null
var _title_label: Label = null
var _message_label: Label = null
var _target_list: ItemList = null
var _error_label: Label = null
var _confirm_button: Button = null
var _cancel_button: Button = null
var _target_options: Array[Dictionary] = []

func _init() -> void:
	_build_ui()

func _ready() -> void:
	super._ready()
	_apply_styles()

func open_for_targets(target_options: Array[Dictionary]) -> void:
	_target_options = target_options.duplicate(true)
	_rebuild_target_list()
	_set_error("")
	open()

func _build_ui() -> void:
	var overlay_rect := ColorRect.new()
	overlay_rect.name = "Overlay"
	overlay_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, 0)
	overlay_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay_rect)

	var center := CenterContainer.new()
	center.name = "Center"
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, 0)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	_dialog_panel = PanelContainer.new()
	_dialog_panel.custom_minimum_size = Vector2(560, 460)
	_dialog_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	center.add_child(_dialog_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_bottom", 18)
	_dialog_panel.add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)

	_title_label = Label.new()
	_title_label.text = "提议回滚"
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 18)
	root.add_child(_title_label)

	_message_label = Label.new()
	_message_label.text = "选择要回滚到的时间点。投票弹窗会明确显示该时间点，全部其他玩家同意后立即执行。"
	_message_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	root.add_child(_message_label)

	_target_list = ItemList.new()
	_target_list.allow_reselect = true
	_target_list.select_mode = ItemList.SELECT_SINGLE
	_target_list.custom_minimum_size = Vector2(0, 260)
	_target_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_target_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_target_list.item_activated.connect(_on_target_item_activated)
	root.add_child(_target_list)

	_error_label = Label.new()
	_error_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_error_label.visible = false
	root.add_child(_error_label)

	var button_row := HBoxContainer.new()
	button_row.alignment = BoxContainer.ALIGNMENT_END
	button_row.add_theme_constant_override("separation", 10)
	root.add_child(button_row)

	_cancel_button = Button.new()
	_cancel_button.text = "取消"
	_cancel_button.custom_minimum_size = Vector2(90, 34)
	_cancel_button.pressed.connect(_on_cancel_pressed)
	button_row.add_child(_cancel_button)

	_confirm_button = Button.new()
	_confirm_button.text = "确认提议"
	_confirm_button.custom_minimum_size = Vector2(110, 34)
	_confirm_button.pressed.connect(_on_confirm_pressed)
	button_row.add_child(_confirm_button)

func _apply_styles() -> void:
	var overlay_rect := get_node_or_null("Overlay") as ColorRect
	if overlay_rect != null:
		overlay_rect.color = overlay_color
	if _dialog_panel != null:
		UiStylesClass.apply_dialog_surface(_dialog_panel)
	if _title_label != null:
		UiStylesClass.apply_label_dark(_title_label)
	if _message_label != null:
		UiStylesClass.apply_label_dark(_message_label)
	if _target_list != null:
		UiStylesClass.apply_item_list_surface(_target_list)
	if _error_label != null:
		UiStylesClass.apply_label_error(_error_label)
	if _confirm_button != null:
		UiStylesClass.apply_button_primary(_confirm_button)
	if _cancel_button != null:
		UiStylesClass.apply_button_secondary(_cancel_button)

func _rebuild_target_list() -> void:
	if _target_list == null:
		return
	_target_list.clear()
	for opt_val in _target_options:
		if not (opt_val is Dictionary):
			continue
		var opt: Dictionary = opt_val
		var label := str(opt.get("label", "")).strip_edges()
		if label.is_empty():
			continue
		var idx := _target_list.item_count
		_target_list.add_item(label)
		_target_list.set_item_metadata(idx, int(opt.get("target_index", -1)))
	if _target_list.item_count > 0:
		_target_list.select(0)
	if _confirm_button != null:
		_confirm_button.disabled = _target_list.item_count <= 0

func _grab_default_focus() -> void:
	if _target_list != null and _target_list.item_count > 0:
		_target_list.grab_focus()
	elif _cancel_button != null:
		_cancel_button.grab_focus()

func _set_error(message: String) -> void:
	if _error_label == null:
		return
	var msg := str(message).strip_edges()
	_error_label.text = msg
	_error_label.visible = not msg.is_empty()

func _on_target_item_activated(_index: int) -> void:
	_on_confirm_pressed()

func _on_confirm_pressed() -> void:
	if _target_list == null:
		return
	var selected := _target_list.get_selected_items()
	if selected.is_empty():
		_set_error("请选择一个回滚时间点")
		return
	var item_idx := int(selected[0])
	var meta = _target_list.get_item_metadata(item_idx)
	close()
	target_selected.emit(int(meta))

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
