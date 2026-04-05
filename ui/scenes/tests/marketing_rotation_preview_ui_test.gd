# Marketing rotation / preview UI regression test
# Covers:
# - marketing placement rotation should use 90-degree step logic and refresh map selection
# - marketing board preview should keep larger footprints visually larger than smaller ones
# - board number badge should stay constrained on 1x1 boards
class_name MarketingRotationPreviewUiTest
extends RefCounted

const MarketingPanelClass = preload("res://ui/components/marketing_panel/marketing_panel.gd")
const MarketingBoardButtonClass = preload("res://ui/components/marketing_panel/marketing_board_button.gd")

static func run() -> Result:
	var r := _case_panel_rotation_logic()
	if not r.ok:
		return r
	r = _case_preview_layout_scaling()
	if not r.ok:
		return r
	return Result.success({})

static func _case_panel_rotation_logic() -> Result:
	var panel := MarketingPanelClass.new()
	panel.rotation_section = Control.new()
	panel.rotate_left_btn = Button.new()
	panel.rotation_value_label = Label.new()
	panel.rotate_right_btn = Button.new()
	panel.target_label = Label.new()
	panel.range_info_label = Label.new()
	panel.error_label = Label.new()
	panel.confirm_btn = Button.new()

	var board_btn := MarketingBoardButtonClass.new()
	board_btn.board_number = 11
	board_btn.base_size = Vector2i(3, 2)
	panel._board_button_by_number[11] = board_btn

	panel._selected_type = "billboard"
	panel._selected_employee_type = "marketing_trainee"
	panel._selected_board_number = 11
	panel._selected_product = "burger"
	panel._selected_target = Vector2i(4, 5)
	panel._update_rotation_section()

	var callback := _MapRefreshSpy.new()
	panel.set_map_selection_callback(Callable(callback, "record"))
	panel.set_selected_rotation(90)

	if panel.get_selected_rotation() != 90:
		return Result.failure("营销旋转应更新为 90 度，实际: %d" % panel.get_selected_rotation())
	if panel._selected_target != Vector2i(-1, -1):
		return Result.failure("营销旋转变化后应清空已选目标，实际: %s" % str(panel._selected_target))
	if panel.rotation_value_label == null or panel.rotation_value_label.text != "90度":
		return Result.failure("营销旋转标签未同步到 90度，实际: %s" % str(panel.rotation_value_label.text if panel.rotation_value_label != null else ""))
	if callback.calls.size() != 1:
		return Result.failure("营销旋转变化后应刷新一次地图选点，实际调用次数: %d" % callback.calls.size())
	if int(callback.calls[0].get("rotation", -1)) != 90:
		return Result.failure("营销旋转刷新应携带 rotation=90，实际: %s" % str(callback.calls[0]))
	if board_btn.tooltip_text.find("2x3") < 0:
		return Result.failure("营销板件 tooltip 应随旋转更新为 2x3，实际: %s" % board_btn.tooltip_text)

	panel.rotate_ccw()
	if panel.get_selected_rotation() != 0:
		return Result.failure("营销左旋后应回到 0 度，实际: %d" % panel.get_selected_rotation())

	panel._selected_type = "airplane"
	panel._selected_rotation = 180
	panel._update_rotation_section()
	if panel.get_selected_rotation() != 0:
		return Result.failure("飞机广告不应保留旋转，实际: %d" % panel.get_selected_rotation())
	if panel.rotation_section != null and panel.rotation_section.visible:
		return Result.failure("飞机广告应隐藏旋转区")

	_safe_free(panel)
	_safe_free(board_btn)
	return Result.success({})

static func _case_preview_layout_scaling() -> Result:
	var three_by_two := MarketingBoardButtonClass.new()
	three_by_two.base_size = Vector2i(3, 2)
	three_by_two.board_number = 11
	var three_layout := three_by_two.get_preview_layout(Vector2(108, 84))

	var two_by_one := MarketingBoardButtonClass.new()
	two_by_one.base_size = Vector2i(2, 1)
	two_by_one.board_number = 14
	var two_layout := two_by_one.get_preview_layout(Vector2(108, 84))

	if three_layout.is_empty() or two_layout.is_empty():
		return Result.failure("营销板件预览布局不应为空")

	var rect_large: Rect2 = three_layout.get("board_rect", Rect2())
	var rect_small: Rect2 = two_layout.get("board_rect", Rect2())
	var area_large := rect_large.size.x * rect_large.size.y
	var area_small := rect_small.size.x * rect_small.size.y
	if area_large <= area_small:
		return Result.failure("3x2 板件预览面积应大于 2x1，实际: 3x2=%s 2x1=%s" % [str(rect_large.size), str(rect_small.size)])

	var one_by_one := MarketingBoardButtonClass.new()
	one_by_one.base_size = Vector2i.ONE
	one_by_one.board_number = 16
	var one_layout := one_by_one.get_preview_layout(Vector2(108, 84))
	if one_layout.is_empty():
		return Result.failure("1x1 板件预览布局不应为空")
	var rect_one: Rect2 = one_layout.get("board_rect", Rect2())
	var badge_layout_val = one_layout.get("badge_layout", {})
	if not (badge_layout_val is Dictionary):
		return Result.failure("1x1 板件应返回序号徽标布局")
	var badge_layout: Dictionary = badge_layout_val
	var badge_diameter := float(badge_layout.get("radius", 0.0)) * 2.0
	var max_allowed := minf(rect_one.size.x, rect_one.size.y) * 0.55
	if badge_diameter > max_allowed:
		return Result.failure("1x1 板件序号徽标过大: badge=%0.2f allowed=%0.2f" % [badge_diameter, max_allowed])

	_safe_free(three_by_two)
	_safe_free(two_by_one)
	_safe_free(one_by_one)
	return Result.success({})

static func _safe_free(node) -> void:
	if node == null or not is_instance_valid(node):
		return
	if node is Node:
		(node as Node).free()

class _MapRefreshSpy:
	extends RefCounted

	var calls: Array[Dictionary] = []

	func record(marketing_type: String, employee_type: String = "", board_number: int = 0, rotation: int = 0) -> void:
		calls.append({
			"marketing_type": marketing_type,
			"employee_type": employee_type,
			"board_number": board_number,
			"rotation": rotation,
		})
