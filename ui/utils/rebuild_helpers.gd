# UI “清理-重建”通用工具：减少重复的 queue_free + clear 样板。
class_name UiRebuildHelpers
extends RefCounted

static func free_children(container: Node) -> void:
	if container == null or not is_instance_valid(container):
		return
	for child in container.get_children():
		if is_instance_valid(child):
			child.queue_free()

static func free_nodes_dict(map: Dictionary) -> void:
	for node in map.values():
		if is_instance_valid(node):
			node.queue_free()
	map.clear()

