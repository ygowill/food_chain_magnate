# tile 内部细分网格线回归测试（无需真实渲染）
# 覆盖 issue_tracker #32：tile 内部应绘制细线分割每个单元格，线宽随 zoom 缩放。
class_name TileInternalGridLinesTest
extends RefCounted

const MapCanvasDrawerClass = preload("res://ui/scenes/game/map/drawer/drawer.gd")
const MapUtilsClass = preload("res://core/map/map_utils.gd")

class FakeCanvas extends RefCounted:
	var _map_data: Dictionary = {}
	var rect_calls: Array[Dictionary] = []

	func _init(map_data: Dictionary) -> void:
		_map_data = map_data.duplicate(true)

	func _world_to_view(world_pos: Vector2i) -> Vector2i:
		# 测试中不做滚动/缩放偏移：直接视为 view 坐标
		return world_pos

	func draw_rect(rect: Rect2, color: Color, filled: bool = true, width: float = -1.0) -> void:
		rect_calls.append({
			"rect": rect,
			"color": color,
			"filled": filled,
			"width": width,
		})

static func run() -> Result:
	var map_data := {
		"tile_placements": [
			{"board_pos": Vector2i(0, 0)},
		],
	}

	var r1 := _assert_inner_lines(map_data, 40, 1.0)
	if not r1.ok:
		return r1

	return _assert_inner_lines(map_data, 100, 2.0)

static func _assert_inner_lines(map_data: Dictionary, cell_size: int, expected_thickness: float) -> Result:
	var canvas := FakeCanvas.new(map_data)
	MapCanvasDrawerClass._draw_tile_borders(canvas, cell_size)

	var inner: Array[Rect2] = []
	for call_val in canvas.rect_calls:
		if not (call_val is Dictionary):
			continue
		var call: Dictionary = call_val
		var col_val = call.get("color", null)
		var rect_val = call.get("rect", null)
		if not (col_val is Color) or not (rect_val is Rect2):
			continue
		var col: Color = col_val
		var rect: Rect2 = rect_val
		if is_equal_approx(col.a, 0.25):
			inner.append(rect)

	var tile_size := int(MapUtilsClass.TILE_SIZE)
	var expected_count := maxi(0, (tile_size - 1) * 2)
	if inner.size() != expected_count:
		return Result.failure("inner grid line count=%d (expected %d) cell_size=%d" % [inner.size(), expected_count, cell_size])

	for r in inner:
		var t := r.size.x if r.size.x < r.size.y else r.size.y
		if not is_equal_approx(float(t), float(expected_thickness)):
			return Result.failure("inner grid thickness=%s (expected %s) cell_size=%d rect=%s" % [str(t), str(expected_thickness), cell_size, str(r)])

	return Result.success({
		"cell_size": cell_size,
		"inner_count": inner.size(),
		"expected_count": expected_count,
	})
