class_name TutorialCampaignScene
extends Control

const UiStylesClass = preload("res://ui/utils/ui_styles.gd")

const BANK_BREAK_PANEL_SCENE_PATH := "res://ui/components/bank_break/bank_break_panel.tscn"
const RESERVE_CARD_ART_SIZE := Vector2(140, 218)
const MAP_PREVIEW_SIZE := Vector2(680, 380)
const MAP_SELECTED_FILL := Color(0.95, 0.25, 0.18, 0.22)
const MAP_SELECTED_BORDER := Color(0.80, 0.18, 0.12, 0.92)
const MAP_VALID_FILL := Color(0.20, 0.75, 0.36, 0.20)
const MAP_VALID_BORDER := Color(0.20, 0.62, 0.28, 0.92)
const MAP_DISTANCE_FILL := Color(0.97, 0.73, 0.18, 0.42)
const MAP_DISTANCE_BORDER := Color(0.65, 0.38, 0.05, 0.95)

const FALLBACK_RESERVE_CARDS := [
	{"cash": 50, "ceo_slots": 2},
	{"cash": 100, "ceo_slots": 3},
	{"cash": 150, "ceo_slots": 4},
]

class RealAssetMapPreview:
	extends Control

	const CELL_SIZE := 54
	const GRID_SIZE := Vector2i(10, 5)
	const GROUND_TEXTURE_PATH := "res://modules/base_tiles/assets/map/ground/ground.png"
	const ROAD_STRAIGHT_TEXTURE_PATH := "res://modules/base_tiles/assets/map/roads/road_straight_new.png"
	const ROAD_CROSS_TEXTURE_PATH := "res://modules/base_tiles/assets/map/roads/road_cross_new.png"
	const RESTAURANT_TEXTURE_PATH := "res://modules/base_pieces/assets/map/pieces/restaurant.png"
	const HOUSE_WITH_GARDEN_TEXTURE_PATH := "res://modules/base_pieces/assets/map/pieces/house_with_garden.png"
	const RESTAURANT_LOGOS := [
		"res://modules/base_pieces/assets/map/logos/fried_geese_donkey.png",
		"res://modules/base_pieces/assets/map/logos/gluttony_inc_burgers.png",
		"res://modules/base_pieces/assets/map/logos/golden_duck_diner.png",
		"res://modules/base_pieces/assets/map/logos/santa_maria_pizza.png",
	]

	var preview_state: Dictionary = {}
	var preview_options: Dictionary = {}
	var textures: Dictionary = {}

	func setup(state_data: Dictionary, options: Dictionary) -> void:
		preview_state = state_data.duplicate(true)
		preview_options = options.duplicate(true)
		custom_minimum_size = Vector2(GRID_SIZE.x * CELL_SIZE, GRID_SIZE.y * CELL_SIZE)
		size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_load_textures()
		queue_redraw()

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _load_textures() -> void:
		textures["ground"] = _load_texture_raw(GROUND_TEXTURE_PATH)
		textures["road_straight"] = _load_texture_raw(ROAD_STRAIGHT_TEXTURE_PATH)
		textures["road_cross"] = _load_texture_raw(ROAD_CROSS_TEXTURE_PATH)
		textures["restaurant"] = _load_texture_raw(RESTAURANT_TEXTURE_PATH)
		textures["house_with_garden"] = _load_texture_raw(HOUSE_WITH_GARDEN_TEXTURE_PATH)
		for i in range(RESTAURANT_LOGOS.size()):
			textures["logo_%d" % i] = _load_texture_raw(str(RESTAURANT_LOGOS[i]))

	static func _load_texture_raw(path: String) -> Texture2D:
		var raw_path := ProjectSettings.globalize_path(path) if path.begins_with("res://") else path
		var img := Image.load_from_file(raw_path)
		if img == null or img.is_empty():
			return null
		return ImageTexture.create_from_image(img)

	func _draw() -> void:
		_draw_cells()
		_draw_tile_boundary()
		_draw_houses()
		_draw_option_overlays()
		_draw_restaurants()
		_draw_structure_preview()

	func _draw_cells() -> void:
		for y in range(GRID_SIZE.y):
			for x in range(GRID_SIZE.x):
				var rect := _cell_rect(Vector2i(x, y))
				var ground: Texture2D = textures.get("ground", null)
				if ground != null:
					draw_texture_rect(ground, rect, false)
				else:
					draw_rect(rect, Color(0.95, 0.91, 0.80, 1.0), true)
				_draw_road_if_needed(Vector2i(x, y), rect)
				draw_rect(rect, Color(0.17, 0.13, 0.09, 0.14), false, 1.0)

	func _draw_road_if_needed(pos: Vector2i, rect: Rect2) -> void:
		var is_horizontal := pos.y == 2
		var is_vertical := pos.x == 2 or pos.x == 7
		if not is_horizontal and not is_vertical:
			return
		var tex: Texture2D = textures.get("road_cross" if is_horizontal and is_vertical else "road_straight", null)
		if tex == null:
			draw_rect(rect.grow(-8), Color(0.42, 0.40, 0.35, 1.0), true)
			return
		if is_vertical and not is_horizontal:
			var center := rect.position + rect.size * 0.5
			draw_set_transform(center, deg_to_rad(90.0), Vector2.ONE)
			draw_texture_rect(tex, Rect2(-rect.size * 0.5, rect.size), false)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		else:
			draw_texture_rect(tex, rect, false)

	func _draw_tile_boundary() -> void:
		var x := float(5 * CELL_SIZE)
		draw_line(Vector2(x, 0), Vector2(x, GRID_SIZE.y * CELL_SIZE), Color(0.17, 0.13, 0.09, 0.75), 4.0)

	func _draw_option_overlays() -> void:
		var overlays_val = preview_options.get("overlays", [])
		if not (overlays_val is Array):
			return
		for overlay_val in overlays_val:
			if not (overlay_val is Dictionary):
				continue
			var overlay: Dictionary = overlay_val
			var style: Dictionary = overlay.get("style", {})
			var fill: Color = style.get("fill", Color(1, 1, 1, 0))
			var border: Color = style.get("border", Color(1, 1, 1, 0))
			var border_width := float(style.get("border_width", 2.0))
			var cells_val = overlay.get("cells", [])
			if not (cells_val is Array):
				continue
			for cell_val in cells_val:
				if cell_val is Vector2i:
					var cell_pos: Vector2i = cell_val
					var rect := _cell_rect(cell_pos)
					draw_rect(rect, fill, true)
					draw_rect(rect, border, false, border_width)

	func _draw_restaurants() -> void:
		var restaurants_val = preview_state.get("restaurants", [])
		if not (restaurants_val is Array):
			return
		for restaurant_val in restaurants_val:
			if not (restaurant_val is Dictionary):
				continue
			var restaurant: Dictionary = restaurant_val
			_draw_restaurant(
				restaurant.get("anchor", Vector2i.ZERO),
				int(restaurant.get("owner", 0)),
				Color(1, 1, 1, 1),
				true
			)

	func _draw_houses() -> void:
		var houses_val = preview_state.get("houses", [])
		if not (houses_val is Array):
			return
		for house_val in houses_val:
			if not (house_val is Dictionary):
				continue
			var house: Dictionary = house_val
			_draw_house(house.get("anchor", Vector2i.ZERO))

	func _draw_structure_preview() -> void:
		var preview_val = preview_options.get("structure_preview", null)
		if not (preview_val is Dictionary):
			return
		var preview: Dictionary = preview_val
		var info: Dictionary = preview.get("info", {})
		var anchor: Vector2i = info.get("anchor", Vector2i.ZERO)
		var owner := int(info.get("owner", 0))
		var valid := bool(preview.get("valid", true))
		_draw_restaurant(anchor, owner, Color(1, 1, 1, 0.72), valid)

	func _draw_restaurant(anchor_val, owner: int, modulate: Color, valid: bool) -> void:
		var anchor: Vector2i = anchor_val if anchor_val is Vector2i else Vector2i.ZERO
		var rect := Rect2(Vector2(anchor.x * CELL_SIZE, anchor.y * CELL_SIZE), Vector2(CELL_SIZE * 2, CELL_SIZE * 2))
		draw_rect(Rect2(rect.position + Vector2(4, 4), rect.size), Color(0, 0, 0, 0.22 * modulate.a), true)
		var restaurant: Texture2D = textures.get("restaurant", null)
		if restaurant != null:
			draw_texture_rect(restaurant, rect, false, modulate)
		else:
			draw_rect(rect, Color(0.96, 0.91, 0.78, 0.96 * modulate.a), true)
		draw_rect(rect, Color(0.17, 0.13, 0.09, 0.75 * modulate.a), false, 2.0)
		var logo: Texture2D = textures.get("logo_%d" % abs(owner % RESTAURANT_LOGOS.size()), null)
		if logo != null:
			draw_texture_rect(logo, rect.grow(-30), false, modulate)
		_draw_entrance_marker(_cell_rect(anchor), modulate.a)
		if not valid:
			draw_rect(rect, Color(0.84, 0.12, 0.10, 0.22), true)
			draw_rect(rect, Color(0.84, 0.12, 0.10, 0.95), false, 4.0)

	func _draw_house(anchor_val) -> void:
		var anchor: Vector2i = anchor_val if anchor_val is Vector2i else Vector2i.ZERO
		var rect := Rect2(Vector2(anchor.x * CELL_SIZE, anchor.y * CELL_SIZE), Vector2(CELL_SIZE * 2, CELL_SIZE * 2))
		draw_rect(Rect2(rect.position + Vector2(3, 3), rect.size), Color(0, 0, 0, 0.16), true)
		var house: Texture2D = textures.get("house_with_garden", null)
		if house != null:
			draw_texture_rect(house, rect, false)
		else:
			draw_rect(rect, Color(0.78, 0.23, 0.18, 1.0), true)
		draw_rect(rect, Color(0.17, 0.13, 0.09, 0.45), false, 1.5)

	func _draw_entrance_marker(rect: Rect2, alpha: float) -> void:
		var col := Color(0, 0, 0, 0.88 * alpha)
		var pad := 8.0
		var length := 18.0
		var thickness := 4.0
		draw_rect(Rect2(rect.position + Vector2(pad, pad), Vector2(length, thickness)), col, true)
		draw_rect(Rect2(rect.position + Vector2(pad, pad), Vector2(thickness, length)), col, true)

	func _cell_rect(pos: Vector2i) -> Rect2:
		return Rect2(Vector2(pos.x * CELL_SIZE, pos.y * CELL_SIZE), Vector2(CELL_SIZE, CELL_SIZE))

const LESSONS := [
	{
		"id": "reserve_bank",
		"title": "1. 储备卡、银行和正式局目标",
		"kicker": "开局 Setup",
		"summary": "开局选择储备卡不是获得现金，而是在银行第一次破产时决定备用规则。正式规则通常在第二次破产后的晚餐结束时终局。",
		"goals": [
			"阅读三张储备卡效果",
			"确认选择后不可更改",
			"看到第一次破产继续游戏，第二次破产结束游戏",
		],
	},
	{
		"id": "initial_restaurant",
		"title": "2. 起始餐厅放置",
		"kicker": "入口与板块",
		"summary": "起始餐厅必须入口邻接道路；起始放置阶段还要求每个地图板块最多只有一个餐厅入口。这个限制看入口所在板块，不看整个餐厅占地。",
		"goals": [
			"识别餐厅占地和入口角",
			"看到入口不邻接道路的非法原因",
			"看到入口所在板块冲突的非法原因",
			"完成一个入口邻路且入口板块不冲突的合法放置",
		],
	},
	{
		"id": "distance",
		"title": "3. 距离不是格子数",
		"kicker": "地图距离",
		"summary": "游戏里的道路距离以跨越地图板块边界的次数为主。道路步数只是辅助信息，不等于晚餐选店里使用的距离。",
		"goals": [
			"比较同板块长路线和跨板块短路线",
			"看到同板块内绕路仍可能距离为 0",
			"看到跨过板块边界后距离增加",
		],
	},
	{
		"id": "bankruptcy",
		"title": "4. 第一次破产与第二次破产",
		"kicker": "经济终局",
		"summary": "银行支付不足或支付后刚好耗尽会触发破产。第一次破产揭示储备卡并注资；第二次破产允许透支完成当前晚餐，然后跳过 Payday 进入终局。",
		"goals": [
			"触发第一次破产并查看储备卡揭示",
			"确认第一次破产不是游戏结束",
			"触发第二次破产并看到晚餐后终局",
		],
	},
]

var _sidebar: VBoxContainer = null
var _lesson_title_label: Label = null
var _lesson_kicker_label: Label = null
var _lesson_summary_label: RichTextLabel = null
var _content_body: VBoxContainer = null
var _prev_button: Button = null
var _next_button: Button = null
var _lesson_buttons: Array[Button] = []

var _selected_lesson: int = 0
var _selected_reserve_index: int = 1
var _reserve_break_revealed: bool = false
var _placement_case: String = "no_road"
var _distance_case: String = "same_board"
var _bankruptcy_step: int = 0

func _ready() -> void:
	GameLog.info("TutorialCampaign", "教学战役已加载")
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, 0)
	_build_shell()
	_select_lesson(0)

func _build_shell() -> void:
	var bg := ColorRect.new()
	bg.name = "WallBackground"
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, 0)
	bg.color = Color(0.90, 0.86, 0.75, 1.0)
	add_child(bg)
	UiStylesClass.apply_tiled_texture(bg, UiStylesClass.WALL_TEXTURE_PATHS, 3.0, Color(0.90, 0.86, 0.75, 1.0))

	var vignette := ColorRect.new()
	vignette.name = "VignetteOverlay"
	vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, 0)
	add_child(vignette)
	UiStylesClass.apply_vignette(vignette, 0.25, 0.5)

	var margin := MarginContainer.new()
	margin.name = "RootMargin"
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, 0)
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_bottom", 24)
	add_child(margin)

	var root := HBoxContainer.new()
	root.name = "RootLayout"
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 18)
	margin.add_child(root)

	root.add_child(_build_sidebar_panel())
	root.add_child(_build_content_panel())

func _build_sidebar_panel() -> Control:
	var panel := PanelContainer.new()
	panel.name = "LessonSidebarPanel"
	panel.custom_minimum_size = Vector2(310, 0)
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	UiStylesClass.apply_panel_poster(panel)

	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 16)
	pad.add_theme_constant_override("margin_top", 16)
	pad.add_theme_constant_override("margin_right", 16)
	pad.add_theme_constant_override("margin_bottom", 16)
	panel.add_child(pad)

	_sidebar = VBoxContainer.new()
	_sidebar.add_theme_constant_override("separation", 10)
	pad.add_child(_sidebar)

	var title := Label.new()
	title.text = "教学战役"
	title.add_theme_font_size_override("font_size", 28)
	UiStylesClass.apply_label_dark(title)
	_sidebar.add_child(title)

	var hint := Label.new()
	hint.text = "前四关原型"
	hint.add_theme_font_size_override("font_size", 15)
	UiStylesClass.apply_label_hint_dark(hint)
	_sidebar.add_child(hint)

	var separator := HSeparator.new()
	_sidebar.add_child(separator)

	for i in range(LESSONS.size()):
		var lesson: Dictionary = LESSONS[i]
		var btn := Button.new()
		btn.text = str(lesson.get("title", "关卡"))
		btn.custom_minimum_size = Vector2(0, 48)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.pressed.connect(_select_lesson.bind(i))
		UiStylesClass.apply_button_secondary(btn)
		_lesson_buttons.append(btn)
		_sidebar.add_child(btn)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_sidebar.add_child(spacer)

	var back := Button.new()
	back.text = "返回主菜单"
	back.custom_minimum_size = Vector2(0, 48)
	back.pressed.connect(_on_back_pressed)
	UiStylesClass.apply_button_secondary(back)
	_sidebar.add_child(back)

	return panel

func _build_content_panel() -> Control:
	var panel := PanelContainer.new()
	panel.name = "LessonContentPanel"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	UiStylesClass.apply_panel_poster_alt(panel)

	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 24)
	pad.add_theme_constant_override("margin_top", 20)
	pad.add_theme_constant_override("margin_right", 24)
	pad.add_theme_constant_override("margin_bottom", 20)
	panel.add_child(pad)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	pad.add_child(vbox)

	_lesson_kicker_label = Label.new()
	_lesson_kicker_label.add_theme_font_size_override("font_size", 15)
	UiStylesClass.apply_label_hint_dark(_lesson_kicker_label)
	vbox.add_child(_lesson_kicker_label)

	_lesson_title_label = Label.new()
	_lesson_title_label.add_theme_font_size_override("font_size", 30)
	_lesson_title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiStylesClass.apply_label_dark(_lesson_title_label)
	vbox.add_child(_lesson_title_label)

	_lesson_summary_label = _make_rich_text("", 70)
	vbox.add_child(_lesson_summary_label)

	var scroll := ScrollContainer.new()
	scroll.name = "LessonScroll"
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	_content_body = VBoxContainer.new()
	_content_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content_body.add_theme_constant_override("separation", 14)
	scroll.add_child(_content_body)

	var nav := HBoxContainer.new()
	nav.add_theme_constant_override("separation", 10)
	vbox.add_child(nav)

	_prev_button = Button.new()
	_prev_button.text = "上一关"
	_prev_button.custom_minimum_size = Vector2(140, 44)
	_prev_button.pressed.connect(_on_prev_pressed)
	UiStylesClass.apply_button_secondary(_prev_button)
	nav.add_child(_prev_button)

	var nav_spacer := Control.new()
	nav_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nav.add_child(nav_spacer)

	_next_button = Button.new()
	_next_button.text = "下一关"
	_next_button.custom_minimum_size = Vector2(140, 44)
	_next_button.pressed.connect(_on_next_pressed)
	UiStylesClass.apply_button_primary(_next_button)
	nav.add_child(_next_button)

	return panel

func _select_lesson(index: int) -> void:
	_selected_lesson = clampi(index, 0, LESSONS.size() - 1)
	for i in range(_lesson_buttons.size()):
		var btn := _lesson_buttons[i]
		btn.disabled = i == _selected_lesson
		if i == _selected_lesson:
			btn.text = "▶ %s" % str(LESSONS[i].get("title", "关卡"))
		else:
			btn.text = str(LESSONS[i].get("title", "关卡"))
	_render_lesson()

func _render_lesson() -> void:
	var lesson: Dictionary = LESSONS[_selected_lesson]
	_lesson_kicker_label.text = str(lesson.get("kicker", ""))
	_lesson_title_label.text = str(lesson.get("title", ""))
	_lesson_summary_label.text = str(lesson.get("summary", ""))
	_prev_button.disabled = _selected_lesson <= 0
	_next_button.disabled = _selected_lesson >= LESSONS.size() - 1

	_clear_content_body()
	_add_goals_card(Array(lesson.get("goals", [])))
	match str(lesson.get("id", "")):
		"reserve_bank":
			_render_reserve_lesson()
		"initial_restaurant":
			_render_initial_restaurant_lesson()
		"distance":
			_render_distance_lesson()
		"bankruptcy":
			_render_bankruptcy_lesson()

func _clear_content_body() -> void:
	for child in _content_body.get_children():
		_content_body.remove_child(child)
		child.queue_free()

func _add_goals_card(goals: Array) -> void:
	var card := _make_section("本关目标")
	var text := ""
	for i in range(goals.size()):
		text += "%d. %s\n" % [i + 1, str(goals[i])]
	card.add_child(_make_rich_text(text.strip_edges(), 110))
	_content_body.add_child(card)

func _render_reserve_lesson() -> void:
	var card := _make_section("储备卡选择")

	var row := HBoxContainer.new()
	row.name = "ReserveCardArtRow"
	row.add_theme_constant_override("separation", 12)
	card.add_child(row)

	var reserve_cards := _get_reserve_cards()
	for i in range(reserve_cards.size()):
		var reserve: Dictionary = reserve_cards[i]
		row.add_child(_build_reserve_card_choice(reserve, i, i == _selected_reserve_index))

	var selected_details := _describe_reserve_card(_selected_reserve_index)
	card.add_child(_make_label(
		"当前选择：%s。确认后不可更改；它不会立刻给你现金。" % str(selected_details.get("summary", "")),
		15,
		UiStylesClass.COLOR_TEXT_PRIMARY
	))
	var demo_button := Button.new()
	demo_button.text = "演示第一次破产揭示"
	demo_button.custom_minimum_size = Vector2(240, 44)
	demo_button.pressed.connect(_on_reveal_reserve_break_pressed)
	UiStylesClass.apply_button_primary(demo_button)
	card.add_child(demo_button)
	if _reserve_break_revealed:
		card.add_child(_build_bank_break_preview(1, 15, 165, _build_first_break_event_data()))
	_content_body.add_child(card)

func _render_initial_restaurant_lesson() -> void:
	var controls := _make_segmented_row([
		{"id": "no_road", "label": "入口无路"},
		{"id": "same_board", "label": "入口板块冲突"},
		{"id": "valid", "label": "合法放置"},
	], _placement_case, Callable(self, "_on_placement_case_selected"))
	_content_body.add_child(controls)

	var card := _make_section("起始放置演示")
	var preview_state = _build_restaurant_preview_state(_placement_case)
	card.add_child(_build_real_map_preview(preview_state, _build_restaurant_preview_options(_placement_case)))
	card.add_child(_make_rich_text(_get_placement_explanation(_placement_case), 120))
	_content_body.add_child(card)

func _render_distance_lesson() -> void:
	var controls := _make_segmented_row([
		{"id": "same_board", "label": "同板块长路线"},
		{"id": "cross_board", "label": "跨板块短路线"},
	], _distance_case, Callable(self, "_on_distance_case_selected"))
	_content_body.add_child(controls)

	var card := _make_section("距离工具演示")
	var preview_state = _build_distance_preview_state(_distance_case)
	card.add_child(_build_real_map_preview(preview_state, _build_distance_preview_options(_distance_case)))
	if _distance_case == "same_board":
		card.add_child(_make_rich_text("同板块长路线：道路步数 8，但没有跨过地图板块边界，所以规则距离 = 0。\n\n这就是为什么距离不能理解成格子数。晚餐选店使用的是跨板块次数。", 130))
	else:
		card.add_child(_make_rich_text("跨板块短路线：道路步数 3，但路径穿过 1 次板块边界，所以规则距离 = 1。\n\n如果两家餐厅价格相同，这 1 点距离就可能改变房屋选择。", 130))
	_content_body.add_child(card)

func _render_bankruptcy_lesson() -> void:
	var card := _make_section("破产流程演示")
	card.add_child(_make_label(_get_bankruptcy_status_text(), 16, UiStylesClass.COLOR_TEXT_PRIMARY))
	if _bankruptcy_step >= 4:
		card.add_child(_build_bank_break_preview(2, 5, -25, _build_second_break_event_data()))
	elif _bankruptcy_step >= 2:
		card.add_child(_build_bank_break_preview(1, 15, 165, _build_first_break_event_data()))
	card.add_child(_build_bankruptcy_timeline())
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var reset := Button.new()
	reset.text = "重置"
	reset.custom_minimum_size = Vector2(120, 42)
	reset.pressed.connect(_on_bankruptcy_reset_pressed)
	UiStylesClass.apply_button_secondary(reset)
	row.add_child(reset)
	var next := Button.new()
	next.text = "推进一步"
	next.custom_minimum_size = Vector2(160, 42)
	next.disabled = _bankruptcy_step >= 4
	next.pressed.connect(_on_bankruptcy_next_pressed)
	UiStylesClass.apply_button_primary(next)
	row.add_child(next)
	card.add_child(row)
	_content_body.add_child(card)

func _get_reserve_cards() -> Array[Dictionary]:
	var fallback: Array[Dictionary] = []
	for card_val in FALLBACK_RESERVE_CARDS:
		if card_val is Dictionary:
			fallback.append((card_val as Dictionary).duplicate(true))
	return fallback

func _get_reserve_card(index: int) -> Dictionary:
	var cards := _get_reserve_cards()
	if cards.is_empty():
		return {}
	var idx := clampi(index, 0, cards.size() - 1)
	return cards[idx]

func _describe_reserve_card(index: int) -> Dictionary:
	return _describe_reserve_card_data(_get_reserve_card(index), index)

func _describe_reserve_card_data(card_data: Dictionary, index: int) -> Dictionary:
	var cash := int(card_data.get("cash", 0))
	var slots := int(card_data.get("ceo_slots", 0))
	if cash > 0 and slots > 0:
		return {
			"index": index,
			"title": "已选储备卡",
			"desc": "首次破产注资：+$%d\n首次破产后 CEO 卡槽：%d" % [cash, slots],
			"summary": "选项#%d，首次破产注资 $%d，CEO 槽位 %d" % [index + 1, cash, slots],
			"image_path": "res://assets/images/reserve_cards/reserve_%d.png" % (index + 2),
		}
	var price := int(card_data.get("type", 0))
	return {
		"index": index,
		"title": "已选储备卡",
		"desc": "基础单价候选：$%d\n首次破产后按多数决定" % price,
		"summary": "选项#%d，基础单价候选 $%d" % [index + 1, price],
		"image_path": "res://assets/images/reserve_cards/reserve_%d.png" % (index + 2),
	}

func _build_reserve_card_choice(card_data: Dictionary, index: int, selected: bool) -> Control:
	var details := _describe_reserve_card_data(card_data, index)
	var panel := PanelContainer.new()
	panel.name = "ReserveCardChoice%d" % (index + 1)
	panel.custom_minimum_size = Vector2(190, 0)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.gui_input.connect(_on_reserve_card_choice_input.bind(index))
	var border := Color(0.17, 0.13, 0.09, 0.24)
	var border_width := 1
	if selected:
		border = Color(0.73, 0.23, 0.18, 0.92)
		border_width = 3
	panel.add_theme_stylebox_override("panel", _make_style(Color(0.96, 0.92, 0.82, 0.92), border, border_width, 6))

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	vbox.add_child(_build_reserve_card_art(str(details.get("image_path", ""))))

	var title := Label.new()
	title.text = "选项 %d" % (index + 1)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 15)
	UiStylesClass.apply_label_dark(title)
	vbox.add_child(title)

	var desc := Label.new()
	desc.text = str(details.get("desc", "")).strip_edges()
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.add_theme_font_size_override("font_size", 12)
	desc.add_theme_color_override("font_color", UiStylesClass.COLOR_TEXT_MUTED)
	vbox.add_child(desc)

	return panel

func _build_reserve_card_art(image_path: String) -> Control:
	var frame := CenterContainer.new()
	frame.custom_minimum_size = RESERVE_CARD_ART_SIZE
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var image := TextureRect.new()
	image.custom_minimum_size = RESERVE_CARD_ART_SIZE
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var raw_path := ProjectSettings.globalize_path(image_path) if image_path.begins_with("res://") else image_path
	var raw_image := Image.load_from_file(raw_path)
	if raw_image != null and not raw_image.is_empty():
		image.texture = ImageTexture.create_from_image(raw_image)
	else:
		image.modulate = Color(1, 1, 1, 0.35)
	frame.add_child(image)
	return frame

func _build_first_break_event_data() -> Dictionary:
	var self_card := _get_reserve_card(_selected_reserve_index)
	var opponent_index := 1
	if opponent_index == _selected_reserve_index and _get_reserve_cards().size() > 2:
		opponent_index = 2
	var opponent_card := _get_reserve_card(opponent_index)
	var self_cash := int(self_card.get("cash", 0))
	var opponent_cash := int(opponent_card.get("cash", 0))
	if self_cash <= 0:
		self_cash = int(self_card.get("type", 0))
	if opponent_cash <= 0:
		opponent_cash = int(opponent_card.get("type", 0))
	return {
		"kind": "first",
		"max_breaks": 2,
		"bank_total_before": 15,
		"bank_total_after": 15 + self_cash + opponent_cash,
		"reserve_added": self_cash + opponent_cash,
		"required_payment": 20,
		"trigger_reason": "房屋购买需要 $20，但银行只有 $15",
		"revealed_cards": [
			{"player_id": 0, "selected_index": _selected_reserve_index, "card": self_card},
			{"player_id": 1, "selected_index": opponent_index, "card": opponent_card},
		],
	}

func _build_second_break_event_data() -> Dictionary:
	return {
		"kind": "second",
		"max_breaks": 2,
		"bank_total_before": 5,
		"bank_total_after": -25,
		"required_payment": 30,
		"trigger_reason": "银行第二次无法覆盖当前晚餐支付",
	}

func _build_bank_break_preview(count: int, bank_before: int, bank_after: int, event_data: Dictionary) -> Control:
	var frame := PanelContainer.new()
	frame.name = "BankBreakPreviewFrame"
	frame.custom_minimum_size = Vector2(560, 360)
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frame.add_theme_stylebox_override("panel", _make_style(Color(0.10, 0.08, 0.06, 0.18), Color(0.17, 0.13, 0.09, 0.20), 1, 6))

	var scene = load(BANK_BREAK_PANEL_SCENE_PATH)
	if scene is PackedScene:
		var preview := (scene as PackedScene).instantiate()
		preview.name = "BankBreakPanelPreview"
		preview.custom_minimum_size = Vector2(560, 360)
		preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
		frame.add_child(preview)
		call_deferred("_configure_bank_break_preview", preview, count, bank_before, bank_after, event_data)
	else:
		frame.add_child(_build_bank_break_fallback(count, bank_before, bank_after, event_data))
	return frame

func _configure_bank_break_preview(panel: Control, count: int, bank_before: int, bank_after: int, event_data: Dictionary) -> void:
	if not is_instance_valid(panel):
		return
	if panel.has_method("set_bankruptcy_info"):
		panel.call("set_bankruptcy_info", count, bank_before, bank_after, event_data)
	panel.visible = true
	var continue_btn := panel.get_node_or_null("CenterContainer/Panel/MarginContainer/VBoxContainer/ContinueButton") as Button
	if continue_btn != null:
		continue_btn.disabled = true
		continue_btn.text = "教学预览"

func _build_bank_break_fallback(count: int, bank_before: int, bank_after: int, event_data: Dictionary) -> Control:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 22)
	margin.add_theme_constant_override("margin_top", 22)
	margin.add_theme_constant_override("margin_right", 22)
	margin.add_theme_constant_override("margin_bottom", 22)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)
	var title := _make_label("银行%s破产" % ("二次" if count >= 2 else "首次"), 22, UiStylesClass.COLOR_TEXT_PRIMARY)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	var details := "破产前银行余额：$%d\n破产后银行余额：$%d\n累计破产次数：%d / %d" % [
		bank_before,
		bank_after,
		count,
		int(event_data.get("max_breaks", 2)),
	]
	var reason := str(event_data.get("trigger_reason", "")).strip_edges()
	if not reason.is_empty():
		details += "\n触发原因：%s" % reason
	vbox.add_child(_make_rich_text(details, 140))
	return margin

func _build_restaurant_preview_state(case_id: String):
	return {
		"restaurants": [
			{"restaurant_id": "rest_demo_opponent", "owner": 1, "anchor": Vector2i(0, 0)},
		],
		"houses": [
			{"house_id": "house_demo_left", "anchor": Vector2i(0, 3)},
			{"house_id": "house_demo_right", "anchor": Vector2i(8, 0)},
		],
	}

func _build_restaurant_preview_options(case_id: String) -> Dictionary:
	var preview_anchor := Vector2i(5, 3)
	var valid := true
	match case_id:
		"no_road":
			preview_anchor = Vector2i(5, 0)
			valid = false
		"same_board":
			preview_anchor = Vector2i(3, 3)
			valid = false
		_:
			preview_anchor = Vector2i(5, 3)
			valid = true
	var cells := _restaurant_cells_for_anchor(preview_anchor, 0)
	return {
		"structure_preview": {
			"cells": cells,
			"valid": valid,
			"info": {
				"piece_id": "restaurant",
				"anchor": preview_anchor,
				"owner": 0,
				"rotation": 0,
			},
		},
		"overlays": [
			{
				"id": "entry_board",
				"cells": _board_cells_for_world(preview_anchor),
				"style": {
					"fill": MAP_VALID_FILL if valid else MAP_SELECTED_FILL,
					"border": MAP_VALID_BORDER if valid else MAP_SELECTED_BORDER,
					"border_width": 2,
				},
			},
		],
	}

func _build_distance_preview_state(case_id: String):
	if case_id == "same_board":
		return {
			"restaurants": [
				{"restaurant_id": "rest_distance_a", "owner": 0, "anchor": Vector2i(0, 0)},
				{"restaurant_id": "rest_distance_b", "owner": 1, "anchor": Vector2i(3, 3)},
			],
			"houses": [
				{"house_id": "house_distance_right", "anchor": Vector2i(8, 0)},
			],
		}
	return {
		"restaurants": [
			{"restaurant_id": "rest_distance_a", "owner": 0, "anchor": Vector2i(3, 3)},
			{"restaurant_id": "rest_distance_b", "owner": 1, "anchor": Vector2i(5, 3)},
		],
		"houses": [
			{"house_id": "house_distance_left", "anchor": Vector2i(0, 0)},
			{"house_id": "house_distance_right", "anchor": Vector2i(8, 0)},
		],
	}

func _build_distance_preview_options(case_id: String) -> Dictionary:
	var path: Array[Vector2i] = []
	if case_id == "same_board":
		path = [
			Vector2i(0, 2),
			Vector2i(1, 2),
			Vector2i(2, 2),
			Vector2i(3, 2),
			Vector2i(4, 2),
			Vector2i(4, 3),
			Vector2i(4, 4),
			Vector2i(3, 4),
			Vector2i(3, 3),
		]
	else:
		path = [
			Vector2i(3, 2),
			Vector2i(4, 2),
			Vector2i(5, 2),
		]
	return {
		"highlights": path,
		"overlays": [
			{
				"id": "distance_path",
				"cells": path,
				"style": {
					"fill": MAP_DISTANCE_FILL,
					"border": MAP_DISTANCE_BORDER,
					"border_width": 2,
				},
			},
		],
	}

func _restaurant_cells_for_anchor(anchor: Vector2i, rotation: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var offsets: Array[Vector2i] = [
		Vector2i(0, 0),
		Vector2i(1, 0),
		Vector2i(0, 1),
		Vector2i(1, 1),
	]
	if rotation == 90 or rotation == 180 or rotation == 270:
		# 餐厅是 2x2，占地旋转后不变；入口教学统一用锚点角。
		pass
	for offset in offsets:
		cells.append(anchor + offset)
	return cells

func _board_cells_for_world(world_pos: Vector2i) -> Array[Vector2i]:
	var board_origin := Vector2i(floori(float(world_pos.x) / 5.0) * 5, floori(float(world_pos.y) / 5.0) * 5)
	var cells: Array[Vector2i] = []
	for y in range(5):
		for x in range(5):
			cells.append(board_origin + Vector2i(x, y))
	return cells

func _build_real_map_preview(state, options: Dictionary) -> Control:
	if state == null:
		var fallback := PanelContainer.new()
		fallback.custom_minimum_size = MAP_PREVIEW_SIZE
		fallback.add_theme_stylebox_override("panel", _make_style(Color(0.96, 0.92, 0.82, 0.92), Color(0.73, 0.23, 0.18, 0.65), 2, 6))
		var label := _make_label("真实地图预览暂不可用", 15, UiStylesClass.COLOR_TEXT_ERROR)
		fallback.add_child(label)
		return fallback

	var frame := PanelContainer.new()
	frame.name = "RealMapPreviewFrame"
	frame.custom_minimum_size = MAP_PREVIEW_SIZE
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frame.add_theme_stylebox_override("panel", _make_style(Color(0.93, 0.88, 0.77, 0.76), Color(0.17, 0.13, 0.09, 0.24), 1, 6))

	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	frame.add_child(center)

	var preview := RealAssetMapPreview.new()
	preview.setup(state if state is Dictionary else {}, options)
	center.add_child(preview)
	return frame

func _build_bankruptcy_timeline() -> Control:
	var timeline := VBoxContainer.new()
	timeline.add_theme_constant_override("separation", 8)
	var items := [
		{"title": "初始状态", "body": "银行 $15，下一笔房屋销售需要支付 $20。", "active": _bankruptcy_step >= 0},
		{"title": "第一笔销售", "body": "银行余额不足以支付 $20，触发第一次破产。", "active": _bankruptcy_step >= 1},
		{"title": "首次破产", "body": "揭示储备卡并注资 $150，支付完成后继续游戏。", "active": _bankruptcy_step >= 2},
		{"title": "第二笔销售", "body": "演示用银行压到 $5，再支付 $30，触发第二次破产。", "active": _bankruptcy_step >= 3},
		{"title": "终局", "body": "银行可透支完成当前晚餐，晚餐结束后跳过 Payday 并进入游戏结束面板。", "active": _bankruptcy_step >= 4},
	]
	for i in range(items.size()):
		var item: Dictionary = items[i]
		var row := PanelContainer.new()
		var bg := Color(0.91, 0.86, 0.74, 1.0)
		var border := Color(0.17, 0.13, 0.09, 0.22)
		if bool(item.get("active", false)):
			bg = Color(0.94, 0.88, 0.70, 1.0)
			border = Color(0.73, 0.23, 0.18, 0.65)
		row.add_theme_stylebox_override("panel", _make_style(bg, border, 2, 6))
		var margin := MarginContainer.new()
		margin.add_theme_constant_override("margin_left", 12)
		margin.add_theme_constant_override("margin_top", 8)
		margin.add_theme_constant_override("margin_right", 12)
		margin.add_theme_constant_override("margin_bottom", 8)
		row.add_child(margin)
		var label := Label.new()
		label.text = "%d. %s\n%s" % [i + 1, str(item.get("title", "")), str(item.get("body", ""))]
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.add_theme_font_size_override("font_size", 15)
		UiStylesClass.apply_label_dark(label)
		margin.add_child(label)
		timeline.add_child(row)
	return timeline

func _get_bankruptcy_status_text() -> String:
	match _bankruptcy_step:
		0:
			return "银行：$15。准备结算第一栋房屋，需支付 $20。"
		1:
			return "银行不足，第一次破产触发。接下来会揭示储备卡并注资。"
		2:
			return "第一次破产完成：注资后支付继续，游戏没有结束。"
		3:
			return "第二笔销售示例：银行再次不足，触发第二次破产。"
		_:
			return "第二次破产完成：银行透支支付当前晚餐，之后跳过 Payday 并结束游戏。"

func _get_placement_explanation(case_id: String) -> String:
	match case_id:
		"no_road":
			return "非法原因：你的餐厅入口没有邻接道路。\n\n教学界面应直接指出“入口不邻接道路”，而不是只提示不能放置。"
		"same_board":
			return "非法原因：你的入口邻接道路，但入口所在板块已经有对手的起始餐厅入口。\n\n注意：这是起始放置专用限制。"
		_:
			return "合法原因：你的入口落在右侧板块，并且入口邻接道路；对手入口在左侧板块，所以起始入口板块不冲突。\n\n起始限制只看入口所在板块，不看整张地图是否已有其他餐厅。"

func _make_segmented_row(options: Array, active_id: String, callback: Callable) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	for opt_val in options:
		var opt: Dictionary = opt_val
		var btn := Button.new()
		btn.text = str(opt.get("label", ""))
		btn.custom_minimum_size = Vector2(170, 42)
		var id := str(opt.get("id", ""))
		btn.disabled = id == active_id
		btn.pressed.connect(callback.bind(id))
		UiStylesClass.apply_button_secondary(btn)
		row.add_child(btn)
	return row

func _make_section(title: String) -> VBoxContainer:
	var section := VBoxContainer.new()
	section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	section.add_theme_constant_override("separation", 10)
	var label := Label.new()
	label.text = title
	label.add_theme_font_size_override("font_size", 21)
	UiStylesClass.apply_label_dark(label)
	section.add_child(label)
	return section

func _make_label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label

func _make_rich_text(text: String, min_height: int) -> RichTextLabel:
	var rich := RichTextLabel.new()
	rich.bbcode_enabled = false
	rich.text = text
	rich.fit_content = true
	rich.scroll_active = false
	rich.custom_minimum_size = Vector2(0, min_height)
	rich.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiStylesClass.apply_rich_text_dark(rich)
	return rich

func _make_style(bg: Color, border: Color, width: int = 1, radius: int = 6) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.border_width_left = width
	style.border_width_top = width
	style.border_width_right = width
	style.border_width_bottom = width
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	return style

func _on_reserve_card_choice_input(event: InputEvent, index: int) -> void:
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			_on_reserve_card_selected(index)

func _on_reserve_card_selected(index: int) -> void:
	_selected_reserve_index = clampi(index, 0, _get_reserve_cards().size() - 1)
	_reserve_break_revealed = false
	_render_lesson()

func _on_reveal_reserve_break_pressed() -> void:
	_reserve_break_revealed = true
	_render_lesson()

func _on_placement_case_selected(case_id: String) -> void:
	_placement_case = case_id
	_render_lesson()

func _on_distance_case_selected(case_id: String) -> void:
	_distance_case = case_id
	_render_lesson()

func _on_bankruptcy_next_pressed() -> void:
	_bankruptcy_step = mini(4, _bankruptcy_step + 1)
	_render_lesson()

func _on_bankruptcy_reset_pressed() -> void:
	_bankruptcy_step = 0
	_render_lesson()

func _on_prev_pressed() -> void:
	_select_lesson(_selected_lesson - 1)

func _on_next_pressed() -> void:
	_select_lesson(_selected_lesson + 1)

func _on_back_pressed() -> void:
	if SceneManager != null and SceneManager.has_method("goto_main_menu"):
		SceneManager.goto_main_menu()
