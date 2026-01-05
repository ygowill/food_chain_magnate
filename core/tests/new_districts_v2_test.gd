# 模块1：新区域（New Districts）
# - 公寓：营销需求 *2，且无需求上限
class_name NewDistrictsV2Test
extends RefCounted

const MapDefClass = preload("res://core/map/map_def.gd")
const MapBakerClass = preload("res://core/map/map_baker.gd")
const MapRuntimeClass = preload("res://core/map/map_runtime.gd")
const MarketingSettlementClass = preload("res://core/rules/phase/marketing_settlement.gd")

static func run(player_count: int = 2, seed_val: int = 12345) -> Result:
	if player_count != 2:
		return Result.failure("本测试固定为 2 人局（实际: %d）" % player_count)

	var engine := GameEngine.new()
	var enabled_modules: Array[String] = [
		"base_rules",
		"base_products",
		"base_pieces",
		"base_tiles",
		"base_maps",
		"base_employees",
		"base_milestones",
		"base_marketing",
		"new_districts",
	]
	var init := engine.initialize(2, seed_val, enabled_modules)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)

	var state: GameState = engine.get_state()

	var map_def := MapDefClass.create_fixed("new_districts_test_map", [
		{"tile_id": "tile_x", "board_pos": Vector2i(0, 0), "rotation": 0},
	])
	var bake := MapBakerClass.bake(map_def, engine.game_data.tiles, engine.game_data.pieces)
	if not bake.ok:
		return Result.failure("地图烘焙失败: %s" % bake.error)
	var apply := MapRuntimeClass.apply_baked_map(state, bake.value)
	if not apply.ok:
		return Result.failure("写入地图失败: %s" % apply.error)

	if not state.map.has("houses") or not (state.map["houses"] is Dictionary):
		return Result.failure("state.map.houses 缺失或类型错误（期望 Dictionary）")
	var houses: Dictionary = state.map["houses"]
	if not houses.has("π"):
		return Result.failure("测试地图应包含公寓房屋 π")
	if not (houses["π"] is Dictionary):
		return Result.failure("houses[π] 类型错误（期望 Dictionary）")
	var apt: Dictionary = houses["π"]

	if not bool(apt.get("no_demand_cap", false)):
		return Result.failure("公寓应启用 no_demand_cap=true")
	if int(apt.get("marketing_demand_multiplier", 0)) != 2:
		return Result.failure("公寓应启用 marketing_demand_multiplier=2")

	state.map["marketing_placements"] = {}
	state.marketing_instances = []
	state.map["marketing_placements"]["1"] = {
		"board_number": 1,
		"type": "billboard",
		"owner": 0,
		"product": "burger",
		"world_pos": Vector2i(0, 2),
		"remaining_duration": -1,
		"axis": "",
		"tile_index": -1,
	}
	state.marketing_instances.append({
		"board_number": 1,
		"type": "billboard",
		"owner": 0,
		"employee_type": "brand_director",
		"product": "burger",
		"world_pos": Vector2i(0, 2),
		"remaining_duration": -1,
		"axis": "",
		"tile_index": -1,
		"created_round": 1,
		"demand_amount": 10,
	})

	var settled := MarketingSettlementClass.apply(state, null, 1, engine.phase_manager)
	if not settled.ok:
		return Result.failure("MarketingSettlement 失败: %s" % settled.error)

	houses = state.map["houses"]
	apt = houses["π"]
	if not apt.has("demands") or not (apt["demands"] is Array):
		return Result.failure("公寓 demands 缺失或类型错误（期望 Array）")
	var demands: Array = apt["demands"]
	if demands.size() != 20:
		return Result.failure("公寓应生成 20 个需求（10 * 2），实际: %d" % demands.size())

	return Result.success()

