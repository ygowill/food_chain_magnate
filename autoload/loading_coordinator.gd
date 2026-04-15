# 全局 Loading 协调器：以 session 形式统一管理跨场景 loading 生命周期。
extends Node

const DEFAULT_PROGRESS_MAX := 100.0

var _sessions: Dictionary = {}
var _session_order: Array[String] = []
var _order_counter: int = 0

func begin_session(session_id: String, options: Dictionary = {}) -> Dictionary:
	var normalized_id := str(session_id).strip_edges()
	if normalized_id.is_empty():
		return {}
	var state := _default_session_state(normalized_id)
	if _sessions.has(normalized_id):
		state = Dictionary(_sessions.get(normalized_id, {})).duplicate(true)
	else:
		_session_order.append(normalized_id)
	state = _merge_session_state(state, options)
	_order_counter += 1
	state["order"] = _order_counter
	state["active"] = true
	_sessions[normalized_id] = state
	_render_active_state()
	return Dictionary(state).duplicate(true)

func update_session(session_id: String, patch: Dictionary) -> Dictionary:
	var normalized_id := str(session_id).strip_edges()
	if normalized_id.is_empty():
		return {}
	if not _sessions.has(normalized_id):
		return begin_session(normalized_id, patch)
	var state: Dictionary = Dictionary(_sessions.get(normalized_id, {})).duplicate(true)
	state = _merge_session_state(state, patch)
	_sessions[normalized_id] = state
	_render_active_state()
	return Dictionary(state).duplicate(true)

func finish_session(session_id: String) -> void:
	var normalized_id := str(session_id).strip_edges()
	if normalized_id.is_empty():
		return
	if _sessions.erase(normalized_id):
		_session_order.erase(normalized_id)
	_render_active_state()

func fail_session(session_id: String, message: String = "") -> Dictionary:
	var normalized_id := str(session_id).strip_edges()
	if normalized_id.is_empty():
		return {}
	var patch := {
		"error": str(message).strip_edges(),
		"detail": str(message).strip_edges(),
		"show_progress": false,
	}
	return update_session(normalized_id, patch)

func clear_all_sessions() -> void:
	_sessions.clear()
	_session_order.clear()
	_render_active_state()

func has_session(session_id: String) -> bool:
	return _sessions.has(str(session_id).strip_edges())

func get_session(session_id: String) -> Dictionary:
	var normalized_id := str(session_id).strip_edges()
	if normalized_id.is_empty() or not _sessions.has(normalized_id):
		return {}
	return Dictionary(_sessions.get(normalized_id, {})).duplicate(true)

func get_active_session_id() -> String:
	var active := _select_active_session()
	return str(active.get("session_id", "")).strip_edges()

func get_active_session() -> Dictionary:
	return _select_active_session()

func _default_session_state(session_id: String) -> Dictionary:
	return {
		"session_id": session_id,
		"title": "加载中...",
		"detail": "",
		"stage": "",
		"wait_text": "",
		"show_progress": false,
		"progress_value": 0.0,
		"progress_max": DEFAULT_PROGRESS_MAX,
		"priority": 0,
		"order": 0,
		"active": true,
		"error": "",
	}

func _merge_session_state(state: Dictionary, patch: Dictionary) -> Dictionary:
	var merged: Dictionary = Dictionary(state).duplicate(true)
	for key in patch.keys():
		merged[str(key)] = patch.get(key, null)
	var progress_max := float(merged.get("progress_max", DEFAULT_PROGRESS_MAX))
	if progress_max <= 0.0:
		progress_max = DEFAULT_PROGRESS_MAX
	merged["progress_max"] = progress_max
	var progress_value := clampf(float(merged.get("progress_value", 0.0)), 0.0, progress_max)
	merged["progress_value"] = progress_value
	return merged

func _select_active_session() -> Dictionary:
	var best: Dictionary = {}
	for session_id in _session_order:
		if not _sessions.has(session_id):
			continue
		var candidate: Dictionary = Dictionary(_sessions.get(session_id, {})).duplicate(true)
		if not bool(candidate.get("active", true)):
			continue
		if best.is_empty():
			best = candidate
			continue
		var best_priority := int(best.get("priority", 0))
		var candidate_priority := int(candidate.get("priority", 0))
		if candidate_priority > best_priority:
			best = candidate
			continue
		if candidate_priority == best_priority and int(candidate.get("order", 0)) >= int(best.get("order", 0)):
			best = candidate
	return best

func _render_active_state() -> void:
	var active := _select_active_session()
	if active.is_empty():
		if SceneManager != null and SceneManager.has_method("clear_loading_state"):
			SceneManager.clear_loading_state()
		return
	if SceneManager != null and SceneManager.has_method("apply_loading_state"):
		SceneManager.apply_loading_state(active)
