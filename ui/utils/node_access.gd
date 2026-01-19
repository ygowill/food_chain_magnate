# UI 节点访问工具：集中处理 get_node_or_null + 类型判断样板。
# 注意：这是“软工具”（返回 null），不会 assert，以避免 UI 生命周期抖动导致的硬失败。
class_name UiNodeAccess
extends RefCounted

static func get_control(root: Node, path: NodePath) -> Control:
	if root == null or not is_instance_valid(root):
		return null
	var n = root.get_node_or_null(path)
	return n as Control if n is Control else null

static func get_button(root: Node, path: NodePath) -> Button:
	if root == null or not is_instance_valid(root):
		return null
	var n = root.get_node_or_null(path)
	return n as Button if n is Button else null

static func set_control_visible(root: Node, path: NodePath, visible: bool) -> void:
	var c := get_control(root, path)
	if c != null:
		c.visible = visible

