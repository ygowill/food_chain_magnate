class_name OnlineResumeFullHistoryBaselineSelectionTest
extends RefCounted

const OnlineResumeFullHistoryAdapterClass = preload("res://ui/scenes/game/timeline/online_resume_full_history_adapter.gd")

static func run() -> Result:
	var previous_timeline := {
		"_build_meta": {
			"processed_command_count": 19,
		},
		"steps": [
			{"anchor_command_index": 18},
		],
	}
	var cached_timeline := {
		"_build_meta": {
			"processed_command_count": 20,
		},
		"steps": [
			{"anchor_command_index": 19},
		],
	}

	var prefer_cached: Dictionary = OnlineResumeFullHistoryAdapterClass.select_preferred_baseline_timeline(
		previous_timeline,
		cached_timeline,
		20,
		true
	)
	if str(prefer_cached.get("source", "")) != "cached":
		return Result.failure("应优先选择更新鲜的 cached timeline")
	if Dictionary(prefer_cached.get("timeline", {})) != cached_timeline:
		return Result.failure("更新鲜的 cached timeline 应作为 baseline 返回")

	var prefer_previous: Dictionary = OnlineResumeFullHistoryAdapterClass.select_preferred_baseline_timeline(
		{
			"_build_meta": {
				"processed_command_count": 21,
			},
			"steps": [
				{"anchor_command_index": 20},
			],
		},
		cached_timeline,
		21,
		true
	)
	if str(prefer_previous.get("source", "")) != "previous":
		return Result.failure("当 previous timeline 更新时应优先复用 previous timeline")

	var prefer_cached_without_append: Dictionary = OnlineResumeFullHistoryAdapterClass.select_preferred_baseline_timeline(
		previous_timeline,
		cached_timeline,
		20,
		false
	)
	if str(prefer_cached_without_append.get("source", "")) != "cached":
		return Result.failure("禁用增量 append 时应直接优先使用 cached timeline")

	return Result.success()
