extends ModalDialogBase

signal allow_spectators_change_requested(allowed: bool)

const RoomConfigEditorClass = preload("res://ui/components/room_config_editor/room_config_editor.gd")
const UiStylesClass = preload("res://ui/utils/ui_styles.gd")

const _SYNCING_STATUS_TEXT := "正在同步观战设置..."

var _dialog_panel: PanelContainer = null
var _summary_label: Label = null
var _status_label: Label = null
var _allow_spectators_hint_label: Label = null
var _spectators_list_container: VBoxContainer = null
var _room_config_editor = null
var _close_button: Button = null

var _room_state: Dictionary = {}
var _local_peer_id: int = 0
var _allow_spectators_request_pending: bool = false
var _suppress_editor_changed: bool = false

func _ready() -> void:
	super._ready()
	_build_ui()

func open_dialog() -> void:
	open()

func set_room_state(room_state: Dictionary, local_peer_id: int) -> void:
	_room_state = Dictionary(room_state).duplicate(true)
	_local_peer_id = int(local_peer_id)
	_refresh_content()

func set_allow_spectators_request_pending(pending: bool) -> void:
	_allow_spectators_request_pending = pending
	if pending:
		_set_status(_SYNCING_STATUS_TEXT, false)
	elif _status_label != null and is_instance_valid(_status_label) and _status_label.text == _SYNCING_STATUS_TEXT:
		_clear_status()
	_refresh_allow_spectators_editable()

func clear_status_message() -> void:
	_clear_status()

func show_allow_spectators_error(message: String) -> void:
	_allow_spectators_request_pending = false
	var msg := str(message).strip_edges()
	if msg.is_empty():
		msg = "服务器拒绝了本次更新。"
	_set_status("观战设置更新失败：%s" % msg, true)
	_refresh_content()

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
	_dialog_panel.custom_minimum_size = Vector2(1240, 720)
	UiStylesClass.apply_dialog_surface(_dialog_panel)
	_dialog_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	center.add_child(_dialog_panel)

	var outer_margin := MarginContainer.new()
	outer_margin.add_theme_constant_override("margin_left", 6)
	outer_margin.add_theme_constant_override("margin_top", 6)
	outer_margin.add_theme_constant_override("margin_right", 6)
	outer_margin.add_theme_constant_override("margin_bottom", 6)
	_dialog_panel.add_child(outer_margin)

	var inner_border := PanelContainer.new()
	UiStylesClass.apply_poster_inner_border(inner_border)
	outer_margin.add_child(inner_border)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	inner_border.add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)

	var title_label := Label.new()
	title_label.text = "对局详情"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 24)
	UiStylesClass.apply_label_dark(title_label)
	root.add_child(title_label)

	var title_line := ColorRect.new()
	title_line.custom_minimum_size = Vector2(320, 2)
	title_line.color = Color(0.73, 0.23, 0.18, 0.5)
	title_line.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	root.add_child(title_line)

	var summary_panel := _build_section_panel()
	root.add_child(summary_panel)

	var summary_margin := MarginContainer.new()
	summary_margin.add_theme_constant_override("margin_left", 16)
	summary_margin.add_theme_constant_override("margin_top", 14)
	summary_margin.add_theme_constant_override("margin_right", 16)
	summary_margin.add_theme_constant_override("margin_bottom", 14)
	summary_panel.add_child(summary_margin)

	_summary_label = Label.new()
	_summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_summary_label.add_theme_font_size_override("font_size", 15)
	UiStylesClass.apply_label_dark(_summary_label)
	summary_margin.add_child(_summary_label)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)

	var config_panel := _build_section_panel()
	content.add_child(config_panel)

	var config_margin := MarginContainer.new()
	config_margin.add_theme_constant_override("margin_left", 16)
	config_margin.add_theme_constant_override("margin_top", 14)
	config_margin.add_theme_constant_override("margin_right", 16)
	config_margin.add_theme_constant_override("margin_bottom", 14)
	config_panel.add_child(config_margin)

	var config_root := VBoxContainer.new()
	config_root.add_theme_constant_override("separation", 10)
	config_margin.add_child(config_root)

	var config_header := Label.new()
	config_header.text = "当前配置"
	config_header.add_theme_font_size_override("font_size", 16)
	UiStylesClass.apply_label_dark(config_header)
	config_root.add_child(config_header)

	_room_config_editor = RoomConfigEditorClass.new()
	_room_config_editor.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_room_config_editor.changed.connect(_on_room_config_changed)
	config_root.add_child(_room_config_editor)

	_allow_spectators_hint_label = Label.new()
	_allow_spectators_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_allow_spectators_hint_label.visible = false
	UiStylesClass.apply_label_hint_dark(_allow_spectators_hint_label)
	config_root.add_child(_allow_spectators_hint_label)

	var spectators_panel := _build_section_panel()
	content.add_child(spectators_panel)

	var spectators_margin := MarginContainer.new()
	spectators_margin.add_theme_constant_override("margin_left", 16)
	spectators_margin.add_theme_constant_override("margin_top", 14)
	spectators_margin.add_theme_constant_override("margin_right", 16)
	spectators_margin.add_theme_constant_override("margin_bottom", 14)
	spectators_panel.add_child(spectators_margin)

	_spectators_list_container = VBoxContainer.new()
	_spectators_list_container.add_theme_constant_override("separation", 8)
	spectators_margin.add_child(_spectators_list_container)

	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_status_label.visible = false
	root.add_child(_status_label)

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	root.add_child(footer)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)

	_close_button = Button.new()
	_close_button.text = "关闭"
	UiStylesClass.apply_button_primary(_close_button)
	_close_button.pressed.connect(_on_close_pressed)
	footer.add_child(_close_button)

	_refresh_content()

func _build_section_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.95, 0.91, 0.83, 0.55)
	style.border_color = Color(0.17, 0.13, 0.09, 0.15)
	style.set_border_width_all(1)
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_right = 10
	style.corner_radius_bottom_left = 10
	panel.add_theme_stylebox_override("panel", style)
	return panel

func _refresh_content() -> void:
	if _summary_label == null or not is_instance_valid(_summary_label):
		return
	if _room_config_editor == null or not is_instance_valid(_room_config_editor):
		return
	if _spectators_list_container == null or not is_instance_valid(_spectators_list_container):
		return

	var room_code := str(_room_state.get("room_code", "")).strip_edges().to_upper()
	var room_status := str(_room_state.get("status", "")).strip_edges()
	var players := Array(_room_state.get("players", []))
	var spectators := Array(_room_state.get("spectators", []))
	var host_peer_id := int(_room_state.get("host_peer_id", 0))
	var self_role := _resolve_self_role()
	var is_host := _local_peer_id > 0 and host_peer_id == _local_peer_id

	if room_code.is_empty():
		_summary_label.text = "当前没有可展示的联机房间信息。"
	else:
		_summary_label.text = "房间：%s\n状态：%s\n我的身份：%s\n玩家：%d\n旁观者：%d" % [
			room_code,
			room_status if not room_status.is_empty() else "-",
			self_role,
			players.size(),
			spectators.size(),
		]

	var cfg: Dictionary = Dictionary(_room_state.get("config", {}))
	_suppress_editor_changed = true
	_room_config_editor.set_from_room_config(cfg)
	_room_config_editor.set_editable(false)
	_suppress_editor_changed = false
	_refresh_allow_spectators_editable()

	var can_edit_allow_spectators := is_host and room_status == "InGame"
	_allow_spectators_hint_label.visible = can_edit_allow_spectators
	if can_edit_allow_spectators:
		_allow_spectators_hint_label.text = "房主可在对局中切换是否允许新的观战者加入。"

	for child in _spectators_list_container.get_children():
		child.queue_free()

	var spectators_header := Label.new()
	spectators_header.text = "当前观战者"
	spectators_header.add_theme_font_size_override("font_size", 16)
	UiStylesClass.apply_label_dark(spectators_header)
	_spectators_list_container.add_child(spectators_header)

	if spectators.is_empty():
		var empty_label := Label.new()
		empty_label.text = "暂无观战者"
		UiStylesClass.apply_label_hint_dark(empty_label)
		_spectators_list_container.add_child(empty_label)
		return

	for spectator_val in spectators:
		if not (spectator_val is Dictionary):
			continue
		var spectator: Dictionary = Dictionary(spectator_val)
		var spectator_name := str(spectator.get("name", "")).strip_edges()
		if spectator_name.is_empty():
			spectator_name = "旁观者"
		var item := Label.new()
		item.text = "• %s" % spectator_name
		UiStylesClass.apply_label_dark(item)
		_spectators_list_container.add_child(item)

func _refresh_allow_spectators_editable() -> void:
	if _room_config_editor == null or not is_instance_valid(_room_config_editor):
		return
	var room_status := str(_room_state.get("status", "")).strip_edges()
	var host_peer_id := int(_room_state.get("host_peer_id", 0))
	var can_edit := _local_peer_id > 0 and host_peer_id == _local_peer_id and room_status == "InGame" and not _allow_spectators_request_pending
	_room_config_editor.set_allow_spectators_editable(can_edit)

func _resolve_self_role() -> String:
	if _local_peer_id <= 0:
		return "-"
	if int(_room_state.get("host_peer_id", 0)) == _local_peer_id:
		return "房主"
	var self_seat_index := int(_room_state.get("self_seat_index", -1))
	if self_seat_index >= 0:
		return "玩家 %d" % (self_seat_index + 1)
	var self_role := str(_room_state.get("self_role", "")).strip_edges()
	if self_role == "spectator":
		return "观战者"
	if not self_role.is_empty():
		return self_role
	return "玩家"

func _on_room_config_changed() -> void:
	if _suppress_editor_changed:
		return
	if _room_config_editor == null or not is_instance_valid(_room_config_editor):
		return
	if _allow_spectators_request_pending:
		return
	var next_value: bool = bool(_room_config_editor.get_allow_spectators_value())
	var current_value := bool(_room_state.get("allow_spectators", true))
	if next_value == current_value:
		return
	allow_spectators_change_requested.emit(next_value)

func _grab_default_focus() -> void:
	if _close_button != null and is_instance_valid(_close_button):
		_close_button.grab_focus()

func _on_close_pressed() -> void:
	close()

func _set_status(message: String, is_error: bool) -> void:
	if _status_label == null or not is_instance_valid(_status_label):
		return
	_status_label.text = str(message).strip_edges()
	_status_label.visible = not _status_label.text.is_empty()
	if is_error:
		UiStylesClass.apply_label_error(_status_label)
	else:
		UiStylesClass.apply_label_hint_dark(_status_label)

func _clear_status() -> void:
	if _status_label == null or not is_instance_valid(_status_label):
		return
	_status_label.text = ""
	_status_label.visible = false

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey:
		var key_event: InputEventKey = event
		if key_event.pressed and not key_event.echo and key_event.keycode == KEY_ESCAPE:
			_on_close_pressed()
			get_viewport().set_input_as_handled()
