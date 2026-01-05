extends RefCounted

func register(registrar) -> Result:
	# 将 Working 的 Recruit 与 Train 对调（其余保持不变）
	var order: Array = [
		"Train",
		"Recruit",
		"Marketing",
		"GetFood",
		"GetDrinks",
		"PlaceHouses",
		"PlaceRestaurants",
	]
	return registrar.register_working_sub_phase_order_override(order, 100)
