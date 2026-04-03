# Game scene：菜单/调试控制器
# 负责：菜单按钮、保存/返回主菜单
class_name GameMenuDebugController
extends RefCounted

const ONLINE_FORFEIT_QUIT_TIMEOUT_SEC := 4.0

var _scene = null
var _menu_dialog = null
var _deps: Dictionary = {}
var _online_quit_pending: bool = false
var _online_quit_request_id: String = ""
var _online_quit_ticket: int = 0

func _init(scene, menu_dialog, deps: Dictionary = {}) -> void:
	_scene = scene
	_menu_dialog = menu_dialog
	_deps = deps.duplicate(false)

func dispose() -> void:
	_disconnect_online_quit_signals()
	_online_quit_pending = false
	_online_quit_request_id = ""

func open_menu() -> void:
	GameLog.info("Game", "打开游戏菜单")
	if is_instance_valid(_menu_dialog):
		_menu_dialog.show()

func close_menu() -> void:
	if is_instance_valid(_menu_dialog):
		_menu_dialog.hide()

func resume() -> void:
	GameLog.info("Game", "继续游戏")
	close_menu()

func save_game() -> void:
	GameLog.info("Game", "保存游戏")
	if _scene == null:
		return
	var engine = _scene.game_engine
	if engine == null:
		GameLog.warn("Game", "游戏引擎未初始化，无法保存")
		close_menu()
		return

	var path := "user://savegame.json"
	var save_result = engine.save_to_file(path)
	if not save_result.ok:
		GameLog.error("Game", "保存失败: %s" % save_result.error)
	else:
		GameLog.info("Game", "已保存到: %s" % path)
	close_menu()

func _get_net_client():
	if _deps.has("net_client"):
		return _deps.get("net_client", null)
	return NetClient

func _get_scene_manager():
	if _deps.has("scene_manager"):
		return _deps.get("scene_manager", null)
	return SceneManager

func _get_globals():
	if _deps.has("globals"):
		return _deps.get("globals", null)
	return Globals

static func cleanup_online_state_before_quit(net_client_override = null) -> void:
	var should_reset := false
	if NetContext != null:
		should_reset = int(NetContext.mode) == int(NetContext.Mode.ONLINE_CLIENT)
		if not should_reset and NetContext.has_method("has_online_resume_context"):
			should_reset = bool(NetContext.has_online_resume_context())
	if not should_reset:
		return
	var net_client = net_client_override if net_client_override != null else NetClient
	if net_client != null and net_client.has_method("shutdown"):
		net_client.shutdown(true)
		return
	if NetContext != null and NetContext.has_method("reset"):
		NetContext.reset()

func quit_to_menu() -> void:
	GameLog.info("Game", "返回主菜单")
	if _should_forfeit_online_match_before_quit():
		_begin_online_forfeit_quit_to_menu()
		return
	_finalize_quit_to_menu()

func _should_forfeit_online_match_before_quit() -> bool:
	if _online_quit_pending:
		return false
	if NetContext == null or int(NetContext.mode) != int(NetContext.Mode.ONLINE_CLIENT):
		return false
	if int(NetContext.local_player_id) < 0:
		return false
	var room_state: Dictionary = Dictionary(NetContext.room_state)
	if str(room_state.get("status", "")).strip_edges() != "InGame":
		return false
	var net = _get_net_client()
	if net == null or not net.has_method("is_online_client_connected"):
		return false
	return bool(net.is_online_client_connected())

func _begin_online_forfeit_quit_to_menu() -> void:
	var net = _get_net_client()
	if net == null or not net.has_method("request_forfeit_and_leave_room"):
		GameLog.warn("Game", "联机主动退出缺少 forfeit-and-leave 能力，回退为本地清理")
		_finalize_quit_to_menu()
		return

	_online_quit_pending = true
	_online_quit_request_id = ""
	close_menu()
	_connect_online_quit_signals()
	_show_loading("正在认输并退出对局...")
	if OnlineSessionCoordinator != null and OnlineSessionCoordinator.has_method("request_forfeit_and_leave_room"):
		_online_quit_request_id = str(OnlineSessionCoordinator.request_forfeit_and_leave_room(net))
	else:
		_online_quit_request_id = str(net.request_forfeit_and_leave_room())
	if _online_quit_request_id.is_empty():
		GameLog.warn("Game", "联机主动退出未生成 request_id，回退为本地清理")
		_fail_online_forfeit_quit_to_menu("request_id_empty")
		return

	_online_quit_ticket += 1
	_schedule_online_quit_timeout(_online_quit_ticket)

func _connect_online_quit_signals() -> void:
	var net = _get_net_client()
	if net == null:
		return
	var cb_room_state := Callable(self, "_on_online_quit_room_state_updated")
	var cb_rejected := Callable(self, "_on_online_quit_request_rejected")
	var cb_disconnected := Callable(self, "_on_online_quit_disconnected")
	if not net.room_state_updated.is_connected(cb_room_state):
		net.room_state_updated.connect(cb_room_state)
	if not net.request_rejected.is_connected(cb_rejected):
		net.request_rejected.connect(cb_rejected)
	if not net.disconnected.is_connected(cb_disconnected):
		net.disconnected.connect(cb_disconnected)

func _disconnect_online_quit_signals() -> void:
	var net = _get_net_client()
	if net == null:
		return
	var cb_room_state := Callable(self, "_on_online_quit_room_state_updated")
	var cb_rejected := Callable(self, "_on_online_quit_request_rejected")
	var cb_disconnected := Callable(self, "_on_online_quit_disconnected")
	if net.room_state_updated.is_connected(cb_room_state):
		net.room_state_updated.disconnect(cb_room_state)
	if net.request_rejected.is_connected(cb_rejected):
		net.request_rejected.disconnect(cb_rejected)
	if net.disconnected.is_connected(cb_disconnected):
		net.disconnected.disconnect(cb_disconnected)

func _schedule_online_quit_timeout(ticket: int) -> void:
	if _scene == null or not is_instance_valid(_scene):
		return
	var tree = _scene.get_tree()
	if tree == null or not (tree is SceneTree):
		return
	var timer = (tree as SceneTree).create_timer(ONLINE_FORFEIT_QUIT_TIMEOUT_SEC)
	timer.timeout.connect(Callable(self, "_on_online_quit_timeout").bind(int(ticket)))

func _on_online_quit_timeout(ticket: int) -> void:
	if not _online_quit_pending:
		return
	if int(ticket) != int(_online_quit_ticket):
		return
	GameLog.warn("Game", "联机主动退出等待超时 request_id=%s" % _online_quit_request_id)
	_fail_online_forfeit_quit_to_menu("timeout")

func _on_online_quit_room_state_updated(room_state: Dictionary) -> void:
	if not _online_quit_pending:
		return
	var room_code := str(room_state.get("room_code", "")).strip_edges()
	if not room_code.is_empty():
		return
	_complete_online_forfeit_quit_to_menu()

func _on_online_quit_request_rejected(request_id: String, code: String, message: String) -> void:
	if not _online_quit_pending:
		return
	if str(request_id) != _online_quit_request_id:
		return
	GameLog.warn(
		"Game",
		"联机主动退出被拒绝 request_id=%s code=%s message=%s"
			% [str(request_id), str(code), str(message)]
	)
	_fail_online_forfeit_quit_to_menu(str(code))

func _on_online_quit_disconnected(reason: String) -> void:
	if not _online_quit_pending:
		return
	GameLog.warn("Game", "联机主动退出期间连接中断: %s" % str(reason))
	_fail_online_forfeit_quit_to_menu(str(reason))

func _complete_online_forfeit_quit_to_menu() -> void:
	_online_quit_pending = false
	_online_quit_request_id = ""
	_disconnect_online_quit_signals()
	_finalize_quit_to_menu()

func _fail_online_forfeit_quit_to_menu(reason: String) -> void:
	_online_quit_pending = false
	_online_quit_request_id = ""
	_disconnect_online_quit_signals()
	GameLog.warn("Game", "联机主动退出回退为本地清理: %s" % str(reason))
	_finalize_quit_to_menu()

func _show_loading(message: String) -> void:
	var scene_manager = _get_scene_manager()
	if scene_manager != null and scene_manager.has_method("show_loading"):
		scene_manager.show_loading(str(message))

func _hide_loading() -> void:
	var scene_manager = _get_scene_manager()
	if scene_manager != null and scene_manager.has_method("hide_loading"):
		scene_manager.hide_loading()

func _finalize_quit_to_menu() -> void:
	_disconnect_online_quit_signals()
	_online_quit_pending = false
	_online_quit_request_id = ""
	_hide_loading()
	cleanup_online_state_before_quit(_get_net_client())
	var globals = _get_globals()
	if globals != null and globals.has_method("reset_game_config"):
		globals.reset_game_config()
	var scene_manager = _get_scene_manager()
	if scene_manager != null and scene_manager.has_method("goto_main_menu"):
		scene_manager.goto_main_menu()
