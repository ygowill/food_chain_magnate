extends RefCounted

# === 现金操作 ===

static func _require_player_cash(state: GameState, player_id: int, caller: String) -> Result:
	if not (state.players is Array):
		return Result.failure("%s: state.players 类型错误（期望 Array）" % caller)
	if player_id < 0 or player_id >= state.players.size():
		return Result.failure("%s: player_id 越界: %d" % [caller, player_id])
	var player_val = state.players[player_id]
	if not (player_val is Dictionary):
		return Result.failure("%s: players[%d] 类型错误（期望 Dictionary）" % [caller, player_id])
	var player: Dictionary = player_val
	if not player.has("cash") or not (player["cash"] is int):
		return Result.failure("%s: players[%d].cash 缺失或类型错误（期望 int）" % [caller, player_id])
	return Result.success({
		"player": player,
		"cash": int(player["cash"]),
	})

static func _require_bank_total(state: GameState, caller: String) -> Result:
	if not (state.bank is Dictionary):
		return Result.failure("%s: state.bank 类型错误（期望 Dictionary）" % caller)
	if not state.bank.has("total") or not (state.bank["total"] is int):
		return Result.failure("%s: state.bank.total 缺失或类型错误（期望 int）" % caller)
	return Result.success(int(state.bank["total"]))

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
			var ctx_read := _require_player_cash(state, holder_id, "StateUpdater._get_balance")
			if not ctx_read.ok:
				return ctx_read
			var ctx: Dictionary = ctx_read.value
			return Result.success(int(ctx["cash"]))
		"bank":
			if holder_id != -1:
				return Result.failure("StateUpdater._get_balance: bank holder_id 必须为 -1，实际: %d" % holder_id)
			return _require_bank_total(state, "StateUpdater._get_balance")
		_:
			return Result.failure("StateUpdater._get_balance: 未知 holder_type: %s" % holder_type)

static func get_balance(state: GameState, holder_type: String, holder_id: int) -> Result:
	return _get_balance(state, holder_type, holder_id)

# 修改余额
static func _modify_balance(state: GameState, holder_type: String, holder_id: int, delta: int) -> Result:
	if state == null:
		return Result.failure("StateUpdater._modify_balance: state 为空")
	match holder_type:
		"player":
			var ctx_read := _require_player_cash(state, holder_id, "StateUpdater._modify_balance")
			if not ctx_read.ok:
				return ctx_read
			var ctx: Dictionary = ctx_read.value
			var player: Dictionary = ctx["player"]
			player["cash"] = int(ctx["cash"]) + delta
			state.players[holder_id] = player
			return Result.success()
		"bank":
			if holder_id != -1:
				return Result.failure("StateUpdater._modify_balance: bank holder_id 必须为 -1，实际: %d" % holder_id)
			var total_read := _require_bank_total(state, "StateUpdater._modify_balance")
			if not total_read.ok:
				return total_read
			state.bank["total"] = int(total_read.value) + delta
			return Result.success()
		_:
			return Result.failure("StateUpdater._modify_balance: 未知 holder_type: %s" % holder_type)

static func modify_balance(state: GameState, holder_type: String, holder_id: int, delta: int) -> Result:
	return _modify_balance(state, holder_type, holder_id, delta)

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
