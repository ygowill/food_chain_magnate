extends RefCounted

# === 现金操作 ===

# 转账：从一方转到另一方
# from_type: "player" | "bank"
# to_type: "player" | "bank"
static func transfer_cash(
	state: GameState,
	from_type: String,
	from_id: int,
	to_type: String,
	to_id: int,
	amount: int
) -> Result:
	if state == null:
		return Result.failure("转账失败：state 为空")
	if not (state.bank is Dictionary):
		return Result.failure("转账失败：state.bank 类型错误（期望 Dictionary）")
	if not (state.players is Array):
		return Result.failure("转账失败：state.players 类型错误（期望 Array）")
	if not state.bank.has("broke_count") or not (state.bank["broke_count"] is int):
		return Result.failure("转账失败：state.bank.broke_count 缺失或类型错误（期望 int）")

	if amount < 0:
		return Result.failure("转账金额不能为负: %d" % amount)

	if amount == 0:
		return Result.success().with_warning("转账金额为0")

	# 检查来源余额
	var from_balance_read := _get_balance(state, from_type, from_id)
	if not from_balance_read.ok:
		return from_balance_read
	var from_balance: int = int(from_balance_read.value)
	var allow_overdraft := false
	if from_type == "bank":
		allow_overdraft = int(state.bank["broke_count"]) >= 2
	if not allow_overdraft and from_balance < amount:
		return Result.failure("余额不足: 需要 $%d, 只有 $%d" % [amount, from_balance])

	# 执行转账
	var debit := _modify_balance(state, from_type, from_id, -amount)
	if not debit.ok:
		return debit
	var credit := _modify_balance(state, to_type, to_id, amount)
	if not credit.ok:
		return credit

	return Result.success({
		"from": {"type": from_type, "id": from_id},
		"to": {"type": to_type, "id": to_id},
		"amount": amount
	})

# 获取余额
static func _get_balance(state: GameState, holder_type: String, holder_id: int) -> Result:
	if state == null:
		return Result.failure("StateUpdater._get_balance: state 为空")
	match holder_type:
		"player":
			if not (state.players is Array):
				return Result.failure("StateUpdater._get_balance: state.players 类型错误（期望 Array）")
			if holder_id < 0 or holder_id >= state.players.size():
				return Result.failure("StateUpdater._get_balance: player_id 越界: %d" % holder_id)
			var player_val = state.players[holder_id]
			if not (player_val is Dictionary):
				return Result.failure("StateUpdater._get_balance: players[%d] 类型错误（期望 Dictionary）" % holder_id)
			var player: Dictionary = player_val
			if not player.has("cash") or not (player["cash"] is int):
				return Result.failure("StateUpdater._get_balance: players[%d].cash 缺失或类型错误（期望 int）" % holder_id)
			return Result.success(int(player["cash"]))
		"bank":
			if not (state.bank is Dictionary):
				return Result.failure("StateUpdater._get_balance: state.bank 类型错误（期望 Dictionary）")
			if holder_id != -1:
				return Result.failure("StateUpdater._get_balance: bank holder_id 必须为 -1，实际: %d" % holder_id)
			if not state.bank.has("total") or not (state.bank["total"] is int):
				return Result.failure("StateUpdater._get_balance: state.bank.total 缺失或类型错误（期望 int）")
			return Result.success(int(state.bank["total"]))
		_:
			return Result.failure("StateUpdater._get_balance: 未知 holder_type: %s" % holder_type)

# 修改余额
static func _modify_balance(state: GameState, holder_type: String, holder_id: int, delta: int) -> Result:
	if state == null:
		return Result.failure("StateUpdater._modify_balance: state 为空")
	match holder_type:
		"player":
			if not (state.players is Array):
				return Result.failure("StateUpdater._modify_balance: state.players 类型错误（期望 Array）")
			if holder_id < 0 or holder_id >= state.players.size():
				return Result.failure("StateUpdater._modify_balance: player_id 越界: %d" % holder_id)
			var player_val = state.players[holder_id]
			if not (player_val is Dictionary):
				return Result.failure("StateUpdater._modify_balance: players[%d] 类型错误（期望 Dictionary）" % holder_id)
			var player: Dictionary = player_val
			if not player.has("cash") or not (player["cash"] is int):
				return Result.failure("StateUpdater._modify_balance: players[%d].cash 缺失或类型错误（期望 int）" % holder_id)
			player["cash"] = int(player["cash"]) + delta
			state.players[holder_id] = player
			return Result.success()
		"bank":
			if not (state.bank is Dictionary):
				return Result.failure("StateUpdater._modify_balance: state.bank 类型错误（期望 Dictionary）")
			if holder_id != -1:
				return Result.failure("StateUpdater._modify_balance: bank holder_id 必须为 -1，实际: %d" % holder_id)
			if not state.bank.has("total") or not (state.bank["total"] is int):
				return Result.failure("StateUpdater._modify_balance: state.bank.total 缺失或类型错误（期望 int）")
			state.bank["total"] = int(state.bank["total"]) + delta
			return Result.success()
		_:
			return Result.failure("StateUpdater._modify_balance: 未知 holder_type: %s" % holder_type)

# === 玩家现金便捷方法 ===

# 玩家收入（从银行）
static func player_receive_from_bank(state: GameState, player_id: int, amount: int) -> Result:
	return transfer_cash(state, "bank", -1, "player", player_id, amount)

# 玩家支付（到银行）
static func player_pay_to_bank(state: GameState, player_id: int, amount: int) -> Result:
	return transfer_cash(state, "player", player_id, "bank", -1, amount)

# 玩家间转账
static func player_pay_to_player(state: GameState, from_id: int, to_id: int, amount: int) -> Result:
	return transfer_cash(state, "player", from_id, "player", to_id, amount)

# 直接设置玩家现金（慎用，主要用于初始化）
static func set_player_cash(state: GameState, player_id: int, amount: int) -> Result:
	if state == null:
		return Result.failure("set_player_cash: state 为空")
	if not (state.players is Array):
		return Result.failure("set_player_cash: state.players 类型错误（期望 Array）")
	if player_id < 0 or player_id >= state.players.size():
		return Result.failure("无效的玩家ID: %d" % player_id)

	if amount < 0:
		return Result.failure("现金不能为负: %d" % amount)

	var player_val = state.players[player_id]
	if not (player_val is Dictionary):
		return Result.failure("set_player_cash: players[%d] 类型错误（期望 Dictionary）" % player_id)
	var player: Dictionary = player_val
	if not player.has("cash") or not (player["cash"] is int):
		return Result.failure("set_player_cash: players[%d].cash 缺失或类型错误（期望 int）" % player_id)

	state.players[player_id]["cash"] = amount
	return Result.success()

