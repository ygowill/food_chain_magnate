# GameLogPanel：详情弹窗控制器
extends RefCounted

const GameLogEntryUtilsClass = preload("res://ui/components/game_log/game_log_entry_utils.gd")

var _details_window: Window = null
var _details_message_label: Label = null
var _details_text: TextEdit = null

func open(host: Node, entry: Dictionary, type_name: String) -> void:
	if OS.has_feature("headless"):
		return
	if entry == null or entry.is_empty():
		return
	_ensure_window(host)
	if _details_window == null or not is_instance_valid(_details_window):
		return

	if _details_message_label != null:
		var ts := str(entry.get("timestamp", "")).strip_edges()
		var msg := str(entry.get("message", "")).strip_edges()
		_details_message_label.text = "[%s] %s\n%s" % [str(type_name), ts, msg]

	if _details_text != null:
		_details_text.text = GameLogEntryUtilsClass.format_details_for_view(entry.get("details", {}))

	if _details_window.has_method("popup_centered"):
		_details_window.popup_centered()
	else:
		_details_window.show()

func _ensure_window(host: Node) -> void:
	if _details_window != null and is_instance_valid(_details_window):
		return
	if host == null or not is_instance_valid(host):
		return
	if host.get_tree() == null or host.get_tree().root == null:
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

	host.get_tree().root.add_child(_details_window)

