# 调试：给玩家增加库存（内部）
# 设计目标：保持命令历史/回放一致性，同时不依赖员工/阶段限制（纯调试作弊入口）。
class_name DebugAddInventoryAction
extends ActionExecutor

const StateUpdaterClass = preload("res://core/state/state_updater.gd")
const ProductRegistryClass = preload("res://core/data/product_registry.gd")

func _init() -> void:
	action_id = "debug_add_inventory"
	display_name = "调试：增加库存"
	description = "调试用：直接增加指定玩家的库存（不依赖员工/阶段）"
	requires_actor = false  # 系统动作
	is_mandatory = false
	is_internal = true

func _validate_specific(state: GameState, command: Command) -> Result:
	if state == null:
		return Result.failure("state 为空")
	if command.actor != -1:
		return Result.failure("debug_add_inventory 必须为系统命令")

	var player_id_read := require_int_param(command, "player_id")
	if not player_id_read.ok:
		return player_id_read
	var player_id: int = int(player_id_read.value)
	if player_id < 0 or player_id >= state.players.size():
		return Result.failure("无效的玩家 ID: %d" % player_id)

	var product_read := require_string_param(command, "product")
	if not product_read.ok:
		return product_read
	var product: String = str(product_read.value).strip_edges()
	if product.is_empty():
		return Result.failure("product 不能为空")

	var amount_read := require_int_param(command, "amount")
	if not amount_read.ok:
		return amount_read
	var amount: int = int(amount_read.value)
	if amount < 0:
		return Result.failure("amount 不能为负: %d" % amount)

	# 严格校验产品 ID，避免写入无效库存键导致后续规则崩溃。
	if ProductRegistryClass.is_loaded() and ProductRegistryClass.get_def(product) == null:
		return Result.failure("未知产品: %s" % product)

	return Result.success()

func _apply_changes(state: GameState, command: Command) -> Result:
	var player_id: int = int(command.params.get("player_id", -1))
	var product: String = str(command.params.get("product", "")).strip_edges()
	var amount: int = int(command.params.get("amount", 0))
	if amount == 0:
		return Result.success()

	var add := StateUpdaterClass.add_inventory(state, player_id, product, amount)
	if not add.ok:
		return add

	return Result.success({
		"player_id": player_id,
		"product": product,
		"amount": amount,
	}).with_warnings(add.warnings)

