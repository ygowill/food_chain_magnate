class_name SkipLobbyistsExtraMapTileAction
extends ActionExecutor

const MODULE_ID := "lobbyists"
const EXTRA_TILE_PENDING_KEY := "lobbyists_extra_tile_pending"

func _init() -> void:
	action_id = "skip_lobbyists_extra_map_tile"
	display_name = "说客里程碑：放弃扩边"
	description = "放弃“额外地图板块”放置（将 pending 清除）"
	requires_actor = true
	is_mandatory = false
	allowed_phases = ["Working"]
	allowed_sub_phases = ["Lobbyists"]

func _validate_specific(state: GameState, command: Command) -> Result:
	var current_player_id := state.get_current_player_id()
	if command.actor != current_player_id:
		return Result.failure("不是你的回合")
	if not (state.round_state is Dictionary):
		return Result.failure("state.round_state 类型错误（期望 Dictionary）")
	if not state.round_state.has(EXTRA_TILE_PENDING_KEY) or not (state.round_state[EXTRA_TILE_PENDING_KEY] is Dictionary):
		return Result.failure("当前没有可放弃的额外地图板块")
	var pending: Dictionary = state.round_state[EXTRA_TILE_PENDING_KEY]
	if not (pending.get(command.actor, false) is bool) or not bool(pending.get(command.actor, false)):
		return Result.failure("当前没有可放弃的额外地图板块")
	return Result.success()

func _apply_changes(state: GameState, command: Command) -> Result:
	var pending: Dictionary = state.round_state[EXTRA_TILE_PENDING_KEY]
	pending[command.actor] = false
	state.round_state[EXTRA_TILE_PENDING_KEY] = pending
	return Result.success({"player_id": int(command.actor)})

