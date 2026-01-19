extends RefCounted

const MODULE_ID := "hard_choices"

func register(registrar) -> Result:
	var patches := [
		# Remove after turn 2
		{"milestone_id": "first_burger_marketed", "patch": {"set_expires_at": 2}},
		{"milestone_id": "first_pizza_marketed", "patch": {"set_expires_at": 2}},
		{"milestone_id": "first_drink_marketed", "patch": {"set_expires_at": 2}},
		{"milestone_id": "first_train", "patch": {"set_expires_at": 2}},
		# Remove after turn 3
		{"milestone_id": "first_hire_3", "patch": {"set_expires_at": 3}},
	]
	for p_val in patches:
		assert(p_val is Dictionary, "%s: patches 元素类型错误（期望 Dictionary）" % MODULE_ID)
		var p: Dictionary = p_val
		var r = registrar.register_milestone_patch(str(p.get("milestone_id", "")), Dictionary(p.get("patch", {})))
		if not r.ok:
			return r

	return Result.success()
