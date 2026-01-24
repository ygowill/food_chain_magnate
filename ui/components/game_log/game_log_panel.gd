# 游戏日志面板组件
# 显示游戏事件历史记录
class_name GameLogPanel
extends Control

signal close_requested()
signal log_entry_clicked(entry_id: int)
signal timeline_seek_requested(timeline_index: int)
signal log_added(entry: Dictionary)

@onready var title_label: Label = $MarginContainer/VBoxContainer/TitleRow/TopRow/TitleLabel
@onready var player_filter: OptionButton = $MarginContainer/VBoxContainer/TitleRow/FilterRow/PlayerFilter
@onready var search_input: LineEdit = $MarginContainer/VBoxContainer/TitleRow/FilterRow/SearchInput
@onready var filter_btn: MenuButton = $MarginContainer/VBoxContainer/TitleRow/FilterRow/FilterButton
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

const PLAYER_FILTER_ALL_ITEM_ID := 9999

var _entries_all: Array[Dictionary] = []  # [{id, type, message, timestamp, details, command_index?}]
var _entry_id_counter: int = 0
var _log_items: Array[Control] = [] # LogItem / PhaseHeaderItem / StepHeaderItem
var _filter_types: Array[LogType] = [LogType.SYSTEM, LogType.PLAYER, LogType.GAME_EVENT]
var _filter_player_id: int = -1
var _filter_keyword: String = ""
var _auto_scroll: bool = true
var _scroll_to_bottom_requested: bool = false
var _max_entries: int = 0 # 0 表示不截断（完整时间线需要保留未来日志）
var _player_count: int = 0

# 时间线（回放/查看历史）预留：在 M1 引入“完整日志”前仅存储指针，不改变渲染。
var _timeline_head_index: int = -1
var _timeline_cursor_index: int = -1

# 分组折叠（M4.1）：按 step_index（或 command_index）打包展示
var _collapsed_step_groups: Dictionary = {} # timeline_index -> bool

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

	if player_filter != null:
		player_filter.item_selected.connect(_on_player_filter_selected)
		set_player_count(Globals.player_count)

	if search_input != null:
		search_input.text_changed.connect(_on_search_text_changed)

	_setup_filter_menu()

func _setup_filter_menu() -> void:
	if filter_btn == null:
		return

	var popup := filter_btn.get_popup()
	popup.clear()

	for log_type in LOG_TYPE_NAMES.keys():
		var type_name: String = LOG_TYPE_NAMES[log_type]
		popup.add_check_item(type_name, log_type)
		popup.set_item_checked(popup.item_count - 1, _filter_types.has(log_type))

	popup.id_pressed.connect(_on_filter_item_pressed)

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

	_entries_all.append(entry)
	log_added.emit(entry)

	# 限制最大条目数
	_enforce_max_entries()

	# 过滤通过则显示
	if _entry_passes_filters(entry):
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
	_entries_all.append(entry.duplicate(true))
	_enforce_max_entries()

	if _entry_passes_filters(entry):
		_add_log_item(entry)
	_update_entry_count()

func get_entries() -> Array[Dictionary]:
	return _entries_all.duplicate(true)

func load_entries(entries: Array[Dictionary]) -> void:
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

	# M4.1：若当前 cursor 落在被折叠的 Working step 中，自动展开以便高亮可见。
	if _collapsed_step_groups.has(_timeline_cursor_index) and bool(_collapsed_step_groups.get(_timeline_cursor_index, false)):
		_collapsed_step_groups[_timeline_cursor_index] = false
		_rebuild_display()
		_apply_timeline_state_to_items(should_scroll)
		return

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
	if player_filter == null:
		return

	var keep := _filter_player_id
	player_filter.clear()
	player_filter.add_item("全部", PLAYER_FILTER_ALL_ITEM_ID)
	for i in range(_player_count):
		player_filter.add_item("玩家%d" % (i + 1), i)

	var select_index := 0
	for idx in range(player_filter.get_item_count()):
		var item_id := int(player_filter.get_item_id(idx))
		if keep < 0 and item_id == PLAYER_FILTER_ALL_ITEM_ID:
			select_index = idx
			break
		if keep >= 0 and item_id == keep:
			select_index = idx
			break
	player_filter.select(select_index)

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

	var visible_entries: Array[Dictionary] = []
	for entry_val in _entries_all:
		if not (entry_val is Dictionary):
			continue
		var entry: Dictionary = entry_val
		if _entry_passes_filters(entry):
			visible_entries.append(entry)

	if _should_use_grouped_view(visible_entries):
		_build_grouped_display(visible_entries)
	else:
		for entry in visible_entries:
			_add_log_item(entry)

	_apply_timeline_state_to_items()

func _should_use_grouped_view(visible_entries: Array[Dictionary]) -> bool:
	# M4.1：仅在“完整时间线/回放”条目具备 phase_segment + timeline_index 时启用分组视图；
	# 对局实时追加日志保持旧的扁平列表（避免影响现有交互与性能）。
	if visible_entries == null or visible_entries.is_empty():
		return false

	var has_phase_segment := false
	var has_timeline_index := false
	for e in visible_entries:
		if not (e is Dictionary):
			continue
		var phase_seg := str(e.get("phase_segment", "")).strip_edges()
		if not phase_seg.is_empty():
			has_phase_segment = true
		if _get_entry_timeline_index(e) != -999:
			has_timeline_index = true
		if has_phase_segment and has_timeline_index:
			return true
	return false

func _build_grouped_display(visible_entries: Array[Dictionary]) -> void:
	# 结构：PhaseHeader -> StepHeader -> LogItems（可折叠）
	var phase_order: Array[String] = []
	var phase_buckets: Dictionary = {} # phase_segment -> {order:Array[int], entries_by_step:Dictionary}

	for e in visible_entries:
		var phase_seg := str(e.get("phase_segment", "")).strip_edges()
		if phase_seg.is_empty():
			phase_seg = "?"

		if not phase_buckets.has(phase_seg):
			phase_order.append(phase_seg)
			phase_buckets[phase_seg] = {
				"order": [],
				"entries_by_step": {},
			}

		var idx := _get_entry_timeline_index(e)
		var bucket: Dictionary = phase_buckets[phase_seg]
		var order: Array = bucket.get("order", [])
		var by_step: Dictionary = bucket.get("entries_by_step", {})
		if not by_step.has(idx):
			by_step[idx] = []
			order.append(idx)
		(by_step[idx] as Array).append(e)

		bucket["order"] = order
		bucket["entries_by_step"] = by_step
		phase_buckets[phase_seg] = bucket

	for phase_seg in phase_order:
		var bucket: Dictionary = phase_buckets.get(phase_seg, {})
		var order: Array = bucket.get("order", [])
		var by_step: Dictionary = bucket.get("entries_by_step", {})

		var start_step := -1
		var end_step := -1
		for idx_val in order:
			if not (idx_val is int):
				continue
			var idx: int = int(idx_val)
			if idx < 0:
				continue
			if start_step < 0 or idx < start_step:
				start_step = idx
			if end_step < 0 or idx > end_step:
				end_step = idx

		_add_phase_header_item(phase_seg, start_step, end_step)

		for idx_val in order:
			var idx2 := int(idx_val)
			var entries_val = by_step.get(idx2, [])
			var entries: Array = entries_val if (entries_val is Array) else []
			if entries.is_empty():
				continue

			# 计算动作摘要：优先选择第一条玩家日志，否则用第一条事件日志。
			var summary := ""
			for ev_entry_val in entries:
				if not (ev_entry_val is Dictionary):
					continue
				var ev_entry: Dictionary = ev_entry_val
				if int(ev_entry.get("type", -1)) == LogType.PLAYER:
					summary = str(ev_entry.get("message", "")).strip_edges()
					break
			if summary.is_empty():
				summary = str(Dictionary(entries[0]).get("message", "")).strip_edges()

			var cmd_index := int(Dictionary(entries[0]).get("command_index", -1))

			var collapsed := false
			if phase_seg == "Working":
				# Working 默认折叠（满足“尽可能打包”）；当前 cursor 所在 step 自动展开以便高亮可见。
				var default_collapsed := true
				collapsed = bool(_collapsed_step_groups.get(idx2, default_collapsed))
				if idx2 == _timeline_cursor_index:
					collapsed = false
				_collapsed_step_groups[idx2] = collapsed

			_add_step_header_item(idx2, cmd_index, summary, entries.size(), collapsed)

			if collapsed:
				continue
			for child_entry_val in entries:
				if not (child_entry_val is Dictionary):
					continue
				_add_log_item(Dictionary(child_entry_val))

func _add_phase_header_item(phase_segment: String, start_step: int, end_step: int) -> void:
	if log_container == null:
		return
	var item := PhaseHeaderItem.new()
	item.phase_segment = str(phase_segment)
	item.start_step_index = int(start_step)
	item.end_step_index = int(end_step)
	item.clicked.connect(_on_phase_header_clicked)
	log_container.add_child(item)
	_log_items.append(item)
	item.apply_timeline_state(_timeline_cursor_index, _timeline_head_index)

func _add_step_header_item(step_index: int, command_index: int, summary: String, count: int, collapsed: bool) -> void:
	if log_container == null:
		return
	var item := StepHeaderItem.new()
	item.step_index = int(step_index)
	item.command_index = int(command_index)
	item.summary = str(summary)
	item.event_count = int(count)
	item.collapsed = bool(collapsed)
	item.clicked.connect(_on_step_header_clicked)
	log_container.add_child(item)
	_log_items.append(item)
	item.apply_timeline_state(_timeline_cursor_index, _timeline_head_index)

func _on_phase_header_clicked(timeline_index: int) -> void:
	timeline_seek_requested.emit(int(timeline_index))

func _on_step_header_clicked(timeline_index: int) -> void:
	var idx := int(timeline_index)
	if idx < -1:
		return

	# Working：支持折叠；其它阶段：仅 seek。
	if _collapsed_step_groups.has(idx):
		var was_collapsed := bool(_collapsed_step_groups.get(idx, false))
		if was_collapsed:
			_collapsed_step_groups[idx] = false
			timeline_seek_requested.emit(idx)
		else:
			_collapsed_step_groups[idx] = true
		_rebuild_display()
		return

	timeline_seek_requested.emit(idx)

func _update_entry_count() -> void:
	if entry_count_label != null:
		var visible_count := 0
		for entry in _entries_all:
			if _entry_passes_filters(entry):
				visible_count += 1
		entry_count_label.text = "显示 %d / %d" % [visible_count, _entries_all.size()]

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

func _on_filter_item_pressed(id: int) -> void:
	var log_type: LogType = id as LogType
	var popup := filter_btn.get_popup()
	var idx := popup.get_item_index(id)
	var is_checked := popup.is_item_checked(idx)

	popup.set_item_checked(idx, not is_checked)

	if is_checked:
		_filter_types.erase(log_type)
	else:
		if not _filter_types.has(log_type):
			_filter_types.append(log_type)

	_rebuild_display()
	_update_entry_count()

func _on_player_filter_selected(index: int) -> void:
	if player_filter == null:
		return
	var selected_id := int(player_filter.get_selected_id())
	_filter_player_id = -1 if selected_id == PLAYER_FILTER_ALL_ITEM_ID else selected_id
	_rebuild_display()
	_update_entry_count()

func _on_search_text_changed(text: String) -> void:
	_filter_keyword = str(text).strip_edges()
	_rebuild_display()
	_update_entry_count()

func _entry_passes_filters(entry: Dictionary) -> bool:
	if entry == null or entry.is_empty():
		return false
	if not _filter_types.has(entry.type):
		return false

	if _filter_player_id >= 0:
		var details = entry.get("details", {})
		if not (details is Dictionary):
			return false
		var pid_val = (details as Dictionary).get("player_id", null)
		if pid_val is int:
			if int(pid_val) != _filter_player_id:
				return false
		elif pid_val is float:
			var f: float = float(pid_val)
			if f != floor(f) or int(f) != _filter_player_id:
				return false
		else:
			return false

	if not _filter_keyword.is_empty():
		var msg := str(entry.get("message", ""))
		if not msg.to_lower().contains(_filter_keyword.to_lower()):
			return false

	return true

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

# === 分组头（M4.1）===
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
		var range := ""
		if start_step_index >= 0 and end_step_index >= 0:
			if start_step_index == end_step_index:
				range = "（step %d）" % start_step_index
			else:
				range = "（step %d..%d）" % [start_step_index, end_step_index]
		_label.text = "阶段: %s%s" % [phase, range]

	func get_timeline_index() -> int:
		return int(start_step_index)

	func apply_timeline_state(cursor_index: int, head_index: int) -> void:
		var cursor := int(cursor_index)
		var head := int(head_index)
		_timeline_is_future = (cursor < head and start_step_index >= 0 and start_step_index > cursor)
		if start_step_index >= 0 and end_step_index >= start_step_index:
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

class StepHeaderItem extends PanelContainer:
	signal clicked(timeline_index: int)

	var step_index: int = -1
	var command_index: int = -1
	var summary: String = ""
	var event_count: int = 0
	var collapsed: bool = false

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

		_label = Label.new()
		_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_label.add_theme_font_size_override("font_size", maxi(9, int(round(11.0 * scale))))
		_label.add_theme_color_override("font_color", Color(0.75, 0.75, 0.78, 1))
		hbox.add_child(_label)

		_update_text()
		_apply_timeline_visuals()

	func _update_text() -> void:
		var arrow := ">" if collapsed else "v"
		var si := int(step_index)
		var ci := int(command_index)
		var sum := str(summary).strip_edges()
		if sum.is_empty():
			sum = "(无摘要)"
		var tail := "（%d 条）" % int(event_count) if int(event_count) > 1 else ""
		_label.text = "%s step %d（cmd %d） %s%s" % [arrow, si, ci, sum, tail]

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
