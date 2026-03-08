# Payday 薪资 token 资格（数据驱动）测试（P0.1）
# 目的：确保 PaydaySettlement 仅依赖 ProductDef 标签决定 token 资格，而不是硬编码某个产品 id。
class_name PaydaySalaryTokenEligibilityTest
extends RefCounted

const ContentCatalogClass = preload("res://core/modules/v2/content_catalog.gd")
const ProductDefClass = preload("res://core/data/product_def.gd")
const ProductRegistryClass = preload("res://core/data/product_registry.gd")
const PaydaySettlementClass = preload("res://modules/base_rules/rules/phase/payday_settlement.gd")

static func run() -> Result:
	var was_loaded := ProductRegistryClass.is_loaded()
	var original_products: Dictionary = {}
	if was_loaded:
		for pid in ProductRegistryClass.get_all_ids():
			original_products[pid] = ProductRegistryClass.get_def(pid)

	var result: Result = Result.success()

	# 构造两种“food”产品：一个可用，一个通过 tag 标记为不可用（且 id 不是 coffee，用于防止字符串特例回归）。
	var eligible_id := "test_food_token_ok"
	var ineligible_id := "test_food_token_ineligible"

	var catalog := ContentCatalogClass.new()
	catalog.products = {}

	var def_ok := ProductDefClass.from_dict({
		"id": eligible_id,
		"name": "Token OK",
		"tags": ["food"],
		"starting_inventory": 0,
	})
	if not def_ok.ok:
		result = Result.failure("构造 ProductDef(eligible) 失败: %s" % def_ok.error)

	var def_no := ProductDefClass.from_dict({
		"id": ineligible_id,
		"name": "Token Ineligible",
		"tags": ["food", "salary_token_ineligible"],
		"starting_inventory": 0,
	})
	if result.ok and not def_no.ok:
		result = Result.failure("构造 ProductDef(ineligible) 失败: %s" % def_no.error)

	if result.ok:
		catalog.products[eligible_id] = def_ok.value
		catalog.products[ineligible_id] = def_no.value
		var configure := ProductRegistryClass.configure_from_catalog(catalog)
		if not configure.ok:
			result = Result.failure("配置 ProductRegistry 失败: %s" % configure.error)

	# Case A: 仅 1 个可用 token + 10 个不可用 token，支付 2 token 应失败（不可偷用 ineligible）。
	if result.ok:
		var state_a := GameState.new()
		state_a.players = [
			{
				"inventory": {
					eligible_id: 1,
					ineligible_id: 10,
				}
			}
		]
		var inv_a: Dictionary = state_a.players[0]["inventory"]
		var count_a := PaydaySettlementClass._count_food_drink_tokens(inv_a)
		if count_a != 1:
			result = Result.failure("count_food_drink_tokens 应忽略 ineligible，仅统计 1 个 eligible，实际: %d" % count_a)
		else:
			var pay_a := PaydaySettlementClass._pay_with_tokens(state_a, 0, 2)
			if pay_a.ok:
				result = Result.failure("仅 1 个 eligible token 时，支付 2 token 应失败（不可使用 ineligible token）")

	# Case B: 可用 token 充足时，仅扣减 eligible，不影响 ineligible。
	if result.ok:
		var state_b := GameState.new()
		state_b.players = [
			{
				"inventory": {
					eligible_id: 2,
					ineligible_id: 10,
				}
			}
		]
		var pay_b := PaydaySettlementClass._pay_with_tokens(state_b, 0, 2)
		if not pay_b.ok:
			result = Result.failure("支付 2 token 失败: %s" % pay_b.error)
		else:
			var inv_b: Dictionary = state_b.players[0]["inventory"]
			if int(inv_b.get(eligible_id, -1)) != 0:
				result = Result.failure("扣减后 eligible 库存应为 0，实际: %d" % int(inv_b.get(eligible_id, -1)))
			elif int(inv_b.get(ineligible_id, -1)) != 10:
				result = Result.failure("扣减后 ineligible 库存应保持 10，实际: %d" % int(inv_b.get(ineligible_id, -1)))
			else:
				var paid: Dictionary = pay_b.value
				if paid.size() != 1 or not paid.has(eligible_id) or int(paid.get(eligible_id, 0)) != 2:
					result = Result.failure("paid_with_tokens 结构不符合预期（应仅包含 eligible=2），实际: %s" % str(paid))

	# Case C: 未知 product id 应被忽略，不参与统计也不被扣减。
	if result.ok:
		var state_c := GameState.new()
		state_c.players = [
			{
				"inventory": {
					eligible_id: 1,
					"ghost_product": 9,
				}
			}
		]
		var inv_c: Dictionary = state_c.players[0]["inventory"]
		var count_c := PaydaySettlementClass._count_food_drink_tokens(inv_c)
		if count_c != 1:
			result = Result.failure("count_food_drink_tokens 应忽略未知 product，仅统计 eligible=1，实际: %d" % count_c)
		else:
			var pay_c := PaydaySettlementClass._pay_with_tokens(state_c, 0, 1)
			if not pay_c.ok:
				result = Result.failure("支付 1 token 失败: %s" % pay_c.error)
			else:
				var after_c: Dictionary = state_c.players[0]["inventory"]
				if int(after_c.get(eligible_id, -1)) != 0:
					result = Result.failure("扣减后 eligible 库存应为 0，实际: %d" % int(after_c.get(eligible_id, -1)))
				elif int(after_c.get("ghost_product", -1)) != 9:
					result = Result.failure("未知 product 不应被扣减，实际: %d" % int(after_c.get("ghost_product", -1)))

	# 恢复全局 ProductRegistry（避免影响后续测试）
	if was_loaded:
		var restore_catalog := ContentCatalogClass.new()
		restore_catalog.products = original_products
		var restore := ProductRegistryClass.configure_from_catalog(restore_catalog)
		if not restore.ok:
			if result.ok:
				result = Result.failure("恢复 ProductRegistry 失败: %s" % restore.error)
	else:
		ProductRegistryClass.reset()

	return result
