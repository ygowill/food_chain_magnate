# Game scene：联机 Resync/Rewind 控制器
# 负责：联机客户端命令回放、ResyncArchive 应用、回退元数据处理与超时兜底。
class_name GameOnlineResyncController
extends RefCounted

const ModuleUiMetadataBootstrapClass = preload("res://gameplay/module_ui_metadata_bootstrap.gd")
const OnlineResumePointValidatorClass = preload("res://core/engine/game_engine/online_resume_point_validator.gd")
const OnlinePerfTraceClass = preload("res://core/debug/online_perf_trace.gd")
const RECONNECT_MAX_ATTEMPTS := 6
const RECONNECT_CONNECT_TIMEOUT_SEC := 3.0
const RECONNECT_RESTORE_TIMEOUT_SEC := 6.0
const RECONNECT_RETRY_DELAY_SEC := 1.0

var _host: Node = null
var _game_log_panel: Control = null

var _get_game_engine: Callable = Callable()
var _apply_live_log_timeline_from_engine: Callable = Callable()
var _request_live_log_timeline_refresh: Callable = Callable()
var _update_ui: Callable = Callable()
var _reset_timeline_state_after_resync: Callable = Callable()
var _show_confirm: Callable = Callable()
var _goto_online_lobby: Callable = Callable()
var _show_loading: Callable = Callable()
var _hide_loading: Callable = Callable()
var _ensure_platform_session: Callable = Callable()
var _resume_room_request: Callable = Callable()
var _connect_to_server: Callable = Callable()
var _shutdown_net: Callable = Callable()
var _request_resync: Callable = Callable()

var _resync_in_progress: bool = false
var _pending_cmds: Array[Dictionary] = [] # [{cmd_dict, state_hash}]
var _rollback_request_id: String = ""
var _resync_request_id: String = ""
var _resync_ticket: int = 0
var _action_id_by_request_id: Dictionary = {} # request_id -> action_id
var _action_request_ids: Array[String] = []
var _reconnect_flow_active: bool = false
var _reconnect_ticket: int = 0
var _reconnect_transport_connected: bool = false
var _reconnect_restore_completed: bool = false
var _reconnect_attempt_failed: bool = false
var _reconnect_attempt_failure_reason: String = ""
var _active_rollback_proposal_id: String = ""
var _handled_rollback_proposal_ids: Dictionary = {}

func _init(
	host: Node,
	game_log_panel: Control,
	get_game_engine: Callable,
	apply_live_log_timeline_from_engine: Callable,
	request_live_log_timeline_refresh: Callable,
	update_ui: Callable,
	reset_timeline_state_after_resync: Callable,
	show_confirm: Callable,
	goto_online_lobby: Callable,
	show_loading: Callable,
	hide_loading: Callable,
	resume_room_request: Callable,
	connect_to_server: Callable,
	shutdown_net: Callable,
	request_resync: Callable,
	ensure_platform_session: Callable = Callable()
) -> void:
	_host = host
	_game_log_panel = game_log_panel
	_get_game_engine = get_game_engine
	_apply_live_log_timeline_from_engine = apply_live_log_timeline_from_engine
	_request_live_log_timeline_refresh = request_live_log_timeline_refresh
	_update_ui = update_ui
	_reset_timeline_state_after_resync = reset_timeline_state_after_resync
	_show_confirm = show_confirm
	_goto_online_lobby = goto_online_lobby
	_show_loading = show_loading
	_hide_loading = hide_loading
	_ensure_platform_session = ensure_platform_session
	_resume_room_request = resume_room_request
	_connect_to_server = connect_to_server
	_shutdown_net = shutdown_net
	_request_resync = request_resync

func dispose() -> void:
	_disconnect_netclient_signals()
	_pending_cmds.clear()
	_action_id_by_request_id.clear()
	_action_request_ids.clear()
	_resync_request_id = ""
	_request_live_log_timeline_refresh = Callable()
	_active_rollback_proposal_id = ""
	_handled_rollback_proposal_ids.clear()

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
	var aid := str(action_id).strip_edges()
	if aid != "confirm_dinnertime" and aid != "confirm_marketing":
		return false
	var msg := str(message).strip_edges()
	if msg == "当前不在晚餐阶段" or msg == "当前不在营销阶段":
		return true
	if msg == "当前无需确认晚餐结算" or msg == "当前无需确认营销结算":
		return true
	if msg.begins_with("玩家") and msg.find("无需确认晚餐结算") != -1:
		return true
	if msg.begins_with("玩家") and msg.find("无需确认营销结算") != -1:
		return true
	return false

func _begin_full_resync_request(reason: String, force: bool = false) -> bool:
	if NetContext == null or NetContext.mode != NetContext.Mode.ONLINE_CLIENT:
		return false
	if NetClient == null or not NetClient.is_online_client_connected():
		return false
	if _resync_in_progress and not force:
		return false
	_resync_in_progress = true
	_rollback_request_id = ""
	var request_id := ""
	if _request_resync.is_valid():
		var request_result = _request_resync.call(bool(force))
		request_id = str(request_result).strip_edges() if request_result != null else ""
	else:
		request_id = str(NetClient.request_resync(bool(force))).strip_edges()
	_resync_request_id = request_id
	GameLog.warn(
		"Game",
		"联机触发 resync: %s request_id=%s force_snapshot=%s"
			% [str(reason), request_id if not request_id.is_empty() else "-", str(bool(force))]
	)
	return true

func _is_matching_resync_rejection(request_id: String, code: String) -> bool:
	var rid := str(request_id).strip_edges()
	if not _resync_request_id.is_empty():
		return rid == _resync_request_id
	if not rid.is_empty():
		return false
	var c := str(code).strip_edges()
	return c == "resync_failed" \
		or c == "resync_archive_too_large" \
		or c == "resync_rate_limited" \
		or c == "not_in_room" \
		or c == "not_in_game" \
		or c == "engine_missing"

func begin_rewind_to_turn_start_request() -> bool:
	if NetContext == null or NetContext.mode != NetContext.Mode.ONLINE_CLIENT:
		return false
	if _resync_in_progress:
		return false
	if NetClient == null or not NetClient.is_online_client_connected():
		GameLog.warn("Game", "联机模式下回退失败：未连接到服务器")
		return false
	_resync_in_progress = true
	_resync_request_id = ""
	var request_id := NetClient.request_rewind_to_turn_start()
	_rollback_request_id = str(request_id)
	GameLog.warn("Game", "联机请求回退到回合开始 request_id=%s" % str(request_id))
	_resync_ticket += 1
	if _update_ui.is_valid():
		_update_ui.call()
	_online_schedule_resync_timeout(_resync_ticket, _rollback_request_id)
	return true

func begin_rollback_last_command_request() -> bool:
	if NetContext == null or NetContext.mode != NetContext.Mode.ONLINE_CLIENT:
		return false
	if _resync_in_progress:
		return false
	if NetClient == null or not NetClient.is_online_client_connected():
		GameLog.warn("Game", "联机模式下回退上一步失败：未连接到服务器")
		return false
	_resync_in_progress = true
	_resync_request_id = ""
	var request_id := NetClient.request_rollback_last_command()
	_rollback_request_id = str(request_id)
	GameLog.warn("Game", "联机请求回退上一步 request_id=%s" % str(request_id))
	_resync_ticket += 1
	if _update_ui.is_valid():
		_update_ui.call()
	_online_schedule_resync_timeout(_resync_ticket, _rollback_request_id)
	return true

func begin_rollback_proposal_request(target_index: int) -> bool:
	if NetContext == null or NetContext.mode != NetContext.Mode.ONLINE_CLIENT:
		return false
	if _resync_in_progress:
		return false
	if NetClient == null or not NetClient.is_online_client_connected():
		GameLog.warn("Game", "联机模式下提议回滚失败：未连接到服务器")
		return false
	var request_id := NetClient.request_rollback_proposal(int(target_index), "proposal_rollback")
	GameLog.warn("Game", "联机请求提议回滚 request_id=%s target=%d" % [str(request_id), int(target_index)])
	return true

func _get_engine():
	if not _get_game_engine.is_valid():
		return null
	return _get_game_engine.call()

func _load_archive_for_online_client(engine, archive: Dictionary) -> Result:
	if engine == null:
		return Result.failure("load archive failed: engine 为空")
	if NetClient != null and NetClient.has_method("load_archive_for_online_client"):
		return NetClient.load_archive_for_online_client(engine, archive)
	return engine.load_from_archive(archive)

func _setup_online_client_bindings() -> void:
	if NetContext == null or NetContext.mode != NetContext.Mode.ONLINE_CLIENT:
		return
	if NetClient == null:
		return

	var cb_applied := Callable(self, "_on_online_command_applied")
	var cb_archive := Callable(self, "_on_online_resync_archive_received")
	var cb_rollback_meta := Callable(self, "_on_online_rollback_meta")
	var cb_room_state := Callable(self, "_on_online_room_state_updated_for_rollback_proposal")
	var cb_delta_applied := Callable(self, "_on_online_resync_delta_applied")
	var cb_delta_failed := Callable(self, "_on_online_resync_delta_failed")
	var cb_rejected := Callable(self, "_on_online_request_rejected")
	var cb_connected := Callable(self, "_on_online_connected")
	var cb_disconnected := Callable(self, "_on_online_disconnected")
	if not NetClient.command_applied.is_connected(cb_applied):
		NetClient.command_applied.connect(cb_applied)
	if not NetClient.resync_archive_received.is_connected(cb_archive):
		NetClient.resync_archive_received.connect(cb_archive)
	if not NetClient.rollback_meta_received.is_connected(cb_rollback_meta):
		NetClient.rollback_meta_received.connect(cb_rollback_meta)
	if not NetClient.room_state_updated.is_connected(cb_room_state):
		NetClient.room_state_updated.connect(cb_room_state)
	if not NetClient.resync_delta_applied.is_connected(cb_delta_applied):
		NetClient.resync_delta_applied.connect(cb_delta_applied)
	if not NetClient.resync_delta_failed.is_connected(cb_delta_failed):
		NetClient.resync_delta_failed.connect(cb_delta_failed)
	if not NetClient.request_rejected.is_connected(cb_rejected):
		NetClient.request_rejected.connect(cb_rejected)
	if not NetClient.connected.is_connected(cb_connected):
		NetClient.connected.connect(cb_connected)
	if not NetClient.disconnected.is_connected(cb_disconnected):
		NetClient.disconnected.connect(cb_disconnected)

	var pending_archive = NetClient.take_pending_resync_archive()
	var pending_rollback_meta = NetClient.take_pending_rollback_meta()
	if pending_archive is Dictionary and not pending_archive.is_empty():
		_resync_in_progress = true
		_on_online_resync_archive_received(Dictionary(pending_archive))
	elif pending_rollback_meta is Dictionary and not pending_rollback_meta.is_empty():
		_resync_in_progress = true
		_on_online_rollback_meta(Dictionary(pending_rollback_meta))
	_on_online_room_state_updated_for_rollback_proposal(NetContext.room_state)

func _disconnect_netclient_signals() -> void:
	if NetClient == null:
		return
	var cb_applied := Callable(self, "_on_online_command_applied")
	var cb_archive := Callable(self, "_on_online_resync_archive_received")
	var cb_rollback_meta := Callable(self, "_on_online_rollback_meta")
	var cb_room_state := Callable(self, "_on_online_room_state_updated_for_rollback_proposal")
	var cb_delta_applied := Callable(self, "_on_online_resync_delta_applied")
	var cb_delta_failed := Callable(self, "_on_online_resync_delta_failed")
	var cb_rejected := Callable(self, "_on_online_request_rejected")
	var cb_connected := Callable(self, "_on_online_connected")
	var cb_disconnected := Callable(self, "_on_online_disconnected")
	if NetClient.command_applied.is_connected(cb_applied):
		NetClient.command_applied.disconnect(cb_applied)
	if NetClient.resync_archive_received.is_connected(cb_archive):
		NetClient.resync_archive_received.disconnect(cb_archive)
	if NetClient.rollback_meta_received.is_connected(cb_rollback_meta):
		NetClient.rollback_meta_received.disconnect(cb_rollback_meta)
	if NetClient.room_state_updated.is_connected(cb_room_state):
		NetClient.room_state_updated.disconnect(cb_room_state)
	if NetClient.resync_delta_applied.is_connected(cb_delta_applied):
		NetClient.resync_delta_applied.disconnect(cb_delta_applied)
	if NetClient.resync_delta_failed.is_connected(cb_delta_failed):
		NetClient.resync_delta_failed.disconnect(cb_delta_failed)
	if NetClient.request_rejected.is_connected(cb_rejected):
		NetClient.request_rejected.disconnect(cb_rejected)
	if NetClient.connected.is_connected(cb_connected):
		NetClient.connected.disconnect(cb_connected)
	if NetClient.disconnected.is_connected(cb_disconnected):
		NetClient.disconnected.disconnect(cb_disconnected)

func _on_online_room_state_updated_for_rollback_proposal(room_state: Dictionary) -> void:
	_maybe_show_rollback_proposal(Dictionary(room_state))

func _maybe_show_rollback_proposal(room_state: Dictionary) -> void:
	if NetContext == null or NetContext.mode != NetContext.Mode.ONLINE_CLIENT:
		return
	var proposal_val = room_state.get("rollback_proposal", null)
	if not (proposal_val is Dictionary):
		_active_rollback_proposal_id = ""
		return
	var proposal: Dictionary = Dictionary(proposal_val)
	if proposal.is_empty():
		_active_rollback_proposal_id = ""
		return
	var proposal_id := str(proposal.get("proposal_id", "")).strip_edges()
	if proposal_id.is_empty():
		return
	var local_pid := int(NetContext.local_player_id)
	if local_pid < 0:
		return
	if local_pid == int(proposal.get("proposer_player_id", -1)):
		return
	if bool(proposal.get("self_vote", false)):
		return
	if bool(_handled_rollback_proposal_ids.get(proposal_id, false)):
		return
	if _active_rollback_proposal_id == proposal_id:
		return
	if not _show_confirm.is_valid():
		return
	_active_rollback_proposal_id = proposal_id
	var proposer_pid := int(proposal.get("proposer_player_id", -1))
	var target_index := int(proposal.get("target_index", -1))
	var before_index := int(proposal.get("before_index", -1))
	var steps := maxi(0, before_index - target_index)
	var target_label := "对局开始前"
	if target_index >= 0:
		target_label = "命令 #%d 后" % target_index
	_show_confirm.call(
		"是否同意回滚",
		"玩家 P%d 提议回滚到%s。\n当前目标会撤销 %d 步操作。\n全部其他玩家同意后会立即执行回滚。" % [proposer_pid + 1, target_label, steps],
		Callable(self, "_confirm_rollback_proposal_vote").bind(proposal_id),
		Callable(self, "_reject_rollback_proposal_vote").bind(proposal_id),
		"同意回滚",
		"拒绝"
	)

func _confirm_rollback_proposal_vote(proposal_id: String) -> void:
	_submit_rollback_proposal_vote(proposal_id, true)

func _reject_rollback_proposal_vote(proposal_id: String) -> void:
	_submit_rollback_proposal_vote(proposal_id, false)

func _submit_rollback_proposal_vote(proposal_id: String, approve: bool) -> void:
	var pid := str(proposal_id).strip_edges()
	if pid.is_empty():
		return
	_handled_rollback_proposal_ids[pid] = true
	if _active_rollback_proposal_id == pid:
		_active_rollback_proposal_id = ""
	if NetClient == null or not NetClient.has_method("vote_rollback_proposal"):
		return
	NetClient.vote_rollback_proposal(pid, bool(approve))

func _on_online_command_applied(cmd_dict: Dictionary, state_hash: String) -> void:
	var engine = _get_engine()
	if engine == null:
		return
	var perf_meta: Dictionary = {}
	if NetClient != null and NetClient.has_method("consume_next_command_applied_perf_meta"):
		perf_meta = NetClient.consume_next_command_applied_perf_meta()
	if _resync_in_progress:
		_pending_cmds.append({
			"cmd_dict": cmd_dict.duplicate(true),
			"state_hash": str(state_hash),
		})
		return
	var parsed: Result = Command.from_dict(cmd_dict)
	if not parsed.ok:
		GameLog.error("Game", "联机 CommandApplied 解析失败: %s" % parsed.error)
		_request_online_force_resync("command_parse_failed")
		return
	var cmd: Command = parsed.value
	if int(cmd.index) != int(engine.command_history.size()):
		_request_online_resync("command_index_mismatch")
		_pending_cmds.append({
			"cmd_dict": cmd_dict.duplicate(true),
			"state_hash": str(state_hash),
		})
		return
	var apply_start_mono_usec := OnlinePerfTraceClass.now_mono_usec()
	if OnlinePerfTraceClass.enabled():
		OnlinePerfTraceClass.emit_event("client.command_applied.apply_start", {
			"request_id": str(perf_meta.get("request_id", "")),
			"action_id": str(cmd.action_id),
			"actor_id": int(cmd.actor),
			"command_index": int(cmd.index),
			"room_code": str(NetContext.room_state.get("room_code", "")).strip_edges().to_upper(),
			"history_size_before": int(engine.command_history.size()),
		})
	var r: Result = engine.execute_command(cmd, true)
	var apply_end_mono_usec := OnlinePerfTraceClass.now_mono_usec()
	if not r.ok:
		GameLog.error("Game", "联机回放命令失败: %s" % r.error)
		_request_online_resync("command_apply_failed")
		return
	var apply_done_meta := {
		"request_id": str(perf_meta.get("request_id", "")),
		"action_id": str(cmd.action_id),
		"actor_id": int(cmd.actor),
		"command_index": int(cmd.index),
		"room_code": str(NetContext.room_state.get("room_code", "")).strip_edges().to_upper(),
		"history_size_after": int(engine.command_history.size()),
		"client_apply_ms": float(maxi(0, apply_end_mono_usec - apply_start_mono_usec)) / 1000.0,
		"client_request_to_rx_ms": float(perf_meta.get("client_request_to_rx_ms", -1.0)),
		"server_exec_ms": float(perf_meta.get("server_exec_ms", -1.0)),
		"server_to_client_ms_approx": int(perf_meta.get("server_to_client_ms_approx", -1)),
	}
	if OnlinePerfTraceClass.enabled():
		OnlinePerfTraceClass.emit_event("client.command_applied.apply_done", apply_done_meta)
	if NetClient != null and NetClient.has_method("record_online_resume_runtime_command_applied"):
		var resume_cache_span := OnlinePerfTraceClass.begin_span("client.command_applied.resume_cache_sync", {
			"request_id": str(perf_meta.get("request_id", "")),
			"action_id": str(cmd.action_id),
			"actor_id": int(cmd.actor),
			"command_index": int(cmd.index),
			"room_code": str(NetContext.room_state.get("room_code", "")).strip_edges().to_upper(),
		})
		NetClient.record_online_resume_runtime_command_applied(cmd_dict, state_hash)
		OnlinePerfTraceClass.end_span(resume_cache_span, {
			"request_id": str(perf_meta.get("request_id", "")),
			"action_id": str(cmd.action_id),
			"actor_id": int(cmd.actor),
			"command_index": int(cmd.index),
			"room_code": str(NetContext.room_state.get("room_code", "")).strip_edges().to_upper(),
		})
	var should_sync_resume_progress := true
	if not state_hash.is_empty():
		var state = engine.get_state()
		if state != null and state.has_method("compute_hash"):
			var local_hash := str(state.compute_hash())
			if local_hash != state_hash:
				GameLog.warn("Game", "联机 state_hash 不一致: local=%s server=%s" % [local_hash, state_hash])
				_request_online_resync("state_hash_mismatch")
				should_sync_resume_progress = false

	if should_sync_resume_progress and NetContext != null and NetContext.has_method("sync_online_resume_progress_from_engine"):
		NetContext.sync_online_resume_progress_from_engine(engine)

	if _request_live_log_timeline_refresh.is_valid():
		_request_live_log_timeline_refresh.call()
	if _update_ui.is_valid():
		var ui_update_span := OnlinePerfTraceClass.begin_span("client.command_applied.ui_update", {
			"request_id": str(perf_meta.get("request_id", "")),
			"action_id": str(cmd.action_id),
			"actor_id": int(cmd.actor),
			"command_index": int(cmd.index),
			"room_code": str(NetContext.room_state.get("room_code", "")).strip_edges().to_upper(),
		})
		_update_ui.call()
		OnlinePerfTraceClass.end_span(ui_update_span, {
			"request_id": str(perf_meta.get("request_id", "")),
			"action_id": str(cmd.action_id),
			"actor_id": int(cmd.actor),
			"command_index": int(cmd.index),
			"room_code": str(NetContext.room_state.get("room_code", "")).strip_edges().to_upper(),
		})
	_trace_online_command_ui_settled(apply_done_meta, apply_end_mono_usec)

func _trace_online_command_ui_settled(meta: Dictionary, apply_end_mono_usec: int) -> void:
	if not OnlinePerfTraceClass.enabled():
		return
	if _host == null or not is_instance_valid(_host):
		return
	_trace_online_command_ui_settled_async(meta.duplicate(true), int(apply_end_mono_usec))

func _trace_online_command_ui_settled_async(meta: Dictionary, apply_end_mono_usec: int) -> void:
	if _host == null or not is_instance_valid(_host):
		return
	await _host.get_tree().process_frame
	var out := meta.duplicate(true)
	out["client_ui_settled_ms"] = float(maxi(0, OnlinePerfTraceClass.now_mono_usec() - apply_end_mono_usec)) / 1000.0
	OnlinePerfTraceClass.emit_event("client.command_applied.ui_settled", out)

func _on_online_resync_archive_received(archive: Dictionary) -> void:
	var engine = _get_engine()
	if engine == null:
		return
	if NetClient != null and NetClient.has_method("clear_pending_resync_archive"):
		NetClient.clear_pending_resync_archive()
	_resync_in_progress = true
	_resync_request_id = ""
	var r: Result = _load_archive_for_online_client(engine, archive)
	if not r.ok:
		GameLog.error("Game", "联机 ResyncArchive 加载失败: %s" % r.error)
		if _reconnect_flow_active:
			_reconnect_attempt_failed = true
			_reconnect_attempt_failure_reason = "联机同步失败：%s" % r.error
		_resync_in_progress = false
		_rollback_request_id = ""
		_resync_request_id = ""
		_pending_cmds.clear()
		if _update_ui.is_valid():
			_update_ui.call()
		if not OS.has_feature("headless"):
			if _show_confirm.is_valid():
				_show_confirm.call("联机同步失败", r.error, Callable(), Callable(), "确定", "关闭")
			return

	OnlineResumePointValidatorClass.prepare_engine_for_online_resume(engine)

	var ui_metadata_apply := ModuleUiMetadataBootstrapClass.apply(engine)
	if not ui_metadata_apply.ok:
		GameLog.error("Game", "联机 ResyncArchive UI metadata 装配失败: %s" % ui_metadata_apply.error)

	if NetClient != null and NetClient.has_method("mark_runtime_engine_as_full_history"):
		NetClient.mark_runtime_engine_as_full_history(engine)
	if NetContext != null and NetContext.has_method("sync_online_resume_progress_from_engine"):
		NetContext.sync_online_resume_progress_from_engine(engine)

	GameLog.warn("Game", "联机 ResyncArchive 加载完成（命令数=%d）" % int(engine.command_history.size()))
	_resync_in_progress = false
	_rollback_request_id = ""
	_resync_request_id = ""
	if _reset_timeline_state_after_resync.is_valid():
		_reset_timeline_state_after_resync.call()
	if is_instance_valid(_game_log_panel) and _game_log_panel.visible:
		if _apply_live_log_timeline_from_engine.is_valid():
			_apply_live_log_timeline_from_engine.call(true)
	elif _request_live_log_timeline_refresh.is_valid():
		_request_live_log_timeline_refresh.call()
	if _update_ui.is_valid():
		_update_ui.call()

	_flush_online_pending_commands_after_resync()
	if _reconnect_flow_active or (NetContext != null and NetContext.has_method("is_online_reconnecting") and NetContext.is_online_reconnecting()):
		_reconnect_restore_completed = true

func _on_online_resync_delta_applied(payload: Dictionary) -> void:
	GameLog.warn(
		"Game",
		"联机 DeltaResync 应用完成 from=%d to=%d entries=%d final_hash=%s"
			% [
				int(payload.get("from_sequence", -1)),
				int(payload.get("final_sequence", -1)),
				int(payload.get("entry_count", -1)),
				_short_hash(str(payload.get("final_hash", "")))
			]
	)
	_resync_in_progress = false
	_rollback_request_id = ""
	_resync_request_id = ""
	if _reset_timeline_state_after_resync.is_valid():
		_reset_timeline_state_after_resync.call()
	if is_instance_valid(_game_log_panel) and _game_log_panel.visible:
		if _apply_live_log_timeline_from_engine.is_valid():
			_apply_live_log_timeline_from_engine.call(true)
	elif _request_live_log_timeline_refresh.is_valid():
		_request_live_log_timeline_refresh.call()
	if _update_ui.is_valid():
		_update_ui.call()
	_flush_online_pending_commands_after_resync()
	if _reconnect_flow_active or (NetContext != null and NetContext.has_method("is_online_reconnecting") and NetContext.is_online_reconnecting()):
		_reconnect_restore_completed = true

func _on_online_resync_delta_failed(message: String) -> void:
	GameLog.warn("Game", "联机 DeltaResync 失败：%s" % str(message))
	if _reconnect_flow_active:
		_reconnect_attempt_failed = true
		_reconnect_attempt_failure_reason = str(message)
		return
	if not _resync_in_progress:
		return
	_resync_in_progress = false
	_resync_request_id = ""
	_pending_cmds.clear()
	if _update_ui.is_valid():
		_update_ui.call()
	_begin_full_resync_request("delta_apply_failed", true)

func _on_online_rollback_meta(payload: Dictionary) -> void:
	var engine = _get_engine()
	if engine == null:
		return
	if NetContext == null or NetContext.mode != NetContext.Mode.ONLINE_CLIENT:
		return
	if NetClient == null or not NetClient.is_online_client_connected():
		return
	if NetClient.has_method("clear_pending_rollback_meta"):
		NetClient.clear_pending_rollback_meta()

	var request_id := str(payload.get("request_id", ""))
	var target_index := int(payload.get("target_index", -999))
	var history_size := int(payload.get("history_size", -1))
	var expected_hash := str(payload.get("state_hash", ""))
	var noop := bool(payload.get("noop", false))

	if not request_id.is_empty() and request_id == _rollback_request_id:
		_rollback_request_id = ""
		_resync_ticket += 1

	_resync_in_progress = true
	_resync_request_id = ""

	if noop:
		_resync_in_progress = false
		_resync_request_id = ""
		if _reset_timeline_state_after_resync.is_valid():
			_reset_timeline_state_after_resync.call()
		if is_instance_valid(_game_log_panel) and _game_log_panel.visible:
			if _apply_live_log_timeline_from_engine.is_valid():
				_apply_live_log_timeline_from_engine.call(true)
		elif _request_live_log_timeline_refresh.is_valid():
			_request_live_log_timeline_refresh.call()
		if _update_ui.is_valid():
			_update_ui.call()
		_flush_online_pending_commands_after_resync()
		return

	# 时间线被 server 回退并截断：丢弃本地等待队列中的旧 CommandApplied（可能属于被撤销的未来）。
	_pending_cmds.clear()

	if target_index < -1:
		GameLog.warn("Game", "联机回退应用失败：target_index 无效: %d" % target_index)
		_begin_full_resync_request("rewind_target_before_runtime_anchor", true)
		if _update_ui.is_valid():
			_update_ui.call()
		return
	if target_index >= engine.command_history.size():
		GameLog.warn(
			"Game",
			"联机回退应用失败：本地历史不足（local=%d target=%d），触发 resync"
				% [engine.command_history.size(), target_index]
		)
		_begin_full_resync_request("rewind_local_history_shortage", true)
		if _update_ui.is_valid():
			_update_ui.call()
		return

	var rewind_r: Result = engine.rewind_to_command(target_index)
	if not rewind_r.ok:
		GameLog.error("Game", "联机回退应用失败：%s（触发 resync）" % rewind_r.error)
		_begin_full_resync_request("rewind_apply_failed", true)
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
		_begin_full_resync_request("rewind_history_size_mismatch", true)
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
				_begin_full_resync_request("rewind_state_hash_mismatch", true)
				if _update_ui.is_valid():
					_update_ui.call()
				return

	_resync_in_progress = false
	_rollback_request_id = ""
	_resync_request_id = ""
	if _reset_timeline_state_after_resync.is_valid():
		_reset_timeline_state_after_resync.call()
	if is_instance_valid(_game_log_panel) and _game_log_panel.visible:
		if _apply_live_log_timeline_from_engine.is_valid():
			_apply_live_log_timeline_from_engine.call(true)
	elif _request_live_log_timeline_refresh.is_valid():
		_request_live_log_timeline_refresh.call()
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
	if request_id.is_empty() or _rollback_request_id != request_id:
		return
	if NetContext == null or NetContext.mode != NetContext.Mode.ONLINE_CLIENT:
		return
	if NetClient == null or not NetClient.is_online_client_connected():
		return

	# 若回退请求迟迟未回灌（例如网络抖动/包丢失），主动发起 resync 兜底，避免 UI 看起来“没反应”。
	GameLog.warn("Game", "联机回退未收到回灌，触发 resync request_id=%s" % str(request_id))
	_begin_full_resync_request("rewind_timeout", true)

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
				_request_online_force_resync("pending_command_parse_failed")
				return
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
				_request_online_force_resync("pending_command_apply_failed")
				return
			if NetClient != null and NetClient.has_method("record_online_resume_runtime_command_applied"):
				NetClient.record_online_resume_runtime_command_applied(item_cmd_dict, item_hash)
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
			_apply_live_log_timeline_from_engine.call(true)
	elif _request_live_log_timeline_refresh.is_valid():
		_request_live_log_timeline_refresh.call()
	if _update_ui.is_valid():
		_update_ui.call()

func _request_online_resync(reason: String) -> void:
	_begin_full_resync_request(reason)

func _request_online_force_resync(reason: String) -> void:
	_begin_full_resync_request(reason, true)

func _on_online_connected() -> void:
	if not _reconnect_flow_active:
		return
	_reconnect_transport_connected = true
	_reconnect_attempt_failed = false
	_reconnect_attempt_failure_reason = ""
	if _show_loading.is_valid():
		_show_loading.call("已重新连接，正在恢复对局...")

func _on_online_request_rejected(request_id: String, code: String, message: String) -> void:
	GameLog.warn("Game", "联机请求被拒绝 request_id=%s: %s %s" % [str(request_id), code, message])
	var action_id := _take_action_id_for_request(request_id)
	var matched_resync_rejection := _resync_in_progress \
		and _rollback_request_id.is_empty() \
		and _is_matching_resync_rejection(request_id, code)
	if _reconnect_flow_active:
		if matched_resync_rejection:
			_resync_in_progress = false
			_resync_request_id = ""
		_reconnect_attempt_failed = true
		_reconnect_attempt_failure_reason = "%s: %s" % [str(code), str(message)]
		return
	if _resync_in_progress and not _rollback_request_id.is_empty() and str(request_id) == _rollback_request_id:
		# 避免“回退请求失败但仍卡在同步中”，导致 ActionPanel 永久禁用与状态不一致。
		_resync_in_progress = false
		_rollback_request_id = ""
		_resync_request_id = ""
		_flush_online_pending_commands_after_resync()
		if _update_ui.is_valid():
			_update_ui.call()
	elif matched_resync_rejection:
		_resync_in_progress = false
		_resync_request_id = ""
		if _update_ui.is_valid():
			_update_ui.call()
		if str(code).strip_edges() == "resync_rate_limited":
			return
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
	if _reconnect_flow_active:
		_reconnect_attempt_failed = true
		_reconnect_attempt_failure_reason = str(reason)
		return
	if _can_attempt_online_reconnect():
		_reconnect_ticket += 1
		_reconnect_flow_active = true
		_reconnect_transport_connected = false
		_reconnect_restore_completed = false
		_reconnect_attempt_failed = false
		_reconnect_attempt_failure_reason = ""
		if OnlineSessionCoordinator != null and OnlineSessionCoordinator.has_method("begin_in_game_reconnect"):
			OnlineSessionCoordinator.begin_in_game_reconnect()
		elif NetContext != null and NetContext.has_method("set_online_reconnecting"):
			NetContext.set_online_reconnecting(true)
		if _show_loading.is_valid():
			_show_loading.call("联机已断开，正在尝试重连...")
		call_deferred("_run_online_reconnect_flow", _reconnect_ticket, str(reason))
		return
	if _show_confirm.is_valid():
		_show_confirm.call("联机已断开", "原因：%s\n将返回联机大厅。" % reason, Callable(), Callable(), "确定", "关闭")
	if _host == null or not is_instance_valid(_host):
		return
	await _host.get_tree().process_frame
	if _host == null or not is_instance_valid(_host):
		return
	if _goto_online_lobby.is_valid():
		_goto_online_lobby.call()

func _can_attempt_online_reconnect() -> bool:
	if _host == null or not is_instance_valid(_host):
		return false
	if not _resume_room_request.is_valid():
		return false
	if not _connect_to_server.is_valid():
		return false
	if OnlineSessionCoordinator != null and OnlineSessionCoordinator.has_method("can_attempt_in_game_resume"):
		return bool(OnlineSessionCoordinator.can_attempt_in_game_resume())
	if NetContext == null or not NetContext.has_method("has_online_resume_context"):
		return false
	if not NetContext.has_online_resume_context():
		return false
	if not NetContext.has_method("is_online_resume_in_game") or not NetContext.is_online_resume_in_game():
		return false
	return true

func _run_online_reconnect_flow(ticket: int, initial_reason: String) -> void:
	if ticket != _reconnect_ticket:
		return
	if _host == null or not is_instance_valid(_host):
		return

	var final_error := "联机已断开：%s" % initial_reason
	for attempt in range(1, RECONNECT_MAX_ATTEMPTS + 1):
		if ticket != _reconnect_ticket or not _reconnect_flow_active:
			return
		_reconnect_transport_connected = false
		_reconnect_restore_completed = false
		_reconnect_attempt_failed = false
		_reconnect_attempt_failure_reason = ""
		if _show_loading.is_valid():
			_show_loading.call("联机已断开，正在重连（%d/%d）..." % [attempt, RECONNECT_MAX_ATTEMPTS])

		var resume_r: Result = await _request_resume_ticket()
		if not resume_r.ok:
			final_error = resume_r.error
			GameLog.warn("Game", "联机重连获取 token 失败 attempt=%d err=%s" % [attempt, resume_r.error])
			if attempt < RECONNECT_MAX_ATTEMPTS:
				await _wait_seconds(RECONNECT_RETRY_DELAY_SEC)
				continue
			await _finish_online_reconnect_failure(ticket, final_error)
			return

		var payload: Dictionary = Dictionary(resume_r.value)
		var url := _build_connect_url(
			str(payload.get("ws_url", "")),
			str(payload.get("connect_token", ""))
		)
		if url.is_empty():
			final_error = "resume_room 返回了无效的 ws_url/connect_token"
			if attempt < RECONNECT_MAX_ATTEMPTS:
				await _wait_seconds(RECONNECT_RETRY_DELAY_SEC)
				continue
			await _finish_online_reconnect_failure(ticket, final_error)
			return

		var connect_r = _connect_to_server.call(url)
		if not (connect_r is Result) or not connect_r.ok:
			final_error = connect_r.error if connect_r is Result else "connect_to_server 返回类型错误"
			GameLog.warn("Game", "联机重连发起连接失败 attempt=%d err=%s" % [attempt, final_error])
			if attempt < RECONNECT_MAX_ATTEMPTS:
				await _wait_seconds(RECONNECT_RETRY_DELAY_SEC)
				continue
			await _finish_online_reconnect_failure(ticket, final_error)
			return

		var transport_ok := await _wait_for_reconnect_transport(ticket, RECONNECT_CONNECT_TIMEOUT_SEC)
		if not transport_ok:
			final_error = _reconnect_attempt_failure_reason if not _reconnect_attempt_failure_reason.is_empty() else "连接服务器超时"
			GameLog.warn("Game", "联机重连 transport 失败 attempt=%d err=%s" % [attempt, final_error])
			if _shutdown_net.is_valid():
				_shutdown_net.call(false)
			if attempt < RECONNECT_MAX_ATTEMPTS:
				await _wait_seconds(RECONNECT_RETRY_DELAY_SEC)
				continue
			await _finish_online_reconnect_failure(ticket, final_error)
			return

		if _show_loading.is_valid():
			_show_loading.call("已重新连接，正在恢复对局...")

		var restore_ok := await _wait_for_reconnect_restore(ticket, RECONNECT_RESTORE_TIMEOUT_SEC)
		if not restore_ok:
			_begin_full_resync_request("reconnect_restore_timeout", true)
			if _show_loading.is_valid():
				_show_loading.call("正在请求对局快照恢复...")
			restore_ok = await _wait_for_reconnect_restore(ticket, RECONNECT_RESTORE_TIMEOUT_SEC)

		if restore_ok:
			_finish_online_reconnect_success(ticket)
			return

		final_error = _reconnect_attempt_failure_reason if not _reconnect_attempt_failure_reason.is_empty() else "恢复对局超时"
		GameLog.warn("Game", "联机重连恢复失败 attempt=%d err=%s" % [attempt, final_error])
		if _shutdown_net.is_valid():
			_shutdown_net.call(false)
		if attempt < RECONNECT_MAX_ATTEMPTS:
			await _wait_seconds(RECONNECT_RETRY_DELAY_SEC)
			continue
		await _finish_online_reconnect_failure(ticket, final_error)
		return

func _request_resume_ticket() -> Result:
	if OnlineSessionCoordinator != null and OnlineSessionCoordinator.has_method("request_resume_ticket") and _ensure_platform_session.is_valid():
		return await OnlineSessionCoordinator.request_resume_ticket({
			"ensure_session": _ensure_platform_session,
			"resume_room": _resume_room_request,
			"defer_resume_room_terminal_clear": true,
		})
	if NetContext == null or not NetContext.has_method("get_online_resume_room_code"):
		return Result.failure("联机恢复状态缺失")
	var room_code := NetContext.get_online_resume_room_code()
	if room_code.is_empty():
		return Result.failure("联机恢复 room_code 缺失")
	var resume_resp = await _resume_room_request.call(room_code)
	if not (resume_resp is Dictionary):
		return Result.failure("resume_room 返回格式错误")
	var resume_dict: Dictionary = Dictionary(resume_resp)
	if resume_dict.has("error"):
		return Result.failure(_stringify_platform_error(resume_dict.get("error", "")))
	var ok_val = resume_dict.get("ok", null)
	if not (ok_val is Dictionary):
		return Result.failure("resume_room 响应缺少 ok")
	var ok: Dictionary = Dictionary(ok_val)
	var ws_url := str(ok.get("ws_url", "")).strip_edges()
	var connect_token := str(ok.get("connect_token", "")).strip_edges()
	if ws_url.is_empty() or connect_token.is_empty():
		return Result.failure("resume_room 缺少 ws_url/connect_token")
	return Result.success({
		"room_code": room_code,
		"ws_url": ws_url,
		"connect_token": connect_token,
	})

func _wait_for_reconnect_transport(ticket: int, timeout_sec: float) -> bool:
	if _host == null or not is_instance_valid(_host):
		return false
	var deadline := Time.get_ticks_msec() + int(timeout_sec * 1000.0)
	while Time.get_ticks_msec() <= deadline:
		if ticket != _reconnect_ticket or not _reconnect_flow_active:
			return false
		if _reconnect_transport_connected:
			return true
		if _reconnect_attempt_failed:
			return false
		await _host.get_tree().process_frame
	return false

func _wait_for_reconnect_restore(ticket: int, timeout_sec: float) -> bool:
	if _host == null or not is_instance_valid(_host):
		return false
	var deadline := Time.get_ticks_msec() + int(timeout_sec * 1000.0)
	while Time.get_ticks_msec() <= deadline:
		if ticket != _reconnect_ticket or not _reconnect_flow_active:
			return false
		if _reconnect_restore_completed:
			return true
		if _reconnect_attempt_failed:
			return false
		await _host.get_tree().process_frame
	return false

func _wait_seconds(duration_sec: float) -> void:
	if _host == null or not is_instance_valid(_host):
		return
	var tree := _host.get_tree()
	if tree == null:
		return
	await tree.create_timer(duration_sec).timeout

func _finish_online_reconnect_success(ticket: int) -> void:
	if ticket != _reconnect_ticket:
		return
	_reconnect_flow_active = false
	_reconnect_transport_connected = false
	_reconnect_restore_completed = false
	_reconnect_attempt_failed = false
	_reconnect_attempt_failure_reason = ""
	_resync_request_id = ""
	if OnlineSessionCoordinator != null and OnlineSessionCoordinator.has_method("finish_in_game_reconnect"):
		OnlineSessionCoordinator.finish_in_game_reconnect(true)
	elif NetContext != null and NetContext.has_method("set_online_reconnecting"):
		NetContext.set_online_reconnecting(false)
	if _hide_loading.is_valid():
		_hide_loading.call()
	if _update_ui.is_valid():
		_update_ui.call()
	GameLog.info("Game", "联机重连恢复成功")

func _finish_online_reconnect_failure(ticket: int, error_message: String) -> void:
	if ticket != _reconnect_ticket:
		return
	_reconnect_flow_active = false
	_reconnect_transport_connected = false
	_reconnect_restore_completed = false
	_reconnect_attempt_failed = false
	_reconnect_attempt_failure_reason = ""
	_resync_request_id = ""
	if OnlineSessionCoordinator != null and OnlineSessionCoordinator.has_method("finish_in_game_reconnect"):
		OnlineSessionCoordinator.finish_in_game_reconnect(false, error_message)
	elif NetContext != null and NetContext.has_method("set_online_reconnecting"):
		NetContext.set_online_reconnecting(false)
	if _hide_loading.is_valid():
		_hide_loading.call()
	if _shutdown_net.is_valid():
		_shutdown_net.call(true)
	if _show_confirm.is_valid():
		_show_confirm.call("重连失败", "%s\n将返回联机大厅。" % error_message, Callable(), Callable(), "确定", "关闭")
	if _host == null or not is_instance_valid(_host):
		return
	await _host.get_tree().process_frame
	if _host == null or not is_instance_valid(_host):
		return
	if _goto_online_lobby.is_valid():
		_goto_online_lobby.call()

func _build_connect_url(ws_url: String, connect_token: String) -> String:
	var base := str(ws_url).strip_edges()
	var token := str(connect_token).strip_edges()
	if base.is_empty() or token.is_empty():
		return ""
	var sep := "?" if base.find("?") < 0 else "&"
	return base + sep + "connect_token=" + token.uri_encode()

func _stringify_platform_error(error_val) -> String:
	if error_val is Dictionary:
		var err_dict: Dictionary = Dictionary(error_val)
		var detail := str(err_dict.get("detail", "")).strip_edges()
		if not detail.is_empty():
			return detail
		var body: Variant = err_dict.get("body", null)
		if body != null:
			return str(body)
		return JSON.stringify(err_dict)
	var text := str(error_val).strip_edges()
	if text.is_empty():
		return "未知错误"
	return text

func _short_hash(hash_value: String) -> String:
	var h := str(hash_value).strip_edges()
	if h.is_empty():
		return "-"
	if h.length() <= 12:
		return h
	return "%s..." % h.substr(0, 12)
