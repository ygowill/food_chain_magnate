# 联机恢复：错误分类与本地 resume 清理策略
class_name OnlineResumeErrorPolicy
extends RefCounted

static func classify_resume_failure(error_val) -> Dictionary:
	var detail := _extract_error_text(error_val)
	var http_status := _extract_http_status(error_val)
	var detail_lower := detail.to_lower()

	if http_status == 404 and detail_lower.find("room not found") != -1:
		return _permanent("房间不存在，无法继续恢复。")
	if http_status == 409 and detail_lower.find("room already ended") != -1:
		return _permanent("对局已结束，恢复上下文已失效。")
	if http_status == 403 and detail_lower.find("room membership not found") != -1:
		return _permanent("你已不在该房间中，恢复上下文已失效。")
	if http_status == 401 or detail_lower.find("unauthorized") != -1 or detail_lower.find("missing session_id") != -1:
		return _permanent("登录状态已失效，无法继续恢复。")
	if detail_lower.find("platform login failed") != -1:
		return _transient(detail if not detail.is_empty() else "平台登录失败。")
	if detail_lower.find("request_failed") != -1 or detail_lower.find("timeout") != -1 or detail_lower.find("cant_connect") != -1:
		return _transient(detail if not detail.is_empty() else "网络请求失败。")
	if detail_lower.find("resume_room 返回格式错误") != -1 or detail_lower.find("resume_room 响应缺少 ok") != -1:
		return _transient(detail if not detail.is_empty() else "恢复接口返回格式错误。")
	if detail_lower.find("resume_room 缺少 ws_url/connect_token") != -1:
		return _transient("恢复接口返回了不完整的连接信息。")
	return _transient(detail if not detail.is_empty() else "恢复失败。")

static func classify_user_mismatch(persisted_user_id: String, active_user_id: String) -> Dictionary:
	var expected := str(persisted_user_id).strip_edges()
	var actual := str(active_user_id).strip_edges()
	if expected.is_empty() or actual.is_empty() or expected == actual:
		return _transient("")
	return {
		"permanent": true,
		"clear_resume_context": true,
		"user_message": "当前登录账号与待恢复对局所属账号不一致，已取消自动恢复。",
	}

static func _extract_http_status(error_val) -> int:
	if error_val is Dictionary:
		return int(Dictionary(error_val).get("_http_status", 0))
	return 0

static func _extract_error_text(error_val) -> String:
	if error_val is Dictionary:
		var err_dict: Dictionary = Dictionary(error_val)
		var detail := str(err_dict.get("detail", "")).strip_edges()
		if not detail.is_empty():
			return detail
		var body: Variant = err_dict.get("body", null)
		if body != null:
			return str(body)
		return JSON.stringify(err_dict)
	return str(error_val).strip_edges()

static func _permanent(message: String) -> Dictionary:
	return {
		"permanent": true,
		"clear_resume_context": true,
		"user_message": str(message).strip_edges(),
	}

static func _transient(message: String) -> Dictionary:
	return {
		"permanent": false,
		"clear_resume_context": false,
		"user_message": str(message).strip_edges(),
	}
