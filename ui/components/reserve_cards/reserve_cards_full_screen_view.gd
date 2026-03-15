class_name ReserveCardsFullScreenView
extends Control

signal close_requested()
signal build_finished()

@onready var sections: VBoxContainer = $MarginContainer/VBoxContainer/ScrollContainer/Sections
@onready var loading_center: Control = $MarginContainer/VBoxContainer/LoadingCenter
@onready var scroll_container: ScrollContainer = $MarginContainer/VBoxContainer/ScrollContainer
@onready var close_button: Button = $MarginContainer/VBoxContainer/HeaderRow/CloseButton
@onready var title_label: Label = $MarginContainer/VBoxContainer/HeaderRow/TitleLabel
@onready var hint_label: Label = $MarginContainer/VBoxContainer/HeaderRow/HintLabel

const ReserveCardsViewDataClass = preload("res://ui/components/reserve_cards/reserve_cards_view_data.gd")
const UiStylesClass = preload("res://ui/utils/ui_styles.gd")

var _opened: bool = false
var _viewer_player_id_override: int = -999
var _focus_player_id: int = -1

func _ready() -> void:
	set_process_unhandled_input(true)
	if is_instance_valid(close_button):
		close_button.pressed.connect(_on_close_pressed)
		UiStylesClass.apply_button_secondary(close_button)
	if is_instance_valid(title_label):
		title_label.add_theme_color_override("font_color", UiStylesClass.COLOR_TEXT_PRIMARY)
	if is_instance_valid(hint_label):
		hint_label.add_theme_color_override("font_color", UiStylesClass.COLOR_TEXT_MUTED)
	_set_loading_visible(false)
	if not _opened:
		visible = false

func set_viewer_player_id_override(viewer_player_id: int) -> void:
	_viewer_player_id_override = viewer_player_id

func clear_viewer_player_id_override() -> void:
	_viewer_player_id_override = -999

func open_with_state(state: GameState, focus_player_id: int = -1) -> void:
	_opened = true
	_focus_player_id = focus_player_id
	visible = true
	_rebuild_from_state(state)

func request_close() -> void:
	if not visible:
		return
	visible = false
	close_requested.emit()

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event != null and event.is_action_pressed("ui_cancel"):
		accept_event()
		request_close()

func _on_close_pressed() -> void:
	request_close()

func _set_loading_visible(loading: bool) -> void:
	if is_instance_valid(loading_center):
		loading_center.visible = loading
	if is_instance_valid(scroll_container):
		scroll_container.visible = not loading

func _rebuild_from_state(state: GameState) -> void:
	_set_loading_visible(true)
	_clear_sections()

	if state == null:
		_set_loading_visible(false)
		build_finished.emit()
		return

	var viewer_id := _viewer_player_id_override
	if viewer_id == -999:
		viewer_id = ReserveCardsViewDataClass.resolve_viewer_player_id(state)

	var sections_data := ReserveCardsViewDataClass.build_player_sections(state, viewer_id)
	_update_header_text(state, viewer_id)

	for section_data in sections_data:
		var section := _build_player_section(section_data)
		if section != null:
			sections.add_child(section)

	_set_loading_visible(false)
	build_finished.emit()

func _update_header_text(state: GameState, viewer_player_id: int) -> void:
	if not is_instance_valid(title_label) or not is_instance_valid(hint_label):
		return

	title_label.text = "储备卡总览"
	if _focus_player_id >= 0:
		title_label.text += "｜%s" % _player_display_name(_focus_player_id)

	var can_peek_all := false
	if state != null and state.players is Array and viewer_player_id >= 0 and viewer_player_id < state.players.size():
		var player_val = state.players[viewer_player_id]
		if player_val is Dictionary:
			var player: Dictionary = player_val
			can_peek_all = bool(player.get("can_peek_all_reserve_cards", false))

	if can_peek_all:
		hint_label.text = "已解锁：可查看全部玩家已选择的储备卡。ESC 关闭"
	else:
		hint_label.text = "仅显示你自己的已选储备卡，或其他玩家已公开的已选项。ESC 关闭"

func _clear_sections() -> void:
	if not is_instance_valid(sections):
		return
	for child in sections.get_children():
		if is_instance_valid(child):
			child.free()

func _build_player_section(section_data: Dictionary) -> Control:
	var player_id := int(section_data.get("player_id", -1))
	var wrapper := PanelContainer.new()
	wrapper.name = "PlayerSection%d" % player_id
	wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrapper.add_theme_stylebox_override("panel", _make_section_style(player_id == _focus_player_id))

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_bottom", 14)
	wrapper.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	vbox.add_child(header)

	var player_label := Label.new()
	player_label.name = "PlayerLabel"
	player_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	player_label.text = _player_display_name(player_id)
	player_label.add_theme_font_size_override("font_size", 18)
	player_label.add_theme_color_override("font_color", UiStylesClass.COLOR_TEXT_PRIMARY)
	header.add_child(player_label)

	var selection_label := Label.new()
	selection_label.name = "SelectionLabel"
	selection_label.text = str(section_data.get("selection_text", "")).strip_edges()
	selection_label.add_theme_font_size_override("font_size", 12)
	selection_label.add_theme_color_override("font_color", UiStylesClass.COLOR_TEXT_MUTED)
	header.add_child(selection_label)

	var cards_row := HBoxContainer.new()
	cards_row.name = "CardsRow"
	cards_row.add_theme_constant_override("separation", 12)
	vbox.add_child(cards_row)

	var cards_val = section_data.get("cards", [])
	if cards_val is Array:
		for card_entry_val in cards_val:
			if not (card_entry_val is Dictionary):
				continue
			cards_row.add_child(_build_card_panel(card_entry_val))

	return wrapper

func _build_card_panel(card_entry: Dictionary) -> Control:
	var visible_card := bool(card_entry.get("visible", false))
	var selected := bool(card_entry.get("selected", false))
	var card_index := int(card_entry.get("index", -1))

	var panel := PanelContainer.new()
	panel.name = "Card%d" % card_index if card_index >= 0 else "Card"
	panel.custom_minimum_size = Vector2(220, 132)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _make_card_style(visible_card, selected))

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	var title := Label.new()
	title.name = "TitleLabel"
	title.text = str(card_entry.get("title", "")).strip_edges()
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", UiStylesClass.COLOR_TEXT_PRIMARY if visible_card else UiStylesClass.COLOR_TEXT_MUTED)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(title)

	var desc := Label.new()
	desc.name = "DescLabel"
	desc.text = str(card_entry.get("desc", "")).strip_edges()
	desc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD
	desc.add_theme_font_size_override("font_size", 13)
	desc.add_theme_color_override("font_color", UiStylesClass.COLOR_TEXT_MUTED)
	vbox.add_child(desc)

	var footer := Label.new()
	footer.name = "FooterLabel"
	footer.add_theme_font_size_override("font_size", 12)
	if selected:
		footer.text = "已选择"
		footer.add_theme_color_override("font_color", Color(0.18, 0.52, 0.26, 1.0))
	elif not visible_card:
		footer.text = "未公开"
		footer.add_theme_color_override("font_color", UiStylesClass.COLOR_TEXT_MUTED)
	else:
		footer.text = ""
	vbox.add_child(footer)

	return panel

func _make_section_style(highlighted: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.98, 0.95, 0.88, 0.98) if highlighted else Color(0.97, 0.94, 0.86, 0.96)
	style.border_color = Color(0.35, 0.29, 0.18, 0.45) if highlighted else Color(0.35, 0.29, 0.18, 0.18)
	style.set_border_width_all(2 if highlighted else 1)
	style.set_corner_radius_all(12)
	return style

func _make_card_style(visible_card: bool, selected: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.set_corner_radius_all(10)
	if not visible_card:
		style.bg_color = Color(0.91, 0.88, 0.82, 0.9)
		style.border_color = Color(0.48, 0.43, 0.36, 0.28)
		style.set_border_width_all(1)
		return style

	style.bg_color = Color(1.0, 0.985, 0.95, 0.98)
	style.border_color = Color(0.35, 0.29, 0.18, 0.18)
	style.set_border_width_all(1)
	if selected:
		style.bg_color = Color(0.94, 0.98, 0.92, 0.98)
		style.border_color = Color(0.20, 0.50, 0.26, 0.65)
		style.set_border_width_all(2)
	return style

func _player_display_name(player_id: int) -> String:
	if player_id >= 0 and Globals != null and Globals.has_method("get_player_name"):
		var name := str(Globals.get_player_name(player_id)).strip_edges()
		if not name.is_empty():
			return name
	if player_id >= 0:
		return "玩家 %d" % (player_id + 1)
	return "玩家 ?"
