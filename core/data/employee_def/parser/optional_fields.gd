extends RefCounted

const DataParseHelpersClass = preload("res://core/data/parse_helpers.gd")

static func apply(emp, data: Dictionary) -> Result:
	var mandatory_read := DataParseHelpersClass.parse_bool(data.get("mandatory", null), "EmployeeDef.mandatory")
	if not mandatory_read.ok:
		return mandatory_read
	emp.mandatory = bool(mandatory_read.value)

	# mandatory_action_id（可选，但 mandatory=true 时必须提供以避免硬编码映射）
	if data.has("mandatory_action_id"):
		var mai_read := DataParseHelpersClass.parse_string(data.get("mandatory_action_id", null), "EmployeeDef.mandatory_action_id", true)
		if not mai_read.ok:
			return mai_read
		emp.mandatory_action_id = mai_read.value
	else:
		if emp.mandatory:
			return Result.failure("EmployeeDef.mandatory_action_id 缺失（mandatory=true 时必须提供；为空字符串表示自动应用）")
		emp.mandatory_action_id = ""

	# can_be_fired（可选）：默认 true
	if data.has("can_be_fired"):
		var cbf_read := DataParseHelpersClass.parse_bool(data.get("can_be_fired", null), "EmployeeDef.can_be_fired")
		if not cbf_read.ok:
			return cbf_read
		emp.can_be_fired = bool(cbf_read.value)
	else:
		emp.can_be_fired = true

	if data.has("marketing_max_duration"):
		var mmd_read := DataParseHelpersClass.parse_non_negative_int(data.get("marketing_max_duration", null), "EmployeeDef.marketing_max_duration")
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
		var food_type_read := DataParseHelpersClass.parse_string(produces.get("food_type", null), "EmployeeDef.produces.food_type", false)
		if not food_type_read.ok:
			return food_type_read
		emp.produces_food_type = food_type_read.value

		var amount_read := DataParseHelpersClass.parse_int(produces.get("amount", null), "EmployeeDef.produces.amount")
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

		var type_read := DataParseHelpersClass.parse_string(pool.get("type", null), "EmployeeDef.pool.type", false)
		if not type_read.ok:
			return type_read
		var ptype: String = type_read.value
		if ptype != "fixed" and ptype != "one_x" and ptype != "none":
			return Result.failure("EmployeeDef.pool.type 不支持: %s" % ptype)
		emp.pool_type = ptype

		match ptype:
			"fixed":
				var count_read := DataParseHelpersClass.parse_non_negative_int(pool.get("count", null), "EmployeeDef.pool.count")
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
		var effect_ids_read := DataParseHelpersClass.parse_string_array(data.get("effect_ids", null), "EmployeeDef.effect_ids", true)
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

	return Result.success()

