class_name OnlineRoundAutosaveTest
extends RefCounted

const ArchiveClass = preload("res://core/engine/game_engine/archive.gd")
const CommandClass = preload("res://core/types/command.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const GameDefaultsClass = preload("res://core/engine/game_defaults.gd")
const GameStateClass = preload("res://core/state/game_state.gd")
const MapSnapshotRendererClass = preload("res://server/map_snapshot_renderer.gd")
const NetClientServerLogicClass = preload("res://autoload/net_client/server.gd")
const RoomManagerClass = preload("res://server/room_manager.gd")
const RoomPersistenceStoreClass = preload("res://server/room_persistence_store.gd")

class FakeNet:
	extends RefCounted
	var calls: Array[Dictionary] = []

	func request_server_round_autosave(room_code: String, completed_round_number: int, state_hash: String = "", snapshot_kind: String = "round_end") -> void:
		calls.append({
			"room_code": str(room_code),
			"completed_round_number": int(completed_round_number),
			"state_hash": str(state_hash),
			"snapshot_kind": str(snapshot_kind),
		})

class FakeRoom:
	extends RefCounted
	var room_code: String = "AUTO01"

static func run() -> Result:
	var signal_r := _test_cleanup_to_restructuring_requests_round_autosave()
	if not signal_r.ok:
		return signal_r

	var game_over_r := _test_game_over_requests_final_round_snapshot()
	if not game_over_r.ok:
		return game_over_r

	var store_r := _test_round_autosave_store_writes_standard_archive_and_overwrites()
	if not store_r.ok:
		return store_r

	var render_r := _test_map_snapshot_renderer_outputs_png()
	if not render_r.ok:
		return render_r

	var terminal_export_r := _test_game_over_autosave_can_export_after_room_marked_ended()
	if not terminal_export_r.ok:
		return terminal_export_r

	return Result.success()

static func _test_cleanup_to_restructuring_requests_round_autosave() -> Result:
	var fake_net := FakeNet.new()
	var server_logic = NetClientServerLogicClass.new()
	server_logic.setup(fake_net)

	var room := FakeRoom.new()
	room.room_code = "auto01"
	var state := GameStateClass.new()
	state.phase = DefsClass.PHASE_RESTRUCTURING
	state.round_number = 3
	var cmd = CommandClass.create("skip", 0)
	cmd.phase = DefsClass.PHASE_CLEANUP

	server_logic._maybe_request_round_end_autosave(room, cmd, state, "hash_after_round")
	if fake_net.calls.size() != 1:
		return Result.failure("Cleanup -> Restructuring 应请求一次回合自动存档，实际: %d" % fake_net.calls.size())
	var call: Dictionary = fake_net.calls[0]
	if str(call.get("room_code", "")) != "AUTO01":
		return Result.failure("自动存档 room_code 应规范为大写，实际: %s" % str(call.get("room_code", "")))
	if int(call.get("completed_round_number", -1)) != 2:
		return Result.failure("completed_round_number 错误: %s" % str(call))
	if str(call.get("state_hash", "")) != "hash_after_round":
		return Result.failure("state_hash 未透传: %s" % str(call))
	if str(call.get("snapshot_kind", "")) != "round_end":
		return Result.failure("snapshot_kind 应为 round_end: %s" % str(call))

	var auto_settlement_cmd = CommandClass.create("skip", 0)
	auto_settlement_cmd.phase = DefsClass.PHASE_PAYDAY
	server_logic._maybe_request_round_end_autosave(room, auto_settlement_cmd, state, "hash_after_payday")
	if fake_net.calls.size() != 2:
		return Result.failure("自动结算阶段进入 Restructuring 时也应请求回合自动存档，实际: %d" % fake_net.calls.size())
	var auto_call: Dictionary = fake_net.calls[1]
	if int(auto_call.get("completed_round_number", -1)) != 2:
		return Result.failure("自动结算 completed_round_number 错误: %s" % str(auto_call))
	if str(auto_call.get("snapshot_kind", "")) != "round_end":
		return Result.failure("自动结算 snapshot_kind 应为 round_end: %s" % str(auto_call))

	var working_cmd = CommandClass.create("skip", 0)
	working_cmd.phase = DefsClass.PHASE_WORKING
	server_logic._maybe_request_round_end_autosave(room, working_cmd, state, "hash_after_working")
	if fake_net.calls.size() != 2:
		return Result.failure("非结算阶段进入 Restructuring 不应请求回合自动存档")

	return Result.success()

static func _test_game_over_requests_final_round_snapshot() -> Result:
	var fake_net := FakeNet.new()
	var server_logic = NetClientServerLogicClass.new()
	server_logic.setup(fake_net)

	var room := FakeRoom.new()
	room.room_code = "final01"
	var state := GameStateClass.new()
	state.phase = DefsClass.PHASE_GAME_OVER
	state.round_number = 5
	var cmd = CommandClass.create("skip", 0)
	cmd.phase = DefsClass.PHASE_CLEANUP

	server_logic._maybe_request_round_end_autosave(room, cmd, state, "hash_final")
	if fake_net.calls.size() != 1:
		return Result.failure("GameOver 应请求一次终局地图截图/存档，实际: %d" % fake_net.calls.size())
	var call: Dictionary = fake_net.calls[0]
	if str(call.get("room_code", "")) != "FINAL01":
		return Result.failure("终局自动存档 room_code 应规范为大写，实际: %s" % str(call.get("room_code", "")))
	if int(call.get("completed_round_number", -1)) != 4:
		return Result.failure("Cleanup 进入 GameOver 时 completed_round_number 应回退到已完成回合: %s" % str(call))
	if str(call.get("snapshot_kind", "")) != "game_over":
		return Result.failure("GameOver snapshot_kind 应为 game_over: %s" % str(call))
	if str(call.get("state_hash", "")) != "hash_final":
		return Result.failure("GameOver state_hash 未透传: %s" % str(call))
	return Result.success()

static func _test_map_snapshot_renderer_outputs_png() -> Result:
	var state := GameStateClass.new()
	state.map = {
		"grid_size": Vector2i(2, 2),
		"map_origin": Vector2i.ZERO,
		"cells": [
			[
				{"road_segments": [{"dir": "n"}]},
				{},
			],
			[
				{},
				{"blocked": true},
			],
		],
		"houses": {
			"1": {
				"anchor_pos": Vector2i(0, 1),
				"cells": [Vector2i(0, 1)],
				"has_garden": true,
			},
		},
		"restaurants": {
			"r1": {
				"owner": 1,
				"anchor_pos": Vector2i(1, 0),
				"cells": [Vector2i(1, 0)],
			},
		},
		"drink_sources": [
			{"world_pos": Vector2i(0, 0), "type": "soda"},
		],
		"marketing_placements": {
			"1": {
				"world_pos": Vector2i(1, 1),
				"footprint_size": Vector2i.ONE,
			},
		},
	}
	var render_r: Result = MapSnapshotRendererClass.render_state_png(state)
	if not render_r.ok:
		return Result.failure("MapSnapshotRenderer.render_state_png 失败: %s" % render_r.error)
	var info: Dictionary = Dictionary(render_r.value)
	if str(info.get("renderer", "")) != "map_snapshot_schematic":
		return Result.failure("服务端地图截图应使用独立 schematic renderer，实际 renderer=%s warnings=%s" % [str(info.get("renderer", "")), render_r.get_warnings_string()])
	var png_bytes: PackedByteArray = PackedByteArray(info.get("png_bytes", PackedByteArray()))
	if png_bytes.size() < 8:
		return Result.failure("地图截图 PNG 过小")
	var signature := png_bytes.slice(0, 8)
	if signature != PackedByteArray([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]):
		return Result.failure("地图截图 PNG 签名错误")

	var store := RoomPersistenceStoreClass.new(
		"user://online_round_autosave_render_test_snapshot.json",
		"user://online_round_autosave_render_test"
	)
	var save_r: Result = store.save_round_map_snapshot_png("render01", png_bytes, 2, "game_over")
	if not save_r.ok:
		return Result.failure("save_round_map_snapshot_png 失败: %s" % save_r.error)
	var png_path := str(store.get_round_map_snapshot_path("render01", 2, "game_over"))
	if not FileAccess.file_exists(png_path):
		return Result.failure("地图截图未写入: %s" % png_path)
	return Result.success()

static func _test_game_over_autosave_can_export_after_room_marked_ended() -> Result:
	var room_code := "TERM01"
	var rm := RoomManagerClass.new()
	var cfg := {
		"desired_player_count": 2,
		"seed_mode": "fixed",
		"seed": 12345,
		"allow_spectators": true,
		"enabled_modules_v2": [],
		"modules_v2_base_dir": GameDefaultsClass.DEFAULT_MODULES_V2_BASE_DIR,
	}
	var create_r: Result = rm.create_room_with_code(
		20,
		{"name": "Host", "color_index": 0, "restaurant_logo_id": -1, "user_id": "u_terminal_host"},
		room_code,
		cfg
	)
	if not create_r.ok:
		return Result.failure("terminal create_room_with_code 失败: %s" % create_r.error)
	var join_r: Result = rm.join_room(
		21,
		{"name": "Player2", "color_index": 1, "restaurant_logo_id": -1, "user_id": "u_terminal_p2"},
		room_code,
		""
	)
	if not join_r.ok:
		return Result.failure("terminal join_room 失败: %s" % join_r.error)

	var room = rm.rooms.get(room_code, null)
	if room == null:
		return Result.failure("terminal room missing after setup")
	var start_r: Result = room.start_game()
	if not start_r.ok:
		return Result.failure("terminal start_game 失败: %s" % start_r.error)
	var state = room.game_engine.get_state()
	if state == null:
		return Result.failure("terminal state missing after start")
	state.phase = DefsClass.PHASE_GAME_OVER
	room.status = "Ended"

	var strict_r: Result = room.build_full_authority_archive_export()
	if strict_r.ok:
		return Result.failure("Ended 房间的普通 full archive export 不应绕过状态门禁")

	var terminal_r: Result = room.build_full_authority_archive_export(true)
	if not terminal_r.ok:
		return Result.failure("终局自动截图应允许 Ended 房间导出 archive: %s" % terminal_r.error)
	var export_info: Dictionary = Dictionary(terminal_r.value) if terminal_r.value is Dictionary else {}
	if str(export_info.get("room_code", "")) != room_code:
		return Result.failure("terminal export room_code 错误: %s" % str(export_info))
	if not (export_info.get("archive", null) is Dictionary):
		return Result.failure("terminal export archive 类型错误: %s" % str(export_info))
	return Result.success()

static func _test_round_autosave_store_writes_standard_archive_and_overwrites() -> Result:
	var room_code := "RASV01"
	var rm := RoomManagerClass.new()
	var cfg := {
		"desired_player_count": 2,
		"seed_mode": "fixed",
		"seed": 12345,
		"allow_spectators": true,
		"enabled_modules_v2": [],
		"modules_v2_base_dir": GameDefaultsClass.DEFAULT_MODULES_V2_BASE_DIR,
	}
	var create_r: Result = rm.create_room_with_code(
		10,
		{"name": "Host", "color_index": 0, "restaurant_logo_id": -1, "user_id": "u_autosave_host"},
		room_code,
		cfg
	)
	if not create_r.ok:
		return Result.failure("create_room_with_code 失败: %s" % create_r.error)
	var join_r: Result = rm.join_room(
		11,
		{"name": "Player2", "color_index": 1, "restaurant_logo_id": -1, "user_id": "u_autosave_p2"},
		room_code,
		""
	)
	if not join_r.ok:
		return Result.failure("join_room 失败: %s" % join_r.error)

	var room = rm.rooms.get(room_code, null)
	if room == null:
		return Result.failure("room missing after setup")
	var start_r: Result = room.start_game()
	if not start_r.ok:
		return Result.failure("start_game 失败: %s" % start_r.error)
	var export_r: Result = room.build_full_authority_archive_export()
	if not export_r.ok:
		return Result.failure("build_full_authority_archive_export 失败: %s" % export_r.error)
	var export_info: Dictionary = Dictionary(export_r.value) if export_r.value is Dictionary else {}
	var archive_val = export_info.get("archive", null)
	if not (archive_val is Dictionary):
		return Result.failure("export archive 类型错误")
	var archive: Dictionary = Dictionary(archive_val).duplicate(true)

	var store := RoomPersistenceStoreClass.new(
		"user://online_round_autosave_test_snapshot.json",
		"user://online_round_autosave_test"
	)
	var save1: Result = store.save_round_autosave_archive(room_code, archive, 1, "hash_one")
	if not save1.ok:
		return Result.failure("save_round_autosave_archive #1 失败: %s" % save1.error)
	if str(Dictionary(save1.value).get("json_text", "")).strip_edges().is_empty():
		return Result.failure("save_round_autosave_archive 应返回 json_text 供服务端上传")
	var save_path := str(store.get_round_autosave_path(room_code))
	var load1: Result = ArchiveClass.load_archive_from_file(save_path)
	if not load1.ok:
		return Result.failure("读取回合自动存档 #1 失败: %s" % load1.error)
	var check1 := _assert_loaded_autosave_archive(Dictionary(load1.value), 1, "hash_one")
	if not check1.ok:
		return check1

	var save2: Result = store.save_round_autosave_archive(room_code, archive, 2, "hash_two")
	if not save2.ok:
		return Result.failure("save_round_autosave_archive #2 失败: %s" % save2.error)
	var load2: Result = ArchiveClass.load_archive_from_file(save_path)
	if not load2.ok:
		return Result.failure("读取回合自动存档 #2 失败: %s" % load2.error)
	var check2 := _assert_loaded_autosave_archive(Dictionary(load2.value), 2, "hash_two")
	if not check2.ok:
		return check2

	return Result.success()

static func _assert_loaded_autosave_archive(archive: Dictionary, completed_round_number: int, state_hash: String) -> Result:
	if not archive.has("schema_version"):
		return Result.failure("回合自动存档应保持标准 archive 根结构，缺少 schema_version")
	if not (archive.get("commands", null) is Array):
		return Result.failure("回合自动存档应保持标准 archive 根结构，缺少 commands")
	var meta: Dictionary = ArchiveClass.get_online_resume_meta(archive)
	var autosave_val = meta.get("round_autosave", null)
	if not (autosave_val is Dictionary):
		return Result.failure("online_resume_meta.round_autosave 缺失")
	var autosave: Dictionary = Dictionary(autosave_val)
	if int(autosave.get("completed_round_number", -1)) != int(completed_round_number):
		return Result.failure("completed_round_number 未覆盖更新: %s" % str(autosave))
	if str(autosave.get("state_hash", "")) != str(state_hash):
		return Result.failure("state_hash 未覆盖更新: %s" % str(autosave))
	if str(autosave.get("snapshot_kind", "")) != "round_end":
		return Result.failure("snapshot_kind 默认应为 round_end: %s" % str(autosave))
	return Result.success()
