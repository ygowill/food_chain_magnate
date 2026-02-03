# 选项对话框组件
# 用于需要用户在多个选项中做选择的场景（例如：飞机角落方向选择）。
class_name ChoiceDialog
extends ModalDialogBase

signal option_selected(option_id: String)
signal cancelled()

const UiStylesClass = preload("res://ui/utils/ui_styles.gd")

@onready var dialog_root: Control = $Center/Dialog
@onready var background_panel: Panel = $Center/Dialog/BackgroundPanel
@onready var title_label: Label = $Center/Dialog/MarginContainer/VBoxContainer/TitleLabel
@onready var message_label: Label = $Center/Dialog/MarginContainer/VBoxContainer/MessageLabel
@onready var options_container: HFlowContainer = $Center/Dialog/MarginContainer/VBoxContainer/OptionsRow
@onready var cancel_row: Control = $Center/Dialog/MarginContainer/VBoxContainer/CancelRow
@onready var cancel_btn: Button = $Center/Dialog/MarginContainer/VBoxContainer/CancelRow/CancelButton
@onready var margin_container: MarginContainer = $Center/Dialog/MarginContainer

var _options: Array[Dictionary] = []
var _base_size: Vector2i = Vector2i.ZERO
var _allow_cancel: bool = true

func _ready() -> void:
	super._ready()
	UiStylesClass.apply_dialog_surface(background_panel)
	UiStylesClass.apply_button_secondary(cancel_btn)
	if dialog_root != null and is_instance_valid(dialog_root):
		_base_size = Vector2i(dialog_root.custom_minimum_size)
	if cancel_btn != null:
		cancel_btn.pressed.connect(_on_cancel_pressed)

func setup(title: String, message: String, options: Array[Dictionary], cancel_text: String = "取消") -> void:
	_options = options.duplicate(true)
	if title_label != null:
		title_label.text = title
	if message_label != null:
		message_label.text = message
	if cancel_btn != null:
		_allow_cancel = not str(cancel_text).is_empty()
		cancel_btn.text = cancel_text
	if cancel_row != null:
		cancel_row.visible = _allow_cancel

	if _base_size != Vector2i.ZERO:
		if dialog_root != null and is_instance_valid(dialog_root):
			dialog_root.custom_minimum_size = Vector2(_base_size.x, _base_size.y)
	_rebuild_options()
	_apply_auto_height_for_options()

func _grab_default_focus() -> void:
	if options_container != null:
		for child in options_container.get_children():
			if child is Button and (child as Button).visible and not (child as Button).disabled:
				(child as Button).grab_focus()
				return
	if cancel_btn != null:
		cancel_btn.grab_focus()

func _rebuild_options() -> void:
	if options_container == null:
		return

	options_container.custom_minimum_size = Vector2.ZERO
	for child in options_container.get_children():
		child.queue_free()

	for opt_val in _options:
		if not (opt_val is Dictionary):
			continue
		var opt: Dictionary = opt_val
		var option_id := str(opt.get("id", "")).strip_edges()
		var text := str(opt.get("text", option_id)).strip_edges()
		if option_id.is_empty():
			continue

		var btn := Button.new()
		btn.text = text if not text.is_empty() else option_id
		btn.custom_minimum_size = Vector2(110, 34)
		UiStylesClass.apply_button_secondary(btn)
		btn.pressed.connect(_on_option_pressed.bind(option_id))
		options_container.add_child(btn)

func _apply_auto_height_for_options() -> void:
	if options_container == null:
		return
	if _base_size == Vector2i.ZERO:
		if dialog_root != null and is_instance_valid(dialog_root):
			_base_size = Vector2i(dialog_root.custom_minimum_size)

	var buttons: Array[Control] = []
	for ch in options_container.get_children():
		if ch is Control and ch.visible:
			buttons.append(ch)

	if buttons.is_empty():
		options_container.custom_minimum_size = Vector2.ZERO
		if _base_size != Vector2i.ZERO:
			if dialog_root != null and is_instance_valid(dialog_root):
				dialog_root.custom_minimum_size = Vector2(_base_size.x, _base_size.y)
		return

	var available_width := float(_base_size.x)
	if margin_container != null:
		available_width -= float(margin_container.get_theme_constant("margin_left") + margin_container.get_theme_constant("margin_right"))
	available_width = maxf(0.0, available_width)
	available_width = maxf(0.0, available_width - 4.0) # 预留一点误差，避免临界换行导致高度不足

	var h_sep := float(options_container.get_theme_constant("h_separation"))
	var v_sep := float(options_container.get_theme_constant("v_separation"))

	var rows := 1
	var row_w := 0.0
	var row_items := 0
	var btn_h := 0.0

	for ch2 in buttons:
		var c: Control = ch2
		var min_s := c.get_combined_minimum_size()
		var w := maxf(c.custom_minimum_size.x, min_s.x)
		var h := maxf(c.custom_minimum_size.y, min_s.y)
		btn_h = maxf(btn_h, h)

		var needed := w + (h_sep if row_items > 0 else 0.0)
		if row_items > 0 and available_width > 0.0 and (row_w + needed) > available_width:
			rows += 1
			row_w = w
			row_items = 1
		else:
			row_w += needed
			row_items += 1

	var required_options_h := float(rows) * btn_h + float(maxi(0, rows - 1)) * v_sep
	options_container.custom_minimum_size = Vector2(0.0, required_options_h)

	if _base_size == Vector2i.ZERO:
		return
	var extra_rows := maxi(0, rows - 1)
	var target_h := _base_size.y + int(round(float(extra_rows) * (btn_h + v_sep)))

	var viewport_h := 0
	var tree := get_tree()
	if tree != null and tree.root != null:
		viewport_h = int(tree.root.get_visible_rect().size.y)
	if viewport_h > 0:
		target_h = mini(target_h, int(round(float(viewport_h) * 0.9)))
	target_h = maxi(target_h, _base_size.y)
	if dialog_root != null and is_instance_valid(dialog_root):
		dialog_root.custom_minimum_size = Vector2(_base_size.x, target_h)

func _on_option_pressed(option_id: String) -> void:
	close()
	option_selected.emit(option_id)

func _on_cancel_pressed() -> void:
	close()
	cancelled.emit()

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey:
		var e: InputEventKey = event
		if e.pressed and not e.echo and e.keycode == KEY_ESCAPE:
			if _allow_cancel:
				_on_cancel_pressed()
				get_viewport().set_input_as_handled()
