# Coffee cleanup 状态访问回归测试
class_name CoffeeCleanupStateAccessTest
extends RefCounted

const CoffeeCleanupClass = preload("res://modules/coffee/rules/coffee_cleanup.gd")

static func run(_player_count: int = 2, _seed_val: int = 12345) -> Result:
	var r := _test_cleanup_discards_coffee_and_preserves_other_inventory()
	if not r.ok:
		return r
	r = _test_cleanup_requires_inventory_dict()
	if not r.ok:
		return r
	return Result.success({"cases": 2})

static func _test_cleanup_discards_coffee_and_preserves_other_inventory() -> Result:
	var state := GameState.new()
	state.players = [
		{"inventory": {"coffee": 2, "burger": 1}},
		{"inventory": {"coffee": 0}},
	]
	state.round_state = {}
	var cleanup = CoffeeCleanupClass.new()
	var run_r := cleanup._cleanup_discard_coffee(state, null)
	if not run_r.ok:
		return Result.failure("cleanup 执行失败: %s" % run_r.error)
	if int(state.players[0]["inventory"].get("coffee", -1)) != 0:
		return Result.failure("玩家0 coffee 应被清零，实际: %s" % str(state.players[0]["inventory"].get("coffee", null)))
	if int(state.players[0]["inventory"].get("burger", -1)) != 1:
		return Result.failure("玩家0 其他库存不应受影响，实际: %s" % str(state.players[0]["inventory"]))
	var coffee_meta = state.round_state.get("coffee", null)
	if not (coffee_meta is Dictionary):
		return Result.failure("round_state.coffee 应为 Dictionary")
	var discarded = coffee_meta.get("discarded", null)
	if not (discarded is Array) or discarded.size() != 1:
		return Result.failure("discarded 应仅记录 1 条，实际: %s" % str(discarded))
	var first = discarded[0]
	if not (first is Dictionary):
		return Result.failure("discarded[0] 应为 Dictionary")
	if int(first.get("player_id", -1)) != 0 or int(first.get("amount", -1)) != 2:
		return Result.failure("discarded[0] 记录错误: %s" % str(first))
	return Result.success()

static func _test_cleanup_requires_inventory_dict() -> Result:
	var state := GameState.new()
	state.players = [
		{"cash": 10},
	]
	state.round_state = {}
	var cleanup = CoffeeCleanupClass.new()
	var run_r := cleanup._cleanup_discard_coffee(state, null)
	if run_r.ok:
		return Result.failure("缺失 inventory 时应失败")
	var err := str(run_r.error)
	if err.find("player[0].inventory") < 0:
		return Result.failure("错误信息应包含 inventory 路径，实际: %s" % err)
	return Result.success()
