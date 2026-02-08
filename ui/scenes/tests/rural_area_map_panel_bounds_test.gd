# Rural Area map panel bounds regression test (no rendering required)
# Ensures MapCanvas can extend its bounds with a right-side module panel without using external_cells.
class_name RuralAreaMapPanelBoundsTest
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

	if not canvas.has_method("get_cell_size"):
		_safe_free(canvas)
		return Result.failure("MapCanvas 缺少 get_cell_size()")
	var cell_size := int(canvas.call("get_cell_size"))

	var applied_margin := 0
	if canvas.has_method("get_ui_outside_margin_applied"):
		applied_margin = int(canvas.call("get_ui_outside_margin_applied"))

	# Register a right-side panel (same size as Rural Area panel in the module).
	if not canvas.has_method("register_map_extension_panel"):
		_safe_free(canvas)
		return Result.failure("MapCanvas 缺少 register_map_extension_panel()")
	canvas.call("register_map_extension_panel", "test:rural_panel", RefCounted.new(), 8, 8)

	var expected_content_x := 2 + applied_margin * 2
	var expected_content_y := 2 + applied_margin * 2
	var expected_extra_right := 2 + 8 + 1 # gap + width + outer_pad
	var expected_cells_x := expected_content_x + expected_extra_right

	# Panel is taller than the base map; MapCanvas should extend downward to fit it (+ outer_pad).
	var base_max_y := (2 - 1) + applied_margin
	var expected_bottom_y := (0 + 8 - 1) + 1 # stack_top=0, height=8, outer_pad=1
	var expected_extra_bottom := maxi(0, int(expected_bottom_y - base_max_y))
	var expected_cells_y := expected_content_y + expected_extra_bottom

	var expected_min := Vector2(float(expected_cells_x * cell_size), float(expected_cells_y * cell_size))
	if canvas.custom_minimum_size != expected_min:
		var actual_min = canvas.custom_minimum_size
		_safe_free(canvas)
		return Result.failure("MapCanvas.custom_minimum_size=%s (期望 %s)" % [str(actual_min), str(expected_min)])

	# Panel region should be marked as non-interactive.
	if not canvas.has_method("is_world_pos_in_extension_panel") or not canvas.has_method("is_interactive_world_pos"):
		_safe_free(canvas)
		return Result.failure("MapCanvas 缺少 extension/interactivity API")

	var content_bounds_val = canvas.get("_content_bounds")
	if not (content_bounds_val is Dictionary):
		_safe_free(canvas)
		return Result.failure("_content_bounds 类型错误")
	var content_bounds: Dictionary = content_bounds_val
	var maxp: Vector2i = content_bounds.get("max", Vector2i.ZERO)
	var minp: Vector2i = content_bounds.get("min", Vector2i.ZERO)
	var panel_world_min := Vector2i(maxp.x + 1 + 2, minp.y) # +gap

	if not bool(canvas.call("is_world_pos_in_extension_panel", panel_world_min)):
		_safe_free(canvas)
		return Result.failure("extension panel world pos 未被识别: %s" % str(panel_world_min))
	if bool(canvas.call("is_interactive_world_pos", panel_world_min)):
		_safe_free(canvas)
		return Result.failure("extension panel world pos 不应可交互: %s" % str(panel_world_min))

	if not bool(canvas.call("is_interactive_world_pos", Vector2i(0, 0))):
		_safe_free(canvas)
		return Result.failure("base map cell 应可交互: (0,0)")

	_safe_free(canvas)
	return Result.success({
		"cell_size": cell_size,
		"applied_margin": applied_margin,
		"expected_cells_x": expected_cells_x,
		"expected_cells_y": expected_cells_y,
	})

static func _safe_free(node: Node) -> void:
	if node != null and is_instance_valid(node):
		node.free()
