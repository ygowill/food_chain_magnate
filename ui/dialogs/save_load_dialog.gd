# 存档/回放文件选择对话框
# - 载入/回放：桌面端使用 FileDialog；Web 端使用浏览器本地文件选择上传 JSON
# - 保存：支持 user://savegame.json（快速存档）+ user://saves/*.json（命名槽位）+ 文件系统路径
class_name SaveLoadDialog
extends ModalDialogBase

signal load_selected(path: String)
signal save_completed(path: String)
signal external_save_requested(target: Dictionary)
signal cancelled()

const UiStylesClass = preload("res://ui/utils/ui_styles.gd")

enum DialogMode { LOAD, SAVE, REPLAY }

const SAVES_DIR := "user://saves"
const QUICK_SAVE_PATH := "user://savegame.json"
const WEB_UPLOAD_DIR := "user://web_uploads"

var _dialog_mode: DialogMode = DialogMode.LOAD
var _engine: GameEngine = null
var _use_external_save_handler: bool = false

var _title_label: Label
var _dialog_panel: PanelContainer

var _tabs: TabContainer
var _slot_tab_root: Control
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
var _direct_file_pick_mode: bool = false
var _web_upload_callback = null

func _ready() -> void:
	super._ready()
	_build_ui()
	_connect_signals()
	_set_title("存档管理")
	_refresh_slots()
	_update_ui_state()

func _is_web() -> bool:
	return OS.has_feature("web")

func open_for_load() -> void:
	_dialog_mode = DialogMode.LOAD
	_engine = null
	_use_external_save_handler = false
	_direct_file_pick_mode = true
	_set_title("载入游戏")
	_update_ui_state()
	close()
	_open_picker_for_load_mode()

func open_for_replay() -> void:
	_dialog_mode = DialogMode.REPLAY
	_engine = null
	_use_external_save_handler = false
	_direct_file_pick_mode = true
	_set_title("选择回放文件")
	_update_ui_state()
	close()
	_open_picker_for_load_mode()

func open_for_save(engine: GameEngine, title: String = "保存游戏", use_external_save_handler: bool = false) -> void:
	_dialog_mode = DialogMode.SAVE
	_engine = engine
	_use_external_save_handler = bool(use_external_save_handler)
	_direct_file_pick_mode = false
	_set_title(title)
	_refresh_slots()
	_update_ui_state()
	_prefer_file_tab_on_web()
	open()

func finish_external_save_success(path: String) -> void:
	_set_status("已保存到: %s" % str(path))
	save_completed.emit(str(path))
	if _dialog_mode == DialogMode.SAVE:
		_refresh_slots()
		_select_slot_path(str(path))
	close()

func finish_external_save_error(message: String) -> void:
	_set_status(str(message))

func _prefer_file_tab_on_web() -> void:
	if not _is_web():
		return
	if _tabs != null and is_instance_valid(_tabs):
		_tabs.current_tab = 1

func _open_picker_for_load_mode() -> void:
	if _is_web():
		if not _try_open_web_file_picker():
			GameLog.warn("SaveLoadDialog", "Web 文件选择器打开失败（已禁用回退到 FileDialog）")
		return
	_open_file_dialog_popup()

func _open_file_dialog_popup() -> void:
	if _file_dialog == null or not is_instance_valid(_file_dialog):
		return
	_file_dialog.current_path = ""
	# FileDialog.popup_file_dialog() 在可用时会优先走原生选择器（Web 下即浏览器本地文件选择）。
	if _file_dialog.has_method("popup_file_dialog"):
		_file_dialog.call("popup_file_dialog")
		return
	_file_dialog.popup_centered_clamped(Vector2i(900, 650))

func _grab_default_focus() -> void:
	if _dialog_mode == DialogMode.SAVE and _slot_name_edit != null:
		_slot_name_edit.grab_focus()
		return
	if _file_path_edit != null:
		_file_path_edit.grab_focus()
		return
	if _slot_list != null:
		_slot_list.grab_focus()

func _set_title(text: String) -> void:
	if _title_label != null and is_instance_valid(_title_label):
		_title_label.text = str(text).strip_edges()

func _build_ui() -> void:
	var overlay_rect := ColorRect.new()
	overlay_rect.name = "Overlay"
	overlay_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay_rect.color = overlay_color
	overlay_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay_rect)

	var center := CenterContainer.new()
	center.name = "Center"
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	_dialog_panel = PanelContainer.new()
	_dialog_panel.name = "DialogPanel"
	_dialog_panel.custom_minimum_size = Vector2(760, 520)
	UiStylesClass.apply_dialog_surface(_dialog_panel)
	center.add_child(_dialog_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	_dialog_panel.add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)

	_title_label = Label.new()
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_title_label.add_theme_font_size_override("font_size", 22)
	UiStylesClass.apply_label_dark(_title_label)
	root.add_child(_title_label)

	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	UiStylesClass.apply_tab_container_surface(_tabs)
	root.add_child(_tabs)

	# === Tab 1: 存档槽 ===
	var slot_tab := VBoxContainer.new()
	slot_tab.add_theme_constant_override("separation", 8)
	_tabs.add_child(slot_tab)
	_slot_tab_root = slot_tab
	_tabs.set_tab_title(_tabs.get_tab_count() - 1, "存档槽")

	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 8)
	slot_tab.add_child(name_row)

	var name_label := Label.new()
	name_label.text = "槽位名:"
	name_label.add_theme_font_size_override("font_size", 12)
	UiStylesClass.apply_label_dark(name_label)
	name_row.add_child(name_label)

	_slot_name_edit = LineEdit.new()
	_slot_name_edit.placeholder_text = "例如：slot1 / round3 / my_save"
	_slot_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiStylesClass.apply_line_edit_field(_slot_name_edit)
	name_row.add_child(_slot_name_edit)

	_slot_refresh_btn = Button.new()
	_slot_refresh_btn.text = "刷新"
	_slot_refresh_btn.custom_minimum_size = Vector2(72, 30)
	UiStylesClass.apply_button_secondary(_slot_refresh_btn)
	name_row.add_child(_slot_refresh_btn)

	_slot_list = ItemList.new()
	_slot_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_slot_list.allow_reselect = true
	_slot_list.select_mode = ItemList.SELECT_SINGLE
	UiStylesClass.apply_item_list_surface(_slot_list)
	slot_tab.add_child(_slot_list)

	var slot_btn_row := HBoxContainer.new()
	slot_btn_row.add_theme_constant_override("separation", 8)
	slot_tab.add_child(slot_btn_row)

	slot_btn_row.add_child(_create_spacer())

	_slot_cancel_btn = Button.new()
	_slot_cancel_btn.text = "取消"
	_slot_cancel_btn.custom_minimum_size = Vector2(90, 34)
	UiStylesClass.apply_button_secondary(_slot_cancel_btn)
	slot_btn_row.add_child(_slot_cancel_btn)

	_slot_primary_btn = Button.new()
	_slot_primary_btn.text = "确定"
	_slot_primary_btn.custom_minimum_size = Vector2(120, 34)
	UiStylesClass.apply_button_primary(_slot_primary_btn)
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
	UiStylesClass.apply_label_dark(file_label)
	file_row.add_child(file_label)

	_file_path_edit = LineEdit.new()
	_file_path_edit.placeholder_text = "选择一个存档 JSON 文件（可为 user:// 或绝对路径）"
	_file_path_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiStylesClass.apply_line_edit_field(_file_path_edit)
	file_row.add_child(_file_path_edit)

	_file_browse_btn = Button.new()
	_file_browse_btn.text = "浏览..."
	_file_browse_btn.custom_minimum_size = Vector2(90, 30)
	UiStylesClass.apply_button_secondary(_file_browse_btn)
	file_row.add_child(_file_browse_btn)

	var file_btn_row := HBoxContainer.new()
	file_btn_row.add_theme_constant_override("separation", 8)
	file_tab.add_child(file_btn_row)

	file_btn_row.add_child(_create_spacer())

	_file_cancel_btn = Button.new()
	_file_cancel_btn.text = "取消"
	_file_cancel_btn.custom_minimum_size = Vector2(90, 34)
	UiStylesClass.apply_button_secondary(_file_cancel_btn)
	file_btn_row.add_child(_file_cancel_btn)

	_file_primary_btn = Button.new()
	_file_primary_btn.text = "加载"
	_file_primary_btn.custom_minimum_size = Vector2(120, 34)
	UiStylesClass.apply_button_primary(_file_primary_btn)
	file_btn_row.add_child(_file_primary_btn)

	_status_label = Label.new()
	_status_label.text = ""
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.add_theme_font_size_override("font_size", 12)
	UiStylesClass.apply_label_hint_dark(_status_label)
	root.add_child(_status_label)

	# FileDialog（文件系统选择）
	_file_dialog = FileDialog.new()
	_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_file_dialog.filters = PackedStringArray([
		"*.json;存档文件;application/json"
	])

	# Web 端：强制使用浏览器文件选择（上传），避免展示运行环境目录。
	if _is_web():
		_file_dialog.use_native_dialog = true
		_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	else:
		_file_dialog.access = FileDialog.ACCESS_FILESYSTEM

	add_child(_file_dialog)

func _connect_signals() -> void:
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
	var is_web := _is_web()
	var primary_text := "保存" if is_save else "加载"
	var file_primary_text := primary_text

	if _slot_tab_root != null and is_instance_valid(_slot_tab_root):
		_slot_tab_root.visible = is_save
	if _tabs != null and is_instance_valid(_tabs):
		_tabs.tabs_visible = is_save
		_tabs.current_tab = 0 if is_save else 1

	if _slot_primary_btn != null:
		_slot_primary_btn.text = primary_text
	if _file_primary_btn != null:
		if is_save and is_web:
			file_primary_text = "下载"
		_file_primary_btn.text = file_primary_text

	if _slot_name_edit != null:
		_slot_name_edit.editable = is_save
		if not is_save:
			_slot_name_edit.placeholder_text = "请选择一个存档槽位"

	if _file_path_edit != null:
		if is_save and is_web:
			_file_path_edit.placeholder_text = "例如：savegame.json（将下载到本地）"
		elif is_save:
			_file_path_edit.placeholder_text = "选择保存路径（可为 user:// 或绝对路径）"
		elif is_web:
			_file_path_edit.placeholder_text = "请选择一个存档 JSON 文件（将上传到浏览器）"
		else:
			_file_path_edit.placeholder_text = "选择一个存档 JSON 文件（可为 user:// 或绝对路径）"

	if _file_browse_btn != null:
		if is_save and is_web:
			_file_browse_btn.visible = false
		else:
			_file_browse_btn.visible = true
			_file_browse_btn.text = "上传..." if (is_web and not is_save) else "浏览..."

	if _file_dialog != null and is_instance_valid(_file_dialog):
		_file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE if is_save else FileDialog.FILE_MODE_OPEN_FILE

func _try_open_web_file_picker() -> bool:
	if not _is_web():
		return false

	_web_upload_callback = JavaScriptBridge.create_callback(_on_web_file_picked)
	var window = JavaScriptBridge.get_interface("window")
	if window == null:
		return false
	window.__godot_save_load_upload_cb = _web_upload_callback

	var ok_val = JavaScriptBridge.eval("""
(() => {
	const cb = window.__godot_save_load_upload_cb;
	if (!cb) return false;
	try {
		const input = document.createElement("input");
		input.type = "file";
		input.accept = ".json,application/json";
		input.style.display = "none";
		const cleanup = () => {
			if (input.parentNode) input.parentNode.removeChild(input);
			try { delete window.__godot_save_load_upload_cb; } catch (_e) {}
		};
		input.addEventListener("change", () => {
			const file = (input.files && input.files.length > 0) ? input.files[0] : null;
			if (!file) {
				cb("", "");
				cleanup();
				return;
			}
			const reader = new FileReader();
			reader.onload = () => {
				cb(String(reader.result || ""), String(file.name || ""));
				cleanup();
			};
			reader.onerror = () => {
				cb("", String(file.name || ""));
				cleanup();
			};
			reader.readAsText(file);
		}, { once: true });
		document.body.appendChild(input);
		input.click();
		return true;
	} catch (e) {
		try { cb("", ""); } catch (_e) {}
		try { delete window.__godot_save_load_upload_cb; } catch (_e) {}
		return false;
	}
})()
""", true)
	if ok_val is bool:
		return bool(ok_val)
	if ok_val is int:
		return int(ok_val) != 0
	if ok_val is float:
		return absf(float(ok_val)) > 0.0001
	var ok_text := str(ok_val).to_lower()
	return ok_text == "true" or ok_text == "1"

func _on_web_file_picked(args: Array) -> void:
	var json_text := ""
	var source_name := ""
	if args.size() > 0:
		json_text = str(args[0])
	if args.size() > 1:
		source_name = str(args[1]).strip_edges()

	if json_text.is_empty():
		_set_status("未选择文件")
		return

	var parsed = JSON.parse_string(json_text)
	if not (parsed is Dictionary):
		_set_status("文件内容无效：不是存档 JSON")
		return

	var base_name := _sanitize_export_file_name(source_name)
	if base_name.is_empty():
		base_name = "upload_save.json"
	base_name = _ensure_json_extension(base_name)
	var stamp := int(Time.get_unix_time_from_system())
	_ensure_dir(WEB_UPLOAD_DIR)
	var path := "%s/%d_%s" % [WEB_UPLOAD_DIR, stamp, base_name]
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_set_status("上传失败：无法写入临时文件")
		return
	file.store_string(json_text)
	file.close()

	if _file_path_edit != null:
		_file_path_edit.text = path
	if source_name.is_empty():
		_set_status("已选择文件")
	else:
		_set_status("已选择: %s" % source_name)
	close()
	_direct_file_pick_mode = false
	load_selected.emit(path)

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
	var d := _read_json_dict(path)
	if d.is_empty():
		return {}

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

func _read_json_dict(path: String) -> Dictionary:
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
	return parsed if (parsed is Dictionary) else {}

func _ensure_saves_dir() -> void:
	_ensure_dir(SAVES_DIR)

func _ensure_dir(dir_path: String) -> void:
	var abs_dir := ProjectSettings.globalize_path(dir_path)
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
	if _file_dialog != null and is_instance_valid(_file_dialog):
		_file_dialog.hide()
	close()
	cancelled.emit()

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey:
		var e: InputEventKey = event
		if e.pressed and not e.echo and e.keycode == KEY_ESCAPE:
			_on_cancel_pressed()
			get_viewport().set_input_as_handled()

func _on_primary_pressed() -> void:
	match _dialog_mode:
		DialogMode.SAVE:
			_save_selected()
		DialogMode.LOAD, DialogMode.REPLAY:
			_emit_selected_slot()

func _on_primary_file_pressed() -> void:
	if _dialog_mode == DialogMode.SAVE:
		_save_to_file_or_download()
		return

	var path := str(_file_path_edit.text).strip_edges()
	if path.is_empty():
		_set_status("请选择一个文件")
		return
	if not FileAccess.file_exists(path):
		_set_status("文件不存在: %s" % path)
		return

	close()
	load_selected.emit(path)

func _save_to_file_or_download() -> void:
	if _engine == null:
		_set_status("游戏引擎为空，无法保存")
		return

	if _is_web():
		var file_name := str(_file_path_edit.text).strip_edges()
		if file_name.is_empty():
			file_name = QUICK_SAVE_PATH.get_file()
		file_name = _sanitize_export_file_name(file_name)
		file_name = _ensure_json_extension(file_name)
		if file_name.is_empty():
			_set_status("文件名无效")
			return
		if _use_external_save_handler:
			_emit_external_save_request({
				"target_kind": "web_download",
				"file_name": file_name,
			})
			return

		var archive_result := _engine.create_archive()
		if not archive_result.ok:
			_set_status("导出失败: %s" % archive_result.error)
			return

		var json := JSON.stringify(archive_result.value, "\t")
		var bytes: PackedByteArray = json.to_utf8_buffer()
		JavaScriptBridge.download_buffer(bytes, file_name, "application/json")
		_set_status("已下载: %s" % file_name)
		save_completed.emit(file_name)
		return

	var path := str(_file_path_edit.text).strip_edges()
	if path.is_empty():
		_set_status("请选择一个保存路径")
		return
	path = _ensure_json_extension(path)
	if _use_external_save_handler:
		_emit_external_save_request({
			"target_kind": "file_path",
			"path": path,
		})
		return

	var result := _engine.save_to_file(path)
	if not result.ok:
		_set_status("保存失败: %s" % result.error)
		return

	_set_status("已保存到: %s" % path)
	save_completed.emit(path)

func _ensure_json_extension(path_or_name: String) -> String:
	var out := str(path_or_name).strip_edges()
	if out.is_empty():
		return ""
	if out.to_lower().ends_with(".json"):
		return out
	return "%s.json" % out

func _sanitize_export_file_name(name: String) -> String:
	var out := str(name).strip_edges()
	out = out.replace("/", "_")
	out = out.replace("\\", "_")
	out = out.replace(":", "_")
	out = out.replace("..", "_")
	return out

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

	close()
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
	if _use_external_save_handler:
		_emit_external_save_request({
			"target_kind": "slot_path",
			"path": path,
		})
		return

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
	if _dialog_mode != DialogMode.SAVE and _is_web():
		if not _try_open_web_file_picker():
			_set_status("浏览器文件选择不可用，请检查浏览器弹窗权限后重试")
		return
	_open_file_dialog_popup()

func _on_file_dialog_selected(path: String) -> void:
	if _file_path_edit != null:
		_file_path_edit.text = path
	_set_status(path)
	if _direct_file_pick_mode and (_dialog_mode == DialogMode.LOAD or _dialog_mode == DialogMode.REPLAY):
		_direct_file_pick_mode = false
		load_selected.emit(path)

func _set_status(msg: String) -> void:
	if _status_label != null:
		_status_label.text = msg

func _emit_external_save_request(target: Dictionary) -> void:
	_set_status("正在准备导出...")
	external_save_requested.emit(Dictionary(target).duplicate(true))
