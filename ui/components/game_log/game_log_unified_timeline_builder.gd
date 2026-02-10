# GameLogPanel：统一 step_timeline 视图构建器（M4.3）
extends RefCounted

const ActionIdsClass = preload("res://core/actions/action_ids.gd")
const GameLogEntryUtilsClass = preload("res://ui/components/game_log/game_log_entry_utils.gd")
const GameLogRoundHeaderItemClass = preload("res://ui/components/game_log/game_log_round_header_item.gd")
const GameLogPhaseHeaderItemClass = preload("res://ui/components/game_log/game_log_phase_header_item.gd")
const GameLogActionGroupHeaderItemClass = preload("res://ui/components/game_log/game_log_action_group_header_item.gd")
const GameLogEventItemClass = preload("res://ui/components/game_log/game_log_event_item.gd")

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
	initial_phase_segment: String
) -> Array[Control]:
	var items: Array[Control] = []
	if log_container == null or not is_instance_valid(log_container):
		return items

	var steps_val = step_timeline.get("steps", null)
	if not (steps_val is Array):
		return items
	var steps: Array = steps_val

	var entries_by_step := _build_entries_by_step(entries_all)

	var prev_round := int(initial_round_number)
	var prev_phase := str(initial_phase_segment)
	if prev_phase.is_empty():
		prev_phase = "?"

	# RoundHeader：默认仅显示 1..n 回合（Setup 的 round=0 不显示）
	if prev_round >= 1:
		_add_round_header_item(items, log_container, prev_round, -1, timeline_cursor_index, timeline_head_index, on_timeline_header_clicked)

	# -1: 初始状态
	var phase_header = _add_phase_header_item(items, log_container, prev_phase, -1, timeline_cursor_index, timeline_head_index, on_timeline_header_clicked)
	var init_entries: Array = entries_by_step.get(-1, [])
	var init_header := _build_action_group_header_data(-1, {}, init_entries, show_phase_events)
	var init_primary_id := int(init_header.get("primary_entry_id", -1))
	var init_primary_entry_val = init_header.get("primary_entry", {})
	var init_primary_entry: Dictionary = init_primary_entry_val if (init_primary_entry_val is Dictionary) else {}
	var init_child_count := _count_event_items_for_action_group(init_entries, init_primary_id, show_phase_events)
	var init_expanded := _is_expanded(is_action_group_expanded, -1)
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
		on_timeline_header_clicked,
		on_entry_double_clicked,
		on_action_group_fold_toggled
	)
	if init_expanded:
		_add_event_items_for_step(items, log_container, -1, entries_by_step, show_phase_events, 2, init_primary_id, timeline_cursor_index, timeline_head_index, on_entry_clicked, on_entry_double_clicked)

	for idx in range(steps.size()):
		var step_val = steps[idx]
		if not (step_val is Dictionary):
			continue
		var step: Dictionary = step_val
		var round_num := int(step.get("round", -1))
		var phase_seg := str(step.get("phase", "")).strip_edges()
		if phase_seg.is_empty():
			phase_seg = "?"

		var round_changed := (round_num != prev_round)
		if round_changed and round_num >= 1:
			_add_round_header_item(items, log_container, round_num, idx, timeline_cursor_index, timeline_head_index, on_timeline_header_clicked)

		if round_changed or phase_seg != prev_phase:
			if phase_header != null and is_instance_valid(phase_header):
				phase_header.end_step_index = idx - 1
			phase_header = _add_phase_header_item(items, log_container, phase_seg, idx, timeline_cursor_index, timeline_head_index, on_timeline_header_clicked)

		var kind := str(step.get("kind", "")).strip_edges()
		if kind == "phase":
			# phase step：不再渲染“进入X”类 ActionGroup 行；阶段标题已足够承载该锚点。
			_add_event_items_for_step(items, log_container, idx, entries_by_step, show_phase_events, 1, -1, timeline_cursor_index, timeline_head_index, on_entry_clicked, on_entry_double_clicked)
		else:
			var step_entries: Array = entries_by_step.get(idx, [])
			var header := _build_action_group_header_data(idx, step, step_entries, show_phase_events)
			var primary_id := int(header.get("primary_entry_id", -1))
			var primary_entry_val = header.get("primary_entry", {})
			var primary_entry: Dictionary = primary_entry_val if (primary_entry_val is Dictionary) else {}
			var child_count := _count_event_items_for_action_group(step_entries, primary_id, show_phase_events)
			var expanded := _is_expanded(is_action_group_expanded, idx)
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
				on_timeline_header_clicked,
				on_entry_double_clicked,
				on_action_group_fold_toggled
			)
			if expanded:
				_add_event_items_for_step(items, log_container, idx, entries_by_step, show_phase_events, 2, primary_id, timeline_cursor_index, timeline_head_index, on_entry_clicked, on_entry_double_clicked)

		prev_round = round_num
		prev_phase = phase_seg

	if phase_header != null and is_instance_valid(phase_header):
		phase_header.end_step_index = steps.size() - 1

	return items

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
		var step_entries: Array = entries_by_step.get(idx, [])
		if kind == "phase":
			# phase step 没有 ActionGroupHeader：只计可见子项（仍受“显示阶段事件”开关影响）。
			visible += _count_event_items_for_action_group(step_entries, -1, show_phase_events)
			continue

		var primary := _pick_primary_entry_for_action_group(step_entries)
		var primary_id := int(primary.get("id", -1)) if (primary != null and not primary.is_empty()) else -1
		if primary_id >= 0:
			visible += 1
		if _is_expanded(is_action_group_expanded, idx):
			visible += _count_event_items_for_action_group(step_entries, primary_id, show_phase_events)

	return visible

static func _is_expanded(is_action_group_expanded: Callable, step_index: int) -> bool:
	if not is_action_group_expanded.is_valid():
		return false
	return bool(is_action_group_expanded.call(int(step_index)))

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
			return ("玩家%d: %s" % [actor + 1, action_name]) if actor >= 0 else action_name
	return "系统推进"

static func _add_round_header_item(
	items: Array[Control],
	log_container: VBoxContainer,
	round_number: int,
	start_step_index: int,
	timeline_cursor_index: int,
	timeline_head_index: int,
	on_timeline_header_clicked: Callable
) -> void:
	var item = GameLogRoundHeaderItemClass.new()
	item.round_number = int(round_number)
	item.start_step_index = int(start_step_index)
	if on_timeline_header_clicked.is_valid():
		item.clicked.connect(on_timeline_header_clicked)
	log_container.add_child(item)
	items.append(item)
	item.apply_timeline_state(int(timeline_cursor_index), int(timeline_head_index))

static func _add_phase_header_item(
	items: Array[Control],
	log_container: VBoxContainer,
	phase_segment: String,
	start_step: int,
	timeline_cursor_index: int,
	timeline_head_index: int,
	on_timeline_header_clicked: Callable
) -> Control:
	var item = GameLogPhaseHeaderItemClass.new()
	item.phase_segment = str(phase_segment)
	item.start_step_index = int(start_step)
	item.end_step_index = int(start_step)
	if on_timeline_header_clicked.is_valid():
		item.clicked.connect(on_timeline_header_clicked)
	log_container.add_child(item)
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
	on_timeline_header_clicked: Callable,
	on_entry_double_clicked: Callable,
	on_action_group_fold_toggled: Callable
) -> void:
	var item = GameLogActionGroupHeaderItemClass.new()
	item.step_index = int(step_index)
	item.summary = str(summary)
	item.primary_entry_id = int(primary_entry_id)
	item.primary_entry = primary_entry.duplicate(true) if (primary_entry is Dictionary) else {}
	item.fold_enabled = bool(fold_enabled)
	item.expanded = bool(expanded)
	item.child_event_count = int(child_event_count)
	if on_timeline_header_clicked.is_valid():
		item.clicked.connect(on_timeline_header_clicked)
	if on_entry_double_clicked.is_valid():
		item.primary_entry_double_clicked.connect(on_entry_double_clicked)
	if on_action_group_fold_toggled.is_valid():
		item.fold_toggled.connect(on_action_group_fold_toggled)
	log_container.add_child(item)
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
	on_entry_double_clicked: Callable
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
		_add_event_item(items, log_container, entry, indent_level, timeline_cursor_index, timeline_head_index, on_entry_clicked, on_entry_double_clicked)

static func _add_event_item(
	items: Array[Control],
	log_container: VBoxContainer,
	entry: Dictionary,
	indent_level: int,
	timeline_cursor_index: int,
	timeline_head_index: int,
	on_entry_clicked: Callable,
	on_entry_double_clicked: Callable
) -> void:
	var item = GameLogEventItemClass.new()
	item.entry_data = entry
	item.indent_level = int(indent_level)
	if on_entry_clicked.is_valid():
		item.entry_clicked.connect(on_entry_clicked)
	if on_entry_double_clicked.is_valid():
		item.entry_double_clicked.connect(on_entry_double_clicked)
	log_container.add_child(item)
	items.append(item)
	item.apply_timeline_state(int(timeline_cursor_index), int(timeline_head_index))
