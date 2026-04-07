# Game scene：冷启动联机恢复控制器（薄适配层，实际恢复由 OnlineSessionCoordinator 统一编排）
class_name GameStartupOnlineResumeController
extends RefCounted

var _host: Node = null
var _ensure_session: Callable = Callable()
var _resume_room: Callable = Callable()
var _connect_to_server: Callable = Callable()
var _on_game_started: Callable = Callable()
var _on_failure: Callable = Callable()
var _on_status_changed: Callable = Callable()

func _init(
	host: Node,
	ensure_session: Callable,
	resume_room: Callable,
	connect_to_server: Callable,
	on_game_started: Callable,
	on_failure: Callable,
	on_status_changed: Callable = Callable()
) -> void:
	_host = host
	_ensure_session = ensure_session
	_resume_room = resume_room
	_connect_to_server = connect_to_server
	_on_game_started = on_game_started
	_on_failure = on_failure
	_on_status_changed = on_status_changed

func dispose() -> void:
	_host = null
	_ensure_session = Callable()
	_resume_room = Callable()
	_connect_to_server = Callable()
	_on_game_started = Callable()
	_on_failure = Callable()
	_on_status_changed = Callable()

func should_attempt_startup_resume() -> bool:
	if OnlineSessionCoordinator == null or not OnlineSessionCoordinator.has_method("should_attempt_startup_game_resume"):
		return false
	return bool(OnlineSessionCoordinator.should_attempt_startup_game_resume())

func attempt_startup_resume_if_needed() -> bool:
	if not should_attempt_startup_resume():
		return false

	var result: Dictionary = await OnlineSessionCoordinator.attempt_startup_game_resume({
		"host": _host,
		"ensure_session": _ensure_session,
		"resume_room": _resume_room,
		"connect_resume": Callable(self, "_connect_from_resume_ticket"),
		"on_game_started": _on_game_started,
		"on_status_changed": _on_status_changed,
		"shutdown_on_wait_failure": true,
	})
	if bool(result.get("ok", false)):
		return true
	if bool(result.get("attempted", false)) and _on_failure.is_valid():
		_on_failure.call(str(result.get("message", "联机恢复失败")))
	return false

func _connect_from_resume_ticket(ws_url: String, connect_token: String) -> Result:
	var url := _build_connect_url(ws_url, connect_token)
	if url.is_empty():
		return Result.failure("resume_room 缺少 ws_url/connect_token")
	if not _connect_to_server.is_valid():
		return Result.failure("connect_to_server callable missing")
	var result = _connect_to_server.call(url)
	if result is Result:
		return result
	return Result.failure("connect_to_server 返回类型错误")

func _build_connect_url(ws_url: String, connect_token: String) -> String:
	var base := str(ws_url).strip_edges()
	var token := str(connect_token).strip_edges()
	if base.is_empty() or token.is_empty():
		return ""
	var sep := "?" if base.find("?") < 0 else "&"
	return base + sep + "connect_token=" + token.uri_encode()
