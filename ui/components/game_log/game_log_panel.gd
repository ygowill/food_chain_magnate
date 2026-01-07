# 游戏日志面板组件
# 显示游戏事件历史记录
class_name GameLogPanel
extends Control

signal log_entry_clicked(entry_id: int)

@onready var title_label: Label = $MarginContainer/VBoxContainer/TitleRow/TitleLabel
@onready var filter_btn: MenuButton = $MarginContainer/VBoxContainer/TitleRow/FilterButton
@onready var clear_btn: Button = $MarginContainer/VBoxContainer/TitleRow/ClearButton
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

var _entries: Array[Dictionary] = []  # [{id, type, message, timestamp, details}]
var _entry_id_counter: int = 0
var _log_items: Array[LogItem] = []
var _filter_types: Array[LogType] = [LogType.SYSTEM, LogType.PHASE, LogType.PLAYER, LogType.GAME_EVENT]
var _auto_scroll: bool = true
var _max_entries: int = 500

func _ready() -> void:
	if clear_btn != null:
		clear_btn.pressed.connect(_on_clear_pressed)
	if auto_scroll_check != null:
		auto_scroll_check.toggled.connect(_on_auto_scroll_toggled)
		auto_scroll_check.button_pressed = _auto_scroll

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

	_entries.append(entry)

	# 限制最大条目数
	while _entries.size() > _max_entries:
		_entries.pop_front()

	# 如果类型在过滤列表中，添加显示
	if _filter_types.has(log_type):
		_add_log_item(entry)

	_update_entry_count()

	return entry_id

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
	_entries.clear()
	_clear_display()
	_update_entry_count()

func _add_log_item(entry: Dictionary) -> void:
	if log_container == null:
		return

	var item := LogItem.new()
	item.entry_data = entry
	item.log_type = entry.type
	item.entry_clicked.connect(_on_entry_clicked)
	log_container.add_child(item)
	_log_items.append(item)

	if _auto_scroll:
		await get_tree().process_frame
		scroll_container.scroll_vertical = int(scroll_container.get_v_scroll_bar().max_value)

func _clear_display() -> void:
	for item in _log_items:
		if is_instance_valid(item):
			item.queue_free()
	_log_items.clear()

func _rebuild_display() -> void:
	_clear_display()

	for entry in _entries:
		if _filter_types.has(entry.type):
			_add_log_item(entry)

func _update_entry_count() -> void:
	if entry_count_label != null:
		var visible_count := 0
		for entry in _entries:
			if _filter_types.has(entry.type):
				visible_count += 1
		entry_count_label.text = "显示 %d / %d" % [visible_count, _entries.size()]

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

func _on_auto_scroll_toggled(toggled: bool) -> void:
	_auto_scroll = toggled

func _on_clear_pressed() -> void:
	clear_logs()

func _on_entry_clicked(entry_id: int) -> void:
	log_entry_clicked.emit(entry_id)


# === 内部类：日志条目 ===
class LogItem extends PanelContainer:
	signal entry_clicked(entry_id: int)

	var entry_data: Dictionary = {}
	var log_type: int = 0

	var _time_label: Label
	var _type_label: Label
	var _message_label: Label

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
		custom_minimum_size = Vector2(350, 28)
		mouse_filter = Control.MOUSE_FILTER_STOP

		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.12, 0.12, 0.14, 0.6)
		style.set_corner_radius_all(2)
		add_theme_stylebox_override("panel", style)

		var hbox := HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 8)
		add_child(hbox)

		# 时间
		_time_label = Label.new()
		_time_label.custom_minimum_size = Vector2(50, 0)
		_time_label.add_theme_font_size_override("font_size", 10)
		_time_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 1))
		hbox.add_child(_time_label)

		# 类型
		_type_label = Label.new()
		_type_label.custom_minimum_size = Vector2(40, 0)
		_type_label.add_theme_font_size_override("font_size", 11)
		hbox.add_child(_type_label)

		# 消息
		_message_label = Label.new()
		_message_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_message_label.add_theme_font_size_override("font_size", 12)
		_message_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		hbox.add_child(_message_label)

		update_display()

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton:
			if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
				if event.double_click:
					var entry_id: int = int(entry_data.get("id", -1))
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
