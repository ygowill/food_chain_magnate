# EmployeePicker regression test (no real rendering required)
# Covers issue_tracker #34: EmployeePickerItem must expose a stable minimum size so FlowContainer
# layouts reserve enough height and cards don't visually overlap the next section.
class_name EmployeePickerMinSizeTest
extends RefCounted

const EmployeePickerClass = preload("res://ui/components/employee_picker/employee_picker.gd")
const EmployeeCardClass = preload("res://ui/components/employee_card/employee_card.gd")

static func run() -> Result:
	var item := EmployeePickerClass.EmployeePickerItem.new()
	item.employee_id = "marketing_trainee"
	item.employee_def = {"id": "marketing_trainee", "name": "marketing_trainee"}
	item.badge_text = "1"
	item.tag_text = "TEST"
	if item.has_method("_build_ui"):
		item.call("_build_ui")
	else:
		return Result.failure("EmployeePickerItem 缺少 _build_ui()")

	var min_y := float(item.custom_minimum_size.y)
	var expected_y := float(EmployeeCardClass.COMPACT_SIZE.y)
	if min_y + 0.01 < expected_y:
		var fail := Result.failure("EmployeePickerItem.custom_minimum_size.y=%s (expected >= %s)" % [str(min_y), str(expected_y)])
		_safe_free(item)
		return fail

	_safe_free(item)
	return Result.success({})

static func _safe_free(node) -> void:
	if node == null or not is_instance_valid(node):
		return
	if node is Node:
		(node as Node).free()
