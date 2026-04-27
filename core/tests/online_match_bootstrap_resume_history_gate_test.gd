class_name OnlineMatchBootstrapResumeHistoryGateTest
extends RefCounted

const OnlineMatchBootstrapClass = preload("res://autoload/online_match_bootstrap.gd")

static func run() -> Result:
	if not OnlineMatchBootstrapClass.should_wait_for_resume_full_history({
		"room_code": "ROOM88",
		"room_mode": "resume_archive",
	}, {}):
		return Result.failure("恢复房在单 full-engine 本地 bootstrap 完成前应继续等待")

	var waiting_snapshot := {
		"runtime_room_code": "ROOM88",
		"single_full_engine_mode": false,
		"full_history_ready": false,
		"full_history_step_timeline_ready": false,
	}
	if not OnlineMatchBootstrapClass.should_wait_for_resume_full_history({
		"room_code": "ROOM88",
		"room_mode": "resume_archive",
	}, waiting_snapshot):
		return Result.failure("恢复房在 full-engine 尚未就绪时应继续等待")

	var no_timeline_snapshot := waiting_snapshot.duplicate(true)
	no_timeline_snapshot["single_full_engine_mode"] = true
	no_timeline_snapshot["runtime_ready"] = true
	no_timeline_snapshot["full_history_ready"] = true
	no_timeline_snapshot["full_history_step_timeline_ready"] = false
	if not OnlineMatchBootstrapClass.should_wait_for_resume_full_history({
		"room_code": "ROOM88",
		"room_mode": "resume_archive",
	}, no_timeline_snapshot):
		return Result.failure("恢复房在时间线缓存未完成前仍应等待")

	var ready_snapshot := no_timeline_snapshot.duplicate(true)
	ready_snapshot["full_history_step_timeline_ready"] = true
	if OnlineMatchBootstrapClass.should_wait_for_resume_full_history({
		"room_code": "ROOM88",
		"room_mode": "resume_archive",
	}, ready_snapshot):
		return Result.failure("single full-engine 与 timeline cache 完成后不应继续等待")

	if OnlineMatchBootstrapClass.should_wait_for_resume_full_history({
		"room_code": "ROOM88",
		"room_mode": "standard",
	}, waiting_snapshot):
		return Result.failure("普通房不应等待恢复房完整历史")

	return Result.success()
