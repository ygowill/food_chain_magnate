# 全屏日志窗口（P2）
# 复用 GameLogPanel，并与来源 GameLogPanel 实时同步新增日志。
class_name FullLogWindow
extends Window

@onready var close_btn: Button = $MarginContainer/VBoxContainer/TopRow/CloseButton
@onready var log_panel = $MarginContainer/VBoxContainer/LogPanel

var _source = null

func _ready() -> void:
	if close_btn != null:
		close_btn.pressed.connect(_on_close_requested)
	close_requested.connect(_on_close_requested)

	if is_instance_valid(log_panel) and log_panel.has_method("set_expand_enabled"):
		log_panel.set_expand_enabled(false)

func open_for(source) -> void:
	_detach_source()
	_source = source

	if is_instance_valid(log_panel) and log_panel.has_method("set_player_count"):
		log_panel.set_player_count(Globals.player_count)

	if is_instance_valid(_source):
		if is_instance_valid(log_panel) and log_panel.has_method("load_entries") and _source.has_method("get_entries"):
			log_panel.load_entries(_source.get_entries())

		if _source.has_signal("log_added"):
			if not _source.log_added.is_connected(_on_source_log_added):
				_source.log_added.connect(_on_source_log_added)

	popup_centered()

func _on_source_log_added(entry: Dictionary) -> void:
	if not is_instance_valid(log_panel) or not log_panel.has_method("append_entry"):
		return
	log_panel.append_entry(entry)

func _on_close_requested() -> void:
	_detach_source()
	hide()
	queue_free()

func _detach_source() -> void:
	if _source != null and is_instance_valid(_source):
		if _source.has_signal("log_added") and _source.log_added.is_connected(_on_source_log_added):
			_source.log_added.disconnect(_on_source_log_added)
	_source = null

