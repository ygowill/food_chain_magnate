# Game timeline：UI 状态同步支持
# 负责：日志面板 timeline 指针、ReplayBar 显隐，以及 ActionPanel 只读原因。
extends RefCounted

const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const OnlinePhaseInteractionClass = preload("res://core/utils/online_phase_interaction.gd")

static func sync_ui(
	game_log_panel: Object,
	action_panel: Object,
	head_index: int,
	cursor_index: int,
	state: GameState,
	replay_mode_active: bool,
	manual_replay_enabled: bool,
	timeline_edit_mode_active: bool,
	get_online_resync_in_progress: Callable,
	set_replay_bar_state: Callable,
	hide_replay_bar: Callable
) -> void:
	var log_panel_visible := _is_log_panel_visible_for_timeline_updates(game_log_panel)
	if is_instance_valid(game_log_panel):
		if game_log_panel.has_method("set_timeline_head_cursor"):
			game_log_panel.call("set_timeline_head_cursor", int(head_index), int(cursor_index), bool(log_panel_visible))
		else:
			game_log_panel.call("set_timeline_head", int(head_index))
			game_log_panel.call("set_timeline_cursor", int(cursor_index))

	var show_bar := bool(replay_mode_active) or int(cursor_index) < int(head_index) or bool(manual_replay_enabled)
	if show_bar:
		if set_replay_bar_state.is_valid():
			set_replay_bar_state.call(
				int(head_index),
				int(cursor_index),
				bool(replay_mode_active) or bool(manual_replay_enabled)
			)
	else:
		if hide_replay_bar.is_valid():
			hide_replay_bar.call()

	if is_instance_valid(action_panel) and action_panel.has_method("set_globally_disabled"):
		action_panel.call(
			"set_globally_disabled",
			resolve_action_panel_disable_reason(
				int(head_index),
				int(cursor_index),
				state,
				bool(replay_mode_active),
				bool(manual_replay_enabled),
				bool(timeline_edit_mode_active),
				get_online_resync_in_progress
			)
		)

static func _is_log_panel_visible_for_timeline_updates(game_log_panel: Object) -> bool:
	if game_log_panel == null or not is_instance_valid(game_log_panel):
		return false
	if game_log_panel is CanvasItem:
		return bool((game_log_panel as CanvasItem).is_visible_in_tree())
	if game_log_panel.has_method("is_visible_in_tree"):
		return bool(game_log_panel.call("is_visible_in_tree"))
	return true

static func resolve_action_panel_disable_reason(
	head_index: int,
	cursor_index: int,
	state: GameState,
	replay_mode_active: bool,
	manual_replay_enabled: bool,
	timeline_edit_mode_active: bool,
	get_online_resync_in_progress: Callable
) -> String:
	if bool(replay_mode_active) or bool(manual_replay_enabled):
		return "回放中不可操作"
	if int(cursor_index) < int(head_index) and not bool(timeline_edit_mode_active):
		return "查看历史中不可操作"
	if state != null and str(state.phase) == DefsClass.PHASE_GAME_OVER:
		return "游戏已结束"
	if NetContext == null or NetContext.mode != NetContext.Mode.ONLINE_CLIENT:
		return ""

	var online_resync := false
	if get_online_resync_in_progress.is_valid():
		online_resync = bool(get_online_resync_in_progress.call())
	if online_resync:
		return "联机：同步中"
	if state == null:
		return "联机：等待同步"
	if NetContext.local_player_id < 0:
		return "联机：身份未就绪"
	if not OnlinePhaseInteractionClass.can_local_player_act_in_online_phase(state):
		return "联机：等待其他玩家操作"
	return ""
