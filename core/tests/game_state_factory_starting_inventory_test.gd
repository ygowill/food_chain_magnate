# GameStateFactory 起始库存读取测试（P0.2）
# 目的：避免 `starting_inventory` 字段被错误当作 method 检测而被静默跳过。
class_name GameStateFactoryStartingInventoryTest
extends RefCounted

const ContentCatalogClass = preload("res://core/modules/v2/content_catalog.gd")
const GameConfigClass = preload("res://core/data/game_config.gd")
const ProductDefClass = preload("res://core/data/product_def.gd")
const ProductRegistryClass = preload("res://core/data/product_registry.gd")

static func run() -> Result:
	var reserve_cards_r := _test_default_reserve_card_cash_values()
	if not reserve_cards_r.ok:
		return reserve_cards_r

	var was_loaded := ProductRegistryClass.is_loaded()
	var original_products: Dictionary = {}
	if was_loaded:
		for pid in ProductRegistryClass.get_all_ids():
			original_products[pid] = ProductRegistryClass.get_def(pid)

	var test_product_id := "test_starting_inventory"
	var result: Result = Result.success()

	var catalog := ContentCatalogClass.new()
	catalog.products = original_products.duplicate()

	if catalog.products.has(test_product_id):
		result = Result.failure("测试 product_id 冲突：ProductRegistry 已包含 %s" % test_product_id)
	else:
		var def_read := ProductDefClass.from_dict({
			"id": test_product_id,
			"name": "Test Starting Inventory",
			"tags": [],
			"starting_inventory": 2,
		})
		if not def_read.ok:
			result = Result.failure("构造 ProductDef 失败: %s" % def_read.error)
		else:
			catalog.products[test_product_id] = def_read.value

			var configure := ProductRegistryClass.configure_from_catalog(catalog)
			if not configure.ok:
				result = Result.failure("配置 ProductRegistry 失败: %s" % configure.error)
			else:
				var cfg := GameConfigClass.new()
				cfg.player_starting_inventory = {} # 避免覆盖 test_product_id

				var player: Dictionary = GameStateFactory._create_player_from_config(0, cfg)
				var inv_val = player.get("inventory", null)
				if not (inv_val is Dictionary):
					result = Result.failure("player.inventory 类型错误（期望 Dictionary）")
				else:
					var inv: Dictionary = inv_val
					var got := int(inv.get(test_product_id, -1))
					if got != 2:
						result = Result.failure("起始库存应从 ProductDef.starting_inventory=2 读取，实际: %d" % got)

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

static func _test_default_reserve_card_cash_values() -> Result:
	var fallback_cfg := GameConfigClass.new()
	var fallback_r := _assert_reserve_card_cash_values(fallback_cfg.player_reserve_cards, "GameConfig.new().player_reserve_cards")
	if not fallback_r.ok:
		return fallback_r

	var cfg_read := GameConfigClass.load_default()
	if not cfg_read.ok:
		return Result.failure("加载默认 GameConfig 失败: %s" % cfg_read.error)
	var cfg = cfg_read.value
	var cfg_r := _assert_reserve_card_cash_values(cfg.player_reserve_cards, "GameConfig.load_default().player_reserve_cards")
	if not cfg_r.ok:
		return cfg_r

	var player: Dictionary = GameStateFactory._create_player_from_config(0, cfg)
	var player_r := _assert_reserve_card_cash_values(player.get("reserve_cards", null), "player.reserve_cards")
	if not player_r.ok:
		return player_r

	return Result.success()

static func _assert_reserve_card_cash_values(cards_val, path: String) -> Result:
	if not (cards_val is Array):
		return Result.failure("%s 类型错误（期望 Array）" % path)
	var cards: Array = cards_val
	var expected_cash: Array[int] = [100, 200, 300]
	var expected_slots: Array[int] = [2, 3, 4]
	if cards.size() != expected_cash.size():
		return Result.failure("%s 张数应为 %d，实际: %d" % [path, expected_cash.size(), cards.size()])
	for i in range(expected_cash.size()):
		var card_val = cards[i]
		if not (card_val is Dictionary):
			return Result.failure("%s[%d] 类型错误（期望 Dictionary）" % [path, i])
		var card: Dictionary = card_val
		if int(card.get("cash", -1)) != expected_cash[i]:
			return Result.failure("%s[%d].cash 应为 %d，实际: %s" % [path, i, expected_cash[i], str(card.get("cash", null))])
		if int(card.get("ceo_slots", -1)) != expected_slots[i]:
			return Result.failure("%s[%d].ceo_slots 应为 %d，实际: %s" % [path, i, expected_slots[i], str(card.get("ceo_slots", null))])
	return Result.success()
