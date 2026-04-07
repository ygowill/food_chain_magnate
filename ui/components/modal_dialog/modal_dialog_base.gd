# Control-based modal dialog base.
# - Avoids Window titlebar styling limits.
# - Fullscreen overlay that blocks input behind.
class_name ModalDialogBase
extends Control

const ModalDialogUiZClass = preload("res://ui/utils/ui_z.gd")

@export var overlay_color: Color = Color(0, 0, 0, 0.62)

@onready var overlay: ColorRect = get_node_or_null("Overlay") as ColorRect

func _ready() -> void:
	visible = false
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process_unhandled_input(true)
	ModalDialogUiZClass.apply_absolute(self, ModalDialogUiZClass.MODAL)

	_apply_full_rect_layout()

	if overlay != null:
		overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, 0)
		overlay.color = overlay_color
		overlay.mouse_filter = Control.MOUSE_FILTER_STOP

func open() -> void:
	visible = true
	_bring_to_front()
	call_deferred("_apply_full_rect_layout")
	grab_focus()
	if has_method("_grab_default_focus"):
		call_deferred("_grab_default_focus")

func close() -> void:
	visible = false

func show_dialog() -> void:
	open()

func _apply_full_rect_layout() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, 0)
	position = Vector2.ZERO
	var p := get_parent()
	if visible and p is Control:
		size = (p as Control).size

func _bring_to_front() -> void:
	var p := get_parent()
	if p == null:
		return
	p.move_child(self, p.get_child_count() - 1)
