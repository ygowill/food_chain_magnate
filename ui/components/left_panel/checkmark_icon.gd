extends Control

var color: Color = Color.WHITE:
	set(v):
		color = v
		queue_redraw()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return

	var s := minf(size.x, size.y)
	# Keep the checkmark readable at small sizes.
	var stroke := maxf(2.0, s * 0.16)
	var origin := (size - Vector2(s, s)) * 0.5

	var p1 := origin + Vector2(s * 0.22, s * 0.56)
	var p2 := origin + Vector2(s * 0.42, s * 0.76)
	var p3 := origin + Vector2(s * 0.80, s * 0.30)

	draw_polyline(PackedVector2Array([p1, p2, p3]), color, stroke, true)
