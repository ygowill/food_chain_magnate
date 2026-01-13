# 地图缩放属性回归测试（无需渲染）
# 覆盖 issue_tracker #1：MapCanvas 缩放应同步影响 cell_size、拾取与 custom_minimum_size。
class_name MapZoomPropertyTest
extends RefCounted

const MapCanvasClass = preload("res://ui/scenes/game/map_canvas.gd")

static func run() -> Result:
	var canvas = MapCanvasClass.new()
	if canvas == null or not is_instance_valid(canvas):
		return Result.failure("无法创建 MapCanvas")

	var map_data := {
		"grid_size": Vector2i(2, 2),
		"map_origin": Vector2i.ZERO,
		"cells": [
			[{}, {}],
			[{}, {}],
		],
	}
	canvas.set_map_data(map_data)

	if canvas.has_method("get_world_origin"):
		var origin = canvas.call("get_world_origin")
		if origin is Vector2i and origin != Vector2i.ZERO:
			_safe_free(canvas)
			return Result.failure("MapCanvas.world_origin=%s (期望 %s)" % [str(origin), str(Vector2i.ZERO)])

	if not canvas.has_method("get_cell_size"):
		_safe_free(canvas)
		return Result.failure("MapCanvas 缺少 get_cell_size()")

	var base_cell_size := int(canvas.call("get_cell_size"))
	if base_cell_size != 40:
		_safe_free(canvas)
		return Result.failure("MapCanvas base cell_size=%d (期望 40)" % base_cell_size)

	if canvas.custom_minimum_size != Vector2(float(2 * base_cell_size), float(2 * base_cell_size)):
		var expected_min := Vector2(float(2 * base_cell_size), float(2 * base_cell_size))
		var actual_min = canvas.custom_minimum_size
		_safe_free(canvas)
		return Result.failure("MapCanvas.custom_minimum_size=%s (期望 %s)" % [str(actual_min), str(expected_min)])

	canvas.call("set_zoom", 1.5)
	var zoom_cell_size := int(canvas.call("get_cell_size"))
	if zoom_cell_size != 60:
		_safe_free(canvas)
		return Result.failure("MapCanvas zoom(1.5) cell_size=%d (期望 60)" % zoom_cell_size)

	var expected_min2 := Vector2(float(2 * zoom_cell_size), float(2 * zoom_cell_size))
	if not canvas.custom_minimum_size.is_equal_approx(expected_min2):
		var actual_min2 = canvas.custom_minimum_size
		_safe_free(canvas)
		return Result.failure("MapCanvas.zoom custom_minimum_size=%s (期望 %s)" % [str(actual_min2), str(expected_min2)])

	if not canvas.has_method("_local_to_world_cell"):
		_safe_free(canvas)
		return Result.failure("MapCanvas 缺少 _local_to_world_cell()（拾取回归测试无法执行）")

	var p0 = canvas.call("_local_to_world_cell", Vector2(float(zoom_cell_size - 1), 0.0))
	var p1 = canvas.call("_local_to_world_cell", Vector2(float(zoom_cell_size + 1), 0.0))
	if not (p0 is Vector2i) or not (p1 is Vector2i):
		_safe_free(canvas)
		return Result.failure("MapCanvas._local_to_world_cell 返回类型错误")

	if Vector2i(p0) != Vector2i(0, 0) or Vector2i(p1) != Vector2i(1, 0):
		_safe_free(canvas)
		return Result.failure("MapCanvas._local_to_world_cell 结果错误: p0=%s p1=%s (期望 (0,0)/(1,0))" % [str(p0), str(p1)])

	_safe_free(canvas)
	return Result.success({
		"base_cell_size": base_cell_size,
		"zoom_cell_size": zoom_cell_size,
	})

static func _safe_free(node: Node) -> void:
	if node != null and is_instance_valid(node):
		node.free()
