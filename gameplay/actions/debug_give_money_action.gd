# 调试：给玩家金钱（内部）
# 通过“注入储备 + 银行转账”保持现金守恒不变量。
class_name DebugGiveMoneyAction
extends ActionExecutor

const StateUpdaterClass = preload("res://core/state/state_updater.gd")

func _init() -> void:
	action_id = "debug_give_money"
	display_name = "调试：给玩家金钱"
	description = "调试用：向指定玩家注入现金（通过 reserve_added_total 记账）"
	requires_actor = false  # 系统动作
	is_mandatory = false
	is_internal = true

func _validate_specific(state: GameState, command: Command) -> Result:
	if state == null:
		return Result.failure("state 为空")
	if command.actor != -1:
		return Result.failure("debug_give_money 必须为系统命令")

	var player_id_read := require_int_param(command, "player_id")
	if not player_id_read.ok:
		return player_id_read
	var player_id: int = int(player_id_read.value)
	if player_id < 0 or player_id >= state.players.size():
		return Result.failure("无效的玩家 ID: %d" % player_id)

	var amount_read := require_int_param(command, "amount")
	if not amount_read.ok:
		return amount_read
	var amount: int = int(amount_read.value)
	if amount < 0:
		return Result.failure("amount 不能为负: %d" % amount)

	return Result.success()

func _apply_changes(state: GameState, command: Command) -> Result:
	var player_id: int = int(command.params.get("player_id", -1))
	var amount: int = int(command.params.get("amount", 0))
	if amount == 0:
		return Result.success()

	if not (state.bank is Dictionary):
		return Result.failure("state.bank 类型错误（期望 Dictionary）")
	if not state.bank.has("total") or not (state.bank["total"] is int):
		return Result.failure("state.bank.total 缺失或类型错误（期望 int）")
	if not state.bank.has("reserve_added_total") or not (state.bank["reserve_added_total"] is int):
		return Result.failure("state.bank.reserve_added_total 缺失或类型错误（期望 int）")

	# 注入储备：增加 bank.total + reserve_added_total，再由银行转账给玩家
	state.bank["total"] = int(state.bank["total"]) + amount
	state.bank["reserve_added_total"] = int(state.bank["reserve_added_total"]) + amount

	var pay := StateUpdaterClass.player_receive_from_bank(state, player_id, amount)
	if not pay.ok:
		return pay

	return Result.success().with_warnings(pay.warnings)

