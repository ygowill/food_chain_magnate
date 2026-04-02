# 左侧信息面板（双栏仪表盘布局）
# - 玩家切换栏：快速切换 view_player
# - 玩家概览卡：餐厅图标、玩家名称、现金、员工数、餐厅数、薪资
# - 双栏区域：
#   - 左栏：公司结构（员工标签）、手牌
#   - 右栏：库存、里程碑
# - 活动流：最近2条日志，"完整日志"按钮
class_name LeftPanel
extends Control

signal logs_requested()

const UiSkinCacheClass = preload("res://ui/visual/ui_skin_cache.gd")
const LeftPanelEmployeeIconsControllerClass = preload("res://ui/components/left_panel/left_panel_employee_icons_controller.gd")
const LeftPanelTurnLogControllerClass = preload("res://ui/components/left_panel/left_panel_turn_log_controller.gd")
const LeftPanelSummaryControllerClass = preload("res://ui/components/left_panel/left_panel_summary_controller.gd")
const LeftPanelMilestonesControllerClass = preload("res://ui/components/left_panel/left_panel_milestones_controller.gd")
const UiStylesClass = preload("res://ui/utils/ui_styles.gd")
const UiPointerInputClass = preload("res://ui/utils/pointer_input.gd")
const WarningIconTexture = preload("res://assets/images/ui_icons/kenney_game/warning.png")
const ForfeitIconTexture = preload("res://assets/ui/icons/kenney/game/close_cross_white.png")

const STATUS_NONE := ""
const STATUS_DISCONNECTED := "disconnected"
const STATUS_FORFEITED := "forfeited"
const STATUS_BADGE_NAME := "StatusBadge"
const STATUS_BADGE_ICON_NAME := "StatusBadgeIcon"

# === 玩家切换栏 ===
@onready var restaurant_overview_section: PanelContainer = $MarginContainer/MainVBox/RestaurantOverviewSection
@onready var overview_header: Label = $MarginContainer/MainVBox/RestaurantOverviewSection/OverviewMargin/OverviewVBox/OverviewHeader
@onready var overview_grid: GridContainer = $MarginContainer/MainVBox/RestaurantOverviewSection/OverviewMargin/OverviewVBox/OverviewGrid
@onready var player_tabs: HBoxContainer = $MarginContainer/MainVBox/PlayerTabs

# === 玩家概览卡 ===
@onready var player_summary_card: PanelContainer = $MarginContainer/MainVBox/PlayerSummaryCard
@onready var restaurant_icon: TextureRect = $MarginContainer/MainVBox/PlayerSummaryCard/SummaryMargin/SummaryVBox/TopRow/RestaurantIcon
@onready var player_name_label: Label = $MarginContainer/MainVBox/PlayerSummaryCard/SummaryMargin/SummaryVBox/TopRow/PlayerNameLabel
@onready var cash_label: Label = $MarginContainer/MainVBox/PlayerSummaryCard/SummaryMargin/SummaryVBox/TopRow/CashLabel
@onready var employee_count_label: Label = $MarginContainer/MainVBox/PlayerSummaryCard/SummaryMargin/SummaryVBox/MetricsRow/EmployeeCountLabel
@onready var restaurant_count_label: Label = $MarginContainer/MainVBox/PlayerSummaryCard/SummaryMargin/SummaryVBox/MetricsRow/RestaurantCountLabel
@onready var salary_label: Label = $MarginContainer/MainVBox/PlayerSummaryCard/SummaryMargin/SummaryVBox/MetricsRow/SalaryLabel

# === 双栏区域 - 左栏（员工） ===
@onready var company_section: VBoxContainer = $MarginContainer/MainVBox/DualColumnArea/LeftColumn/EmployeesScroll/EmployeesContent/CompanySection
@onready var company_section_header: Label = $MarginContainer/MainVBox/DualColumnArea/LeftColumn/EmployeesScroll/EmployeesContent/CompanySection/CompanySectionHeader
@onready var company_tags_flow: VBoxContainer = $MarginContainer/MainVBox/DualColumnArea/LeftColumn/EmployeesScroll/EmployeesContent/CompanySection/CompanyTagsFlow
@onready var hand_section: VBoxContainer = $MarginContainer/MainVBox/DualColumnArea/LeftColumn/EmployeesScroll/EmployeesContent/HandSection
@onready var hand_section_header: Label = $MarginContainer/MainVBox/DualColumnArea/LeftColumn/EmployeesScroll/EmployeesContent/HandSection/HandSectionHeader
@onready var hand_tags_flow: VBoxContainer = $MarginContainer/MainVBox/DualColumnArea/LeftColumn/EmployeesScroll/EmployeesContent/HandSection/HandTagsFlow
@onready var busy_section: VBoxContainer = $MarginContainer/MainVBox/DualColumnArea/LeftColumn/EmployeesScroll/EmployeesContent/BusySection
@onready var busy_section_header: Label = $MarginContainer/MainVBox/DualColumnArea/LeftColumn/EmployeesScroll/EmployeesContent/BusySection/BusySectionHeader
@onready var busy_tags_flow: VBoxContainer = $MarginContainer/MainVBox/DualColumnArea/LeftColumn/EmployeesScroll/EmployeesContent/BusySection/BusyTagsFlow

# === 双栏区域 - 库存与里程碑 ===
@onready var inventory_header: Label = $MarginContainer/MainVBox/DualColumnArea/LeftColumn/InventorySection/InventoryHeader
@onready var inventory_tokens_flow: HFlowContainer = $MarginContainer/MainVBox/DualColumnArea/LeftColumn/InventorySection/InventoryTokensFlow
@onready var milestones_header: Label = $MarginContainer/MainVBox/DualColumnArea/RightColumn/MilestonesSection/MilestonesHeader
@onready var milestones_scroll: ScrollContainer = $MarginContainer/MainVBox/DualColumnArea/RightColumn/MilestonesSection/MilestonesScroll
@onready var milestones_list: VBoxContainer = $MarginContainer/MainVBox/DualColumnArea/RightColumn/MilestonesSection/MilestonesScroll/MilestonesList

# === 活动流 ===
@onready var activity_feed: PanelContainer = $MarginContainer/MainVBox/ActivityFeed
@onready var activity_line1: Label = $MarginContainer/MainVBox/ActivityFeed/ActivityMargin/ActivityHBox/ActivityVBox/ActivityLine1
@onready var activity_line2: Label = $MarginContainer/MainVBox/ActivityFeed/ActivityMargin/ActivityHBox/ActivityVBox/ActivityLine2
@onready var view_logs_button: Button = $MarginContainer/MainVBox/ActivityFeed/ActivityMargin/ActivityHBox/ViewLogsButton

var cash_overrides: Dictionary = {}  # {player_id: int -> cash: int}
var _game_state: GameState = null
var _player_count: int = 0
var _current_player_id: int = -1
var _view_player_id: int = -1

var _skin = null
var _skin_modules_key: String = ""
var _state_seed: int = 0
var _player_restaurant_logo_ids: Dictionary = {} # player_id -> logo_id
var _fallback_logo_ids: Array[int] = []

var _tab_buttons: Array[Button] = []
var _attached_log_panel: Node = null
var _attached_hand_area: Node = null
var _attached_company_structure: Node = null
var _last_phase: String = ""

var _employee_icons_controller = null
var _turn_log_controller = null
var _summary_controller = null
var _milestones_controller = null

func _ready() -> void:
	_ensure_controllers()
	_apply_visual_styles()
	_rebuild_player_tabs()
	apply_font_settings()
	_connect_signals()
	_refresh()

func _connect_signals() -> void:
	if is_instance_valid(view_logs_button):
		if not view_logs_button.pressed.is_connected(_on_view_logs_pressed):
			view_logs_button.pressed.connect(_on_view_logs_pressed)
	if NetClient != null:
		var cb := Callable(self, "_on_room_state_updated")
		if not NetClient.room_state_updated.is_connected(cb):
			NetClient.room_state_updated.connect(cb)

func _ensure_controllers() -> void:
	if _employee_icons_controller == null or not is_instance_valid(_employee_icons_controller):
		_employee_icons_controller = LeftPanelEmployeeIconsControllerClass.new()
	if _employee_icons_controller != null and is_instance_valid(_employee_icons_controller):
		_employee_icons_controller.setup(self)

	if _turn_log_controller == null or not is_instance_valid(_turn_log_controller):
		_turn_log_controller = LeftPanelTurnLogControllerClass.new()
	if _turn_log_controller != null and is_instance_valid(_turn_log_controller):
		_turn_log_controller.setup(self)

	if _summary_controller == null or not is_instance_valid(_summary_controller):
		_summary_controller = LeftPanelSummaryControllerClass.new()
	if _summary_controller != null and is_instance_valid(_summary_controller):
		_summary_controller.setup(self)

	if _milestones_controller == null or not is_instance_valid(_milestones_controller):
		_milestones_controller = LeftPanelMilestonesControllerClass.new()
	if _milestones_controller != null and is_instance_valid(_milestones_controller):
		_milestones_controller.setup(self)

func _apply_visual_styles() -> void:
	# 餐厅概览区
	if is_instance_valid(restaurant_overview_section):
		UiStylesClass.apply_panel_poster_alt(restaurant_overview_section)
	if is_instance_valid(overview_header):
		UiStylesClass.apply_label_dark(overview_header)

	# 玩家概览卡
	if is_instance_valid(player_summary_card):
		UiStylesClass.apply_panel_poster_alt(player_summary_card)
	if is_instance_valid(player_name_label):
		UiStylesClass.apply_label_dark(player_name_label)
		player_name_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		player_name_label.max_lines_visible = 1
		player_name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		player_name_label.clip_text = true
	if is_instance_valid(cash_label):
		UiStylesClass.apply_label_dark(cash_label)
	if is_instance_valid(employee_count_label):
		UiStylesClass.apply_label_hint_dark(employee_count_label)
	if is_instance_valid(restaurant_count_label):
		UiStylesClass.apply_label_hint_dark(restaurant_count_label)
	if is_instance_valid(salary_label):
		UiStylesClass.apply_label_hint_dark(salary_label)

	# 区块标题
	if is_instance_valid(company_section_header):
		UiStylesClass.apply_label_dark(company_section_header)
	if is_instance_valid(hand_section_header):
		UiStylesClass.apply_label_hint_dark(hand_section_header)
	if is_instance_valid(busy_section_header):
		UiStylesClass.apply_label_hint_dark(busy_section_header)
	if is_instance_valid(inventory_header):
		UiStylesClass.apply_label_hint_dark(inventory_header)
	if is_instance_valid(milestones_header):
		UiStylesClass.apply_label_hint_dark(milestones_header)
	if is_instance_valid(milestones_scroll):
		milestones_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		milestones_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO

	# 活动流
	if is_instance_valid(activity_feed):
		UiStylesClass.apply_panel_poster_alt(activity_feed)
	if is_instance_valid(activity_line1):
		UiStylesClass.apply_label_dark(activity_line1)
		activity_line1.autowrap_mode = TextServer.AUTOWRAP_OFF
		activity_line1.max_lines_visible = 1
		activity_line1.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		activity_line1.clip_text = true
	if is_instance_valid(activity_line2):
		UiStylesClass.apply_label_hint_dark(activity_line2)
		activity_line2.autowrap_mode = TextServer.AUTOWRAP_OFF
		activity_line2.max_lines_visible = 1
		activity_line2.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		activity_line2.clip_text = true
	if is_instance_valid(view_logs_button):
		UiStylesClass.apply_button_secondary(view_logs_button)
		view_logs_button.flat = false
		view_logs_button.focus_mode = Control.FOCUS_NONE
		view_logs_button.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
		view_logs_button.expand_icon = false
		view_logs_button.add_theme_constant_override("icon_max_width", 16)
		view_logs_button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

func apply_font_settings() -> void:
	var fs_name := 17
	var fs_cash := 22
	var fs_metrics := 14
	var fs_section := 18
	var fs_activity := 14
	var fs_overview := 18
	if Globals != null:
		fs_name = int(Globals.get_scaled_font_size(17))
		fs_cash = int(Globals.get_scaled_font_size(22))
		fs_metrics = int(Globals.get_scaled_font_size(14))
		fs_section = int(Globals.get_scaled_font_size(18))
		fs_activity = int(Globals.get_scaled_font_size(14))
		fs_overview = int(Globals.get_scaled_font_size(18))

	if is_instance_valid(overview_header):
		overview_header.add_theme_font_size_override("font_size", fs_overview)

	if is_instance_valid(player_name_label):
		player_name_label.add_theme_font_size_override("font_size", fs_name)
	if is_instance_valid(cash_label):
		cash_label.add_theme_font_size_override("font_size", fs_cash)
	if is_instance_valid(employee_count_label):
		employee_count_label.add_theme_font_size_override("font_size", fs_metrics)
	if is_instance_valid(restaurant_count_label):
		restaurant_count_label.add_theme_font_size_override("font_size", fs_metrics)
	if is_instance_valid(salary_label):
		salary_label.add_theme_font_size_override("font_size", fs_metrics)
	if is_instance_valid(company_section_header):
		company_section_header.add_theme_font_size_override("font_size", fs_section)
	if is_instance_valid(hand_section_header):
		hand_section_header.add_theme_font_size_override("font_size", fs_section)
	if is_instance_valid(busy_section_header):
		busy_section_header.add_theme_font_size_override("font_size", fs_section)
	if is_instance_valid(inventory_header):
		inventory_header.add_theme_font_size_override("font_size", fs_section)
	if is_instance_valid(milestones_header):
		milestones_header.add_theme_font_size_override("font_size", fs_section)
	if is_instance_valid(activity_line1):
		activity_line1.add_theme_font_size_override("font_size", fs_activity)
	if is_instance_valid(activity_line2):
		activity_line2.add_theme_font_size_override("font_size", fs_activity)
	if is_instance_valid(view_logs_button):
		view_logs_button.add_theme_font_size_override("font_size", fs_activity)

func set_game_state(state: GameState) -> void:
	_game_state = state
	_ensure_skin()
	_rebuild_player_logo_ids()
	var count := 0
	if state != null and state.players is Array:
		count = state.players.size()
	if count != _player_count:
		_player_count = count
		_rebuild_player_tabs()
	else:
		_update_player_tab_icons()
	_refresh()

func set_current_player(player_id: int) -> void:
	_current_player_id = player_id
	_update_tab_styles()
	_refresh_restaurant_overview_cards()

func set_view_player(player_id: int) -> void:
	_ensure_controllers()
	_view_player_id = player_id
	_update_tab_styles()
	_refresh_restaurant_overview_cards()
	if _summary_controller != null and is_instance_valid(_summary_controller):
		_summary_controller.refresh()
	if _employee_icons_controller != null and is_instance_valid(_employee_icons_controller):
		_employee_icons_controller.refresh()
	if _milestones_controller != null and is_instance_valid(_milestones_controller):
		_milestones_controller.refresh()
	if _turn_log_controller != null and is_instance_valid(_turn_log_controller):
		_turn_log_controller.refresh()

func select_tab(tab_id: String) -> void:
	# 兼容旧接口（双栏布局不再有 TabContainer）
	match tab_id:
		"logs":
			logs_requested.emit()

func bind_game_log_panel(panel: Node) -> void:
	_ensure_controllers()
	if panel == null or not is_instance_valid(panel):
		return
	if _turn_log_controller != null and is_instance_valid(_turn_log_controller):
		_turn_log_controller.bind_log_panel(panel)

func attach_game_log_panel(panel: Node) -> void:
	bind_game_log_panel(panel)

func attach_hand_area(_panel: Node) -> void:
	pass  # 新布局不需要 reparent

func detach_hand_area(_panel: Node, _target_parent: Node) -> void:
	pass

func attach_company_structure(_panel: Node) -> void:
	pass

func detach_company_structure(_panel: Node, _target_parent: Node) -> void:
	pass

func _rebuild_player_tabs() -> void:
	if not is_instance_valid(player_tabs):
		return

	for ch in player_tabs.get_children():
		if is_instance_valid(ch):
			ch.queue_free()
	_tab_buttons.clear()

	var group := ButtonGroup.new()
	for i in range(_player_count):
		var btn := Button.new()
		btn.toggle_mode = true
		btn.button_group = group
		btn.custom_minimum_size = Vector2(68, 52)
		btn.focus_mode = Control.FOCUS_NONE
		_apply_player_tab_icon(btn, i)
		btn.toggled.connect(_on_player_tab_toggled.bind(i))
		player_tabs.add_child(btn)
		_tab_buttons.append(btn)

	_update_tab_styles()

func _ensure_skin() -> void:
	if _game_state == null:
		_skin = null
		_skin_modules_key = ""
		return

	var mods: Array[String] = Array(_game_state.modules, TYPE_STRING, "", null)
	var key: String = str(mods)
	if _skin != null and key == _skin_modules_key:
		return
	_skin_modules_key = key
	_skin = UiSkinCacheClass.get_skin_for_modules(Globals.modules_v2_base_dir, mods, 40)

func _read_logo_id(value, logo_count: int) -> int:
	if logo_count <= 0:
		return -1
	var logo_id := -1
	if value is int:
		logo_id = int(value)
	elif value is float:
		var f: float = float(value)
		if f == floor(f):
			logo_id = int(f)
	if logo_id < 0 or logo_id >= logo_count:
		return -1
	return logo_id

func _build_fallback_logo_ids(logo_count: int) -> Array[int]:
	if logo_count <= 0:
		return []
	var ids: Array[int] = []
	for i in range(logo_count):
		ids.append(i)

	var rng := RandomNumberGenerator.new()
	var logo_seed := int(_state_seed) ^ int(0x4C4F474F) # 'LOGO'
	rng.seed = int(logo_seed)
	rng.state = int(logo_seed)
	for i in range(ids.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := ids[i]
		ids[i] = ids[j]
		ids[j] = tmp

	return ids

func _fallback_logo_id_for_player(player_id: int, fallback_logo_ids: Array[int]) -> int:
	if fallback_logo_ids.is_empty():
		return -1
	var pid := maxi(0, int(player_id))
	return int(fallback_logo_ids[pid % fallback_logo_ids.size()])

func _rebuild_player_logo_ids() -> void:
	_player_restaurant_logo_ids.clear()
	_fallback_logo_ids.clear()
	_state_seed = 0
	if _game_state == null:
		return
	_state_seed = int(_game_state.seed)

	var logo_count := 0
	if _skin != null and _skin.has_method("get_restaurant_logo_piece_ids"):
		var ids_val = _skin.get_restaurant_logo_piece_ids()
		if ids_val is Array:
			logo_count = (ids_val as Array).size()
	_fallback_logo_ids = _build_fallback_logo_ids(logo_count)
	for i in range(_game_state.players.size()):
		var p_val = _game_state.players[i]
		if not (p_val is Dictionary):
			continue
		var p: Dictionary = p_val
		var pid := int(p.get("id", i))
		if pid < 0:
			continue

		var logo_id := _read_logo_id(p.get("restaurant_logo_id", null), logo_count)
		if logo_id >= 0:
			_player_restaurant_logo_ids[pid] = logo_id
		else:
			_player_restaurant_logo_ids[pid] = _fallback_logo_id_for_player(pid, _fallback_logo_ids)

func _get_player_restaurant_logo_texture(player_id: int) -> Texture2D:
	if _skin == null:
		return null
	if not (_skin.has_method("get_restaurant_logo_piece_ids")) or not (_skin.has_method("get_restaurant_logo_texture_by_id")):
		return null
	var logo_count := (_skin.get_restaurant_logo_piece_ids() as Array).size()
	if logo_count <= 0:
		return null
	var logo_id := int(_player_restaurant_logo_ids.get(player_id, -1))
	if logo_id < 0 or logo_id >= logo_count:
		logo_id = _fallback_logo_id_for_player(player_id, _fallback_logo_ids)
	return _skin.get_restaurant_logo_texture_by_id(logo_id)

func _apply_player_tab_icon(btn: Button, player_id: int) -> void:
	if btn == null or not is_instance_valid(btn):
		return
	var tex := _get_player_restaurant_logo_texture(player_id)
	if tex != null:
		btn.text = ""
		btn.icon = tex
		btn.expand_icon = false
		btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		btn.add_theme_constant_override("icon_max_width", 44)
	else:
		btn.icon = null
		btn.text = str(player_id + 1)

func _update_player_tab_icons() -> void:
	for i in range(_tab_buttons.size()):
		var btn := _tab_buttons[i]
		if not is_instance_valid(btn):
			continue
		_apply_player_tab_icon(btn, i)

func _update_tab_styles() -> void:
	var view_id := _resolve_view_player_id()
	for i in range(_tab_buttons.size()):
		var btn := _tab_buttons[i]
		if not is_instance_valid(btn):
			continue

		btn.set_pressed_no_signal(i == view_id)

		var is_view := i == view_id

		var bg := Color(0.96, 0.93, 0.85, 0.98)
		var border_normal := Color(0.42, 0.36, 0.28, 0.7)
		var border_hover := Color(0.52, 0.44, 0.32, 0.9)
		var border_selected := Color(0.78, 0.42, 0.16, 1.0)

		var normal := StyleBoxFlat.new()
		normal.bg_color = bg
		normal.border_color = border_normal
		normal.set_border_width_all(2)
		normal.set_corner_radius_all(18)

		var hover := StyleBoxFlat.new()
		hover.bg_color = Color(0.98, 0.95, 0.88, 0.99)
		hover.border_color = border_hover
		hover.set_border_width_all(2)
		hover.set_corner_radius_all(18)

		var pressed := StyleBoxFlat.new()
		pressed.bg_color = Color(0.99, 0.97, 0.91, 1.0)
		pressed.border_color = border_selected
		pressed.set_border_width_all(4 if is_view else 2)
		pressed.set_corner_radius_all(18)

		btn.add_theme_stylebox_override("normal", normal)
		btn.add_theme_stylebox_override("pressed", pressed)
		btn.add_theme_stylebox_override("hover", hover)
		btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

		btn.add_theme_color_override("font_color", Color(0.15, 0.15, 0.15, 0.9))
		btn.add_theme_color_override("font_hover_color", Color(0.15, 0.15, 0.15, 0.9))
		btn.add_theme_color_override("font_pressed_color", Color(0.15, 0.15, 0.15, 0.9))
		btn.add_theme_color_override("font_focus_color", Color(0.15, 0.15, 0.15, 0.9))
		btn.modulate = Color(1, 1, 1, 1) if is_view else Color(0.95, 0.95, 0.95, 1)

func _refresh() -> void:
	_ensure_controllers()
	_refresh_restaurant_overview_cards()
	if _summary_controller != null and is_instance_valid(_summary_controller):
		_summary_controller.refresh()
	if _employee_icons_controller != null and is_instance_valid(_employee_icons_controller):
		_employee_icons_controller.refresh()
	if _milestones_controller != null and is_instance_valid(_milestones_controller):
		_milestones_controller.refresh()
	_update_tab_styles()
	if _turn_log_controller != null and is_instance_valid(_turn_log_controller):
		_turn_log_controller.refresh()

func set_cash_overrides(overrides: Dictionary) -> void:
	if overrides == null:
		cash_overrides = {}
	else:
		cash_overrides = overrides.duplicate()
	_update_cash_overrides_display()

func clear_cash_overrides() -> void:
	cash_overrides = {}
	_update_cash_overrides_display()

func _update_cash_overrides_display() -> void:
	_update_summary_cash_label()
	_update_overview_cash_labels()

func _update_summary_cash_label() -> void:
	if not is_instance_valid(cash_label):
		return
	if _game_state == null or not (_game_state.players is Array) or _game_state.players.is_empty():
		return
	var view_id := _resolve_view_player_id()
	if view_id < 0 or view_id >= _game_state.players.size():
		return
	var player_val = _game_state.players[view_id]
	var player: Dictionary = player_val if player_val is Dictionary else {}
	var cash := int(cash_overrides.get(view_id, player.get("cash", 0)))
	cash_label.text = "$%d" % cash

func _update_overview_cash_labels() -> void:
	if not is_instance_valid(overview_grid):
		return
	if _game_state == null or not (_game_state.players is Array) or _game_state.players.is_empty():
		return

	for node in overview_grid.get_children():
		if not (node is Control) or not is_instance_valid(node):
			continue
		var card: Control = node
		if not card.has_meta("player_id"):
			continue
		var pid := int(card.get_meta("player_id"))
		if pid < 0 or pid >= _game_state.players.size():
			continue
		var player_val = _game_state.players[pid]
		var player: Dictionary = player_val if player_val is Dictionary else {}
		var cash := int(cash_overrides.get(pid, player.get("cash", 0)))
		var cash_label_item: Label = card.find_child("CashLabel", true, false)
		if cash_label_item != null:
			cash_label_item.text = "$%d" % cash

func _count_total_employees(player: Dictionary) -> int:
	if _summary_controller != null and is_instance_valid(_summary_controller):
		return int(_summary_controller.count_total_employees(player))
	return 0

func _count_restaurants(player: Dictionary) -> int:
	if _summary_controller != null and is_instance_valid(_summary_controller):
		return int(_summary_controller.count_restaurants(player))
	return 0

func _count_milestones(player: Dictionary) -> int:
	if _summary_controller != null and is_instance_valid(_summary_controller):
		return int(_summary_controller.count_milestones(player))
	return 0

func _get_player_salary_cost(player: Dictionary) -> int:
	if _summary_controller != null and is_instance_valid(_summary_controller):
		return int(_summary_controller.get_player_salary_cost(player))
	return 0

func _refresh_restaurant_overview_cards() -> void:
	if not is_instance_valid(overview_grid):
		return

	for c in overview_grid.get_children():
		if is_instance_valid(c):
			c.queue_free()

	if _game_state == null or not (_game_state.players is Array) or _game_state.players.is_empty():
		var empty := Label.new()
		empty.text = "暂无餐厅信息"
		UiStylesClass.apply_label_hint_dark(empty)
		var fs := 14
		if Globals != null:
			fs = int(Globals.get_scaled_font_size(14))
		empty.add_theme_font_size_override("font_size", fs)
		overview_grid.add_child(empty)
		return

	var view_id := _resolve_view_player_id()
	for i in range(_game_state.players.size()):
		var player_val = _game_state.players[i]
		var player: Dictionary = player_val if player_val is Dictionary else {}
		var card := _create_restaurant_overview_card(i, player, i == view_id)
		overview_grid.add_child(card)

func _create_restaurant_overview_card(player_id: int, player: Dictionary, is_selected: bool) -> Control:
	var card := PanelContainer.new()
	card.set_meta("player_id", player_id)
	card.custom_minimum_size = Vector2(0, 96)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.98, 0.95, 0.88, 0.98)
	style.border_color = Color(0.78, 0.42, 0.16, 1.0) if is_selected else Color(0.42, 0.36, 0.28, 0.7)
	style.set_border_width_all(3 if is_selected else 2)
	style.set_corner_radius_all(10)
	card.add_theme_stylebox_override("panel", style)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 6)
	margin.add_theme_constant_override("margin_top", 4)
	margin.add_theme_constant_override("margin_right", 6)
	margin.add_theme_constant_override("margin_bottom", 4)
	card.add_child(margin)

	var root_row := HBoxContainer.new()
	root_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root_row.add_theme_constant_override("separation", 6)
	margin.add_child(root_row)

	var logo := TextureRect.new()
	logo.name = "RestaurantLogo"
	logo.custom_minimum_size = Vector2(58, 58)
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.texture = _get_player_restaurant_logo_texture(player_id)
	var status_kind := _get_player_status_kind(player_id, player)
	_apply_player_status_badge(logo, status_kind)
	root_row.add_child(logo)

	var cash := int(cash_overrides.get(player_id, player.get("cash", 0)))
	var emp_count := _count_total_employees(player)
	var rest_count := _count_restaurants(player)
	var milestone_count := _count_milestones(player)
	var salary_level := _get_player_salary_cost(player)

	var info_vbox := VBoxContainer.new()
	info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_vbox.add_theme_constant_override("separation", 2)
	root_row.add_child(info_vbox)

	var first_row := HBoxContainer.new()
	first_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	first_row.add_theme_constant_override("separation", 6)
	info_vbox.add_child(first_row)

	var display_name := "玩家%d" % (player_id + 1)
	if Globals != null and Globals.has_method("get_player_name"):
		var n := str(Globals.get_player_name(player_id)).strip_edges()
		if not n.is_empty():
			display_name = n

	var player_id_label := Label.new()
	player_id_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	player_id_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	player_id_label.max_lines_visible = 1
	player_id_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	player_id_label.clip_text = true
	player_id_label.text = display_name
	UiStylesClass.apply_label_dark(player_id_label)
	var fs_name := 14
	if Globals != null:
		fs_name = int(Globals.get_scaled_font_size(14))
	player_id_label.add_theme_font_size_override("font_size", fs_name)
	first_row.add_child(player_id_label)

	var cash_label_item := Label.new()
	cash_label_item.name = "CashLabel"
	cash_label_item.text = "$%d" % cash
	UiStylesClass.apply_label_dark(cash_label_item)
	var fs_cash := 16
	if Globals != null:
		fs_cash = int(Globals.get_scaled_font_size(16))
	cash_label_item.add_theme_font_size_override("font_size", fs_cash)
	first_row.add_child(cash_label_item)

	var metrics := Label.new()
	metrics.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	metrics.clip_text = true
	metrics.autowrap_mode = TextServer.AUTOWRAP_OFF
	metrics.max_lines_visible = 2
	metrics.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	metrics.text = "员工%d  餐厅%d\n里程碑%d  薪资$%d" % [emp_count, rest_count, milestone_count, salary_level]
	UiStylesClass.apply_label_hint_dark(metrics)
	var fs_metrics := 13
	if Globals != null:
		fs_metrics = int(Globals.get_scaled_font_size(13))
	metrics.add_theme_font_size_override("font_size", fs_metrics)
	info_vbox.add_child(metrics)

	var id_label := "玩家%d" % (player_id + 1)
	var default_name := "玩家 %d" % (player_id + 1)
	var tooltip_header := display_name
	if display_name != id_label and display_name != default_name:
		tooltip_header = "%s (%s)" % [display_name, id_label]

	card.tooltip_text = "%s\n现金: $%d\n员工: %d  餐厅: %d  里程碑: %d  薪资等级: $%d" % [
		tooltip_header,
		cash,
		emp_count,
		rest_count,
		milestone_count,
		salary_level
	]
	var status_text := _get_player_status_text(status_kind)
	if not status_text.is_empty():
		card.tooltip_text += "\n状态: %s" % status_text
	card.set_meta("status_kind", status_kind)
	card.gui_input.connect(Callable(self, "_on_overview_card_gui_input").bind(player_id))
	return card

func _on_room_state_updated(_room_state: Dictionary) -> void:
	if not is_inside_tree():
		return
	_refresh_restaurant_overview_cards()
	if _summary_controller != null and is_instance_valid(_summary_controller):
		_summary_controller.refresh()

func _get_player_status_kind(player_id: int, player: Dictionary = {}) -> String:
	var live_player := player
	if live_player.is_empty() and _game_state != null and (_game_state.players is Array):
		if player_id >= 0 and player_id < _game_state.players.size():
			var player_val = _game_state.players[player_id]
			if player_val is Dictionary:
				live_player = Dictionary(player_val)

	if bool(live_player.get("forfeited", false)):
		return STATUS_FORFEITED

	if NetContext == null or NetContext.mode != NetContext.Mode.ONLINE_CLIENT:
		return STATUS_NONE
	var room_state := Dictionary(NetContext.room_state)
	var players_val = room_state.get("players", null)
	if not (players_val is Array):
		return STATUS_NONE

	for p_val in Array(players_val):
		if not (p_val is Dictionary):
			continue
		var room_player: Dictionary = Dictionary(p_val)
		if int(room_player.get("seat_index", -1)) != player_id:
			continue
		if bool(room_player.get("forfeited", false)):
			return STATUS_FORFEITED
		if not bool(room_player.get("connected", true)):
			return STATUS_DISCONNECTED
		return STATUS_NONE
	return STATUS_NONE

func _get_player_status_text(status_kind: String) -> String:
	match status_kind:
		STATUS_DISCONNECTED:
			return "网络连接不佳"
		STATUS_FORFEITED:
			return "已弃权"
		_:
			return ""

func _ensure_player_status_badge(host: Control) -> PanelContainer:
	if host == null or not is_instance_valid(host):
		return null
	var badge := host.get_node_or_null(STATUS_BADGE_NAME) as PanelContainer
	if badge != null and is_instance_valid(badge):
		return badge

	badge = PanelContainer.new()
	badge.name = STATUS_BADGE_NAME
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.visible = false
	badge.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	badge.offset_left = -20.0
	badge.offset_top = 0.0
	badge.offset_right = 0.0
	badge.offset_bottom = 20.0
	host.add_child(badge)

	var icon := TextureRect.new()
	icon.name = STATUS_BADGE_ICON_NAME
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.layout_mode = 1
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon.anchor_right = 1.0
	icon.anchor_bottom = 1.0
	icon.offset_left = 3.0
	icon.offset_top = 3.0
	icon.offset_right = -3.0
	icon.offset_bottom = -3.0
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	badge.add_child(icon)
	return badge

func _apply_player_status_badge(host: Control, status_kind: String) -> void:
	var badge := _ensure_player_status_badge(host)
	if badge == null or not is_instance_valid(badge):
		return
	var icon := badge.get_node_or_null(STATUS_BADGE_ICON_NAME) as TextureRect
	if status_kind.is_empty():
		badge.visible = false
		badge.set_meta("status_kind", STATUS_NONE)
		if icon != null:
			icon.texture = null
		return

	var style := StyleBoxFlat.new()
	style.set_corner_radius_all(10)
	style.set_border_width_all(1)
	match status_kind:
		STATUS_DISCONNECTED:
			style.bg_color = Color(0.95, 0.75, 0.18, 0.98)
			style.border_color = Color(0.42, 0.24, 0.08, 0.95)
			if icon != null:
				icon.texture = WarningIconTexture
				icon.modulate = Color(0.24, 0.18, 0.08, 1.0)
		STATUS_FORFEITED:
			style.bg_color = Color(0.78, 0.22, 0.18, 0.98)
			style.border_color = Color(0.42, 0.08, 0.08, 0.95)
			if icon != null:
				icon.texture = ForfeitIconTexture
				icon.modulate = Color(1, 1, 1, 1)
		_:
			badge.visible = false
			badge.set_meta("status_kind", STATUS_NONE)
			if icon != null:
				icon.texture = null
			return

	badge.add_theme_stylebox_override("panel", style)
	badge.visible = true
	badge.set_meta("status_kind", status_kind)

func _update_summary_status_badge(player_id: int = -1, player: Dictionary = {}) -> void:
	if not is_instance_valid(restaurant_icon):
		return
	var status_kind := STATUS_NONE
	if player_id >= 0:
		status_kind = _get_player_status_kind(player_id, player)
	restaurant_icon.set_meta("status_kind", status_kind)
	restaurant_icon.tooltip_text = _get_player_status_text(status_kind)
	_apply_player_status_badge(restaurant_icon, status_kind)

func _resolve_view_player_id() -> int:
	if _game_state == null:
		return 0
	var view_id := _view_player_id
	if view_id < 0 or view_id >= _game_state.players.size():
		if NetContext != null and NetContext.mode == NetContext.Mode.ONLINE_CLIENT and int(NetContext.local_player_id) >= 0:
			view_id = int(NetContext.local_player_id)
		else:
			view_id = _current_player_id
	if view_id < 0 or view_id >= _game_state.players.size():
		view_id = 0
	view_id = clamp(view_id, 0, maxi(0, _game_state.players.size() - 1))
	return view_id

func _on_player_tab_toggled(pressed: bool, player_id: int) -> void:
	if not pressed:
		return
	set_view_player(player_id)

func _on_overview_card_gui_input(event: InputEvent, player_id: int) -> void:
	if not UiPointerInputClass.is_primary_press(event):
		return
	set_view_player(player_id)

func _on_view_logs_pressed() -> void:
	logs_requested.emit()
