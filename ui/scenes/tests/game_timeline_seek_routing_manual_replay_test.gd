class_name GameTimelineSeekRoutingManualReplayTest
extends RefCounted

const GameTimelineSeekRoutingSupportClass = preload("res://ui/scenes/game/timeline/seek_routing_support.gd")

static func run() -> Result:
	var history_timeline := {
		"steps": [
			{"anchor_command_index": 0},
			{"anchor_command_index": 1},
			{"anchor_command_index": 2},
		]
	}

	var manual_at_head := GameTimelineSeekRoutingSupportClass.is_seek_enabled(
		false,
		true,
		history_timeline,
		2,
		2,
		true
	)
	if not bool(manual_at_head):
		return Result.failure("手动回放开启后，即使 cursor 位于 head，也应允许首次 seek")

	var no_manual_at_head := GameTimelineSeekRoutingSupportClass.is_seek_enabled(
		false,
		true,
		history_timeline,
		2,
		2,
		false
	)
	if bool(no_manual_at_head):
		return Result.failure("未开启手动回放且 cursor 位于 head 时，不应允许 seek")

	var history_midway := GameTimelineSeekRoutingSupportClass.is_seek_enabled(
		false,
		true,
		history_timeline,
		1,
		2,
		false
	)
	if not bool(history_midway):
		return Result.failure("已处于历史位置时，应继续允许 seek")

	return Result.success({})
