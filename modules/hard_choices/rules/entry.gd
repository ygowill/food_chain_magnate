extends RefCounted

const MODULE_ID := "hard_choices"

func register(registrar) -> Result:
	# Remove after turn 2
	var r = registrar.register_milestone_patch("first_burger_marketed", {"set_expires_at": 2})
	if not r.ok:
		return r
	r = registrar.register_milestone_patch("first_pizza_marketed", {"set_expires_at": 2})
	if not r.ok:
		return r
	r = registrar.register_milestone_patch("first_drink_marketed", {"set_expires_at": 2})
	if not r.ok:
		return r
	r = registrar.register_milestone_patch("first_train", {"set_expires_at": 2})
	if not r.ok:
		return r

	# Remove after turn 3
	r = registrar.register_milestone_patch("first_hire_3", {"set_expires_at": 3})
	if not r.ok:
		return r

	return Result.success()

