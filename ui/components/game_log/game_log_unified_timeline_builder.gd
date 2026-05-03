# GameLogPanel：统一 step_timeline 视图构建器（M4.3）
extends RefCounted

const ActionIdsClass = preload("res://core/actions/action_ids.gd")
const GameLogEntryUtilsClass = preload("res://ui/components/game_log/game_log_entry_utils.gd")
const GameLogRoundHeaderItemClass = preload("res://ui/components/game_log/game_log_round_header_item.gd")
const GameLogPhaseHeaderItemClass = preload("res://ui/components/game_log/game_log_phase_header_item.gd")
const GameLogActionGroupHeaderItemClass = preload("res://ui/components/game_log/game_log_action_group_header_item.gd")
const GameLogEventItemClass = preload("res://ui/components/game_log/game_log_event_item.gd")

const _RESTRUCTURING_NOISE_ACTION_IDS: PackedStringArray = [
	"restructure_employee",
	"set_company_structure_direct",
	"set_company_structure_report",
]

static func build(
	log_container: VBoxContainer,
	step_timeline: Dictionary,
	entries_all: Array[Dictionary],
	show_phase_events: bool,
	fold_details_enabled: bool,
	is_action_group_expanded: Callable,
	timeline_cursor_index: int,
	timeline_head_index: int,
	on_timeline_header_clicked: Callable,
	on_entry_clicked: Callable,
	on_entry_double_clicked: Callable,
	on_action_group_fold_toggled: Callable,
	initial_round_number: int,
	initial_phase_segment: String,
	acquire_item: Callable = Callable()
) -> Dictionary:
	var items: Array[Control] = []
	var visible_entry_count := 0
	if log_container == null or not is_instance_valid(log_container):
		return {
			"items": items,
			"visible_entry_count": int(visible_entry_count),
		}

	var steps_val = step_timeline.get("steps", null)
	if not (steps_val is Array):
		return {
			"items": items,
			"visible_entry_count": int(visible_entry_count),
		}
	var steps: Array = steps_val

	var entries_by_step := _build_entries_by_step(entries_all)

	var prev_round := int(initial_round_number)
	var prev_phase := str(initial_phase_segment)
	if prev_phase.is_empty():
		prev_phase = "?"

	# RoundHeader：默认仅显示 1..n 回合（Setup 的 round=0 不显示）
	if prev_round >= 1:
		_add_round_header_item(items, log_container, prev_round, -1, timeline_cursor_index, timeline_head_index, on_timeline_header_clicked, acquire_item)

	# -1: 初始状态
	var phase_header = _add_phase_header_item(items, log_container, prev_phase, -1, timeline_cursor_index, timeline_head_index, on_timeline_header_clicked, acquire_item)
	var init_entries: Array = entries_by_step.get(-1, [])
	var init_header := _build_action_group_header_data(-1, {}, init_entries, show_phase_events)
	var init_primary_id := int(init_header.get("primary_entry_id", -1))
	var init_primary_entry_val = init_header.get("primary_entry", {})
	var init_primary_entry: Dictionary = init_primary_entry_val if (init_primary_entry_val is Dictionary) else {}
	var init_child_count := _count_event_items_for_action_group(init_entries, init_primary_id, show_phase_events)
	var init_expanded := _is_expanded(is_action_group_expanded, -1)
	if init_primary_id >= 0:
		visible_entry_count += 1
	_add_action_group_header_item(
		items,
		log_container,
		-1,
		str(init_header.get("summary", "")),
		init_primary_id,
		init_primary_entry,
		fold_details_enabled,
		init_expanded,
		init_child_count,
		timeline_cursor_index,
		timeline_head_index,
		on_entry_clicked,
		on_timeline_header_clicked,
		on_entry_double_clicked,
		on_action_group_fold_toggled,
		acquire_item
	)
	if init_expanded:
		_add_event_items_for_step(items, log_container, -1, entries_by_step, show_phase_events, 2, init_primary_id, timeline_cursor_index, timeline_head_index, on_entry_clicked, on_entry_double_clicked, acquire_item)
		visible_entry_count += init_child_count

	for idx in range(steps.size()):
		var step_val = steps[idx]
		if not (step_val is Dictionary):
			continue
		var step: Dictionary = step_val
		var round_num := int(step.get("round", -1))
		var phase_seg := str(step.get("phase", "")).strip_edges()
		if phase_seg.is_empty():
			phase_seg = "?"
		var action_id := str(step.get("action_id", "")).strip_edges()

		var round_changed := (round_num != prev_round)
		if round_changed and round_num >= 1:
			_add_round_header_item(items, log_container, round_num, idx, timeline_cursor_index, timeline_head_index, on_timeline_header_clicked, acquire_item)

		if round_changed or phase_seg != prev_phase:
			if phase_header != null and is_instance_valid(phase_header):
				phase_header.end_step_index = idx - 1
			phase_header = _add_phase_header_item(items, log_container, phase_seg, idx, timeline_cursor_index, timeline_head_index, on_timeline_header_clicked, acquire_item)

		var kind := str(step.get("kind", "")).strip_edges()
		if kind == "phase":
			# phase step：不再渲染“进入X”类 ActionGroup 行；阶段标题已足够承载该锚点。
			_add_event_items_for_step(items, log_container, idx, entries_by_step, show_phase_events, 1, -1, timeline_cursor_index, timeline_head_index, on_entry_clicked, on_entry_double_clicked, acquire_item)
			visible_entry_count += _count_event_items_for_action_group(entries_by_step.get(idx, []), -1, show_phase_events)
		elif _is_hidden_restructuring_noise_action(action_id):
			# 重组阶段拖拽调整动作（直属槽/下属/在岗待命）不再逐条显示日志。
			# 仍保留 submit_restructuring（确认重组）的日志项。
			continue
		elif _is_flow_command_action_id(str(step.get("action_id", "")).strip_edges()):
			# flow command（skip/end_turn/skip_sub_phase/advance_phase）不再显示“系统推进”分组行。
			_add_event_items_for_step(items, log_container, idx, entries_by_step, show_phase_events, 1, -1, timeline_cursor_index, timeline_head_index, on_entry_clicked, on_entry_double_clicked, acquire_item)
			visible_entry_count += _count_event_items_for_action_group(entries_by_step.get(idx, []), -1, show_phase_events)
		else:
			var step_entries: Array = entries_by_step.get(idx, [])
			var header := _build_action_group_header_data(idx, step, step_entries, show_phase_events)
			var primary_id := int(header.get("primary_entry_id", -1))
			var primary_entry_val = header.get("primary_entry", {})
			var primary_entry: Dictionary = primary_entry_val if (primary_entry_val is Dictionary) else {}
			var child_count := _count_event_items_for_action_group(step_entries, primary_id, show_phase_events)
			var expanded := _is_expanded(is_action_group_expanded, idx)
			if primary_id >= 0:
				visible_entry_count += 1
			_add_action_group_header_item(
				items,
				log_container,
				idx,
				str(header.get("summary", "")),
				primary_id,
				primary_entry,
				fold_details_enabled,
				expanded,
				child_count,
				timeline_cursor_index,
				timeline_head_index,
				on_entry_clicked,
				on_timeline_header_clicked,
				on_entry_double_clicked,
				on_action_group_fold_toggled,
				acquire_item
			)
			if expanded:
				_add_event_items_for_step(items, log_container, idx, entries_by_step, show_phase_events, 2, primary_id, timeline_cursor_index, timeline_head_index, on_entry_clicked, on_entry_double_clicked, acquire_item)
				visible_entry_count += child_count

		prev_round = round_num
		prev_phase = phase_seg

	if phase_header != null and is_instance_valid(phase_header):
		phase_header.end_step_index = steps.size() - 1

	return {
		"items": items,
		"visible_entry_count": int(visible_entry_count),
	}

static func append_step_range(
	existing_items: Array[Control],
	log_container: VBoxContainer,
	step_timeline: Dictionary,
	entries_all: Array[Dictionary],
	start_step_index: int,
	show_phase_events: bool,
	fold_details_enabled: bool,
	is_action_group_expanded: Callable,
	timeline_cursor_index: int,
	timeline_head_index: int,
	on_timeline_header_clicked: Callable,
	on_entry_clicked: Callable,
	on_entry_double_clicked: Callable,
	on_action_group_fold_toggled: Callable,
	initial_round_number: int,
	initial_phase_segment: String,
	acquire_item: Callable = Callable(),
	append_phase_header = null
) -> Dictionary:
	var items: Array[Control] = []
	var visible_entry_count := 0
	if log_container == null or not is_instance_valid(log_container):
		return {
			"items": items,
			"visible_entry_count": int(visible_entry_count),
		}

	var steps_val = step_timeline.get("steps", null)
	if not (steps_val is Array):
		return {
			"items": items,
			"visible_entry_count": int(visible_entry_count),
		}
	var steps: Array = steps_val
	var start_idx := maxi(0, int(start_step_index))
	if start_idx >= steps.size():
		return {
			"items": items,
			"visible_entry_count": int(visible_entry_count),
		}

	var entries_by_step := _build_entries_by_step(entries_all)
	var context := _resolve_append_context(
		existing_items,
		step_timeline,
		start_idx,
		initial_round_number,
		initial_phase_segment,
		append_phase_header
	)
	var prev_round := int(context.get("prev_round", initial_round_number))
	var prev_phase := str(context.get("prev_phase", initial_phase_segment)).strip_edges()
	if prev_phase.is_empty():
		prev_phase = "?"
	var phase_header = context.get("phase_header", null)

	for idx in range(start_idx, steps.size()):
		var step_val = steps[idx]
		if not (step_val is Dictionary):
			continue
		var step: Dictionary = step_val
		var round_num := int(step.get("round", -1))
		var phase_seg := str(step.get("phase", "")).strip_edges()
		if phase_seg.is_empty():
			phase_seg = "?"
		var action_id := str(step.get("action_id", "")).strip_edges()

		var round_changed := (round_num != prev_round)
		if round_changed and round_num >= 1:
			_add_round_header_item(items, log_container, round_num, idx, timeline_cursor_index, timeline_head_index, on_timeline_header_clicked, acquire_item)

		if round_changed or phase_seg != prev_phase:
			if phase_header != null and is_instance_valid(phase_header):
				phase_header.end_step_index = idx - 1
			phase_header = _add_phase_header_item(items, log_container, phase_seg, idx, timeline_cursor_index, timeline_head_index, on_timeline_header_clicked, acquire_item)

		var kind := str(step.get("kind", "")).strip_edges()
		if kind == "phase":
			_add_event_items_for_step(items, log_container, idx, entries_by_step, show_phase_events, 1, -1, timeline_cursor_index, timeline_head_index, on_entry_clicked, on_entry_double_clicked, acquire_item)
			visible_entry_count += _count_event_items_for_action_group(entries_by_step.get(idx, []), -1, show_phase_events)
		elif _is_hidden_restructuring_noise_action(action_id):
			continue
		elif _is_flow_command_action_id(str(step.get("action_id", "")).strip_edges()):
			_add_event_items_for_step(items, log_container, idx, entries_by_step, show_phase_events, 1, -1, timeline_cursor_index, timeline_head_index, on_entry_clicked, on_entry_double_clicked, acquire_item)
			visible_entry_count += _count_event_items_for_action_group(entries_by_step.get(idx, []), -1, show_phase_events)
		else:
			var step_entries: Array = entries_by_step.get(idx, [])
			var header: Dictionary = _build_action_group_header_data(idx, step, step_entries, show_phase_events)
			var primary_id := int(header.get("primary_entry_id", -1))
			var primary_entry_val = header.get("primary_entry", {})
			var primary_entry: Dictionary = primary_entry_val if (primary_entry_val is Dictionary) else {}
			var child_count := _count_event_items_for_action_group(step_entries, primary_id, show_phase_events)
			var expanded := _is_expanded(is_action_group_expanded, idx)
			if primary_id >= 0:
				visible_entry_count += 1
			_add_action_group_header_item(
				items,
				log_container,
				idx,
				str(header.get("summary", "")),
				primary_id,
				primary_entry,
				fold_details_enabled,
				expanded,
				child_count,
				timeline_cursor_index,
				timeline_head_index,
				on_entry_clicked,
				on_timeline_header_clicked,
				on_entry_double_clicked,
				on_action_group_fold_toggled,
				acquire_item
			)
			if expanded:
				_add_event_items_for_step(items, log_container, idx, entries_by_step, show_phase_events, 2, primary_id, timeline_cursor_index, timeline_head_index, on_entry_clicked, on_entry_double_clicked, acquire_item)
				visible_entry_count += child_count

		prev_round = round_num
		prev_phase = phase_seg

	if phase_header != null and is_instance_valid(phase_header):
		phase_header.end_step_index = steps.size() - 1

	return {
		"items": items,
		"visible_entry_count": int(visible_entry_count),
	}

static func build_descriptors(
	step_timeline: Dictionary,
	entries_all: Array[Dictionary],
	show_phase_events: bool,
	fold_details_enabled: bool,
	expanded_action_groups: Dictionary,
	initial_round_number: int,
	initial_phase_segment: String
) -> Dictionary:
	var descriptors: Array[Dictionary] = []
	var visible_entry_count := 0
	var steps_val = step_timeline.get("steps", null)
	if not (steps_val is Array):
		return {
			"items": descriptors,
			"timeline_step_count": 0,
			"visible_entry_count": int(visible_entry_count),
		}
	var steps: Array = steps_val

	var entries_by_step := _build_entries_by_step(entries_all)

	var prev_round := int(initial_round_number)
	var prev_phase := str(initial_phase_segment).strip_edges()
	if prev_phase.is_empty():
		prev_phase = "?"

	if prev_round >= 1:
		descriptors.append({
			"kind": "round_header",
			"round_number": int(prev_round),
			"start_step_index": -1,
		})

	descriptors.append({
		"kind": "phase_header",
		"phase_segment": str(prev_phase),
		"start_step_index": -1,
		"end_step_index": -1,
	})
	var current_phase_descriptor_index := descriptors.size() - 1

	var init_entries: Array = entries_by_step.get(-1, [])
	var init_header := _build_action_group_header_data(-1, {}, init_entries, show_phase_events)
	var init_primary_id := int(init_header.get("primary_entry_id", -1))
	var init_primary_entry_val = init_header.get("primary_entry", {})
	var init_primary_entry: Dictionary = init_primary_entry_val if (init_primary_entry_val is Dictionary) else {}
	var init_child_count := _count_event_items_for_action_group(init_entries, init_primary_id, show_phase_events)
	var init_expanded := _is_expanded_from_snapshot(bool(fold_details_enabled), expanded_action_groups, -1)
	if init_primary_id >= 0:
		visible_entry_count += 1
	descriptors.append({
		"kind": "action_group_header",
		"step_index": -1,
		"summary": str(init_header.get("summary", "")),
		"primary_entry_id": int(init_primary_id),
		"primary_entry": init_primary_entry.duplicate(true),
		"fold_enabled": bool(fold_details_enabled),
		"expanded": bool(init_expanded),
		"child_event_count": int(init_child_count),
	})
	if init_expanded:
		visible_entry_count += init_child_count
		_append_event_descriptors_for_step(
			descriptors,
			-1,
			entries_by_step,
			show_phase_events,
			2,
			init_primary_id
		)

	for idx in range(steps.size()):
		var step_val = steps[idx]
		if not (step_val is Dictionary):
			continue
		var step: Dictionary = step_val
		var round_num := int(step.get("round", -1))
		var phase_seg := str(step.get("phase", "")).strip_edges()
		if phase_seg.is_empty():
			phase_seg = "?"
		var action_id := str(step.get("action_id", "")).strip_edges()

		var round_changed := (round_num != prev_round)
		if round_changed and round_num >= 1:
			descriptors.append({
				"kind": "round_header",
				"round_number": int(round_num),
				"start_step_index": int(idx),
			})

		if round_changed or phase_seg != prev_phase:
			if current_phase_descriptor_index >= 0 and current_phase_descriptor_index < descriptors.size():
				var prev_desc: Dictionary = Dictionary(descriptors[current_phase_descriptor_index])
				prev_desc["end_step_index"] = int(idx) - 1
				descriptors[current_phase_descriptor_index] = prev_desc
			descriptors.append({
				"kind": "phase_header",
				"phase_segment": str(phase_seg),
				"start_step_index": int(idx),
				"end_step_index": int(idx),
			})
			current_phase_descriptor_index = descriptors.size() - 1

		var kind := str(step.get("kind", "")).strip_edges()
		if kind == "phase":
			visible_entry_count += _count_event_items_for_action_group(entries_by_step.get(idx, []), -1, show_phase_events)
			_append_event_descriptors_for_step(
				descriptors,
				idx,
				entries_by_step,
				show_phase_events,
				1,
				-1
			)
		elif _is_hidden_restructuring_noise_action(action_id):
			pass
		elif _is_flow_command_action_id(str(step.get("action_id", "")).strip_edges()):
			visible_entry_count += _count_event_items_for_action_group(entries_by_step.get(idx, []), -1, show_phase_events)
			_append_event_descriptors_for_step(
				descriptors,
				idx,
				entries_by_step,
				show_phase_events,
				1,
				-1
			)
		else:
			var step_entries: Array = entries_by_step.get(idx, [])
			var header: Dictionary = _build_action_group_header_data(idx, step, step_entries, show_phase_events)
			var primary_id := int(header.get("primary_entry_id", -1))
			var primary_entry_val = header.get("primary_entry", {})
			var primary_entry: Dictionary = primary_entry_val if (primary_entry_val is Dictionary) else {}
			var child_count := _count_event_items_for_action_group(step_entries, primary_id, show_phase_events)
			var expanded := _is_expanded_from_snapshot(bool(fold_details_enabled), expanded_action_groups, idx)
			if primary_id >= 0:
				visible_entry_count += 1
			descriptors.append({
				"kind": "action_group_header",
				"step_index": int(idx),
				"summary": str(header.get("summary", "")),
				"primary_entry_id": int(primary_id),
				"primary_entry": primary_entry.duplicate(true),
				"fold_enabled": bool(fold_details_enabled),
				"expanded": bool(expanded),
				"child_event_count": int(child_count),
			})
			if expanded:
				visible_entry_count += child_count
				_append_event_descriptors_for_step(
					descriptors,
					idx,
					entries_by_step,
					show_phase_events,
					2,
					primary_id
				)

		prev_round = round_num
		prev_phase = phase_seg

	if current_phase_descriptor_index >= 0 and current_phase_descriptor_index < descriptors.size():
		var final_desc: Dictionary = Dictionary(descriptors[current_phase_descriptor_index])
		final_desc["end_step_index"] = steps.size() - 1
		descriptors[current_phase_descriptor_index] = final_desc

	return {
		"items": descriptors,
		"timeline_step_count": int(steps.size()),
		"visible_entry_count": int(visible_entry_count),
	}

static func build_append_descriptors(
	step_timeline: Dictionary,
	entries_all: Array[Dictionary],
	start_step_index: int,
	show_phase_events: bool,
	fold_details_enabled: bool,
	expanded_action_groups: Dictionary,
	initial_round_number: int,
	initial_phase_segment: String
) -> Dictionary:
	var steps_val = step_timeline.get("steps", null)
	if not (steps_val is Array):
		return {
			"items": [],
			"timeline_step_count": 0,
			"patch_existing_last_phase_header_end_step_index": -999,
			"visible_entry_count_delta": 0,
		}
	var steps: Array = steps_val
	var start_idx := maxi(0, int(start_step_index))
	if start_idx >= steps.size():
		return {
			"items": [],
			"timeline_step_count": int(steps.size()),
			"patch_existing_last_phase_header_end_step_index": -999,
			"visible_entry_count_delta": 0,
		}

	var entries_by_step := _build_entries_by_step(entries_all)
	var prev_round := int(initial_round_number)
	var prev_phase := str(initial_phase_segment).strip_edges()
	if prev_phase.is_empty():
		prev_phase = "?"

	if start_idx > 0:
		var prev_idx := start_idx - 1
		if prev_idx >= 0 and prev_idx < steps.size():
			var prev_step_val = steps[prev_idx]
			if prev_step_val is Dictionary:
				var prev_step: Dictionary = prev_step_val
				prev_round = int(prev_step.get("round", prev_round))
				prev_phase = str(prev_step.get("phase", prev_phase)).strip_edges()
				if prev_phase.is_empty():
					prev_phase = "?"

	var descriptors: Array[Dictionary] = []
	var visible_entry_count_delta := 0
	var current_phase_descriptor_index := -1
	var patch_existing_last_phase_header_end_step_index := -999
	var needs_patch_existing_phase_header := true

	for idx in range(start_idx, steps.size()):
		var step_val = steps[idx]
		if not (step_val is Dictionary):
			continue
		var step: Dictionary = step_val
		var round_num := int(step.get("round", -1))
		var phase_seg := str(step.get("phase", "")).strip_edges()
		if phase_seg.is_empty():
			phase_seg = "?"
		var action_id := str(step.get("action_id", "")).strip_edges()

		var round_changed := (round_num != prev_round)
		if round_changed and round_num >= 1:
			descriptors.append({
				"kind": "round_header",
				"round_number": int(round_num),
				"start_step_index": int(idx),
			})

		if round_changed or phase_seg != prev_phase:
			if current_phase_descriptor_index >= 0 and current_phase_descriptor_index < descriptors.size():
				var prev_desc: Dictionary = Dictionary(descriptors[current_phase_descriptor_index])
				prev_desc["end_step_index"] = int(idx) - 1
				descriptors[current_phase_descriptor_index] = prev_desc
			elif needs_patch_existing_phase_header:
				patch_existing_last_phase_header_end_step_index = int(idx) - 1
			needs_patch_existing_phase_header = false

			descriptors.append({
				"kind": "phase_header",
				"phase_segment": str(phase_seg),
				"start_step_index": int(idx),
				"end_step_index": int(idx),
			})
			current_phase_descriptor_index = descriptors.size() - 1
		elif needs_patch_existing_phase_header:
			needs_patch_existing_phase_header = false

		var kind := str(step.get("kind", "")).strip_edges()
		if kind == "phase":
			visible_entry_count_delta += _count_event_items_for_action_group(entries_by_step.get(idx, []), -1, show_phase_events)
			_append_event_descriptors_for_step(
				descriptors,
				idx,
				entries_by_step,
				show_phase_events,
				1,
				-1
			)
		elif _is_hidden_restructuring_noise_action(action_id):
			pass
		elif _is_flow_command_action_id(str(step.get("action_id", "")).strip_edges()):
			visible_entry_count_delta += _count_event_items_for_action_group(entries_by_step.get(idx, []), -1, show_phase_events)
			_append_event_descriptors_for_step(
				descriptors,
				idx,
				entries_by_step,
				show_phase_events,
				1,
				-1
			)
		else:
			var step_entries: Array = entries_by_step.get(idx, [])
			var header: Dictionary = _build_action_group_header_data(idx, step, step_entries, show_phase_events)
			var primary_id := int(header.get("primary_entry_id", -1))
			var primary_entry_val = header.get("primary_entry", {})
			var primary_entry: Dictionary = primary_entry_val if (primary_entry_val is Dictionary) else {}
			var child_count := _count_event_items_for_action_group(step_entries, primary_id, show_phase_events)
			var expanded := _is_expanded_from_snapshot(bool(fold_details_enabled), expanded_action_groups, idx)
			if primary_id >= 0:
				visible_entry_count_delta += 1
			descriptors.append({
				"kind": "action_group_header",
				"step_index": int(idx),
				"summary": str(header.get("summary", "")),
				"primary_entry_id": int(primary_id),
				"primary_entry": primary_entry.duplicate(true),
				"fold_enabled": bool(fold_details_enabled),
				"expanded": bool(expanded),
				"child_event_count": int(child_count),
			})
			if expanded:
				visible_entry_count_delta += child_count
				_append_event_descriptors_for_step(
					descriptors,
					idx,
					entries_by_step,
					show_phase_events,
					2,
					primary_id
				)

		prev_round = round_num
		prev_phase = phase_seg

	if current_phase_descriptor_index >= 0 and current_phase_descriptor_index < descriptors.size():
		var final_desc: Dictionary = Dictionary(descriptors[current_phase_descriptor_index])
		final_desc["end_step_index"] = steps.size() - 1
		descriptors[current_phase_descriptor_index] = final_desc
	elif not needs_patch_existing_phase_header:
		patch_existing_last_phase_header_end_step_index = steps.size() - 1

	return {
		"items": descriptors,
		"timeline_step_count": int(steps.size()),
		"patch_existing_last_phase_header_end_step_index": int(patch_existing_last_phase_header_end_step_index),
		"visible_entry_count_delta": int(visible_entry_count_delta),
	}

static func append_descriptor_slice(
	items: Array[Control],
	log_container: VBoxContainer,
	descriptors: Array,
	from_index: int,
	to_exclusive: int,
	timeline_cursor_index: int,
	timeline_head_index: int,
	on_timeline_header_clicked: Callable,
	on_entry_clicked: Callable,
	on_entry_double_clicked: Callable,
	on_action_group_fold_toggled: Callable,
	acquire_item: Callable = Callable()
) -> void:
	if log_container == null or not is_instance_valid(log_container):
		return
	var from_idx := maxi(0, int(from_index))
	var to_idx := mini(int(to_exclusive), descriptors.size())
	for idx in range(from_idx, to_idx):
		var descriptor_val = descriptors[idx]
		if not (descriptor_val is Dictionary):
			continue
		var descriptor: Dictionary = descriptor_val
		var kind := str(descriptor.get("kind", "")).strip_edges()
		match kind:
			"round_header":
				_add_round_header_item(
					items,
					log_container,
					int(descriptor.get("round_number", -1)),
					int(descriptor.get("start_step_index", -1)),
					timeline_cursor_index,
					timeline_head_index,
					on_timeline_header_clicked,
					acquire_item
				)
			"phase_header":
				var phase_item = _add_phase_header_item(
					items,
					log_container,
					str(descriptor.get("phase_segment", "")),
					int(descriptor.get("start_step_index", -1)),
					timeline_cursor_index,
					timeline_head_index,
					on_timeline_header_clicked,
					acquire_item
				)
				if phase_item != null and is_instance_valid(phase_item):
					phase_item.end_step_index = int(descriptor.get("end_step_index", phase_item.end_step_index))
			"action_group_header":
				var primary_entry_val = descriptor.get("primary_entry", {})
				var primary_entry: Dictionary = primary_entry_val if (primary_entry_val is Dictionary) else {}
				_add_action_group_header_item(
					items,
					log_container,
					int(descriptor.get("step_index", -1)),
					str(descriptor.get("summary", "")),
					int(descriptor.get("primary_entry_id", -1)),
					primary_entry,
					bool(descriptor.get("fold_enabled", false)),
					bool(descriptor.get("expanded", true)),
					int(descriptor.get("child_event_count", 0)),
					timeline_cursor_index,
					timeline_head_index,
					on_entry_clicked,
					on_timeline_header_clicked,
					on_entry_double_clicked,
					on_action_group_fold_toggled,
					acquire_item
				)
			"event_item":
				var entry_val = descriptor.get("entry", {})
				var entry: Dictionary = entry_val if (entry_val is Dictionary) else {}
				_add_event_item(
					items,
					log_container,
					entry,
					int(descriptor.get("indent_level", 1)),
					timeline_cursor_index,
					timeline_head_index,
					on_entry_clicked,
					on_entry_double_clicked,
					acquire_item
				)
			_:
				pass

static func compute_visible_entry_count(
	step_timeline: Dictionary,
	entries_all: Array[Dictionary],
	show_phase_events: bool,
	is_action_group_expanded: Callable
) -> int:
	var steps_val = step_timeline.get("steps", null)
	if not (steps_val is Array):
		return entries_all.size()
	var steps: Array = steps_val

	var entries_by_step := _build_entries_by_step(entries_all)
	var visible := 0

	# -1 初始动作组：默认也计入（若有 primary 则计 1，否则仅计子项）
	var init_entries: Array = entries_by_step.get(-1, [])
	var init_primary := _pick_primary_entry_for_action_group(init_entries)
	var init_primary_id := int(init_primary.get("id", -1)) if (init_primary != null and not init_primary.is_empty()) else -1
	if init_primary_id >= 0:
		visible += 1
	if _is_expanded(is_action_group_expanded, -1):
		visible += _count_event_items_for_action_group(init_entries, init_primary_id, show_phase_events)

	for idx in range(steps.size()):
		var step_val = steps[idx]
		if not (step_val is Dictionary):
			continue
		var step: Dictionary = step_val
		var kind := str(step.get("kind", "")).strip_edges()
		var action_id := str(step.get("action_id", "")).strip_edges()
		var step_entries: Array = entries_by_step.get(idx, [])
		if kind == "phase":
			# phase step 没有 ActionGroupHeader：只计可见子项（仍受“显示阶段事件”开关影响）。
			visible += _count_event_items_for_action_group(step_entries, -1, show_phase_events)
			continue
		if _is_hidden_restructuring_noise_action(action_id):
			continue
		if _is_flow_command_action_id(str(step.get("action_id", "")).strip_edges()):
			visible += _count_event_items_for_action_group(step_entries, -1, show_phase_events)
			continue

		var primary := _pick_primary_entry_for_action_group(step_entries)
		var primary_id := int(primary.get("id", -1)) if (primary != null and not primary.is_empty()) else -1
		if primary_id >= 0:
			visible += 1
		if _is_expanded(is_action_group_expanded, idx):
			visible += _count_event_items_for_action_group(step_entries, primary_id, show_phase_events)

	return visible

static func _acquire_control_item(acquire_item: Callable, kind: String):
	if not acquire_item.is_valid():
		return null
	var item = acquire_item.call(str(kind))
	return item if (item is Control and is_instance_valid(item)) else null

static func _resolve_append_context(
	existing_items: Array[Control],
	step_timeline: Dictionary,
	start_step_index: int,
	initial_round_number: int,
	initial_phase_segment: String,
	append_phase_header = null
) -> Dictionary:
	var prev_round := int(initial_round_number)
	var prev_phase := str(initial_phase_segment).strip_edges()
	if prev_phase.is_empty():
		prev_phase = "?"

	var steps_val = step_timeline.get("steps", null)
	if steps_val is Array and int(start_step_index) > 0:
		var steps: Array = steps_val
		var prev_idx := int(start_step_index) - 1
		if prev_idx >= 0 and prev_idx < steps.size():
			var prev_step_val = steps[prev_idx]
			if prev_step_val is Dictionary:
				var prev_step: Dictionary = prev_step_val
				prev_round = int(prev_step.get("round", prev_round))
				prev_phase = str(prev_step.get("phase", prev_phase)).strip_edges()
				if prev_phase.is_empty():
					prev_phase = "?"

	var phase_header = null
	if append_phase_header is Control and is_instance_valid(append_phase_header):
		phase_header = append_phase_header
	else:
		phase_header = _find_last_phase_header_item(existing_items)

	return {
		"prev_round": prev_round,
		"prev_phase": prev_phase,
		"phase_header": phase_header,
	}

static func _find_last_phase_header_item(existing_items: Array[Control]):
	for i in range(existing_items.size() - 1, -1, -1):
		var item_val = existing_items[i]
		if not (item_val is Control):
			continue
		var item: Control = item_val
		if not is_instance_valid(item):
			continue
		if str(item.get_meta("_log_pool_kind", "")).strip_edges() == "phase_header":
			return item
	return null

static func _is_expanded(is_action_group_expanded: Callable, step_index: int) -> bool:
	if not is_action_group_expanded.is_valid():
		return false
	return bool(is_action_group_expanded.call(int(step_index)))

static func _is_expanded_from_snapshot(fold_details_enabled: bool, expanded_action_groups: Dictionary, step_index: int) -> bool:
	if not bool(fold_details_enabled):
		return true
	return bool(expanded_action_groups.get(int(step_index), false))

static func _build_entries_by_step(entries_all: Array[Dictionary]) -> Dictionary:
	var out: Dictionary = {} # step_index -> Array[Dictionary]
	for entry_val in entries_all:
		if not (entry_val is Dictionary):
			continue
		var entry: Dictionary = entry_val
		var si := int(GameLogEntryUtilsClass.get_entry_step_index(entry))
		if si == -999:
			continue
		if not out.has(si):
			out[si] = []
		(out[si] as Array).append(entry)

	# 稳定排序：timeline 按 event_seq，extra 按 id
	for k in out.keys():
		var arr_val = out[k]
		if not (arr_val is Array):
			continue
		var arr: Array = arr_val
		arr.sort_custom(func(a, b):
			var da: Dictionary = a if (a is Dictionary) else {}
			var db: Dictionary = b if (b is Dictionary) else {}
			var sa := int(da.get("event_seq", -1))
			var sb := int(db.get("event_seq", -1))
			if sa != sb:
				if sa < 0:
					return false
				if sb < 0:
					return true
				return sa < sb
			return int(da.get("id", 0)) < int(db.get("id", 0))
		)
		out[k] = arr

	return out

static func _should_show_event_item(entry: Dictionary, show_phase_events: bool) -> bool:
	if entry == null or entry.is_empty():
		return false
	if show_phase_events:
		return true
	return not GameLogEntryUtilsClass.entry_is_stage_event(entry)

static func _build_action_group_header_data(step_index: int, step: Dictionary, entries: Array, show_phase_events: bool) -> Dictionary:
	# 统一视图：ActionGroupHeader 的摘要优先取“第一条玩家动作”，并把该条作为 primary 以避免在子项中重复展示。
	# 但对 flow command（skip/end_turn/skip_sub_phase）来说，step 内的“第一条可见玩家日志”往往是结算/派生事件，
	# 把它提升为 summary 会导致同组内其它事件出现额外缩进（且语义上也不应由结算事件代表该 step）。
	if _is_flow_command_action_id(str(step.get("action_id", "")).strip_edges()):
		return {
			"summary": _build_action_group_fallback_summary(step_index, step),
			"primary_entry_id": -1,
			"primary_entry": {},
		}
	var primary := _pick_primary_entry_for_action_group(entries)
	if primary != null and not primary.is_empty():
		var msg := str(primary.get("message", "")).strip_edges()
		if not msg.is_empty():
			return {
				"summary": msg,
				"primary_entry_id": int(primary.get("id", -1)),
				"primary_entry": primary,
			}
	return {
		"summary": _build_action_group_fallback_summary(step_index, step),
		"primary_entry_id": -1,
		"primary_entry": {},
	}

static func _pick_primary_entry_for_action_group(entries: Array) -> Dictionary:
	if entries == null or entries.is_empty():
		return {}
	for e_val in entries:
		if not (e_val is Dictionary):
			continue
		var e: Dictionary = e_val
		if GameLogEntryUtilsClass.entry_is_stage_event(e):
			continue
		if int(e.get("type", -1)) == GameLogPanel.LogType.PLAYER:
			var msg := str(e.get("message", "")).strip_edges()
			if not msg.is_empty():
				return e
	return {}

static func _is_flow_command_action_id(action_id: String) -> bool:
	var aid := str(action_id).strip_edges()
	return aid == ActionIdsClass.SKIP or aid == ActionIdsClass.END_TURN or aid == ActionIdsClass.SKIP_SUB_PHASE or aid == ActionIdsClass.ADVANCE_PHASE

static func _is_hidden_restructuring_noise_action(action_id: String) -> bool:
	var aid := str(action_id).strip_edges()
	return _RESTRUCTURING_NOISE_ACTION_IDS.has(aid)

static func _build_action_group_fallback_summary(step_index: int, step: Dictionary) -> String:
	# 兜底：系统摘要/命令元信息（用于“无可见事件 step”的可读性）
	if step_index < 0:
		return "初始状态"

	var kind := str(step.get("kind", "")).strip_edges()
	if kind == "command":
		# 去噪：skip/end_turn/skip_sub_phase 不再以“玩家X:确认结束/结束回合”作为摘要。
		if _is_flow_command_action_id(str(step.get("action_id", ""))):
			return "系统推进"
		var action_name := str(step.get("action_display_name", "")).strip_edges()
		if action_name.is_empty():
			action_name = str(step.get("action_id", "")).strip_edges()
		var actor := int(step.get("actor", -1))
		if not action_name.is_empty():
			if actor >= 0:
				var actor_name := "玩家%d" % (actor + 1)
				if Globals != null:
					if Globals.has_method("get_player_name_compact"):
						var s := str(Globals.get_player_name_compact(actor)).strip_edges()
						if not s.is_empty():
							actor_name = s
					elif Globals.has_method("get_player_name"):
						var s2 := str(Globals.get_player_name(actor)).strip_edges()
						if not s2.is_empty():
							actor_name = s2
				return "%s: %s" % [actor_name, action_name]
			return action_name
	return "系统推进"

static func _add_round_header_item(
	items: Array[Control],
	log_container: VBoxContainer,
	round_number: int,
	start_step_index: int,
	timeline_cursor_index: int,
	timeline_head_index: int,
	on_timeline_header_clicked: Callable,
	acquire_item: Callable
) -> void:
	var item = _acquire_control_item(acquire_item, "round_header")
	if item == null:
		item = GameLogRoundHeaderItemClass.new()
	item.set_meta("_log_pool_kind", "round_header")
	log_container.add_child(item)
	if item.has_method("configure_round_header"):
		item.configure_round_header(int(round_number), int(start_step_index))
	else:
		item.round_number = int(round_number)
		item.start_step_index = int(start_step_index)
	if on_timeline_header_clicked.is_valid() and not item.clicked.is_connected(on_timeline_header_clicked):
		item.clicked.connect(on_timeline_header_clicked)
	items.append(item)
	item.apply_timeline_state(int(timeline_cursor_index), int(timeline_head_index))

static func _add_phase_header_item(
	items: Array[Control],
	log_container: VBoxContainer,
	phase_segment: String,
	start_step: int,
	timeline_cursor_index: int,
	timeline_head_index: int,
	on_timeline_header_clicked: Callable,
	acquire_item: Callable
) -> Control:
	var item = _acquire_control_item(acquire_item, "phase_header")
	if item == null:
		item = GameLogPhaseHeaderItemClass.new()
	item.set_meta("_log_pool_kind", "phase_header")
	log_container.add_child(item)
	if item.has_method("configure_phase_header"):
		item.configure_phase_header(str(phase_segment), int(start_step), int(start_step))
	else:
		item.phase_segment = str(phase_segment)
		item.start_step_index = int(start_step)
		item.end_step_index = int(start_step)
	if on_timeline_header_clicked.is_valid() and not item.clicked.is_connected(on_timeline_header_clicked):
		item.clicked.connect(on_timeline_header_clicked)
	items.append(item)
	item.apply_timeline_state(int(timeline_cursor_index), int(timeline_head_index))
	return item

static func _add_action_group_header_item(
	items: Array[Control],
	log_container: VBoxContainer,
	step_index: int,
	summary: String,
	primary_entry_id: int,
	primary_entry: Dictionary,
	fold_enabled: bool,
	expanded: bool,
	child_event_count: int,
	timeline_cursor_index: int,
	timeline_head_index: int,
	on_entry_clicked: Callable,
	on_timeline_header_clicked: Callable,
	on_entry_double_clicked: Callable,
	on_action_group_fold_toggled: Callable,
	acquire_item: Callable
) -> void:
	var item = _acquire_control_item(acquire_item, "action_group_header")
	if item == null:
		item = GameLogActionGroupHeaderItemClass.new()
	item.set_meta("_log_pool_kind", "action_group_header")
	log_container.add_child(item)
	if item.has_method("configure_action_group"):
		item.configure_action_group(
			int(step_index),
			str(summary),
			int(primary_entry_id),
			primary_entry,
			bool(fold_enabled),
			bool(expanded),
			int(child_event_count)
		)
	else:
		item.step_index = int(step_index)
		item.summary = str(summary)
		item.primary_entry_id = int(primary_entry_id)
		item.primary_entry = primary_entry.duplicate(true) if (primary_entry is Dictionary) else {}
		item.fold_enabled = bool(fold_enabled)
		item.expanded = bool(expanded)
		item.child_event_count = int(child_event_count)
	if int(primary_entry_id) >= 0:
		item.set_meta("log_entry_id", int(primary_entry_id))
	else:
		item.remove_meta("log_entry_id")
	if on_entry_clicked.is_valid() and not item.primary_entry_clicked.is_connected(on_entry_clicked):
		item.primary_entry_clicked.connect(on_entry_clicked)
	if on_timeline_header_clicked.is_valid() and not item.clicked.is_connected(on_timeline_header_clicked):
		item.clicked.connect(on_timeline_header_clicked)
	if on_entry_double_clicked.is_valid() and not item.primary_entry_double_clicked.is_connected(on_entry_double_clicked):
		item.primary_entry_double_clicked.connect(on_entry_double_clicked)
	if on_action_group_fold_toggled.is_valid() and not item.fold_toggled.is_connected(on_action_group_fold_toggled):
		item.fold_toggled.connect(on_action_group_fold_toggled)
	items.append(item)
	item.apply_timeline_state(int(timeline_cursor_index), int(timeline_head_index))

static func _count_event_items_for_action_group(entries: Array, skip_entry_id: int, show_phase_events: bool) -> int:
	if entries == null or entries.is_empty():
		return 0
	var count := 0
	var skip_id := int(skip_entry_id)
	for entry_val in entries:
		if not (entry_val is Dictionary):
			continue
		var entry: Dictionary = entry_val
		if skip_id >= 0 and int(entry.get("id", -1)) == skip_id:
			continue
		if not _should_show_event_item(entry, show_phase_events):
			continue
		count += 1
	return count

static func _append_event_descriptors_for_step(
	descriptors: Array[Dictionary],
	step_index: int,
	entries_by_step: Dictionary,
	show_phase_events: bool,
	indent_level: int,
	skip_entry_id: int
) -> void:
	var idx := int(step_index)
	var list_val = entries_by_step.get(idx, [])
	if not (list_val is Array):
		return
	var list: Array = list_val
	var skip_id := int(skip_entry_id)
	for entry_val in list:
		if not (entry_val is Dictionary):
			continue
		var entry: Dictionary = entry_val
		if skip_id >= 0 and int(entry.get("id", -1)) == skip_id:
			continue
		if not _should_show_event_item(entry, show_phase_events):
			continue
		descriptors.append({
			"kind": "event_item",
			"entry": entry.duplicate(true),
			"indent_level": int(indent_level),
		})

static func _add_event_items_for_step(
	items: Array[Control],
	log_container: VBoxContainer,
	step_index: int,
	entries_by_step: Dictionary,
	show_phase_events: bool,
	indent_level: int,
	skip_entry_id: int,
	timeline_cursor_index: int,
	timeline_head_index: int,
	on_entry_clicked: Callable,
	on_entry_double_clicked: Callable,
	acquire_item: Callable
) -> void:
	var idx := int(step_index)
	var list_val = entries_by_step.get(idx, [])
	if not (list_val is Array):
		return
	var list: Array = list_val
	var skip_id := int(skip_entry_id)
	for entry_val in list:
		if not (entry_val is Dictionary):
			continue
		var entry: Dictionary = entry_val
		if skip_id >= 0 and int(entry.get("id", -1)) == skip_id:
			continue
		if not _should_show_event_item(entry, show_phase_events):
			continue
		_add_event_item(items, log_container, entry, indent_level, timeline_cursor_index, timeline_head_index, on_entry_clicked, on_entry_double_clicked, acquire_item)

static func _add_event_item(
	items: Array[Control],
	log_container: VBoxContainer,
	entry: Dictionary,
	indent_level: int,
	timeline_cursor_index: int,
	timeline_head_index: int,
	on_entry_clicked: Callable,
	on_entry_double_clicked: Callable,
	acquire_item: Callable
) -> void:
	var item = _acquire_control_item(acquire_item, "event_item")
	if item == null:
		item = GameLogEventItemClass.new()
	item.set_meta("_log_pool_kind", "event_item")
	item.set_meta("log_entry_id", int(entry.get("id", -1)))
	log_container.add_child(item)
	if item.has_method("configure_entry"):
		item.configure_entry(entry, int(indent_level))
	else:
		item.entry_data = entry
		item.indent_level = int(indent_level)
	if on_entry_clicked.is_valid() and not item.entry_clicked.is_connected(on_entry_clicked):
		item.entry_clicked.connect(on_entry_clicked)
	if on_entry_double_clicked.is_valid() and not item.entry_double_clicked.is_connected(on_entry_double_clicked):
		item.entry_double_clicked.connect(on_entry_double_clicked)
	items.append(item)
	item.apply_timeline_state(int(timeline_cursor_index), int(timeline_head_index))
