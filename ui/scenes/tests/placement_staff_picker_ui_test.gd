class_name PlacementStaffPickerUiTest
extends RefCounted

const HouseOverlayClass = preload("res://ui/components/house_placement/house_placement_overlay.gd")
const RestaurantOverlayClass = preload("res://ui/components/restaurant_placement/restaurant_placement_overlay.gd")

static func run() -> Result:
	var r := _case_house_overlay_keeps_selected_staff_id()
	if not r.ok:
		return r
	r = _case_restaurant_overlay_defaults_to_enabled_staff()
	if not r.ok:
		return r
	return Result.success({})

static func _case_house_overlay_keeps_selected_staff_id() -> Result:
	var overlay := HouseOverlayClass.new()
	overlay.set_available_employee_items([
		{"staff_id": 101, "employee_type": "new_business_developer", "capacity": 1, "used": 1, "remaining": 0, "can_place_house": true, "can_add_garden": true},
		{"staff_id": 102, "employee_type": "new_business_developer", "capacity": 1, "used": 0, "remaining": 1, "can_place_house": true, "can_add_garden": true},
	])
	if int(overlay.get_selected_staff_id()) != 102:
		overlay.free()
		return Result.failure("house overlay 应默认选中 remaining>0 的 staff_id=102，实际: %s" % str(overlay.get_selected_staff_id()))
	overlay.set_selected_employee_key("staff:101")
	if int(overlay.get_selected_staff_id()) != 101:
		overlay.free()
		return Result.failure("house overlay 切换后应保留 staff_id=101，实际: %s" % str(overlay.get_selected_staff_id()))
	overlay.free()
	return Result.success()

static func _case_restaurant_overlay_defaults_to_enabled_staff() -> Result:
	var overlay := RestaurantOverlayClass.new()
	overlay.set_available_employee_items([
		{"staff_id": 201, "employee_type": "regional_manager", "capacity": 1, "used": 1, "remaining": 0, "can_place_restaurant": true, "can_move_restaurant": true},
		{"staff_id": 202, "employee_type": "regional_manager", "capacity": 1, "used": 0, "remaining": 1, "can_place_restaurant": true, "can_move_restaurant": true},
	])
	if int(overlay.get_selected_staff_id()) != 202:
		overlay.free()
		return Result.failure("restaurant overlay 应默认选中 remaining>0 的 staff_id=202，实际: %s" % str(overlay.get_selected_staff_id()))
	overlay.set_selected_employee_key("staff:201")
	if int(overlay.get_selected_staff_id()) != 201:
		overlay.free()
		return Result.failure("restaurant overlay 切换后应保留 staff_id=201，实际: %s" % str(overlay.get_selected_staff_id()))
	overlay.free()
	return Result.success()
