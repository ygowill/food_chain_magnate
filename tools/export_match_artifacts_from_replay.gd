extends SceneTree

const ResultClass = preload("res://core/types/result.gd")
const ArchiveClass = preload("res://core/engine/game_engine/archive.gd")
const GameEngineClass = preload("res://core/engine/game_engine.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const MapSnapshotRendererClass = preload("res://server/map_snapshot_renderer.gd")

const NAME := "BackfillMatchArtifacts"
const SNAPSHOT_KIND_ROUND_END := "round_end"
const SNAPSHOT_KIND_GAME_OVER := "game_over"
const LATEST_AUTOSAVE_FILENAME := "latest_autosave.json"
const MANIFEST_FILENAME := "manifest.json"

func _initialize() -> void:
	var args := _parse_args()
	var run_r = _run(args)
	if run_r.ok:
		var manifest: Dictionary = Dictionary(run_r.value) if run_r.value is Dictionary else {}
		print(
			"[%s] BACKFILL_EXPORT_OK manifest=%s snapshots=%d"
			% [NAME, str(manifest.get("manifest_path", "")), int(manifest.get("map_snapshot_count", 0))]
		)
		quit(0)
		return

	push_error("[%s] BACKFILL_EXPORT_FAIL %s" % [NAME, str(run_r.error)])
	quit(1)

static func _parse_args() -> Dictionary:
	var parsed := {}
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		var arg := str(args[i])
		if not arg.begins_with("--"):
			i += 1
			continue
		var body := arg.substr(2)
		var eq := body.find("=")
		if eq >= 0:
			parsed[body.substr(0, eq)] = body.substr(eq + 1)
			i += 1
			continue
		if i + 1 < args.size() and not str(args[i + 1]).begins_with("--"):
			parsed[body] = str(args[i + 1])
			i += 2
			continue
		parsed[body] = true
		i += 1
	return parsed

static func _run(args: Dictionary):
	var replay_file := _require_arg(args, "replay-file")
	if replay_file.is_empty():
		return ResultClass.failure("--replay-file 不能为空")
	var output_dir := _require_arg(args, "output-dir")
	if output_dir.is_empty():
		return ResultClass.failure("--output-dir 不能为空")
	var room_code := _normalize_room_code(_require_arg(args, "room-code"))
	if room_code.is_empty():
		return ResultClass.failure("--room-code 不能为空")
	var match_id := _require_arg(args, "match-id")

	var replay_path := _absolute_path(replay_file)
	if not FileAccess.file_exists(replay_path):
		return ResultClass.failure("replay 文件不存在: %s" % replay_path)
	var output_dir_abs := _absolute_path(output_dir)
	var mkdir_err := DirAccess.make_dir_recursive_absolute(output_dir_abs)
	if mkdir_err != OK:
		return ResultClass.failure("无法创建输出目录: %s err=%d" % [output_dir_abs, mkdir_err])

	var archive_r = ArchiveClass.load_archive_from_file(replay_path)
	if not archive_r.ok:
		return ResultClass.failure("读取 replay 失败: %s" % archive_r.error)
	var archive: Dictionary = Dictionary(archive_r.value).duplicate(true)

	var engine = GameEngineClass.new()
	var load_r = engine.load_from_archive(archive)
	if not load_r.ok:
		engine.dispose()
		return ResultClass.failure("加载 replay 失败: %s" % load_r.error)

	var snapshot_items_r = _export_map_snapshots(engine, output_dir_abs)
	if not snapshot_items_r.ok:
		engine.dispose()
		return snapshot_items_r
	var map_snapshots: Array[Dictionary] = snapshot_items_r.value

	var latest_r = _export_latest_autosave(engine, output_dir_abs, room_code)
	if not latest_r.ok:
		engine.dispose()
		return latest_r
	var latest_save: Dictionary = Dictionary(latest_r.value)

	var manifest_path := output_dir_abs.path_join(MANIFEST_FILENAME)
	var manifest := {
		"ok": true,
		"match_id": match_id,
		"room_code": room_code,
		"replay_file": replay_path,
		"output_dir": output_dir_abs,
		"latest_save": latest_save,
		"map_snapshots": map_snapshots,
		"map_snapshot_count": map_snapshots.size(),
		"manifest_path": manifest_path,
	}
	var write_manifest_r = _write_json(manifest_path, manifest)
	engine.dispose()
	if not write_manifest_r.ok:
		return write_manifest_r
	return ResultClass.success(manifest)

static func _export_map_snapshots(engine, output_dir_abs: String):
	var command_history: Array = engine.get_command_history()
	var max_index := mini(int(engine.current_command_index), command_history.size() - 1)
	var snapshots_dir := output_dir_abs.path_join("map_snapshots")
	var mkdir_err := DirAccess.make_dir_recursive_absolute(snapshots_dir)
	if mkdir_err != OK:
		return ResultClass.failure("无法创建截图目录: %s err=%d" % [snapshots_dir, mkdir_err])

	var out: Array[Dictionary] = []
	var seen := {}
	for i in range(max_index + 1):
		var rewind_r = engine.rewind_to_command(i)
		if not rewind_r.ok:
			return ResultClass.failure("回放到命令 #%d 失败: %s" % [i, rewind_r.error])
		var state = engine.get_state()
		var cmd = command_history[i]
		var event := _snapshot_event_for_state_after_command(cmd, state)
		if event.is_empty():
			continue
		var round_number := int(event.get("round_number", 0))
		var snapshot_kind := str(event.get("snapshot_kind", ""))
		var key := "%d:%s" % [round_number, snapshot_kind]
		if seen.has(key):
			continue
		seen[key] = true
		var snapshot_r = _write_map_snapshot(state, snapshots_dir, round_number, snapshot_kind)
		if not snapshot_r.ok:
			return snapshot_r
		out.append(Dictionary(snapshot_r.value))
	return ResultClass.success(out)

static func _export_latest_autosave(engine, output_dir_abs: String, room_code: String):
	var final_index := int(engine.current_command_index)
	var command_history: Array = engine.get_command_history()
	if not command_history.is_empty():
		final_index = mini(command_history.size() - 1, maxi(final_index, -1))
		var rewind_r = engine.rewind_to_command(final_index)
		if not rewind_r.ok:
			return ResultClass.failure("回放到最终命令 #%d 失败: %s" % [final_index, rewind_r.error])

	var state = engine.get_state()
	if state == null:
		return ResultClass.failure("最终状态为空")
	var final_cmd = command_history[final_index] if final_index >= 0 and final_index < command_history.size() else null
	var event := _snapshot_event_for_state_after_command(final_cmd, state)
	if event.is_empty():
		event = _fallback_final_snapshot_event(final_cmd, state)

	var archive_r = engine.create_archive()
	if not archive_r.ok:
		return ResultClass.failure("创建最新存档失败: %s" % archive_r.error)
	var archive: Dictionary = Dictionary(archive_r.value).duplicate(true)
	var state_hash: String = str(state.compute_hash())
	var saved_at: String = Time.get_datetime_string_from_system()
	var meta: Dictionary = ArchiveClass.get_online_resume_meta(archive)
	meta["version"] = ArchiveClass.ONLINE_RESUME_META_VERSION
	meta["round_autosave"] = {
		"version": 1,
		"room_code": room_code,
		"completed_round_number": int(event.get("round_number", 0)),
		"snapshot_kind": str(event.get("snapshot_kind", SNAPSHOT_KIND_ROUND_END)),
		"state_hash": state_hash,
		"saved_at": saved_at,
		"saved_at_unix_sec": int(Time.get_unix_time_from_system()),
		"backfilled": true,
	}
	archive = ArchiveClass.with_online_resume_meta(archive, meta)

	var path := output_dir_abs.path_join(LATEST_AUTOSAVE_FILENAME)
	var json_text := JSON.stringify(archive, "\t")
	var bytes := json_text.to_utf8_buffer()
	var write_r = _write_bytes(path, bytes)
	if not write_r.ok:
		return write_r

	return ResultClass.success({
		"artifact_type": "autosave_latest",
		"snapshot_kind": str(event.get("snapshot_kind", SNAPSHOT_KIND_ROUND_END)),
		"round_number": int(event.get("round_number", 0)),
		"state_hash": state_hash,
		"filename": LATEST_AUTOSAVE_FILENAME,
		"path": path,
		"mime_type": "application/json",
		"checksum": _sha256_hex(bytes),
		"size_bytes": bytes.size(),
	})

static func _write_map_snapshot(state, snapshots_dir: String, round_number: int, snapshot_kind: String):
	var render_r = MapSnapshotRendererClass.render_state_png(state)
	if not render_r.ok:
		return ResultClass.failure("渲染地图截图失败 round=%d kind=%s: %s" % [round_number, snapshot_kind, render_r.error])
	var render_info: Dictionary = Dictionary(render_r.value) if render_r.value is Dictionary else {}
	var png_bytes := PackedByteArray(render_info.get("png_bytes", PackedByteArray()))
	if png_bytes.is_empty():
		return ResultClass.failure("渲染地图截图为空 round=%d kind=%s" % [round_number, snapshot_kind])
	var filename := "round_%04d_%s.png" % [maxi(0, round_number), snapshot_kind]
	var path := snapshots_dir.path_join(filename)
	var write_r = _write_bytes(path, png_bytes)
	if not write_r.ok:
		return write_r
	return ResultClass.success({
		"artifact_type": "map_snapshot",
		"snapshot_kind": snapshot_kind,
		"round_number": maxi(0, round_number),
		"state_hash": state.compute_hash(),
		"filename": filename,
		"path": path,
		"mime_type": "image/png",
		"checksum": _sha256_hex(png_bytes),
		"size_bytes": png_bytes.size(),
		"width": int(render_info.get("width", 0)),
		"height": int(render_info.get("height", 0)),
	})

static func _snapshot_event_for_state_after_command(cmd, state) -> Dictionary:
	if state == null:
		return {}
	if str(state.phase) == DefsClass.PHASE_GAME_OVER:
		var final_round_number := int(state.round_number)
		if cmd != null and str(cmd.phase) == DefsClass.PHASE_CLEANUP and final_round_number > 1:
			final_round_number -= 1
		if final_round_number <= 0:
			final_round_number = 1
		return {
			"round_number": final_round_number,
			"snapshot_kind": SNAPSHOT_KIND_GAME_OVER,
		}
	if cmd == null or str(cmd.phase) != DefsClass.PHASE_CLEANUP:
		return {}
	if str(state.phase) != DefsClass.PHASE_RESTRUCTURING:
		return {}
	var completed_round_number := int(state.round_number) - 1
	if completed_round_number <= 0:
		return {}
	return {
		"round_number": completed_round_number,
		"snapshot_kind": SNAPSHOT_KIND_ROUND_END,
	}

static func _fallback_final_snapshot_event(cmd, state) -> Dictionary:
	if state == null:
		return {
			"round_number": 0,
			"snapshot_kind": SNAPSHOT_KIND_ROUND_END,
		}
	var kind := SNAPSHOT_KIND_GAME_OVER if str(state.phase) == DefsClass.PHASE_GAME_OVER else SNAPSHOT_KIND_ROUND_END
	var round_number := int(state.round_number)
	if kind == SNAPSHOT_KIND_GAME_OVER and cmd != null and str(cmd.phase) == DefsClass.PHASE_CLEANUP and round_number > 1:
		round_number -= 1
	elif kind == SNAPSHOT_KIND_ROUND_END and str(state.phase) == DefsClass.PHASE_RESTRUCTURING and round_number > 1:
		round_number -= 1
	if round_number <= 0:
		round_number = 1
	return {
		"round_number": round_number,
		"snapshot_kind": kind,
	}

static func _write_json(path: String, data: Dictionary):
	var text := JSON.stringify(data, "\t")
	return _write_bytes(path, text.to_utf8_buffer())

static func _write_bytes(path: String, bytes: PackedByteArray):
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return ResultClass.failure("无法写入文件: %s err=%d" % [path, FileAccess.get_open_error()])
	file.store_buffer(bytes)
	file.close()
	return ResultClass.success(path)

static func _sha256_hex(bytes: PackedByteArray) -> String:
	var ctx := HashingContext.new()
	var start_err := ctx.start(HashingContext.HASH_SHA256)
	if start_err != OK:
		return ""
	ctx.update(bytes)
	return ctx.finish().hex_encode()

static func _require_arg(args: Dictionary, name: String) -> String:
	return str(args.get(name, "")).strip_edges()

static func _absolute_path(path: String) -> String:
	var s := str(path).strip_edges()
	if s.begins_with("res://") or s.begins_with("user://"):
		return ProjectSettings.globalize_path(s)
	return s

static func _normalize_room_code(value: String) -> String:
	var s := str(value).strip_edges().to_upper()
	var out := ""
	for i in range(s.length()):
		var c := s.substr(i, 1)
		if (c >= "A" and c <= "Z") or (c >= "0" and c <= "9") or c == "_" or c == "-":
			out += c
	return out
