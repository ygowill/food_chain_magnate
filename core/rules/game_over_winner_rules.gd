# GameOver：赢家选择规则
# 约束（联机弃权）：forfeited 玩家不得获胜
class_name GameOverWinnerRules
extends RefCounted

static func build_cash_rankings(state: GameState) -> Result:
	if state == null:
		return Result.failure("state 为空")
	if not (state.players is Array):
		return Result.failure("state.players 类型错误（期望 Array）")

	var out: Array[Dictionary] = []
	for player_id in range(state.players.size()):
		var pv = state.players[player_id]
		if not (pv is Dictionary):
			return Result.failure("players[%d] 类型错误（期望 Dictionary）" % player_id)
		var p: Dictionary = pv
		out.append({
			"id": player_id,
			"cash": int(p.get("cash", 0)),
			"forfeited": bool(p.get("forfeited", false)),
		})

	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var af := bool(a.get("forfeited", false))
		var bf := bool(b.get("forfeited", false))
		if af != bf:
			# 非弃权在前
			return (not af) and bf
		var ac := int(a.get("cash", 0))
		var bc := int(b.get("cash", 0))
		if ac != bc:
			return ac > bc
		return int(a.get("id", 0)) < int(b.get("id", 0))
	)

	return Result.success(out)

static func pick_winner_player_id(state: GameState) -> Result:
	var rankings_r := build_cash_rankings(state)
	if not rankings_r.ok:
		return rankings_r
	var rankings_val = rankings_r.value
	if not (rankings_val is Array):
		return Result.failure("rankings 类型错误（期望 Array）")
	var rankings: Array = rankings_val
	for entry_val in rankings:
		if not (entry_val is Dictionary):
			continue
		var entry: Dictionary = entry_val
		if bool(entry.get("forfeited", false)):
			continue
		return Result.success(int(entry.get("id", -1)))
	return Result.success(-1)

