class_name TutorialCampaignScene
extends Control

const UiStylesClass = preload("res://ui/utils/ui_styles.gd")

const RESERVE_CARDS := [
	{"title": "储备卡 1", "cash": 50, "slots": 2, "summary": "首次破产注资 $50，CEO 变为 2 槽候选"},
	{"title": "储备卡 2", "cash": 100, "slots": 3, "summary": "首次破产注资 $100，CEO 变为 3 槽候选"},
	{"title": "储备卡 3", "cash": 150, "slots": 4, "summary": "首次破产注资 $150，CEO 变为 4 槽候选"},
]

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
			"完成一个合法的跨板块占地、不同入口板块放置",
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
	GameLog.info("TutorialCampaign", "教学战役原型已加载")
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
	row.add_theme_constant_override("separation", 10)
	card.add_child(row)
	for i in range(RESERVE_CARDS.size()):
		var reserve: Dictionary = RESERVE_CARDS[i]
		var btn := Button.new()
		btn.text = "%s\n+$%d / CEO %d 槽" % [
			str(reserve.get("title", "")),
			int(reserve.get("cash", 0)),
			int(reserve.get("slots", 0)),
		]
		btn.custom_minimum_size = Vector2(210, 76)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.disabled = i == _selected_reserve_index
		btn.pressed.connect(_on_reserve_card_selected.bind(i))
		UiStylesClass.apply_button_secondary(btn)
		row.add_child(btn)
	card.add_child(_make_label("当前选择：%s。确认后不可更改；它不会立刻给你现金。" % str(RESERVE_CARDS[_selected_reserve_index].get("summary", "")), 15, UiStylesClass.COLOR_TEXT_PRIMARY))
	var demo_button := Button.new()
	demo_button.text = "演示第一次破产揭示"
	demo_button.custom_minimum_size = Vector2(240, 44)
	demo_button.pressed.connect(_on_reveal_reserve_break_pressed)
	UiStylesClass.apply_button_primary(demo_button)
	card.add_child(demo_button)
	if _reserve_break_revealed:
		var selected: Dictionary = RESERVE_CARDS[_selected_reserve_index]
		var opponent := RESERVE_CARDS[1]
		var total_added := int(selected.get("cash", 0)) + int(opponent.get("cash", 0))
		var chosen_slots := maxi(int(selected.get("slots", 0)), int(opponent.get("slots", 0)))
		card.add_child(_make_rich_text("银行支付不足时触发首次破产：\n- 你的已选卡揭示：+$%d / CEO %d 槽候选\n- 对手示例卡揭示：+$%d / CEO %d 槽候选\n- 银行合计注资：$%d\n- 本例 CEO 新卡槽：%d\n\n第一次破产后继续游戏，直到第二次破产才进入终局流程。" % [
			int(selected.get("cash", 0)),
			int(selected.get("slots", 0)),
			int(opponent.get("cash", 0)),
			int(opponent.get("slots", 0)),
			total_added,
			chosen_slots,
		], 190))
	_content_body.add_child(card)

func _render_initial_restaurant_lesson() -> void:
	var controls := _make_segmented_row([
		{"id": "no_road", "label": "入口无路"},
		{"id": "same_board", "label": "入口板块冲突"},
		{"id": "valid", "label": "合法放置"},
	], _placement_case, Callable(self, "_on_placement_case_selected"))
	_content_body.add_child(controls)

	var card := _make_section("起始放置演示")
	var state := _build_restaurant_grid_state(_placement_case)
	card.add_child(_build_board_grid(state))
	card.add_child(_make_rich_text(_get_placement_explanation(_placement_case), 120))
	_content_body.add_child(card)

func _render_distance_lesson() -> void:
	var controls := _make_segmented_row([
		{"id": "same_board", "label": "同板块长路线"},
		{"id": "cross_board", "label": "跨板块短路线"},
	], _distance_case, Callable(self, "_on_distance_case_selected"))
	_content_body.add_child(controls)

	var card := _make_section("距离工具演示")
	card.add_child(_build_board_grid(_build_distance_grid_state(_distance_case)))
	if _distance_case == "same_board":
		card.add_child(_make_rich_text("同板块长路线：道路步数 8，但没有跨过地图板块边界，所以规则距离 = 0。\n\n这就是为什么距离不能理解成格子数。晚餐选店使用的是跨板块次数。", 130))
	else:
		card.add_child(_make_rich_text("跨板块短路线：道路步数 3，但路径穿过 1 次板块边界，所以规则距离 = 1。\n\n如果两家餐厅价格相同，这 1 点距离就可能改变房屋选择。", 130))
	_content_body.add_child(card)

func _render_bankruptcy_lesson() -> void:
	var card := _make_section("破产流程演示")
	card.add_child(_make_label(_get_bankruptcy_status_text(), 16, UiStylesClass.COLOR_TEXT_PRIMARY))
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

func _build_restaurant_grid_state(case_id: String) -> Dictionary:
	var cells := _base_board_cells()
	_mark_road_row(cells, 2)
	_mark_restaurant(cells, [Vector2i(1, 0), Vector2i(2, 0), Vector2i(1, 1), Vector2i(2, 1)], Vector2i(1, 1), "对手", Color(0.42, 0.56, 0.82, 1.0))
	match case_id:
		"no_road":
			_mark_restaurant(cells, [Vector2i(6, 3), Vector2i(7, 3), Vector2i(6, 4), Vector2i(7, 4)], Vector2i(7, 4), "你", Color(0.83, 0.33, 0.25, 1.0))
		"same_board":
			_mark_restaurant(cells, [Vector2i(3, 0), Vector2i(4, 0), Vector2i(3, 1), Vector2i(4, 1)], Vector2i(4, 1), "你", Color(0.83, 0.33, 0.25, 1.0))
		"valid":
			_mark_restaurant(cells, [Vector2i(4, 0), Vector2i(5, 0), Vector2i(4, 1), Vector2i(5, 1)], Vector2i(5, 1), "你", Color(0.83, 0.33, 0.25, 1.0))
	return cells

func _build_distance_grid_state(case_id: String) -> Dictionary:
	var cells := _base_board_cells()
	if case_id == "same_board":
		var path := [
			Vector2i(0, 0),
			Vector2i(0, 1),
			Vector2i(0, 2),
			Vector2i(1, 2),
			Vector2i(2, 2),
			Vector2i(3, 2),
			Vector2i(4, 2),
			Vector2i(4, 3),
			Vector2i(4, 4),
		]
		_mark_path(cells, path, "S", "A")
	else:
		var path2 := [Vector2i(3, 2), Vector2i(4, 2), Vector2i(5, 2), Vector2i(6, 2)]
		_mark_path(cells, path2, "S", "B")
	return cells

func _base_board_cells() -> Dictionary:
	var cells := {}
	for y in range(5):
		for x in range(10):
			cells[_cell_key(x, y)] = {
				"text": "",
				"bg": Color(0.95, 0.91, 0.80, 1.0),
				"fg": UiStylesClass.COLOR_TEXT_PRIMARY,
			}
	return cells

func _mark_road_row(cells: Dictionary, y: int) -> void:
	for x in range(10):
		var key := _cell_key(x, y)
		cells[key] = {"text": "路", "bg": Color(0.58, 0.56, 0.50, 1.0), "fg": Color(0.98, 0.96, 0.88, 1.0)}

func _mark_restaurant(cells: Dictionary, footprint: Array, door: Vector2i, label: String, color: Color) -> void:
	for pos_val in footprint:
		var pos: Vector2i = pos_val
		cells[_cell_key(pos.x, pos.y)] = {"text": label, "bg": color, "fg": Color.WHITE}
	cells[_cell_key(door.x, door.y)] = {"text": "门", "bg": Color(0.96, 0.74, 0.24, 1.0), "fg": UiStylesClass.COLOR_TEXT_PRIMARY}

func _mark_path(cells: Dictionary, path: Array, start_label: String, end_label: String) -> void:
	for pos_val in path:
		var pos: Vector2i = pos_val
		cells[_cell_key(pos.x, pos.y)] = {"text": "·", "bg": Color(0.34, 0.65, 0.48, 1.0), "fg": Color.WHITE}
	var start: Vector2i = path[0]
	var ending: Vector2i = path[path.size() - 1]
	cells[_cell_key(start.x, start.y)] = {"text": start_label, "bg": Color(0.18, 0.47, 0.35, 1.0), "fg": Color.WHITE}
	cells[_cell_key(ending.x, ending.y)] = {"text": end_label, "bg": Color(0.83, 0.33, 0.25, 1.0), "fg": Color.WHITE}

func _build_board_grid(cells: Dictionary) -> Control:
	var outer := HBoxContainer.new()
	outer.add_theme_constant_override("separation", 8)
	outer.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	outer.add_child(_build_single_board(cells, 0))
	var boundary := VBoxContainer.new()
	boundary.custom_minimum_size = Vector2(28, 0)
	boundary.alignment = BoxContainer.ALIGNMENT_CENTER
	var boundary_label := Label.new()
	boundary_label.text = "板\n块\n边\n界"
	boundary_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiStylesClass.apply_label_hint_dark(boundary_label)
	boundary.add_child(boundary_label)
	outer.add_child(boundary)
	outer.add_child(_build_single_board(cells, 5))
	return outer

func _build_single_board(cells: Dictionary, offset_x: int) -> Control:
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 3)
	grid.add_theme_constant_override("v_separation", 3)
	for y in range(5):
		for local_x in range(5):
			var x := offset_x + local_x
			var data: Dictionary = cells.get(_cell_key(x, y), {})
			var cell := PanelContainer.new()
			cell.custom_minimum_size = Vector2(54, 54)
			cell.add_theme_stylebox_override("panel", _make_style(
				data.get("bg", Color(0.95, 0.91, 0.80, 1.0)),
				Color(0.17, 0.13, 0.09, 0.22),
				1,
				3
			))
			var label := Label.new()
			label.text = str(data.get("text", ""))
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			label.add_theme_font_size_override("font_size", 15)
			label.add_theme_color_override("font_color", data.get("fg", UiStylesClass.COLOR_TEXT_PRIMARY))
			cell.add_child(label)
			grid.add_child(cell)
	return grid

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
			return "合法原因：餐厅占地跨过板块边界，但入口落在右侧板块，并且邻接道路。\n\n起始限制只看入口所在板块，不看整个 footprint。"

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

func _cell_key(x: int, y: int) -> String:
	return "%d,%d" % [x, y]

func _on_reserve_card_selected(index: int) -> void:
	_selected_reserve_index = clampi(index, 0, RESERVE_CARDS.size() - 1)
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
