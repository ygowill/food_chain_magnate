extends RefCounted

const GameLogUnifiedTimelineBuilderClass = preload("res://ui/components/game_log/game_log_unified_timeline_builder.gd")

func execute(job: Dictionary) -> Dictionary:
	var mode := str(job.get("mode", "")).strip_edges()
	var timeline_val = job.get("timeline", {})
	var timeline: Dictionary = timeline_val if (timeline_val is Dictionary) else {}

	var entries_all: Array[Dictionary] = []
	var entries_all_val = job.get("entries_all", [])
	if entries_all_val is Array:
		for entry_val in entries_all_val:
			if entry_val is Dictionary:
				entries_all.append(Dictionary(entry_val).duplicate(true))

	var descriptor_info: Dictionary = {}
	match mode:
		"append":
			descriptor_info = GameLogUnifiedTimelineBuilderClass.build_append_descriptors(
				timeline,
				entries_all,
				int(job.get("start_step_index", 0)),
				bool(job.get("show_phase_events", false)),
				bool(job.get("fold_details_enabled", false)),
				Dictionary(job.get("expanded_action_groups", {})).duplicate(true),
				int(job.get("initial_round_number", -1)),
				str(job.get("initial_phase_segment", ""))
			)
		_:
			descriptor_info = GameLogUnifiedTimelineBuilderClass.build_descriptors(
				timeline,
				entries_all,
				bool(job.get("show_phase_events", false)),
				bool(job.get("fold_details_enabled", false)),
				Dictionary(job.get("expanded_action_groups", {})).duplicate(true),
				int(job.get("initial_round_number", -1)),
				str(job.get("initial_phase_segment", ""))
			)

	return {
		"generation": int(job.get("generation", -1)),
		"mode": mode,
		"descriptor_info": descriptor_info.duplicate(true) if (descriptor_info is Dictionary) else {},
	}
