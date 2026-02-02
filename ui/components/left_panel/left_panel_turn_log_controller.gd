# LeftPanel：本回合日志小节（绑定 GameLogPanel + 过滤/截断）
extends RefCounted

var _panel = null

func setup(panel) -> void:
	_panel = panel
	_bind_ui_signals()

func bind_log_panel(panel: Node) -> void:
	if _panel == null or not is_instance_valid(_panel):
		return
	if panel == null or not is_instance_valid(panel):
		return
	_detach_log_panel_signals()
	_panel._attached_log_panel = panel
	_attach_log_panel_signals()
	refresh()

func refresh() -> void:
	if _panel == null or not is_instance_valid(_panel):
		return
	_refresh_turn_log()

func _bind_ui_signals() -> void:
	if _panel == null or not is_instance_valid(_panel):
		return
	if is_instance_valid(_panel.turn_log_toggle_button):
		if not _panel.turn_log_toggle_button.toggled.is_connected(_on_turn_log_toggled):
			_panel.turn_log_toggle_button.toggled.connect(_on_turn_log_toggled)
	if is_instance_valid(_panel.turn_log_to_logs_button):
		if not _panel.turn_log_to_logs_button.pressed.is_connected(_on_turn_log_to_logs_pressed):
			_panel.turn_log_to_logs_button.pressed.connect(_on_turn_log_to_logs_pressed)

func _attach_log_panel_signals() -> void:
	if _panel._attached_log_panel == null or not is_instance_valid(_panel._attached_log_panel):
		return
	if _panel._attached_log_panel.has_signal("log_added"):
		var sig = _panel._attached_log_panel.log_added
		if sig is Signal:
			if not sig.is_connected(_on_log_added):
				sig.connect(_on_log_added)

func _detach_log_panel_signals() -> void:
	if _panel == null or not is_instance_valid(_panel):
		return
	if _panel._attached_log_panel == null or not is_instance_valid(_panel._attached_log_panel):
		_panel._attached_log_panel = null
		return
	if _panel._attached_log_panel.has_signal("log_added"):
		var sig = _panel._attached_log_panel.log_added
		if sig is Signal:
			if sig.is_connected(_on_log_added):
				sig.disconnect(_on_log_added)
	_panel._attached_log_panel = null

func _on_log_added(_entry: Dictionary) -> void:
	refresh()

func _refresh_turn_log() -> void:
	if not is_instance_valid(_panel.turn_log_lines):
		return

	for c in _panel.turn_log_lines.get_children():
		if is_instance_valid(c):
			c.queue_free()

	if _panel._attached_log_panel == null or not is_instance_valid(_panel._attached_log_panel):
		_add_turn_log_line("（未绑定日志面板）", Color(0.6, 0.6, 0.6, 0.9))
		return
	if not _panel._attached_log_panel.has_method("get_entries"):
		_add_turn_log_line("（日志面板不支持 get_entries）", Color(0.6, 0.6, 0.6, 0.9))
		return

	var view_id: int = _panel._resolve_view_player_id()
	var entries_val = _panel._attached_log_panel.call("get_entries")
	if not (entries_val is Array):
		_add_turn_log_line("（日志数据异常）", Color(0.6, 0.6, 0.6, 0.9))
		return
	var entries: Array = entries_val

	var start_idx := 0
	var round_number := int(_panel._game_state.round_number) if _panel._game_state != null else -1
	var round_start_idx := _find_round_start_entry_index(entries, round_number)
	if round_start_idx >= 0:
		start_idx = round_start_idx + 1

	var matched: Array[Dictionary] = []
	for i in range(start_idx, entries.size()):
		var e_val = entries[i]
		if not (e_val is Dictionary):
			continue
		var e: Dictionary = e_val
		if _entry_matches_view_player(e, view_id):
			matched.append(e)

	var n := matched.size()
	var max_lines := 6
	var start := maxi(0, n - max_lines)
	if n <= 0:
		_add_turn_log_line("（暂无该玩家日志）", Color(0.6, 0.6, 0.6, 0.9))
		return
	for i in range(start, n):
		var e: Dictionary = matched[i]
		var msg := str(e.get("message", ""))
		msg = msg.strip_edges()
		if msg.is_empty():
			continue
		_add_turn_log_line(msg, Color(0.85, 0.85, 0.9, 1))

func _find_round_start_entry_index(entries: Array, round_number: int) -> int:
	if round_number < 0:
		return -1
	if entries == null or entries.is_empty():
		return -1

	for i in range(entries.size() - 1, -1, -1):
		var e_val = entries[i]
		if not (e_val is Dictionary):
			continue
		var e: Dictionary = e_val

		var t_val = e.get("type", null)
		var t := int(t_val) if (t_val is int or t_val is float) else -1
		if t != 1: # GameLogPanel.LogType.PHASE
			continue

		var msg := str(e.get("message", "")).strip_edges()
		if not msg.begins_with("回合开始"):
			continue

		var details_val = e.get("details", null)
		if not (details_val is Dictionary):
			continue
		var details: Dictionary = details_val
		var r_val = details.get("round", null)
		var r := -1
		if r_val is int:
			r = int(r_val)
		elif r_val is float:
			var f: float = float(r_val)
			if f == floor(f):
				r = int(f)
		if r == round_number:
			return i

	return -1

func _entry_matches_view_player(entry: Dictionary, view_id: int) -> bool:
	if entry == null or entry.is_empty():
		return false

	var details_val = entry.get("details", null)
	if details_val is Dictionary:
		var details: Dictionary = details_val
		var pid_val = details.get("player_id", null)
		if pid_val is int:
			return int(pid_val) == view_id
		if pid_val is float:
			var f: float = float(pid_val)
			if f == floor(f):
				return int(f) == view_id

	var t_val = entry.get("type", null)
	var t := int(t_val) if (t_val is int or t_val is float) else -1
	if t == 2: # GameLogPanel.LogType.PLAYER
		var msg := str(entry.get("message", ""))
		return msg.begins_with("玩家%d:" % (view_id + 1))

	return false

func _add_turn_log_line(text: String, color: Color) -> void:
	if not is_instance_valid(_panel.turn_log_lines):
		return
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", color)
	_panel.turn_log_lines.add_child(l)

func _on_turn_log_toggled(pressed: bool) -> void:
	if is_instance_valid(_panel.turn_log_lines):
		_panel.turn_log_lines.visible = pressed
	if is_instance_valid(_panel.turn_log_toggle_button):
		_panel.turn_log_toggle_button.text = ("▼ 本回合日志" if pressed else "▶ 本回合日志")

func _on_turn_log_to_logs_pressed() -> void:
	_panel.logs_requested.emit()
	if is_instance_valid(_panel.turn_log_toggle_button) and not _panel.turn_log_toggle_button.button_pressed:
		_panel.turn_log_toggle_button.button_pressed = true
		_on_turn_log_toggled(true)
