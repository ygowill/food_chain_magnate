# state_updater inventory 状态访问回归测试
class_name StateUpdaterInventoryStateAccessTest
extends RefCounted

const InventoryOps = preload("res://core/state/state_updater/inventory.gd")

static func run(_player_count: int = 2, _seed_val: int = 12345) -> Result:
	var r := _test_add_inventory_reads_inventory_via_helper()
	if not r.ok:
		return r
	r = _test_remove_inventory_fails_fast_on_missing_inventory()
	if not r.ok:
		return r
	r = _test_has_inventory_reads_inventory_via_helper()
	if not r.ok:
		return r
	return Result.success({"cases": 3})

static func _make_state() -> GameState:
	var state := GameState.new()
	state.players = [
		{
			"inventory": {
				"burger": 2,
				"beer": 1,
			},
		},
		{
			"cash": 7,
		},
	]
	return state

static func _test_add_inventory_reads_inventory_via_helper() -> Result:
	var state := _make_state()
	var add := InventoryOps.add_inventory(state, 0, "burger", 3)
	if not add.ok:
		return Result.failure("add_inventory 失败: %s" % add.error)
	var inventory: Dictionary = state.players[0]["inventory"]
	if int(inventory.get("burger", -1)) != 5:
		return Result.failure("burger 库存应为 5，实际: %s" % str(inventory))
	return Result.success()

static func _test_remove_inventory_fails_fast_on_missing_inventory() -> Result:
	var state := _make_state()
	state.players[0].erase("inventory")
	var remove := InventoryOps.remove_inventory(state, 0, "burger", 1)
	if remove.ok:
		return Result.failure("缺失 inventory 时 remove_inventory 应失败")
	var err := str(remove.error)
	if err.find("player[0].inventory") < 0:
		return Result.failure("错误信息应包含 inventory 路径，实际: %s" % err)
	return Result.success()

static func _test_has_inventory_reads_inventory_via_helper() -> Result:
	var state := _make_state()
	if not InventoryOps.has_inventory(state, 0, "burger", 2):
		return Result.failure("burger=2 时应判定库存足够")
	if InventoryOps.has_inventory(state, 0, "burger", 3):
		return Result.failure("burger=3 时应判定库存不足")
	if not InventoryOps.has_inventory(state, 0, "pizza", 0):
		return Result.failure("缺失商品但 amount=0 时应返回 true")
	return Result.success()
