# 调试：给房屋增加需求（内部）
# 通过复用 MarketingSettlementHelpers.add_house_demand，确保需求 token 结构与 cap/花园规则一致。
class_name DebugAddHouseDemandAction
extends ActionExecutor

const MarketingSettlementHelpersClass = preload("res://modules/base_rules/rules/phase/marketing/settlement_helpers.gd")
const MapStateAccessClass = preload("res://core/state/map_state_access.gd")

func _init() -> void:
	action_id = "debug_add_house_demand"
	display_name = "调试：给房屋增加需求"
	description = "调试用：直接向指定房屋追加需求 token（用于快速构造晚餐/营销场景）"
	requires_actor = false  # 系统动作
	is_mandatory = false
	is_internal = true

func _validate_specific(state: GameState, command: Command) -> Result:
	if state == null:
		return Result.failure("state 为空")
	if command.actor != -1:
		return Result.failure("debug_add_house_demand 必须为系统命令")

	var house_id_read := require_string_param(command, "house_id")
	if not house_id_read.ok:
		return house_id_read
	var house_id: String = house_id_read.value

	var product_read := require_string_param(command, "product")
	if not product_read.ok:
		return product_read
	var product: String = product_read.value

	var amount_read := optional_int_param(command, "amount", 1)
	if not amount_read.ok:
		return amount_read
	var amount: int = int(amount_read.value)
	if amount <= 0:
		return Result.failure("amount 必须 > 0，实际: %d" % amount)

	var from_player_read := optional_int_param(command, "from_player", -1)
	if not from_player_read.ok:
		return from_player_read
	var from_player: int = int(from_player_read.value)
	if from_player < -1 or from_player >= state.players.size():
		return Result.failure("无效的 from_player: %d" % from_player)

	var board_number_read := optional_int_param(command, "board_number", 0)
	if not board_number_read.ok:
		return board_number_read

	var marketing_type_read := optional_string_param(command, "marketing_type", "debug")
	if not marketing_type_read.ok:
		return marketing_type_read
	var marketing_type: String = marketing_type_read.value

	var houses_read := MapStateAccessClass.require_houses(state, action_id)
	if not houses_read.ok:
		return houses_read
	var houses: Dictionary = houses_read.value
	if not houses.has(house_id):
		return Result.failure("房屋不存在: %s" % house_id)
	var house_val = houses[house_id]
	if not (house_val is Dictionary):
		return Result.failure("houses[%s] 类型错误（期望 Dictionary）" % house_id)
	var house: Dictionary = house_val
	if not house.has("has_garden") or not (house["has_garden"] is bool):
		return Result.failure("houses[%s].has_garden 缺失或类型错误（期望 bool）" % house_id)
	if not house.has("demands") or not (house["demands"] is Array):
		return Result.failure("houses[%s].demands 缺失或类型错误（期望 Array）" % house_id)

	if marketing_type.is_empty():
		return Result.failure("marketing_type 不能为空")
	if product.is_empty():
		return Result.failure("product 不能为空")

	return Result.success()

func _apply_changes(state: GameState, command: Command) -> Result:
	var house_id: String = str(command.params.get("house_id", ""))
	var product: String = str(command.params.get("product", ""))
	var from_player: int = int(command.params.get("from_player", -1))
	var board_number: int = int(command.params.get("board_number", 0))
	var marketing_type: String = str(command.params.get("marketing_type", "debug"))
	var amount: int = int(command.params.get("amount", 1))
	return MarketingSettlementHelpersClass.add_house_demand(
		state, house_id, product, from_player, board_number, marketing_type, amount
	)
