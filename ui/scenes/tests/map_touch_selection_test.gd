class_name MapTouchSelectionTest
extends RefCounted

const MapCanvasClass = preload("res://ui/scenes/game/map/canvas.gd")
const UiPointerInputClass = preload("res://ui/utils/pointer_input.gd")

static func run() -> Result:
	var canvas = MapCanvasClass.new()
	if canvas == null or not is_instance_valid(canvas):
		return Result.failure("无法创建 MapCanvas")

	canvas.set_map_data({
		"grid_size": Vector2i(2, 2),
		"map_origin": Vector2i.ZERO,
		"cells": [
			[{}, {}],
			[{}, {}],
		],
	})

	var origin := Vector2i.ZERO
	if canvas.has_method("get_world_origin"):
		var origin_val = canvas.call("get_world_origin")
		if origin_val is Vector2i:
			origin = Vector2i(origin_val)

	var cell_size := 40
	if canvas.has_method("get_cell_size"):
		cell_size = int(canvas.call("get_cell_size"))

	var touch := InputEventScreenTouch.new()
	touch.pressed = true
	var view_pos := Vector2i.ZERO - origin
	touch.position = Vector2(
		float(view_pos.x * cell_size + (cell_size / 2)),
		float(view_pos.y * cell_size + (cell_size / 2))
	)

	if not UiPointerInputClass.is_primary_press(touch):
		_safe_free(canvas)
		return Result.failure("ScreenTouch 未被识别为主指针按下")

	var mapped = canvas.call("_local_to_world_cell", UiPointerInputClass.get_position(touch))
	if not (mapped is Vector2i):
		_safe_free(canvas)
		return Result.failure("MapCanvas._local_to_world_cell 返回类型错误: %s" % str(mapped))
	if Vector2i(mapped) != Vector2i.ZERO:
		_safe_free(canvas)
		return Result.failure("触摸坐标未映射到左上角格子，实际: %s" % str(mapped))

	_safe_free(canvas)
	return Result.success()

static func _safe_free(node: Node) -> void:
	if node != null and is_instance_valid(node):
		node.free()
