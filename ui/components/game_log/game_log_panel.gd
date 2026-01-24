# 游戏日志面板组件
# 显示游戏事件历史记录
class_name GameLogPanel
extends Control

signal close_requested()
signal log_entry_clicked(entry_id: int)
signal timeline_seek_requested(timeline_index: int)
signal log_added(entry: Dictionary)

@onready var title_label: Label = $MarginContainer/VBoxContainer/TitleRow/TopRow/TitleLabel
@onready var show_phase_events_check: CheckBox = $MarginContainer/VBoxContainer/TitleRow/OptionsRow/ShowPhaseEventsCheck
@onready var expand_btn: Button = $MarginContainer/VBoxContainer/TitleRow/TopRow/ExpandButton
@onready var close_btn: Button = $MarginContainer/VBoxContainer/TitleRow/TopRow/CloseButton
@onready var replay_bar: Control = $MarginContainer/VBoxContainer/TitleRow/ReplayBar
@onready var scroll_container: ScrollContainer = $MarginContainer/VBoxContainer/ScrollContainer
@onready var log_container: VBoxContainer = $MarginContainer/VBoxContainer/ScrollContainer/LogContainer
@onready var auto_scroll_check: CheckBox = $MarginContainer/VBoxContainer/BottomRow/AutoScrollCheck
@onready var entry_count_label: Label = $MarginContainer/VBoxContainer/BottomRow/EntryCountLabel

# 日志类型
enum LogType {
	SYSTEM,      # 系统消息
	PHASE,       # 阶段变更
	PLAYER,      # 玩家操作
	GAME_EVENT,  # 游戏事件（银行破产等）
	DEBUG,       # 调试信息
}

const LOG_TYPE_NAMES: Dictionary = {
	LogType.SYSTEM: "系统",
	LogType.PHASE: "阶段",
	LogType.PLAYER: "玩家",
	LogType.GAME_EVENT: "事件",
	LogType.DEBUG: "调试",
}

const LOG_TYPE_COLORS: Dictionary = {
	LogType.SYSTEM: Color(0.6, 0.6, 0.6, 1),
	LogType.PHASE: Color(0.5, 0.7, 0.9, 1),
	LogType.PLAYER: Color(0.9, 0.9, 0.9, 1),
	LogType.GAME_EVENT: Color(0.9, 0.7, 0.4, 1),
	LogType.DEBUG: Color(0.5, 0.8, 0.5, 1),
}

const PHASE_DISPLAY_NAMES: Dictionary = {
	"Working": "工作时间",
	"Dinnertime": "晚餐时间",
	"Setup": "开局设置",
	"Payday": "发薪日",
	"Marketing": "广告行动",
	"Cleanup": "清理阶段",
	"Restructuring": "重组结构",
	"OrderOfBusiness": "商业秩序",
	"GameOver": "游戏结束",
}

var _step_timeline: Dictionary = {} # {initial_state_dict, steps[], events[]}
var _timeline_entries: Array[Dictionary] = [] # timeline events formatted as entries
var _extra_entries: Array[Dictionary] = [] # UI-only logs (e.g. failed action)
var _entries_all: Array[Dictionary] = []  # merged entries for details lookup
var _entry_id_counter: int = 0
var _log_items: Array[Control] = [] # LogItem / RoundHeaderItem / PhaseHeaderItem / ActionGroupHeaderItem / EventItem
var _auto_scroll: bool = true
var _scroll_to_bottom_requested: bool = false
var _max_entries: int = 0 # 0 表示不截断（完整时间线需要保留未来日志）
var _player_count: int = 0
var _show_phase_events: bool = false

# 时间线（回放/查看历史）预留：在 M1 引入“完整日志”前仅存储指针，不改变渲染。
var _timeline_head_index: int = -1
var _timeline_cursor_index: int = -1

const FULL_LOG_WINDOW_SCENE_PATH := "res://ui/components/game_log/full_log_window.tscn"

var _full_log_window_scene: PackedScene = null
var _details_window: Window = null
var _details_message_label: Label = null
var _details_text: TextEdit = null

func _ready() -> void:
	if auto_scroll_check != null:
		auto_scroll_check.toggled.connect(_on_auto_scroll_toggled)
		auto_scroll_check.button_pressed = _auto_scroll

	if expand_btn != null:
		expand_btn.pressed.connect(_on_expand_pressed)
	if close_btn != null:
		close_btn.pressed.connect(_on_close_pressed)

	if show_phase_events_check != null:
		show_phase_events_check.toggled.connect(_on_show_phase_events_toggled)
		show_phase_events_check.button_pressed = _show_phase_events

func add_log(log_type: LogType, message: String, details: Dictionary = {}) -> int:
	var entry_id := _entry_id_counter
	_entry_id_counter += 1

	var entry: Dictionary = {
		"id": entry_id,
		"type": log_type,
		"message": message,
		"timestamp": Time.get_datetime_string_from_system(),
		"details": details,
	}

	if _is_step_timeline_loaded():
		# UI-only 日志：默认挂到当前 cursor step（回放/复盘时仍可定位到该 step）
		_attach_entry_to_current_step(entry)
		_extra_entries.append(entry)
		_rebuild_entries_all()
		log_added.emit(entry)
		_rebuild_display()
		_apply_timeline_state_to_items()
		_update_entry_count()
		return entry_id

	_entries_all.append(entry)
	log_added.emit(entry)

	# 限制最大条目数
	_enforce_max_entries()

	_add_log_item(entry)
	_update_entry_count()

	return entry_id

func _enforce_max_entries() -> void:
	if _max_entries <= 0:
		return
	while _entries_all.size() > _max_entries:
		_entries_all.pop_front()

func append_entry(entry: Dictionary) -> void:
	if entry == null or entry.is_empty():
		return

	var d: Dictionary = entry.duplicate(true)
	if _is_step_timeline_loaded():
		d["id"] = _entry_id_counter
		_entry_id_counter += 1
		if not d.has("step_index"):
			_attach_entry_to_current_step(d)
		_extra_entries.append(d)
		_rebuild_entries_all()
		_rebuild_display()
		_apply_timeline_state_to_items()
		_update_entry_count()
		return

	_entries_all.append(d)
	_enforce_max_entries()
	_add_log_item(d)
	_update_entry_count()

func get_entries() -> Array[Dictionary]:
	return _entries_all.duplicate(true)

func load_entries(entries: Array[Dictionary]) -> void:
	# Flat list mode (legacy/tests). This intentionally clears step timeline view state.
	_step_timeline.clear()
	_timeline_entries.clear()
	_extra_entries.clear()
	_entries_all.clear()
	_entry_id_counter = 0

	for e in entries:
		if not (e is Dictionary):
			continue
		var d: Dictionary = e
		_entries_all.append(d.duplicate(true))
		var id_val = d.get("id", null)
		if id_val is int:
			_entry_id_counter = maxi(_entry_id_counter, int(id_val) + 1)
		elif id_val is float:
			var f: float = float(id_val)
			if f == floor(f):
				_entry_id_counter = maxi(_entry_id_counter, int(f) + 1)

	_rebuild_display()
	_apply_timeline_state_to_items(true)
	_update_entry_count()

func load_step_timeline(timeline: Dictionary, entries: Array[Dictionary], reset_extra_entries: bool = false) -> void:
	# Unified timeline view (M4.3): structure comes from steps, contents come from formatted entries.
	_step_timeline = timeline.duplicate(true) if (timeline is Dictionary) else {}
	_timeline_entries.clear()
	if entries is Array:
		for e in entries:
			if e is Dictionary:
				var d: Dictionary = Dictionary(e).duplicate(true)
				d["id"] = _entry_id_counter
				_entry_id_counter += 1
				_timeline_entries.append(d)

	if reset_extra_entries:
		_extra_entries.clear()

	_rebuild_entries_all()
	_rebuild_display()
	_apply_timeline_state_to_items(true)
	_update_entry_count()

func set_expand_enabled(enabled: bool) -> void:
	if expand_btn != null:
		expand_btn.visible = enabled

func set_timeline_head(head_index: int) -> void:
	var h := int(head_index)
	if h == _timeline_head_index:
		return
	_timeline_head_index = h
	_apply_timeline_state_to_items()

func set_timeline_cursor(cursor_index: int) -> void:
	var c := int(cursor_index)
	if c == _timeline_cursor_index:
		return
	_timeline_cursor_index = c
	var should_scroll := _timeline_cursor_index < _timeline_head_index

	_apply_timeline_state_to_items(should_scroll)

func set_entry_command_index(entry_id: int, command_index: int) -> void:
	var cmd := int(command_index)
	for i in range(_entries_all.size()):
		var e_val = _entries_all[i]
		if not (e_val is Dictionary):
			continue
		var e: Dictionary = e_val
		if int(e.get("id", -1)) != int(entry_id):
			continue

		e["command_index"] = cmd
		var details_val = e.get("details", {})
		var details: Dictionary = details_val if (details_val is Dictionary) else {}
		details["command_index"] = cmd
		e["details"] = details
		_entries_all[i] = e
		break

func add_system_log(message: String, details: Dictionary = {}) -> int:
	return add_log(LogType.SYSTEM, message, details)

func add_phase_log(message: String, details: Dictionary = {}) -> int:
	return add_log(LogType.PHASE, message, details)

func add_player_log(player_id: int, message: String, details: Dictionary = {}) -> int:
	var full_message := "玩家%d: %s" % [player_id + 1, message]
	return add_log(LogType.PLAYER, full_message, details)

func add_event_log(message: String, details: Dictionary = {}) -> int:
	return add_log(LogType.GAME_EVENT, message, details)

func add_debug_log(message: String, details: Dictionary = {}) -> int:
	return add_log(LogType.DEBUG, message, details)

func clear_logs() -> void:
	_step_timeline.clear()
	_timeline_entries.clear()
	_extra_entries.clear()
	_entries_all.clear()
	_clear_display()
	_update_entry_count()

func get_replay_bar() -> Control:
	return replay_bar

func apply_font_settings() -> void:
	# 允许 SettingsDialog 在运行时调整日志可读性（例如字体倍率）。
	for item in _log_items:
		if is_instance_valid(item) and item.has_method("apply_font_settings"):
			item.apply_font_settings()

func set_player_count(count: int) -> void:
	_player_count = maxi(0, count)

func _is_step_timeline_loaded() -> bool:
	if _step_timeline == null or _step_timeline.is_empty():
		return false
	var steps_val = _step_timeline.get("steps", null)
	return (steps_val is Array)

func _rebuild_entries_all() -> void:
	_entries_all.clear()
	for e in _timeline_entries:
		if e is Dictionary:
			_entries_all.append(Dictionary(e))
	for e2 in _extra_entries:
		if e2 is Dictionary:
			_entries_all.append(Dictionary(e2))

func _get_initial_state_dict() -> Dictionary:
	var init_val = _step_timeline.get("initial_state_dict", null)
	return Dictionary(init_val) if (init_val is Dictionary) else {}

func _get_initial_round_number() -> int:
	var init := _get_initial_state_dict()
	var r_val = init.get("round_number", null)
	if r_val is int:
		return int(r_val)
	if r_val is float:
		var f: float = float(r_val)
		if f == floor(f):
			return int(f)
	return -1

func _get_initial_phase_segment() -> String:
	var init := _get_initial_state_dict()
	return str(init.get("phase", "")).strip_edges()

func _get_anchor_command_index_for_step(step_index: int) -> int:
	var idx := int(step_index)
	if idx < 0:
		return -1
	var steps_val = _step_timeline.get("steps", null)
	if not (steps_val is Array):
		return -1
	var steps: Array = steps_val
	if idx >= steps.size():
		return -1
	var step_val = steps[idx]
	if not (step_val is Dictionary):
		return -1
	return int(Dictionary(step_val).get("anchor_command_index", -1))

func _get_phase_for_step(step_index: int) -> String:
	var idx := int(step_index)
	if idx < 0:
		return _get_initial_phase_segment()
	var steps_val = _step_timeline.get("steps", null)
	if not (steps_val is Array):
		return ""
	var steps: Array = steps_val
	if idx >= steps.size():
		return ""
	var step_val = steps[idx]
	if not (step_val is Dictionary):
		return ""
	return str(Dictionary(step_val).get("phase", "")).strip_edges()

func _attach_entry_to_current_step(entry: Dictionary) -> void:
	if entry == null or entry.is_empty():
		return
	var step_idx := int(_timeline_cursor_index)
	if step_idx < -1:
		step_idx = int(_timeline_head_index)
	if int(_timeline_head_index) >= -1:
		step_idx = clampi(step_idx, -1, int(_timeline_head_index))

	var cmd_idx := _get_anchor_command_index_for_step(step_idx)
	var phase_seg := _get_phase_for_step(step_idx)

	entry["step_index"] = step_idx
	entry["command_index"] = cmd_idx
	if not phase_seg.is_empty():
		entry["phase_segment"] = phase_seg
	entry["is_stage_event"] = false
	entry["source"] = "ui"

	var details_val = entry.get("details", {})
	var details: Dictionary = details_val.duplicate(true) if (details_val is Dictionary) else {}
	details["step_index"] = step_idx
	details["command_index"] = cmd_idx
	if not phase_seg.is_empty():
		details["phase_segment"] = phase_seg
	entry["details"] = details

func _add_log_item(entry: Dictionary) -> void:
	if log_container == null:
		return

	var item := LogItem.new()
	item.entry_data = entry
	item.log_type = entry.type
	item.entry_clicked.connect(_on_entry_clicked)
	item.entry_double_clicked.connect(_on_entry_double_clicked)
	log_container.add_child(item)
	_log_items.append(item)
	item.apply_timeline_state(_timeline_cursor_index, _timeline_head_index)

	_request_scroll_to_bottom()

func _request_scroll_to_bottom() -> void:
	if not _auto_scroll:
		return
	if _scroll_to_bottom_requested:
		return
	_scroll_to_bottom_requested = true
	call_deferred("_apply_scroll_to_bottom")

func _apply_scroll_to_bottom() -> void:
	_scroll_to_bottom_requested = false
	if scroll_container == null:
		return
	scroll_container.scroll_vertical = int(scroll_container.get_v_scroll_bar().max_value)

func _clear_display() -> void:
	for item in _log_items:
		if is_instance_valid(item):
			item.queue_free()
	_log_items.clear()

func _rebuild_display() -> void:
	_clear_display()

	if _is_step_timeline_loaded():
		_build_unified_timeline_display()
	else:
		for entry_val in _entries_all:
			if entry_val is Dictionary:
				_add_log_item(Dictionary(entry_val))

	_apply_timeline_state_to_items()

func _build_unified_timeline_display() -> void:
	if log_container == null:
		return

	var steps_val = _step_timeline.get("steps", null)
	if not (steps_val is Array):
		return
	var steps: Array = steps_val

	var entries_by_step := _build_entries_by_step()

	var prev_round := _get_initial_round_number()
	var prev_phase := _get_initial_phase_segment()
	if prev_phase.is_empty():
		prev_phase = "?"

	# -1: 初始状态
	var phase_header: PhaseHeaderItem = _add_phase_header_item(prev_phase, -1)
	_add_action_group_header_item(-1, _build_action_group_summary(-1, {}, entries_by_step.get(-1, [])))
	_add_event_items_for_step(-1, entries_by_step)

	for idx in range(steps.size()):
		var step_val = steps[idx]
		if not (step_val is Dictionary):
			continue
		var step: Dictionary = step_val
		var round_num := int(step.get("round", -1))
		var phase_seg := str(step.get("phase", "")).strip_edges()
		if phase_seg.is_empty():
			phase_seg = "?"

		var round_changed := (idx > 0 and round_num != prev_round)
		if round_changed:
			_add_round_header_item(idx)

		if round_changed or phase_seg != prev_phase:
			if phase_header != null and is_instance_valid(phase_header):
				phase_header.end_step_index = idx - 1
			phase_header = _add_phase_header_item(phase_seg, idx)

		_add_action_group_header_item(idx, _build_action_group_summary(idx, step, entries_by_step.get(idx, [])))
		_add_event_items_for_step(idx, entries_by_step)

		prev_round = round_num
		prev_phase = phase_seg

	if phase_header != null and is_instance_valid(phase_header):
		phase_header.end_step_index = steps.size() - 1

func _build_entries_by_step() -> Dictionary:
	var out: Dictionary = {} # step_index -> Array[Dictionary]
	for entry_val in _entries_all:
		if not (entry_val is Dictionary):
			continue
		var entry: Dictionary = entry_val
		var si := _get_entry_step_index(entry)
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

func _entry_is_stage_event(entry: Dictionary) -> bool:
	if entry == null or entry.is_empty():
		return false
	if entry.has("is_stage_event"):
		return bool(entry.get("is_stage_event", false))
	var t := str(entry.get("event_type", "")).strip_edges()
	if t.is_empty():
		var details_val = entry.get("details", null)
		if details_val is Dictionary:
			t = str(Dictionary(details_val).get("event_type", "")).strip_edges()
	if t.is_empty():
		return false
	if t.ends_with("_report"):
		return true
	return t in ["phase_changed", "sub_phase_changed", "round_started", "round_ended"]

func _should_show_event_item(entry: Dictionary) -> bool:
	if entry == null or entry.is_empty():
		return false
	if _show_phase_events:
		return true
	return not _entry_is_stage_event(entry)

func _build_action_group_summary(step_index: int, step: Dictionary, entries: Array) -> String:
	# 优先：动作组内第一条“玩家动作”（排除阶段事件子项）
	for e_val in entries:
		if not (e_val is Dictionary):
			continue
		var e: Dictionary = e_val
		if _entry_is_stage_event(e):
			continue
		if int(e.get("type", -1)) == LogType.PLAYER:
			var msg := str(e.get("message", "")).strip_edges()
			if not msg.is_empty():
				return msg

	# 兜底：系统摘要
	if step_index < 0:
		return "初始状态"

	var kind := str(step.get("kind", "")).strip_edges()
	var phase_seg := str(step.get("phase", "")).strip_edges()
	if kind == "phase" and not phase_seg.is_empty():
		return "进入%s" % _get_phase_display_name(phase_seg)
	return "系统推进"

func _get_phase_display_name(phase_segment: String) -> String:
	var key := str(phase_segment).strip_edges()
	if PHASE_DISPLAY_NAMES.has(key):
		return str(PHASE_DISPLAY_NAMES[key])
	return key if not key.is_empty() else "?"

func _add_round_header_item(start_step_index: int) -> void:
	if log_container == null:
		return
	var item := RoundHeaderItem.new()
	item.start_step_index = int(start_step_index)
	item.clicked.connect(_on_timeline_header_clicked)
	log_container.add_child(item)
	_log_items.append(item)
	item.apply_timeline_state(_timeline_cursor_index, _timeline_head_index)

func _add_phase_header_item(phase_segment: String, start_step: int) -> PhaseHeaderItem:
	if log_container == null:
		return null
	var item := PhaseHeaderItem.new()
	item.phase_segment = str(phase_segment)
	item.start_step_index = int(start_step)
	item.end_step_index = int(start_step)
	item.clicked.connect(_on_timeline_header_clicked)
	log_container.add_child(item)
	_log_items.append(item)
	item.apply_timeline_state(_timeline_cursor_index, _timeline_head_index)
	return item

func _add_action_group_header_item(step_index: int, summary: String) -> void:
	if log_container == null:
		return
	var item := ActionGroupHeaderItem.new()
	item.step_index = int(step_index)
	item.summary = str(summary)
	item.clicked.connect(_on_timeline_header_clicked)
	log_container.add_child(item)
	_log_items.append(item)
	item.apply_timeline_state(_timeline_cursor_index, _timeline_head_index)

func _add_event_items_for_step(step_index: int, entries_by_step: Dictionary) -> void:
	if log_container == null:
		return
	var idx := int(step_index)
	var list_val = entries_by_step.get(idx, [])
	if not (list_val is Array):
		return
	var list: Array = list_val
	for entry_val in list:
		if not (entry_val is Dictionary):
			continue
		var entry: Dictionary = entry_val
		if not _should_show_event_item(entry):
			continue
		_add_event_item(entry, 2)

func _add_event_item(entry: Dictionary, indent_level: int = 0) -> void:
	if log_container == null:
		return
	var item := EventItem.new()
	item.entry_data = entry
	item.indent_level = int(indent_level)
	item.entry_clicked.connect(_on_entry_clicked)
	item.entry_double_clicked.connect(_on_entry_double_clicked)
	log_container.add_child(item)
	_log_items.append(item)
	item.apply_timeline_state(_timeline_cursor_index, _timeline_head_index)

func _on_timeline_header_clicked(timeline_index: int) -> void:
	timeline_seek_requested.emit(int(timeline_index))

func _update_entry_count() -> void:
	if entry_count_label == null:
		return

	var total := _entries_all.size()
	var visible := total
	if _is_step_timeline_loaded() and not _show_phase_events:
		visible = 0
		for entry_val in _entries_all:
			if entry_val is Dictionary and _should_show_event_item(Dictionary(entry_val)):
				visible += 1
	entry_count_label.text = "显示 %d / %d" % [visible, total]

func _get_entry_command_index(entry: Dictionary) -> int:
	if entry == null or entry.is_empty():
		return -999
	var ci_val = entry.get("command_index", null)
	if ci_val is int:
		return int(ci_val)
	if ci_val is float:
		var f: float = float(ci_val)
		if f == floor(f):
			return int(f)
	var details_val = entry.get("details", null)
	if details_val is Dictionary:
		var details: Dictionary = details_val
		var ci2_val = details.get("command_index", null)
		if ci2_val is int:
			return int(ci2_val)
		if ci2_val is float:
			var f2: float = float(ci2_val)
			if f2 == floor(f2):
				return int(f2)
	return -999

func _get_entry_step_index(entry: Dictionary) -> int:
	if entry == null or entry.is_empty():
		return -999
	var si_val = entry.get("step_index", null)
	if si_val is int:
		return int(si_val)
	if si_val is float:
		var f: float = float(si_val)
		if f == floor(f):
			return int(f)
	var details_val = entry.get("details", null)
	if details_val is Dictionary:
		var details: Dictionary = details_val
		var si2_val = details.get("step_index", null)
		if si2_val is int:
			return int(si2_val)
		if si2_val is float:
			var f2: float = float(si2_val)
			if f2 == floor(f2):
				return int(f2)
	return -999

func _get_entry_timeline_index(entry: Dictionary) -> int:
	# 优先 step_index（M4.2：大阶段可步进），否则回退到 command_index（旧命令时间线）。
	var si := _get_entry_step_index(entry)
	return si if si != -999 else _get_entry_command_index(entry)

func _apply_timeline_state_to_items(scroll_to_cursor: bool = false) -> void:
	for item in _log_items:
		if not is_instance_valid(item):
			continue
		if item.has_method("apply_timeline_state"):
			item.apply_timeline_state(_timeline_cursor_index, _timeline_head_index)

	if not scroll_to_cursor:
		return
	if OS.has_feature("headless"):
		return
	if scroll_container == null:
		return
	if not scroll_container.has_method("ensure_control_visible"):
		return

	# 定位到当前 cursor 对应的第一条可见日志（过滤后可能不存在）。
	for item in _log_items:
		if not is_instance_valid(item):
			continue
		if not item.has_method("get_timeline_index"):
			continue
		if int(item.call("get_timeline_index")) != _timeline_cursor_index:
			continue
		scroll_container.call("ensure_control_visible", item)
		break

func _on_show_phase_events_toggled(toggled: bool) -> void:
	_show_phase_events = bool(toggled)
	_rebuild_display()
	_apply_timeline_state_to_items()
	_update_entry_count()

func _on_auto_scroll_toggled(toggled: bool) -> void:
	_auto_scroll = toggled

func _on_close_pressed() -> void:
	close_requested.emit()

func _on_expand_pressed() -> void:
	if OS.has_feature("headless"):
		return
	var scene := _get_full_log_window_scene()
	if scene == null:
		return
	var win = scene.instantiate()
	if win == null:
		return
	get_tree().root.add_child(win)
	if win.has_method("open_for"):
		win.open_for(self)
	else:
		win.show()

func _get_full_log_window_scene() -> PackedScene:
	if _full_log_window_scene != null:
		return _full_log_window_scene
	var res = load(FULL_LOG_WINDOW_SCENE_PATH)
	if res is PackedScene:
		_full_log_window_scene = res
		return _full_log_window_scene
	return null

func _on_entry_clicked(entry_id: int) -> void:
	log_entry_clicked.emit(entry_id)

func _on_entry_double_clicked(entry_id: int) -> void:
	_open_entry_details(entry_id)

func get_entry_by_id(entry_id: int) -> Dictionary:
	var e := _find_entry_by_id(entry_id)
	return e.duplicate(true) if not e.is_empty() else {}

func get_entry_command_index(entry_id: int) -> int:
	var e := _find_entry_by_id(entry_id)
	return _get_entry_command_index(e) if not e.is_empty() else -999

func get_entry_timeline_index(entry_id: int) -> int:
	var e := _find_entry_by_id(entry_id)
	return _get_entry_timeline_index(e) if not e.is_empty() else -999

func _open_entry_details(entry_id: int) -> void:
	if OS.has_feature("headless"):
		return
	var entry := _find_entry_by_id(entry_id)
	if entry.is_empty():
		return
	_ensure_details_window()
	if _details_window == null or not is_instance_valid(_details_window):
		return

	if _details_message_label != null:
		var type_name: String = LOG_TYPE_NAMES.get(int(entry.get("type", 0)), "?")
		var ts := str(entry.get("timestamp", "")).strip_edges()
		var msg := str(entry.get("message", "")).strip_edges()
		_details_message_label.text = "[%s] %s\n%s" % [type_name, ts, msg]

	if _details_text != null:
		_details_text.text = _format_details_for_view(entry.get("details", {}))

	if _details_window.has_method("popup_centered"):
		_details_window.popup_centered()
	else:
		_details_window.show()

func _find_entry_by_id(entry_id: int) -> Dictionary:
	for e_val in _entries_all:
		if not (e_val is Dictionary):
			continue
		var e: Dictionary = e_val
		if int(e.get("id", -1)) == entry_id:
			return e
	return {}

func _format_details_for_view(details) -> String:
	if details == null:
		return ""
	# Prefer JSON when possible, fallback to var_to_str for non-JSON variants (Vector2i, Color...).
	if details is Dictionary or details is Array:
		var json := JSON.stringify(details, "\t")
		if not json.is_empty() and json != "null":
			return json
	return var_to_str(details)

func _ensure_details_window() -> void:
	if _details_window != null and is_instance_valid(_details_window):
		return
	if get_tree() == null or get_tree().root == null:
		return

	_details_window = Window.new()
	_details_window.title = "日志详情"
	_details_window.size = Vector2i(780, 520)
	_details_window.close_requested.connect(func() -> void:
		if is_instance_valid(_details_window):
			_details_window.hide()
	)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	_details_window.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	_details_message_label = Label.new()
	_details_message_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_details_message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_details_message_label)

	_details_text = TextEdit.new()
	_details_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_details_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_details_text.editable = false
	vbox.add_child(_details_text)

	get_tree().root.add_child(_details_window)


# === 内部类：日志条目 ===

# === 内部类：时间线行（M4.3）===

class RoundHeaderItem extends PanelContainer:
	signal clicked(timeline_index: int)

	# 点击跳转到该回合段落的第一条 ActionGroup（即 start_step_index）
	var start_step_index: int = -1

	var _label: Label
	var _panel_style: StyleBoxFlat = null
	var _timeline_is_future: bool = false

	func _ready() -> void:
		_build_ui()

	func _build_ui() -> void:
		var scale := 1.0
		if Globals != null:
			scale = clampf(float(Globals.log_font_scale), 0.5, 3.0)

		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		custom_minimum_size = Vector2(0, float(maxi(24, int(round(24.0 * scale)))))
		mouse_filter = Control.MOUSE_FILTER_STOP

		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.08, 0.08, 0.10, 0.9)
		style.set_corner_radius_all(2)
		add_theme_stylebox_override("panel", style)
		_panel_style = style

		var hbox := HBoxContainer.new()
		hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hbox.add_theme_constant_override("separation", 8)
		add_child(hbox)

		_label = Label.new()
		_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_label.add_theme_font_size_override("font_size", maxi(10, int(round(12.0 * scale))))
		_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75, 1))
		_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hbox.add_child(_label)

		_label.text = "回合切换"
		_apply_timeline_visuals()

	func get_timeline_index() -> int:
		return int(start_step_index)

	func apply_timeline_state(cursor_index: int, head_index: int) -> void:
		var cursor := int(cursor_index)
		var head := int(head_index)
		_timeline_is_future = (cursor < head and start_step_index >= 0 and start_step_index > cursor)
		_apply_timeline_visuals()

	func _apply_timeline_visuals() -> void:
		modulate = Color(0.85, 0.85, 0.85, 0.55) if _timeline_is_future else Color(1, 1, 1, 1)

	func apply_font_settings() -> void:
		var scale := 1.0
		if Globals != null:
			scale = clampf(float(Globals.log_font_scale), 0.5, 3.0)
		custom_minimum_size = Vector2(0, float(maxi(24, int(round(24.0 * scale)))))
		if _label != null:
			_label.add_theme_font_size_override("font_size", maxi(10, int(round(12.0 * scale))))

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			clicked.emit(get_timeline_index())

class PhaseHeaderItem extends PanelContainer:
	signal clicked(timeline_index: int)

	var phase_segment: String = ""
	var start_step_index: int = -1
	var end_step_index: int = -1

	var _label: Label
	var _panel_style: StyleBoxFlat = null
	var _timeline_is_future: bool = false
	var _timeline_is_cursor: bool = false

	func _ready() -> void:
		_build_ui()

	func _build_ui() -> void:
		var scale := 1.0
		if Globals != null:
			scale = clampf(float(Globals.log_font_scale), 0.5, 3.0)

		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		custom_minimum_size = Vector2(0, float(maxi(26, int(round(26.0 * scale)))))
		mouse_filter = Control.MOUSE_FILTER_STOP

		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.10, 0.10, 0.12, 0.85)
		style.set_corner_radius_all(2)
		add_theme_stylebox_override("panel", style)
		_panel_style = style

		var hbox := HBoxContainer.new()
		hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hbox.add_theme_constant_override("separation", 8)
		add_child(hbox)

		_label = Label.new()
		_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_label.add_theme_font_size_override("font_size", maxi(10, int(round(12.0 * scale))))
		_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.9, 1))
		hbox.add_child(_label)

		_update_text()
		_apply_timeline_visuals()

	func _update_text() -> void:
		var phase := str(phase_segment).strip_edges()
		if phase.is_empty():
			phase = "?"
		var display_name := GameLogPanel.PHASE_DISPLAY_NAMES.get(phase, phase)
		_label.text = str(display_name)

	func get_timeline_index() -> int:
		return int(start_step_index)

	func apply_timeline_state(cursor_index: int, head_index: int) -> void:
		var cursor := int(cursor_index)
		var head := int(head_index)
		_timeline_is_future = (cursor < head and start_step_index >= 0 and start_step_index > cursor)
		if end_step_index >= start_step_index:
			_timeline_is_cursor = (cursor >= start_step_index and cursor <= end_step_index)
		else:
			_timeline_is_cursor = (cursor == start_step_index)
		_apply_timeline_visuals()

	func _apply_timeline_visuals() -> void:
		if _panel_style != null:
			_panel_style.bg_color = Color(0.16, 0.16, 0.22, 0.90) if _timeline_is_cursor else Color(0.10, 0.10, 0.12, 0.85)
		modulate = Color(0.85, 0.85, 0.85, 0.55) if _timeline_is_future else Color(1, 1, 1, 1)

	func apply_font_settings() -> void:
		var scale := 1.0
		if Globals != null:
			scale = clampf(float(Globals.log_font_scale), 0.5, 3.0)
		custom_minimum_size = Vector2(0, float(maxi(26, int(round(26.0 * scale)))))
		if _label != null:
			_label.add_theme_font_size_override("font_size", maxi(10, int(round(12.0 * scale))))

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			clicked.emit(get_timeline_index())

class ActionGroupHeaderItem extends PanelContainer:
	signal clicked(timeline_index: int)

	var step_index: int = -1
	var summary: String = ""

	var _label: Label
	var _panel_style: StyleBoxFlat = null
	var _timeline_is_future: bool = false
	var _timeline_is_cursor: bool = false

	func _ready() -> void:
		_build_ui()

	func _build_ui() -> void:
		var scale := 1.0
		if Globals != null:
			scale = clampf(float(Globals.log_font_scale), 0.5, 3.0)

		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		custom_minimum_size = Vector2(0, float(maxi(26, int(round(26.0 * scale)))))
		mouse_filter = Control.MOUSE_FILTER_STOP

		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.12, 0.12, 0.14, 0.75)
		style.set_corner_radius_all(2)
		add_theme_stylebox_override("panel", style)
		_panel_style = style

		var hbox := HBoxContainer.new()
		hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hbox.add_theme_constant_override("separation", 8)
		add_child(hbox)

		# PhaseHeader 下一级缩进
		var spacer := Control.new()
		spacer.custom_minimum_size = Vector2(14, 0)
		hbox.add_child(spacer)

		_label = Label.new()
		_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_label.add_theme_font_size_override("font_size", maxi(9, int(round(11.0 * scale))))
		_label.add_theme_color_override("font_color", Color(0.82, 0.82, 0.85, 1))
		_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hbox.add_child(_label)

		_update_text()
		_apply_timeline_visuals()

	func _update_text() -> void:
		var sum := str(summary).strip_edges()
		if sum.is_empty():
			sum = "(无摘要)"
		_label.text = sum

	func get_timeline_index() -> int:
		return int(step_index)

	func apply_timeline_state(cursor_index: int, head_index: int) -> void:
		var cursor := int(cursor_index)
		var head := int(head_index)
		_timeline_is_future = (cursor < head and step_index >= 0 and step_index > cursor)
		_timeline_is_cursor = (step_index == cursor)
		_apply_timeline_visuals()

	func _apply_timeline_visuals() -> void:
		if _panel_style != null:
			_panel_style.bg_color = Color(0.20, 0.20, 0.28, 0.85) if _timeline_is_cursor else Color(0.12, 0.12, 0.14, 0.75)
		modulate = Color(0.85, 0.85, 0.85, 0.55) if _timeline_is_future else Color(1, 1, 1, 1)

	func apply_font_settings() -> void:
		var scale := 1.0
		if Globals != null:
			scale = clampf(float(Globals.log_font_scale), 0.5, 3.0)
		custom_minimum_size = Vector2(0, float(maxi(26, int(round(26.0 * scale)))))
		if _label != null:
			_label.add_theme_font_size_override("font_size", maxi(9, int(round(11.0 * scale))))
		_update_text()

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			clicked.emit(get_timeline_index())

class EventItem extends PanelContainer:
	signal entry_clicked(entry_id: int)
	signal entry_double_clicked(entry_id: int)

	var entry_data: Dictionary = {}
	var indent_level: int = 0

	var _label: Label
	var _panel_style: StyleBoxFlat = null
	var _timeline_is_future: bool = false
	var _timeline_is_cursor: bool = false

	const LOG_TYPE_COLORS: Dictionary = {
		0: Color(0.6, 0.6, 0.6, 1),  # SYSTEM
		1: Color(0.5, 0.7, 0.9, 1),  # PHASE
		2: Color(0.9, 0.9, 0.9, 1),  # PLAYER
		3: Color(0.9, 0.7, 0.4, 1),  # GAME_EVENT
		4: Color(0.5, 0.8, 0.5, 1),  # DEBUG
	}

	func _ready() -> void:
		_build_ui()

	func _build_ui() -> void:
		var scale := 1.0
		if Globals != null:
			scale = clampf(float(Globals.log_font_scale), 0.5, 3.0)

		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		custom_minimum_size = Vector2(0, float(maxi(22, int(round(22.0 * scale)))))
		mouse_filter = Control.MOUSE_FILTER_STOP

		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.12, 0.12, 0.14, 0.6)
		style.set_corner_radius_all(2)
		add_theme_stylebox_override("panel", style)
		_panel_style = style

		var hbox := HBoxContainer.new()
		hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hbox.add_theme_constant_override("separation", 8)
		add_child(hbox)

		# 缩进：默认作为 ActionGroup 的子项
		var spacer := Control.new()
		spacer.custom_minimum_size = Vector2(14 + 14 * maxi(0, indent_level - 1), 0)
		hbox.add_child(spacer)

		_label = Label.new()
		_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_label.add_theme_font_size_override("font_size", maxi(9, int(round(11.0 * scale))))
		_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hbox.add_child(_label)

		update_display()
		_apply_timeline_visuals()

	func update_display() -> void:
		if _label == null:
			return
		_label.text = str(entry_data.get("message", ""))
		var t := int(entry_data.get("type", 0))
		_label.add_theme_color_override("font_color", LOG_TYPE_COLORS.get(t, Color(0.85, 0.85, 0.85, 1)))

	func get_timeline_index() -> int:
		return _get_entry_timeline_index()

	func _get_entry_timeline_index() -> int:
		var si_val = entry_data.get("step_index", null)
		if si_val is int:
			return int(si_val)
		if si_val is float:
			var sf: float = float(si_val)
			if sf == floor(sf):
				return int(sf)
		var ci_val = entry_data.get("command_index", null)
		if ci_val is int:
			return int(ci_val)
		if ci_val is float:
			var f: float = float(ci_val)
			if f == floor(f):
				return int(f)
		return -999

	func apply_timeline_state(cursor_index: int, head_index: int) -> void:
		var idx := _get_entry_timeline_index()
		_timeline_is_future = (cursor_index < head_index and idx >= 0 and idx > cursor_index)
		_timeline_is_cursor = (idx == cursor_index)
		_apply_timeline_visuals()

	func _apply_timeline_visuals() -> void:
		if _panel_style != null:
			_panel_style.bg_color = Color(0.20, 0.20, 0.28, 0.85) if _timeline_is_cursor else Color(0.12, 0.12, 0.14, 0.6)
		modulate = Color(0.85, 0.85, 0.85, 0.55) if _timeline_is_future else Color(1, 1, 1, 1)

	func apply_font_settings() -> void:
		var scale := 1.0
		if Globals != null:
			scale = clampf(float(Globals.log_font_scale), 0.5, 3.0)
		custom_minimum_size = Vector2(0, float(maxi(22, int(round(22.0 * scale)))))
		if _label != null:
			_label.add_theme_font_size_override("font_size", maxi(9, int(round(11.0 * scale))))

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			var entry_id: int = int(entry_data.get("id", -1))
			if entry_id < 0:
				return
			if event.double_click:
				entry_double_clicked.emit(entry_id)
			else:
				entry_clicked.emit(entry_id)

class LogItem extends PanelContainer:
	signal entry_clicked(entry_id: int)
	signal entry_double_clicked(entry_id: int)

	var entry_data: Dictionary = {}
	var log_type: int = 0

	var _time_label: Label
	var _type_label: Label
	var _message_label: RichTextLabel
	var _panel_style: StyleBoxFlat = null
	var _timeline_is_future: bool = false
	var _timeline_is_cursor: bool = false

	const LOG_TYPE_COLORS: Dictionary = {
		0: Color(0.6, 0.6, 0.6, 1),  # SYSTEM
		1: Color(0.5, 0.7, 0.9, 1),  # PHASE
		2: Color(0.9, 0.9, 0.9, 1),  # PLAYER
		3: Color(0.9, 0.7, 0.4, 1),  # GAME_EVENT
		4: Color(0.5, 0.8, 0.5, 1),  # DEBUG
	}

	const LOG_TYPE_NAMES: Dictionary = {
		0: "系统",
		1: "阶段",
		2: "玩家",
		3: "事件",
		4: "调试",
	}

	func _ready() -> void:
		_build_ui()

	func _build_ui() -> void:
		var scale := 1.0
		if Globals != null:
			scale = clampf(float(Globals.log_font_scale), 0.5, 3.0)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		custom_minimum_size = Vector2(0, float(maxi(28, int(round(28.0 * scale)))))
		mouse_filter = Control.MOUSE_FILTER_STOP

		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.12, 0.12, 0.14, 0.6)
		style.set_corner_radius_all(2)
		add_theme_stylebox_override("panel", style)
		_panel_style = style

		var hbox := HBoxContainer.new()
		hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hbox.add_theme_constant_override("separation", 8)
		add_child(hbox)

		# 时间
		_time_label = Label.new()
		_time_label.custom_minimum_size = Vector2(50, 0)
		_time_label.add_theme_font_size_override("font_size", maxi(8, int(round(10.0 * scale))))
		_time_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 1))
		hbox.add_child(_time_label)

		# 类型
		_type_label = Label.new()
		_type_label.custom_minimum_size = Vector2(40, 0)
		_type_label.add_theme_font_size_override("font_size", maxi(9, int(round(11.0 * scale))))
		hbox.add_child(_type_label)

		# 消息
		_message_label = RichTextLabel.new()
		_message_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_message_label.add_theme_font_size_override("normal_font_size", maxi(10, int(round(12.0 * scale))))
		_message_label.bbcode_enabled = false
		_message_label.fit_content = true
		_message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_message_label.scroll_active = false
		_message_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hbox.add_child(_message_label)

		update_display()
		_apply_timeline_visuals()

	func apply_timeline_state(cursor_index: int, head_index: int) -> void:
		var cmd_index := _get_entry_command_index()
		_timeline_is_future = (cursor_index < head_index and cmd_index >= 0 and cmd_index > cursor_index)
		_timeline_is_cursor = (cmd_index == cursor_index)
		_apply_timeline_visuals()

	func get_timeline_index() -> int:
		return _get_entry_command_index()

	func _get_entry_command_index() -> int:
		# timeline index: prefer step_index (M4.2), fallback to command_index.
		var si_val = entry_data.get("step_index", null)
		if si_val is int:
			return int(si_val)
		if si_val is float:
			var sf: float = float(si_val)
			if sf == floor(sf):
				return int(sf)

		var ci_val = entry_data.get("command_index", null)
		if ci_val is int:
			return int(ci_val)
		if ci_val is float:
			var f: float = float(ci_val)
			if f == floor(f):
				return int(f)
		var details_val = entry_data.get("details", null)
		if details_val is Dictionary:
			var details: Dictionary = details_val
			var si2_val = details.get("step_index", null)
			if si2_val is int:
				return int(si2_val)
			if si2_val is float:
				var sf2: float = float(si2_val)
				if sf2 == floor(sf2):
					return int(sf2)
			var ci2_val = details.get("command_index", null)
			if ci2_val is int:
				return int(ci2_val)
			if ci2_val is float:
				var f2: float = float(ci2_val)
				if f2 == floor(f2):
					return int(f2)
		return -999

	func _apply_timeline_visuals() -> void:
		if _panel_style != null:
			_panel_style.bg_color = Color(0.20, 0.20, 0.28, 0.85) if _timeline_is_cursor else Color(0.12, 0.12, 0.14, 0.6)

		if _timeline_is_cursor:
			modulate = Color(1, 1, 1, 1)
		elif _timeline_is_future:
			modulate = Color(0.85, 0.85, 0.85, 0.55)
		else:
			modulate = Color(1, 1, 1, 1)

	func apply_font_settings() -> void:
		var scale := 1.0
		if Globals != null:
			scale = clampf(float(Globals.log_font_scale), 0.5, 3.0)
		custom_minimum_size = Vector2(0, float(maxi(28, int(round(28.0 * scale)))))
		if _time_label != null:
			_time_label.add_theme_font_size_override("font_size", maxi(8, int(round(10.0 * scale))))
		if _type_label != null:
			_type_label.add_theme_font_size_override("font_size", maxi(9, int(round(11.0 * scale))))
		if _message_label != null:
			_message_label.add_theme_font_size_override("normal_font_size", maxi(10, int(round(12.0 * scale))))

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton:
			if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
				var entry_id: int = int(entry_data.get("id", -1))
				if entry_id < 0:
					return
				if event.double_click:
					entry_double_clicked.emit(entry_id)
				else:
					entry_clicked.emit(entry_id)

	func update_display() -> void:
		if _time_label != null:
			var timestamp: String = str(entry_data.get("timestamp", ""))
			# 只显示时间部分
			if timestamp.length() >= 8:
				_time_label.text = timestamp.substr(timestamp.length() - 8, 5)
			else:
				_time_label.text = timestamp

		if _type_label != null:
			var type_name: String = LOG_TYPE_NAMES.get(log_type, "?")
			_type_label.text = "[%s]" % type_name
			var type_color: Color = LOG_TYPE_COLORS.get(log_type, Color.WHITE)
			_type_label.add_theme_color_override("font_color", type_color)

		if _message_label != null:
			_message_label.text = str(entry_data.get("message", ""))
