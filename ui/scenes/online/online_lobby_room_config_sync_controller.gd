# OnlineLobby：Room 配置自动同步控制器（debounce/dirty/syncing/error）
extends RefCounted

var _lobby = null
var _status_label: Label = null
var _debounce_timer: Timer = null

var _state: String = "synced" # synced/dirty/syncing/error
var _message: String = ""
var _pending_patch: Dictionary = {}
var _last_editor_sync_signature: String = ""

func setup(lobby, status_label: Label, debounce_timer: Timer) -> void:
	_lobby = lobby
	_status_label = status_label
	_debounce_timer = debounce_timer
	_last_editor_sync_signature = ""
	set_state("synced", "")

func get_state() -> String:
	return _state

func is_error() -> bool:
	return _state == "error"

func reset() -> void:
	if _debounce_timer != null and is_instance_valid(_debounce_timer):
		_debounce_timer.stop()
	_pending_patch = {}
	_last_editor_sync_signature = ""
	set_state("synced", "")

func set_state(state: String, message: String) -> void:
	_state = str(state)
	_message = str(message).strip_edges()
	_apply_state_to_label()

func _apply_state_to_label() -> void:
	if _status_label == null or not is_instance_valid(_status_label):
		return
	var s := ""
	match _state:
		"synced":
			s = "配置：已同步"
		"dirty":
			s = "配置：待同步..."
		"syncing":
			s = "配置：同步中..."
		"error":
			s = "配置：错误 - %s" % _message
		_:
			s = "配置：%s" % _state
	if _status_label.text == s:
		return
	_status_label.text = s

func on_request_rejected(code: String, message: String) -> void:
	var c := str(code).strip_edges()
	if c.begins_with("update_config"):
		set_state("error", str(message))

func on_room_config_editor_validation_failed(message: String) -> void:
	set_state("error", str(message))

func on_room_config_editor_changed(room_state: Dictionary, is_host: bool, room_config_editor: Object) -> void:
	if not bool(is_host):
		return
	if str(room_state.get("status", "")).strip_edges() != "Lobby":
		return
	if str(room_state.get("room_mode", "")).strip_edges() == "resume_archive":
		return
	if room_config_editor == null or not is_instance_valid(room_config_editor):
		return
	if not room_config_editor.has_method("validate") or not room_config_editor.has_method("get_config_patch"):
		return

	var vr: Result = room_config_editor.call("validate")
	if not vr.ok:
		set_state("error", vr.error)
		return

	var patch_val = room_config_editor.call("get_config_patch")
	_pending_patch = Dictionary(patch_val) if (patch_val is Dictionary) else {}
	set_state("dirty", "")
	if _debounce_timer != null and is_instance_valid(_debounce_timer):
		_debounce_timer.start()

func on_debounce_timeout(room_state: Dictionary, is_host: bool, net_client: Object) -> void:
	if not bool(is_host):
		return
	if str(room_state.get("status", "")).strip_edges() != "Lobby":
		return
	if str(room_state.get("room_mode", "")).strip_edges() == "resume_archive":
		return
	if _pending_patch.is_empty():
		return
	if net_client == null or not is_instance_valid(net_client):
		return
	if net_client.has_method("is_online_client_connected") and not bool(net_client.call("is_online_client_connected")):
		return
	if not net_client.has_method("request_update_room_config"):
		return

	set_state("syncing", "")
	net_client.call("request_update_room_config", _pending_patch)

func sync_editor_from_room_state(room_state: Dictionary, is_host: bool, room_config_editor: Object) -> void:
	if not bool(is_host) and _state != "synced":
		set_state("synced", "")
	if room_config_editor == null or not is_instance_valid(room_config_editor):
		_last_editor_sync_signature = ""
		return
	var cfg: Dictionary = Dictionary(room_state.get("config", {}))
	var editable: bool = bool(is_host) and str(room_state.get("status", "")).strip_edges() == "Lobby" and str(room_state.get("room_mode", "")).strip_edges() != "resume_archive"
	var should_sync_from_room := (not bool(is_host)) or _state == "synced" or _state == "syncing"
	var sync_signature := _build_editor_sync_signature(cfg, editable, should_sync_from_room, room_config_editor)
	if sync_signature == _last_editor_sync_signature:
		return
	if should_sync_from_room:
		if room_config_editor.has_method("set_from_room_config"):
			room_config_editor.call("set_from_room_config", cfg)
		if bool(is_host) and _state == "syncing":
			_pending_patch = {}
			set_state("synced", "")
	if room_config_editor.has_method("set_editable"):
		room_config_editor.call("set_editable", editable)
	_last_editor_sync_signature = _build_editor_sync_signature(cfg, editable, ((not bool(is_host)) or _state == "synced" or _state == "syncing"), room_config_editor)

func _build_editor_sync_signature(cfg: Dictionary, editable: bool, should_sync_from_room: bool, room_config_editor: Object) -> String:
	var editor_id := 0
	if room_config_editor != null and is_instance_valid(room_config_editor):
		editor_id = int(room_config_editor.get_instance_id())
	return JSON.stringify({
		"editor_id": editor_id,
		"cfg": cfg.duplicate(true),
		"editable": bool(editable),
		"should_sync_from_room": bool(should_sync_from_room),
		"state": str(_state),
	})

func pre_sync_for_start_game(room_state: Dictionary, net_client: Object, room_config_editor: Object, timeout_sec: float = 5.0) -> bool:
	if str(room_state.get("room_mode", "")).strip_edges() == "resume_archive":
		_pending_patch = {}
		set_state("synced", "")
		return true
	if _debounce_timer != null and is_instance_valid(_debounce_timer):
		_debounce_timer.stop()
	if room_config_editor == null or not is_instance_valid(room_config_editor):
		set_state("error", "房间配置编辑器缺失")
		return false

	var patch_val = room_config_editor.call("get_config_patch") if room_config_editor.has_method("get_config_patch") else null
	var patch: Dictionary = Dictionary(patch_val) if (patch_val is Dictionary) else {}
	var cfg: Dictionary = Dictionary(room_state.get("config", {}))

	if _room_config_matches_patch(cfg, patch):
		_pending_patch = {}
		set_state("synced", "")
		return true

	if net_client == null or not is_instance_valid(net_client) or not net_client.has_method("request_update_room_config"):
		set_state("error", "NetClient 缺失")
		return false

	_pending_patch = patch
	set_state("syncing", "")
	net_client.call("request_update_room_config", patch)
	var synced: bool = await await_synced(timeout_sec)
	if not synced:
		if _state != "error":
			set_state("error", "配置同步超时")
		return false
	return true

func await_synced(timeout_sec: float = 5.0) -> bool:
	var deadline_ms := int(Time.get_ticks_msec() + int(round(timeout_sec * 1000.0)))
	while Time.get_ticks_msec() < deadline_ms:
		if _state == "synced":
			return true
		if _state == "error":
			return false
		if _lobby == null or not is_instance_valid(_lobby):
			return false
		await _lobby.get_tree().process_frame
	return false

func _room_config_matches_patch(cfg: Dictionary, patch: Dictionary) -> bool:
	if cfg == null or patch == null:
		return false
	for k in patch.keys():
		if cfg.get(k, null) != patch.get(k, null):
			return false
	return true
