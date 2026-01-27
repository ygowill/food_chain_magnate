extends RefCounted

const DataParseHelpersClass = preload("res://core/data/parse_helpers.gd")

static func apply(emp, data: Dictionary) -> Result:
	var id_read := DataParseHelpersClass.parse_string(data.get("id", null), "EmployeeDef.id", false)
	if not id_read.ok:
		return id_read
	emp.id = id_read.value

	var name_read := DataParseHelpersClass.parse_string(data.get("name", null), "EmployeeDef.name", false)
	if not name_read.ok:
		return name_read
	emp.name = name_read.value

	var desc_read := DataParseHelpersClass.parse_string(data.get("description", null), "EmployeeDef.description", true)
	if not desc_read.ok:
		return desc_read
	emp.description = desc_read.value

	if not data.has("role"):
		return Result.failure("EmployeeDef.role 缺失（必须提供）")
	var role_read := DataParseHelpersClass.parse_string(data.get("role", null), "EmployeeDef.role", false)
	if not role_read.ok:
		return role_read
	emp.role = role_read.value
	if emp.role != "manager" \
			and emp.role != "recruit_train" \
			and emp.role != "produce_food" \
			and emp.role != "procure_drink" \
			and emp.role != "price" \
			and emp.role != "marketing" \
			and emp.role != "new_shop" \
			and emp.role != "special":
		return Result.failure("EmployeeDef.role 不支持: %s" % emp.role)

	var salary_read := DataParseHelpersClass.parse_bool(data.get("salary", null), "EmployeeDef.salary")
	if not salary_read.ok:
		return salary_read
	emp.salary = bool(salary_read.value)

	var unique_read := DataParseHelpersClass.parse_bool(data.get("unique", null), "EmployeeDef.unique")
	if not unique_read.ok:
		return unique_read
	emp.unique = bool(unique_read.value)

	var manager_slots_read := DataParseHelpersClass.parse_non_negative_int(data.get("manager_slots", null), "EmployeeDef.manager_slots")
	if not manager_slots_read.ok:
		return manager_slots_read
	emp.manager_slots = int(manager_slots_read.value)

	var range_val = data.get("range", null)
	if not (range_val is Dictionary):
		return Result.failure("EmployeeDef.range 缺失或类型错误（期望 Dictionary）")
	var range: Dictionary = range_val

	var range_type_val = range.get("type", null)
	if range_type_val == null:
		emp.range_type = ""
	else:
		var range_type_read := DataParseHelpersClass.parse_string(range_type_val, "EmployeeDef.range.type", false)
		if not range_type_read.ok:
			return range_type_read
		var rt: String = range_type_read.value
		if rt != "road" and rt != "air":
			return Result.failure("EmployeeDef.range.type 不支持: %s" % rt)
		emp.range_type = rt

	var range_value_read := DataParseHelpersClass.parse_int(range.get("value", null), "EmployeeDef.range.value")
	if not range_value_read.ok:
		return range_value_read
	emp.range_value = int(range_value_read.value)
	if emp.range_value < -1:
		return Result.failure("EmployeeDef.range.value 必须 >= -1，实际: %d" % emp.range_value)
	if emp.range_type.is_empty() and emp.range_value != 0:
		return Result.failure("EmployeeDef.range.type 为空时 range.value 必须为 0，实际: %d" % emp.range_value)

	var train_to_read := DataParseHelpersClass.parse_string_array(data.get("train_to", null), "EmployeeDef.train_to", true)
	if not train_to_read.ok:
		return train_to_read
	emp.train_to = Array(train_to_read.value, TYPE_STRING, "", null)

	var train_capacity_read := DataParseHelpersClass.parse_non_negative_int(data.get("train_capacity", null), "EmployeeDef.train_capacity")
	if not train_capacity_read.ok:
		return train_capacity_read
	emp.train_capacity = int(train_capacity_read.value)

	var tags_read := DataParseHelpersClass.parse_string_array(data.get("tags", null), "EmployeeDef.tags", true)
	if not tags_read.ok:
		return tags_read
	emp.tags = Array(tags_read.value, TYPE_STRING, "", null)

	var usage_tags_read := DataParseHelpersClass.parse_string_array(data.get("usage_tags", null), "EmployeeDef.usage_tags", true)
	if not usage_tags_read.ok:
		return usage_tags_read
	emp.usage_tags = Array(usage_tags_read.value, TYPE_STRING, "", null)

	# recruit_capacity（严格）：use:recruit 时必须提供且 > 0；未声明 use:recruit 时不允许提供
	var has_recruit_usage = emp.has_usage_tag("use:recruit")
	if data.has("recruit_capacity"):
		if not has_recruit_usage:
			return Result.failure("EmployeeDef.recruit_capacity 仅允许在 usage_tags 包含 use:recruit 时提供")
		var rc_read := DataParseHelpersClass.parse_non_negative_int(data.get("recruit_capacity", null), "EmployeeDef.recruit_capacity")
		if not rc_read.ok:
			return rc_read
		emp.recruit_capacity = int(rc_read.value)
		if emp.recruit_capacity <= 0:
			return Result.failure("EmployeeDef.recruit_capacity 必须 > 0")
	else:
		if has_recruit_usage:
			return Result.failure("EmployeeDef.recruit_capacity 缺失（usage_tags 包含 use:recruit 时必须提供）")
		emp.recruit_capacity = 0

	return Result.success()

