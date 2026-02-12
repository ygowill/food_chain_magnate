# 基础覆盖层：使用 tile_size + map_offset 进行绘制
# 用途：消除多个 overlay 中重复的 set_tile_size/set_map_offset 与“释放子节点数组”样板。
class_name BaseTileOverlay
extends Control

var _tile_size: Vector2 = Vector2(64, 64)
var _map_offset: Vector2 = Vector2.ZERO

func set_tile_size(size: Vector2) -> void:
	_tile_size = size
	_on_layout_changed()

func set_map_offset(offset: Vector2) -> void:
	_map_offset = offset
	_on_layout_changed()

func _on_layout_changed() -> void:
	# Virtual: subclasses override.
	pass

func _grid_to_pixel_center(grid_pos: Vector2i) -> Vector2:
	return Vector2(grid_pos.x, grid_pos.y) * _tile_size + _map_offset + (_tile_size * 0.5)

func _grid_to_pixel_top_left(grid_pos: Vector2i) -> Vector2:
	return Vector2(grid_pos.x, grid_pos.y) * _tile_size + _map_offset

func _grid_cell_rect(grid_pos: Vector2i, inset_px: float = 0.0) -> Rect2:
	var inset := maxf(0.0, inset_px)
	var size := _tile_size - Vector2(inset * 2.0, inset * 2.0)
	if size.x <= 0.0 or size.y <= 0.0:
		size = _tile_size
		inset = 0.0
	var pos := _grid_to_pixel_top_left(grid_pos) + Vector2(inset, inset)
	return Rect2(pos, size)

func _draw_cell_fills(
	cells: Array[Vector2i],
	fill_color: Color,
	inset_px: float = 0.0,
	outline_color: Color = Color(0, 0, 0, 0),
	outline_width: float = 0.0
) -> void:
	if cells.is_empty():
		return

	for cell in cells:
		var r := _grid_cell_rect(cell, inset_px)
		draw_rect(r, fill_color, true)
		if outline_width > 0.0 and outline_color.a > 0.0:
			draw_rect(r, outline_color, false, outline_width)

func _free_nodes(nodes: Array) -> void:
	for n in nodes:
		if is_instance_valid(n):
			n.queue_free()
	nodes.clear()
