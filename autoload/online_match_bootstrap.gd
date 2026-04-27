extends Node

const SESSION_PRIORITY := 100
const PHASE_PREPARING := "preparing"
const PHASE_WAITING_FOR_PLAYERS := "waiting_for_players"
const PHASE_COMMITTING := "committing"

var _active_room_code: String = ""
var _active_bootstrap_id: String = ""
var _active_request_id: String = ""
var _local_ready: bool = false
var _runtime_bootstrap_ready: bool = false
var _waiting_resume_full_history: bool = false
var _ready_request_sent: bool = false
var _enter_game_requested: bool = false

func _ready() -> void:
	_ensure_net_signal_connections()

func begin_local_start_request(room_state: Dictionary) -> void:
	_ensure_net_signal_connections()
	var room_code := _extract_room_code(room_state)
	if room_code.is_empty():
		return
	if _active_room_code != room_code:
		_clear_state(true, true)
	_active_room_code = room_code
	_active_bootstrap_id = ""
	_active_request_id = ""
	_local_ready = false
	_runtime_bootstrap_ready = false
	_waiting_resume_full_history = false
	_ready_request_sent = false
	_enter_game_requested = false
	_apply_loading_state({
		"title": "正在开始联机对局...",
		"detail": "正在同步房间配置并提交开始请求。",
		"stage": "正在准备开始游戏...",
		"wait_text": "",
		"show_progress": true,
		"progress_value": 8.0,
		"progress_max": 100.0,
		"priority": SESSION_PRIORITY,
	})

func sync_from_room_state(room_state: Dictionary) -> void:
	_ensure_net_signal_connections()
	var room_code := _extract_room_code(room_state)
	var status := str(room_state.get("status", "")).strip_edges()
	if status == "Starting":
		if room_code.is_empty():
			return
		if _active_room_code != room_code:
			_clear_state(true, true)
			_active_room_code = room_code
			_active_bootstrap_id = ""
			_active_request_id = ""
			_local_ready = false
			_runtime_bootstrap_ready = false
			_waiting_resume_full_history = false
			_ready_request_sent = false
			_enter_game_requested = false
		var bootstrap: Dictionary = Dictionary(room_state.get("bootstrap", {})).duplicate(true)
		_active_bootstrap_id = str(bootstrap.get("id", _active_bootstrap_id)).strip_edges()
		_active_request_id = str(bootstrap.get("request_id", _active_request_id)).strip_edges()
		_maybe_send_ready_ack()
		_apply_loading_state(_build_starting_loading_state(room_state, bootstrap))
		return

	if not has_active_session():
		return
	if room_code.is_empty() or room_code != _active_room_code:
		reset()
		return
	if status == "InGame":
		_apply_loading_state({
			"title": "正在进入联机对局...",
			"detail": "服务器已确认开局，正在切换到游戏界面。",
			"stage": "正在进入对局...",
			"wait_text": "",
			"show_progress": true,
			"progress_value": 95.0,
			"progress_max": 100.0,
			"priority": SESSION_PRIORITY,
		})
		return
	if status == "Lobby":
		reset()

func mark_local_bootstrap_ready(room_state: Dictionary) -> void:
	_ensure_net_signal_connections()
	var room_code := _extract_room_code(room_state)
	if _active_room_code.is_empty() and not room_code.is_empty():
		_active_room_code = room_code
	if _active_room_code.is_empty():
		return
	_runtime_bootstrap_ready = true
	var bootstrap: Dictionary = Dictionary(room_state.get("bootstrap", {})).duplicate(true)
	if not bootstrap.is_empty():
		_active_bootstrap_id = str(bootstrap.get("id", _active_bootstrap_id)).strip_edges()
		_active_request_id = str(bootstrap.get("request_id", _active_request_id)).strip_edges()
	_waiting_resume_full_history = _needs_resume_full_history_before_ready(room_state)
	if _waiting_resume_full_history:
		_local_ready = false
		_apply_loading_state(_build_starting_loading_state(room_state, bootstrap))
		return
	_local_ready = true
	_maybe_send_ready_ack()
	if str(room_state.get("status", "")).strip_edges() == "InGame":
		_apply_loading_state({
			"title": "正在进入联机对局...",
			"detail": "本地对局已准备完成，正在进入游戏界面。",
			"stage": "正在进入对局...",
			"wait_text": "",
			"show_progress": true,
			"progress_value": 95.0,
			"progress_max": 100.0,
			"priority": SESSION_PRIORITY,
		})
		return
	_apply_loading_state(_build_starting_loading_state(room_state, bootstrap))

func mark_local_bootstrap_failed(message: String, room_state: Dictionary) -> void:
	var room_code := _extract_room_code(room_state)
	if _active_room_code.is_empty() and not room_code.is_empty():
		_active_room_code = room_code
	if _active_room_code.is_empty():
		return
	var reason := str(message).strip_edges()
	if reason.is_empty():
		reason = "本地初始化失败"
	_apply_loading_state({
		"title": "开始游戏失败",
		"detail": reason,
		"stage": "本地对局初始化失败",
		"wait_text": "",
		"show_progress": false,
		"progress_value": 0.0,
		"progress_max": 100.0,
		"priority": SESSION_PRIORITY,
	})
	if not _active_bootstrap_id.is_empty() and NetClient != null and NetClient.has_method("request_match_bootstrap_failed"):
		NetClient.request_match_bootstrap_failed(_active_bootstrap_id, reason)

func on_resume_full_history_ready(payload: Dictionary = {}) -> void:
	if not has_active_session():
		return
	if not _runtime_bootstrap_ready:
		return
	if not _waiting_resume_full_history:
		return
	var room_state: Dictionary = NetContext.room_state if NetContext != null else {}
	if _extract_room_code(room_state) != _active_room_code:
		return
	var snapshot: Dictionary = Dictionary(payload).duplicate(true) if (payload is Dictionary) else {}
	if should_wait_for_resume_full_history(room_state, snapshot):
		return
	_waiting_resume_full_history = false
	_local_ready = true
	var bootstrap: Dictionary = Dictionary(room_state.get("bootstrap", {})).duplicate(true)
	if not bootstrap.is_empty():
		_active_bootstrap_id = str(bootstrap.get("id", _active_bootstrap_id)).strip_edges()
		_active_request_id = str(bootstrap.get("request_id", _active_request_id)).strip_edges()
	_maybe_send_ready_ack()
	if str(room_state.get("status", "")).strip_edges() == "InGame":
		_apply_loading_state({
			"title": "正在进入联机对局...",
			"detail": "完整历史已准备完成，正在进入游戏界面。",
			"stage": "正在进入对局...",
			"wait_text": "",
			"show_progress": true,
			"progress_value": 95.0,
			"progress_max": 100.0,
			"priority": SESSION_PRIORITY,
		})
		return
	_apply_loading_state(_build_starting_loading_state(room_state, bootstrap))

func should_enter_game(room_state: Dictionary) -> bool:
	if not has_active_session():
		return false
	if not _local_ready:
		return false
	if _extract_room_code(room_state) != _active_room_code:
		return false
	return str(room_state.get("status", "")).strip_edges() == "InGame"

func mark_enter_game_requested() -> void:
	if not has_active_session():
		return
	_enter_game_requested = true
	_apply_loading_state({
		"title": "正在进入联机对局...",
		"detail": "所有玩家已完成准备，正在切换到游戏场景。",
		"stage": "正在进入对局...",
		"wait_text": "",
		"show_progress": true,
		"progress_value": 96.0,
		"progress_max": 100.0,
		"priority": SESSION_PRIORITY,
	})

func on_game_scene_stage(stage: String, progress_value: float, detail: String = "") -> void:
	if not has_active_session():
		return
	_apply_loading_state({
		"title": "正在进入联机对局...",
		"detail": str(detail).strip_edges(),
		"stage": str(stage).strip_edges(),
		"wait_text": "",
		"show_progress": true,
		"progress_value": progress_value,
		"progress_max": 100.0,
		"priority": SESSION_PRIORITY,
	})

func finish_after_game_ui_ready() -> void:
	if not has_active_session():
		return
	var session_id := _session_id()
	_clear_state(false, false)
	if not session_id.is_empty() and LoadingCoordinator != null and LoadingCoordinator.has_method("finish_session"):
		LoadingCoordinator.finish_session(session_id)

func reset() -> void:
	_clear_state(true, true)

func has_active_session() -> bool:
	return not _active_room_code.is_empty()

func is_active() -> bool:
	return has_active_session()

static func should_wait_for_resume_full_history(room_state: Dictionary, session_snapshot: Dictionary) -> bool:
	if room_state == null:
		return false
	if str(room_state.get("room_mode", "")).strip_edges() != "resume_archive":
		return false
	var snapshot: Dictionary = Dictionary(session_snapshot).duplicate(true) if (session_snapshot is Dictionary) else {}
	if snapshot.is_empty():
		return true
	var snapshot_room_code := str(snapshot.get("runtime_room_code", "")).strip_edges().to_upper()
	var room_code := str(room_state.get("room_code", "")).strip_edges().to_upper()
	if not snapshot_room_code.is_empty() and not room_code.is_empty() and snapshot_room_code != room_code:
		return false
	if not bool(snapshot.get("single_full_engine_mode", false)):
		return true
	if not bool(snapshot.get("runtime_ready", false)):
		return true
	if not bool(snapshot.get("full_history_ready", false)):
		return true
	if not bool(snapshot.get("full_history_step_timeline_ready", false)):
		return true
	return false

func _build_starting_loading_state(room_state: Dictionary, bootstrap: Dictionary) -> Dictionary:
	var phase := str(bootstrap.get("phase", PHASE_PREPARING)).strip_edges()
	var ready_count := int(bootstrap.get("ready_count", 0))
	var total_count := maxi(1, int(bootstrap.get("total_count", 0)))
	var is_host := int(room_state.get("host_peer_id", 0)) == int(multiplayer.get_unique_id())
	var title := "正在开始联机对局..."
	var stage := "正在准备开始游戏..."
	var detail := "房间正在切换到统一加载状态。"
	var wait_text := ""
	var progress_value := 12.0

	match phase:
		PHASE_PREPARING:
			stage = "服务器正在准备对局..."
			detail = "房主已发起开始游戏，服务器正在准备启动数据。" if not is_host else "服务器正在准备启动数据。"
			progress_value = 22.0
		PHASE_WAITING_FOR_PLAYERS:
			if _local_ready:
				stage = "正在等待其他玩家..."
				detail = "本地对局已准备完成，正在等待其他玩家完成初始化。"
				progress_value = 80.0 + minf(10.0, 10.0 * float(ready_count) / float(total_count))
			elif _waiting_resume_full_history:
				stage = "正在构建完整历史..."
				detail = "正在为恢复房预构建完整历史与日志时间线缓存。"
				progress_value = 68.0
			else:
				stage = "正在初始化本地对局..."
				detail = "正在接收启动数据并初始化本地对局。"
				progress_value = 55.0
			wait_text = "等待玩家 %d/%d" % [ready_count, total_count]
		PHASE_COMMITTING:
			stage = "正在进入对局..."
			detail = "所有玩家已完成准备，服务器正在提交开局。"
			progress_value = 94.0
		_:
			progress_value = 18.0
	if _enter_game_requested:
		stage = "正在进入对局..."
		detail = "游戏场景正在装配，请稍候。"
		progress_value = maxf(progress_value, 96.0)

	return {
		"title": title,
		"detail": detail,
		"stage": stage,
		"wait_text": wait_text,
		"show_progress": true,
		"progress_value": progress_value,
		"progress_max": 100.0,
		"priority": SESSION_PRIORITY,
	}

func _maybe_send_ready_ack() -> void:
	if not _local_ready:
		return
	if _ready_request_sent:
		return
	if _active_bootstrap_id.is_empty():
		return
	if NetClient == null or not NetClient.has_method("request_match_bootstrap_ready"):
		return
	NetClient.request_match_bootstrap_ready(_active_bootstrap_id)
	_ready_request_sent = true

func _apply_loading_state(state: Dictionary) -> void:
	if not has_active_session():
		return
	var session_id := _session_id()
	if session_id.is_empty():
		return
	var payload: Dictionary = Dictionary(state).duplicate(true)
	payload["priority"] = SESSION_PRIORITY
	if LoadingCoordinator == null:
		return
	if LoadingCoordinator.has_method("has_session") and not LoadingCoordinator.has_session(session_id):
		LoadingCoordinator.begin_session(session_id, payload)
		return
	LoadingCoordinator.update_session(session_id, payload)

func _clear_state(cleanup_local_engine: bool, finish_loading: bool) -> void:
	var session_id := _session_id()
	var room_code := _active_room_code
	_active_room_code = ""
	_active_bootstrap_id = ""
	_active_request_id = ""
	_local_ready = false
	_runtime_bootstrap_ready = false
	_waiting_resume_full_history = false
	_ready_request_sent = false
	_enter_game_requested = false
	if finish_loading and not session_id.is_empty() and LoadingCoordinator != null and LoadingCoordinator.has_method("finish_session"):
		LoadingCoordinator.finish_session(session_id)
	if cleanup_local_engine:
		_cleanup_local_bootstrap_state(room_code)

func _ensure_net_signal_connections() -> void:
	if NetClient == null:
		return
	if NetClient.has_signal("resume_full_history_ready") and not NetClient.resume_full_history_ready.is_connected(_on_resume_full_history_ready):
		NetClient.resume_full_history_ready.connect(_on_resume_full_history_ready)
	if NetClient.has_signal("local_bootstrap_progress") and not NetClient.local_bootstrap_progress.is_connected(_on_local_bootstrap_progress):
		NetClient.local_bootstrap_progress.connect(_on_local_bootstrap_progress)

func _on_resume_full_history_ready(payload: Dictionary) -> void:
	on_resume_full_history_ready(payload)

func _on_local_bootstrap_progress(payload: Dictionary) -> void:
	if not has_active_session():
		return
	if not (payload is Dictionary):
		return
	var room_code := str(Dictionary(payload).get("room_code", "")).strip_edges().to_upper()
	if room_code.is_empty() or room_code != _active_room_code:
		return
	var state: Dictionary = Dictionary(payload).duplicate(true)
	state["priority"] = SESSION_PRIORITY
	_apply_loading_state(state)

func _needs_resume_full_history_before_ready(room_state: Dictionary) -> bool:
	if NetClient == null or not NetClient.has_method("get_online_resume_session_snapshot"):
		return false
	return should_wait_for_resume_full_history(
		room_state,
		Dictionary(NetClient.get_online_resume_session_snapshot()).duplicate(true)
	)

func _cleanup_local_bootstrap_state(room_code: String) -> void:
	var normalized_room_code := str(room_code).strip_edges().to_upper()
	if normalized_room_code.is_empty():
		return
	var should_dispose_runtime_engine := false
	if NetClient != null:
		if NetClient.has_method("clear_pending_online_resync_state"):
			NetClient.clear_pending_online_resync_state()
		if NetClient.has_method("clear_online_resume_full_history_state"):
			NetClient.clear_online_resume_full_history_state()
		if str(NetClient.get("_online_client_engine_room_code")).strip_edges().to_upper() == normalized_room_code:
			should_dispose_runtime_engine = true
			NetClient.set("_online_client_engine_room_code", "")
	if Globals == null or not Globals.has_method("set_current_game_engine"):
		return
	if not should_dispose_runtime_engine:
		return
	var engine = Globals.current_game_engine
	if engine == null:
		return
	if engine.has_method("dispose"):
		engine.dispose()
	Globals.set_current_game_engine(null)

func _session_id() -> String:
	if _active_room_code.is_empty():
		return ""
	return "online_match_bootstrap:%s" % _active_room_code

func _extract_room_code(room_state: Dictionary) -> String:
	if room_state == null:
		return ""
	return str(room_state.get("room_code", "")).strip_edges().to_upper()
