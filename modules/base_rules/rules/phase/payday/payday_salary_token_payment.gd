extends RefCounted

const ProductRegistryClass = preload("res://core/data/product_registry.gd")
const PlayerStateAccessClass = preload("res://core/state/player_state_access.gd")

static func count_food_drink_tokens(inventory: Dictionary) -> int:
	var total := 0
	for k in inventory.keys():
		var product_id: String = str(k)
		var def = ProductRegistryClass.get_def(product_id)
		if def == null or not (def is ProductDef):
			continue
		var product: ProductDef = def
		if product.has_tag("salary_token_ineligible"):
			continue
		if not (product.has_tag("food") or product.has_tag("drink")):
			continue
		var v = inventory.get(k, 0)
		if v is int and int(v) > 0:
			total += int(v)
	return total

static func compute_min_tokens_needed(
	paid_employee_count: int,
	salary_cost: int,
	milestone_delta: int,
	discount_amount: int,
	cash_available: int
) -> int:
	if paid_employee_count <= 0:
		return 0
	for t in range(paid_employee_count + 1):
		var due_cash := maxi(0, (paid_employee_count - t) * salary_cost + milestone_delta - discount_amount)
		if cash_available >= due_cash:
			return t
	return paid_employee_count

static func pay_with_tokens(state: GameState, player_id: int, tokens_needed: int) -> Result:
	if state == null:
		return Result.failure("PaydaySalaryTokenPayment: state 为空")
	if player_id < 0 or player_id >= state.players.size():
		return Result.failure("PaydaySalaryTokenPayment: player_id 越界: %d" % player_id)
	if tokens_needed <= 0:
		return Result.success({})

	var player_val = state.players[player_id]
	if not (player_val is Dictionary):
		return Result.failure("PaydaySalaryTokenPayment: players[%d] 类型错误（期望 Dictionary）" % player_id)
	var player: Dictionary = player_val

	var inventory_read := PlayerStateAccessClass.require_inventory(player, "player[%d]" % player_id, "PaydaySalaryTokenPayment")
	if not inventory_read.ok:
		return inventory_read
	var inventory: Dictionary = inventory_read.value

	var paid: Dictionary = {}
	var remaining := tokens_needed

	var ids: Array[String] = []
	for k in inventory.keys():
		ids.append(str(k))
	ids.sort()

	for product_id in ids:
		if remaining <= 0:
			break
		var def = ProductRegistryClass.get_def(product_id)
		if def == null or not (def is ProductDef):
			continue
		var product: ProductDef = def
		if product.has_tag("salary_token_ineligible"):
			continue
		if not (product.has_tag("food") or product.has_tag("drink")):
			continue
		var cur_val = inventory.get(product_id, 0)
		if not (cur_val is int):
			continue
		var cur: int = int(cur_val)
		if cur <= 0:
			continue
		var use := mini(cur, remaining)
		inventory[product_id] = cur - use
		paid[product_id] = use
		remaining -= use

	if remaining > 0:
		return Result.failure("PaydaySalaryTokenPayment: food/drink tokens 不足（need=%d remain=%d）" % [tokens_needed, remaining])

	player["inventory"] = inventory
	state.players[player_id] = player
	return Result.success(paid)
