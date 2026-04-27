# NetClient：恢复房完整历史 timeline cache 应通过 autoload 包装层正确转发
class_name NetClientOnlineResumeCachedTimelineForwardingTest
extends RefCounted

const OnlineResumeFullHistoryAdapterClass = preload("res://ui/scenes/game/timeline/online_resume_full_history_adapter.gd")

static func run() -> Result:
	if NetClient == null:
		return Result.failure("NetClient autoload missing")
	if not NetClient.has_method("get_online_resume_full_replay_step_timeline"):
		return Result.failure("NetClient 缺少 get_online_resume_full_replay_step_timeline()")
	if not NetClient.has_method("set_online_resume_full_replay_step_timeline"):
		return Result.failure("NetClient 缺少 set_online_resume_full_replay_step_timeline()")
	if not NetClient.has_method("get_online_resume_full_replay_step_timeline_entries"):
		return Result.failure("NetClient 缺少 get_online_resume_full_replay_step_timeline_entries()")
	if not NetClient.has_method("set_online_resume_full_replay_step_timeline_entries"):
		return Result.failure("NetClient 缺少 set_online_resume_full_replay_step_timeline_entries()")
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

	NetClient.set_online_resume_full_replay_step_timeline(cached_timeline)
	NetClient.set_online_resume_full_replay_step_timeline_entries([
		{
			"message": "玩家1: 测试日志",
			"step_index": 0,
			"event_seq": 512,
			"details": {
				"sentinel": {"value": 11},
			},
		},
	])

	var read_back := NetClient.get_online_resume_full_replay_step_timeline()
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

	var read_back_entries := NetClient.get_online_resume_full_replay_step_timeline_entries()
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

	NetClient.clear_online_resume_full_history_state()
	return Result.success()
