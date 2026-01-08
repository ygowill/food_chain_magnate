extends RefCounted

static func apply_from_dict(emp, data: Dictionary) -> Result:
	var id_read := _parse_string(data.get("id", null), "EmployeeDef.id", false)
	if not id_read.ok:
		return id_read
	emp.id = id_read.value

	var name_read := _parse_string(data.get("name", null), "EmployeeDef.name", false)
	if not name_read.ok:
		return name_read
	emp.name = name_read.value

	var desc_read := _parse_string(data.get("description", null), "EmployeeDef.description", true)
	if not desc_read.ok:
		return desc_read
	emp.description = desc_read.value

	if not data.has("role"):
		return Result.failure("EmployeeDef.role 缺失（必须提供）")
	var role_read := _parse_string(data.get("role", null), "EmployeeDef.role", false)
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

	var salary_read := _parse_bool(data.get("salary", null), "EmployeeDef.salary")
	if not salary_read.ok:
		return salary_read
	emp.salary = bool(salary_read.value)

	var unique_read := _parse_bool(data.get("unique", null), "EmployeeDef.unique")
	if not unique_read.ok:
		return unique_read
	emp.unique = bool(unique_read.value)

	var manager_slots_read := _parse_non_negative_int(data.get("manager_slots", null), "EmployeeDef.manager_slots")
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
		var range_type_read := _parse_string(range_type_val, "EmployeeDef.range.type", false)
		if not range_type_read.ok:
			return range_type_read
		var rt: String = range_type_read.value
		if rt != "road" and rt != "air":
			return Result.failure("EmployeeDef.range.type 不支持: %s" % rt)
		emp.range_type = rt

	var range_value_read := _parse_int(range.get("value", null), "EmployeeDef.range.value")
	if not range_value_read.ok:
		return range_value_read
	emp.range_value = int(range_value_read.value)
	if emp.range_value < -1:
		return Result.failure("EmployeeDef.range.value 必须 >= -1，实际: %d" % emp.range_value)
	if emp.range_type.is_empty() and emp.range_value != 0:
		return Result.failure("EmployeeDef.range.type 为空时 range.value 必须为 0，实际: %d" % emp.range_value)

	var train_to_read := _parse_string_array(data.get("train_to", null), "EmployeeDef.train_to", true)
	if not train_to_read.ok:
		return train_to_read
	emp.train_to = Array(train_to_read.value, TYPE_STRING, "", null)

	var train_capacity_read := _parse_non_negative_int(data.get("train_capacity", null), "EmployeeDef.train_capacity")
	if not train_capacity_read.ok:
		return train_capacity_read
	emp.train_capacity = int(train_capacity_read.value)

	var tags_read := _parse_string_array(data.get("tags", null), "EmployeeDef.tags", true)
	if not tags_read.ok:
		return tags_read
	emp.tags = Array(tags_read.value, TYPE_STRING, "", null)

	var usage_tags_read := _parse_string_array(data.get("usage_tags", null), "EmployeeDef.usage_tags", true)
	if not usage_tags_read.ok:
		return usage_tags_read
	emp.usage_tags = Array(usage_tags_read.value, TYPE_STRING, "", null)

	# recruit_capacity（严格）：use:recruit 时必须提供且 > 0；未声明 use:recruit 时不允许提供
	var has_recruit_usage = emp.has_usage_tag("use:recruit")
	if data.has("recruit_capacity"):
		if not has_recruit_usage:
			return Result.failure("EmployeeDef.recruit_capacity 仅允许在 usage_tags 包含 use:recruit 时提供")
		var rc_read := _parse_non_negative_int(data.get("recruit_capacity", null), "EmployeeDef.recruit_capacity")
		if not rc_read.ok:
			return rc_read
		emp.recruit_capacity = int(rc_read.value)
		if emp.recruit_capacity <= 0:
			return Result.failure("EmployeeDef.recruit_capacity 必须 > 0")
	else:
		if has_recruit_usage:
			return Result.failure("EmployeeDef.recruit_capacity 缺失（usage_tags 包含 use:recruit 时必须提供）")
		emp.recruit_capacity = 0

	var mandatory_read := _parse_bool(data.get("mandatory", null), "EmployeeDef.mandatory")
	if not mandatory_read.ok:
		return mandatory_read
	emp.mandatory = bool(mandatory_read.value)

	# mandatory_action_id（可选，但 mandatory=true 时必须提供以避免硬编码映射）
	if data.has("mandatory_action_id"):
		var mai_read := _parse_string(data.get("mandatory_action_id", null), "EmployeeDef.mandatory_action_id", true)
		if not mai_read.ok:
			return mai_read
		emp.mandatory_action_id = mai_read.value
	else:
		if emp.mandatory:
			return Result.failure("EmployeeDef.mandatory_action_id 缺失（mandatory=true 时必须提供；为空字符串表示自动应用）")
		emp.mandatory_action_id = ""

	# can_be_fired（可选）：默认 true
	if data.has("can_be_fired"):
		var cbf_read := _parse_bool(data.get("can_be_fired", null), "EmployeeDef.can_be_fired")
		if not cbf_read.ok:
			return cbf_read
		emp.can_be_fired = bool(cbf_read.value)
	else:
		emp.can_be_fired = true

	if data.has("marketing_max_duration"):
		var mmd_read := _parse_non_negative_int(data.get("marketing_max_duration", null), "EmployeeDef.marketing_max_duration")
		if not mmd_read.ok:
			return mmd_read
		emp.marketing_max_duration = int(mmd_read.value)
		if emp.marketing_max_duration <= 0:
			return Result.failure("EmployeeDef.marketing_max_duration 必须 > 0")

	if data.has("produces"):
		var produces_val = data.get("produces", null)
		if not (produces_val is Dictionary):
			return Result.failure("EmployeeDef.produces 类型错误（期望 Dictionary）")
		var produces: Dictionary = produces_val
		var food_type_read := _parse_string(produces.get("food_type", null), "EmployeeDef.produces.food_type", false)
		if not food_type_read.ok:
			return food_type_read
		emp.produces_food_type = food_type_read.value

		var amount_read := _parse_int(produces.get("amount", null), "EmployeeDef.produces.amount")
		if not amount_read.ok:
			return amount_read
		emp.produces_amount = int(amount_read.value)
		if emp.produces_amount <= 0:
			return Result.failure("EmployeeDef.produces.amount 必须 > 0")

	# pool（可选）：用于 Pools 推导（路线B）
	if data.has("pool"):
		var pool_val = data.get("pool", null)
		if not (pool_val is Dictionary):
			return Result.failure("EmployeeDef.pool 类型错误（期望 Dictionary）")
		var pool: Dictionary = pool_val

		var type_read := _parse_string(pool.get("type", null), "EmployeeDef.pool.type", false)
		if not type_read.ok:
			return type_read
		var ptype: String = type_read.value
		if ptype != "fixed" and ptype != "one_x" and ptype != "none":
			return Result.failure("EmployeeDef.pool.type 不支持: %s" % ptype)
		emp.pool_type = ptype

		match ptype:
			"fixed":
				var count_read := _parse_non_negative_int(pool.get("count", null), "EmployeeDef.pool.count")
				if not count_read.ok:
					return count_read
				emp.pool_count = int(count_read.value)
				if emp.pool_count <= 0:
					return Result.failure("EmployeeDef.pool.count 必须 > 0")
			"one_x":
				if pool.has("count"):
					return Result.failure("EmployeeDef.pool.type=one_x 不应包含 count")
				emp.pool_count = 0
			"none":
				if pool.has("count"):
					return Result.failure("EmployeeDef.pool.type=none 不应包含 count")
				emp.pool_count = 0
	else:
		emp.pool_type = "none"
		emp.pool_count = 0

	# effect_ids（可选）：用于 EffectRegistry（M5）
	if data.has("effect_ids"):
		var effect_ids_read := _parse_string_array(data.get("effect_ids", null), "EmployeeDef.effect_ids", true)
		if not effect_ids_read.ok:
			return effect_ids_read
		emp.effect_ids = Array(effect_ids_read.value, TYPE_STRING, "", null)
		for i in range(emp.effect_ids.size()):
			var eid: String = emp.effect_ids[i]
			var colon_idx := eid.find(":")
			if colon_idx <= 0 or colon_idx >= eid.length() - 1:
				return Result.failure("EmployeeDef.effect_ids[%d] 必须为 module_id:...，实际: %s" % [i, eid])
	else:
		emp.effect_ids = Array([], TYPE_STRING, "", null)

	return Result.success(emp)

static func _parse_string(value, path: String, allow_empty: bool) -> Result:
	if not (value is String):
		return Result.failure("%s 类型错误（期望 String）" % path)
	var s: String = value
	if not allow_empty and s.is_empty():
		return Result.failure("%s 不能为空" % path)
	return Result.success(s)

static func _parse_bool(value, path: String) -> Result:
	if not (value is bool):
		return Result.failure("%s 类型错误（期望 bool）" % path)
	return Result.success(bool(value))

static func _parse_int(value, path: String) -> Result:
	if value is int:
		return Result.success(int(value))
	if value is float:
		var f: float = float(value)
		if f != floor(f):
			return Result.failure("%s 必须为整数，实际: %s" % [path, str(value)])
		return Result.success(int(f))
	return Result.failure("%s 类型错误（期望整数）" % path)

static func _parse_non_negative_int(value, path: String) -> Result:
	var r := _parse_int(value, path)
	if not r.ok:
		return r
	if int(r.value) < 0:
		return Result.failure("%s 必须 >= 0，实际: %d" % [path, int(r.value)])
	return r

static func _parse_string_array(value, path: String, allow_empty: bool) -> Result:
	if not (value is Array):
		return Result.failure("%s 类型错误（期望 Array[String]）" % path)
	var out: Array[String] = []
	for i in range(value.size()):
		var item = value[i]
		var s_read := _parse_string(item, "%s[%d]" % [path, i], false)
		if not s_read.ok:
			return s_read
		out.append(s_read.value)
	if not allow_empty and out.is_empty():
		return Result.failure("%s 不能为空" % path)
	return Result.success(out)
