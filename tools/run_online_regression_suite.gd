# 联机恢复专项回归套件（Headless）
# 用途：在本地快速验证“主菜单自动恢复 / Lobby 恢复 / InGame 重连 / 主动退出清理”关键链路，
# 避免每次都走完整构建部署。
extends SceneTree

const ResultClass = preload("res://core/types/result.gd")
const NAME := "OnlineRegressionSuite"

const TESTS: Array[Dictionary] = [
	{
		"name": "NetContextOnlineResumeTest",
		"path": "res://core/tests/net_context_online_resume_test.gd",
	},
	{
		"name": "NetContextOnlineResumePersistenceTest",
		"path": "res://core/tests/net_context_online_resume_persistence_test.gd",
	},
	{
		"name": "NetClientConnectPreserveContextTest",
		"path": "res://core/tests/net_client_connect_preserve_context_test.gd",
	},
	{
		"name": "OnlineResumeErrorPolicyTest",
		"path": "res://core/tests/online_resume_error_policy_test.gd",
	},
	{
		"name": "PlatformConnectTokenAutoJoinTest",
		"path": "res://core/tests/platform_connect_token_auto_join_test.gd",
	},
	{
		"name": "OnlineClientDisconnectPreserveContextTest",
		"path": "res://core/tests/online_client_disconnect_preserve_context_test.gd",
	},
	{
		"name": "OnlineClientGameStartedReconnectTest",
		"path": "res://core/tests/online_client_game_started_reconnect_test.gd",
	},
	{
		"name": "GameMenuDebugControllerOnlineQuitTest",
		"path": "res://core/tests/game_menu_debug_controller_online_quit_test.gd",
	},
	{
		"name": "GameMenuDebugControllerOnlineSurrenderQuitTest",
		"path": "res://core/tests/game_menu_debug_controller_online_surrender_quit_test.gd",
	},
	{
		"name": "OnlineRoomManagerTest",
		"path": "res://core/tests/online_room_manager_test.gd",
	},
	{
		"name": "OnlineRoomListTest",
		"path": "res://core/tests/online_room_list_test.gd",
	},
	{
		"name": "OnlineStartGameReplayTest",
		"path": "res://core/tests/online_start_game_replay_test.gd",
	},
	{
		"name": "ServerResyncGuardTest",
		"path": "res://core/tests/server_resync_guard_test.gd",
	},
	{
		"name": "OnlineClientResyncSnapshotChunkTest",
		"path": "res://core/tests/online_client_resync_snapshot_chunk_test.gd",
	},
	{
		"name": "OnlineClientRewindToTurnStartMetaTest",
		"path": "res://core/tests/online_client_rewind_to_turn_start_meta_test.gd",
	},
	{
		"name": "OnlineClientResyncDeltaApplyTest",
		"path": "res://core/tests/online_client_resync_delta_apply_test.gd",
	},
	{
		"name": "OnlineClientResyncRoomIsolationTest",
		"path": "res://core/tests/online_client_resync_room_isolation_test.gd",
	},
	{
		"name": "OnlineLobbyDisconnectReclaimTest",
		"path": "res://core/tests/online_lobby_disconnect_reclaim_test.gd",
	},
	{
		"name": "OnlineLobbyDisconnectGraceReleaseTest",
		"path": "res://core/tests/online_lobby_disconnect_grace_release_test.gd",
	},
	{
		"name": "OnlineDisconnectGraceReconnectTest",
		"path": "res://core/tests/online_disconnect_grace_reconnect_test.gd",
	},
	{
		"name": "OnlineInGameLastPeerDisconnectRecoveryTest",
		"path": "res://core/tests/online_in_game_last_peer_disconnect_recovery_test.gd",
	},
	{
		"name": "OnlineForfeitAndLeaveRoomTest",
		"path": "res://core/tests/online_forfeit_and_leave_room_test.gd",
	},
	{
		"name": "GameOnlineResyncReconnectFlowTest",
		"path": "res://core/tests/game_online_resync_reconnect_flow_test.gd",
	},
	{
		"name": "GameOnlineResumeProgressSyncTest",
		"path": "res://core/tests/game_online_resume_progress_sync_test.gd",
	},
	{
		"name": "GameOnlineResyncRequestRejectionTest",
		"path": "res://core/tests/game_online_resync_request_rejection_test.gd",
	},
	{
		"name": "OnlineRoomPersistenceRecoveryTest",
		"path": "res://core/tests/online_room_persistence_recovery_test.gd",
	},
	{
		"name": "OnlineLobbyResumeControllerTest",
		"path": "res://core/tests/online_lobby_resume_controller_test.gd",
	},
	{
		"name": "OnlineLobbyPersistenceRecoveryTest",
		"path": "res://core/tests/online_lobby_persistence_recovery_test.gd",
	},
	{
		"name": "GameStartupDirectResumeGuardTest",
		"path": "res://core/tests/game_startup_direct_resume_guard_test.gd",
	},
	{
		"name": "GameStartupOnlineResumeControllerTest",
		"path": "res://core/tests/game_startup_online_resume_controller_test.gd",
	},
]

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	print("[%s] START total=%d" % [NAME, TESTS.size()])

	var passed := 0
	var failed: Array[String] = []
	var total_start := Time.get_ticks_msec()

	for test_def in TESTS:
		var name := str(test_def.get("name", "UnknownTest"))
		var path := str(test_def.get("path", "")).strip_edges()
		print("[%s] RUN %s" % [NAME, name])

		var test_script = load(path)
		if test_script == null:
			failed.append(name)
			push_error("[%s] FAIL %s: load 失败 path=%s" % [NAME, name, path])
			await _cleanup_runtime_between_tests()
			continue
		if not test_script.has_method("run"):
			failed.append(name)
			push_error("[%s] FAIL %s: 缺少 run()" % [NAME, name])
			await _cleanup_runtime_between_tests()
			continue

		var start := Time.get_ticks_msec()
		var call_result = await test_script.run()
		var result = call_result if (call_result is ResultClass) else ResultClass.failure("测试返回值类型错误（期望 Result）")
		var duration_ms := Time.get_ticks_msec() - start

		if result.ok:
			passed += 1
			print("[%s] PASS %s (%dms)" % [NAME, name, duration_ms])
		else:
			failed.append(name)
			push_error("[%s] FAIL %s (%dms): %s" % [NAME, name, duration_ms, str(result.error)])

		await _cleanup_runtime_between_tests()

	var total_ms := Time.get_ticks_msec() - total_start
	print("[%s] SUMMARY passed=%d/%d failed=%s total_ms=%d" % [NAME, passed, TESTS.size(), str(failed), total_ms])
	quit(0 if failed.is_empty() else 1)

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
