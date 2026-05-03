class_name ReserveCardsFullScreenView
extends Control

signal close_requested()
signal build_finished()

@onready var sections: GridContainer = $CenterContainer/MarginContainer/PanelContainer/MarginContainer2/VBoxContainer/ScrollContainer/Sections
@onready var loading_center: Control = $CenterContainer/MarginContainer/PanelContainer/MarginContainer2/VBoxContainer/LoadingCenter
@onready var scroll_container: ScrollContainer = $CenterContainer/MarginContainer/PanelContainer/MarginContainer2/VBoxContainer/ScrollContainer
@onready var close_button: Button = $CenterContainer/MarginContainer/PanelContainer/MarginContainer2/VBoxContainer/HeaderRow/CloseButton
@onready var title_label: Label = $CenterContainer/MarginContainer/PanelContainer/MarginContainer2/VBoxContainer/HeaderRow/TitleLabel
@onready var hint_label: Label = $CenterContainer/MarginContainer/PanelContainer/MarginContainer2/VBoxContainer/HeaderRow/HintLabel
@onready var panel_container: PanelContainer = $CenterContainer/MarginContainer/PanelContainer

const ReserveCardsViewDataClass = preload("res://ui/components/reserve_cards/reserve_cards_view_data.gd")
const UiStylesClass = preload("res://ui/utils/ui_styles.gd")

const PANEL_MIN_SIZE := Vector2(560, 420)
const PANEL_MAX_SIZE := Vector2(920, 680)
const VIEWPORT_MARGIN := 40.0
const PANEL_INNER_MARGIN := 40.0
const SCROLL_MIN_HEIGHT := 320.0
const SECTION_MIN_WIDTH := 244.0
const SECTION_GAP := 12.0
const CARD_ART_SIZE := Vector2(180, 280)
const CARD_ART_CORNER_RADIUS := 18

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
	if is_instance_valid(panel_container):
		panel_container.add_theme_stylebox_override("panel", _make_modal_panel_style())
	_apply_layout_constraints()
	_set_loading_visible(false)
	if not _opened:
		visible = false

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_apply_layout_constraints()
	if what == NOTIFICATION_VISIBILITY_CHANGED and visible:
		_apply_layout_constraints()

func set_viewer_player_id_override(viewer_player_id: int) -> void:
	_viewer_player_id_override = viewer_player_id

func clear_viewer_player_id_override() -> void:
	_viewer_player_id_override = -999

func open_with_state(state: GameState, focus_player_id: int = -1) -> void:
	_opened = true
	_focus_player_id = focus_player_id
	visible = true
	_apply_layout_constraints()
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

	var can_peek_all := false
	if state != null and state.players is Array and viewer_player_id >= 0 and viewer_player_id < state.players.size():
		var player_val = state.players[viewer_player_id]
		if player_val is Dictionary:
			var player: Dictionary = player_val
			can_peek_all = bool(player.get("can_peek_all_reserve_cards", false))

	if can_peek_all:
		hint_label.text = "已解锁：可查看全部玩家已选择的储备卡。ESC 关闭"
	else:
		hint_label.text = "所有玩家都可查看总览；未解锁时，他人的未公开储备卡显示为问号。ESC 关闭"

func _clear_sections() -> void:
	if not is_instance_valid(sections):
		return
	for child in sections.get_children():
		if is_instance_valid(child):
			child.free()

func _apply_layout_constraints() -> void:
	if not is_instance_valid(panel_container):
		return

	var viewport_size := get_viewport_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		viewport_size = Vector2(960, 640)

	var panel_w := maxf(PANEL_MIN_SIZE.x, minf(PANEL_MAX_SIZE.x, viewport_size.x - VIEWPORT_MARGIN))
	var panel_h := maxf(PANEL_MIN_SIZE.y, minf(PANEL_MAX_SIZE.y, viewport_size.y - VIEWPORT_MARGIN))
	panel_container.custom_minimum_size = Vector2(panel_w, panel_h)

	if is_instance_valid(scroll_container):
		var scroll_w := maxf(0.0, panel_w - PANEL_INNER_MARGIN)
		var scroll_h := maxf(SCROLL_MIN_HEIGHT, panel_h - 120.0)
		scroll_container.custom_minimum_size = Vector2(scroll_w, scroll_h)

	if is_instance_valid(sections):
		var usable_w := maxf(SECTION_MIN_WIDTH, panel_w - PANEL_INNER_MARGIN)
		var columns := int(floor((usable_w + SECTION_GAP) / (SECTION_MIN_WIDTH + SECTION_GAP)))
		sections.columns = maxi(1, mini(3, columns))

func _build_player_section(section_data: Dictionary) -> Control:
	var player_id := int(section_data.get("player_id", -1))
	var wrapper := VBoxContainer.new()
	wrapper.name = "PlayerSection%d" % player_id
	wrapper.custom_minimum_size = Vector2(220, 0)
	wrapper.add_theme_constant_override("separation", 8)

	var player_label := Label.new()
	player_label.name = "PlayerLabel"
	player_label.text = _player_display_name(player_id)
	player_label.add_theme_font_size_override("font_size", 15)
	player_label.add_theme_color_override("font_color", UiStylesClass.COLOR_TEXT_PRIMARY)
	wrapper.add_child(player_label)

	var cards_vbox := VBoxContainer.new()
	cards_vbox.name = "CardsVBox"
	cards_vbox.add_theme_constant_override("separation", 6)
	wrapper.add_child(cards_vbox)

	var cards_val = section_data.get("cards", [])
	if cards_val is Array:
		for card_entry_val in cards_val:
			if not (card_entry_val is Dictionary):
				continue
			cards_vbox.add_child(_build_card_panel(card_entry_val))

	return wrapper

func _build_card_panel(card_entry: Dictionary) -> Control:
	var visible_card := bool(card_entry.get("visible", false))
	var card_index := int(card_entry.get("index", -1))

	var card := VBoxContainer.new()
	card.name = "Card%d" % card_index if card_index >= 0 else "Card"
	card.custom_minimum_size = Vector2(220, CARD_ART_SIZE.y)
	card.add_theme_constant_override("separation", 4)

	if visible_card:
		var image := _build_card_image(str(card_entry.get("image_path", "")).strip_edges())
		if image != null:
			card.add_child(image)
		else:
			card.add_child(_build_card_missing_art())
	else:
		card.add_child(_build_card_hidden_art())

	var title := Label.new()
	title.name = "TitleLabel"
	title.text = str(card_entry.get("title", "")).strip_edges()
	title.visible = false
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", UiStylesClass.COLOR_TEXT_PRIMARY if visible_card else UiStylesClass.COLOR_TEXT_MUTED)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD
	title.max_lines_visible = 1
	card.add_child(title)

	var desc := Label.new()
	desc.name = "DescLabel"
	desc.text = str(card_entry.get("desc", "")).strip_edges()
	desc.visible = false
	desc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD
	desc.add_theme_font_size_override("font_size", 12)
	desc.add_theme_color_override("font_color", UiStylesClass.COLOR_TEXT_MUTED)
	desc.max_lines_visible = 2
	card.add_child(desc)

	return card

func _build_card_image(image_path: String) -> TextureRect:
	if image_path.is_empty():
		return null
	var loaded = load(image_path)
	if not (loaded is Texture2D):
		return null

	var image := TextureRect.new()
	image.name = "CardImage"
	image.custom_minimum_size = CARD_ART_SIZE
	image.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	image.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.texture = loaded as Texture2D
	return image

func _build_card_hidden_art() -> Control:
	var panel := PanelContainer.new()
	panel.name = "HiddenCardArt"
	panel.custom_minimum_size = CARD_ART_SIZE
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _make_hidden_card_style())

	var center := CenterContainer.new()
	center.name = "HiddenQuestionCenter"
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(center)

	var question := Label.new()
	question.name = "HiddenQuestionLabel"
	question.text = "?"
	question.add_theme_font_size_override("font_size", 72)
	question.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	center.add_child(question)
	return panel

func _build_card_missing_art() -> Control:
	var center := CenterContainer.new()
	center.name = "MissingCardArt"
	center.custom_minimum_size = CARD_ART_SIZE
	center.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	center.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var label := Label.new()
	label.name = "MissingCardLabel"
	label.text = str("卡图缺失")
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", UiStylesClass.COLOR_TEXT_MUTED)
	center.add_child(label)
	return center

func _make_modal_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.98, 0.96, 0.90, 1.0)
	style.border_color = Color(0.35, 0.29, 0.18, 0.3)
	style.set_border_width_all(1)
	style.set_corner_radius_all(16)
	style.shadow_color = Color(0, 0, 0, 0.25)
	style.shadow_size = 12
	style.shadow_offset = Vector2(0, 4)
	return style

func _make_hidden_card_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.015, 0.015, 0.015, 1.0)
	style.set_corner_radius_all(CARD_ART_CORNER_RADIUS)
	return style

func _player_display_name(player_id: int) -> String:
	if player_id >= 0 and Globals != null and Globals.has_method("get_player_name"):
		var name := str(Globals.get_player_name(player_id)).strip_edges()
		if not name.is_empty():
			return name
	if player_id >= 0:
		return "玩家 %d" % (player_id + 1)
	return "玩家 ?"
