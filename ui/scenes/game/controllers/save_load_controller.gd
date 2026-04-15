# Game scene：存档/回放选择控制器
# 负责：SaveLoadDialog 的生命周期与回调分发（当前仅保留“保存”）
class_name GameSaveLoadController
extends RefCounted

const ArchiveClass = preload("res://core/engine/game_engine/archive.gd")

var _scene = null
var _save_load_dialog_script: Script = null
var _save_load_dialog = null
var _context: String = ""
var _on_replay_selected: Callable = Callable()
var _pending_full_archive_request_id: String = ""
var _pending_full_archive_payload: Dictionary = {}
var _pending_full_archive_error: String = ""
var _external_save_in_flight: bool = false

func _init(scene, save_load_dialog_script: Script, on_replay_selected: Callable) -> void:
	_scene = scene
	_save_load_dialog_script = save_load_dialog_script
	_on_replay_selected = on_replay_selected

func open_for_save(engine: GameEngine, title: String = "保存游戏") -> void:
	if engine == null:
		GameLog.warn("Game", "游戏引擎未初始化，无法打开存档对话框")
		return
	_ensure_dialog()
	_context = "save"
	if _save_load_dialog != null and is_instance_valid(_save_load_dialog):
		_save_load_dialog.open_for_save(engine, title, _should_use_server_full_archive_export())

func open_for_replay() -> void:
	# 产品约束：游戏内禁用“载入/回放文件”，仅允许主菜单载入。
	_context = ""
	GameLog.info("Game", "游戏内载入已禁用（仅主菜单可载入）")

func _ensure_dialog() -> void:
	if _save_load_dialog != null and is_instance_valid(_save_load_dialog):
		_bind_net_signals()
		return
	if _scene == null:
		return
	if _save_load_dialog_script == null:
		return

	_save_load_dialog = _save_load_dialog_script.new()
	_scene.add_child(_save_load_dialog)

	if _save_load_dialog.has_signal("load_selected"):
		if not _save_load_dialog.load_selected.is_connected(_on_save_load_selected):
			_save_load_dialog.load_selected.connect(_on_save_load_selected)
	if _save_load_dialog.has_signal("save_completed"):
		if not _save_load_dialog.save_completed.is_connected(_on_save_completed):
			_save_load_dialog.save_completed.connect(_on_save_completed)
	if _save_load_dialog.has_signal("external_save_requested"):
		if not _save_load_dialog.external_save_requested.is_connected(_on_external_save_requested):
			_save_load_dialog.external_save_requested.connect(_on_external_save_requested)
	_bind_net_signals()

func dispose() -> void:
	_unbind_net_signals()
	if _save_load_dialog != null and is_instance_valid(_save_load_dialog):
		if _save_load_dialog.has_signal("load_selected") and _save_load_dialog.load_selected.is_connected(_on_save_load_selected):
			_save_load_dialog.load_selected.disconnect(_on_save_load_selected)
		if _save_load_dialog.has_signal("save_completed") and _save_load_dialog.save_completed.is_connected(_on_save_completed):
			_save_load_dialog.save_completed.disconnect(_on_save_completed)
		if _save_load_dialog.has_signal("external_save_requested") and _save_load_dialog.external_save_requested.is_connected(_on_external_save_requested):
			_save_load_dialog.external_save_requested.disconnect(_on_external_save_requested)
	_save_load_dialog = null

func _on_save_load_selected(path: String) -> void:
	if path.is_empty():
		return

	if _context == "replay":
		var cb := _on_replay_selected
		if cb.is_valid():
			cb.call(path)
		return

	# 预留：未来可支持“游戏内载入存档”
	GameLog.warn("Game", "未支持的存档载入上下文: %s (%s)" % [_context, path])

func _on_save_completed(path: String) -> void:
	if path.is_empty():
		return
	GameLog.info("Game", "存档已保存: %s" % path)

func _on_external_save_requested(target: Dictionary) -> void:
	if _context != "save":
		return
	if _external_save_in_flight:
		return
	if not _should_use_server_full_archive_export():
		if _save_load_dialog != null and is_instance_valid(_save_load_dialog) and _save_load_dialog.has_method("finish_external_save_error"):
			_save_load_dialog.finish_external_save_error("当前导出模式不可用")
		return
	_external_save_in_flight = true
	var export_r: Result = await _request_full_archive_export_from_server()
	if not export_r.ok:
		_external_save_in_flight = false
		if _save_load_dialog != null and is_instance_valid(_save_load_dialog) and _save_load_dialog.has_method("finish_external_save_error"):
			_save_load_dialog.finish_external_save_error("导出失败: %s" % export_r.error)
		return
	var archive: Dictionary = Dictionary(export_r.value).duplicate(true)
	var write_r: Result = _write_archive_to_target(archive, target)
	_external_save_in_flight = false
	if not write_r.ok:
		if _save_load_dialog != null and is_instance_valid(_save_load_dialog) and _save_load_dialog.has_method("finish_external_save_error"):
			_save_load_dialog.finish_external_save_error("保存失败: %s" % write_r.error)
		return
	var saved_path := str(write_r.value)
	if _save_load_dialog != null and is_instance_valid(_save_load_dialog) and _save_load_dialog.has_method("finish_external_save_success"):
		_save_load_dialog.finish_external_save_success(saved_path)

func _should_use_server_full_archive_export() -> bool:
	if NetContext == null or NetClient == null:
		return false
	if NetContext.mode != NetContext.Mode.ONLINE_CLIENT:
		return false
	if str(NetContext.room_state.get("room_mode", "")).strip_edges() != "resume_archive":
		return false
	return true

func _bind_net_signals() -> void:
	if NetClient == null:
		return
	if NetClient.has_signal("full_archive_export_ready") and not NetClient.full_archive_export_ready.is_connected(_on_full_archive_export_ready):
		NetClient.full_archive_export_ready.connect(_on_full_archive_export_ready)
	if NetClient.has_signal("request_rejected") and not NetClient.request_rejected.is_connected(_on_request_rejected):
		NetClient.request_rejected.connect(_on_request_rejected)

func _unbind_net_signals() -> void:
	if NetClient == null:
		return
	if NetClient.has_signal("full_archive_export_ready") and NetClient.full_archive_export_ready.is_connected(_on_full_archive_export_ready):
		NetClient.full_archive_export_ready.disconnect(_on_full_archive_export_ready)
	if NetClient.has_signal("request_rejected") and NetClient.request_rejected.is_connected(_on_request_rejected):
		NetClient.request_rejected.disconnect(_on_request_rejected)

func _request_full_archive_export_from_server() -> Result:
	if NetClient == null:
		return Result.failure("NetClient autoload missing")
	if not NetClient.has_method("request_full_archive_export"):
		return Result.failure("NetClient.request_full_archive_export missing")
	var request_id := str(NetClient.request_full_archive_export()).strip_edges()
	if request_id.is_empty():
		return Result.failure("request_id 为空")
	_pending_full_archive_request_id = request_id
	_pending_full_archive_payload = {}
	_pending_full_archive_error = ""
	var deadline := Time.get_ticks_msec() + 10000
	while Time.get_ticks_msec() <= deadline:
		if not _pending_full_archive_payload.is_empty():
			var payload: Dictionary = _pending_full_archive_payload.duplicate(true)
			_pending_full_archive_request_id = ""
			_pending_full_archive_payload = {}
			_pending_full_archive_error = ""
			return Result.success(Dictionary(payload.get("archive", {})).duplicate(true))
		if not _pending_full_archive_error.is_empty():
			var err := _pending_full_archive_error
			_pending_full_archive_request_id = ""
			_pending_full_archive_payload = {}
			_pending_full_archive_error = ""
			return Result.failure(err)
		if _scene == null or not is_instance_valid(_scene):
			break
		await _scene.get_tree().process_frame
	_pending_full_archive_request_id = ""
	_pending_full_archive_payload = {}
	_pending_full_archive_error = ""
	return Result.failure("等待服务端完整存档导出超时")

func _write_archive_to_target(archive: Dictionary, target: Dictionary) -> Result:
	var kind := str(target.get("target_kind", "")).strip_edges()
	if kind == "web_download":
		var file_name := str(target.get("file_name", "")).strip_edges()
		if file_name.is_empty():
			return Result.failure("文件名为空")
		var json := JSON.stringify(archive, "\t")
		var bytes: PackedByteArray = json.to_utf8_buffer()
		JavaScriptBridge.download_buffer(bytes, file_name, "application/json")
		return Result.success(file_name)
	var path := str(target.get("path", "")).strip_edges()
	if path.is_empty():
		return Result.failure("保存路径为空")
	return ArchiveClass.save_archive_to_file(archive, path)

func _on_full_archive_export_ready(payload: Dictionary) -> void:
	if _pending_full_archive_request_id.is_empty():
		return
	if str(payload.get("request_id", "")).strip_edges() != _pending_full_archive_request_id:
		return
	_pending_full_archive_payload = Dictionary(payload).duplicate(true)

func _on_request_rejected(request_id: String, code: String, message: String) -> void:
	if _pending_full_archive_request_id.is_empty():
		return
	if str(request_id).strip_edges() != _pending_full_archive_request_id:
		return
	_pending_full_archive_error = "%s: %s" % [str(code), str(message)]
