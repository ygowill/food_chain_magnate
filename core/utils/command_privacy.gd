# 命令参数脱敏（联机保密）
# 约束：目前仅处理银行储备卡的选择保密（select_reserve_card.selected_index）。
extends RefCounted

static func sanitize_params(action_id: String, actor_id: int, params: Dictionary, viewer_player_id: int, state: GameState) -> Dictionary:
	if params == null:
		return {}
	# 必须复制：避免在 UI/调试视图中修改原始 Command.params（会污染命令历史/导出）
	var out: Dictionary = params.duplicate(true)
	if out.is_empty():
		return out

	var aid := str(action_id).strip_edges()
	if aid == "select_reserve_card":
		_sanitize_select_reserve_card(actor_id, out, viewer_player_id, state)

	return out

static func _sanitize_select_reserve_card(actor_id: int, out: Dictionary, viewer_player_id: int, state: GameState) -> void:
	if not out.has("selected_index"):
		return

	# 未知查看者（本地/热座）：不做脱敏
	if viewer_player_id < 0:
		return

	# 本人可见
	if viewer_player_id == actor_id:
		return

	# 特殊能力：允许查看全部储备卡（里程碑 first_have_20）
	if _viewer_can_peek_all_reserve_cards(viewer_player_id, state):
		return

	# 已揭示则公开
	if _is_reserve_card_revealed(actor_id, state):
		return

	out["selected_index"] = "<hidden>"

static func _viewer_can_peek_all_reserve_cards(viewer_player_id: int, state: GameState) -> bool:
	if state == null:
		return false
	if viewer_player_id < 0 or viewer_player_id >= state.players.size():
		return false
	var p_val = state.players[viewer_player_id]
	if not (p_val is Dictionary):
		return false
	var p: Dictionary = p_val
	var v = p.get("can_peek_all_reserve_cards", false)
	return (v is bool) and bool(v)

static func _is_reserve_card_revealed(player_id: int, state: GameState) -> bool:
	if state == null:
		return false
	if player_id < 0 or player_id >= state.players.size():
		return false
	var p_val = state.players[player_id]
	if not (p_val is Dictionary):
		return false
	var p: Dictionary = p_val
	var v = p.get("reserve_card_revealed", false)
	return (v is bool) and bool(v)
