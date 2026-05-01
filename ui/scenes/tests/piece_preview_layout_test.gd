class_name PiecePreviewLayoutTest
extends RefCounted

const PiecePreviewLayoutClass = preload("res://ui/utils/piece_preview_layout.gd")

static func run() -> Result:
	var r := _case_road_icon_uses_corner_for_l_shape()
	if not r.ok:
		return r
	r = _case_road_icon_uses_geometric_center_for_straight_shape()
	if not r.ok:
		return r
	r = _case_park_icon_uses_longest_straight_run()
	if not r.ok:
		return r
	r = _case_park_icon_uses_full_solid_rectangle()
	if not r.ok:
		return r
	r = _case_vertical_run_reports_orientation()
	if not r.ok:
		return r
	return Result.success({})

static func _case_road_icon_uses_corner_for_l_shape() -> Result:
	var cells: Array[Vector2i] = [
		Vector2i(4, 2),
		Vector2i(4, 3),
		Vector2i(5, 3),
	]
	var center: Vector2 = PiecePreviewLayoutClass.get_road_icon_center(cells)
	if center != Vector2(0.5, 1.5):
		return Result.failure("L 形道路维修标志应落在拐点格中心，实际: %s" % str(center))
	return Result.success({})

static func _case_road_icon_uses_geometric_center_for_straight_shape() -> Result:
	var cells: Array[Vector2i] = [
		Vector2i(0, 0),
		Vector2i(1, 0),
	]
	var center: Vector2 = PiecePreviewLayoutClass.get_road_icon_center(cells)
	if center != Vector2(1.0, 0.5):
		return Result.failure("一字型道路维修标志应落在整体中心，实际: %s" % str(center))
	return Result.success({})

static func _case_park_icon_uses_longest_straight_run() -> Result:
	var cells: Array[Vector2i] = [
		Vector2i(0, 0),
		Vector2i(1, 0),
		Vector2i(2, 0),
		Vector2i(0, 1),
	]
	var run: Array[Vector2i] = PiecePreviewLayoutClass.get_park_texture_cells(cells)
	var expected: Array[Vector2i] = [
		Vector2i(0, 0),
		Vector2i(1, 0),
		Vector2i(2, 0),
	]
	if run != expected:
		return Result.failure("公园图标应选择最长边，实际: %s" % str(run))
	return Result.success({})

static func _case_park_icon_uses_full_solid_rectangle() -> Result:
	var cells: Array[Vector2i] = [
		Vector2i(0, 0),
		Vector2i(1, 0),
		Vector2i(0, 1),
		Vector2i(1, 1),
	]
	var texture_cells: Array[Vector2i] = PiecePreviewLayoutClass.get_park_texture_cells(cells)
	if texture_cells.size() != 4:
		return Result.failure("完整 2x2 公园应使用整个区域绘制，实际: %s" % str(texture_cells))
	if PiecePreviewLayoutClass.should_rotate_texture_for_cells(texture_cells):
		return Result.failure("完整 2x2 公园不应旋转纹理")
	return Result.success({})

static func _case_vertical_run_reports_orientation() -> Result:
	var cells: Array[Vector2i] = [
		Vector2i(2, 2),
		Vector2i(2, 3),
		Vector2i(2, 4),
	]
	var run: Array[Vector2i] = PiecePreviewLayoutClass.get_park_texture_cells(cells)
	if not PiecePreviewLayoutClass.should_rotate_texture_for_cells(run):
		return Result.failure("竖向最长边应标记为 vertical，实际: %s" % str(run))
	return Result.success({})
