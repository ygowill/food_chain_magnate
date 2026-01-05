# Fail Fast 解析回归测试（T1）
# 覆盖：
# - MapRuntime.apply_baked_map 对 baked_data 的严格校验（Result.failure，而非静默兜底）
# - GameStateSerialization 对 map 的严格反序列化（拒绝非 String key / 非整数坐标）
# - MapBaker.bake 在缺失 piece_registry 时必须失败（不允许假设/默认占地）
class_name FailFastParsingTest
extends RefCounted

const GameDataClass = preload("res://core/data/game_data.gd")
const GameStateClass = preload("res://core/state/game_state.gd")
const MapBakerClass = preload("res://core/map/map_baker.gd")
const MapRuntimeClass = preload("res://core/map/map_runtime.gd")
const ContentCatalogLoaderV2Class = preload("res://core/modules/v2/content_catalog_loader.gd")

static func run(_player_count: int = 2, _seed_val: int = 12345) -> Result:
	var r1 := _test_map_runtime_apply_baked_map_validation()
	if not r1.ok:
		return r1

	var r2 := _test_game_state_map_decode_failures()
	if not r2.ok:
		return r2

	var r3 := _test_map_baker_requires_piece_registry()
	if not r3.ok:
		return r3

	return Result.success({
		"cases": 3,
	})

static func _test_map_runtime_apply_baked_map_validation() -> Result:
	var tile_size := int(MapUtils.TILE_SIZE)
	if tile_size <= 0:
		return Result.failure("测试前提不成立：MapUtils.TILE_SIZE 非法: %d" % tile_size)

	var grid_size := Vector2i(tile_size, tile_size)
	var cells := []
	for y in range(grid_size.y):
		var row := []
		for x in range(grid_size.x):
			row.append({})
		cells.append(row)

	var baked_ok := {
		"cells": cells,
		"grid_size": grid_size,
		"tile_placements": [{"tile_id": "tile_dummy", "board_pos": Vector2i.ZERO, "rotation": 0}],
		"houses": {},
		"restaurants": {},
		"drink_sources": [],
		"boundary_index": {},
		"next_house_number": 1,
	}

	var state_ok := GameStateClass.new()
	var ok_apply := MapRuntimeClass.apply_baked_map(state_ok, baked_ok)
	if not ok_apply.ok:
		return Result.failure("MapRuntime.apply_baked_map 不应拒绝合法 baked_data: %s" % ok_apply.error)

	# 确保 MapRuntime 写入运行时必需字段（不依赖 GameState 内置默认值）
	if not state_ok.map.has("next_restaurant_id") or not (state_ok.map["next_restaurant_id"] is int):
		return Result.failure("MapRuntime.apply_baked_map 应写入 next_restaurant_id(int)")
	if int(state_ok.map["next_restaurant_id"]) != 1:
		return Result.failure("next_restaurant_id 初始应为 1，实际: %s" % str(state_ok.map["next_restaurant_id"]))

	var bad_grid_size := baked_ok.duplicate(true)
	bad_grid_size["grid_size"] = [grid_size.x, grid_size.y]
	var r1 := MapRuntimeClass.apply_baked_map(GameStateClass.new(), bad_grid_size)
	if r1.ok:
		return Result.failure("grid_size 非 Vector2i 时应失败，但返回 ok")
	if str(r1.error).find("grid_size") < 0:
		return Result.failure("错误信息应包含 grid_size，实际: %s" % str(r1.error))

	var bad_cells := baked_ok.duplicate(true)
	bad_cells["cells"] = [[]]
	var r2 := MapRuntimeClass.apply_baked_map(GameStateClass.new(), bad_cells)
	if r2.ok:
		return Result.failure("cells 维度不匹配时应失败，但返回 ok")
	if str(r2.error).find("cells") < 0:
		return Result.failure("错误信息应包含 cells，实际: %s" % str(r2.error))

	var bad_next_house := baked_ok.duplicate(true)
	bad_next_house["next_house_number"] = 0
	var r3 := MapRuntimeClass.apply_baked_map(GameStateClass.new(), bad_next_house)
	if r3.ok:
		return Result.failure("next_house_number<=0 时应失败，但返回 ok")
	if str(r3.error).find("next_house_number") < 0:
		return Result.failure("错误信息应包含 next_house_number，实际: %s" % str(r3.error))

	return Result.success()

static func _test_game_state_map_decode_failures() -> Result:
	var state := GameStateClass.new()
	state.rules = {"dummy_rule": 1}

	var base: Dictionary = state.to_dict()

	# 1) map key 必须为 String
	var data_bad_key := base.duplicate(true)
	var map_bad_key: Dictionary = data_bad_key["map"]
	map_bad_key[123] = "bad"
	data_bad_key["map"] = map_bad_key

	var r1 := GameStateClass.from_dict(data_bad_key)
	if r1.ok:
		return Result.failure("GameState.from_dict 遇到非 String map key 时应失败，但返回 ok")
	var err1 := str(r1.error)
	if err1.find("GameState.map") < 0 or err1.find("key 类型错误") < 0:
		return Result.failure("错误信息应包含 GameState.map 与 key 类型错误，实际: %s" % err1)

	# 2) 坐标数组必须为整数（拒绝非整数 float）
	var data_bad_grid := base.duplicate(true)
	var map_bad_grid: Dictionary = data_bad_grid["map"]
	map_bad_grid["grid_size"] = [1.5, 2]
	data_bad_grid["map"] = map_bad_grid

	var r2 := GameStateClass.from_dict(data_bad_grid)
	if r2.ok:
		return Result.failure("GameState.from_dict 遇到非整数坐标时应失败，但返回 ok")
	var err2 := str(r2.error)
	if err2.find("grid_size") < 0 or err2.find("必须为整数") < 0:
		return Result.failure("错误信息应包含 grid_size 与 必须为整数，实际: %s" % err2)

	return Result.success()

static func _test_map_baker_requires_piece_registry() -> Result:
	var catalog_read := ContentCatalogLoaderV2Class.load_for_modules("res://modules", ["base_tiles"])
	if not catalog_read.ok:
		return Result.failure("无法加载模块内容: %s" % catalog_read.error)
	var data_read := GameDataClass.from_catalog(catalog_read.value)
	if not data_read.ok:
		return Result.failure("无法从 ContentCatalog 构建 GameData: %s" % data_read.error)
	var data: GameData = data_read.value

	# 构造一个最小 MapDef：只放一张包含印刷建筑的 tile（依赖 piece_registry）
	if not data.tiles.has("tile_a1"):
		return Result.failure("测试前提不成立：tile_registry 缺少 tile_a1")
	var tile_a1_val = data.tiles["tile_a1"]
	if not (tile_a1_val is TileDef):
		return Result.failure("tile_a1 定义类型错误（期望 TileDef）")
	var tile_a1: TileDef = tile_a1_val
	if tile_a1.printed_structures.is_empty():
		return Result.failure("测试前提不成立：tile_a1 没有 printed_structures")

	var map_def := MapDef.create_fixed("fail_fast_map", [{
		"tile_id": "tile_a1",
		"board_pos": Vector2i(0, 0),
		"rotation": 0,
	}])

	# piece_registry 省略（使用默认 {}）时，遇到印刷建筑必须失败
	var baked := MapBakerClass.bake(map_def, data.tiles)
	if baked.ok:
		return Result.failure("MapBaker.bake 在缺失 piece_registry 时不应成功（必须 fail-fast）")
	if str(baked.error).find("未找到建筑件定义") < 0:
		return Result.failure("错误信息应包含'未找到建筑件定义'，实际: %s" % str(baked.error))

	return Result.success()
