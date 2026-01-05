extends RefCounted

func register(registrar) -> Result:
	# 将 recruit 从 Working/Recruit 改为 Working/Train（用于验证 action availability override 生效）
	var points: Array = [
		{"phase": "Working", "sub_phase": "Train"},
	]
	return registrar.register_action_availability_override("recruit", points, 100)
