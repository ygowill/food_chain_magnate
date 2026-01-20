# move_restaurant：餐厅下拉选项可读 label 回归测试
# 覆盖 issue_tracker #28：下拉框不应暴露内部 id（rest_0），应显示“餐厅 N @ (x,y)”。
class_name MoveRestaurantDisplayLabelTest
extends RefCounted

const RestaurantPlacementOverlayClass = preload("res://ui/components/restaurant_placement/restaurant_placement_overlay.gd")

static func run() -> Result:
	var overlay = RestaurantPlacementOverlayClass.new()
	overlay.set_map_data({
		"restaurants": {
			"rest_0": {"entrance_pos": Vector2i(3, 4)},
			"rest_1": {"entrance_pos": Vector2i(0, 0)},
		}
	})
	overlay.set_available_restaurants(["rest_1", "rest_0"])

	var l0 := str(overlay.get_restaurant_display_label("rest_0"))
	var l1 := str(overlay.get_restaurant_display_label("rest_1"))

	if l0 != "餐厅 1 @ (3,4)":
		overlay.free()
		return Result.failure("rest_0 label=%s (expected %s)" % [l0, "餐厅 1 @ (3,4)"])
	if l1 != "餐厅 2 @ (0,0)":
		overlay.free()
		return Result.failure("rest_1 label=%s (expected %s)" % [l1, "餐厅 2 @ (0,0)"])

	if l0.find("rest_0") >= 0 or l1.find("rest_1") >= 0:
		overlay.free()
		return Result.failure("label 泄露内部 id: l0=%s l1=%s" % [l0, l1])

	overlay.free()
	return Result.success({})
