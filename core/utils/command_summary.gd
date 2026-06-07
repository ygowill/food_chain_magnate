# 命令摘要：用于 UI/联机 payload 中展示动作内容，同时复用隐私脱敏规则。
extends RefCounted

const CommandPrivacyClass = preload("res://core/utils/command_privacy.gd")

const PUBLIC_VIEWER_PLAYER_ID := 999999

static func summarize_command(
	command: Command,
	action_registry: ActionRegistry = null,
	viewer_player_id: int = -1,
	state: GameState = null,
	include_index: bool = true
) -> Dictionary:
	if command == null:
		return {}

	var action_id := str(command.action_id).strip_edges()
	var action_name := _resolve_action_name(action_id, command, action_registry)
	var sanitized_params: Dictionary = CommandPrivacyClass.sanitize_params(
		action_id,
		int(command.actor),
		command.params,
		int(viewer_player_id),
		state
	)
	var text := _build_text(command, action_name, sanitized_params, include_index)
	return {
		"index": int(command.index),
		"actor": int(command.actor),
		"action_id": action_id,
		"action_name": action_name,
		"params": sanitized_params,
		"text": text,
	}

static func summarize_command_range(
	command_history: Array,
	from_index: int,
	to_index: int,
	action_registry: ActionRegistry = null,
	viewer_player_id: int = -1,
	state: GameState = null,
	max_count: int = 8
) -> Dictionary:
	var summaries: Array[Dictionary] = []
	if command_history.is_empty():
		return {
			"summaries": summaries,
			"omitted_count": 0,
		}

	var start := clampi(int(from_index), 0, command_history.size())
	var end := clampi(int(to_index), -1, command_history.size() - 1)
	if end < start:
		return {
			"summaries": summaries,
			"omitted_count": 0,
		}

	var limit := maxi(1, int(max_count))
	var omitted_count := 0
	for idx in range(start, end + 1):
		if summaries.size() >= limit:
			omitted_count = end - idx + 1
			break
		var cmd_val = command_history[idx]
		if not (cmd_val is Command):
			continue
		summaries.append(summarize_command(cmd_val, action_registry, viewer_player_id, state, true))

	return {
		"summaries": summaries,
		"omitted_count": int(omitted_count),
	}

static func format_summaries(summaries: Array, omitted_count: int = 0, separator: String = "\n") -> String:
	var lines: Array[String] = []
	for summary_val in summaries:
		if not (summary_val is Dictionary):
			continue
		var summary: Dictionary = summary_val
		var text := str(summary.get("text", "")).strip_edges()
		if text.is_empty():
			continue
		lines.append(text)
	if int(omitted_count) > 0:
		lines.append("另有 %d 步未显示" % int(omitted_count))
	return str(separator).join(lines)

static func _resolve_action_name(action_id: String, command: Command, action_registry: ActionRegistry) -> String:
	var action_name := ""
	if action_registry != null:
		var executor := action_registry.get_executor(action_id)
		if executor != null:
			action_name = str(executor.display_name).strip_edges()
	if action_name.is_empty() and command != null:
		action_name = str(command.metadata.get("description", "")).strip_edges()
	if action_name.is_empty():
		action_name = action_id
	if action_name.is_empty():
		action_name = "未知动作"
	return action_name

static func _build_text(command: Command, action_name: String, params: Dictionary, include_index: bool) -> String:
	var parts: Array[String] = []
	if include_index:
		parts.append("#%d" % int(command.index))
	if int(command.actor) < 0:
		parts.append("系统")
	else:
		parts.append("P%d" % (int(command.actor) + 1))
	parts.append(str(action_name).strip_edges())
	var params_text := _format_params(params)
	if not params_text.is_empty():
		parts.append(params_text)
	return " ".join(parts)

static func _format_params(params: Dictionary) -> String:
	if params == null or params.is_empty():
		return ""

	var keys: Array[String] = []
	for key_val in params.keys():
		keys.append(str(key_val))
	keys.sort()

	var parts: Array[String] = []
	for key in keys:
		parts.append("%s=%s" % [key, _format_value(params.get(key, null))])
	return "{%s}" % ", ".join(parts)

static func _format_value(value) -> String:
	if value == null:
		return "null"
	if value is String:
		return str(value)
	if value is bool:
		return "true" if bool(value) else "false"
	if value is int or value is float:
		return str(value)
	if value is Dictionary:
		return _format_params(value)
	if value is Array:
		var parts: Array[String] = []
		var arr: Array = value
		for item in arr:
			parts.append(_format_value(item))
		return "[%s]" % ", ".join(parts)
	return str(value)
