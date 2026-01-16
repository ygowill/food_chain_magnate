# GameStateFactory 起始库存读取测试（P0.2）
# 目的：避免 `starting_inventory` 字段被错误当作 method 检测而被静默跳过。
class_name GameStateFactoryStartingInventoryTest
extends RefCounted

const ContentCatalogClass = preload("res://core/modules/v2/content_catalog.gd")
const GameConfigClass = preload("res://core/data/game_config.gd")
const ProductDefClass = preload("res://core/data/product_def.gd")
const ProductRegistryClass = preload("res://core/data/product_registry.gd")

static func run() -> Result:
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

