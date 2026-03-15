extends Control

var color: Color = Color.WHITE:
	set(v):
		color = v
		queue_redraw()

var filled: bool = false:
	set(v):
		filled = v
		queue_redraw()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return

	var s := minf(size.x, size.y)
	var radius := s * 0.32
	var center := size * 0.5
	if filled:
		draw_circle(center, radius, color)
		return

	var stroke := maxf(1.5, s * 0.12)
	draw_arc(center, radius, 0.0, TAU, 24, color, stroke, true)
