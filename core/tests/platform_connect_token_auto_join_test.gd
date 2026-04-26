# Platform：connect_token 验签 + ClientHello 自动建房/入房
class_name PlatformConnectTokenAutoJoinTest
extends RefCounted

const ArchiveClass = preload("res://core/engine/game_engine/archive.gd")
const ConnectTokenClass = preload("res://core/utils/connect_token.gd")
const ServerLogicClass = preload("res://autoload/net_client/server.gd")
const RoomManagerClass = preload("res://server/room_manager.gd")
const GameEngineClass = preload("res://core/engine/game_engine.gd")
const GameDefaultsClass = preload("res://core/engine/game_defaults.gd")
const TestPhaseUtilsClass = preload("res://core/tests/test_phase_utils.gd")
const ResyncSnapshotTransferClass = preload("res://core/utils/resync_snapshot_transfer.gd")
const ONLINE_DINNERTIME_CONFIRM_KEY := "online_require_dinnertime_confirm"
const ONLINE_MARKETING_CONFIRM_KEY := "online_require_marketing_confirm"

static func run() -> Result:
	_reset_net_context()
	if NetContext == null:
		return Result.failure("NetContext autoload missing")
	NetContext.mode = NetContext.Mode.ONLINE_SERVER

	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var rm = RoomManagerClass.new(rng)

	var mock_net := _MockNetClient.new(rm)
	var server = ServerLogicClass.new()
	server.setup(mock_net)
	server.connect_token_secret_override = "test-secret"

	var room_code := "Q1W2E3"

	# Host: create room with fixed code
	var cfg := {
		"desired_player_count": 2,
		"seed_mode": "fixed",
		"seed": 12345,
		"allow_spectators": true,
		"enabled_modules_v2": [],
		"modules_v2_base_dir": GameDefaultsClass.DEFAULT_MODULES_V2_BASE_DIR,
	}
	var host_payload := {
		"user_id": "u_host",
		"room_code": room_code,
		"role": "host",
		"display_name": "HostUser",
		"seat_index": 0,
		"generation": 1,
		"config_json": JSON.stringify(cfg),
		"join_policy": "password",
		"password_hash": "platform-password-hash",
		"exp": int(Time.get_unix_time_from_system()) + 3600,
	}
	var host_token_r: Result = ConnectTokenClass.create_token(host_payload, server.connect_token_secret_override)
	if not host_token_r.ok:
		_reset_net_context()
		return Result.failure("create_token(host) 失败: %s" % host_token_r.error)

	mock_net.multiplayer.remote_sender_id = 10
	server.handle_rpc_client_hello({
		"request_id": "r_host",
		"protocol_version": NetContext.PROTOCOL_VERSION,
		"game_version": "0.0.0",
		"schema_version": 0,
		"player_profile": {"name": "Host", "color_index": 1, "restaurant_logo_id": -1},
		"connect_token": str(host_token_r.value),
	})

	if not rm.rooms.has(room_code):
		_reset_net_context()
		return Result.failure("平台建房失败：rooms 未包含 %s" % room_code)
	if str(rm.peer_to_room.get(10, "")) != room_code:
		_reset_net_context()
		return Result.failure("平台建房失败：host peer_to_room 未绑定到 %s" % room_code)
	var room = rm.rooms.get(room_code, null)
	if room == null:
		_reset_net_context()
		return Result.failure("平台建房失败：room 为空")
	if int(room.host_peer_id) != 10:
		_reset_net_context()
		return Result.failure("平台建房失败：host_peer_id 错误: %d" % int(room.host_peer_id))
	if str(room.join_policy) != "password":
		_reset_net_context()
		return Result.failure("平台建房失败：join_policy 错误: %s" % str(room.join_policy))
	if str(room.password_hash) != "platform-password-hash":
		_reset_net_context()
		return Result.failure("平台建房失败：password_hash 未透传")
	if not room.is_password_required():
		_reset_net_context()
		return Result.failure("平台建房失败：密码房间应标记为需要密码")

	# Player: auto join existing room
	var player_payload := {
		"user_id": "u_p2",
		"room_code": room_code,
		"role": "player",
		"display_name": "P2",
		"seat_index": 1,
		"generation": 1,
		"exp": int(Time.get_unix_time_from_system()) + 3600,
	}
	var player_token_r: Result = ConnectTokenClass.create_token(player_payload, server.connect_token_secret_override)
	if not player_token_r.ok:
		_reset_net_context()
		return Result.failure("create_token(player) 失败: %s" % player_token_r.error)

	mock_net.multiplayer.remote_sender_id = 11
	server.handle_rpc_client_hello({
		"request_id": "r_p2",
		"protocol_version": NetContext.PROTOCOL_VERSION,
		"game_version": "0.0.0",
		"schema_version": 0,
		"player_profile": {"name": "P2Local", "color_index": 2, "restaurant_logo_id": -1},
		"connect_token": str(player_token_r.value),
	})

	if str(rm.peer_to_room.get(11, "")) != room_code:
		_reset_net_context()
		return Result.failure("平台入房失败：player peer_to_room 未绑定到 %s" % room_code)
	var peers: Array[int] = room.get_peer_ids()
	if peers.size() != 2 or not peers.has(10) or not peers.has(11):
		_reset_net_context()
		return Result.failure("平台入房失败：get_peer_ids=%s" % str(peers))

	# Same user reuses stale token: server should reject it instead of allowing arbitrary takeover.
	mock_net.multiplayer.remote_sender_id = 12
	server.handle_rpc_client_hello({
		"request_id": "r_p2_takeover_stale",
		"protocol_version": NetContext.PROTOCOL_VERSION,
		"game_version": "0.0.0",
		"schema_version": 0,
		"player_profile": {"name": "P2Takeover", "color_index": 2, "restaurant_logo_id": -1},
		"connect_token": str(player_token_r.value),
	})

	if _find_request_rejected(mock_net.sent, 12, "r_p2_takeover_stale", "generation_conflict") < 0:
		_reset_net_context()
		return Result.failure("平台 stale token 应返回 generation_conflict")
	if rm.peer_to_room.has(12):
		_reset_net_context()
		return Result.failure("平台 stale token 不应绑定新 peer")
	if str(rm.peer_to_room.get(11, "")) != room_code:
		_reset_net_context()
		return Result.failure("平台 stale token 不应破坏旧 peer 绑定")

	var player_takeover_payload := {
		"user_id": "u_p2",
		"room_code": room_code,
		"role": "player",
		"display_name": "P2Takeover",
		"seat_index": 1,
		"generation": 2,
		"exp": int(Time.get_unix_time_from_system()) + 3600,
	}
	var player_takeover_token_r: Result = ConnectTokenClass.create_token(player_takeover_payload, server.connect_token_secret_override)
	if not player_takeover_token_r.ok:
		_reset_net_context()
		return Result.failure("create_token(player_takeover) 失败: %s" % player_takeover_token_r.error)

	mock_net.multiplayer.remote_sender_id = 12
	server.handle_rpc_client_hello({
		"request_id": "r_p2_takeover",
		"protocol_version": NetContext.PROTOCOL_VERSION,
		"game_version": "0.0.0",
		"schema_version": 0,
		"player_profile": {"name": "P2Takeover", "color_index": 2, "restaurant_logo_id": -1},
		"connect_token": str(player_takeover_token_r.value),
	})

	if str(rm.peer_to_room.get(12, "")) != room_code:
		_reset_net_context()
		return Result.failure("平台接管失败：new peer_to_room 未绑定到 %s" % room_code)
	if rm.peer_to_room.has(11):
		_reset_net_context()
		return Result.failure("平台接管失败：old peer_to_room 未清理")
	var peers_after: Array[int] = room.get_peer_ids()
	if peers_after.size() != 2 or not peers_after.has(10) or not peers_after.has(12) or peers_after.has(11):
		_reset_net_context()
		return Result.failure("平台接管失败：get_peer_ids=%s" % str(peers_after))
	if not _has_empty_room_state_push(mock_net.sent, 11):
		_reset_net_context()
		return Result.failure("平台接管失败：old peer 未收到 empty room_state")

	var start_r: Result = room.start_game()
	if not start_r.ok:
		_reset_net_context()
		return Result.failure("平台自动入房测试开局失败: %s" % start_r.error)

	var spectator_payload := {
		"user_id": "u_spec_1",
		"room_code": room_code,
		"role": "spectator",
		"display_name": "Spec1",
		"exp": int(Time.get_unix_time_from_system()) + 3600,
	}
	var spectator_token_r: Result = ConnectTokenClass.create_token(spectator_payload, server.connect_token_secret_override)
	if not spectator_token_r.ok:
		_reset_net_context()
		return Result.failure("create_token(spectator1) 失败: %s" % spectator_token_r.error)

	mock_net.multiplayer.remote_sender_id = 20
	server.handle_rpc_client_hello({
		"request_id": "r_spec_1",
		"protocol_version": NetContext.PROTOCOL_VERSION,
		"game_version": "0.0.0",
		"schema_version": 0,
		"player_profile": {"name": "Spec1Local", "color_index": 3, "restaurant_logo_id": -1},
		"connect_token": str(spectator_token_r.value),
	})

	if str(rm.peer_to_room.get(20, "")) != room_code:
		_reset_net_context()
		return Result.failure("观战自动入房失败：spectator1 peer_to_room 未绑定到 %s" % room_code)

	var spectator_payload2 := {
		"user_id": "u_spec_2",
		"room_code": room_code,
		"role": "spectator",
		"display_name": "Spec2",
		"exp": int(Time.get_unix_time_from_system()) + 3600,
	}
	var spectator_token_r2: Result = ConnectTokenClass.create_token(spectator_payload2, server.connect_token_secret_override)
	if not spectator_token_r2.ok:
		_reset_net_context()
		return Result.failure("create_token(spectator2) 失败: %s" % spectator_token_r2.error)

	mock_net.multiplayer.remote_sender_id = 21
	server.handle_rpc_client_hello({
		"request_id": "r_spec_2",
		"protocol_version": NetContext.PROTOCOL_VERSION,
		"game_version": "0.0.0",
		"schema_version": 0,
		"player_profile": {"name": "Spec2Local", "color_index": 4, "restaurant_logo_id": -1},
		"connect_token": str(spectator_token_r2.value),
	})

	if str(rm.peer_to_room.get(21, "")) != room_code:
		_reset_net_context()
		return Result.failure("观战自动入房失败：spectator2 peer_to_room 未绑定到 %s" % room_code)
	var in_game_peers: Array[int] = room.get_peer_ids()
	if in_game_peers.size() != 4 or not in_game_peers.has(10) or not in_game_peers.has(12) or not in_game_peers.has(20) or not in_game_peers.has(21):
		_reset_net_context()
		return Result.failure("多观战者未同时存在：get_peer_ids=%s" % str(in_game_peers))

	mock_net.multiplayer.remote_sender_id = 22
	server.handle_rpc_client_hello({
		"request_id": "r_spec_1_takeover",
		"protocol_version": NetContext.PROTOCOL_VERSION,
		"game_version": "0.0.0",
		"schema_version": 0,
		"player_profile": {"name": "Spec1Takeover", "color_index": 3, "restaurant_logo_id": -1},
		"connect_token": str(spectator_token_r.value),
	})

	if str(rm.peer_to_room.get(22, "")) != room_code:
		_reset_net_context()
		return Result.failure("观战接管失败：new spectator peer_to_room 未绑定到 %s" % room_code)
	if rm.peer_to_room.has(20):
		_reset_net_context()
		return Result.failure("观战接管失败：old spectator peer_to_room 未清理")
	var peers_after_spectator_takeover: Array[int] = room.get_peer_ids()
	if peers_after_spectator_takeover.size() != 4 \
		or not peers_after_spectator_takeover.has(10) \
		or not peers_after_spectator_takeover.has(12) \
		or not peers_after_spectator_takeover.has(21) \
		or not peers_after_spectator_takeover.has(22) \
		or peers_after_spectator_takeover.has(20):
		_reset_net_context()
		return Result.failure("观战接管失败：get_peer_ids=%s" % str(peers_after_spectator_takeover))
	if not _has_empty_room_state_push(mock_net.sent, 20):
		_reset_net_context()
		return Result.failure("观战接管失败：old spectator 未收到 empty room_state")

	mock_net._peer = _MockPeer.new(128)
	var player_ingame_fail_payload := {
		"user_id": "u_p2",
		"room_code": room_code,
		"role": "player",
		"display_name": "P2ReconnectFail",
		"seat_index": 1,
		"generation": 3,
		"exp": int(Time.get_unix_time_from_system()) + 3600,
	}
	var player_ingame_fail_token_r: Result = ConnectTokenClass.create_token(player_ingame_fail_payload, server.connect_token_secret_override)
	if not player_ingame_fail_token_r.ok:
		_reset_net_context()
		return Result.failure("create_token(player_ingame_fail) 失败: %s" % player_ingame_fail_token_r.error)
	mock_net.multiplayer.remote_sender_id = 13
	server.handle_rpc_client_hello({
		"request_id": "r_p2_ingame_fail",
		"protocol_version": NetContext.PROTOCOL_VERSION,
		"game_version": "0.0.0",
		"schema_version": 0,
		"player_profile": {"name": "P2ReconnectFail", "color_index": 2, "restaurant_logo_id": -1},
		"connect_token": str(player_ingame_fail_token_r.value),
	})

	if rm.peer_to_room.has(13):
		_reset_net_context()
		return Result.failure("InGame 自动恢复快照构建失败时不应绑定新 peer")
	if str(rm.peer_to_room.get(12, "")) != room_code:
		_reset_net_context()
		return Result.failure("InGame 自动恢复快照构建失败时不应破坏旧 peer 绑定")
	if int(room.player_id_by_peer_id.get(12, -1)) != 1:
		_reset_net_context()
		return Result.failure("InGame 自动恢复快照构建失败时旧 seat 控制权丢失")
	if room.player_id_by_peer_id.has(13):
		_reset_net_context()
		return Result.failure("InGame 自动恢复快照构建失败时不应留下新 peer 的 player_id 映射")
	if _find_request_rejected(mock_net.sent, 13, "r_p2_ingame_fail", "platform_join_failed") < 0:
		_reset_net_context()
		return Result.failure("InGame 自动恢复快照构建失败时应返回 platform_join_failed")
	if _find_sent_method(mock_net.sent, 13, "rpc_game_started") >= 0:
		_reset_net_context()
		return Result.failure("InGame 自动恢复快照构建失败时不应提前发送 GameStarted")

	var resume_auto_join_r: Result = _run_resume_archive_auto_join_scenario()
	if not resume_auto_join_r.ok:
		_reset_net_context()
		return resume_auto_join_r
	var resume_auto_assign_r: Result = _run_resume_archive_auto_assign_scenario()
	if not resume_auto_assign_r.ok:
		_reset_net_context()
		return resume_auto_assign_r

	_reset_net_context()
	return Result.success()

static func _run_resume_archive_auto_join_scenario() -> Result:
	_reset_net_context()
	if NetContext == null:
		return Result.failure("NetContext autoload missing")
	NetContext.mode = NetContext.Mode.ONLINE_SERVER

	var archive_r: Result = _build_test_archive()
	if not archive_r.ok:
		return archive_r
	var base_archive: Dictionary = Dictionary(archive_r.value).duplicate(true)
	var resume_archive_r: Result = _build_midpoint_resume_archive(base_archive)
	if not resume_archive_r.ok:
		return resume_archive_r
	var resume_info: Dictionary = Dictionary(resume_archive_r.value).duplicate(true)
	var archive: Dictionary = Dictionary(resume_info.get("archive", {})).duplicate(true)
	var expected_hash := str(resume_info.get("expected_hash", "")).strip_edges()
	if expected_hash.is_empty():
		return Result.failure("resume archive 缺少 final_hash")
	var selected_index := int(resume_info.get("selected_index", -1))
	var selected_round_number := int(resume_info.get("round_number", 0))
	var selected_phase := str(resume_info.get("phase", "")).strip_edges()

	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var rm = RoomManagerClass.new(rng)

	var mock_net := _MockNetClient.new(rm)
	var server = ServerLogicClass.new()
	server.setup(mock_net)
	server.connect_token_secret_override = "test-secret"

	var room_code := "RSM123"
	var cfg := {
		"room_mode": "resume_archive",
		"desired_player_count": 2,
		"seed_mode": "fixed",
		"seed": 12345,
		"allow_spectators": true,
		"enabled_modules_v2": [],
		"modules_v2_base_dir": GameDefaultsClass.DEFAULT_MODULES_V2_BASE_DIR,
		"resume_summary": {
			"source_name": "platform_resume_test.json",
			"player_count": 2,
			"round_number": selected_round_number,
			"phase": selected_phase,
			"current_index": selected_index,
		},
	}
	var host_payload := {
		"user_id": "u_resume_host",
		"room_code": room_code,
		"role": "host",
		"display_name": "ResumeHost",
		"seat_index": null,
		"generation": 1,
		"config_json": JSON.stringify(cfg),
		"join_policy": "public",
		"exp": int(Time.get_unix_time_from_system()) + 3600,
	}
	var host_token_r: Result = ConnectTokenClass.create_token(host_payload, server.connect_token_secret_override)
	if not host_token_r.ok:
		return Result.failure("create_token(resume host) 失败: %s" % host_token_r.error)

	mock_net.multiplayer.remote_sender_id = 30
	server.handle_rpc_client_hello({
		"request_id": "r_resume_host",
		"protocol_version": NetContext.PROTOCOL_VERSION,
		"game_version": "0.0.0",
		"schema_version": 0,
		"player_profile": {"name": "ResumeHostLocal", "color_index": 1, "restaurant_logo_id": -1},
		"connect_token": str(host_token_r.value),
		"resume_room_bootstrap": {"archive": archive},
	})

	if str(rm.peer_to_room.get(30, "")) != room_code:
		return Result.failure("恢复房平台建房失败：host peer_to_room 未绑定到 %s" % room_code)
	var room = rm.rooms.get(room_code, null)
	if room == null:
		return Result.failure("恢复房平台建房失败：room 为空")
	if not room.has_method("is_resume_archive_room") or not room.is_resume_archive_room():
		return Result.failure("恢复房平台建房失败：room_mode 不是 resume_archive")
	if int(room.host_peer_id) != 30:
		return Result.failure("恢复房平台建房失败：host_peer_id 错误: %d" % int(room.host_peer_id))
	if room.get_player_count() != 0:
		return Result.failure("恢复房建房后不应已有已分座玩家: %d" % room.get_player_count())
	if not room.has_method("get_waiting_member_count") or int(room.get_waiting_member_count()) != 1:
		return Result.failure("恢复房建房后待分配成员数错误: %s" % str(room.get_waiting_member_count() if room.has_method("get_waiting_member_count") else -1))

	var player_payload := {
		"user_id": "u_resume_player",
		"room_code": room_code,
		"role": "player",
		"display_name": "ResumeP2",
		"seat_index": null,
		"generation": 1,
		"exp": int(Time.get_unix_time_from_system()) + 3600,
	}
	var player_token_r: Result = ConnectTokenClass.create_token(player_payload, server.connect_token_secret_override)
	if not player_token_r.ok:
		return Result.failure("create_token(resume player) 失败: %s" % player_token_r.error)

	mock_net.multiplayer.remote_sender_id = 31
	server.handle_rpc_client_hello({
		"request_id": "r_resume_player",
		"protocol_version": NetContext.PROTOCOL_VERSION,
		"game_version": "0.0.0",
		"schema_version": 0,
		"player_profile": {"name": "ResumeP2Local", "color_index": 2, "restaurant_logo_id": -1},
		"connect_token": str(player_token_r.value),
	})

	if str(rm.peer_to_room.get(31, "")) != room_code:
		return Result.failure("恢复房平台入房失败：player peer_to_room 未绑定到 %s" % room_code)
	if int(room.get_waiting_member_count()) != 2:
		return Result.failure("恢复房玩家加入后待分配成员数错误: %d" % int(room.get_waiting_member_count()))
	var waiting_peers: Array[int] = room.get_peer_ids()
	if waiting_peers.size() != 2 or not waiting_peers.has(30) or not waiting_peers.has(31):
		return Result.failure("恢复房待分配 peer 集合错误: %s" % str(waiting_peers))

	mock_net.multiplayer.remote_sender_id = 30
	server.handle_rpc_assign_room_seat({
		"request_id": "r_resume_assign_host",
		"user_id": "u_resume_host",
		"seat_index": 0,
	})
	server.handle_rpc_assign_room_seat({
		"request_id": "r_resume_assign_player",
		"user_id": "u_resume_player",
		"seat_index": 1,
	})

	if _find_request_rejected(mock_net.sent, 30, "r_resume_assign_host", "assign_seat_failed") >= 0:
		return Result.failure("恢复房 host 分座不应被拒绝")
	if _find_request_rejected(mock_net.sent, 30, "r_resume_assign_player", "assign_seat_failed") >= 0:
		return Result.failure("恢复房 player 分座不应被拒绝")
	if int(room.get_waiting_member_count()) != 0:
		return Result.failure("恢复房分座后不应仍有待分配成员: %d" % int(room.get_waiting_member_count()))
	if room.get_player_count() != 2:
		return Result.failure("恢复房分座后 player_count 错误: %d" % room.get_player_count())
	if room.get_connected_player_count() != 2:
		return Result.failure("恢复房分座后 connected_player_count 错误: %d" % room.get_connected_player_count())

	var ready_r: Result = room.can_start_game()
	if not ready_r.ok:
		return Result.failure("恢复房分座后应允许开始游戏: %s" % ready_r.error)

	mock_net.multiplayer.remote_sender_id = 30
	server.handle_rpc_start_game({
		"request_id": "r_resume_start",
	})
	if _find_request_rejected(mock_net.sent, 30, "r_resume_start", "start_game_failed") >= 0:
		return Result.failure("恢复房平台自动入房场景开局不应失败")
	if str(room.status) != "Starting":
		return Result.failure("恢复房开局请求后房间应先进入 Starting: %s" % str(room.status))
	if room.game_engine != null:
		return Result.failure("恢复房在全部 ready 之前不应提前 commit game_engine")
	if not room.has_method("has_pending_start_session") or not room.has_pending_start_session():
		return Result.failure("恢复房开局后应存在 pending start session")
	var bootstrap_id := str(room.get_pending_start_session_id()).strip_edges() if room.has_method("get_pending_start_session_id") else ""
	if bootstrap_id.is_empty():
		return Result.failure("恢复房开局后缺少 bootstrap_id")
	var bootstrap_summary: Dictionary = room.get_pending_start_summary() if room.has_method("get_pending_start_summary") else {}
	if int(Dictionary(bootstrap_summary).get("total_count", 0)) != 2:
		return Result.failure("恢复房 bootstrap total_count 错误: %s" % str(bootstrap_summary))
	if int(Dictionary(bootstrap_summary).get("ready_count", -1)) != 0:
		return Result.failure("恢复房 bootstrap 初始 ready_count 应为 0: %s" % str(bootstrap_summary))
	var expected_history_size := selected_index + 1
	if _find_sent_method(mock_net.sent, 30, "rpc_game_started") < 0 or _find_sent_method(mock_net.sent, 31, "rpc_game_started") < 0:
		return Result.failure("恢复房开局后双方都应收到 rpc_game_started")
	if _find_sent_method(mock_net.sent, 30, "rpc_resync_snapshot_manifest") < 0 or _find_sent_method(mock_net.sent, 31, "rpc_resync_snapshot_manifest") < 0:
		return Result.failure("恢复房单 full-engine 启动应下发 snapshot manifest")
	if _find_sent_method(mock_net.sent, 30, "rpc_resync_snapshot_chunk") < 0 or _find_sent_method(mock_net.sent, 31, "rpc_resync_snapshot_chunk") < 0:
		return Result.failure("恢复房单 full-engine 启动应下发 snapshot chunk")
	if _find_sent_method(mock_net.sent, 30, "rpc_resync_archive") >= 0 or _find_sent_method(mock_net.sent, 31, "rpc_resync_archive") >= 0:
		return Result.failure("恢复房开局主链路不应回退到旧 rpc_resync_archive")
	var host_game_started := _get_sent_payload(mock_net.sent, 30, "rpc_game_started")
	var player_game_started := _get_sent_payload(mock_net.sent, 31, "rpc_game_started")
	if host_game_started.is_empty() or player_game_started.is_empty():
		return Result.failure("恢复房开局缺少 rpc_game_started payload")
	if str(host_game_started.get("resume_bootstrap_mode", "")).strip_edges() != "full_archive_snapshot":
		return Result.failure("host rpc_game_started 应标记 full_archive_snapshot bootstrap mode")
	if str(player_game_started.get("resume_bootstrap_mode", "")).strip_edges() != "full_archive_snapshot":
		return Result.failure("player rpc_game_started 应标记 full_archive_snapshot bootstrap mode")
	if host_game_started.get("resume_fast_start_bundle", null) is Dictionary and not Dictionary(host_game_started.get("resume_fast_start_bundle", {})).is_empty():
		return Result.failure("single full-engine 启动不应再内联 resume_fast_start_bundle")
	if player_game_started.get("resume_fast_start_bundle", null) is Dictionary and not Dictionary(player_game_started.get("resume_fast_start_bundle", {})).is_empty():
		return Result.failure("single full-engine 启动不应再内联 player resume_fast_start_bundle")

	mock_net.multiplayer.remote_sender_id = 30
	server.handle_rpc_match_bootstrap_ready({
		"request_id": "r_resume_ready_host",
		"bootstrap_id": bootstrap_id,
	})
	if str(room.status) != "Starting":
		return Result.failure("仅房主 ready 后房间仍应保持 Starting: %s" % str(room.status))
	var host_ready_summary: Dictionary = room.get_pending_start_summary() if room.has_method("get_pending_start_summary") else {}
	if int(Dictionary(host_ready_summary).get("ready_count", -1)) != 1:
		return Result.failure("房主 ready 后 ready_count 应为 1: %s" % str(host_ready_summary))

	mock_net.multiplayer.remote_sender_id = 31
	server.handle_rpc_match_bootstrap_ready({
		"request_id": "r_resume_ready_player",
		"bootstrap_id": bootstrap_id,
	})
	if str(room.status) != "InGame":
		return Result.failure("双方 ready 后房间应进入 InGame: %s" % str(room.status))
	if room.has_method("has_pending_start_session") and room.has_pending_start_session():
		return Result.failure("双方 ready commit 后不应仍保留 pending start session")
	if room.game_engine == null or room.game_engine.get_state() == null:
		return Result.failure("恢复房 commit 后缺少 game_engine/state")
	var actual_hash := str(room.game_engine.get_state().compute_hash())
	if actual_hash != expected_hash:
		return Result.failure("恢复房开局 hash 不一致: %s vs %s" % [expected_hash, actual_hash])
	if int(room.game_engine.command_history.size()) != expected_history_size:
		return Result.failure(
			"恢复房开局后不应保留未来历史: %d vs %d"
				% [int(room.game_engine.command_history.size()), expected_history_size]
		)
	if int(room.game_engine.current_command_index) != selected_index:
		return Result.failure("恢复房开局 current_command_index 错误: %d vs %d" % [int(room.game_engine.current_command_index), selected_index])

	return Result.success()

static func _run_resume_archive_auto_assign_scenario() -> Result:
	_reset_net_context()
	if NetContext == null:
		return Result.failure("NetContext autoload missing")
	NetContext.mode = NetContext.Mode.ONLINE_SERVER

	var archive_r: Result = _build_test_archive()
	if not archive_r.ok:
		return archive_r
	var base_archive: Dictionary = Dictionary(archive_r.value).duplicate(true)
	var resume_archive_r: Result = _build_midpoint_resume_archive(base_archive)
	if not resume_archive_r.ok:
		return resume_archive_r
	var resume_info: Dictionary = Dictionary(resume_archive_r.value).duplicate(true)
	var archive: Dictionary = Dictionary(resume_info.get("archive", {})).duplicate(true)
	archive = ArchiveClass.with_online_resume_meta(archive, {
		"version": ArchiveClass.ONLINE_RESUME_META_VERSION,
		"owner_user_id": "u_resume_host_auto",
		"participant_slots": [
			{
				"seat_index": 0,
				"player_id": 0,
				"user_id": "u_resume_host_auto",
				"display_name": "ResumeHostAuto",
				"role": "host",
				"restaurant_logo_id": 0,
				"restaurants_count": 1,
				"restaurant_summary": [{"restaurant_id": "r_auto_host"}],
			},
			{
				"seat_index": 1,
				"player_id": 1,
				"user_id": "u_resume_player_auto",
				"display_name": "ResumeP2Auto",
				"role": "player",
				"restaurant_logo_id": 1,
				"restaurants_count": 1,
				"restaurant_summary": [{"restaurant_id": "r_auto_player"}],
			},
		],
	})

	var rng := RandomNumberGenerator.new()
	rng.seed = 5150
	var rm = RoomManagerClass.new(rng)
	var mock_net := _MockNetClient.new(rm)
	var server = ServerLogicClass.new()
	server.setup(mock_net)
	server.connect_token_secret_override = "test-secret"

	var room_code := "RSA123"
	var cfg := {
		"room_mode": "resume_archive",
		"desired_player_count": 2,
		"seed_mode": "fixed",
		"seed": 12345,
		"allow_spectators": true,
		"enabled_modules_v2": [],
		"modules_v2_base_dir": GameDefaultsClass.DEFAULT_MODULES_V2_BASE_DIR,
		"resume_participant_bindings": [
			{"user_id": "u_resume_host_auto", "seat_index": 0, "player_id": 0, "role": "host"},
			{"user_id": "u_resume_player_auto", "seat_index": 1, "player_id": 1, "role": "player"},
		],
	}

	var host_payload := {
		"user_id": "u_resume_host_auto",
		"room_code": room_code,
		"role": "host",
		"display_name": "ResumeHostAuto",
		"seat_index": null,
		"generation": 1,
		"config_json": JSON.stringify(cfg),
		"join_policy": "public",
		"exp": int(Time.get_unix_time_from_system()) + 3600,
	}
	var host_token_r: Result = ConnectTokenClass.create_token(host_payload, server.connect_token_secret_override)
	if not host_token_r.ok:
		return Result.failure("create_token(resume auto host) 失败: %s" % host_token_r.error)

	mock_net.multiplayer.remote_sender_id = 40
	server.handle_rpc_client_hello({
		"request_id": "r_resume_auto_host",
		"protocol_version": NetContext.PROTOCOL_VERSION,
		"game_version": "0.0.0",
		"schema_version": 0,
		"player_profile": {"name": "ResumeHostAutoLocal", "color_index": 1, "restaurant_logo_id": -1},
		"connect_token": str(host_token_r.value),
		"resume_room_bootstrap": {"archive": archive},
	})

	var room = rm.rooms.get(room_code, null)
	if room == null:
		return Result.failure("恢复房自动分配场景建房失败：room 为空")
	if room.get_player_count() != 1:
		return Result.failure("恢复房 host 应自动占回原 seat: %d" % room.get_player_count())
	if int(room.get_waiting_member_count()) != 0:
		return Result.failure("恢复房 host 自动分配后不应仍在 waiting: %d" % int(room.get_waiting_member_count()))
	if int(room.find_seat_index_for_user_id("u_resume_host_auto")) != 0:
		return Result.failure("恢复房 host 未自动回到 seat 0")

	var player_payload := {
		"user_id": "u_resume_player_auto",
		"room_code": room_code,
		"role": "player",
		"display_name": "ResumeP2Auto",
		"seat_index": null,
		"generation": 1,
		"exp": int(Time.get_unix_time_from_system()) + 3600,
	}
	var player_token_r: Result = ConnectTokenClass.create_token(player_payload, server.connect_token_secret_override)
	if not player_token_r.ok:
		return Result.failure("create_token(resume auto player) 失败: %s" % player_token_r.error)

	mock_net.multiplayer.remote_sender_id = 41
	server.handle_rpc_client_hello({
		"request_id": "r_resume_auto_player",
		"protocol_version": NetContext.PROTOCOL_VERSION,
		"game_version": "0.0.0",
		"schema_version": 0,
		"player_profile": {"name": "ResumeP2AutoLocal", "color_index": 2, "restaurant_logo_id": -1},
		"connect_token": str(player_token_r.value),
	})

	if room.get_player_count() != 2:
		return Result.failure("恢复房同批玩家自动分配后 player_count 错误: %d" % room.get_player_count())
	if int(room.get_waiting_member_count()) != 0:
		return Result.failure("恢复房同批玩家自动分配后不应仍有 waiting 成员: %d" % int(room.get_waiting_member_count()))
	if int(room.find_seat_index_for_user_id("u_resume_player_auto")) != 1:
		return Result.failure("恢复房 player 未自动回到 seat 1")
	if room.get_connected_player_count() != 2:
		return Result.failure("恢复房同批玩家自动分配后 connected_player_count 错误: %d" % room.get_connected_player_count())
	var ready_r: Result = room.can_start_game()
	if not ready_r.ok:
		return Result.failure("恢复房同批玩家自动分配后应允许开始游戏: %s" % ready_r.error)

	return Result.success()

static func _build_test_archive() -> Result:
	var engine = GameEngineClass.new()
	var init_r: Result = engine.initialize(2, 12345, [], GameDefaultsClass.DEFAULT_MODULES_V2_BASE_DIR)
	if not init_r.ok:
		return Result.failure("初始化恢复测试存档失败: %s" % init_r.error)
	var setup_r: Result = TestPhaseUtilsClass.complete_setup(engine)
	if not setup_r.ok:
		return Result.failure("构造恢复测试历史失败: %s" % setup_r.error)
	var archive_r: Result = engine.create_archive()
	if not archive_r.ok:
		return Result.failure("创建恢复测试存档失败: %s" % archive_r.error)
	return Result.success(Dictionary(archive_r.value).duplicate(true))

static func _build_midpoint_resume_archive(base_archive: Dictionary) -> Result:
	var commands_val = base_archive.get("commands", null)
	if not (commands_val is Array) or Array(commands_val).size() < 2:
		return Result.failure("恢复测试需要至少 2 条命令历史")
	var selected_index := maxi(0, int(floor(float(Array(commands_val).size()) / 2.0)) - 1)
	var preview_engine = GameEngineClass.new()
	var load_r: Result = preview_engine.load_from_archive(base_archive)
	if not load_r.ok:
		return Result.failure("预览恢复测试存档失败: %s" % load_r.error)
	var rewind_r: Result = preview_engine.rewind_to_command(selected_index)
	if not rewind_r.ok:
		return Result.failure("预览切换恢复点失败: %s" % rewind_r.error)
	var preview_state = preview_engine.get_state()
	if preview_state == null:
		return Result.failure("预览恢复点状态为空")
	if not (preview_state.rules is Dictionary):
		preview_state.rules = {}
	preview_state.rules[ONLINE_DINNERTIME_CONFIRM_KEY] = 1
	preview_state.rules[ONLINE_MARKETING_CONFIRM_KEY] = 1
	var archive: Dictionary = base_archive.duplicate(true)
	archive["current_index"] = selected_index
	var expected_hash := str(preview_state.compute_hash())
	archive["final_hash"] = expected_hash
	var phase_text := str(preview_state.phase)
	var sub_phase_text := str(preview_state.sub_phase).strip_edges()
	if not sub_phase_text.is_empty():
		phase_text += " / %s" % sub_phase_text
	return Result.success({
		"archive": archive,
		"selected_index": selected_index,
		"round_number": int(preview_state.round_number),
		"phase": phase_text,
		"expected_hash": expected_hash,
	})

static func _extract_snapshot_archive(sent: Array[Dictionary], peer_id: int) -> Result:
	var manifest: Dictionary = {}
	var chunks: Dictionary = {}
	for item_val in sent:
		if not (item_val is Dictionary):
			continue
		var item: Dictionary = Dictionary(item_val)
		if int(item.get("peer_id", -1)) != int(peer_id):
			continue
		var method := str(item.get("method", "")).strip_edges()
		var payload_val = item.get("payload", null)
		if not (payload_val is Dictionary):
			continue
		var payload: Dictionary = Dictionary(payload_val).duplicate(true)
		if method == "rpc_resync_snapshot_manifest":
			manifest = payload
			chunks.clear()
			continue
		if method != "rpc_resync_snapshot_chunk":
			continue
		if manifest.is_empty():
			continue
		if str(payload.get("transfer_id", "")).strip_edges() != str(manifest.get("transfer_id", "")).strip_edges():
			continue
		var bytes_val = payload.get("bytes", null)
		if not (bytes_val is PackedByteArray):
			return Result.failure("snapshot chunk bytes invalid")
		chunks[int(payload.get("chunk_index", -1))] = bytes_val
	if manifest.is_empty():
		return Result.failure("snapshot manifest missing")
	var assemble_r: Result = ResyncSnapshotTransferClass.assemble_snapshot(manifest, chunks)
	if not assemble_r.ok:
		return assemble_r
	return Result.success(Dictionary(assemble_r.value).duplicate(true))

static func _reset_net_context() -> void:
	if NetContext != null and NetContext.has_method("reset"):
		NetContext.reset()

class _MockMultiplayer:
	extends RefCounted
	var remote_sender_id: int = 0

	func get_remote_sender_id() -> int:
		return int(remote_sender_id)

class _MockPeer:
	extends RefCounted

	var outbound_buffer_size: int = 0

	func _init(buffer_size: int) -> void:
		outbound_buffer_size = int(buffer_size)

class _MockNetClient:
	extends RefCounted

	var multiplayer := _MockMultiplayer.new()
	var _room_manager = null
	var _profile_by_peer_id: Dictionary = {}
	var sent: Array[Dictionary] = []
	var _peer = _MockPeer.new(16 * 1024 * 1024)

	func _init(room_manager) -> void:
		_room_manager = room_manager

	func rpc_id(peer_id: int, method: String, payload: Dictionary) -> void:
		sent.append({
			"peer_id": int(peer_id),
			"method": str(method),
			"payload": payload.duplicate(true),
		})

static func _has_empty_room_state_push(sent: Array[Dictionary], peer_id: int) -> bool:
	for item in sent:
		if int(item.get("peer_id", -1)) != int(peer_id):
			continue
		if str(item.get("method", "")) != "rpc_room_state":
			continue
		var payload = item.get("payload", null)
		if not (payload is Dictionary):
			continue
		var room_state: Dictionary = Dictionary(payload)
		if str(room_state.get("room_code", "")).strip_edges().is_empty():
			return true
	return false

static func _find_sent_method(sent: Array[Dictionary], peer_id: int, method: String) -> int:
	for i in range(sent.size()):
		var item: Dictionary = Dictionary(sent[i])
		if int(item.get("peer_id", -1)) != int(peer_id):
			continue
		if str(item.get("method", "")) != str(method):
			continue
		return i
	return -1

static func _get_sent_payload(sent: Array[Dictionary], peer_id: int, method: String) -> Dictionary:
	var idx := _find_sent_method(sent, peer_id, method)
	if idx < 0 or idx >= sent.size():
		return {}
	var item: Dictionary = Dictionary(sent[idx])
	var payload_val = item.get("payload", null)
	if not (payload_val is Dictionary):
		return {}
	return Dictionary(payload_val).duplicate(true)

static func _find_request_rejected(sent: Array[Dictionary], peer_id: int, request_id: String, code: String) -> int:
	for i in range(sent.size()):
		var item: Dictionary = Dictionary(sent[i])
		if int(item.get("peer_id", -1)) != int(peer_id):
			continue
		if str(item.get("method", "")) != "rpc_request_rejected":
			continue
		var payload_val = item.get("payload", null)
		if not (payload_val is Dictionary):
			continue
		var payload: Dictionary = Dictionary(payload_val)
		if str(payload.get("request_id", "")) != str(request_id):
			continue
		if str(payload.get("code", "")) != str(code):
			continue
		return i
	return -1
