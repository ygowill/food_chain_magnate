# 联机大厅：即使错过 game_started 信号，也应在 InGame + engine 就绪时补进 Game。
class_name OnlineLobbyInGameEntryFallbackTest
extends RefCounted

const LobbyScript = preload("res://ui/scenes/online/online_lobby.gd")
const GameEngineClass = preload("res://core/engine/game_engine.gd")
const GameDefaultsClass = preload("res://core/engine/game_defaults.gd")

static func run() -> Result:
	if NetClient == null:
		return Result.failure("NetClient autoload missing")
	if Globals == null:
		return Result.failure("Globals autoload missing")

	var prev_engine = Globals.current_game_engine
	var prev_is_game_active := bool(Globals.is_game_active)
	var lobby = LobbyScript.new()
	var cb_rejected := Callable(lobby, "_on_request_rejected")
	var cb_game_started := Callable(lobby, "_on_game_started")

	if not NetClient.request_rejected.is_connected(cb_rejected):
		NetClient.request_rejected.connect(cb_rejected)
	if NetClient.game_started.is_connected(cb_game_started):
		NetClient.game_started.disconnect(cb_game_started)

	lobby.call("_bind_net_signals")
	if not NetClient.game_started.is_connected(cb_game_started):
		_cleanup_lobby_connections(cb_rejected, cb_game_started)
		_restore(prev_engine, prev_is_game_active)
		return Result.failure("request_rejected 已绑定时，_bind_net_signals 仍应补绑 game_started")

	Globals.current_game_engine = null
	Globals.is_game_active = false
	if bool(lobby.call("_should_enter_online_game_scene_from_room_state", {"status": "InGame"})):
		_cleanup_lobby_connections(cb_rejected, cb_game_started)
		_restore(prev_engine, prev_is_game_active)
		return Result.failure("没有 engine 时不应触发大厅补进 Game")

	var engine = GameEngineClass.new()
	var init_r: Result = engine.initialize(2, 12345, [], GameDefaultsClass.DEFAULT_MODULES_V2_BASE_DIR, [], [-1, -1])
	if not init_r.ok:
		_cleanup_lobby_connections(cb_rejected, cb_game_started)
		_restore(prev_engine, prev_is_game_active)
		return Result.failure("初始化测试 engine 失败: %s" % init_r.error)
	Globals.set_current_game_engine(engine)

	if not bool(lobby.call("_should_enter_online_game_scene_from_room_state", {"status": "InGame"})):
		_cleanup_lobby_connections(cb_rejected, cb_game_started)
		_restore(prev_engine, prev_is_game_active)
		return Result.failure("InGame 且 engine 已就绪时应允许大厅补进 Game")

	lobby.set("_enter_game_transition_requested", true)
	if bool(lobby.call("_should_enter_online_game_scene_from_room_state", {"status": "InGame"})):
		_cleanup_lobby_connections(cb_rejected, cb_game_started)
		_restore(prev_engine, prev_is_game_active)
		return Result.failure("进入 Game 已请求后不应重复触发大厅补进")
	lobby.set("_enter_game_transition_requested", false)

	if bool(lobby.call("_should_enter_online_game_scene_from_room_state", {"status": "Lobby"})):
		_cleanup_lobby_connections(cb_rejected, cb_game_started)
		_restore(prev_engine, prev_is_game_active)
		return Result.failure("非 InGame 状态不应触发大厅补进 Game")

	_cleanup_lobby_connections(cb_rejected, cb_game_started)
	_restore(prev_engine, prev_is_game_active)
	return Result.success()

static func _cleanup_lobby_connections(cb_rejected: Callable, cb_game_started: Callable) -> void:
	if NetClient == null:
		return
	if NetClient.request_rejected.is_connected(cb_rejected):
		NetClient.request_rejected.disconnect(cb_rejected)
	if NetClient.game_started.is_connected(cb_game_started):
		NetClient.game_started.disconnect(cb_game_started)

static func _restore(prev_engine, prev_is_game_active: bool) -> void:
	Globals.current_game_engine = prev_engine
	Globals.is_game_active = prev_is_game_active
