# 随机地图生成测试（M2）
# 验证：
# - MapDef.random_tile_pool 非空时，初始化会随机抽取 tile 并随机旋转拼接
# - 抽取不放回（本局 tile_placements.tile_id 不重复；以 base_maps 的 pool 为准）
# - 同 seed 初始化结果确定性一致（回放一致性）
class_name RandomMapGenerationTest
extends RefCounted

static func run(player_count: int = 2, seed_val: int = 12345) -> Result:
	var engine_a := GameEngine.new()
	var init_a := engine_a.initialize(player_count, seed_val)
	if not init_a.ok:
		return Result.failure("初始化失败(A): %s" % init_a.error)
	var state_a := engine_a.get_state()

	var placements_val_a = state_a.map.get("tile_placements", null)
	if not (placements_val_a is Array):
		return Result.failure("state.map.tile_placements 类型错误（期望 Array）")
	var placements_a: Array = placements_val_a

	var grid_val = state_a.map.get("tile_grid_size", null)
	if not (grid_val is Vector2i):
		return Result.failure("state.map.tile_grid_size 类型错误（期望 Vector2i）")
	var grid: Vector2i = grid_val
	var expected: int = grid.x * grid.y
	if placements_a.size() != expected:
		return Result.failure("tile_placements 数量错误: got=%d expected=%d" % [placements_a.size(), expected])

	var seen: Dictionary = {}
	for i in range(placements_a.size()):
		var p_val = placements_a[i]
		if not (p_val is Dictionary):
			return Result.failure("tile_placements[%d] 类型错误（期望 Dictionary）" % i)
		var p: Dictionary = p_val
		if not p.has("tile_id") or not (p["tile_id"] is String) or str(p["tile_id"]).is_empty():
			return Result.failure("tile_placements[%d].tile_id 缺失或类型错误" % i)
		if not p.has("board_pos") or not (p["board_pos"] is Vector2i):
			return Result.failure("tile_placements[%d].board_pos 缺失或类型错误" % i)
		if not p.has("rotation") or not (p["rotation"] is int):
			return Result.failure("tile_placements[%d].rotation 缺失或类型错误" % i)
		var tile_id: String = str(p["tile_id"])
		if seen.has(tile_id):
			return Result.failure("tile_id 不应重复（不放回）：%s" % tile_id)
		seen[tile_id] = true
		var rot: int = int(p["rotation"])
		if rot != 0 and rot != 90 and rot != 180 and rot != 270:
			return Result.failure("rotation 非法: %d" % rot)

	var engine_b := GameEngine.new()
	var init_b := engine_b.initialize(player_count, seed_val)
	if not init_b.ok:
		return Result.failure("初始化失败(B): %s" % init_b.error)
	var state_b := engine_b.get_state()
	var placements_val_b = state_b.map.get("tile_placements", null)
	if not (placements_val_b is Array):
		return Result.failure("state_b.map.tile_placements 类型错误（期望 Array）")
	var placements_b: Array = placements_val_b

	var diff := _first_tile_placement_diff(placements_a, placements_b)
	if not diff.is_empty():
		var a_calls := engine_a.random_manager.get_call_count() if engine_a.random_manager != null else -1
		var b_calls := engine_b.random_manager.get_call_count() if engine_b.random_manager != null else -1
		return Result.failure("同 seed 初始化应确定性一致，但 tile_placements 不一致: %s (rng_calls a=%d b=%d)" % [diff, a_calls, b_calls])

	return Result.success({
		"player_count": player_count,
		"seed": seed_val,
		"tile_count": placements_a.size(),
	})

static func _tile_placements_equal(a: Array, b: Array) -> bool:
	return _first_tile_placement_diff(a, b).is_empty()

static func _first_tile_placement_diff(a: Array, b: Array) -> String:
	if a.size() != b.size():
		return "size a=%d b=%d" % [a.size(), b.size()]
	for i in range(a.size()):
		var av = a[i]
		var bv = b[i]
		if not (av is Dictionary) or not (bv is Dictionary):
			return "index=%d type_mismatch" % i
		var ad: Dictionary = av
		var bd: Dictionary = bv
		var atile: String = str(ad.get("tile_id", ""))
		var btile: String = str(bd.get("tile_id", ""))
		var apos = ad.get("board_pos", null)
		var bpos = bd.get("board_pos", null)
		var arot: int = int(ad.get("rotation", -1))
		var brot: int = int(bd.get("rotation", -1))

		if atile != btile or arot != brot or not (apos is Vector2i) or not (bpos is Vector2i) or Vector2i(apos) != Vector2i(bpos):
			return "index=%d a={tile=%s pos=%s rot=%d} b={tile=%s pos=%s rot=%d}" % [
				i, atile, str(apos), arot, btile, str(bpos), brot
			]
	return ""
