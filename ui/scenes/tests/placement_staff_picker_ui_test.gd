class_name PlacementStaffPickerUiTest
extends RefCounted

const HouseOverlayClass = preload("res://ui/components/house_placement/house_placement_overlay.gd")
const RestaurantOverlayClass = preload("res://ui/components/restaurant_placement/restaurant_placement_overlay.gd")
const StaffPickerStateClass = preload("res://ui/components/employee_picker/staff_picker_state.gd")

static func run() -> Result:
	var r := _case_staff_picker_state_defaults_to_enabled_staff()
	if not r.ok:
		return r
	r = _case_staff_picker_state_reselects_by_employee_type()
	if not r.ok:
		return r
	r = _case_house_overlay_keeps_selected_staff_id()
	if not r.ok:
		return r
	r = _case_restaurant_overlay_defaults_to_enabled_staff()
	if not r.ok:
		return r
	return Result.success({})

static func _case_staff_picker_state_defaults_to_enabled_staff() -> Result:
	var state := StaffPickerStateClass.new(["can_place_house", "can_add_garden"])
	state.set_items([
		{"staff_id": 101, "employee_type": "new_business_developer", "capacity": 1, "used": 1, "remaining": 0, "can_place_house": true, "can_add_garden": true},
		{"staff_id": 102, "employee_type": "new_business_developer", "capacity": 1, "used": 0, "remaining": 1, "can_place_house": true, "can_add_garden": true},
	])
	if int(state.get_selected_staff_id()) != 102:
		return Result.failure("StaffPickerState 应默认选中 remaining>0 的 staff_id=102，实际: %s" % str(state.get_selected_staff_id()))
	var items := state.get_items()
	if items.size() != 2:
		return Result.failure("StaffPickerState 应保留 2 个 picker item，实际: %d" % items.size())
	if not bool(Dictionary(items[0]).get("can_place_house", false)):
		return Result.failure("StaffPickerState 应复制 capability 字段 can_place_house")
	return Result.success()

static func _case_staff_picker_state_reselects_by_employee_type() -> Result:
	var state := StaffPickerStateClass.new(["can_place_restaurant", "can_move_restaurant"])
	state.set_items([
		{"staff_id": 201, "employee_type": "regional_manager", "capacity": 1, "used": 1, "remaining": 0, "can_place_restaurant": true, "can_move_restaurant": true},
		{"staff_id": 202, "employee_type": "regional_manager", "capacity": 1, "used": 0, "remaining": 1, "can_place_restaurant": true, "can_move_restaurant": true},
	])
	state.apply_selected_key("staff:201")
	if int(state.get_selected_staff_id()) != 201:
		return Result.failure("StaffPickerState 按 key 切换后应保留 staff_id=201，实际: %s" % str(state.get_selected_staff_id()))
	state.apply_selected_employee_type("regional_manager")
	if int(state.get_selected_staff_id()) != 202:
		return Result.failure("StaffPickerState 按 employee_type 回退时应优先选择可用 staff_id=202，实际: %s" % str(state.get_selected_staff_id()))
	state.refresh_selected()
	if int(state.get_selected_staff_id()) != 202:
		return Result.failure("StaffPickerState refresh_selected 后应保留 staff_id=202，实际: %s" % str(state.get_selected_staff_id()))
	return Result.success()

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
