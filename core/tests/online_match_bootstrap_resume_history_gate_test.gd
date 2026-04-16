class_name OnlineMatchBootstrapResumeHistoryGateTest
extends RefCounted

const OnlineMatchBootstrapClass = preload("res://autoload/online_match_bootstrap.gd")

static func run() -> Result:
	var waiting_snapshot := {
		"runtime_room_code": "ROOM88",
		"full_history_source_mode": "archive_payload",
		"has_full_archive_payload": true,
		"full_replay_ready": false,
		"full_replay_step_timeline_ready": false,
	}
	if OnlineMatchBootstrapClass.should_wait_for_resume_full_history({
		"room_code": "ROOM88",
		"room_mode": "resume_archive",
	}, waiting_snapshot):
		return Result.failure("恢复房快启动路径不应再等待完整历史")

	var no_timeline_snapshot := waiting_snapshot.duplicate(true)
	no_timeline_snapshot["full_replay_ready"] = true
	no_timeline_snapshot["full_replay_step_timeline_ready"] = false
	if OnlineMatchBootstrapClass.should_wait_for_resume_full_history({
		"room_code": "ROOM88",
		"room_mode": "resume_archive",
	}, no_timeline_snapshot):
		return Result.failure("恢复房快启动路径不应被 timeline cache gate")

	var ready_snapshot := waiting_snapshot.duplicate(true)
	ready_snapshot["full_replay_ready"] = true
	ready_snapshot["full_replay_step_timeline_ready"] = true
	if OnlineMatchBootstrapClass.should_wait_for_resume_full_history({
		"room_code": "ROOM88",
		"room_mode": "resume_archive",
	}, ready_snapshot):
		return Result.failure("完整历史与 timeline cache 均就绪后不应继续等待")

	if OnlineMatchBootstrapClass.should_wait_for_resume_full_history({
		"room_code": "ROOM88",
		"room_mode": "standard",
	}, waiting_snapshot):
		return Result.failure("普通房不应等待恢复房完整历史")

	return Result.success()
