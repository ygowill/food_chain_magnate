# Game scene：联机 Resync/Rewind 控制器
# 负责：联机客户端命令回放、ResyncArchive 应用、回退到回合开始的回灌与超时兜底。
class_name GameOnlineResyncController
extends RefCounted

const ModuleUiMetadataBootstrapClass = preload("res://gameplay/module_ui_metadata_bootstrap.gd")

var _host: Node = null
var _game_log_panel: Control = null

var _get_game_engine: Callable = Callable()
var _apply_live_log_timeline_from_engine: Callable = Callable()
var _update_ui: Callable = Callable()
var _reset_timeline_state_after_resync: Callable = Callable()
var _show_confirm: Callable = Callable()
var _goto_online_lobby: Callable = Callable()

var _resync_in_progress: bool = false
var _pending_cmds: Array[Dictionary] = [] # [{cmd_dict, state_hash}]
var _rewind_request_id: String = ""
var _resync_ticket: int = 0
var _action_id_by_request_id: Dictionary = {} # request_id -> action_id
var _action_request_ids: Array[String] = []

func _init(
	host: Node,
	game_log_panel: Control,
	get_game_engine: Callable,
	apply_live_log_timeline_from_engine: Callable,
	update_ui: Callable,
	reset_timeline_state_after_resync: Callable,
	show_confirm: Callable,
	goto_online_lobby: Callable
) -> void:
	_host = host
	_game_log_panel = game_log_panel
	_get_game_engine = get_game_engine
	_apply_live_log_timeline_from_engine = apply_live_log_timeline_from_engine
	_update_ui = update_ui
	_reset_timeline_state_after_resync = reset_timeline_state_after_resync
	_show_confirm = show_confirm
	_goto_online_lobby = goto_online_lobby

func dispose() -> void:
	_disconnect_netclient_signals()
	_pending_cmds.clear()
	_action_id_by_request_id.clear()
	_action_request_ids.clear()

func is_resync_in_progress() -> bool:
	return _resync_in_progress

func initialize() -> void:
	_setup_online_client_bindings()

func try_send_online_action(command: Command) -> Result:
	if _resync_in_progress:
		return Result.failure("联机同步中，请稍后")
	if NetClient == null or not NetClient.is_online_client_connected():
		return Result.failure("未连接到服务器")
	if NetContext.local_player_id < 0:
		return Result.failure("联机身份未就绪（local_player_id 未设置）")
	if command == null:
		return Result.failure("command 为空")
	var action_id := str(command.action_id).strip_edges()
	if action_id.is_empty():
		return Result.failure("action_id 为空")
	# 联机模式：禁止代操（客户端侧兜底；服务器仍会根据 peer_id 强制映射 actor_id）
	if command.actor == -1:
		return Result.failure("联机模式下不允许发送系统命令")
	if command.actor != NetContext.local_player_id:
		return Result.failure("联机模式下只能操作自己（local_player_id=%d）" % int(NetContext.local_player_id))
	var params: Dictionary = {}
	if command.params is Dictionary:
		params = Dictionary(command.params)
	var request_id := NetClient.request_action(action_id, params)
	_action_id_by_request_id[str(request_id)] = action_id
	_action_request_ids.append(str(request_id))
	if _action_request_ids.size() > 200:
		var old_id := str(_action_request_ids.pop_front())
		_action_id_by_request_id.erase(old_id)
	GameLog.info("Game", "联机发送 ActionRequest: %s request_id=%s" % [action_id, request_id])
	return Result.success({"request_id": request_id})

func _take_action_id_for_request(request_id: String) -> String:
	var rid := str(request_id).strip_edges()
	if rid.is_empty():
		return ""
	var action_id := str(_action_id_by_request_id.get(rid, "")).strip_edges()
	if not action_id.is_empty():
		_action_id_by_request_id.erase(rid)
	return action_id

func _should_ignore_request_rejected(action_id: String, code: String, message: String) -> bool:
	if str(code).strip_edges() != "action_failed":
		return false
	if str(action_id).strip_edges() != "confirm_dinnertime":
		return false
	var msg := str(message).strip_edges()
	if msg == "当前不在晚餐阶段":
		return true
	if msg == "当前无需确认晚餐结算":
		return true
	if msg.begins_with("玩家") and msg.find("无需确认晚餐结算") != -1:
		return true
	return false

func begin_rewind_to_turn_start_request() -> bool:
	if NetContext == null or NetContext.mode != NetContext.Mode.ONLINE_CLIENT:
		return false
	if _resync_in_progress:
		return false
	if NetClient == null or not NetClient.is_online_client_connected():
		GameLog.warn("Game", "联机模式下回退失败：未连接到服务器")
		return false
	_resync_in_progress = true
	var request_id := NetClient.request_rewind_to_turn_start()
	_rewind_request_id = str(request_id)
	GameLog.warn("Game", "联机请求回退到回合开始 request_id=%s" % str(request_id))
	_resync_ticket += 1
	if _update_ui.is_valid():
		_update_ui.call()
	_online_schedule_resync_timeout(_resync_ticket, _rewind_request_id)
	return true

func _get_engine():
	if not _get_game_engine.is_valid():
		return null
	return _get_game_engine.call()

func _setup_online_client_bindings() -> void:
	if NetContext == null or NetContext.mode != NetContext.Mode.ONLINE_CLIENT:
		return
	if NetClient == null:
		return

	var cb_applied := Callable(self, "_on_online_command_applied")
	var cb_archive := Callable(self, "_on_online_resync_archive_received")
	var cb_rejected := Callable(self, "_on_online_request_rejected")
	var cb_disconnected := Callable(self, "_on_online_disconnected")
	if not NetClient.command_applied.is_connected(cb_applied):
		NetClient.command_applied.connect(cb_applied)
	if not NetClient.resync_archive_received.is_connected(cb_archive):
		NetClient.resync_archive_received.connect(cb_archive)
	if not NetClient.request_rejected.is_connected(cb_rejected):
		NetClient.request_rejected.connect(cb_rejected)
	if not NetClient.disconnected.is_connected(cb_disconnected):
		NetClient.disconnected.connect(cb_disconnected)

	var pending = NetClient.take_pending_resync_archive()
	if pending is Dictionary and not pending.is_empty():
		_resync_in_progress = true
		_on_online_resync_archive_received(Dictionary(pending))

func _disconnect_netclient_signals() -> void:
	if NetClient == null:
		return
	var cb_applied := Callable(self, "_on_online_command_applied")
	var cb_archive := Callable(self, "_on_online_resync_archive_received")
	var cb_rejected := Callable(self, "_on_online_request_rejected")
	var cb_disconnected := Callable(self, "_on_online_disconnected")
	if NetClient.command_applied.is_connected(cb_applied):
		NetClient.command_applied.disconnect(cb_applied)
	if NetClient.resync_archive_received.is_connected(cb_archive):
		NetClient.resync_archive_received.disconnect(cb_archive)
	if NetClient.request_rejected.is_connected(cb_rejected):
		NetClient.request_rejected.disconnect(cb_rejected)
	if NetClient.disconnected.is_connected(cb_disconnected):
		NetClient.disconnected.disconnect(cb_disconnected)

func _on_online_command_applied(cmd_dict: Dictionary, state_hash: String) -> void:
	var engine = _get_engine()
	if engine == null:
		return
	if _resync_in_progress:
		_pending_cmds.append({
			"cmd_dict": cmd_dict.duplicate(true),
			"state_hash": str(state_hash),
		})
		return
	var parsed: Result = Command.from_dict(cmd_dict)
	if not parsed.ok:
		GameLog.error("Game", "联机 CommandApplied 解析失败: %s" % parsed.error)
		return
	var cmd: Command = parsed.value
	if int(cmd.index) != int(engine.command_history.size()):
		_request_online_resync("command_index_mismatch")
		_pending_cmds.append({
			"cmd_dict": cmd_dict.duplicate(true),
			"state_hash": str(state_hash),
		})
		return
	var r: Result = engine.execute_command(cmd, true)
	if not r.ok:
		GameLog.error("Game", "联机回放命令失败: %s" % r.error)
		return
	if not state_hash.is_empty():
		var state = engine.get_state()
		if state != null and state.has_method("compute_hash"):
			var local_hash := str(state.compute_hash())
			if local_hash != state_hash:
				GameLog.warn("Game", "联机 state_hash 不一致: local=%s server=%s" % [local_hash, state_hash])
				_request_online_resync("state_hash_mismatch")

	if is_instance_valid(_game_log_panel) and _game_log_panel.visible:
		if _apply_live_log_timeline_from_engine.is_valid():
			_apply_live_log_timeline_from_engine.call()
	if _update_ui.is_valid():
		_update_ui.call()

func _on_online_resync_archive_received(archive: Dictionary) -> void:
	var engine = _get_engine()
	if engine == null:
		return
	# 联机回退：server 通过 ResyncArchive 通道下发“元数据”（避免发送大 archive 导致 WebSocket buffer 溢出）。
	if archive.has("_rewind_to_turn_start"):
		var meta_val = archive.get("_rewind_to_turn_start", null)
		if meta_val is Dictionary:
			_on_online_rewind_to_turn_start_meta(Dictionary(meta_val))
			return
	_resync_in_progress = true
	var r: Result = engine.load_from_archive(archive)
	if not r.ok:
		GameLog.error("Game", "联机 ResyncArchive 加载失败: %s" % r.error)
		_resync_in_progress = false
		_rewind_request_id = ""
		_pending_cmds.clear()
		if _update_ui.is_valid():
			_update_ui.call()
		if not OS.has_feature("headless"):
			if _show_confirm.is_valid():
				_show_confirm.call("联机同步失败", r.error, Callable(), Callable(), "确定", "关闭")
		return

	var ui_metadata_apply := ModuleUiMetadataBootstrapClass.apply(engine)
	if not ui_metadata_apply.ok:
		GameLog.error("Game", "联机 ResyncArchive UI metadata 装配失败: %s" % ui_metadata_apply.error)

	GameLog.warn("Game", "联机 ResyncArchive 加载完成（命令数=%d）" % int(engine.command_history.size()))
	_resync_in_progress = false
	_rewind_request_id = ""
	if _reset_timeline_state_after_resync.is_valid():
		_reset_timeline_state_after_resync.call()
	if is_instance_valid(_game_log_panel) and _game_log_panel.visible:
		if _apply_live_log_timeline_from_engine.is_valid():
			_apply_live_log_timeline_from_engine.call()
	if _update_ui.is_valid():
		_update_ui.call()

	_flush_online_pending_commands_after_resync()

func _on_online_rewind_to_turn_start_meta(payload: Dictionary) -> void:
	var engine = _get_engine()
	if engine == null:
		return
	if NetContext == null or NetContext.mode != NetContext.Mode.ONLINE_CLIENT:
		return
	if NetClient == null or not NetClient.is_online_client_connected():
		return

	var request_id := str(payload.get("request_id", ""))
	var target_index := int(payload.get("target_index", -999))
	var history_size := int(payload.get("history_size", -1))
	var expected_hash := str(payload.get("state_hash", ""))
	var noop := bool(payload.get("noop", false))

	if not request_id.is_empty() and request_id == _rewind_request_id:
		_rewind_request_id = ""
		_resync_ticket += 1

	_resync_in_progress = true

	if noop:
		_resync_in_progress = false
		if _reset_timeline_state_after_resync.is_valid():
			_reset_timeline_state_after_resync.call()
		if is_instance_valid(_game_log_panel) and _game_log_panel.visible:
			if _apply_live_log_timeline_from_engine.is_valid():
				_apply_live_log_timeline_from_engine.call()
		if _update_ui.is_valid():
			_update_ui.call()
		_flush_online_pending_commands_after_resync()
		return

	# 时间线被 server 回退并截断：丢弃本地等待队列中的旧 CommandApplied（可能属于被撤销的未来）。
	_pending_cmds.clear()

	if target_index < -1:
		GameLog.warn("Game", "联机回退应用失败：target_index 无效: %d" % target_index)
		_resync_in_progress = false
		if _update_ui.is_valid():
			_update_ui.call()
		return
	if target_index >= engine.command_history.size():
		GameLog.warn(
			"Game",
			"联机回退应用失败：本地历史不足（local=%d target=%d），触发 resync"
				% [engine.command_history.size(), target_index]
		)
		_rewind_request_id = ""
		NetClient.request_resync()
		if _update_ui.is_valid():
			_update_ui.call()
		return

	var rewind_r: Result = engine.rewind_to_command(target_index)
	if not rewind_r.ok:
		GameLog.error("Game", "联机回退应用失败：%s（触发 resync）" % rewind_r.error)
		_rewind_request_id = ""
		NetClient.request_resync()
		if _update_ui.is_valid():
			_update_ui.call()
		return

	engine.truncate_future_history()

	if history_size >= 0 and engine.command_history.size() != history_size:
		GameLog.warn(
			"Game",
			"联机回退后历史长度不一致（local=%d server=%d），触发 resync"
				% [engine.command_history.size(), history_size]
		)
		NetClient.request_resync()
		if _update_ui.is_valid():
			_update_ui.call()
		return

	if not expected_hash.is_empty():
		var state = engine.get_state()
		if state != null and state.has_method("compute_hash"):
			var local_hash := str(state.compute_hash())
			if local_hash != expected_hash:
				GameLog.warn(
					"Game",
					"联机回退后 state_hash 不一致（local=%s server=%s），触发 resync"
						% [local_hash, expected_hash]
				)
				NetClient.request_resync()
				if _update_ui.is_valid():
					_update_ui.call()
				return

	_resync_in_progress = false
	_rewind_request_id = ""
	if _reset_timeline_state_after_resync.is_valid():
		_reset_timeline_state_after_resync.call()
	if is_instance_valid(_game_log_panel) and _game_log_panel.visible:
		if _apply_live_log_timeline_from_engine.is_valid():
			_apply_live_log_timeline_from_engine.call()
	if _update_ui.is_valid():
		_update_ui.call()
	_flush_online_pending_commands_after_resync()

func _online_schedule_resync_timeout(ticket: int, request_id: String) -> void:
	if ticket <= 0:
		return
	if request_id.is_empty():
		return
	if _host == null or not is_instance_valid(_host):
		return
	var t := _host.get_tree().create_timer(2.0)
	if t == null:
		return
	t.timeout.connect(Callable(self, "_on_online_resync_timeout").bind(ticket, request_id))

func _on_online_resync_timeout(ticket: int, request_id: String) -> void:
	if ticket != _resync_ticket:
		return
	if not _resync_in_progress:
		return
	if request_id.is_empty() or _rewind_request_id != request_id:
		return
	if NetContext == null or NetContext.mode != NetContext.Mode.ONLINE_CLIENT:
		return
	if NetClient == null or not NetClient.is_online_client_connected():
		return

	# 若回退请求迟迟未回灌（例如网络抖动/包丢失），主动发起 resync 兜底，避免 UI 看起来“没反应”。
	GameLog.warn("Game", "联机回退未收到回灌，触发 resync request_id=%s" % str(request_id))
	NetClient.request_resync()

func _flush_online_pending_commands_after_resync() -> void:
	var engine = _get_engine()
	if engine == null:
		_pending_cmds.clear()
		return
	if _pending_cmds.is_empty():
		return

	var queue := _pending_cmds
	_pending_cmds = []

	queue.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_cmd: Dictionary = Dictionary(a.get("cmd_dict", {}))
		var b_cmd: Dictionary = Dictionary(b.get("cmd_dict", {}))
		return int(a_cmd.get("index", -1)) < int(b_cmd.get("index", -1))
	)

	var safety := 0
	while not queue.is_empty() and safety < 1000:
		safety += 1
		var progressed := false

		for i in range(queue.size()):
			var item: Dictionary = queue[i]
			var item_cmd_dict: Dictionary = Dictionary(item.get("cmd_dict", {}))
			var item_hash := str(item.get("state_hash", ""))
			var parsed: Result = Command.from_dict(item_cmd_dict)
			if not parsed.ok:
				GameLog.error("Game", "联机待处理命令解析失败: %s" % parsed.error)
				queue.remove_at(i)
				progressed = true
				break
			var cmd: Command = parsed.value
			var expected_index := int(engine.command_history.size())
			if int(cmd.index) < expected_index:
				queue.remove_at(i)
				progressed = true
				break
			if int(cmd.index) > expected_index:
				continue

			var r: Result = engine.execute_command(cmd, true)
			if not r.ok:
				GameLog.error("Game", "联机回放待处理命令失败: %s" % r.error)
				queue.remove_at(i)
				progressed = true
				break
			if not item_hash.is_empty():
				var state = engine.get_state()
				if state != null and state.has_method("compute_hash"):
					var local_hash := str(state.compute_hash())
					if local_hash != item_hash:
						GameLog.warn("Game", "联机待处理 state_hash 不一致: local=%s server=%s" % [local_hash, item_hash])
						queue.remove_at(i)
						_request_online_resync("pending_state_hash_mismatch")
						return

			queue.remove_at(i)
			progressed = true
			break

		if not progressed:
			_request_online_resync("pending_command_gap")
			return

	if not queue.is_empty():
		_request_online_resync("pending_queue_overflow")
		return

	if is_instance_valid(_game_log_panel) and _game_log_panel.visible:
		if _apply_live_log_timeline_from_engine.is_valid():
			_apply_live_log_timeline_from_engine.call()
	if _update_ui.is_valid():
		_update_ui.call()

func _request_online_resync(reason: String) -> void:
	if NetContext == null or NetContext.mode != NetContext.Mode.ONLINE_CLIENT:
		return
	if NetClient == null or not NetClient.is_online_client_connected():
		return
	if _resync_in_progress:
		return
	_resync_in_progress = true
	_rewind_request_id = ""
	GameLog.warn("Game", "联机触发 resync: %s" % str(reason))
	NetClient.request_resync()

func _on_online_request_rejected(request_id: String, code: String, message: String) -> void:
	GameLog.warn("Game", "联机请求被拒绝 request_id=%s: %s %s" % [str(request_id), code, message])
	var action_id := _take_action_id_for_request(request_id)
	if _resync_in_progress and not _rewind_request_id.is_empty() and str(request_id) == _rewind_request_id:
		# 避免“回退请求失败但仍卡在同步中”，导致 ActionPanel 永久禁用与状态不一致。
		_resync_in_progress = false
		_rewind_request_id = ""
		_flush_online_pending_commands_after_resync()
		if _update_ui.is_valid():
			_update_ui.call()
	if OS.has_feature("headless"):
		return
	if _should_ignore_request_rejected(action_id, code, message):
		return
	if _show_confirm.is_valid():
		_show_confirm.call("联机请求失败", "%s\n%s" % [code, message], Callable(), Callable(), "确定", "关闭")

func _on_online_disconnected(reason: String) -> void:
	if OS.has_feature("headless"):
		return
	GameLog.warn("Game", "联机断开: %s" % reason)
	if _show_confirm.is_valid():
		_show_confirm.call("联机已断开", "原因：%s\n将返回联机大厅。" % reason, Callable(), Callable(), "确定", "关闭")
	if _host == null or not is_instance_valid(_host):
		return
	await _host.get_tree().process_frame
	if _host == null or not is_instance_valid(_host):
		return
	if _goto_online_lobby.is_valid():
		_goto_online_lobby.call()
