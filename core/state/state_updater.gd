# 状态更新辅助类
# 提供安全的状态修改方法，支持事务性更新和变更跟踪
class_name StateUpdater
extends RefCounted

const CashOps = preload("res://core/state/state_updater/cash.gd")
const Collections = preload("res://core/state/state_updater/collections.gd")
const InventoryOps = preload("res://core/state/state_updater/inventory.gd")
const PeopleOps = preload("res://core/state/state_updater/employees_and_milestones.gd")
const BatchOps = preload("res://core/state/state_updater/batch.gd")

# 变更记录
var _changes: Array[Dictionary] = []
var _track_changes: bool = false

# === 现金操作 ===

static func transfer_cash(
	state: GameState,
	from_type: String,
	from_id: int,
	to_type: String,
	to_id: int,
	amount: int
) -> Result:
	return CashOps.transfer_cash(state, from_type, from_id, to_type, to_id, amount)

static func _get_balance(state: GameState, holder_type: String, holder_id: int) -> Result:
	return CashOps._get_balance(state, holder_type, holder_id)

static func _modify_balance(state: GameState, holder_type: String, holder_id: int, delta: int) -> Result:
	return CashOps._modify_balance(state, holder_type, holder_id, delta)

# === 玩家现金便捷方法 ===

static func player_receive_from_bank(state: GameState, player_id: int, amount: int) -> Result:
	return CashOps.player_receive_from_bank(state, player_id, amount)

static func player_pay_to_bank(state: GameState, player_id: int, amount: int) -> Result:
	return CashOps.player_pay_to_bank(state, player_id, amount)

static func player_pay_to_player(state: GameState, from_id: int, to_id: int, amount: int) -> Result:
	return CashOps.player_pay_to_player(state, from_id, to_id, amount)

static func set_player_cash(state: GameState, player_id: int, amount: int) -> Result:
	return CashOps.set_player_cash(state, player_id, amount)

# === 数值操作 ===

static func increment(dict: Dictionary, key: String, amount: int = 1) -> int:
	return Collections.increment(dict, key, amount)

static func decrement(dict: Dictionary, key: String, amount: int = 1) -> int:
	return Collections.decrement(dict, key, amount)

static func set_clamped(dict: Dictionary, key: String, value: int, min_val: int = 0, max_val: int = 999999) -> int:
	return Collections.set_clamped(dict, key, value, min_val, max_val)

# === 数组操作 ===

static func append_to_array(dict: Dictionary, key: String, item) -> void:
	Collections.append_to_array(dict, key, item)

static func remove_from_array(dict: Dictionary, key: String, item) -> bool:
	return Collections.remove_from_array(dict, key, item)

static func remove_at_index(dict: Dictionary, key: String, index: int) -> bool:
	return Collections.remove_at_index(dict, key, index)

# === 库存操作 ===

static func add_inventory(state: GameState, player_id: int, food_type: String, amount: int) -> Result:
	return InventoryOps.add_inventory(state, player_id, food_type, amount)

static func remove_inventory(state: GameState, player_id: int, food_type: String, amount: int) -> Result:
	return InventoryOps.remove_inventory(state, player_id, food_type, amount)

static func has_inventory(state: GameState, player_id: int, food_type: String, amount: int) -> bool:
	return InventoryOps.has_inventory(state, player_id, food_type, amount)

# === 员工操作 ===

static func add_employee(state: GameState, player_id: int, employee_id: String, to_reserve: bool = false) -> Result:
	return PeopleOps.add_employee(state, player_id, employee_id, to_reserve)

static func take_from_pool(state: GameState, employee_type: String, count: int = 1) -> Result:
	return PeopleOps.take_from_pool(state, employee_type, count)

static func return_to_pool(state: GameState, employee_type: String, count: int = 1) -> Result:
	return PeopleOps.return_to_pool(state, employee_type, count)

# === 里程碑操作 ===

static func claim_milestone(state: GameState, player_id: int, milestone_id: String) -> Result:
	return PeopleOps.claim_milestone(state, player_id, milestone_id)

static func is_milestone_available(state: GameState, milestone_id: String) -> bool:
	return PeopleOps.is_milestone_available(state, milestone_id)

static func player_has_milestone(state: GameState, player_id: int, milestone_id: String) -> bool:
	return PeopleOps.player_has_milestone(state, player_id, milestone_id)

# === 批量更新 ===

static func apply_batch(state: GameState, updates: Array[Dictionary]) -> Result:
	return BatchOps.apply_batch(state, updates)

