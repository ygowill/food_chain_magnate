# 晚餐结算动画：从结算数据构建可播放的订单序列
class_name DinnertimeAnimationOrdersBuilder
extends RefCounted

const HouseNumberManagerClass = preload("res://core/map/house_number_manager.gd")

static func build_orders_from_settlement(dt: Dictionary) -> Array[Dictionary]:
	var orders: Array[Dictionary] = []
	var sales_val = dt.get("sales", [])
	var sales_arr: Array = sales_val if sales_val is Array else []
	for i in range(sales_arr.size()):
		var sale = sales_arr[i]
		if not (sale is Dictionary):
			continue
		var req: Dictionary = sale.get("required", {})
		var house_id := str(sale.get("house_id", ""))
		var house_number_val = sale.get("house_number", house_id)
		orders.append({
			"house_id": house_id,
			"house_number": HouseNumberManagerClass.format_display_label(house_number_val, house_id, str(house_number_val)),
			"house_sort_value": house_number_val,
			"demands": req,
			"matched_restaurant": str(sale.get("winner_restaurant_id", "")),
			"products": req,
			"revenue": int(sale.get("revenue", 0)),
			"distance": int(sale.get("distance", 0)),
			"steps": int(sale.get("steps", 0)),
			"score": int(sale.get("score", 0)),
			"unit_price": int(sale.get("unit_price", 0)),
			"decision_unit_price": int(sale.get("decision_unit_price", sale.get("unit_price", 0))),
			"quantity": int(sale.get("quantity", 0)),
			"has_garden": bool(sale.get("has_garden", false)),
			"price_part": int(sale.get("price_part", 0)),
			"bonus": int(sale.get("bonus", 0)),
			"house_bonus": int(sale.get("house_bonus", 0)),
			"demand_variant_id": str(sale.get("demand_variant_id", "")),
			"winner_owner": int(sale.get("winner_owner", -1)),
			"sale_index": i,
			"is_skipped": false,
		})
	for skip in dt.get("skipped", []):
		if not (skip is Dictionary):
			continue
		var house_id := str(skip.get("house_id", ""))
		var house_number_val = skip.get("house_number", house_id)
		orders.append({
			"house_id": house_id,
			"house_number": HouseNumberManagerClass.format_display_label(house_number_val, house_id, str(house_number_val)),
			"house_sort_value": house_number_val,
			"demands": skip.get("required", {}),
			"matched_restaurant": "",
			"products": {},
			"revenue": 0,
			"distance": 0,
			"steps": 0,
			"score": 0,
			"winner_owner": -1,
			"demand_cards": int(skip.get("demands", 0)),
			"has_garden": bool(skip.get("has_garden", false)),
			"is_apartment": bool(skip.get("is_apartment", false)),
			"demand_variant_id": "",
			"is_skipped": true,
		})
	orders.sort_custom(func(a, b):
		var an: int = _parse_house_number(a.get("house_sort_value", a.get("house_number", "")))
		var bn: int = _parse_house_number(b.get("house_sort_value", b.get("house_number", "")))
		if an != bn:
			return an < bn
		return str(a.get("house_id", "")) < str(b.get("house_id", ""))
	)
	return orders

static func _parse_house_number(value) -> int:
	if value is int:
		return int(value)
	if value is float:
		var f: float = float(value)
		if f == floor(f):
			return int(f)
	if value is String:
		var s: String = str(value)
		if s.is_valid_int():
			return s.to_int()
	return 999999
