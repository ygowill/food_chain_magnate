class_name OnlineResumeReplayEntryStateNoopTest
extends RefCounted

const GameTimelineOnlineResumeHistoryViewSupportClass = preload("res://ui/scenes/game/timeline/online_resume_history_view_support.gd")
const META_REPLAY_TOGGLE_AVAILABILITY_SIGNATURE := "_timeline_replay_toggle_availability_signature"

class _GameLogPanelSpy:
	extends RefCounted

	var availability_calls: int = 0
	var last_available: bool = false
	var last_inactive_text: String = ""
	var last_disabled_reason: String = ""

	func set_replay_toggle_availability(
		available: bool,
		inactive_text: String = "进入回放",
		disabled_reason: String = ""
	) -> void:
		availability_calls += 1
		last_available = bool(available)
		last_inactive_text = str(inactive_text)
		last_disabled_reason = str(disabled_reason)

static func run() -> Result:
	var panel := _GameLogPanelSpy.new()

	GameTimelineOnlineResumeHistoryViewSupportClass.sync_replay_entry_state(panel, true)
	if panel.availability_calls != 1:
		return Result.failure("首次 sync_replay_entry_state 应调用 1 次，实际=%d" % panel.availability_calls)

	GameTimelineOnlineResumeHistoryViewSupportClass.sync_replay_entry_state(panel, true)
	if panel.availability_calls != 1:
		return Result.failure("相同 replay entry state 不应重复同步，实际=%d" % panel.availability_calls)

	panel.set_meta(META_REPLAY_TOGGLE_AVAILABILITY_SIGNATURE, {"available": false})
	GameTimelineOnlineResumeHistoryViewSupportClass.sync_replay_entry_state(panel, true)
	if panel.availability_calls != 2:
		return Result.failure("signature 失效后应重新同步，实际=%d" % panel.availability_calls)
	if not panel.last_available:
		return Result.failure("replay_mode_active=true 时 availability 应保持 true")

	return Result.success({})
