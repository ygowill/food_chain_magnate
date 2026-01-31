# Control-based modal dialog base.
# - Avoids Window titlebar styling limits.
# - Fullscreen overlay that blocks input behind.
class_name ModalDialogBase
extends Control

@export var overlay_color: Color = Color(0, 0, 0, 0.62)

@onready var overlay: ColorRect = get_node_or_null("Overlay") as ColorRect

func _ready() -> void:
	visible = false
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process_unhandled_input(true)

	set_anchors_preset(Control.PRESET_FULL_RECT)

	if overlay != null:
		overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
		overlay.color = overlay_color
		overlay.mouse_filter = Control.MOUSE_FILTER_STOP

func open() -> void:
	visible = true
	_bring_to_front()
	grab_focus()
	if has_method("_grab_default_focus"):
		call_deferred("_grab_default_focus")

func close() -> void:
	visible = false

func show_dialog() -> void:
	open()

func _bring_to_front() -> void:
	var p := get_parent()
	if p == null:
		return
	p.move_child(self, p.get_child_count() - 1)
