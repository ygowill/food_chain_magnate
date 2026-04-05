# 创建房间弹窗（支持普通建房 / 从存档恢复）
class_name CreateRoomDialog
extends ModalDialogBase

signal create_requested(room_password: String, config_patch: Dictionary, resume_room_bootstrap: Dictionary)
signal cancelled()

const ArchiveClass = preload("res://core/engine/game_engine/archive.gd")
const GameEngineClass = preload("res://core/engine/game_engine.gd")
const ResumeLogHistoryBuilderClass = preload("res://ui/dialogs/create_room_resume_log_history_builder.gd")
const RoomConfigEditorClass = preload("res://ui/components/room_config_editor/room_config_editor.gd")
const UiStylesClass = preload("res://ui/utils/ui_styles.gd")

class _SilentEventSink:
	extends RefCounted

	func emit_event(_event_type: String, _data: Dictionary) -> void:
		pass

	func clear_history_and_reset_sequence() -> void:
		pass

	func clear_history() -> void:
		pass

	func record_event(_event_type: String, _data: Dictionary) -> void:
		pass

var _dialog_panel: PanelContainer = null
var _inner_border: PanelContainer = null
var _title_label: Label = null
var _password_edit: LineEdit = null
var _resume_checkbox: CheckBox = null
var _archive_controls: VBoxContainer = null
var _archive_path_edit: LineEdit = null
var _browse_archive_button: Button = null
var _clear_archive_button: Button = null
var _archive_preview_label: Label = null
var _resume_log_list: ItemList = null
var _resume_hint_label: Label = null
var _archive_file_dialog: FileDialog = null
var _room_config_editor = null
var _error_label: Label = null
var _create_button: Button = null
var _cancel_button: Button = null

var _resume_room_bootstrap: Dictionary = {}
var _resume_config_patch: Dictionary = {}
var _loaded_resume_archive_path: String = ""
var _loaded_resume_archive: Dictionary = {}
var _resume_preview_engine = null
var _resume_original_current_index: int = -1
var _resume_selected_current_index: int = -1
var _resume_log_items: Array[Dictionary] = []
var _resume_original_log_item_index: int = -1
var _resume_selected_log_item_index: int = -1
var _resume_history_warning_text: String = ""
var _resume_selection_syncing: bool = false

func _ready() -> void:
	super._ready()
	_build_ui()

func open_dialog() -> void:
	if _password_edit != null and is_instance_valid(_password_edit):
		_password_edit.text = ""
	_clear_error()
	_apply_resume_mode_ui()
	open()

func _build_ui() -> void:
	var overlay_rect := ColorRect.new()
	overlay_rect.name = "Overlay"
	overlay_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, 0)
	overlay_rect.color = overlay_color
	overlay_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay_rect)

	var center := CenterContainer.new()
	center.name = "Center"
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, 0)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	_dialog_panel = PanelContainer.new()
	_dialog_panel.custom_minimum_size = Vector2(1200, 700)
	UiStylesClass.apply_dialog_surface(_dialog_panel)
	_dialog_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	center.add_child(_dialog_panel)

	var outer_margin := MarginContainer.new()
	outer_margin.add_theme_constant_override("margin_left", 6)
	outer_margin.add_theme_constant_override("margin_top", 6)
	outer_margin.add_theme_constant_override("margin_right", 6)
	outer_margin.add_theme_constant_override("margin_bottom", 6)
	_dialog_panel.add_child(outer_margin)

	_inner_border = PanelContainer.new()
	UiStylesClass.apply_poster_inner_border(_inner_border)
	outer_margin.add_child(_inner_border)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	_inner_border.add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)

	_title_label = Label.new()
	_title_label.text = "创建房间"
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 24)
	UiStylesClass.apply_label_dark(_title_label)
	root.add_child(_title_label)

	var line := ColorRect.new()
	line.custom_minimum_size = Vector2(320, 2)
	line.color = Color(0.73, 0.23, 0.18, 0.5)
	line.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	root.add_child(line)

	var pw_row := HBoxContainer.new()
	pw_row.add_theme_constant_override("separation", 8)
	root.add_child(pw_row)

	var pw_label := Label.new()
	pw_label.text = "房间密码（可空）"
	UiStylesClass.apply_label_dark(pw_label)
	pw_row.add_child(pw_label)

	_password_edit = LineEdit.new()
	_password_edit.secret = true
	_password_edit.secret_character = "*"
	_password_edit.placeholder_text = "留空则无密码"
	_password_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_password_edit.custom_minimum_size = Vector2(200, 0)
	UiStylesClass.apply_line_edit_field(_password_edit)
	pw_row.add_child(_password_edit)

	_resume_checkbox = CheckBox.new()
	_resume_checkbox.text = "从存档恢复"
	UiStylesClass.apply_check_box_field(_resume_checkbox)
	_resume_checkbox.toggled.connect(_on_resume_checkbox_toggled)
	root.add_child(_resume_checkbox)

	_archive_controls = VBoxContainer.new()
	_archive_controls.add_theme_constant_override("separation", 8)
	root.add_child(_archive_controls)

	var archive_row := HBoxContainer.new()
	archive_row.add_theme_constant_override("separation", 8)
	_archive_controls.add_child(archive_row)

	var archive_label := Label.new()
	archive_label.text = "存档文件"
	UiStylesClass.apply_label_dark(archive_label)
	archive_row.add_child(archive_label)

	_archive_path_edit = LineEdit.new()
	_archive_path_edit.editable = false
	_archive_path_edit.placeholder_text = "选择一个存档 JSON 文件"
	_archive_path_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiStylesClass.apply_line_edit_field(_archive_path_edit)
	archive_row.add_child(_archive_path_edit)

	_browse_archive_button = Button.new()
	_browse_archive_button.text = "选择文件"
	UiStylesClass.apply_button_secondary(_browse_archive_button)
	_browse_archive_button.pressed.connect(_on_browse_archive_pressed)
	archive_row.add_child(_browse_archive_button)

	_clear_archive_button = Button.new()
	_clear_archive_button.text = "清除"
	UiStylesClass.apply_button_secondary(_clear_archive_button)
	_clear_archive_button.pressed.connect(_on_clear_archive_pressed)
	archive_row.add_child(_clear_archive_button)

	_archive_preview_label = Label.new()
	_archive_preview_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_archive_preview_label.visible = false
	UiStylesClass.apply_label_hint_dark(_archive_preview_label)
	_archive_controls.add_child(_archive_preview_label)

	var resume_log_label := Label.new()
	resume_log_label.text = "恢复时间点（日志历史）"
	UiStylesClass.apply_label_dark(resume_log_label)
	_archive_controls.add_child(resume_log_label)

	_resume_log_list = ItemList.new()
	_resume_log_list.allow_reselect = true
	_resume_log_list.select_mode = ItemList.SELECT_SINGLE
	_resume_log_list.custom_minimum_size = Vector2(0, 240)
	UiStylesClass.apply_item_list_surface(_resume_log_list)
	_resume_log_list.item_selected.connect(_on_resume_log_item_selected)
	_archive_controls.add_child(_resume_log_list)

	_resume_hint_label = Label.new()
	_resume_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	UiStylesClass.apply_label_hint_dark(_resume_hint_label)
	_archive_controls.add_child(_resume_hint_label)

	var line2 := ColorRect.new()
	line2.custom_minimum_size = Vector2(320, 2)
	line2.color = Color(0.73, 0.23, 0.18, 0.5)
	line2.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	root.add_child(line2)

	_room_config_editor = RoomConfigEditorClass.new()
	_room_config_editor.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_room_config_editor)

	_error_label = Label.new()
	_error_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_error_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_error_label.visible = false
	UiStylesClass.apply_label_error(_error_label)
	root.add_child(_error_label)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 12)
	root.add_child(btn_row)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_row.add_child(spacer)

	_cancel_button = Button.new()
	_cancel_button.text = "取消"
	UiStylesClass.apply_button_secondary(_cancel_button)
	_cancel_button.pressed.connect(_on_cancel_pressed)
	btn_row.add_child(_cancel_button)

	_create_button = Button.new()
	_create_button.text = "创建并进入"
	UiStylesClass.apply_button_primary(_create_button)
	_create_button.pressed.connect(_on_create_pressed)
	btn_row.add_child(_create_button)

	_archive_file_dialog = FileDialog.new()
	_archive_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_archive_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_archive_file_dialog.filters = PackedStringArray(["*.json;存档文件;application/json"])
	_archive_file_dialog.file_selected.connect(_on_archive_file_selected)
	add_child(_archive_file_dialog)

	_reset_resume_selection_controls()
	_apply_resume_mode_ui()

func _grab_default_focus() -> void:
	if _password_edit != null and is_instance_valid(_password_edit):
		_password_edit.grab_focus()

func _apply_resume_mode_ui() -> void:
	var use_resume := _resume_checkbox != null and is_instance_valid(_resume_checkbox) and _resume_checkbox.button_pressed
	if _archive_controls != null and is_instance_valid(_archive_controls):
		_archive_controls.visible = use_resume
	if _room_config_editor != null and is_instance_valid(_room_config_editor):
		_room_config_editor.set_editable(not use_resume)
	_create_button.text = "从存档创建房间" if use_resume else "创建并进入"

func _build_resume_config_patch(path: String, archive: Dictionary, state, current_index: int) -> Dictionary:
	var player_count := 0
	var enabled_modules: Array[String] = []
	var seed := 0
	var round_number := 0
	var phase := ""
	var sub_phase := ""
	if state != null:
		player_count = state.players.size() if state.players is Array else 0
		seed = int(state.seed)
		round_number = int(state.round_number)
		phase = str(state.phase)
		sub_phase = str(state.sub_phase)
		if state.modules is Array:
			for module_id in state.modules:
				var mid := str(module_id).strip_edges()
				if mid.is_empty():
					continue
				enabled_modules.append(mid)
	var phase_text := phase
	if not sub_phase.is_empty():
		phase_text += " / %s" % sub_phase
	return {
		"desired_player_count": player_count,
		"seed_mode": "fixed",
		"seed": seed,
		"enabled_modules_v2": enabled_modules,
		"modules_v2_base_dir": str(archive.get("modules_v2_base_dir", Globals.modules_v2_base_dir)).strip_edges(),
		"allow_spectators": true,
		"game_option_overrides": {},
		"room_mode": "resume_archive",
		"resume_summary": {
			"source_name": path.get_file(),
			"player_count": player_count,
			"round_number": round_number,
			"phase": phase_text,
			"current_index": current_index,
		},
	}

func _get_resume_archive_command_count() -> int:
	var commands_val = _loaded_resume_archive.get("commands", null)
	if commands_val is Array:
		return Array(commands_val).size()
	return 0

func _get_resume_archive_max_index() -> int:
	return _get_resume_archive_command_count() - 1

func _build_resume_selected_archive() -> Dictionary:
	if _loaded_resume_archive.is_empty():
		return {}
	var archive := _loaded_resume_archive.duplicate(true)
	archive["current_index"] = _resume_selected_current_index
	if _resume_preview_engine != null and is_instance_valid(_resume_preview_engine):
		var state = _resume_preview_engine.get_state() if _resume_preview_engine.has_method("get_state") else null
		if state != null and state.has_method("compute_hash"):
			archive["final_hash"] = str(state.compute_hash())
	return archive

func _get_resume_log_item(index: int) -> Dictionary:
	if index < 0 or index >= _resume_log_items.size():
		return {}
	var item_val = _resume_log_items[index]
	if not (item_val is Dictionary):
		return {}
	return Dictionary(item_val)

func _get_resume_log_display_text(index: int, fallback_text: String = "") -> String:
	var item := _get_resume_log_item(index)
	var text := str(item.get("display_text", "")).strip_edges()
	if text.is_empty():
		return fallback_text
	return text

func _update_resume_preview_label(state) -> void:
	if _archive_preview_label == null or not is_instance_valid(_archive_preview_label):
		return
	if state == null:
		_archive_preview_label.text = ""
		_archive_preview_label.visible = false
		return
	var player_count: int = 0
	if state.players is Array:
		player_count = int(state.players.size())
	var phase_text := str(state.phase)
	var sub_phase_text := str(state.sub_phase).strip_edges()
	if not sub_phase_text.is_empty():
		phase_text += " / %s" % sub_phase_text
	var current_player_text := "-"
	if state.has_method("get_current_player_id"):
		var current_player_id := int(state.get_current_player_id())
		if current_player_id >= 0:
			current_player_text = "P%d" % (current_player_id + 1)
	var preview := "已载入：%s\n玩家数：%d\n历史命令数：%d\n原存档位置：%s\n当前选择：%s\n回合：%d\n阶段：%s\n当前玩家：%s" % [
		_loaded_resume_archive_path.get_file(),
		player_count,
		_get_resume_archive_command_count(),
		_get_resume_log_display_text(_resume_original_log_item_index, "开局（未执行命令）"),
		_get_resume_log_display_text(_resume_selected_log_item_index, "开局（未执行命令）"),
		int(state.round_number),
		phase_text,
		current_player_text,
	]
	_archive_preview_label.text = preview
	_archive_preview_label.visible = true

func _reset_resume_selection_controls() -> void:
	_resume_selection_syncing = true
	_resume_log_items.clear()
	_resume_original_log_item_index = -1
	_resume_selected_log_item_index = -1
	_resume_history_warning_text = ""
	if _resume_log_list != null and is_instance_valid(_resume_log_list):
		_resume_log_list.clear()
	_resume_selection_syncing = false
	_update_resume_hint_label()

func _update_resume_hint_label() -> void:
	if _resume_hint_label == null or not is_instance_valid(_resume_hint_label):
		return
	if _resume_log_items.is_empty():
		var empty_lines: Array[String] = ["载入存档后可从日志历史选择恢复时间点。"]
		if not _resume_history_warning_text.is_empty():
			empty_lines.append(_resume_history_warning_text)
		_resume_hint_label.text = "\n".join(empty_lines)
		return
	var lines: Array[String] = [
		"选择一条日志后，会恢复到该条日志对应命令执行完成后的状态；同一命令产生多条日志时，恢复结果相同。"
	]
	var selected_text := _get_resume_log_display_text(_resume_selected_log_item_index, "")
	if not selected_text.is_empty():
		lines.append("当前日志：%s" % selected_text)
	if not _resume_history_warning_text.is_empty():
		lines.append(_resume_history_warning_text)
	_resume_hint_label.text = "\n".join(lines)

func _populate_resume_log_history() -> void:
	_resume_log_items.clear()
	_resume_original_log_item_index = -1
	_resume_selected_log_item_index = -1
	_resume_history_warning_text = ""
	if _resume_log_list == null or not is_instance_valid(_resume_log_list):
		return
	_resume_log_list.clear()

	if _resume_preview_engine == null or not is_instance_valid(_resume_preview_engine):
		_update_resume_hint_label()
		return

	var build_r: Result = ResumeLogHistoryBuilderClass.new().build(_resume_preview_engine, _resume_original_current_index)
	if not build_r.ok:
		_resume_history_warning_text = "日志历史构建失败：%s" % build_r.error
		_update_resume_hint_label()
		return
	if not build_r.warnings.is_empty():
		_resume_history_warning_text = build_r.get_warnings_string()

	var data_val = build_r.value
	if not (data_val is Dictionary):
		_resume_history_warning_text = "日志历史构建失败：返回值类型错误"
		_update_resume_hint_label()
		return
	var data: Dictionary = data_val
	var items_val = data.get("items", null)
	if items_val is Array:
		for item_val in items_val:
			if not (item_val is Dictionary):
				continue
			var item: Dictionary = Dictionary(item_val)
			var display_text := str(item.get("display_text", "")).strip_edges()
			if display_text.is_empty():
				continue
			var next_index := _resume_log_list.item_count
			_resume_log_list.add_item(display_text)
			_resume_log_items.append(item)
			_resume_log_list.set_item_metadata(next_index, int(item.get("command_index", -1)))

	_resume_original_log_item_index = int(data.get("original_item_index", -1))
	_resume_selected_log_item_index = int(data.get("selected_item_index", -1))
	_update_resume_hint_label()

func _resolve_resume_log_item_index(preferred_log_item_index: int, target_index: int) -> int:
	if preferred_log_item_index >= 0 and preferred_log_item_index < _resume_log_items.size():
		var preferred_item := _get_resume_log_item(preferred_log_item_index)
		if int(preferred_item.get("command_index", -999999)) == int(target_index):
			return preferred_log_item_index
	for i in range(_resume_log_items.size() - 1, -1, -1):
		var item := _get_resume_log_item(i)
		if int(item.get("command_index", -999999)) == int(target_index):
			return i
	return -1

func _sync_resume_selection_controls(selected_log_item_index: int) -> void:
	_resume_selection_syncing = true
	_resume_selected_log_item_index = selected_log_item_index
	if _resume_log_list != null and is_instance_valid(_resume_log_list):
		if selected_log_item_index >= 0 and selected_log_item_index < _resume_log_list.item_count:
			_resume_log_list.select(selected_log_item_index)
	_resume_selection_syncing = false
	_update_resume_hint_label()

func _clear_loaded_archive() -> void:
	_loaded_resume_archive_path = ""
	_loaded_resume_archive = {}
	_resume_preview_engine = null
	_resume_original_current_index = -1
	_resume_selected_current_index = -1
	_resume_room_bootstrap = {}
	_resume_config_patch = {}
	if _archive_path_edit != null and is_instance_valid(_archive_path_edit):
		_archive_path_edit.text = ""
	if _archive_preview_label != null and is_instance_valid(_archive_preview_label):
		_archive_preview_label.text = ""
		_archive_preview_label.visible = false
	_reset_resume_selection_controls()

func _apply_resume_target_index(target_index: int, preferred_log_item_index: int = -1) -> void:
	if _resume_preview_engine == null or not is_instance_valid(_resume_preview_engine):
		return
	var max_index := _get_resume_archive_max_index()
	var normalized_index := mini(maxi(int(target_index), -1), max_index)
	var rewind_r: Result = _resume_preview_engine.rewind_to_command(normalized_index)
	if not rewind_r.ok:
		_resume_room_bootstrap = {}
		_resume_config_patch = {}
		_set_error("无法切换恢复位置：%s" % rewind_r.error)
		return
	var state = _resume_preview_engine.get_state() if _resume_preview_engine.has_method("get_state") else null
	if state == null:
		_resume_room_bootstrap = {}
		_resume_config_patch = {}
		_set_error("无法切换恢复位置：预览状态为空")
		return
	_resume_selected_current_index = normalized_index
	_resume_config_patch = _build_resume_config_patch(_loaded_resume_archive_path, _loaded_resume_archive, state, normalized_index)
	_resume_room_bootstrap = {"archive": _build_resume_selected_archive()}
	_sync_resume_selection_controls(_resolve_resume_log_item_index(preferred_log_item_index, normalized_index))
	_update_resume_preview_label(state)
	_clear_error()

func _apply_loaded_archive(path: String, archive: Dictionary, engine) -> void:
	_loaded_resume_archive_path = path
	_loaded_resume_archive = archive.duplicate(true)
	_resume_preview_engine = engine
	_resume_original_current_index = int(archive.get("current_index", -1))
	_resume_selected_current_index = _resume_original_current_index
	if _archive_path_edit != null and is_instance_valid(_archive_path_edit):
		_archive_path_edit.text = path
	_populate_resume_log_history()
	_apply_resume_target_index(_resume_original_current_index, _resume_original_log_item_index)
	if _room_config_editor != null and is_instance_valid(_room_config_editor):
		_room_config_editor.set_from_room_config(_resume_config_patch)

func _load_archive_from_path(path: String) -> void:
	var archive_r: Result = ArchiveClass.load_archive_from_file(path)
	if not archive_r.ok:
		_set_error("读取存档失败：%s" % archive_r.error)
		return
	var archive: Dictionary = Dictionary(archive_r.value).duplicate(true)
	var engine = GameEngineClass.new()
	if engine.has_method("set_event_sink"):
		engine.set_event_sink(_SilentEventSink.new())
	var load_r: Result = engine.load_from_archive(archive)
	if not load_r.ok:
		_set_error("存档不可用于联机恢复：%s" % load_r.error)
		return
	var state = engine.get_state()
	if state == null or not (state.players is Array):
		_set_error("存档状态无效：缺少玩家信息")
		return
	var player_count: int = int(state.players.size())
	if player_count < Globals.MIN_PLAYERS or player_count > Globals.MAX_PLAYERS:
		_set_error("当前仅支持 %d-%d 人局联机恢复，存档人数为 %d" % [Globals.MIN_PLAYERS, Globals.MAX_PLAYERS, player_count])
		return
	_apply_loaded_archive(path, archive, engine)

func _on_resume_checkbox_toggled(_pressed: bool) -> void:
	_apply_resume_mode_ui()

func _on_browse_archive_pressed() -> void:
	if _archive_file_dialog == null or not is_instance_valid(_archive_file_dialog):
		return
	_archive_file_dialog.popup_centered_ratio(0.7)

func _on_archive_file_selected(path: String) -> void:
	_load_archive_from_path(str(path))

func _on_clear_archive_pressed() -> void:
	_clear_loaded_archive()
	if _resume_checkbox != null and is_instance_valid(_resume_checkbox):
		_resume_checkbox.button_pressed = false
	_apply_resume_mode_ui()

func _on_resume_log_item_selected(index: int) -> void:
	if _resume_selection_syncing:
		return
	var item := _get_resume_log_item(index)
	if item.is_empty():
		return
	_apply_resume_target_index(int(item.get("command_index", -1)), index)

func _on_create_pressed() -> void:
	_clear_error()
	if _room_config_editor == null or not is_instance_valid(_room_config_editor):
		_set_error("配置编辑器缺失。")
		return

	var use_resume := _resume_checkbox != null and is_instance_valid(_resume_checkbox) and _resume_checkbox.button_pressed
	var patch: Dictionary = {}
	var resume_bootstrap: Dictionary = {}
	if use_resume:
		if _resume_room_bootstrap.is_empty() or _resume_config_patch.is_empty():
			_set_error("请先选择一个可用的存档文件。")
			return
		patch = _resume_config_patch.duplicate(true)
		resume_bootstrap = _resume_room_bootstrap.duplicate(true)
	else:
		var vr: Result = _room_config_editor.validate()
		if not vr.ok:
			_set_error(vr.error)
			return
		patch = _room_config_editor.get_config_patch()

	var password := str(_password_edit.text) if (_password_edit != null and is_instance_valid(_password_edit)) else ""
	close()
	create_requested.emit(password, patch, resume_bootstrap)

func _on_cancel_pressed() -> void:
	close()
	cancelled.emit()

func _set_error(message: String) -> void:
	if _error_label == null or not is_instance_valid(_error_label):
		return
	_error_label.text = str(message).strip_edges()
	_error_label.visible = not str(message).strip_edges().is_empty()

func _clear_error() -> void:
	if _error_label == null or not is_instance_valid(_error_label):
		return
	_error_label.text = ""
	_error_label.visible = false

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey:
		var e: InputEventKey = event
		if e.pressed and not e.echo and e.keycode == KEY_ESCAPE:
			_on_cancel_pressed()
			get_viewport().set_input_as_handled()
