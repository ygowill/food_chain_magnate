# Game timeline：ReplayBar 视图支持
# 负责：ReplayBar 的连接、显示/隐藏与状态文本构建。
extends RefCounted

const UiSignalHelpersClass = preload("res://ui/utils/signal_helpers.gd")
const GameLogPanelClass = preload("res://ui/components/game_log/game_log_panel.gd")
const META_REPLAY_BAR_STATE_SIGNATURE := "_timeline_replay_bar_state_signature"

static func connect_seek_signal(game_log_panel: Object, owner: Object, method_name: String) -> void:
	var replay_bar = _get_replay_bar(game_log_panel)
	if replay_bar == null:
		return
	if replay_bar.has_signal("seek_requested"):
		UiSignalHelpersClass.safe_connect(replay_bar, "seek_requested", Callable(owner, method_name))
	if replay_bar.has_method("set_active"):
		replay_bar.call("set_active", false)
	_set_replay_bar_state_signature(replay_bar, {"active": false})

static func disconnect_seek_signal(game_log_panel: Object, owner: Object, method_name: String) -> void:
	var replay_bar = _get_replay_bar(game_log_panel)
	if replay_bar == null:
		return
	var cb := Callable(owner, method_name)
	if replay_bar.has_signal("seek_requested") and replay_bar.is_connected("seek_requested", cb):
		replay_bar.disconnect("seek_requested", cb)

static func set_state(
	game_log_panel: Object,
	replay_mode_active: bool,
	replay_step_timeline: Dictionary,
	history_step_timeline_active: bool,
	history_step_timeline: Dictionary,
	head_index: int,
	cursor_index: int,
	read_only: bool
) -> void:
	var replay_bar = _get_replay_bar(game_log_panel)
	if replay_bar == null:
		return
	var extra := ""
	if bool(replay_mode_active) and replay_step_timeline.has("steps"):
		extra = build_status_extra(cursor_index, replay_step_timeline)
	elif bool(history_step_timeline_active) and history_step_timeline.has("steps"):
		extra = build_status_extra(cursor_index, history_step_timeline)

	var next_signature := {
		"active": true,
		"head_index": int(head_index),
		"cursor_index": int(cursor_index),
		"read_only": bool(read_only),
		"status_extra": extra,
	}
	var previous_signature = _get_replay_bar_state_signature(replay_bar)
	if previous_signature == next_signature:
		return
	var was_active := bool(previous_signature.get("active", false)) if previous_signature is Dictionary else false
	if replay_bar.has_method("set_active"):
		if not was_active:
			replay_bar.call("set_active", true)
	if replay_bar.has_method("set_timeline"):
		replay_bar.call("set_timeline", int(head_index), int(cursor_index), bool(read_only), extra)
	_set_replay_bar_state_signature(replay_bar, next_signature)

static func hide(game_log_panel: Object) -> void:
	var replay_bar = _get_replay_bar(game_log_panel)
	if replay_bar == null:
		return
	var previous_signature = _get_replay_bar_state_signature(replay_bar)
	if previous_signature is Dictionary and not bool(previous_signature.get("active", false)):
		return
	if replay_bar.has_method("set_active"):
		replay_bar.call("set_active", false)
	_set_replay_bar_state_signature(replay_bar, {"active": false})

static func build_status_extra(step_index: int, timeline: Dictionary) -> String:
	if timeline == null or timeline.is_empty():
		return ""

	var idx := int(step_index)
	var phase := ""
	if idx < 0:
		var init_val = timeline.get("initial_state_dict", null)
		if init_val is Dictionary:
			phase = str(Dictionary(init_val).get("phase", "")).strip_edges()
	else:
		var steps_val = timeline.get("steps", null)
		if not (steps_val is Array):
			return ""
		var steps: Array = steps_val
		if idx >= steps.size():
			return ""
		var s_val = steps[idx]
		if not (s_val is Dictionary):
			return ""
		phase = str(Dictionary(s_val).get("phase", "")).strip_edges()

	var display_name = GameLogPanelClass.PHASE_DISPLAY_NAMES.get(phase, phase)
	if str(display_name).strip_edges().is_empty():
		return "初始"
	return "阶段：%s" % str(display_name)

static func _get_replay_bar(game_log_panel: Object):
	if game_log_panel == null or not is_instance_valid(game_log_panel):
		return null
	if not game_log_panel.has_method("get_replay_bar"):
		return null
	var replay_bar = game_log_panel.call("get_replay_bar")
	if replay_bar == null or not is_instance_valid(replay_bar):
		return null
	return replay_bar

static func _get_replay_bar_state_signature(replay_bar: Object) -> Variant:
	if replay_bar == null or not is_instance_valid(replay_bar):
		return null
	if not replay_bar.has_meta(META_REPLAY_BAR_STATE_SIGNATURE):
		return null
	return replay_bar.get_meta(META_REPLAY_BAR_STATE_SIGNATURE)

static func _set_replay_bar_state_signature(replay_bar: Object, signature: Dictionary) -> void:
	if replay_bar == null or not is_instance_valid(replay_bar):
		return
	replay_bar.set_meta(META_REPLAY_BAR_STATE_SIGNATURE, Dictionary(signature))
