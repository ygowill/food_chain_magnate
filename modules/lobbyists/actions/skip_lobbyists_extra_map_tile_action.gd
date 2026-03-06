class_name SkipLobbyistsExtraMapTileAction
extends ActionExecutor

const RoundStatePlayerBoolFlagsClass = preload("res://core/utils/round_state_player_bool_flags.gd")

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
	var pending_read := RoundStatePlayerBoolFlagsClass.get_player_flag(
		state.round_state,
		[EXTRA_TILE_PENDING_KEY],
		command.actor,
		MODULE_ID
	)
	if not pending_read.ok:
		return pending_read
	if not bool(pending_read.value):
		return Result.failure("当前没有可放弃的额外地图板块")
	return Result.success()

func _apply_changes(state: GameState, command: Command) -> Result:
	var clear_pending := RoundStatePlayerBoolFlagsClass.set_player_flag(
		state.round_state,
		[EXTRA_TILE_PENDING_KEY],
		command.actor,
		false,
		MODULE_ID
	)
	if not clear_pending.ok:
		return clear_pending
	return Result.success({"player_id": int(command.actor)})
