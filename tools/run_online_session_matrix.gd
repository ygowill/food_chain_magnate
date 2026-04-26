# 联机会话场景矩阵（Headless）
# 用途：按用户可感知场景分组运行本地联机恢复 / 断线 / 主动退出 / 目录清理相关测试，
# 方便在部署前快速验证某一类问题是否回归。
extends SceneTree

const ResultClass = preload("res://core/types/result.gd")
const NAME := "OnlineSessionMatrix"

const GROUP_ORDER: Array[String] = [
	"resume",
	"lobby",
	"ingame",
	"resync",
	"persistence",
]

const GROUPS := {
	"resume": {
		"title": "Resume Basics",
		"tests": [
			{
				"name": "NetContextOnlineResumeTest",
				"scenario": "resume_context_basics",
				"path": "res://core/tests/net_context_online_resume_test.gd",
			},
			{
				"name": "NetContextOnlineResumePersistenceTest",
				"scenario": "resume_context_persistence",
				"path": "res://core/tests/net_context_online_resume_persistence_test.gd",
			},
			{
				"name": "NetClientConnectPreserveContextTest",
				"scenario": "connect_preserve_context",
				"path": "res://core/tests/net_client_connect_preserve_context_test.gd",
			},
			{
				"name": "OnlineResumeErrorPolicyTest",
				"scenario": "terminal_vs_retryable_resume_errors",
				"path": "res://core/tests/online_resume_error_policy_test.gd",
			},
			{
				"name": "OnlineClientDisconnectPreserveContextTest",
				"scenario": "disconnect_preserve_resume_context",
				"path": "res://core/tests/online_client_disconnect_preserve_context_test.gd",
			},
		],
	},
	"lobby": {
		"title": "Lobby Lifecycle",
		"tests": [
			{
				"name": "PlatformConnectTokenAutoJoinTest",
				"scenario": "auto_join_and_takeover",
				"path": "res://core/tests/platform_connect_token_auto_join_test.gd",
			},
			{
				"name": "OnlineRoomListTest",
				"scenario": "room_directory_counts",
				"path": "res://core/tests/online_room_list_test.gd",
			},
			{
				"name": "OnlineLobbyDisconnectReclaimTest",
				"scenario": "lobby_disconnect_reclaim",
				"path": "res://core/tests/online_lobby_disconnect_reclaim_test.gd",
			},
			{
				"name": "OnlineLobbyDisconnectGraceReleaseTest",
				"scenario": "lobby_disconnect_grace_release",
				"path": "res://core/tests/online_lobby_disconnect_grace_release_test.gd",
			},
			{
				"name": "OnlineLobbyResumeControllerTest",
				"scenario": "lobby_cold_start_resume",
				"path": "res://core/tests/online_lobby_resume_controller_test.gd",
			},
			{
				"name": "OnlineLobbyPersistenceRecoveryTest",
				"scenario": "lobby_server_restart_recovery",
				"path": "res://core/tests/online_lobby_persistence_recovery_test.gd",
			},
		],
	},
	"ingame": {
		"title": "InGame Lifecycle",
		"tests": [
			{
				"name": "OnlineDisconnectGraceReconnectTest",
				"scenario": "ingame_disconnect_reconnect_within_grace",
				"path": "res://core/tests/online_disconnect_grace_reconnect_test.gd",
			},
			{
				"name": "OnlineInGameLastPeerDisconnectRecoveryTest",
				"scenario": "all_peers_disconnect_then_recover",
				"path": "res://core/tests/online_in_game_last_peer_disconnect_recovery_test.gd",
			},
			{
				"name": "OnlineForfeitAndLeaveRoomTest",
				"scenario": "server_forfeit_and_leave",
				"path": "res://core/tests/online_forfeit_and_leave_room_test.gd",
			},
			{
				"name": "GameMenuDebugControllerOnlineSurrenderQuitTest",
				"scenario": "client_immediate_surrender_to_menu",
				"path": "res://core/tests/game_menu_debug_controller_online_surrender_quit_test.gd",
			},
			{
				"name": "OnlineClientGameStartedReconnectTest",
				"scenario": "reuse_existing_engine_on_reconnect",
				"path": "res://core/tests/online_client_game_started_reconnect_test.gd",
			},
			{
				"name": "GameStartupDirectResumeGuardTest",
				"scenario": "startup_resume_gatekeeping",
				"path": "res://core/tests/game_startup_direct_resume_guard_test.gd",
			},
			{
				"name": "GameStartupOnlineResumeControllerTest",
				"scenario": "cold_start_resume_to_game",
				"path": "res://core/tests/game_startup_online_resume_controller_test.gd",
			},
		],
	},
	"resync": {
		"title": "Resync Protocol",
		"tests": [
			{
				"name": "ServerResyncGuardTest",
				"scenario": "delta_snapshot_guardrails",
				"path": "res://core/tests/server_resync_guard_test.gd",
			},
			{
				"name": "OnlineClientResyncSnapshotChunkTest",
				"scenario": "snapshot_chunk_assemble",
				"path": "res://core/tests/online_client_resync_snapshot_chunk_test.gd",
			},
			{
				"name": "OnlineClientResyncDeltaApplyTest",
				"scenario": "delta_apply_to_existing_engine",
				"path": "res://core/tests/online_client_resync_delta_apply_test.gd",
			},
			{
				"name": "OnlineClientResyncRoomIsolationTest",
				"scenario": "ignore_stale_cross_room_resync_payloads",
				"path": "res://core/tests/online_client_resync_room_isolation_test.gd",
			},
			{
				"name": "GameOnlineResumeProgressSyncTest",
				"scenario": "resume_cursor_sync_after_live_and_snapshot_restore",
				"path": "res://core/tests/game_online_resume_progress_sync_test.gd",
			},
			{
				"name": "GameOnlineResyncReconnectFlowTest",
				"scenario": "in_scene_reconnect_restore_flow",
				"path": "res://core/tests/game_online_resync_reconnect_flow_test.gd",
			},
			{
				"name": "GameOnlineResyncRequestRejectionTest",
				"scenario": "resync_rejection_and_force_snapshot_fallback",
				"path": "res://core/tests/game_online_resync_request_rejection_test.gd",
			},
		],
	},
	"persistence": {
		"title": "Server Persistence",
		"tests": [
			{
				"name": "OnlineRoomPersistenceRecoveryTest",
				"scenario": "ingame_room_persistence_recovery",
				"path": "res://core/tests/online_room_persistence_recovery_test.gd",
			},
			{
				"name": "OnlineRoundAutosaveTest",
				"scenario": "round_end_server_autosave",
				"path": "res://core/tests/online_round_autosave_test.gd",
			},
			{
				"name": "OnlineLobbyPersistenceRecoveryTest",
				"scenario": "lobby_room_persistence_recovery",
				"path": "res://core/tests/online_lobby_persistence_recovery_test.gd",
			},
			{
				"name": "ServerIdentityStoreTest",
				"scenario": "stable_server_identity_across_restart",
				"path": "res://core/tests/server_identity_store_test.gd",
			},
		],
	},
}

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var options := _parse_args(OS.get_cmdline_user_args())
	if bool(options.get("list_only", false)):
		_print_group_list()
		quit(0)
		return

	var selected_groups: Array[String] = []
	var groups_csv := str(options.get("groups_csv", "")).strip_edges()
	for item in groups_csv.split(",", false):
		var normalized := str(item).strip_edges()
		if normalized.is_empty():
			continue
		selected_groups.append(normalized)
	if selected_groups.is_empty():
		push_error("[%s] FAIL no groups selected" % NAME)
		quit(1)
		return

	print("[%s] START groups=%s" % [NAME, str(selected_groups)])
	var total_start := Time.get_ticks_msec()
	var total_cases := 0
	var passed := 0
	var failed: Array[String] = []

	for group_name in selected_groups:
		var group_def_val = GROUPS.get(group_name, null)
		if not (group_def_val is Dictionary):
			failed.append("group:%s" % group_name)
			push_error("[%s] FAIL unknown group=%s" % [NAME, group_name])
			continue
		var group_def: Dictionary = Dictionary(group_def_val)
		var tests: Array = Array(group_def.get("tests", []))
		print(
			"[%s] GROUP %s title=%s total=%d"
				% [
					NAME,
					group_name,
					str(group_def.get("title", group_name)),
					tests.size(),
				]
		)

		for test_def_val in tests:
			var test_def: Dictionary = Dictionary(test_def_val)
			var name := str(test_def.get("name", "UnknownTest"))
			var scenario := str(test_def.get("scenario", "")).strip_edges()
			var path := str(test_def.get("path", "")).strip_edges()
			total_cases += 1
			print("[%s] RUN group=%s scenario=%s test=%s" % [NAME, group_name, scenario, name])

			var test_script = load(path)
			if test_script == null:
				failed.append("%s/%s" % [group_name, name])
				push_error("[%s] FAIL %s/%s: load 失败 path=%s" % [NAME, group_name, name, path])
				await _cleanup_runtime_between_tests()
				continue
			if not test_script.has_method("run"):
				failed.append("%s/%s" % [group_name, name])
				push_error("[%s] FAIL %s/%s: 缺少 run()" % [NAME, group_name, name])
				await _cleanup_runtime_between_tests()
				continue

			var start := Time.get_ticks_msec()
			var call_result = await test_script.run()
			var result = call_result if (call_result is ResultClass) else ResultClass.failure("测试返回值类型错误（期望 Result）")
			var duration_ms := Time.get_ticks_msec() - start

			if result.ok:
				passed += 1
				print(
					"[%s] PASS group=%s scenario=%s test=%s (%dms)"
						% [NAME, group_name, scenario, name, duration_ms]
				)
			else:
				failed.append("%s/%s" % [group_name, name])
				push_error(
					"[%s] FAIL group=%s scenario=%s test=%s (%dms): %s"
						% [NAME, group_name, scenario, name, duration_ms, str(result.error)]
				)

			await _cleanup_runtime_between_tests()

	var total_ms := Time.get_ticks_msec() - total_start
	print("[%s] SUMMARY passed=%d/%d failed=%s total_ms=%d" % [NAME, passed, total_cases, str(failed), total_ms])
	quit(0 if failed.is_empty() else 1)

func _parse_args(args: Array) -> Dictionary:
	var selected_groups: Array = []
	var list_only := false

	for raw_arg in args:
		var arg := str(raw_arg).strip_edges()
		if arg.is_empty():
			continue
		if arg == "--list":
			list_only = true
			continue
		if arg.begins_with("--group="):
			var value := arg.substr("--group=".length())
			for part in value.split(",", false):
				var group_name := str(part).strip_edges()
				if group_name.is_empty():
					continue
				selected_groups.append(group_name)
			continue
		push_warning("[%s] WARN ignoring unknown arg: %s" % [NAME, arg])

	if selected_groups.is_empty():
		for default_group in GROUP_ORDER:
			selected_groups.append(str(default_group))

	var normalized_groups: Array = []
	for group_name in selected_groups:
		var normalized := str(group_name).strip_edges()
		if normalized == "all":
			for default_group in GROUP_ORDER:
				if not normalized_groups.has(default_group):
					normalized_groups.append(default_group)
			continue
		if not normalized_groups.has(normalized):
			normalized_groups.append(normalized)

	var groups_csv := ""
	for i in range(normalized_groups.size()):
		if i > 0:
			groups_csv += ","
		groups_csv += str(normalized_groups[i])

	return {
		"list_only": list_only,
		"groups_csv": groups_csv,
	}

func _print_group_list() -> void:
	print("[%s] GROUPS" % NAME)
	for group_name in GROUP_ORDER:
		var group_def: Dictionary = Dictionary(GROUPS.get(group_name, {}))
		var tests: Array = Array(group_def.get("tests", []))
		print(
			"[%s] GROUP name=%s title=%s total=%d"
				% [NAME, group_name, str(group_def.get("title", group_name)), tests.size()]
		)
		for test_def_val in tests:
			var test_def: Dictionary = Dictionary(test_def_val)
			print(
				"[%s] CASE group=%s scenario=%s test=%s"
					% [
						NAME,
						group_name,
						str(test_def.get("scenario", "")),
						str(test_def.get("name", "")),
					]
			)

func _cleanup_runtime_between_tests() -> void:
	var net_client = _get_autoload_node("NetClient")
	if net_client != null and net_client.has_method("shutdown"):
		net_client.shutdown()
	var event_bus = _get_autoload_node("EventBus")
	if event_bus != null:
		if event_bus.has_method("clear_all_subscribers"):
			event_bus.clear_all_subscribers()
		if event_bus.has_method("clear_history_and_reset_sequence"):
			event_bus.clear_history_and_reset_sequence()
		elif event_bus.has_method("clear_history"):
			event_bus.clear_history()
	var scene_manager = _get_autoload_node("SceneManager")
	if scene_manager != null and scene_manager.has_method("clear_stack"):
		scene_manager.clear_stack()
	var globals = _get_autoload_node("Globals")
	if globals != null and globals.has_method("reset_game_config"):
		globals.reset_game_config()
	await _drain_frames(2)

func _drain_frames(count: int) -> void:
	var n := maxi(1, int(count))
	for _i in range(n):
		await process_frame

func _get_autoload_node(name: String):
	var root := get_root()
	if root == null:
		return null
	return root.get_node_or_null(NodePath(str(name).strip_edges()))
