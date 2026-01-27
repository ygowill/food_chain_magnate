extends RefCounted

const CoreFieldsClass = preload("res://core/data/employee_def/parser/core_fields.gd")
const OptionalFieldsClass = preload("res://core/data/employee_def/parser/optional_fields.gd")

static func apply_from_dict(emp, data: Dictionary) -> Result:
	var r := CoreFieldsClass.apply(emp, data)
	if not r.ok:
		return r
	r = OptionalFieldsClass.apply(emp, data)
	if not r.ok:
		return r
	return Result.success(emp)
