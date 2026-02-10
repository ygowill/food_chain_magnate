class_name EmployeeTreeLayoutBottomTagTest
extends RefCounted

const LayoutClass = preload("res://ui/components/employee_tree/employee_tree_layout.gd")
const _BOTTOM_TAG := "ui_layout_bottom"

static func run() -> Result:
	var node_ids: Array[String] = ["a", "b"]
	var edges_out: Dictionary = {
		"a": [],
		"b": [],
	}
	var entry_ids: Array[String] = []
	var roles: Dictionary = {
		"a": "produce_food",
		"b": "produce_food",
	}
	var tags_by_id: Dictionary = {
		"b": [_BOTTOM_TAG],
	}
	var layout: Dictionary = LayoutClass.layout(
		node_ids,
		edges_out,
		entry_ids,
		roles,
		Vector2(10, 10),
		100.0,
		10.0,
		Vector2.ZERO,
		6,
		tags_by_id
	)
	var positions_val = layout.get("positions", null)
	if not (positions_val is Dictionary):
		return Result.failure("positions 缺失或类型错误")
	var positions: Dictionary = positions_val
	var a_pos_val = positions.get("a", null)
	var b_pos_val = positions.get("b", null)
	if not (a_pos_val is Vector2) or not (b_pos_val is Vector2):
		return Result.failure("positions.a/positions.b 缺失或类型错误")
	var a_pos: Vector2 = a_pos_val
	var b_pos: Vector2 = b_pos_val
	if b_pos.y <= a_pos.y:
		return Result.failure("bottom tag 节点应位于同 lane 的更下方: a_y=%s b_y=%s" % [a_pos.y, b_pos.y])
	return Result.success({
		"a_y": a_pos.y,
		"b_y": b_pos.y,
	})
