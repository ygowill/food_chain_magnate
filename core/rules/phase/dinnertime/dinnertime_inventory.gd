# DinnertimeSettlement：需求/库存辅助
class_name DinnertimeInventory
extends RefCounted

const ProductRegistryClass = preload("res://core/data/product_registry.gd")

static func build_demand_requirements(demands: Array) -> Result:
	var required: Dictionary = {}
	for i in range(demands.size()):
		var d = demands[i]
		if not (d is Dictionary):
			return Result.failure("晚餐结算失败：demands[%d] 类型错误（期望 Dictionary）" % i)
		var product_val = d.get("product", null)
		if not (product_val is String):
			return Result.failure("晚餐结算失败：demands[%d].product 类型错误（期望 String）" % i)
		var product := str(product_val)
		if product.is_empty():
			return Result.failure("晚餐结算失败：demands[%d].product 不能为空" % i)
		required[product] = int(required.get(product, 0)) + 1
	return Result.success(required)

static func required_has_non_drink_food(required: Dictionary) -> Result:
	if required == null or not (required is Dictionary):
		return Result.failure("晚餐结算失败：required 类型错误（期望 Dictionary）")
	for product_id_val in required.keys():
		if not (product_id_val is String):
			return Result.failure("晚餐结算失败：required key 类型错误（期望 String）")
		var product_id: String = str(product_id_val)
		if product_id.is_empty():
			return Result.failure("晚餐结算失败：required key 不能为空")
		var def_val = ProductRegistryClass.get_def(product_id)
		if def_val == null:
			return Result.failure("晚餐结算失败：未知产品定义: %s" % product_id)
		if not (def_val is ProductDef):
			return Result.failure("晚餐结算失败：产品定义类型错误（期望 ProductDef）: %s" % product_id)
		var def: ProductDef = def_val
		if def.has_tag("food") and not def.is_drink():
			return Result.success(true)
	return Result.success(false)

static func player_has_inventory(player: Dictionary, required: Dictionary) -> Result:
	var inv_val = player.get("inventory", null)
	if not (inv_val is Dictionary):
		return Result.failure("晚餐结算失败：player.inventory 类型错误（期望 Dictionary）")
	var inv: Dictionary = inv_val

	for product in required.keys():
		var need := int(required.get(product, 0))
		if need <= 0:
			continue
		var have := int(inv.get(product, 0))
		if have < need:
			return Result.success(false)
	return Result.success(true)

static func apply_inventory_delta(state: GameState, player_id: int, required: Dictionary) -> Result:
	if player_id < 0 or player_id >= state.players.size():
		return Result.failure("晚餐结算失败：player_id 越界: %d" % player_id)
	var player_val = state.players[player_id]
	if not (player_val is Dictionary):
		return Result.failure("晚餐结算失败：player 类型错误: players[%d]（期望 Dictionary）" % player_id)
	var player: Dictionary = player_val

	var inv_val = player.get("inventory", null)
	if not (inv_val is Dictionary):
		return Result.failure("晚餐结算失败：player[%d].inventory 类型错误（期望 Dictionary）" % player_id)
	var inv: Dictionary = inv_val

	for product in required.keys():
		var need := int(required.get(product, 0))
		if need <= 0:
			continue
		var before := int(inv.get(product, 0))
		var after := before - need
		if after < 0:
			return Result.failure("晚餐结算失败：库存扣减为负数: player=%d product=%s before=%d need=%d" % [player_id, str(product), before, need])
		inv[product] = after
	player["inventory"] = inv
	state.players[player_id] = player
	return Result.success()
