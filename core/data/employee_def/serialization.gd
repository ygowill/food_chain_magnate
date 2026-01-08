extends RefCounted

static func to_dict(emp) -> Dictionary:
	var result := {
		"id": emp.id,
		"name": emp.name,
		"description": emp.description,
		"salary": emp.salary,
		"unique": emp.unique,
		"role": emp.role,
		"manager_slots": emp.manager_slots,
		"range": {
			"type": emp.range_type if not emp.range_type.is_empty() else null,
			"value": emp.range_value,
		},
		"train_to": emp.train_to,
		"train_capacity": emp.train_capacity,
		"tags": emp.tags,
		"usage_tags": emp.usage_tags,
		"mandatory": emp.mandatory,
		"can_be_fired": emp.can_be_fired,
		"effect_ids": emp.effect_ids,
	}
	if emp.recruit_capacity > 0:
		result["recruit_capacity"] = emp.recruit_capacity
	if emp.mandatory:
		result["mandatory_action_id"] = emp.mandatory_action_id

	if emp.pool_type != "none":
		var pool: Dictionary = {"type": emp.pool_type}
		if emp.pool_type == "fixed":
			pool["count"] = emp.pool_count
		result["pool"] = pool

	if emp.marketing_max_duration > 0:
		result["marketing_max_duration"] = emp.marketing_max_duration

	# 仅在有生产能力时添加 produces 字段
	if not emp.produces_food_type.is_empty() and emp.produces_amount > 0:
		result["produces"] = {
			"food_type": emp.produces_food_type,
			"amount": emp.produces_amount
		}

	return result

