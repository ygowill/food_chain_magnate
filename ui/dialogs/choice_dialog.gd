# 选项对话框组件
# 用于需要用户在多个选项中做选择的场景（例如：飞机角落方向选择）。
class_name ChoiceDialog
extends Window

signal option_selected(option_id: String)
signal cancelled()

const UiStylesClass = preload("res://ui/utils/ui_styles.gd")

@onready var background_panel: Panel = $BackgroundPanel
@onready var title_label: Label = $MarginContainer/VBoxContainer/TitleLabel
@onready var message_label: Label = $MarginContainer/VBoxContainer/MessageLabel
@onready var options_container: HFlowContainer = $MarginContainer/VBoxContainer/OptionsRow
@onready var cancel_btn: Button = $MarginContainer/VBoxContainer/CancelRow/CancelButton
@onready var margin_container: MarginContainer = $MarginContainer

var _options: Array[Dictionary] = []
var _base_size: Vector2i = Vector2i.ZERO

func _ready() -> void:
	UiStylesClass.apply_dialog_surface(background_panel)
	UiStylesClass.apply_button_secondary(cancel_btn)
	_base_size = size
	if cancel_btn != null:
		cancel_btn.pressed.connect(_on_cancel_pressed)
	close_requested.connect(_on_cancel_pressed)

func setup(title: String, message: String, options: Array[Dictionary], cancel_text: String = "取消") -> void:
	_options = options.duplicate(true)
	if title_label != null:
		title_label.text = title
	if message_label != null:
		message_label.text = message
	if cancel_btn != null:
		cancel_btn.text = cancel_text

	if _base_size != Vector2i.ZERO:
		size = _base_size
	_rebuild_options()
	_apply_auto_height_for_options()

func show_dialog() -> void:
	popup_centered()

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
		_base_size = size

	var buttons: Array[Control] = []
	for ch in options_container.get_children():
		if ch is Control and ch.visible:
			buttons.append(ch)

	if buttons.is_empty():
		options_container.custom_minimum_size = Vector2.ZERO
		if _base_size != Vector2i.ZERO:
			size = _base_size
		return

	var available_width := float(size.x)
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
	size = Vector2i(_base_size.x, target_h)

func _on_option_pressed(option_id: String) -> void:
	hide()
	option_selected.emit(option_id)

func _on_cancel_pressed() -> void:
	hide()
	cancelled.emit()
