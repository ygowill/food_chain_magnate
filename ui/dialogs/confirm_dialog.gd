# 确认对话框组件
# 通用确认/取消对话框
class_name ConfirmDialog
extends Window

signal confirmed()
signal cancelled()

@onready var title_label: Label = $MarginContainer/VBoxContainer/TitleLabel
@onready var message_label: Label = $MarginContainer/VBoxContainer/MessageLabel
@onready var confirm_btn: Button = $MarginContainer/VBoxContainer/ButtonRow/ConfirmButton
@onready var cancel_btn: Button = $MarginContainer/VBoxContainer/ButtonRow/CancelButton

var _confirm_text: String = "确认"
var _cancel_text: String = "取消"

func _ready() -> void:
	if confirm_btn != null:
		confirm_btn.pressed.connect(_on_confirm_pressed)
	if cancel_btn != null:
		cancel_btn.pressed.connect(_on_cancel_pressed)

	close_requested.connect(_on_cancel_pressed)

func setup(title: String, message: String, confirm_text: String = "确认", cancel_text: String = "取消") -> void:
	if title_label != null:
		title_label.text = title
	if message_label != null:
		message_label.text = message
	if confirm_btn != null:
		confirm_btn.text = confirm_text
	if cancel_btn != null:
		cancel_btn.text = cancel_text

	_confirm_text = confirm_text
	_cancel_text = cancel_text

func show_dialog() -> void:
	popup_centered()

func _on_confirm_pressed() -> void:
	hide()
	confirmed.emit()

func _on_cancel_pressed() -> void:
	hide()
	cancelled.emit()

# 便捷静态方法
static func show_confirm(parent: Node, title: String, message: String, on_confirm: Callable, on_cancel: Callable = Callable()) -> ConfirmDialog:
	var dialog := ConfirmDialog.new()
	dialog.title = title

	# 手动构建 UI（因为静态方法无法加载场景）
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	dialog.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	margin.add_child(vbox)

	var title_lbl := Label.new()
	title_lbl.text = title
	title_lbl.add_theme_font_size_override("font_size", 18)
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title_lbl)

	var msg_lbl := Label.new()
	msg_lbl.text = message
	msg_lbl.add_theme_font_size_override("font_size", 14)
	msg_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	msg_lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(msg_lbl)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 20)
	vbox.add_child(btn_row)

	var cancel_btn := Button.new()
	cancel_btn.text = "取消"
	cancel_btn.custom_minimum_size = Vector2(80, 32)
	cancel_btn.pressed.connect(func():
		dialog.hide()
		dialog.queue_free()
		if on_cancel.is_valid():
			on_cancel.call()
	)
	btn_row.add_child(cancel_btn)

	var confirm_btn := Button.new()
	confirm_btn.text = "确认"
	confirm_btn.custom_minimum_size = Vector2(80, 32)
	confirm_btn.pressed.connect(func():
		dialog.hide()
		dialog.queue_free()
		if on_confirm.is_valid():
			on_confirm.call()
	)
	btn_row.add_child(confirm_btn)

	dialog.size = Vector2i(350, 180)
	dialog.transient = true

	parent.add_child(dialog)
	dialog.popup_centered()

	return dialog
