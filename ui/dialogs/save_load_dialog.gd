# 存档/回放文件选择对话框
# - 多存档槽：支持 user://savegame.json（快速存档）+ user://saves/*.json（命名槽位）
# - 文件系统选择：FileDialog 选择任意 JSON 存档文件
class_name SaveLoadDialog
extends Window

signal load_selected(path: String)
signal save_completed(path: String)
signal cancelled()

enum DialogMode { LOAD, SAVE, REPLAY }

const SAVES_DIR := "user://saves"
const QUICK_SAVE_PATH := "user://savegame.json"

var _dialog_mode: DialogMode = DialogMode.LOAD
var _engine: GameEngine = null

var _tabs: TabContainer
var _slot_list: ItemList
var _slot_name_edit: LineEdit
var _slot_refresh_btn: Button
var _slot_primary_btn: Button
var _slot_cancel_btn: Button

var _file_path_edit: LineEdit
var _file_browse_btn: Button
var _file_primary_btn: Button
var _file_cancel_btn: Button

var _status_label: Label
var _file_dialog: FileDialog

var _slot_paths: Array[String] = []
var _suppress_slot_selection: bool = false

func _ready() -> void:
	title = "存档管理"
	size = Vector2i(760, 520)
	visible = false

	_build_ui()
	_connect_signals()
	_refresh_slots()
	_update_ui_state()

func open_for_load() -> void:
	_dialog_mode = DialogMode.LOAD
	_engine = null
	title = "载入游戏"
	_refresh_slots()
	_update_ui_state()
	popup_centered()

func open_for_replay() -> void:
	_dialog_mode = DialogMode.REPLAY
	_engine = null
	title = "选择回放文件"
	_refresh_slots()
	_update_ui_state()
	popup_centered()

func open_for_save(engine: GameEngine) -> void:
	_dialog_mode = DialogMode.SAVE
	_engine = engine
	title = "保存游戏"
	_refresh_slots()
	_update_ui_state()
	popup_centered()

func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 10)
	add_child(root)

	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_tabs)

	# === Tab 1: 存档槽 ===
	var slot_tab := VBoxContainer.new()
	slot_tab.add_theme_constant_override("separation", 8)
	_tabs.add_child(slot_tab)
	_tabs.set_tab_title(_tabs.get_tab_count() - 1, "存档槽")

	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 8)
	slot_tab.add_child(name_row)

	var name_label := Label.new()
	name_label.text = "槽位名:"
	name_label.add_theme_font_size_override("font_size", 12)
	name_row.add_child(name_label)

	_slot_name_edit = LineEdit.new()
	_slot_name_edit.placeholder_text = "例如：slot1 / round3 / my_save"
	_slot_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(_slot_name_edit)

	_slot_refresh_btn = Button.new()
	_slot_refresh_btn.text = "刷新"
	_slot_refresh_btn.custom_minimum_size = Vector2(72, 30)
	name_row.add_child(_slot_refresh_btn)

	_slot_list = ItemList.new()
	_slot_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_slot_list.allow_reselect = true
	_slot_list.select_mode = ItemList.SELECT_SINGLE
	slot_tab.add_child(_slot_list)

	var slot_btn_row := HBoxContainer.new()
	slot_btn_row.add_theme_constant_override("separation", 8)
	slot_tab.add_child(slot_btn_row)

	slot_btn_row.add_child(_create_spacer())

	_slot_cancel_btn = Button.new()
	_slot_cancel_btn.text = "取消"
	_slot_cancel_btn.custom_minimum_size = Vector2(90, 34)
	slot_btn_row.add_child(_slot_cancel_btn)

	_slot_primary_btn = Button.new()
	_slot_primary_btn.text = "确定"
	_slot_primary_btn.custom_minimum_size = Vector2(120, 34)
	slot_btn_row.add_child(_slot_primary_btn)

	# === Tab 2: 文件系统 ===
	var file_tab := VBoxContainer.new()
	file_tab.add_theme_constant_override("separation", 10)
	_tabs.add_child(file_tab)
	_tabs.set_tab_title(_tabs.get_tab_count() - 1, "文件")

	var file_row := HBoxContainer.new()
	file_row.add_theme_constant_override("separation", 8)
	file_tab.add_child(file_row)

	var file_label := Label.new()
	file_label.text = "文件:"
	file_label.add_theme_font_size_override("font_size", 12)
	file_row.add_child(file_label)

	_file_path_edit = LineEdit.new()
	_file_path_edit.placeholder_text = "选择一个存档 JSON 文件（可为 user:// 或绝对路径）"
	_file_path_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	file_row.add_child(_file_path_edit)

	_file_browse_btn = Button.new()
	_file_browse_btn.text = "浏览..."
	_file_browse_btn.custom_minimum_size = Vector2(90, 30)
	file_row.add_child(_file_browse_btn)

	var file_btn_row := HBoxContainer.new()
	file_btn_row.add_theme_constant_override("separation", 8)
	file_tab.add_child(file_btn_row)

	file_btn_row.add_child(_create_spacer())

	_file_cancel_btn = Button.new()
	_file_cancel_btn.text = "取消"
	_file_cancel_btn.custom_minimum_size = Vector2(90, 34)
	file_btn_row.add_child(_file_cancel_btn)

	_file_primary_btn = Button.new()
	_file_primary_btn.text = "加载"
	_file_primary_btn.custom_minimum_size = Vector2(120, 34)
	file_btn_row.add_child(_file_primary_btn)

	_status_label = Label.new()
	_status_label.text = ""
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.add_theme_font_size_override("font_size", 12)
	_status_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	root.add_child(_status_label)

	# FileDialog（文件系统选择）
	_file_dialog = FileDialog.new()
	_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_file_dialog.filters = PackedStringArray([
		"*.json;存档文件;application/json"
	])
	add_child(_file_dialog)

func _connect_signals() -> void:
	close_requested.connect(_on_cancel_pressed)

	_slot_refresh_btn.pressed.connect(_on_refresh_pressed)
	_slot_cancel_btn.pressed.connect(_on_cancel_pressed)
	_slot_primary_btn.pressed.connect(_on_primary_pressed)
	_slot_list.item_selected.connect(_on_slot_selected)
	_slot_list.item_activated.connect(_on_slot_activated)

	_file_browse_btn.pressed.connect(_on_browse_pressed)
	_file_cancel_btn.pressed.connect(_on_cancel_pressed)
	_file_primary_btn.pressed.connect(_on_primary_file_pressed)
	_file_dialog.file_selected.connect(_on_file_dialog_selected)

func _create_spacer() -> Control:
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return spacer

func _update_ui_state() -> void:
	var is_save := _dialog_mode == DialogMode.SAVE
	var primary_text := "保存" if is_save else "加载"

	if _slot_primary_btn != null:
		_slot_primary_btn.text = primary_text
	if _file_primary_btn != null:
		_file_primary_btn.text = primary_text

	if _slot_name_edit != null:
		_slot_name_edit.editable = is_save
		if not is_save:
			_slot_name_edit.placeholder_text = "请选择一个存档槽位"

func _refresh_slots() -> void:
	_ensure_saves_dir()
	_slot_paths.clear()

	if _slot_list == null:
		return

	var selected_path := _get_selected_slot_path()
	_slot_list.clear()

	# 0) 快速存档
	if FileAccess.file_exists(QUICK_SAVE_PATH):
		_add_slot_item("快速存档 (savegame.json)", QUICK_SAVE_PATH)
	else:
		_add_slot_item("快速存档 (不存在)", QUICK_SAVE_PATH)

	# 1) user://saves/*.json
	var dir := DirAccess.open(SAVES_DIR)
	if dir != null:
		var files: Array[String] = []
		dir.list_dir_begin()
		var f := dir.get_next()
		while not f.is_empty():
			if not dir.current_is_dir() and str(f).to_lower().ends_with(".json"):
				files.append(str(f))
			f = dir.get_next()
		dir.list_dir_end()

		files.sort()
		for i in range(files.size()):
			var file_name: String = files[i]
			var path := "%s/%s" % [SAVES_DIR, file_name]
			var label := _build_slot_label(file_name, path)
			_add_slot_item(label, path)

	# 选择恢复
	if not selected_path.is_empty():
		_select_slot_path(selected_path)
	elif _slot_list.item_count > 0:
		_slot_list.select(0)
		_on_slot_selected(0)

func _add_slot_item(text: String, path: String) -> void:
	_slot_list.add_item(text)
	_slot_paths.append(path)

func _build_slot_label(file_name: String, path: String) -> String:
	var meta := _read_archive_metadata(path)
	if meta.is_empty():
		return "槽位: %s (损坏/无法读取)" % file_name

	var created_at := str(meta.get("created_at", ""))
	var cmd_count := int(meta.get("command_count", 0))
	var player_count := int(meta.get("player_count", 0))
	var hash := str(meta.get("final_hash", ""))
	if hash.length() > 8:
		hash = hash.substr(0, 8)

	var parts: Array[String] = []
	parts.append("槽位: %s" % file_name)
	if not created_at.is_empty():
		parts.append(created_at)
	if player_count > 0:
		parts.append("玩家:%d" % player_count)
	parts.append("命令:%d" % cmd_count)
	if not hash.is_empty():
		parts.append("hash:%s" % hash)

	return "  |  ".join(parts)

func _read_archive_metadata(path: String) -> Dictionary:
	if path.is_empty():
		return {}
	if not FileAccess.file_exists(path):
		return {}

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var json := file.get_as_text()
	file.close()

	var parsed = JSON.parse_string(json)
	if parsed == null or not (parsed is Dictionary):
		return {}
	var d: Dictionary = parsed

	var cmd_count := 0
	var commands_val = d.get("commands", null)
	if commands_val is Array:
		cmd_count = Array(commands_val).size()

	var player_count := 0
	var init_val = d.get("initial_state", null)
	if init_val is Dictionary:
		var init_state: Dictionary = init_val
		var players_val = init_state.get("players", null)
		if players_val is Array:
			player_count = Array(players_val).size()

	return {
		"created_at": d.get("created_at", ""),
		"final_hash": d.get("final_hash", ""),
		"command_count": cmd_count,
		"player_count": player_count,
	}

func _ensure_saves_dir() -> void:
	var abs_dir := ProjectSettings.globalize_path(SAVES_DIR)
	if DirAccess.dir_exists_absolute(abs_dir):
		return
	DirAccess.make_dir_recursive_absolute(abs_dir)

func _get_selected_slot_path() -> String:
	if _slot_list == null:
		return ""
	var selected := _slot_list.get_selected_items()
	if selected.is_empty():
		return ""
	var idx := int(selected[0])
	if idx < 0 or idx >= _slot_paths.size():
		return ""
	return _slot_paths[idx]

func _select_slot_path(path: String) -> void:
	if path.is_empty() or _slot_list == null:
		return
	for i in range(_slot_paths.size()):
		if _slot_paths[i] == path:
			_suppress_slot_selection = true
			_slot_list.select(i)
			_suppress_slot_selection = false
			_on_slot_selected(i)
			return

func _on_refresh_pressed() -> void:
	_refresh_slots()

func _on_cancel_pressed() -> void:
	hide()
	cancelled.emit()

func _on_primary_pressed() -> void:
	match _dialog_mode:
		DialogMode.SAVE:
			_save_selected()
		DialogMode.LOAD, DialogMode.REPLAY:
			_emit_selected_slot()

func _on_primary_file_pressed() -> void:
	if _dialog_mode == DialogMode.SAVE:
		_set_status("当前仅支持保存到 user:// 存档槽位（文件系统保存后续补齐）")
		return

	var path := str(_file_path_edit.text).strip_edges()
	if path.is_empty():
		_set_status("请选择一个文件")
		return
	if not FileAccess.file_exists(path):
		_set_status("文件不存在: %s" % path)
		return

	hide()
	load_selected.emit(path)

func _on_slot_selected(index: int) -> void:
	if _suppress_slot_selection:
		return
	if index < 0 or index >= _slot_paths.size():
		return

	var path := _slot_paths[index]
	if _dialog_mode == DialogMode.SAVE:
		# 选中槽位时同步名称输入（允许在“快速存档”选中时直接输入新槽位名）
		if path == QUICK_SAVE_PATH:
			_slot_name_edit.text = ""
		else:
			_slot_name_edit.text = path.get_file().trim_suffix(".json")
	else:
		_slot_name_edit.text = ""

	_set_status(path)

func _on_slot_activated(index: int) -> void:
	if _dialog_mode == DialogMode.SAVE:
		return
	_on_slot_selected(index)
	_emit_selected_slot()

func _emit_selected_slot() -> void:
	var path := _get_selected_slot_path()
	if path.is_empty():
		_set_status("请选择一个存档")
		return
	if not FileAccess.file_exists(path):
		_set_status("文件不存在: %s" % path)
		return

	hide()
	load_selected.emit(path)

func _save_selected() -> void:
	if _engine == null:
		_set_status("游戏引擎为空，无法保存")
		return

	var name := str(_slot_name_edit.text).strip_edges()
	var path := ""
	if not name.is_empty():
		name = _sanitize_slot_name(name)
		if name.is_empty():
			_set_status("槽位名无效")
			return
		path = "%s/%s.json" % [SAVES_DIR, name]
	else:
		path = _get_selected_slot_path()
		if path.is_empty():
			path = QUICK_SAVE_PATH

	var result := _engine.save_to_file(path)
	if not result.ok:
		_set_status("保存失败: %s" % result.error)
		return

	_set_status("已保存到: %s" % path)
	save_completed.emit(path)
	_refresh_slots()
	_select_slot_path(path)

func _sanitize_slot_name(name: String) -> String:
	var out := name.strip_edges()
	out = out.replace("/", "_")
	out = out.replace("\\", "_")
	out = out.replace(":", "_")
	out = out.replace("..", "_")
	return out

func _on_browse_pressed() -> void:
	if _file_dialog == null:
		return
	_file_dialog.current_path = ""
	_file_dialog.popup_centered_clamped(Vector2i(900, 650))

func _on_file_dialog_selected(path: String) -> void:
	if _file_path_edit != null:
		_file_path_edit.text = path
	_set_status(path)

func _set_status(msg: String) -> void:
	if _status_label != null:
		_status_label.text = msg
