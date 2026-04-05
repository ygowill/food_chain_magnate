# 联机大厅：即使错过 game_started 信号，也应在 InGame + engine 就绪 + 当前房间存在待同步数据时补进 Game。
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
	var prev_pending_archive := Dictionary(NetClient._pending_resync_archive).duplicate(true)
	var prev_pending_manifest := Dictionary(NetClient._pending_resync_snapshot_manifest).duplicate(true)
	var prev_pending_delta := Dictionary(NetClient._pending_resync_delta).duplicate(true)
	var lobby = LobbyScript.new()
	var cb_rejected := Callable(lobby, "_on_request_rejected")
	var cb_game_started := Callable(lobby, "_on_game_started")
	var cb_resync_archive := Callable(lobby, "_on_online_resync_archive_received")

	if not NetClient.request_rejected.is_connected(cb_rejected):
		NetClient.request_rejected.connect(cb_rejected)
	if NetClient.game_started.is_connected(cb_game_started):
		NetClient.game_started.disconnect(cb_game_started)
	if NetClient.resync_archive_received.is_connected(cb_resync_archive):
		NetClient.resync_archive_received.disconnect(cb_resync_archive)

	lobby.call("_bind_net_signals")
	if not NetClient.game_started.is_connected(cb_game_started):
		_cleanup_lobby_connections(lobby)
		_restore(
			prev_engine,
			prev_is_game_active,
			prev_pending_archive,
			prev_pending_manifest,
			prev_pending_delta
		)
		return Result.failure("request_rejected 已绑定时，_bind_net_signals 仍应补绑 game_started")
	if not NetClient.resync_archive_received.is_connected(cb_resync_archive):
		_cleanup_lobby_connections(lobby)
		_restore(
			prev_engine,
			prev_is_game_active,
			prev_pending_archive,
			prev_pending_manifest,
			prev_pending_delta
		)
		return Result.failure("request_rejected 已绑定时，_bind_net_signals 仍应补绑 resync_archive_received")

	Globals.current_game_engine = null
	Globals.is_game_active = false
	NetClient._pending_resync_archive = {}
	NetClient._pending_resync_snapshot_manifest = {}
	NetClient._pending_resync_delta = {}
	if bool(lobby.call("_should_enter_online_game_scene_from_room_state", {"status": "InGame", "room_code": "ROOM01"})):
		_cleanup_lobby_connections(lobby)
		_restore(
			prev_engine,
			prev_is_game_active,
			prev_pending_archive,
			prev_pending_manifest,
			prev_pending_delta
		)
		return Result.failure("没有 engine 时不应触发大厅补进 Game")

	var engine = GameEngineClass.new()
	var init_r: Result = engine.initialize(2, 12345, [], GameDefaultsClass.DEFAULT_MODULES_V2_BASE_DIR, [], [-1, -1])
	if not init_r.ok:
		_cleanup_lobby_connections(lobby)
		_restore(
			prev_engine,
			prev_is_game_active,
			prev_pending_archive,
			prev_pending_manifest,
			prev_pending_delta
		)
		return Result.failure("初始化测试 engine 失败: %s" % init_r.error)
	Globals.set_current_game_engine(engine)

	if bool(lobby.call("_should_enter_online_game_scene_from_room_state", {"status": "InGame", "room_code": "ROOM01"})):
		_cleanup_lobby_connections(lobby)
		_restore(
			prev_engine,
			prev_is_game_active,
			prev_pending_archive,
			prev_pending_manifest,
			prev_pending_delta
		)
		return Result.failure("只有 engine、没有待同步数据时不应触发大厅补进 Game")

	NetClient._pending_resync_snapshot_manifest = {"room_code": "ROOM99"}
	if bool(lobby.call("_should_enter_online_game_scene_from_room_state", {"status": "InGame", "room_code": "ROOM01"})):
		_cleanup_lobby_connections(lobby)
		_restore(
			prev_engine,
			prev_is_game_active,
			prev_pending_archive,
			prev_pending_manifest,
			prev_pending_delta
		)
		return Result.failure("其他房间的待同步数据不应触发大厅补进 Game")

	NetClient._pending_resync_snapshot_manifest = {"room_code": "ROOM01"}
	if not bool(lobby.call("_should_enter_online_game_scene_from_room_state", {"status": "InGame", "room_code": "ROOM01"})):
		_cleanup_lobby_connections(lobby)
		_restore(
			prev_engine,
			prev_is_game_active,
			prev_pending_archive,
			prev_pending_manifest,
			prev_pending_delta
		)
		return Result.failure("InGame 且 engine 已就绪并存在当前房间待同步数据时应允许大厅补进 Game")

	lobby.set("_enter_game_transition_requested", true)
	if bool(lobby.call("_should_enter_online_game_scene_from_room_state", {"status": "InGame", "room_code": "ROOM01"})):
		_cleanup_lobby_connections(lobby)
		_restore(
			prev_engine,
			prev_is_game_active,
			prev_pending_archive,
			prev_pending_manifest,
			prev_pending_delta
		)
		return Result.failure("进入 Game 已请求后不应重复触发大厅补进")
	lobby.set("_enter_game_transition_requested", false)

	if bool(lobby.call("_should_enter_online_game_scene_from_room_state", {"status": "Lobby", "room_code": "ROOM01"})):
		_cleanup_lobby_connections(lobby)
		_restore(
			prev_engine,
			prev_is_game_active,
			prev_pending_archive,
			prev_pending_manifest,
			prev_pending_delta
		)
		return Result.failure("非 InGame 状态不应触发大厅补进 Game")

	_cleanup_lobby_connections(lobby)
	_restore(
		prev_engine,
		prev_is_game_active,
		prev_pending_archive,
		prev_pending_manifest,
		prev_pending_delta
	)
	return Result.success()

static func _cleanup_lobby_connections(lobby) -> void:
	if NetClient == null:
		return
	if lobby == null:
		return
	var cb_connected := Callable(lobby, "_on_net_connected")
	var cb_disconnected := Callable(lobby, "_on_net_disconnected")
	var cb_room_state_updated := Callable(lobby, "_on_room_state_updated")
	var cb_room_list_updated := Callable(lobby, "_on_room_list_updated")
	var cb_rejected := Callable(lobby, "_on_request_rejected")
	var cb_game_started := Callable(lobby, "_on_game_started")
	var cb_resync_archive := Callable(lobby, "_on_online_resync_archive_received")
	if NetClient.connected.is_connected(cb_connected):
		NetClient.connected.disconnect(cb_connected)
	if NetClient.disconnected.is_connected(cb_disconnected):
		NetClient.disconnected.disconnect(cb_disconnected)
	if NetClient.room_state_updated.is_connected(cb_room_state_updated):
		NetClient.room_state_updated.disconnect(cb_room_state_updated)
	if NetClient.room_list_updated.is_connected(cb_room_list_updated):
		NetClient.room_list_updated.disconnect(cb_room_list_updated)
	if NetClient.request_rejected.is_connected(cb_rejected):
		NetClient.request_rejected.disconnect(cb_rejected)
	if NetClient.game_started.is_connected(cb_game_started):
		NetClient.game_started.disconnect(cb_game_started)
	if NetClient.resync_archive_received.is_connected(cb_resync_archive):
		NetClient.resync_archive_received.disconnect(cb_resync_archive)

static func _restore(
	prev_engine,
	prev_is_game_active: bool,
	prev_pending_archive: Dictionary,
	prev_pending_manifest: Dictionary,
	prev_pending_delta: Dictionary
) -> void:
	Globals.current_game_engine = prev_engine
	Globals.is_game_active = prev_is_game_active
	NetClient._pending_resync_archive = prev_pending_archive.duplicate(true)
	NetClient._pending_resync_snapshot_manifest = prev_pending_manifest.duplicate(true)
	NetClient._pending_resync_delta = prev_pending_delta.duplicate(true)
