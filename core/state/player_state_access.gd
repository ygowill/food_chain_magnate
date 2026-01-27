class_name PlayerStateAccess
extends RefCounted

static func _prefix(label: String) -> String:
	if label.is_empty():
		return ""
	if label.ends_with(": "):
		return label
	if label.ends_with("： "):
		return label
	if label.ends_with(":"):
		return "%s " % label
	if label.ends_with("："):
		return "%s " % label
	return "%s: " % label

static func require_player(state: GameState, player_id: int, prefix_label: String) -> Result:
	var prefix := _prefix(prefix_label)
	if state == null:
		return Result.failure("%sstate 为空" % prefix)
	if not (state.players is Array):
		return Result.failure("%sstate.players 类型错误（期望 Array）" % prefix)
	if player_id < 0 or player_id >= state.players.size():
		return Result.failure("%splayer_id 越界: %d" % [prefix, player_id])
	var player_val = state.players[player_id]
	if not (player_val is Dictionary):
		return Result.failure("%splayers[%d] 类型错误（期望 Dictionary）" % [prefix, player_id])
	return Result.success(player_val)

static func require_milestones(player: Dictionary, player_label: String, prefix_label: String) -> Result:
	var prefix := _prefix(prefix_label)
	if not player.has("milestones") or not (player["milestones"] is Array):
		return Result.failure("%s%s.milestones 缺失或类型错误（期望 Array）" % [prefix, player_label])
	return Result.success(player["milestones"])

static func require_player_milestones(state: GameState, player_id: int, prefix_label: String) -> Result:
	var player_read := require_player(state, player_id, prefix_label)
	if not player_read.ok:
		return player_read
	var player: Dictionary = player_read.value
	return require_milestones(player, "player[%d]" % player_id, prefix_label)
