class_name ServerResyncGuardTest
extends RefCounted

const CommandClass = preload("res://core/types/command.gd")
const ServerLogicClass = preload("res://autoload/net_client/server.gd")
const RoomManagerClass = preload("res://server/room_manager.gd")
const GameDefaultsClass = preload("res://core/engine/game_defaults.gd")
const StateUpdaterClass = preload("res://core/state/state_updater.gd")
const ActionIdsClass = preload("res://core/actions/action_ids.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")

static func run() -> Result:
	_reset_net_context()
	if NetContext == null:
		return Result.failure("NetContext autoload missing")
	NetContext.mode = NetContext.Mode.ONLINE_SERVER

	var oversize_r := _run_oversize_archive_case()
	if not oversize_r.ok:
		_reset_net_context()
		return oversize_r

	var delta_r := _run_delta_case()
	if not delta_r.ok:
		_reset_net_context()
		return delta_r

	var rewind_meta_r := _run_rewind_meta_case()
	if not rewind_meta_r.ok:
		_reset_net_context()
		return rewind_meta_r

	var rewind_actor_scope_r := _run_rewind_actor_scope_case()
	if not rewind_actor_scope_r.ok:
		_reset_net_context()
		return rewind_actor_scope_r

	var rollback_last_r := _run_rollback_last_command_case()
	if not rollback_last_r.ok:
		_reset_net_context()
		return rollback_last_r

	var rollback_proposal_r := _run_rollback_proposal_case()
	if not rollback_proposal_r.ok:
		_reset_net_context()
		return rollback_proposal_r

	var rate_limit_r := _run_rate_limit_case()
	_reset_net_context()
	if not rate_limit_r.ok:
		return rate_limit_r
	return Result.success()

static func _run_oversize_archive_case() -> Result:
	var setup_r := _build_in_game_room_setup()
	if not setup_r.ok:
		return setup_r
	var setup: Dictionary = Dictionary(setup_r.value)
	var mock_net := _MockNetClient.new(setup.get("room_manager", null), 128)
	var server = ServerLogicClass.new()
	server.setup(mock_net)

	mock_net.multiplayer.remote_sender_id = 11
	server.handle_rpc_resync_request({"request_id": "req_oversize"})

	if _find_sent_method(mock_net.sent, 11, "rpc_resync_snapshot_manifest") != -1:
		return Result.failure("超限 snapshot manifest 不应被发送")
	if _find_sent_method(mock_net.sent, 11, "rpc_resync_snapshot_chunk") != -1:
		return Result.failure("超限 snapshot chunk 不应被发送")
	var reject_idx := _find_request_rejected(mock_net.sent, 11, "req_oversize", "resync_archive_too_large")
	if reject_idx < 0:
		return Result.failure("超限 archive 应返回 resync_archive_too_large，实际=%s" % str(mock_net.sent))
	return Result.success()

static func _run_rate_limit_case() -> Result:
	var setup_r := _build_in_game_room_setup()
	if not setup_r.ok:
		return setup_r
	var setup: Dictionary = Dictionary(setup_r.value)
	var mock_net := _MockNetClient.new(setup.get("room_manager", null), 16 * 1024 * 1024)
	var server = ServerLogicClass.new()
	server.setup(mock_net)

	mock_net.multiplayer.remote_sender_id = 11
	server.handle_rpc_resync_request({"request_id": "req_ok"})
	if _find_sent_method(mock_net.sent, 11, "rpc_resync_snapshot_manifest") < 0:
		return Result.failure("首次 ResyncRequest 应发送 snapshot manifest")
	if _find_sent_method(mock_net.sent, 11, "rpc_resync_snapshot_chunk") < 0:
		return Result.failure("首次 ResyncRequest 应发送 snapshot chunk")
	if _find_sent_method(mock_net.sent, 11, "rpc_resync_archive") >= 0:
		return Result.failure("snapshot 主链路不应再发送旧 rpc_resync_archive")

	var before_count := mock_net.sent.size()
	server.handle_rpc_resync_request({"request_id": "req_rate_limit"})
	if mock_net.sent.size() <= before_count:
		return Result.failure("重复 ResyncRequest 应返回限流拒绝")
	var reject_idx := _find_request_rejected(mock_net.sent, 11, "req_rate_limit", "resync_rate_limited")
	if reject_idx < 0:
		return Result.failure("重复 ResyncRequest 应返回 resync_rate_limited，实际=%s" % str(mock_net.sent))
	return Result.success()

static func _run_delta_case() -> Result:
	var setup_r := _build_in_game_room_setup()
	if not setup_r.ok:
		return setup_r
	var setup: Dictionary = Dictionary(setup_r.value)
	var room = setup.get("room", null)
	if room == null:
		return Result.failure("delta case 缺少 room")
	var mock_net := _MockNetClient.new(setup.get("room_manager", null), 16 * 1024 * 1024)
	var server = ServerLogicClass.new()
	server.setup(mock_net)

	var initial_hash := ""
	if room.has_method("get_resume_cursor"):
		var cursor0: Dictionary = room.get_resume_cursor()
		initial_hash = str(cursor0.get("last_state_hash", ""))
	if initial_hash.is_empty():
		return Result.failure("delta case 缺少初始 checkpoint hash")

	var actor := int(room.game_engine.get_state().get_current_player_id())
	var cmd := CommandClass.create("select_reserve_card", actor, {"selected_index": 0})
	var exec_r: Result = room.game_engine.execute_command(cmd)
	if not exec_r.ok:
		return Result.failure("delta case 执行命令失败: %s" % exec_r.error)
	server.broadcast_command_applied(room, cmd)
	mock_net.sent.clear()

	mock_net.multiplayer.remote_sender_id = 11
	server.handle_rpc_resync_request({
		"request_id": "req_delta",
		"resume_cursor": {
			"checkpoint_id": "cp_initial",
			"last_applied_sequence": 0,
			"last_state_hash": initial_hash,
		},
	})
	if _find_sent_method(mock_net.sent, 11, "rpc_resync_delta") < 0:
		return Result.failure("匹配 cursor 时应优先发送 rpc_resync_delta，实际=%s" % str(mock_net.sent))
	if _find_sent_method(mock_net.sent, 11, "rpc_resync_snapshot_manifest") >= 0:
		return Result.failure("匹配 cursor 时不应回退到 snapshot archive")

	mock_net.sent.clear()
	server.handle_rpc_resync_request({
		"request_id": "req_force_snapshot",
		"resume_cursor": {
			"checkpoint_id": "cp_initial",
			"last_applied_sequence": 0,
			"last_state_hash": initial_hash,
			"force_snapshot": true,
		},
	})
	if _find_sent_method(mock_net.sent, 11, "rpc_resync_snapshot_manifest") < 0:
		return Result.failure("force_snapshot 时应允许立即回退到 snapshot manifest，实际=%s" % str(mock_net.sent))
	if _find_sent_method(mock_net.sent, 11, "rpc_resync_snapshot_chunk") < 0:
		return Result.failure("force_snapshot 时应允许立即发送 snapshot chunk，实际=%s" % str(mock_net.sent))
	if _find_sent_method(mock_net.sent, 11, "rpc_resync_archive") >= 0:
		return Result.failure("force_snapshot fallback 不应再发送旧 rpc_resync_archive")
	if _find_request_rejected(mock_net.sent, 11, "req_force_snapshot", "resync_rate_limited") >= 0:
		return Result.failure("force_snapshot fallback 不应被 resync_rate_limited 拒绝")
	var force_prepared_r: Result = server._resync_service.build_best_effort_resume_transfer(room, {
		"checkpoint_id": "cp_initial",
		"last_applied_sequence": 0,
		"last_state_hash": initial_hash,
		"force_snapshot": true,
	})
	if not force_prepared_r.ok:
		return Result.failure("force_snapshot prepared transfer 应成功: %s" % force_prepared_r.error)
	var force_prepared: Dictionary = force_prepared_r.value
	if str(force_prepared.get("fallback_reason_code", "")) != "force_snapshot_requested":
		return Result.failure("force_snapshot fallback class 错误: %s" % str(force_prepared))

	server._resync_service.forget_peer(11)
	mock_net.sent.clear()
	server.handle_rpc_resync_request({
		"request_id": "req_snapshot_fallback",
		"resume_cursor": {
			"checkpoint_id": "cp_initial",
			"last_applied_sequence": 0,
			"last_state_hash": "mismatched_hash",
		},
	})
	if _find_sent_method(mock_net.sent, 11, "rpc_resync_snapshot_manifest") < 0:
		return Result.failure("hash 不匹配时应回退到 snapshot manifest，实际=%s" % str(mock_net.sent))
	if _find_sent_method(mock_net.sent, 11, "rpc_resync_snapshot_chunk") < 0:
		return Result.failure("hash 不匹配时应发送 snapshot chunk，实际=%s" % str(mock_net.sent))
	if _find_sent_method(mock_net.sent, 11, "rpc_resync_archive") >= 0:
		return Result.failure("hash 不匹配 fallback 不应再发送旧 rpc_resync_archive")
	var mismatch_prepared_r: Result = server._resync_service.build_best_effort_resume_transfer(room, {
		"checkpoint_id": "cp_initial",
		"last_applied_sequence": 0,
		"last_state_hash": "mismatched_hash",
	})
	if not mismatch_prepared_r.ok:
		return Result.failure("hash mismatch prepared transfer 应成功: %s" % mismatch_prepared_r.error)
	var mismatch_prepared: Dictionary = mismatch_prepared_r.value
	if str(mismatch_prepared.get("fallback_reason_code", "")) != "cursor_hash_mismatch":
		return Result.failure("hash mismatch fallback class 错误: %s" % str(mismatch_prepared))

	room._resume_delta_store.set_unhealthy_reason("test recovery store unhealthy")
	var unhealthy_prepared_r: Result = server._resync_service.build_best_effort_resume_transfer(room, {
		"checkpoint_id": "cp_initial",
		"last_applied_sequence": 0,
		"last_state_hash": initial_hash,
	})
	room._resume_delta_store.set_unhealthy_reason("")
	if not unhealthy_prepared_r.ok:
		return Result.failure("unhealthy recovery store prepared transfer 应回退 snapshot: %s" % unhealthy_prepared_r.error)
	var unhealthy_prepared: Dictionary = unhealthy_prepared_r.value
	if str(unhealthy_prepared.get("fallback_reason_code", "")) != "recovery_store_unhealthy":
		return Result.failure("unhealthy recovery store fallback class 错误: %s" % str(unhealthy_prepared))
	return Result.success()

static func _run_rewind_meta_case() -> Result:
	var setup_r := _build_in_game_room_setup()
	if not setup_r.ok:
		return setup_r
	var setup: Dictionary = Dictionary(setup_r.value)
	var room = setup.get("room", null)
	if room == null:
		return Result.failure("rewind meta case 缺少 room")
	var mock_net := _MockNetClient.new(setup.get("room_manager", null), 16 * 1024 * 1024)
	var server = ServerLogicClass.new()
	server.setup(mock_net)

	var state = room.game_engine.get_state()
	if state == null:
		return Result.failure("rewind meta case 缺少 state")
	var current_actor := int(state.get_current_player_id())
	var peer_id := -1
	for peer_key in Dictionary(room.player_id_by_peer_id).keys():
		if int(room.player_id_by_peer_id.get(peer_key, -1)) != current_actor:
			continue
		peer_id = int(peer_key)
		break
	if peer_id <= 0:
		return Result.failure("rewind meta case 找不到当前玩家 peer actor=%d map=%s" % [current_actor, str(room.player_id_by_peer_id)])
	mock_net.multiplayer.remote_sender_id = peer_id
	server.handle_rpc_rewind_to_turn_start({"request_id": "req_rewind"})

	for target_peer_id in Array(room.get_peer_ids()):
		var pid := int(target_peer_id)
		if _find_sent_method(mock_net.sent, pid, "rpc_rollback_meta") < 0:
			return Result.failure("rewind 应广播 rpc_rollback_meta 给 peer=%d: %s" % [pid, str(mock_net.sent)])
		if _find_sent_method(mock_net.sent, pid, "rpc_resync_archive") >= 0:
			return Result.failure("rewind 元数据不应再复用旧 rpc_resync_archive: %s" % str(mock_net.sent))

	for item in mock_net.sent:
		var sent_item: Dictionary = Dictionary(item)
		if str(sent_item.get("method", "")) != "rpc_rollback_meta":
			continue
		var payload_val = sent_item.get("payload", null)
		if not (payload_val is Dictionary):
			return Result.failure("rewind meta payload 类型错误: %s" % str(sent_item))
		var payload: Dictionary = Dictionary(payload_val)
		if payload.has("archive"):
			return Result.failure("rewind meta payload 不应再包在 archive 字段内: %s" % str(payload))
		if str(payload.get("request_id", "")) != "req_rewind":
			return Result.failure("rewind meta request_id 错误: %s" % str(payload))
	return Result.success()

static func _run_rewind_actor_scope_case() -> Result:
	var setup_r := _build_in_game_room_setup()
	if not setup_r.ok:
		return setup_r
	var setup: Dictionary = Dictionary(setup_r.value)
	var room = setup.get("room", null)
	if room == null:
		return Result.failure("rewind actor scope case 缺少 room")
	var prepare_r := _prepare_restructuring_actor_scope_history(room)
	if not prepare_r.ok:
		return prepare_r
	var prepare: Dictionary = Dictionary(prepare_r.value)
	var expected_target := int(prepare.get("expected_target", -999))
	var p0_submit_index := int(prepare.get("p0_submit_index", -1))
	var p1_direct_index := int(prepare.get("p1_direct_index", -1))
	if expected_target < 0:
		return Result.failure("rewind actor scope case expected_target 无效: %d" % expected_target)

	var mock_net := _MockNetClient.new(setup.get("room_manager", null), 16 * 1024 * 1024)
	var server = ServerLogicClass.new()
	server.setup(mock_net)

	mock_net.multiplayer.remote_sender_id = 11
	server.handle_rpc_rewind_to_turn_start({"request_id": "req_rewind_actor_scope"})

	var idx := _find_sent_method(mock_net.sent, 11, "rpc_rollback_meta")
	if idx < 0:
		return Result.failure("actor scope rewind 应发送 meta 给 P2，实际=%s" % str(mock_net.sent))
	var payload_val = Dictionary(mock_net.sent[idx]).get("payload", null)
	if not (payload_val is Dictionary):
		return Result.failure("actor scope rewind payload 类型错误: %s" % str(mock_net.sent[idx]))
	var payload: Dictionary = Dictionary(payload_val)
	if int(payload.get("player_id", -1)) != 1:
		return Result.failure("actor scope rewind 应记录发起玩家 P2: %s" % str(payload))
	if int(payload.get("target_index", -999)) != expected_target:
		return Result.failure(
			"actor scope rewind target 错误: got=%d want=%d p0_submit=%d p1_direct=%d payload=%s"
				% [int(payload.get("target_index", -999)), expected_target, p0_submit_index, p1_direct_index, str(payload)]
		)
	if int(room.game_engine.current_command_index) != expected_target:
		return Result.failure("actor scope rewind 后 engine current_index 错误: got=%d want=%d" % [int(room.game_engine.current_command_index), expected_target])
	if int(room.game_engine.command_history.size()) != expected_target + 1:
		return Result.failure("actor scope rewind 后 history_size 错误: got=%d want=%d" % [int(room.game_engine.command_history.size()), expected_target + 1])
	return Result.success()

static func _run_rollback_last_command_case() -> Result:
	var setup_r := _build_in_game_room_setup()
	if not setup_r.ok:
		return setup_r
	var setup: Dictionary = Dictionary(setup_r.value)
	var room = setup.get("room", null)
	if room == null or room.game_engine == null:
		return Result.failure("rollback last case 缺少 room/engine")
	var engine = room.game_engine
	var state = engine.get_state()
	if state == null:
		return Result.failure("rollback last case state 为空")
	var actor := int(state.get_current_player_id())
	var peer_id := -1
	for peer_key in Dictionary(room.player_id_by_peer_id).keys():
		if int(room.player_id_by_peer_id.get(peer_key, -1)) != actor:
			continue
		peer_id = int(peer_key)
		break
	if peer_id <= 0:
		return Result.failure("rollback last case 找不到 actor peer actor=%d map=%s" % [actor, str(room.player_id_by_peer_id)])

	var before_index := int(engine.current_command_index)
	var cmd := CommandClass.create("select_reserve_card", actor, {"selected_index": 0})
	var exec_r: Result = engine.execute_command(cmd)
	if not exec_r.ok:
		return Result.failure("rollback last case 执行命令失败: %s" % exec_r.error)
	var rolled_back_index := int(engine.current_command_index)
	if rolled_back_index != before_index + 1:
		return Result.failure("rollback last case 准备历史失败 before=%d current=%d" % [before_index, rolled_back_index])

	var mock_net := _MockNetClient.new(setup.get("room_manager", null), 16 * 1024 * 1024)
	var server = ServerLogicClass.new()
	server.setup(mock_net)

	mock_net.multiplayer.remote_sender_id = peer_id
	server.handle_rpc_rollback_last_command({"request_id": "req_rollback_last"})

	for target_peer_id in Array(room.get_peer_ids()):
		var pid := int(target_peer_id)
		if _find_sent_method(mock_net.sent, pid, "rpc_rollback_meta") < 0:
			return Result.failure("rollback last 应广播 rpc_rollback_meta 给 peer=%d: %s" % [pid, str(mock_net.sent)])
	var idx := _find_sent_method(mock_net.sent, peer_id, "rpc_rollback_meta")
	if idx < 0:
		return Result.failure("rollback last 缺少发起者 meta: %s" % str(mock_net.sent))
	var payload_val = Dictionary(mock_net.sent[idx]).get("payload", null)
	if not (payload_val is Dictionary):
		return Result.failure("rollback last payload 类型错误: %s" % str(mock_net.sent[idx]))
	var payload: Dictionary = Dictionary(payload_val)
	if str(payload.get("reason", "")) != "undo_last_command":
		return Result.failure("rollback last reason 错误: %s" % str(payload))
	if int(payload.get("target_index", -999)) != before_index:
		return Result.failure("rollback last target 错误: got=%d want=%d payload=%s" % [int(payload.get("target_index", -999)), before_index, str(payload)])
	if int(payload.get("rolled_back_index", -999)) != rolled_back_index:
		return Result.failure("rollback last rolled_back_index 错误: %s" % str(payload))
	if str(payload.get("rolled_back_action_id", "")) != "select_reserve_card":
		return Result.failure("rollback last rolled_back_action_id 错误: %s" % str(payload))
	if int(engine.current_command_index) != before_index:
		return Result.failure("rollback last 后 engine current_index 错误: got=%d want=%d" % [int(engine.current_command_index), before_index])
	if int(engine.command_history.size()) != before_index + 1:
		return Result.failure("rollback last 后 history_size 错误: got=%d want=%d" % [int(engine.command_history.size()), before_index + 1])
	return Result.success()

static func _run_rollback_proposal_case() -> Result:
	var setup_r := _build_in_game_room_setup()
	if not setup_r.ok:
		return setup_r
	var setup: Dictionary = Dictionary(setup_r.value)
	var room = setup.get("room", null)
	if room == null or room.game_engine == null:
		return Result.failure("rollback proposal case 缺少 room/engine")
	var engine = room.game_engine
	var state = engine.get_state()
	if state == null:
		return Result.failure("rollback proposal case state 为空")
	var actor := int(state.get_current_player_id())
	var host_peer_id := int(room.host_peer_id)
	if host_peer_id <= 0:
		return Result.failure("rollback proposal case 缺少 host peer")

	var before_index := int(engine.current_command_index)
	var cmd := CommandClass.create("select_reserve_card", actor, {"selected_index": 0})
	var exec_r: Result = engine.execute_command(cmd)
	if not exec_r.ok:
		return Result.failure("rollback proposal case 执行命令失败: %s" % exec_r.error)
	var proposed_from_index := int(engine.current_command_index)
	if proposed_from_index != before_index + 1:
		return Result.failure("rollback proposal case 准备历史失败 before=%d current=%d" % [before_index, proposed_from_index])

	var mock_net := _MockNetClient.new(setup.get("room_manager", null), 16 * 1024 * 1024)
	var server = ServerLogicClass.new()
	server.setup(mock_net)

	mock_net.multiplayer.remote_sender_id = 11
	server.handle_rpc_request_rollback_proposal({
		"request_id": "req_proposal",
		"target_index": before_index,
	})

	var host_state_idx := _find_sent_method(mock_net.sent, host_peer_id, "rpc_room_state")
	if host_state_idx < 0:
		return Result.failure("非房主创建提议后应广播 room_state 给 host: %s" % str(mock_net.sent))
	var state_payload_val = Dictionary(mock_net.sent[host_state_idx]).get("payload", null)
	if not (state_payload_val is Dictionary):
		return Result.failure("rollback proposal room_state payload 类型错误")
	var state_payload: Dictionary = Dictionary(state_payload_val)
	var proposal_val = state_payload.get("rollback_proposal", null)
	if not (proposal_val is Dictionary):
		return Result.failure("room_state 应包含 rollback_proposal: %s" % str(state_payload))
	var proposal: Dictionary = Dictionary(proposal_val)
	if str(proposal.get("proposal_id", "")) != "req_proposal":
		return Result.failure("proposal_id 错误: %s" % str(proposal))
	if int(proposal.get("target_index", -999)) != before_index:
		return Result.failure("proposal target 错误: %s" % str(proposal))
	if int(proposal.get("before_index", -999)) != proposed_from_index:
		return Result.failure("proposal before_index 错误: %s" % str(proposal))
	if bool(proposal.get("self_vote", true)):
		return Result.failure("host 在投票前 self_vote 应为 false: %s" % str(proposal))
	if int(proposal.get("proposer_player_id", -1)) != 1:
		return Result.failure("非房主提议应记录 proposer_player_id=P2: %s" % str(proposal))
	var rollback_summaries_val = proposal.get("rollback_summaries", null)
	if not (rollback_summaries_val is Array) or Array(rollback_summaries_val).is_empty():
		return Result.failure("proposal 应包含将撤销命令摘要: %s" % str(proposal))
	var rollback_summary_val = Array(rollback_summaries_val)[0]
	if not (rollback_summary_val is Dictionary):
		return Result.failure("proposal rollback_summaries[0] 类型错误: %s" % str(proposal))
	var rollback_summary: Dictionary = Dictionary(rollback_summary_val)
	var rollback_summary_text := str(rollback_summary.get("text", "")).strip_edges()
	if rollback_summary_text.find("选择储备卡") < 0:
		return Result.failure("proposal 摘要应显示动作名，实际: %s" % rollback_summary_text)
	if rollback_summary_text.find("<hidden>") < 0:
		return Result.failure("proposal 公共摘要应脱敏隐藏参数，实际: %s" % rollback_summary_text)
	if rollback_summary_text.find("selected_index=0") >= 0:
		return Result.failure("proposal 公共摘要不应泄露 selected_index=0，实际: %s" % rollback_summary_text)

	mock_net.sent.clear()
	mock_net.multiplayer.remote_sender_id = host_peer_id
	server.handle_rpc_action_request({
		"request_id": "req_action_while_proposal",
		"action_id": "select_reserve_card",
		"params": {"selected_index": 0},
	})
	if _find_request_rejected(mock_net.sent, host_peer_id, "req_action_while_proposal", "rollback_proposal_pending") < 0:
		return Result.failure("回滚提议待投票时应拒绝新动作: %s" % str(mock_net.sent))

	mock_net.sent.clear()
	mock_net.multiplayer.remote_sender_id = host_peer_id
	server.handle_rpc_vote_rollback_proposal({
		"request_id": "req_vote",
		"proposal_id": "req_proposal",
		"approve": true,
	})

	for target_peer_id in Array(room.get_peer_ids()):
		var pid := int(target_peer_id)
		if _find_sent_method(mock_net.sent, pid, "rpc_rollback_meta") < 0:
			return Result.failure("提议回滚通过后应广播 rpc_rollback_meta 给 peer=%d: %s" % [pid, str(mock_net.sent)])
	var meta_idx := _find_sent_method(mock_net.sent, host_peer_id, "rpc_rollback_meta")
	if meta_idx < 0:
		return Result.failure("提议回滚缺少 host meta: %s" % str(mock_net.sent))
	var payload_val = Dictionary(mock_net.sent[meta_idx]).get("payload", null)
	if not (payload_val is Dictionary):
		return Result.failure("提议回滚 meta payload 类型错误: %s" % str(mock_net.sent[meta_idx]))
	var payload: Dictionary = Dictionary(payload_val)
	if str(payload.get("reason", "")) != "proposal_rollback":
		return Result.failure("提议回滚 reason 错误: %s" % str(payload))
	if str(payload.get("proposal_id", "")) != "req_proposal":
		return Result.failure("提议回滚 proposal_id 错误: %s" % str(payload))
	if int(payload.get("proposer_player_id", -1)) != 1:
		return Result.failure("提议回滚 proposer_player_id 错误: %s" % str(payload))
	if int(payload.get("target_index", -999)) != before_index:
		return Result.failure("提议回滚 target 错误: got=%d want=%d payload=%s" % [int(payload.get("target_index", -999)), before_index, str(payload)])
	if int(engine.current_command_index) != before_index:
		return Result.failure("提议回滚后 engine current_index 错误: got=%d want=%d" % [int(engine.current_command_index), before_index])
	if int(engine.command_history.size()) != before_index + 1:
		return Result.failure("提议回滚后 history_size 错误: got=%d want=%d" % [int(engine.command_history.size()), before_index + 1])
	var last_state_idx := _find_last_sent_method(mock_net.sent, 11, "rpc_room_state")
	if last_state_idx < 0:
		return Result.failure("提议回滚完成后应广播 room_state")
	var last_state_val = Dictionary(mock_net.sent[last_state_idx]).get("payload", null)
	if last_state_val is Dictionary and Dictionary(last_state_val).has("rollback_proposal"):
		return Result.failure("提议回滚完成后 pending proposal 应清空: %s" % str(last_state_val))
	return Result.success()

static func _prepare_restructuring_actor_scope_history(room) -> Result:
	if room == null or room.game_engine == null:
		return Result.failure("actor scope setup 缺少 engine")
	var engine = room.game_engine
	var state = engine.get_state()
	if state == null:
		return Result.failure("actor scope setup state 为空")
	state.round_number = 1
	var clear_pending_r := _clear_setup_pending_for_direct_phase_jump(state)
	if not clear_pending_r.ok:
		return clear_pending_r
	var checkpoint_r := _sync_initial_checkpoint(engine)
	if not checkpoint_r.ok:
		return checkpoint_r
	var adv: Result = engine.execute_command(CommandClass.create_system(ActionIdsClass.ADVANCE_PHASE))
	if not adv.ok:
		return Result.failure("actor scope setup 推进到 Restructuring 失败: %s" % adv.error)
	state = engine.get_state()
	if str(state.phase) != DefsClass.PHASE_RESTRUCTURING:
		return Result.failure("actor scope setup 应在 Restructuring，实际: %s" % str(state.phase))
	var p0_submit: Result = engine.execute_command(CommandClass.create("submit_restructuring", 0, {}))
	if not p0_submit.ok:
		return Result.failure("actor scope setup P1 submit 失败: %s" % p0_submit.error)
	var p0_submit_index := int(engine.current_command_index)

	state = engine.get_state()
	var take := StateUpdaterClass.take_from_pool(state, "local_manager", 1)
	if not take.ok:
		return Result.failure("actor scope setup 取 local_manager 失败: %s" % take.error)
	var add := StateUpdaterClass.add_employee(state, 1, "local_manager", true)
	if not add.ok:
		return Result.failure("actor scope setup 给 P2 添加 local_manager 失败: %s" % add.error)

	var p1_direct: Result = engine.execute_command(CommandClass.create("set_company_structure_direct", 1, {
		"slot_index": 0,
		"employee_id": "local_manager",
	}))
	if not p1_direct.ok:
		return Result.failure("actor scope setup P2 direct 失败: %s" % p1_direct.error)
	var p1_direct_index := int(engine.current_command_index)
	state = engine.get_state()
	if state != null:
		state.current_player_index = maxi(0, Array(state.turn_order).find(0))
	return Result.success({
		"expected_target": p1_direct_index - 1,
		"p0_submit_index": p0_submit_index,
		"p1_direct_index": p1_direct_index,
	})

static func _clear_setup_pending_for_direct_phase_jump(state: GameState) -> Result:
	if state == null:
		return Result.failure("direct phase jump state 为空")
	if not (state.round_state is Dictionary):
		return Result.failure("direct phase jump round_state 类型错误（期望 Dictionary）")
	var ppa_val = state.round_state.get("pending_phase_actions", null)
	if ppa_val == null:
		return Result.success()
	if not (ppa_val is Dictionary):
		return Result.failure("direct phase jump pending_phase_actions 类型错误（期望 Dictionary）")
	var ppa: Dictionary = Dictionary(ppa_val).duplicate(true)
	ppa.erase(DefsClass.PHASE_SETUP)
	state.round_state["pending_phase_actions"] = ppa
	return Result.success()

static func _sync_initial_checkpoint(engine) -> Result:
	if engine == null:
		return Result.failure("sync checkpoint: engine 为空")
	var state: GameState = engine.get_state()
	if state == null:
		return Result.failure("sync checkpoint: state 为空")
	if engine.checkpoints.is_empty() or not (engine.checkpoints[0] is Dictionary):
		return Result.failure("sync checkpoint: 缺少初始 checkpoint")
	var cp0: Dictionary = Dictionary(engine.checkpoints[0]).duplicate(true)
	cp0["state_dict"] = state.to_dict().duplicate(true)
	cp0["hash"] = state.compute_hash()
	if engine.random_manager != null:
		cp0["rng_calls"] = int(engine.random_manager.get_call_count())
	engine.checkpoints[0] = cp0
	return Result.success()

static func _build_in_game_room_setup() -> Result:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var room_manager = RoomManagerClass.new(rng)
	var config := {
		"desired_player_count": 2,
		"seed_mode": "fixed",
		"seed": 12345,
		"allow_spectators": true,
		"enabled_modules_v2": [],
		"modules_v2_base_dir": GameDefaultsClass.DEFAULT_MODULES_V2_BASE_DIR,
	}
	var host_profile := {
		"name": "Host",
		"color_index": 0,
		"restaurant_logo_id": -1,
		"user_id": "u_host_resync_guard",
	}
	var create_r: Result = room_manager.create_room(10, host_profile, "", config)
	if not create_r.ok:
		return Result.failure("create_room 失败: %s" % create_r.error)
	var create_payload: Dictionary = Dictionary(create_r.value)
	var room_code := str(create_payload.get("room_code", "")).strip_edges().to_upper()
	var room = create_payload.get("room", null)
	if room == null:
		return Result.failure("create_room 返回缺少 room")

	var join_r: Result = room_manager.join_room(11, {
		"name": "P2",
		"color_index": 1,
		"restaurant_logo_id": -1,
		"user_id": "u_p2_resync_guard",
	}, room_code, "")
	if not join_r.ok:
		return Result.failure("join_room 失败: %s" % join_r.error)

	var start_r: Result = room.start_game()
	if not start_r.ok:
		return Result.failure("start_game 失败: %s" % start_r.error)

	return Result.success({
		"room_manager": room_manager,
		"room": room,
		"room_code": room_code,
	})

static func _find_sent_method(sent: Array[Dictionary], peer_id: int, method: String) -> int:
	for i in range(sent.size()):
		var item: Dictionary = Dictionary(sent[i])
		if int(item.get("peer_id", -1)) != int(peer_id):
			continue
		if str(item.get("method", "")) != str(method):
			continue
		return i
	return -1

static func _find_last_sent_method(sent: Array[Dictionary], peer_id: int, method: String) -> int:
	for i in range(sent.size() - 1, -1, -1):
		var item: Dictionary = Dictionary(sent[i])
		if int(item.get("peer_id", -1)) != int(peer_id):
			continue
		if str(item.get("method", "")) != str(method):
			continue
		return i
	return -1

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
	var _peer = null
	var sent: Array[Dictionary] = []

	func _init(room_manager, buffer_size: int) -> void:
		_room_manager = room_manager
		_peer = _MockPeer.new(buffer_size)

	func rpc_id(peer_id: int, method: String, payload: Dictionary) -> void:
		sent.append({
			"peer_id": int(peer_id),
			"method": str(method),
			"payload": payload.duplicate(true),
		})
