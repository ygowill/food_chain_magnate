# 联机大厅：冷启动恢复控制器（薄适配层，实际恢复由 OnlineSessionCoordinator 统一编排）
class_name OnlineLobbyResumeController
extends RefCounted

var _ensure_session: Callable = Callable()
var _resume_room: Callable = Callable()
var _connect_to_ws: Callable = Callable()
var _mark_platform_ready: Callable = Callable()
var _set_connect_status: Callable = Callable()
var _set_browse_status: Callable = Callable()
var _show_error: Callable = Callable()
var _hide_loading: Callable = Callable()
var _refresh_ui: Callable = Callable()
var _attempted: bool = false

func setup(
	ensure_session: Callable,
	resume_room: Callable,
	connect_to_ws: Callable,
	mark_platform_ready: Callable,
	set_connect_status: Callable,
	set_browse_status: Callable,
	show_error: Callable,
	hide_loading: Callable,
	refresh_ui: Callable
) -> void:
	_ensure_session = ensure_session
	_resume_room = resume_room
	_connect_to_ws = connect_to_ws
	_mark_platform_ready = mark_platform_ready
	_set_connect_status = set_connect_status
	_set_browse_status = set_browse_status
	_show_error = show_error
	_hide_loading = hide_loading
	_refresh_ui = refresh_ui

func dispose() -> void:
	_ensure_session = Callable()
	_resume_room = Callable()
	_connect_to_ws = Callable()
	_mark_platform_ready = Callable()
	_set_connect_status = Callable()
	_set_browse_status = Callable()
	_show_error = Callable()
	_hide_loading = Callable()
	_refresh_ui = Callable()

func has_attempted() -> bool:
	return _attempted

func should_attempt_auto_resume() -> bool:
	if _attempted:
		return false
	if OnlineSessionCoordinator == null or not OnlineSessionCoordinator.has_method("should_attempt_lobby_auto_resume"):
		return false
	return bool(OnlineSessionCoordinator.should_attempt_lobby_auto_resume())

func attempt_auto_resume_if_needed() -> void:
	if not should_attempt_auto_resume():
		return

	_attempted = true
	_set_auto_resume_reconnecting(true)
	var result: Dictionary = await OnlineSessionCoordinator.attempt_lobby_auto_resume({
		"ensure_session": _ensure_session,
		"resume_room": _resume_room,
		"connect_resume": _connect_to_ws,
		"on_status_changed": Callable(self, "_set_retry_status"),
		"shutdown_on_wait_failure": true,
	})
	_set_auto_resume_reconnecting(false)

	if bool(result.get("ok", false)):
		if _mark_platform_ready.is_valid():
			_mark_platform_ready.call()
		if _hide_loading.is_valid():
			_hide_loading.call()
		if _set_browse_status.is_valid():
			_set_browse_status.call("")
		if _refresh_ui.is_valid():
			_refresh_ui.call()
		return

	if not bool(result.get("attempted", false)):
		return
	_fail(
		str(result.get("title", "自动恢复失败")),
		str(result.get("message", "自动恢复失败"))
	)

func _fail(title: String, message: String) -> void:
	if _hide_loading.is_valid():
		_hide_loading.call()
	if _set_connect_status.is_valid():
		_set_connect_status.call(message)
	if _set_browse_status.is_valid():
		_set_browse_status.call("")
	if _refresh_ui.is_valid():
		_refresh_ui.call()
	if not OS.has_feature("headless") and _show_error.is_valid():
		_show_error.call(title, message)

func _set_retry_status(message: String) -> void:
	if _set_connect_status.is_valid():
		_set_connect_status.call(str(message))
	if _set_browse_status.is_valid():
		_set_browse_status.call("正在恢复房间...")
	if _refresh_ui.is_valid():
		_refresh_ui.call()

func _set_auto_resume_reconnecting(active: bool) -> void:
	if NetContext == null or not NetContext.has_method("set_online_reconnecting"):
		return
	if not NetContext.has_online_resume_context():
		return
	NetContext.set_online_reconnecting(bool(active))
