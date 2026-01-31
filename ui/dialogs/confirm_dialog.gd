# 确认对话框组件
# 通用确认/取消对话框
class_name ConfirmDialog
extends ModalDialogBase

signal confirmed()
signal cancelled()

const UiStylesClass = preload("res://ui/utils/ui_styles.gd")

@onready var background_panel: Panel = $Center/Dialog/BackgroundPanel
@onready var title_label: Label = $Center/Dialog/MarginContainer/VBoxContainer/TitleLabel
@onready var message_label: Label = $Center/Dialog/MarginContainer/VBoxContainer/MessageScroll/MessageContainer/MessageLabel
@onready var confirm_btn: Button = $Center/Dialog/MarginContainer/VBoxContainer/ButtonRow/ConfirmButton
@onready var cancel_btn: Button = $Center/Dialog/MarginContainer/VBoxContainer/ButtonRow/CancelButton

var _confirm_text: String = "确认"
var _cancel_text: String = "取消"

func _ready() -> void:
	super._ready()
	UiStylesClass.apply_dialog_surface(background_panel)
	UiStylesClass.apply_button_primary(confirm_btn)
	UiStylesClass.apply_button_secondary(cancel_btn)

	if confirm_btn != null:
		confirm_btn.pressed.connect(_on_confirm_pressed)
	if cancel_btn != null:
		cancel_btn.pressed.connect(_on_cancel_pressed)

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

func _grab_default_focus() -> void:
	if cancel_btn != null:
		cancel_btn.grab_focus()

func _on_confirm_pressed() -> void:
	close()
	confirmed.emit()

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

# 便捷静态方法
static func show_confirm(parent: Node, title: String, message: String, on_confirm: Callable, on_cancel: Callable = Callable()) -> ConfirmDialog:
	var scene: PackedScene = load("res://ui/dialogs/confirm_dialog.tscn")
	if scene == null:
		return null

	var dialog_val := scene.instantiate()
	if not (dialog_val is ConfirmDialog):
		if dialog_val != null:
			dialog_val.queue_free()
		return null
	var dialog: ConfirmDialog = dialog_val
	parent.add_child(dialog)

	dialog.setup(title, message)
	dialog.confirmed.connect(func() -> void:
		if on_confirm.is_valid():
			on_confirm.call()
		dialog.queue_free()
	)
	dialog.cancelled.connect(func() -> void:
		if on_cancel.is_valid():
			on_cancel.call()
		dialog.queue_free()
	)
	dialog.show_dialog()
	return dialog
