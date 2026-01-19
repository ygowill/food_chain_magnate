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

func _free_nodes(nodes: Array) -> void:
	for n in nodes:
		if is_instance_valid(n):
			n.queue_free()
	nodes.clear()

