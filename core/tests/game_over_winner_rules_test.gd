# GameOver 赢家规则：弃权玩家不得获胜（M4）
class_name GameOverWinnerRulesTest
extends RefCounted

const RulesClass = preload("res://core/rules/game_over_winner_rules.gd")

static func run() -> Result:
	var engine := GameEngine.new()
	var init_r := engine.initialize(2, 12345)
	if not init_r.ok:
		return Result.failure("initialize 失败: %s" % init_r.error)

	var state: GameState = engine.get_state()
	if state == null:
		return Result.failure("state 为空")

	# P0 弃权且现金更高，P1 现金更低但应获胜
	var p0: Dictionary = state.get_player(0)
	p0["cash"] = 100
	p0["forfeited"] = true
	state.players[0] = p0

	var p1: Dictionary = state.get_player(1)
	p1["cash"] = -10
	p1["forfeited"] = false
	state.players[1] = p1

	var w1: Result = RulesClass.pick_winner_player_id(state)
	if not w1.ok:
		return Result.failure("pick_winner_player_id 失败: %s" % w1.error)
	if int(w1.value) != 1:
		return Result.failure("winner 预期为 P1，但实际: %s" % str(w1.value))

	# 排序：非弃权应排在弃权之前
	var rankings_r1: Result = RulesClass.build_cash_rankings(state)
	if not rankings_r1.ok:
		return Result.failure("build_cash_rankings 失败: %s" % rankings_r1.error)
	var rankings1_val = rankings_r1.value
	if not (rankings1_val is Array):
		return Result.failure("rankings 类型错误（期望 Array）")
	var rankings1: Array = rankings1_val
	if rankings1.is_empty():
		return Result.failure("rankings 为空")
	var first1: Dictionary = Dictionary(rankings1[0])
	if bool(first1.get("forfeited", false)):
		return Result.failure("rankings[0] 不应为 forfeited: %s" % str(first1))

	# 全员弃权：无赢家（-1）
	p1 = state.get_player(1)
	p1["forfeited"] = true
	state.players[1] = p1
	var w2: Result = RulesClass.pick_winner_player_id(state)
	if not w2.ok:
		return Result.failure("pick_winner_player_id(all forfeited) 失败: %s" % w2.error)
	if int(w2.value) != -1:
		return Result.failure("全员弃权 winner 预期为 -1，但实际: %s" % str(w2.value))

	return Result.success()
