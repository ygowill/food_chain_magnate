class_name GameOnlineResyncRequestRejectionTest
extends RefCounted

const ControllerClass = preload("res://ui/scenes/game/controllers/online_resync_controller.gd")

static func run() -> Result:
	if NetContext == null:
		return Result.failure("NetContext autoload missing")
	if NetClient == null:
		return Result.failure("NetClient autoload missing")

	var loop = Engine.get_main_loop()
	if not (loop is SceneTree):
		return Result.failure("Main loop is not SceneTree")
	var tree: SceneTree = loop
	var host := Node.new()
	tree.root.add_child(host)

	var prev_mode = NetContext.mode
	var prev_local_player_id := int(NetContext.local_player_id)
	var prev_room_state := Dictionary(NetContext.room_state).duplicate(true)
	var prev_connected := bool(NetClient._client_transport_connected)

	NetContext.mode = NetContext.Mode.ONLINE_CLIENT
	NetContext.local_player_id = 1
	NetContext.room_state = {
		"room_code": "ROOMRS",
		"status": "InGame",
		"players": [],
		"spectators": [],
	}
	NetClient._client_transport_connected = true

	var apply_failure_harness := _Harness.new(_FailingEngine.new())
	var apply_failure_controller = ControllerClass.new(
		host,
		null,
		Callable(apply_failure_harness, "get_engine"),
		Callable(),
		Callable(),
		Callable(apply_failure_harness, "update_ui"),
		Callable(),
		Callable(apply_failure_harness, "show_confirm"),
		Callable(),
		Callable(),
		Callable(),
		Callable(),
		Callable(),
		Callable(),
		Callable(apply_failure_harness, "request_resync")
	)
	apply_failure_controller._on_online_command_applied({
		"index": 0,
		"action_id": "forced_apply_failure",
		"actor": 0,
		"params": {},
		"phase": "test",
		"sub_phase": "",
		"timestamp": 1,
		"metadata": {},
	}, "unused_hash")
	if apply_failure_harness.request_resync_calls != 1:
		apply_failure_controller.dispose()
		host.queue_free()
		_restore(prev_mode, prev_local_player_id, prev_room_state, prev_connected)
		return Result.failure("命令回放失败后应立刻请求 resync: %d" % apply_failure_harness.request_resync_calls)
	if not apply_failure_controller.is_resync_in_progress():
		apply_failure_controller.dispose()
		host.queue_free()
		_restore(prev_mode, prev_local_player_id, prev_room_state, prev_connected)
		return Result.failure("命令回放失败后应进入同步中状态")
	apply_failure_controller.dispose()

	var parse_failure_harness := _Harness.new(_FailingEngine.new())
	var parse_failure_controller = ControllerClass.new(
		host,
		null,
		Callable(parse_failure_harness, "get_engine"),
		Callable(),
		Callable(),
		Callable(parse_failure_harness, "update_ui"),
		Callable(),
		Callable(parse_failure_harness, "show_confirm"),
		Callable(),
		Callable(),
		Callable(),
		Callable(),
		Callable(),
		Callable(),
		Callable(parse_failure_harness, "request_resync")
	)
	parse_failure_controller._on_online_command_applied({"index": 0}, "")
	if parse_failure_harness.request_resync_calls != 1:
		parse_failure_controller.dispose()
		host.queue_free()
		_restore(prev_mode, prev_local_player_id, prev_room_state, prev_connected)
		return Result.failure("CommandApplied 解析失败后应立刻请求 resync: %d" % parse_failure_harness.request_resync_calls)
	if parse_failure_harness.request_resync_force_flags.size() != 1 or not bool(parse_failure_harness.request_resync_force_flags[0]):
		parse_failure_controller.dispose()
		host.queue_free()
		_restore(prev_mode, prev_local_player_id, prev_room_state, prev_connected)
		return Result.failure("CommandApplied 解析失败后的 resync 应携带 force_snapshot")
	if not parse_failure_controller.is_resync_in_progress():
		parse_failure_controller.dispose()
		host.queue_free()
		_restore(prev_mode, prev_local_player_id, prev_room_state, prev_connected)
		return Result.failure("CommandApplied 解析失败后应进入同步中状态")
	parse_failure_controller.dispose()

	var pending_failure_harness := _Harness.new(_FailingEngine.new())
	var pending_failure_controller = ControllerClass.new(
		host,
		null,
		Callable(pending_failure_harness, "get_engine"),
		Callable(),
		Callable(),
		Callable(pending_failure_harness, "update_ui"),
		Callable(),
		Callable(pending_failure_harness, "show_confirm"),
		Callable(),
		Callable(),
		Callable(),
		Callable(),
		Callable(),
		Callable(),
		Callable(pending_failure_harness, "request_resync")
	)
	pending_failure_controller._pending_cmds.clear()
	pending_failure_controller._pending_cmds.append({
		"cmd_dict": {
			"index": 0,
			"action_id": "forced_pending_apply_failure",
			"actor": 0,
			"params": {},
			"phase": "test",
			"sub_phase": "",
			"timestamp": 1,
			"metadata": {},
		},
		"state_hash": "",
	})
	pending_failure_controller._flush_online_pending_commands_after_resync()
	if pending_failure_harness.request_resync_calls != 1:
		pending_failure_controller.dispose()
		host.queue_free()
		_restore(prev_mode, prev_local_player_id, prev_room_state, prev_connected)
		return Result.failure("待处理命令执行失败后应立刻请求 resync: %d" % pending_failure_harness.request_resync_calls)
	if pending_failure_harness.request_resync_force_flags.size() != 1 or not bool(pending_failure_harness.request_resync_force_flags[0]):
		pending_failure_controller.dispose()
		host.queue_free()
		_restore(prev_mode, prev_local_player_id, prev_room_state, prev_connected)
		return Result.failure("待处理命令执行失败后的 resync 应携带 force_snapshot")
	if pending_failure_harness.update_ui_calls != 0:
		pending_failure_controller.dispose()
		host.queue_free()
		_restore(prev_mode, prev_local_player_id, prev_room_state, prev_connected)
		return Result.failure("待处理命令失败后不应按成功路径刷新 UI: %d" % pending_failure_harness.update_ui_calls)
	if not pending_failure_controller.is_resync_in_progress():
		pending_failure_controller.dispose()
		host.queue_free()
		_restore(prev_mode, prev_local_player_id, prev_room_state, prev_connected)
		return Result.failure("待处理命令执行失败后应进入同步中状态")
	pending_failure_controller.dispose()

	var pending_parse_harness := _Harness.new(_FailingEngine.new())
	var pending_parse_controller = ControllerClass.new(
		host,
		null,
		Callable(pending_parse_harness, "get_engine"),
		Callable(),
		Callable(),
		Callable(pending_parse_harness, "update_ui"),
		Callable(),
		Callable(pending_parse_harness, "show_confirm"),
		Callable(),
		Callable(),
		Callable(),
		Callable(),
		Callable(),
		Callable(),
		Callable(pending_parse_harness, "request_resync")
	)
	pending_parse_controller._pending_cmds.clear()
	pending_parse_controller._pending_cmds.append({
		"cmd_dict": {"index": 0},
		"state_hash": "",
	})
	pending_parse_controller._flush_online_pending_commands_after_resync()
	if pending_parse_harness.request_resync_calls != 1:
		pending_parse_controller.dispose()
		host.queue_free()
		_restore(prev_mode, prev_local_player_id, prev_room_state, prev_connected)
		return Result.failure("待处理命令解析失败后应立刻请求 resync: %d" % pending_parse_harness.request_resync_calls)
	if pending_parse_harness.request_resync_force_flags.size() != 1 or not bool(pending_parse_harness.request_resync_force_flags[0]):
		pending_parse_controller.dispose()
		host.queue_free()
		_restore(prev_mode, prev_local_player_id, prev_room_state, prev_connected)
		return Result.failure("待处理命令解析失败后的 resync 应携带 force_snapshot")
	if pending_parse_harness.update_ui_calls != 0:
		pending_parse_controller.dispose()
		host.queue_free()
		_restore(prev_mode, prev_local_player_id, prev_room_state, prev_connected)
		return Result.failure("待处理命令解析失败后不应按成功路径刷新 UI: %d" % pending_parse_harness.update_ui_calls)
	if not pending_parse_controller.is_resync_in_progress():
		pending_parse_controller.dispose()
		host.queue_free()
		_restore(prev_mode, prev_local_player_id, prev_room_state, prev_connected)
		return Result.failure("待处理命令解析失败后应进入同步中状态")
	pending_parse_controller.dispose()

	var harness := _Harness.new()
	var controller = ControllerClass.new(
		host,
		null,
		Callable(),
		Callable(),
		Callable(),
		Callable(harness, "update_ui"),
		Callable(),
		Callable(harness, "show_confirm"),
		Callable(),
		Callable(),
		Callable(),
		Callable(),
		Callable(),
		Callable(),
		Callable(harness, "request_resync")
	)

	controller._request_online_resync("forced_mismatch")
	var first_request_id := str(controller._resync_request_id).strip_edges()
	if first_request_id.is_empty():
		controller.dispose()
		host.queue_free()
		_restore(prev_mode, prev_local_player_id, prev_room_state, prev_connected)
		return Result.failure("完整 resync 应记录 request_id")
	if not controller.is_resync_in_progress():
		controller.dispose()
		host.queue_free()
		_restore(prev_mode, prev_local_player_id, prev_room_state, prev_connected)
		return Result.failure("发送 resync 后应进入同步中状态")
	if harness.request_resync_force_flags.size() != 1 or bool(harness.request_resync_force_flags[0]):
		controller.dispose()
		host.queue_free()
		_restore(prev_mode, prev_local_player_id, prev_room_state, prev_connected)
		return Result.failure("普通 resync 不应携带 force_snapshot")
	controller._on_online_request_rejected(first_request_id, "resync_archive_too_large", "too large")
	if controller.is_resync_in_progress():
		host.queue_free()
		_restore(prev_mode, prev_local_player_id, prev_room_state, prev_connected)
		return Result.failure("resync 被拒绝后不应继续卡在同步中")
	if not str(controller._resync_request_id).strip_edges().is_empty():
		host.queue_free()
		_restore(prev_mode, prev_local_player_id, prev_room_state, prev_connected)
		return Result.failure("resync 被拒绝后应清理 request_id")

	controller._request_online_resync("forced_rate_limit")
	var second_request_id := str(controller._resync_request_id).strip_edges()
	if second_request_id.is_empty():
		controller.dispose()
		host.queue_free()
		_restore(prev_mode, prev_local_player_id, prev_room_state, prev_connected)
		return Result.failure("第二次 resync 也应记录 request_id")
	controller._on_online_request_rejected(second_request_id, "resync_rate_limited", "slow down")
	if controller.is_resync_in_progress():
		host.queue_free()
		_restore(prev_mode, prev_local_player_id, prev_room_state, prev_connected)
		return Result.failure("resync_rate_limited 后不应继续卡在同步中")
	if harness.request_resync_calls != 2:
		controller.dispose()
		host.queue_free()
		_restore(prev_mode, prev_local_player_id, prev_room_state, prev_connected)
		return Result.failure("request_resync 调用次数错误: %d" % harness.request_resync_calls)
	if harness.update_ui_calls < 2:
		controller.dispose()
		host.queue_free()
		_restore(prev_mode, prev_local_player_id, prev_room_state, prev_connected)
		return Result.failure("拒绝 resync 后应刷新 UI: %d" % harness.update_ui_calls)

	controller._resync_in_progress = true
	controller._on_online_resync_delta_failed("delta mismatch")
	if harness.request_resync_calls != 3:
		controller.dispose()
		host.queue_free()
		_restore(prev_mode, prev_local_player_id, prev_room_state, prev_connected)
		return Result.failure("delta 失败后应立刻发起 snapshot fallback: %d" % harness.request_resync_calls)
	if harness.request_resync_force_flags.size() != 3 or not bool(harness.request_resync_force_flags[2]):
		controller.dispose()
		host.queue_free()
		_restore(prev_mode, prev_local_player_id, prev_room_state, prev_connected)
		return Result.failure("delta 失败后的 fallback 应携带 force_snapshot")
	if not controller.is_resync_in_progress():
		controller.dispose()
		host.queue_free()
		_restore(prev_mode, prev_local_player_id, prev_room_state, prev_connected)
		return Result.failure("delta 失败后重新发起 snapshot fallback 时应保持同步中状态")

	controller._resync_in_progress = false
	var confirm_count_before_proposal := int(harness.show_confirm_calls)
	controller._on_online_room_state_updated_for_rollback_proposal({
		"rollback_proposal": {
			"proposal_id": "proposal_popup",
			"proposer_player_id": 0,
			"target_index": 2,
			"before_index": 5,
			"required_player_ids": [1],
			"votes": {0: true},
			"self_vote": false,
			"target_summary": {"text": "#2 P1 招聘 {employee_type=trainer}"},
			"rollback_summaries": [
				{"text": "#3 P2 选择储备卡 {selected_index=<hidden>}"},
			],
			"rollback_summaries_omitted_count": 0,
		},
	})
	if harness.show_confirm_calls != confirm_count_before_proposal + 1:
		controller.dispose()
		host.queue_free()
		_restore(prev_mode, prev_local_player_id, prev_room_state, prev_connected)
		return Result.failure("收到回滚提议后应弹出投票确认框: before=%d after=%d" % [confirm_count_before_proposal, harness.show_confirm_calls])
	if str(harness.last_confirm_body).find("命令 #2 后") < 0 or str(harness.last_confirm_body).find("撤销 3 步") < 0:
		controller.dispose()
		host.queue_free()
		_restore(prev_mode, prev_local_player_id, prev_room_state, prev_connected)
		return Result.failure("投票确认框应明确目标时间点和撤销步数: %s" % str(harness.last_confirm_body))
	if str(harness.last_confirm_body).find("招聘") < 0 or str(harness.last_confirm_body).find("选择储备卡") < 0 or str(harness.last_confirm_body).find("<hidden>") < 0:
		controller.dispose()
		host.queue_free()
		_restore(prev_mode, prev_local_player_id, prev_room_state, prev_connected)
		return Result.failure("投票确认框应显示目标/撤销动作摘要且保持脱敏: %s" % str(harness.last_confirm_body))

	controller.dispose()
	host.queue_free()
	_restore(prev_mode, prev_local_player_id, prev_room_state, prev_connected)
	return Result.success()

static func _restore(prev_mode, prev_local_player_id: int, prev_room_state: Dictionary, prev_connected: bool) -> void:
	NetContext.mode = prev_mode
	NetContext.local_player_id = int(prev_local_player_id)
	NetContext.room_state = prev_room_state.duplicate(true)
	NetClient._client_transport_connected = prev_connected

class _Harness:
	extends RefCounted

	var _engine = null
	var request_resync_calls: int = 0
	var request_resync_force_flags: Array[bool] = []
	var update_ui_calls: int = 0
	var show_confirm_calls: int = 0
	var last_confirm_title: String = ""
	var last_confirm_body: String = ""
	var last_confirm_ok: String = ""
	var last_confirm_close: String = ""

	func _init(engine = null) -> void:
		_engine = engine

	func get_engine():
		return _engine

	func request_resync(force_snapshot: bool = false) -> String:
		request_resync_calls += 1
		request_resync_force_flags.append(bool(force_snapshot))
		return "mock_resync_%d" % request_resync_calls

	func update_ui() -> void:
		update_ui_calls += 1

	func show_confirm(_title: String, _body: String, _confirmed: Callable, _cancelled: Callable, _ok: String, _close: String) -> void:
		show_confirm_calls += 1
		last_confirm_title = str(_title)
		last_confirm_body = str(_body)
		last_confirm_ok = str(_ok)
		last_confirm_close = str(_close)

class _FailingEngine:
	extends RefCounted

	var command_history: Array = []

	func execute_command(_cmd, _is_replay: bool = false) -> Result:
		return Result.failure("forced apply failure")
