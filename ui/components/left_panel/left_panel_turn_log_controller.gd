# LeftPanel：活动流（简化版：最多2条最近日志）
extends RefCounted

var _panel = null

func setup(panel) -> void:
	_panel = panel

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
	_refresh_activity_feed()

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

func _refresh_activity_feed() -> void:
	if not is_instance_valid(_panel.activity_line1) or not is_instance_valid(_panel.activity_line2):
		return

	# 默认显示
	_panel.activity_line1.text = "暂无活动记录"
	_panel.activity_line2.text = ""
	_panel.activity_line2.visible = false

	if _panel._attached_log_panel == null or not is_instance_valid(_panel._attached_log_panel):
		return
	if not _panel._attached_log_panel.has_method("get_entries"):
		return

	var view_id: int = _panel._resolve_view_player_id()
	var entries_val = _panel._attached_log_panel.call("get_entries")
	if not (entries_val is Array):
		return
	var entries: Array = entries_val

	# 找到当前回合起始位置
	var start_idx := 0
	var round_number := int(_panel._game_state.round_number) if _panel._game_state != null else -1
	var round_start_idx := _find_round_start_entry_index(entries, round_number)
	if round_start_idx >= 0:
		start_idx = round_start_idx + 1

	# 筛选当前玩家的日志
	var matched: Array[Dictionary] = []
	for i in range(start_idx, entries.size()):
		var e_val = entries[i]
		if not (e_val is Dictionary):
			continue
		var e: Dictionary = e_val
		if _entry_matches_view_player(e, view_id):
			matched.append(e)

	var n := matched.size()
	if n <= 0:
		_panel.activity_line1.text = "（本回合暂无该玩家日志）"
		return

	# 显示最近2条
	var last1 := matched[n - 1]
	var msg1 := _format_log_message(last1)
	_panel.activity_line1.text = "- " + msg1

	if n >= 2:
		var last2 := matched[n - 2]
		var msg2 := _format_log_message(last2)
		_panel.activity_line2.text = "- " + msg2
		_panel.activity_line2.visible = true
	else:
		_panel.activity_line2.text = ""
		_panel.activity_line2.visible = false

func _format_log_message(entry: Dictionary) -> String:
	var msg := str(entry.get("message", "")).strip_edges()
	# 限制长度
	if msg.length() > 40:
		msg = msg.substr(0, 37) + "..."
	return msg

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
