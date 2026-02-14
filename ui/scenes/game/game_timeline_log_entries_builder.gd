# Game scene：时间线日志条目构建器
# 负责：将 StepTimelineBuild 的 events 转换为 GameLogPanel 可渲染的 entries。
class_name GameTimelineLogEntriesBuilder
extends RefCounted

const GAME_EVENT_LOG_FORMATTER_SCRIPT_PATH := "res://ui/scenes/game/game_event_log_formatter.gd"

static func build(events: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if events == null or events.is_empty():
		return out

	var formatter = _new_formatter()
	var entry_id := 0

	for ev_val in events:
		if not (ev_val is Dictionary):
			continue
		var ev: Dictionary = ev_val
		var event_type := str(ev.get("type", "")).strip_edges()
		var is_stage_event := (
			event_type == EventBus.EventType.PHASE_CHANGED
			or event_type == EventBus.EventType.SUB_PHASE_CHANGED
			or event_type == EventBus.EventType.ROUND_STARTED
			or event_type == EventBus.EventType.ROUND_ENDED
			or event_type == EventBus.EventType.PLAYER_TURN_STARTED
			or event_type == EventBus.EventType.PLAYER_TURN_ENDED
			or event_type.ends_with("_report")
		)
		var cmd_index := int(ev.get("command_index", -1))
		var step_index := int(ev.get("step_index", cmd_index))
		var phase_segment := str(ev.get("phase_segment", "")).strip_edges()
		var event_seq := int(ev.get("sequence", entry_id))

		var formatted: Array = formatter.format(ev) if (formatter != null and is_instance_valid(formatter) and formatter.has_method("format")) else []
		for f_val in formatted:
			if not (f_val is Dictionary):
				continue
			var f: Dictionary = f_val
			var log_type := int(f.get("type", GameLogPanel.LogType.DEBUG))
			var msg := str(f.get("message", ""))
			var details_val = f.get("details", {})
			var details: Dictionary = details_val if (details_val is Dictionary) else {}
			if not details.has("command_index"):
				details["command_index"] = cmd_index
			if not details.has("step_index"):
				details["step_index"] = step_index
			if not phase_segment.is_empty() and not details.has("phase_segment"):
				details["phase_segment"] = phase_segment
			if not event_type.is_empty() and not details.has("event_type"):
				details["event_type"] = event_type
			if not details.has("is_stage_event"):
				details["is_stage_event"] = is_stage_event

			out.append({
				"type": log_type,
				"message": msg,
				"timestamp": str(event_seq),
				"details": details,
				"command_index": cmd_index,
				"step_index": step_index,
				"phase_segment": phase_segment,
				"event_seq": event_seq,
				"event_type": event_type,
				"is_stage_event": is_stage_event,
			})
			entry_id += 1

	if formatter != null and is_instance_valid(formatter) and formatter.has_method("dispose"):
		formatter.dispose()

	return out

static func _new_formatter():
	var formatter_script = ResourceLoader.load(
		GAME_EVENT_LOG_FORMATTER_SCRIPT_PATH,
		"Script",
		ResourceLoader.CACHE_MODE_IGNORE
	)
	if formatter_script == null:
		return null
	return formatter_script.new()
