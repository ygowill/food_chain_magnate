extends RefCounted

func register(registrar) -> Result:
	# 将 Marketing 与 Payday 对调：
	# Restructuring -> OrderOfBusiness -> Working -> Dinnertime -> Marketing -> Payday -> Cleanup
	var order: Array = [
		"Restructuring",
		"OrderOfBusiness",
		"Working",
		"Dinnertime",
		"Marketing",
		"Payday",
		"Cleanup",
	]
	return registrar.register_phase_order_override(order, 100)
