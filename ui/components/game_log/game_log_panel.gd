# 游戏日志面板组件
# 显示游戏事件历史记录
class_name GameLogPanel
extends Control

signal close_requested()
signal log_entry_clicked(entry_id: int)
signal timeline_seek_requested(timeline_index: int)
signal log_added(entry: Dictionary)
signal log_entry_hovered(entry_id: int, hovering: bool)
signal replay_toggle_changed(active: bool)

@onready var title_label: Label = $MarginContainer/VBoxContainer/TitleRow/TopRow/TitleLabel
@onready var options_row: Control = $MarginContainer/VBoxContainer/TitleRow/OptionsRow
@onready var show_phase_events_check: CheckBox = $MarginContainer/VBoxContainer/TitleRow/OptionsRow/ShowPhaseEventsCheck
@onready var fold_details_check: CheckBox = $MarginContainer/VBoxContainer/TitleRow/OptionsRow/FoldDetailsCheck
@onready var close_btn: Button = $MarginContainer/VBoxContainer/TitleRow/TopRow/CloseButton
@onready var replay_toggle_button: Button = $MarginContainer/VBoxContainer/TitleRow/TopRow/ReplayToggleButton
@onready var replay_bar: Control = $MarginContainer/VBoxContainer/TitleRow/ReplayBar
@onready var scroll_container: ScrollContainer = $MarginContainer/VBoxContainer/ScrollContainer
@onready var log_container: VBoxContainer = $MarginContainer/VBoxContainer/ScrollContainer/LogContainer
@onready var auto_scroll_check: CheckBox = $MarginContainer/VBoxContainer/BottomRow/AutoScrollCheck
@onready var entry_count_label: Label = $MarginContainer/VBoxContainer/BottomRow/EntryCountLabel

const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const UiStylesClass = preload("res://ui/utils/ui_styles.gd")
const GameLogEntryUtilsClass = preload("res://ui/components/game_log/game_log_entry_utils.gd")
const GameLogDetailsWindowControllerClass = preload("res://ui/components/game_log/game_log_details_window_controller.gd")
const GameLogUnifiedTimelineBuilderClass = preload("res://ui/components/game_log/game_log_unified_timeline_builder.gd")
const GameLogItemClass = preload("res://ui/components/game_log/game_log_item.gd")

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
	DefsClass.PHASE_WORKING: "工作时间",
	DefsClass.PHASE_DINNERTIME: "晚餐结算",
	DefsClass.PHASE_SETUP: "开局设置",
	DefsClass.PHASE_PAYDAY: "发薪日",
	DefsClass.PHASE_MARKETING: "广告行动",
	DefsClass.PHASE_CLEANUP: "清理阶段",
	DefsClass.PHASE_RESTRUCTURING: "重组结构",
	DefsClass.PHASE_ORDER_OF_BUSINESS: "商业秩序",
	DefsClass.PHASE_GAME_OVER: "游戏结束",
}

var _step_timeline: Dictionary = {} # {initial_state_dict, steps[], events[]}
var _timeline_entries: Array[Dictionary] = [] # timeline events formatted as entries
var _extra_entries: Array[Dictionary] = [] # UI-only logs (e.g. failed action)
var _entries_all: Array[Dictionary] = []  # merged entries for details lookup
var _entry_id_counter: int = 0
var _log_items: Array[Control] = [] # GameLogItem / GameLogRoundHeaderItem / GameLogPhaseHeaderItem / GameLogActionGroupHeaderItem / GameLogEventItem
var _auto_scroll: bool = true
var _scroll_to_bottom_requested: bool = false
var _max_entries: int = 0 # 0 表示不截断（完整时间线需要保留未来日志）
var _player_count: int = 0
var _show_phase_events: bool = false
var _fold_details_enabled: bool = false
var _expanded_action_groups: Dictionary = {} # step_index -> true（当启用折叠时仅展开少量动作组）

# 时间线（回放/查看历史）预留：在 M1 引入“完整日志”前仅存储指针，不改变渲染。
var _timeline_head_index: int = -1
var _timeline_cursor_index: int = -1

var _details_controller = null
var _blank_display_warned: bool = false
var _replay_toggle_available: bool = true
var _replay_toggle_inactive_text: String = "进入回放"
var _replay_toggle_disabled_reason: String = ""

func _ready() -> void:
	if auto_scroll_check != null:
		auto_scroll_check.toggled.connect(_on_auto_scroll_toggled)
		auto_scroll_check.button_pressed = _auto_scroll

	if replay_toggle_button != null:
		replay_toggle_button.toggled.connect(_on_replay_toggle_toggled)

	if close_btn != null:
		close_btn.pressed.connect(_on_close_pressed)

	if show_phase_events_check != null:
		show_phase_events_check.toggled.connect(_on_show_phase_events_toggled)
		show_phase_events_check.button_pressed = _show_phase_events

	if fold_details_check != null:
		fold_details_check.toggled.connect(_on_fold_details_toggled)
		fold_details_check.button_pressed = _fold_details_enabled

	if options_row != null:
		options_row.visible = false
	if show_phase_events_check != null:
		show_phase_events_check.visible = false
	if fold_details_check != null:
		fold_details_check.visible = false

	if title_label != null:
		UiStylesClass.apply_label_dark(title_label)
	if show_phase_events_check != null:
		UiStylesClass.apply_check_box_field(show_phase_events_check)
	if fold_details_check != null:
		UiStylesClass.apply_check_box_field(fold_details_check)
	if auto_scroll_check != null:
		UiStylesClass.apply_check_box_field(auto_scroll_check)
	if entry_count_label != null:
		UiStylesClass.apply_label_hint_dark(entry_count_label)

	UiStylesClass.apply_button_secondary(close_btn)
	UiStylesClass.apply_button_secondary(replay_toggle_button)
	_sync_replay_toggle_button_state()

	if not visibility_changed.is_connected(_on_visibility_changed):
		visibility_changed.connect(_on_visibility_changed)

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
		_request_scroll_to_bottom()
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
		_request_scroll_to_bottom()
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
	_blank_display_warned = false
	_entry_id_counter = 0
	_fold_details_enabled = false
	_expanded_action_groups.clear()
	if fold_details_check != null:
		fold_details_check.button_pressed = _fold_details_enabled

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
	_request_scroll_to_bottom()
	_update_entry_count()

func load_step_timeline(timeline: Dictionary, entries: Array[Dictionary], reset_extra_entries: bool = false) -> void:
	# Unified timeline view (M4.3): structure comes from steps, contents come from formatted entries.
	_step_timeline = timeline.duplicate(true) if (timeline is Dictionary) else {}
	_timeline_entries.clear()
	_blank_display_warned = false
	if entries is Array:
		for e in entries:
			if e is Dictionary:
				var d: Dictionary = Dictionary(e).duplicate(true)
				d["id"] = _entry_id_counter
				_entry_id_counter += 1
				_timeline_entries.append(d)

	if reset_extra_entries:
		_extra_entries.clear()

	_prune_expanded_action_groups()
	if fold_details_check != null:
		fold_details_check.button_pressed = _fold_details_enabled

	_rebuild_entries_all()
	_rebuild_display()
	_apply_timeline_state_to_items(true)
	_request_scroll_to_bottom()
	_update_entry_count()

func set_expand_enabled(_enabled: bool) -> void:
	# 保留接口兼容 FullLogWindow，当前日志面板已移除“全屏”按钮。
	pass

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
	var prefix := "玩家%d" % (player_id + 1)
	if Globals != null:
		if Globals.has_method("get_player_name_compact"):
			var s := str(Globals.get_player_name_compact(player_id)).strip_edges()
			if not s.is_empty():
				prefix = s
		elif Globals.has_method("get_player_name"):
			var s2 := str(Globals.get_player_name(player_id)).strip_edges()
			if not s2.is_empty():
				prefix = s2

	var d: Dictionary = details if (details is Dictionary) else {}
	if not d.has("player_id"):
		d = d.duplicate(true)
		d["player_id"] = player_id

	var full_message := "%s: %s" % [prefix, message]
	return add_log(LogType.PLAYER, full_message, d)

func add_event_log(message: String, details: Dictionary = {}) -> int:
	return add_log(LogType.GAME_EVENT, message, details)

func add_debug_log(message: String, details: Dictionary = {}) -> int:
	return add_log(LogType.DEBUG, message, details)

func clear_logs() -> void:
	_step_timeline.clear()
	_timeline_entries.clear()
	_extra_entries.clear()
	_entries_all.clear()
	_blank_display_warned = false
	_fold_details_enabled = false
	_expanded_action_groups.clear()
	if fold_details_check != null:
		fold_details_check.button_pressed = _fold_details_enabled
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

func ensure_display_ready() -> void:
	if not is_inside_tree():
		return
	if log_container == null or not is_instance_valid(log_container):
		return

	# 没有日志数据：不强行塞占位符，保持空面板（但仍显示 EntryCountLabel）。
	var has_data := (not _entries_all.is_empty()) or _is_step_timeline_loaded()
	if not has_data:
		return

	# UI 已有子节点：无需重复 rebuild。
	if log_container.get_child_count() > 0:
		_blank_display_warned = false
		return

	_rebuild_display()
	_apply_timeline_state_to_items()
	_request_scroll_to_bottom()
	_update_entry_count()

	# 若数据存在但仍构建为空：打一次 warning（便于用户反馈时定位）。
	if log_container.get_child_count() <= 0 and not _entries_all.is_empty() and not _blank_display_warned:
		_blank_display_warned = true
		var steps_val = _step_timeline.get("steps", [])
		var steps_count := int(steps_val.size()) if (steps_val is Array) else 0
		var events_val = _step_timeline.get("events", [])
		var events_count := int(events_val.size()) if (events_val is Array) else 0
		GameLog.warn(
			"GameLogPanel",
			"日志面板构建为空（可能是初始化/布局时序问题）：entries=%d steps=%d events=%d visible_in_tree=%s" % [
				_entries_all.size(),
				steps_count,
				events_count,
				str(is_visible_in_tree()),
			]
		)

func _on_visibility_changed() -> void:
	if not is_visible_in_tree():
		return
	# 延后一帧：避免 dock/reparent 后 Container 尚未完成 layout 导致的“短暂空白”。
	call_deferred("ensure_display_ready")

func _is_step_timeline_loaded() -> bool:
	if _step_timeline == null or _step_timeline.is_empty():
		return false
	var steps_val = _step_timeline.get("steps", null)
	return (steps_val is Array)

func _is_action_group_expanded(step_index: int) -> bool:
	if not _fold_details_enabled:
		return true
	return bool(_expanded_action_groups.get(int(step_index), false))

func _prune_expanded_action_groups() -> void:
	if _expanded_action_groups == null or _expanded_action_groups.is_empty():
		return

	var max_step := int(_timeline_head_index)
	var steps_val = _step_timeline.get("steps", null)
	if steps_val is Array:
		max_step = (steps_val as Array).size() - 1

	for k in _expanded_action_groups.keys():
		if not (k is int or k is float):
			_expanded_action_groups.erase(k)
			continue
		var idx := int(k)
		if idx < -1 or idx > max_step:
			_expanded_action_groups.erase(k)

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

	var item = GameLogItemClass.new()
	item.entry_data = entry
	item.log_type = entry.type
	item.set_meta("log_entry_id", int(entry.get("id", -1)))
	item.entry_clicked.connect(_on_entry_clicked)
	item.entry_double_clicked.connect(_on_entry_double_clicked)
	_connect_item_hover_signals(item)
	log_container.add_child(item)
	_log_items.append(item)
	item.apply_timeline_state(_timeline_cursor_index, _timeline_head_index)

	_request_scroll_to_bottom()

func _request_scroll_to_bottom() -> void:
	if not _auto_scroll:
		return
	# 时间旅行/回放等“光标不在 head”的情况下，避免新日志把视角强行拉回底部。
	if _timeline_cursor_index < _timeline_head_index:
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
	# 某些布局/重建时序下，ScrollBar 的 max_value 会在下一帧才更新；这里补一次确保落到底部。
	call_deferred("_apply_scroll_to_bottom_final")

func _apply_scroll_to_bottom_final() -> void:
	if not _auto_scroll:
		return
	if _timeline_cursor_index < _timeline_head_index:
		return
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

	var items = GameLogUnifiedTimelineBuilderClass.build(
		log_container,
		_step_timeline,
		_entries_all,
		_show_phase_events,
		_fold_details_enabled,
		Callable(self, "_is_action_group_expanded"),
		_timeline_cursor_index,
		_timeline_head_index,
		Callable(self, "_on_timeline_header_clicked"),
		Callable(self, "_on_entry_clicked"),
		Callable(self, "_on_entry_double_clicked"),
		Callable(self, "_on_action_group_fold_toggled"),
		_get_initial_round_number(),
		_get_initial_phase_segment()
	)
	_log_items = items
	for item in _log_items:
		if item is Control:
			_connect_item_hover_signals(item)

func _on_timeline_header_clicked(timeline_index: int) -> void:
	timeline_seek_requested.emit(int(timeline_index))

func _on_action_group_fold_toggled(step_index: int, expanded: bool) -> void:
	if not _fold_details_enabled:
		return
	var idx := int(step_index)
	if idx < -1:
		return
	if expanded:
		_expanded_action_groups[idx] = true
	else:
		if _expanded_action_groups.has(idx):
			_expanded_action_groups.erase(idx)

	_rebuild_display()
	_apply_timeline_state_to_items()
	_update_entry_count()

func _update_entry_count() -> void:
	if entry_count_label == null:
		return

	var total := _entries_all.size()
	var visible := total
	if _is_step_timeline_loaded():
		visible = GameLogUnifiedTimelineBuilderClass.compute_visible_entry_count(
			_step_timeline,
			_entries_all,
			_show_phase_events,
			Callable(self, "_is_action_group_expanded")
		)
	entry_count_label.text = "显示 %d / %d" % [visible, total]

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

func _connect_item_hover_signals(item: Control) -> void:
	if item == null or not is_instance_valid(item):
		return

	var cb_enter := Callable(self, "_on_item_mouse_entered").bind(item)
	if not item.mouse_entered.is_connected(cb_enter):
		item.mouse_entered.connect(cb_enter)
	var cb_exit := Callable(self, "_on_item_mouse_exited").bind(item)
	if not item.mouse_exited.is_connected(cb_exit):
		item.mouse_exited.connect(cb_exit)

func _on_item_mouse_entered(item: Control) -> void:
	var entry_id := _get_entry_id_from_item(item)
	if entry_id < 0:
		return
	log_entry_hovered.emit(entry_id, true)

func _on_item_mouse_exited(item: Control) -> void:
	var entry_id := _get_entry_id_from_item(item)
	if entry_id < 0:
		return
	log_entry_hovered.emit(entry_id, false)

func _get_entry_id_from_item(item: Control) -> int:
	if item == null or not is_instance_valid(item):
		return -1
	if item.has_meta("log_entry_id"):
		var v = item.get_meta("log_entry_id")
		if v is int:
			return int(v)
		if v is float:
			var f: float = float(v)
			if f == floor(f):
				return int(f)
	return -1

func _on_show_phase_events_toggled(toggled: bool) -> void:
	_show_phase_events = bool(toggled)
	_rebuild_display()
	_apply_timeline_state_to_items()
	_update_entry_count()

func _on_fold_details_toggled(toggled: bool) -> void:
	set_fold_details_enabled(bool(toggled), false)

func set_fold_details_enabled(enabled: bool, update_checkbox: bool = true) -> void:
	var en := bool(enabled)
	if en == _fold_details_enabled:
		if update_checkbox and fold_details_check != null:
			fold_details_check.button_pressed = _fold_details_enabled
		return

	_fold_details_enabled = en
	_expanded_action_groups.clear()

	# 默认只展开当前 cursor 的动作组，避免一次性展开导致列表过长。
	if _fold_details_enabled:
		var idx := int(_timeline_cursor_index)
		if idx < -1:
			idx = -1
		if _timeline_head_index >= -1:
			idx = clampi(idx, -1, int(_timeline_head_index))
		_expanded_action_groups[idx] = true

	_prune_expanded_action_groups()

	if update_checkbox and fold_details_check != null:
		fold_details_check.button_pressed = _fold_details_enabled

	_rebuild_display()
	_apply_timeline_state_to_items()
	_update_entry_count()

func _on_auto_scroll_toggled(toggled: bool) -> void:
	_auto_scroll = toggled

func set_replay_toggle_active(active: bool) -> void:
	if replay_toggle_button == null:
		return
	var v := bool(active)
	if replay_toggle_button.button_pressed != v:
		replay_toggle_button.button_pressed = v
	_sync_replay_toggle_button_state()

func set_replay_toggle_availability(
	available: bool,
	inactive_text: String = "进入回放",
	disabled_reason: String = ""
) -> void:
	_replay_toggle_available = bool(available)
	var next_inactive_text := str(inactive_text).strip_edges()
	if next_inactive_text.is_empty():
		next_inactive_text = "进入回放"
	_replay_toggle_inactive_text = next_inactive_text
	_replay_toggle_disabled_reason = str(disabled_reason).strip_edges()
	_sync_replay_toggle_button_state()

func _on_replay_toggle_toggled(toggled: bool) -> void:
	_sync_replay_toggle_button_state()
	replay_toggle_changed.emit(bool(toggled))

func _on_close_pressed() -> void:
	close_requested.emit()

func _sync_replay_toggle_button_state() -> void:
	if replay_toggle_button == null:
		return
	var pressed := bool(replay_toggle_button.button_pressed)
	var should_disable := (not _replay_toggle_available) and (not pressed)
	replay_toggle_button.disabled = should_disable
	if should_disable and not _replay_toggle_disabled_reason.is_empty():
		replay_toggle_button.tooltip_text = "不可用：%s" % _replay_toggle_disabled_reason
	else:
		replay_toggle_button.tooltip_text = ""
	replay_toggle_button.text = "退出回放" if pressed else (
		_replay_toggle_inactive_text if not _replay_toggle_available else "进入回放"
	)

func _on_entry_clicked(entry_id: int) -> void:
	log_entry_clicked.emit(entry_id)

func _on_entry_double_clicked(entry_id: int) -> void:
	_open_entry_details(entry_id)

func get_entry_by_id(entry_id: int) -> Dictionary:
	var e := _find_entry_by_id(entry_id)
	return e.duplicate(true) if not e.is_empty() else {}

func get_entry_command_index(entry_id: int) -> int:
	var e := _find_entry_by_id(entry_id)
	return GameLogEntryUtilsClass.get_entry_command_index(e) if not e.is_empty() else -999

func get_entry_timeline_index(entry_id: int) -> int:
	var e := _find_entry_by_id(entry_id)
	return GameLogEntryUtilsClass.get_entry_timeline_index(e) if not e.is_empty() else -999

func _open_entry_details(entry_id: int) -> void:
	if OS.has_feature("headless"):
		return
	var entry := _find_entry_by_id(entry_id)
	if entry.is_empty():
		return

	if _details_controller == null:
		_details_controller = GameLogDetailsWindowControllerClass.new()
	var type_name: String = LOG_TYPE_NAMES.get(int(entry.get("type", 0)), "?")
	_details_controller.open(self, entry, type_name)

func _find_entry_by_id(entry_id: int) -> Dictionary:
	for e_val in _entries_all:
		if not (e_val is Dictionary):
			continue
		var e: Dictionary = e_val
		if int(e.get("id", -1)) == entry_id:
			return e
	return {}
