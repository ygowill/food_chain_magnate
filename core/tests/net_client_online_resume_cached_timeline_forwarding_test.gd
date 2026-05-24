# NetClient：恢复房完整历史 timeline cache 应通过 autoload 包装层正确转发
class_name NetClientOnlineResumeCachedTimelineForwardingTest
extends RefCounted

const GameDefaultsClass = preload("res://core/engine/game_defaults.gd")
const GameEngineClass = preload("res://core/engine/game_engine.gd")
const GameTimelineOnlineResumeHistoryViewSupportClass = preload("res://ui/scenes/game/timeline/online_resume_history_view_support.gd")
const OnlineResumeFullHistoryAdapterClass = preload("res://ui/scenes/game/timeline/online_resume_full_history_adapter.gd")

static func run() -> Result:
	if NetClient == null:
		return Result.failure("NetClient autoload missing")
	if NetContext == null:
		return Result.failure("NetContext autoload missing")
	if Globals == null:
		return Result.failure("Globals autoload missing")
	if not NetClient.has_method("get_online_resume_full_history_step_timeline"):
		return Result.failure("NetClient 缺少 get_online_resume_full_history_step_timeline()")
	if not NetClient.has_method("set_online_resume_full_history_step_timeline"):
		return Result.failure("NetClient 缺少 set_online_resume_full_history_step_timeline()")
	if not NetClient.has_method("get_online_resume_full_history_step_timeline_entries"):
		return Result.failure("NetClient 缺少 get_online_resume_full_history_step_timeline_entries()")
	if not NetClient.has_method("set_online_resume_full_history_step_timeline_entries"):
		return Result.failure("NetClient 缺少 set_online_resume_full_history_step_timeline_entries()")
	if NetClient.has_signal("resume_fast_start_ready"):
		return Result.failure("NetClient 不应再暴露 resume_fast_start_ready 信号")

	NetClient.clear_online_resume_full_history_state()

	var cached_timeline := {
		"_build_meta": {
			"processed_command_count": 248,
			"last_event_sequence": 512,
		},
		"steps": [
			{
				"anchor_command_index": 247,
				"kind": "command",
				"phase": "Working",
				"round": 5,
				"state_dict": {
					"sentinel": {"value": 7},
				},
			},
		],
		"events": [
			{
				"sequence": 512,
				"command_index": 247,
				"step_index": 0,
			},
		],
	}

	NetClient.set_online_resume_full_history_step_timeline(cached_timeline)
	NetClient.set_online_resume_full_history_step_timeline_entries([
		{
			"message": "玩家1: 测试日志",
			"step_index": 0,
			"event_seq": 512,
			"details": {
				"sentinel": {"value": 11},
			},
		},
	])

	var read_back := NetClient.get_online_resume_full_history_step_timeline()
	if Dictionary(read_back.get("_build_meta", {})).get("processed_command_count", -1) != 248:
		NetClient.clear_online_resume_full_history_state()
		return Result.failure("NetClient 读取的 cached timeline processed_command_count 错误")

	var adapter_read := OnlineResumeFullHistoryAdapterClass.get_cached_history_timeline()
	if Dictionary(adapter_read.get("_build_meta", {})).get("processed_command_count", -1) != 248:
		NetClient.clear_online_resume_full_history_state()
		return Result.failure("OnlineResumeFullHistoryAdapter 未读到 autoload 转发的 cached timeline")

	var steps_val = adapter_read.get("steps", [])
	if not (steps_val is Array) or Array(steps_val).is_empty():
		NetClient.clear_online_resume_full_history_state()
		return Result.failure("adapter cached timeline 缺少 steps")
	var first_step_val = Array(steps_val)[0]
	if not (first_step_val is Dictionary):
		NetClient.clear_online_resume_full_history_state()
		return Result.failure("adapter cached timeline 首个 step 类型错误")
	var state_dict := Dictionary(Dictionary(first_step_val).get("state_dict", {}))
	var nested_value := Dictionary(state_dict.get("sentinel", {}))
	if int(nested_value.get("value", -1)) != 7:
		NetClient.clear_online_resume_full_history_state()
		return Result.failure("cached timeline 深层字段在 autoload 转发后丢失")

	var read_back_entries := NetClient.get_online_resume_full_history_step_timeline_entries()
	if not (read_back_entries is Array) or Array(read_back_entries).size() != 1:
		NetClient.clear_online_resume_full_history_state()
		return Result.failure("NetClient 读取的 cached timeline entries 数量错误")
	var first_entry_val = Array(read_back_entries)[0]
	if not (first_entry_val is Dictionary):
		NetClient.clear_online_resume_full_history_state()
		return Result.failure("NetClient 读取的 cached timeline entry 类型错误")
	var first_entry: Dictionary = Dictionary(first_entry_val)
	var entry_sentinel := Dictionary(Dictionary(first_entry.get("details", {})).get("sentinel", {}))
	if int(entry_sentinel.get("value", -1)) != 11:
		NetClient.clear_online_resume_full_history_state()
		return Result.failure("cached timeline entries 深层字段在 autoload 转发后丢失")

	var live_history_r := _case_live_history_view_rebuilds_invalidated_prebuilt_entries()
	if not live_history_r.ok:
		NetClient.clear_online_resume_full_history_state()
		return live_history_r

	NetClient.clear_online_resume_full_history_state()
	return Result.success()

static func _case_live_history_view_rebuilds_invalidated_prebuilt_entries() -> Result:
	var prev_mode := int(NetContext.mode)
	var prev_local_player_id := int(NetContext.local_player_id)
	var prev_local_role := str(NetContext.local_role)
	var prev_room_state := Dictionary(NetContext.room_state).duplicate(true)
	var prev_engine = Globals.current_game_engine
	var prev_is_game_active := bool(Globals.is_game_active)

	NetClient.clear_online_resume_full_history_state()
	NetContext.mode = NetContext.Mode.ONLINE_CLIENT
	NetContext.local_player_id = 0
	NetContext.local_role = "player"
	NetContext.room_state = {
		"room_code": "LOGC1",
		"room_mode": "resume_archive",
		"status": "InGame",
		"self_seat_index": 0,
		"self_role": "player",
		"players": [],
		"spectators": [],
	}

	var engine := GameEngineClass.new()
	var init_r: Result = engine.initialize(
		2,
		12345,
		[],
		GameDefaultsClass.DEFAULT_MODULES_V2_BASE_DIR
	)
	if not init_r.ok:
		return _restore_live_log_case_and_fail(
			prev_mode,
			prev_local_player_id,
			prev_local_role,
			prev_room_state,
			prev_engine,
			prev_is_game_active,
			"初始化 runtime engine 失败: %s" % init_r.error
		)

	NetClient.mark_runtime_engine_as_full_history(engine)
	var single_snapshot := NetClient.get_online_resume_session_snapshot()
	if not bool(single_snapshot.get("single_full_engine_mode", false)):
		return _restore_live_log_case_and_fail(
			prev_mode,
			prev_local_player_id,
			prev_local_role,
			prev_room_state,
			prev_engine,
			prev_is_game_active,
			"未进入 single full-engine 恢复房缓存模式"
		)

	var old_timeline := _build_prebuilt_cash_timeline(1)
	var new_timeline := _build_prebuilt_cash_timeline(2)
	NetClient.set_online_resume_full_history_step_timeline(old_timeline)
	NetClient.set_online_resume_full_history_step_timeline_entries([
		{
			"message": "stale-entry",
			"event_seq": 1,
			"command_index": 0,
			"step_index": 0,
			"details": {"sentinel": "old"},
		},
	])
	var old_snapshot := NetClient.get_online_resume_session_snapshot()
	if int(old_snapshot.get("full_history_step_timeline_entries_processed_command_count", -1)) != 1:
		return _restore_live_log_case_and_fail(
			prev_mode,
			prev_local_player_id,
			prev_local_role,
			prev_room_state,
			prev_engine,
			prev_is_game_active,
			"旧 entries 未按旧 timeline processed count 写入"
		)

	NetClient.set_online_resume_full_history_step_timeline(new_timeline)
	var updated_snapshot := NetClient.get_online_resume_session_snapshot()
	if bool(updated_snapshot.get("full_history_step_timeline_entries_ready", false)):
		return _restore_live_log_case_and_fail(
			prev_mode,
			prev_local_player_id,
			prev_local_role,
			prev_room_state,
			prev_engine,
			prev_is_game_active,
			"timeline processed count 前进后仍保留旧 cached entries"
		)

	var panel := _FakeGameLogPanel.new()
	var build_r: Result = GameTimelineOnlineResumeHistoryViewSupportClass.build_live_history_view(
		engine,
		panel,
		"runtime",
		{},
		false,
		Callable()
	)
	if not build_r.ok:
		return _restore_live_log_case_and_fail(
			prev_mode,
			prev_local_player_id,
			prev_local_role,
			prev_room_state,
			prev_engine,
			prev_is_game_active,
			"live history view 未能从 cached timeline 重建日志: %s" % build_r.error
		)
	if panel.loaded_entries.size() != 2:
		return _restore_live_log_case_and_fail(
			prev_mode,
			prev_local_player_id,
			prev_local_role,
			prev_room_state,
			prev_engine,
			prev_is_game_active,
			"live history view 复用了不完整 entries，期望 2 条，实际 %d 条" % panel.loaded_entries.size()
		)
	if int(panel.loaded_entries[1].get("event_seq", -1)) != 2:
		return _restore_live_log_case_and_fail(
			prev_mode,
			prev_local_player_id,
			prev_local_role,
			prev_room_state,
			prev_engine,
			prev_is_game_active,
			"live history view 缺少新 timeline 的第二条日志"
		)

	var after_live_snapshot := NetClient.get_online_resume_session_snapshot()
	if int(after_live_snapshot.get("full_history_step_timeline_entries_processed_command_count", -1)) != 2:
		return _restore_live_log_case_and_fail(
			prev_mode,
			prev_local_player_id,
			prev_local_role,
			prev_room_state,
			prev_engine,
			prev_is_game_active,
			"重建后的 entries 未回写到当前 processed count"
		)

	_restore_live_log_case(
		prev_mode,
		prev_local_player_id,
		prev_local_role,
		prev_room_state,
		prev_engine,
		prev_is_game_active
	)
	return Result.success()

static func _build_prebuilt_cash_timeline(command_count: int) -> Dictionary:
	var steps: Array = []
	var events: Array = []
	for i in range(maxi(0, int(command_count))):
		steps.append({
			"kind": "command",
			"anchor_command_index": i,
			"round": 1,
			"phase": "Working",
			"sub_phase": "test",
			"state_dict": {},
		})
		events.append({
			"sequence": i + 1,
			"command_index": i,
			"step_index": i,
			"phase_segment": "Working",
			"type": EventBus.EventType.PLAYER_CASH_CHANGED,
			"data": {
				"player_id": i % 2,
				"old_cash": 10 + i,
				"new_cash": 11 + i,
				"delta": 1,
			},
		})
	return {
		"_build_meta": {
			"processed_command_count": maxi(0, int(command_count)),
			"last_event_sequence": maxi(0, int(command_count)),
		},
		"steps": steps,
		"events": events,
	}

static func _restore_live_log_case_and_fail(
	prev_mode: int,
	prev_local_player_id: int,
	prev_local_role: String,
	prev_room_state: Dictionary,
	prev_engine,
	prev_is_game_active: bool,
	message: String
) -> Result:
	_restore_live_log_case(
		prev_mode,
		prev_local_player_id,
		prev_local_role,
		prev_room_state,
		prev_engine,
		prev_is_game_active
	)
	return Result.failure(message)

static func _restore_live_log_case(
	prev_mode: int,
	prev_local_player_id: int,
	prev_local_role: String,
	prev_room_state: Dictionary,
	prev_engine,
	prev_is_game_active: bool
) -> void:
	NetClient.clear_online_resume_full_history_state()
	NetContext.mode = prev_mode
	NetContext.local_player_id = prev_local_player_id
	NetContext.local_role = prev_local_role
	NetContext.room_state = prev_room_state.duplicate(true)
	Globals.current_game_engine = prev_engine
	Globals.is_game_active = prev_is_game_active

class _FakeGameLogPanel:
	extends RefCounted

	var loaded_timeline: Dictionary = {}
	var loaded_entries: Array[Dictionary] = []

	func load_step_timeline(timeline: Dictionary, entries: Array, _read_only: bool = false) -> void:
		loaded_timeline = Dictionary(timeline).duplicate(true)
		loaded_entries.clear()
		for entry_val in entries:
			if entry_val is Dictionary:
				loaded_entries.append(Dictionary(entry_val).duplicate(true))

	func get_step_timeline_entries() -> Array[Dictionary]:
		var out: Array[Dictionary] = []
		for entry_val in loaded_entries:
			out.append(Dictionary(entry_val).duplicate(true))
		return out
