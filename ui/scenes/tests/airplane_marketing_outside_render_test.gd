# airplane marketing rect placement regression test (no real rendering required)
# Covers issue_tracker #30: airplane boards should render flush outside the base map edge.
class_name AirplaneMarketingOutsideRenderTest
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

	var filled_rects: Array[Rect2] = []

	func _init(map_data: Dictionary, base_grid_size: Vector2i, marketing_by_pos: Dictionary) -> void:
		_map_data = map_data.duplicate(true)
		_base_grid_size = base_grid_size
		_marketing_by_pos = marketing_by_pos.duplicate(true)
		_skin = FakeSkin.new()

	func _world_to_view(world_pos: Vector2i) -> Vector2i:
		return world_pos - _world_origin

	func _is_valid_world_pos(_world_pos: Vector2i) -> bool:
		# Tests validate geometry only; assume bounds are valid.
		return true

	func draw_rect(rect: Rect2, _color: Color, filled: bool = true, _width: float = -1.0) -> void:
		if filled:
			filled_rects.append(rect)

	func draw_set_transform(_origin: Vector2, _rotation: float, _scale: Vector2) -> void:
		# No-op for geometry-only tests; MapCanvasDrawer may rotate airplane textures.
		pass

static func run() -> Result:
	var map_data := {
		"map_origin": Vector2i.ZERO,
		"grid_size": Vector2i(10, 10),
	}
	var grid_size := Vector2i(10, 10)
	var cell_size := 10

	var r1 := _assert_airplane_rect(map_data, grid_size, cell_size, {
		"name": "left",
		"anchor": Vector2i(0, 2),
		"footprint_size": Vector2i(3, 2),
		"rotation": 0,
		"axis": "row",
		"expected_pos": Vector2(-20, 20),
		"expected_size": Vector2(20, 30),
	})
	if not r1.ok:
		return r1

	var r2 := _assert_airplane_rect(map_data, grid_size, cell_size, {
		"name": "right",
		"anchor": Vector2i(8, 2),
		"footprint_size": Vector2i(3, 2),
		"rotation": 0,
		"axis": "row",
		"expected_pos": Vector2(100, 20),
		"expected_size": Vector2(20, 30),
	})
	if not r2.ok:
		return r2

	var r3 := _assert_airplane_rect(map_data, grid_size, cell_size, {
		"name": "top",
		"anchor": Vector2i(2, 0),
		"footprint_size": Vector2i(3, 2),
		"rotation": 0,
		"axis": "col",
		"expected_pos": Vector2(20, -20),
		"expected_size": Vector2(30, 20),
	})
	if not r3.ok:
		return r3

	var r4 := _assert_airplane_rect(map_data, grid_size, cell_size, {
		"name": "bottom",
		"anchor": Vector2i(2, 8),
		"footprint_size": Vector2i(3, 2),
		"rotation": 0,
		"axis": "col",
		"expected_pos": Vector2(20, 100),
		"expected_size": Vector2(30, 20),
	})
	if not r4.ok:
		return r4

	var r5 := _assert_airplane_rect(map_data, grid_size, cell_size, {
		"name": "corner_row_prefers_left",
		"anchor": Vector2i(0, 0),
		"footprint_size": Vector2i(3, 2),
		"rotation": 0,
		"axis": "row",
		"expected_pos": Vector2(-20, 0),
		"expected_size": Vector2(20, 30),
	})
	if not r5.ok:
		return r5

	return _assert_airplane_rect(map_data, grid_size, cell_size, {
		"name": "corner_col_prefers_top",
		"anchor": Vector2i(0, 0),
		"footprint_size": Vector2i(3, 2),
		"rotation": 0,
		"axis": "col",
		"expected_pos": Vector2(0, -20),
		"expected_size": Vector2(30, 20),
	})

static func _assert_airplane_rect(map_data: Dictionary, grid_size: Vector2i, cell_size: int, spec: Dictionary) -> Result:
	var name := str(spec.get("name", "case"))
	var anchor: Vector2i = spec.get("anchor", Vector2i.ZERO)
	var footprint_size: Vector2i = spec.get("footprint_size", Vector2i.ONE)
	var rotation := int(spec.get("rotation", 0))
	var axis := str(spec.get("axis", ""))

	var placement := {
		"type": "airplane",
		"world_pos": anchor,
		"rotation": rotation,
		"footprint_size": footprint_size,
		"axis": axis,
	}

	var canvas := FakeCanvas.new(map_data, grid_size, {anchor: placement})
	MapCanvasDrawerClass._draw_marketing(canvas, cell_size)

	var expected_pos: Vector2 = spec.get("expected_pos", Vector2.ZERO)
	var expected_size: Vector2 = spec.get("expected_size", Vector2.ZERO)
	var rect_read := _find_expected_airplane_rect(canvas.filled_rects, expected_pos, expected_size)
	if not rect_read.ok:
		return Result.failure("%s: %s" % [name, rect_read.error])

	return Result.success({"case": name})

static func _find_expected_airplane_rect(rects: Array[Rect2], expected_pos: Vector2, expected_size: Vector2) -> Result:
	if rects.is_empty():
		return Result.failure("expected a filled rect draw call")

	var same_size_positions: Array[String] = []
	for rect in rects:
		if not rect.size.is_equal_approx(expected_size):
			continue
		if rect.position.is_equal_approx(expected_pos):
			return Result.success(rect)
		same_size_positions.append(str(rect.position))

	if same_size_positions.is_empty():
		return Result.failure("no filled rect with expected size=%s; rects=%s" % [str(expected_size), str(rects)])
	return Result.failure("no filled rect at expected position=%s with size=%s; same-size positions=%s" % [str(expected_pos), str(expected_size), str(same_size_positions)])
