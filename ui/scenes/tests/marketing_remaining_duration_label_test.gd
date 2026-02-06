# marketing remaining duration label regression test (no real rendering required)
# Ensures marketing pieces render remaining_duration as a centered label over the product icon.
class_name MarketingRemainingDurationLabelTest
extends RefCounted

const MapCanvasDrawerClass = preload("res://ui/scenes/game/map_canvas_drawer.gd")

class FakeSkin extends RefCounted:
	func get_marketing_texture(_key: String) -> Texture2D:
		return null

	func get_product_icon_texture(_product_id: String) -> Texture2D:
		return null

class FakeCanvas extends RefCounted:
	var _skin = null
	var strings: Array[Dictionary] = []

	func _init() -> void:
		_skin = FakeSkin.new()

	func draw_rect(_rect: Rect2, _color: Color, _filled: bool = true, _width: float = -1.0) -> void:
		pass

	func draw_circle(_pos: Vector2, _radius: float, _color: Color) -> void:
		pass

	func draw_string(_font: Font, pos: Vector2, text: String, alignment: int, width: float, font_size: int, color: Color) -> void:
		strings.append({
			"pos": pos,
			"text": text,
			"alignment": alignment,
			"width": width,
			"font_size": font_size,
			"color": color,
		})

	func draw_set_transform(_origin: Vector2, _rotation: float, _scale: Vector2) -> void:
		pass

static func run() -> Result:
	var cell_size := 40
	var placement := {
		"type": "billboard",
		"product": "burger",
		"remaining_duration": 3,
		"board_number": 0,
	}

	var canvas := FakeCanvas.new()
	MapCanvasDrawerClass._draw_marketing_placement(canvas, cell_size, placement, 1.0, Rect2(Vector2.ZERO, Vector2(cell_size, cell_size)))

	if canvas.strings.is_empty():
		return Result.failure("expected draw_string call for remaining duration label")

	var found := false
	for s_val in canvas.strings:
		if s_val is Dictionary and str(Dictionary(s_val).get("text", "")) == "3":
			found = true
			break
	if not found:
		return Result.failure("expected remaining duration text '3', got: %s" % str(canvas.strings))

	return Result.success({})

