class_name ReplayBarSupportNoopTest
extends RefCounted

const GameTimelineReplayBarSupportClass = preload("res://ui/scenes/game/timeline/replay_bar_support.gd")

class _ReplayBarSpy:
	extends RefCounted

	var active_calls: int = 0
	var timeline_calls: int = 0
	var active: bool = true
	var last_head_index: int = -999
	var last_cursor_index: int = -999
	var last_read_only: bool = false
	var last_status_extra: String = ""

	func set_active(next_active: bool) -> void:
		active_calls += 1
		active = bool(next_active)

	func set_timeline(head_index: int, cursor_index: int, read_only: bool, status_extra: String = "") -> void:
		timeline_calls += 1
		last_head_index = int(head_index)
		last_cursor_index = int(cursor_index)
		last_read_only = bool(read_only)
		last_status_extra = str(status_extra)

class _GameLogPanelSpy:
	extends RefCounted

	var replay_bar = _ReplayBarSpy.new()

	func get_replay_bar():
		return replay_bar

static func run() -> Result:
	var game_log_panel := _GameLogPanelSpy.new()
	var history_timeline := {
		"steps": [
			{"phase": "Working"},
			{"phase": "Dinnertime"},
		],
	}
	var expected_extra_cursor_0 := GameTimelineReplayBarSupportClass.build_status_extra(0, history_timeline)
	var expected_extra_cursor_1 := GameTimelineReplayBarSupportClass.build_status_extra(1, history_timeline)

	GameTimelineReplayBarSupportClass.hide(game_log_panel)
	if game_log_panel.replay_bar.active_calls != 1:
		return Result.failure("首次 hide 应调用 1 次 set_active(false)，实际=%d" % game_log_panel.replay_bar.active_calls)

	GameTimelineReplayBarSupportClass.hide(game_log_panel)
	if game_log_panel.replay_bar.active_calls != 1:
		return Result.failure("重复 hide 不应重复调用 set_active(false)，实际=%d" % game_log_panel.replay_bar.active_calls)

	GameTimelineReplayBarSupportClass.set_state(
		game_log_panel,
		false,
		{},
		true,
		history_timeline,
		1,
		0,
		true
	)
	if game_log_panel.replay_bar.active_calls != 2:
		return Result.failure("首次 set_state 应把 ReplayBar 重新激活，实际 active_calls=%d" % game_log_panel.replay_bar.active_calls)
	if game_log_panel.replay_bar.timeline_calls != 1:
		return Result.failure("首次 set_state 应调用 1 次 set_timeline，实际=%d" % game_log_panel.replay_bar.timeline_calls)
	if game_log_panel.replay_bar.last_head_index != 1 or game_log_panel.replay_bar.last_cursor_index != 0:
		return Result.failure(
			"set_timeline 参数错误，实际 head=%d cursor=%d"
				% [game_log_panel.replay_bar.last_head_index, game_log_panel.replay_bar.last_cursor_index]
		)
	if game_log_panel.replay_bar.last_status_extra != expected_extra_cursor_0:
		return Result.failure("status_extra 应命中阶段文案，实际=%s" % game_log_panel.replay_bar.last_status_extra)

	GameTimelineReplayBarSupportClass.set_state(
		game_log_panel,
		false,
		{},
		true,
		history_timeline,
		1,
		0,
		true
	)
	if game_log_panel.replay_bar.active_calls != 2 or game_log_panel.replay_bar.timeline_calls != 1:
		return Result.failure(
			"相同 set_state 不应重复刷新 ReplayBar，实际 active=%d timeline=%d"
				% [game_log_panel.replay_bar.active_calls, game_log_panel.replay_bar.timeline_calls]
		)

	GameTimelineReplayBarSupportClass.set_state(
		game_log_panel,
		false,
		{},
		true,
		history_timeline,
		1,
		1,
		true
	)
	if game_log_panel.replay_bar.active_calls != 2:
		return Result.failure("仅 timeline 参数变化时不应重复 set_active(true)，实际=%d" % game_log_panel.replay_bar.active_calls)
	if game_log_panel.replay_bar.timeline_calls != 2:
		return Result.failure("cursor 变化时应只追加 1 次 set_timeline，实际=%d" % game_log_panel.replay_bar.timeline_calls)
	if game_log_panel.replay_bar.last_status_extra != expected_extra_cursor_1:
		return Result.failure("cursor 切换后阶段文案应更新，实际=%s" % game_log_panel.replay_bar.last_status_extra)

	GameTimelineReplayBarSupportClass.hide(game_log_panel)
	if game_log_panel.replay_bar.active_calls != 3:
		return Result.failure("从 active 切回隐藏时应调用 1 次 set_active(false)，实际=%d" % game_log_panel.replay_bar.active_calls)

	return Result.success({})
