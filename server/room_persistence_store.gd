class_name RoomPersistenceStore
extends RefCounted

const OnlinePerfTraceClass = preload("res://core/debug/online_perf_trace.gd")
const SNAPSHOT_VERSION := 1

var _snapshot_path := "user://dedicated_server/online_room_snapshots.json"

func _init(snapshot_path: String = "user://dedicated_server/online_room_snapshots.json") -> void:
	var path := str(snapshot_path).strip_edges()
	if not path.is_empty():
		_snapshot_path = path

func get_snapshot_path() -> String:
	return _snapshot_path

func load_snapshot() -> Result:
	if not FileAccess.file_exists(_snapshot_path):
		return Result.success(_empty_snapshot())

	var file := FileAccess.open(_snapshot_path, FileAccess.READ)
	if file == null:
		return Result.failure("打开快照失败: %s" % _snapshot_path)
	var text := file.get_as_text()
	file.close()

	if text.strip_edges().is_empty():
		return Result.success(_empty_snapshot())

	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		return Result.failure("快照 JSON 根节点类型错误（期望 Dictionary）")

	var snapshot := Dictionary(_normalize_json_numbers(parsed))
	var version := int(snapshot.get("version", 0))
	if version != SNAPSHOT_VERSION:
		return Result.failure("不支持的房间快照版本: %d" % version)

	var rooms_val = snapshot.get("rooms", null)
	if not (rooms_val is Array):
		return Result.failure("快照 rooms 类型错误（期望 Array）")

	return Result.success(snapshot.duplicate(true))

func save_room_manager(room_manager) -> Result:
	if room_manager == null or not room_manager.has_method("create_persistence_snapshot"):
		return Result.failure("RoomManager 持久化接口缺失")

	var snapshot_r: Result = room_manager.create_persistence_snapshot()
	if not snapshot_r.ok:
		return snapshot_r

	var snapshot: Dictionary = Dictionary(snapshot_r.value).duplicate(true)
	snapshot["version"] = SNAPSHOT_VERSION
	return save_snapshot(snapshot)

func save_snapshot(snapshot: Dictionary) -> Result:
	var abs_path := ProjectSettings.globalize_path(_snapshot_path)
	var abs_dir := abs_path.get_base_dir()
	var room_count := Array(snapshot.get("rooms", [])).size() if snapshot.get("rooms", null) is Array else 0
	var mkdir_err := DirAccess.make_dir_recursive_absolute(abs_dir)
	if mkdir_err != OK:
		return Result.failure("创建快照目录失败: %s err=%s" % [abs_dir, str(mkdir_err)])

	var stringify_span := OnlinePerfTraceClass.begin_span("server.persistence.snapshot.stringify", {
		"room_count": room_count,
		"path": _snapshot_path,
	})
	var json_text := JSON.stringify(snapshot, "\t")
	var json_bytes := json_text.to_utf8_buffer().size()
	OnlinePerfTraceClass.end_span(stringify_span, {
		"room_count": room_count,
		"path": _snapshot_path,
		"json_bytes": json_bytes,
	})

	var write_span := OnlinePerfTraceClass.begin_span("server.persistence.snapshot.write", {
		"room_count": room_count,
		"path": _snapshot_path,
		"json_bytes": json_bytes,
	})
	var file := FileAccess.open(_snapshot_path, FileAccess.WRITE)
	if file == null:
		OnlinePerfTraceClass.end_span(write_span, {
			"ok": false,
			"error": "写入快照失败",
			"path": _snapshot_path,
			"room_count": room_count,
			"json_bytes": json_bytes,
		})
		return Result.failure("写入快照失败: %s" % _snapshot_path)
	file.store_string(json_text)
	file.close()
	OnlinePerfTraceClass.end_span(write_span, {
		"ok": true,
		"path": _snapshot_path,
		"room_count": room_count,
		"json_bytes": json_bytes,
	})

	return Result.success({
		"path": abs_path,
		"room_count": room_count,
		"json_bytes": json_bytes,
	})

func _empty_snapshot() -> Dictionary:
	return {
		"version": SNAPSHOT_VERSION,
		"saved_at_unix_sec": 0,
		"rooms": [],
	}

func _normalize_json_numbers(value):
	match typeof(value):
		TYPE_DICTIONARY:
			var out := {}
			for k in value.keys():
				out[k] = _normalize_json_numbers(value[k])
			return out
		TYPE_ARRAY:
			var out_arr := []
			for item in value:
				out_arr.append(_normalize_json_numbers(item))
			return out_arr
		TYPE_FLOAT:
			var f: float = float(value)
			if f == floor(f) and f >= -9223372036854775808.0 and f <= 9223372036854775807.0:
				return int(f)
			return f
		_:
			return value
