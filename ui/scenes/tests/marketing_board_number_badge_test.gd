# marketing board number badge regression test (no real rendering required)
# Covers issue_tracker #37: marketing pieces should render a top-right number badge (white circle + black number).
class_name MarketingBoardNumberBadgeTest
extends RefCounted

const MapCanvasDrawerClass = preload("res://ui/scenes/game/map/drawer/drawer.gd")

class FakeSkin extends RefCounted:
	func get_marketing_texture(_key: String) -> Texture2D:
		return null

	func get_product_icon_texture(_product_id: String) -> Texture2D:
		return null

class FakeCanvas extends RefCounted:
	var _marketing_by_pos: Dictionary = {}
	var _map_data: Dictionary = {}
	var _base_grid_size: Vector2i = Vector2i.ZERO
	var _world_origin: Vector2i = Vector2i.ZERO
	var _skin = null

	var circles: Array[Dictionary] = []
	var strings: Array[Dictionary] = []

	func _init(map_data: Dictionary, base_grid_size: Vector2i, marketing_by_pos: Dictionary) -> void:
		_map_data = map_data.duplicate(true)
		_base_grid_size = base_grid_size
		_marketing_by_pos = marketing_by_pos.duplicate(true)
		_skin = FakeSkin.new()

	func _world_to_view(world_pos: Vector2i) -> Vector2i:
		return world_pos - _world_origin

	func _is_valid_world_pos(_world_pos: Vector2i) -> bool:
		return true

	func draw_rect(_rect: Rect2, _color: Color, _filled: bool = true, _width: float = -1.0) -> void:
		pass

	func draw_circle(pos: Vector2, radius: float, color: Color) -> void:
		circles.append({"pos": pos, "radius": radius, "color": color})

	func draw_string(_font: Font, pos: Vector2, text: String, alignment: int, width: float, font_size: int, color: Color) -> void:
		strings.append({
			"pos": pos,
			"text": text,
			"alignment": alignment,
			"width": width,
			"font_size": font_size,
			"color": color,
		})

static func run() -> Result:
	var map_data := {
		"map_origin": Vector2i.ZERO,
		"grid_size": Vector2i(10, 10),
	}
	var grid_size := Vector2i(10, 10)
	var cell_size := 10

	var anchor := Vector2i(2, 2)
	var placement := {
		"type": "billboard",
		"world_pos": anchor,
		"rotation": 0,
		"footprint_size": Vector2i(3, 2),
		"board_number": 11,
		"product": "",
	}

	var canvas := FakeCanvas.new(map_data, grid_size, {anchor: placement})
	MapCanvasDrawerClass._draw_marketing(canvas, cell_size)

	if canvas.circles.is_empty():
		return Result.failure("expected draw_circle call for board number badge")
	if canvas.strings.is_empty():
		return Result.failure("expected draw_string call for board number badge")

	var found := false
	for s_val in canvas.strings:
		if s_val is Dictionary and str(Dictionary(s_val).get("text", "")) == "11":
			found = true
			break
	if not found:
		return Result.failure("expected badge text '11', got: %s" % str(canvas.strings))

	return Result.success({})

