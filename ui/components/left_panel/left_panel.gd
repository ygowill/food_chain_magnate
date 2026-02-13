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
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const ProductRegistryClass = preload("res://core/data/product_registry.gd")
const LeftPanelEmployeeIconsControllerClass = preload("res://ui/components/left_panel/left_panel_employee_icons_controller.gd")
const LeftPanelTurnLogControllerClass = preload("res://ui/components/left_panel/left_panel_turn_log_controller.gd")
const UiStylesClass = preload("res://ui/utils/ui_styles.gd")
const EmployeeRulesClass = preload("res://core/rules/employee_rules.gd")

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

const EMPLOYEE_CATEGORY_ORDER := ["管理", "厨房", "营销", "其他"]
const EMPLOYEE_CATEGORY_ICON: Dictionary = {
	"管理": "👔",
	"厨房": "👨‍🍳",
	"营销": "📢",
	"其他": "⭐",
}

# 里程碑状态颜色
const MILESTONE_COLOR_CLAIMED := Color(0.28, 0.55, 0.22, 1.0)  # 成功绿
const MILESTONE_COLOR_AVAILABLE := Color(0.83, 0.63, 0.23, 1.0)  # 警告橙
const MILESTONE_COLOR_GONE := Color(0.5, 0.45, 0.35, 1.0)  # hint灰
const MILESTONE_PALETTE_PURPLE := Color(0.69, 0.57, 0.77, 1.0)
const MILESTONE_PALETTE_GRAY := Color(0.76, 0.75, 0.74, 1.0)
const MILESTONE_PALETTE_MARKETING_BLUE := Color(0.59, 0.77, 0.82, 1.0)
const MILESTONE_PALETTE_PRODUCE_GREEN := Color(0.60, 0.71, 0.35, 1.0)
const MILESTONE_PALETTE_PROCURE_GREEN := Color(0.70, 0.81, 0.58, 1.0)
const MILESTONE_PALETTE_PRICE_ORANGE := Color(0.92, 0.66, 0.56, 1.0)
const MILESTONE_PALETTE_COFFEE_MINT := Color(0.60, 0.80, 0.72, 1.0)
const MILESTONE_PALETTE_KETCHUP_DARK := Color(0.15, 0.11, 0.10, 1.0)
const MILESTONE_SCROLL_GUTTER := 16
const MILESTONE_CATEGORY_COLORS: Dictionary = {
	"employee": MILESTONE_PALETTE_PURPLE,
	"marketing": MILESTONE_PALETTE_MARKETING_BLUE,
	"finance": MILESTONE_PALETTE_PURPLE,
	"ops": MILESTONE_PALETTE_PRODUCE_GREEN,
	"expansion": MILESTONE_PALETTE_MARKETING_BLUE,
	"general": MILESTONE_PALETTE_GRAY,
}
const MILESTONE_COLOR_BY_ID: Dictionary = {
	# Base milestones（按规则书配色）
	"first_hire_3": MILESTONE_PALETTE_PURPLE,
	"first_throw_away": MILESTONE_PALETTE_PURPLE,
	"first_waitress": MILESTONE_PALETTE_PURPLE,
	"first_have_20": MILESTONE_PALETTE_PURPLE,
	"first_have_100": MILESTONE_PALETTE_PURPLE,
	"first_train": MILESTONE_PALETTE_GRAY,
	"first_pay_20_salaries": MILESTONE_PALETTE_GRAY,
	"first_billboard": MILESTONE_PALETTE_MARKETING_BLUE,
	"first_burger_marketed": MILESTONE_PALETTE_MARKETING_BLUE,
	"first_pizza_marketed": MILESTONE_PALETTE_MARKETING_BLUE,
	"first_drink_marketed": MILESTONE_PALETTE_MARKETING_BLUE,
	"first_airplane": MILESTONE_PALETTE_MARKETING_BLUE,
	"first_radio": MILESTONE_PALETTE_MARKETING_BLUE,
	"first_burger_produced": MILESTONE_PALETTE_PRODUCE_GREEN,
	"first_pizza_produced": MILESTONE_PALETTE_PRODUCE_GREEN,
	"first_errand_boy": MILESTONE_PALETTE_PROCURE_GREEN,
	"first_cart_operator": MILESTONE_PALETTE_PROCURE_GREEN,
	"first_lower_prices": MILESTONE_PALETTE_PRICE_ORANGE,
	# Module milestones（规则书中的模块区）
	"first_rural_marketeer_used": MILESTONE_PALETTE_MARKETING_BLUE,
	"first_lobbyist_used": MILESTONE_PALETTE_PURPLE,
	"first_coffee_sold": MILESTONE_PALETTE_COFFEE_MINT,
	"ketchup_sold_your_demand": MILESTONE_PALETTE_KETCHUP_DARK,
	# New milestones（按规则书分组）
	"first_marketeer_used": MILESTONE_PALETTE_MARKETING_BLUE,
	"first_marketing_trainee_used": MILESTONE_PALETTE_MARKETING_BLUE,
	"first_campaign_manager_used": MILESTONE_PALETTE_MARKETING_BLUE,
	"first_brand_manager_used": MILESTONE_PALETTE_MARKETING_BLUE,
	"first_brand_director_used": MILESTONE_PALETTE_MARKETING_BLUE,
	"first_new_restaurant": MILESTONE_PALETTE_MARKETING_BLUE,
	"first_burger_sold": MILESTONE_PALETTE_PRODUCE_GREEN,
	"first_pizza_sold": MILESTONE_PALETTE_PRODUCE_GREEN,
	"first_beer_sold": MILESTONE_PALETTE_PROCURE_GREEN,
	"first_coke_sold": MILESTONE_PALETTE_PROCURE_GREEN,
	"first_lemonade_sold": MILESTONE_PALETTE_PROCURE_GREEN,
	"first_recruiting_girl_used": MILESTONE_PALETTE_PURPLE,
	"first_waitress_used": MILESTONE_PALETTE_PURPLE,
	"first_trainer_used": MILESTONE_PALETTE_GRAY,
	"first_house_built": MILESTONE_PALETTE_GRAY,
	"first_discount_manager_used": MILESTONE_PALETTE_PRICE_ORANGE,
	"first_cart_operator_used": MILESTONE_PALETTE_PROCURE_GREEN,
}
const MILESTONE_EFFECT_CATEGORY: Dictionary = {
	"gain_card": "employee",
	"gain_cards": "employee",
	"ban_card": "employee",
	"multi_trainer_on_one": "employee",
	"train_from_active_same_color": "employee",
	"employee_no_salary": "employee",
	"peek_reserve_cards": "finance",
	"base_price_delta": "finance",
	"sell_bonus": "finance",
	"salary_total_delta": "finance",
	"turnorder_empty_slots": "finance",
	"ceo_get_cfo": "finance",
	"salary_pay_with_tokens": "finance",
	"salary_allow_unpaid": "finance",
	"salary_cost_override": "finance",
	"bank_burn_on_discount_ge_3": "finance",
	"marketing_no_salary": "marketing",
	"marketing_permanent": "marketing",
	"extra_marketing": "marketing",
	"procure_plus_one": "ops",
	"drinks_per_source_delta": "ops",
	"distance_plus_one": "ops",
	"gain_fridge": "ops",
}

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

func _ensure_controllers() -> void:
	if _employee_icons_controller == null or not is_instance_valid(_employee_icons_controller):
		_employee_icons_controller = LeftPanelEmployeeIconsControllerClass.new()
	if _employee_icons_controller != null and is_instance_valid(_employee_icons_controller):
		_employee_icons_controller.setup(self)

	if _turn_log_controller == null or not is_instance_valid(_turn_log_controller):
		_turn_log_controller = LeftPanelTurnLogControllerClass.new()
	if _turn_log_controller != null and is_instance_valid(_turn_log_controller):
		_turn_log_controller.setup(self)

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
	if is_instance_valid(activity_line2):
		UiStylesClass.apply_label_hint_dark(activity_line2)
	if is_instance_valid(view_logs_button):
		UiStylesClass.apply_button_secondary(view_logs_button)
		view_logs_button.flat = false
		view_logs_button.focus_mode = Control.FOCUS_NONE
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
	_refresh_summary()
	if _employee_icons_controller != null and is_instance_valid(_employee_icons_controller):
		_employee_icons_controller.refresh()
	_refresh_milestones_compact()
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
	_refresh_summary()
	if _employee_icons_controller != null and is_instance_valid(_employee_icons_controller):
		_employee_icons_controller.refresh()
	_refresh_milestones_compact()
	_update_tab_styles()
	if _turn_log_controller != null and is_instance_valid(_turn_log_controller):
		_turn_log_controller.refresh()

func _refresh_summary() -> void:
	if _game_state == null:
		_set_summary_empty()
		return

	var view_id := _resolve_view_player_id()
	if view_id < 0 or view_id >= _game_state.players.size():
		_set_summary_empty()
		return

	var player_val = _game_state.players[view_id]
	var player: Dictionary = player_val if player_val is Dictionary else {}

	# 餐厅图标
	if is_instance_valid(restaurant_icon):
		var tex := _get_player_restaurant_logo_texture(view_id)
		restaurant_icon.texture = tex

	# 玩家名称
	if is_instance_valid(player_name_label):
		player_name_label.text = Globals.get_player_name(view_id)

	# 现金
	var cash := int(player.get("cash", 0))
	if is_instance_valid(cash_label):
		cash_label.text = "$%d" % cash

	# 员工总数
	var emp_count := _count_total_employees(player)
	if is_instance_valid(employee_count_label):
		employee_count_label.text = "👥%d人" % emp_count

	# 餐厅数
	var rest_count := _count_restaurants(player)
	if is_instance_valid(restaurant_count_label):
		restaurant_count_label.text = "🏠%d店" % rest_count

	# 每回合薪资
	var total_salary := _calculate_total_salary(player)
	if is_instance_valid(salary_label):
		salary_label.text = "💰$%d/回合" % total_salary

	# 库存
	var inv_val = player.get("inventory", {})
	var inv: Dictionary = inv_val if inv_val is Dictionary else {}
	_refresh_inventory_ui(inv, _get_fridge_capacity_for_player(player))

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
	logo.custom_minimum_size = Vector2(58, 58)
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.texture = _get_player_restaurant_logo_texture(player_id)
	root_row.add_child(logo)

	var cash := int(player.get("cash", 0))
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

	var player_id_label := Label.new()
	player_id_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	player_id_label.clip_text = true
	player_id_label.text = "玩家%d" % (player_id + 1)
	UiStylesClass.apply_label_dark(player_id_label)
	var fs_name := 14
	if Globals != null:
		fs_name = int(Globals.get_scaled_font_size(14))
	player_id_label.add_theme_font_size_override("font_size", fs_name)
	first_row.add_child(player_id_label)

	var cash_label_item := Label.new()
	cash_label_item.text = "$%d" % cash
	UiStylesClass.apply_label_dark(cash_label_item)
	var fs_cash := 16
	if Globals != null:
		fs_cash = int(Globals.get_scaled_font_size(16))
	cash_label_item.add_theme_font_size_override("font_size", fs_cash)
	first_row.add_child(cash_label_item)

	var metrics := Label.new()
	metrics.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	metrics.clip_text = false
	metrics.autowrap_mode = TextServer.AUTOWRAP_OFF
	metrics.max_lines_visible = 2
	metrics.text = "员工%d  餐厅%d\n里程碑%d  薪资$%d" % [emp_count, rest_count, milestone_count, salary_level]
	UiStylesClass.apply_label_hint_dark(metrics)
	var fs_metrics := 13
	if Globals != null:
		fs_metrics = int(Globals.get_scaled_font_size(13))
	metrics.add_theme_font_size_override("font_size", fs_metrics)
	info_vbox.add_child(metrics)

	card.tooltip_text = "玩家%d\n现金: $%d\n员工: %d  餐厅: %d  里程碑: %d  薪资等级: $%d" % [
		player_id + 1,
		cash,
		emp_count,
		rest_count,
		milestone_count,
		salary_level
	]
	card.gui_input.connect(Callable(self, "_on_overview_card_gui_input").bind(player_id))
	return card

func _set_summary_empty() -> void:
	if is_instance_valid(restaurant_icon):
		restaurant_icon.texture = null
	if is_instance_valid(player_name_label):
		player_name_label.text = "-"
	if is_instance_valid(cash_label):
		cash_label.text = "$0"
	if is_instance_valid(employee_count_label):
		employee_count_label.text = "👥0人"
	if is_instance_valid(restaurant_count_label):
		restaurant_count_label.text = "🏠0店"
	if is_instance_valid(salary_label):
		salary_label.text = "💰$0/回合"
	_refresh_inventory_ui({}, -1)

func _count_total_employees(player: Dictionary) -> int:
	if player == null:
		return 0
	var count := 0
	var sources := [
		player.get("employees", []),
		player.get("reserve_employees", []),
		player.get("busy_marketers", []),
	]
	for src_val in sources:
		for e_val in Array(src_val):
			var emp_id := str(e_val).strip_edges()
			if not emp_id.is_empty():
				count += 1
	return count

func _count_restaurants(player: Dictionary) -> int:
	if player == null:
		return 0

	var restaurants_val = player.get("restaurants", [])
	if not (restaurants_val is Array):
		return 0

	var count := 0
	for rid_val in Array(restaurants_val):
		var rid := str(rid_val).strip_edges()
		if not rid.is_empty():
			count += 1
	return count

func _count_milestones(player: Dictionary) -> int:
	if player == null:
		return 0
	var milestones_val = player.get("milestones", [])
	if not (milestones_val is Array):
		return 0
	var count := 0
	for mid_val in Array(milestones_val):
		var mid := str(mid_val).strip_edges()
		if not mid.is_empty():
			count += 1
	return count

func _calculate_total_salary(player: Dictionary) -> int:
	if player == null:
		return 0

	if not EmployeeRegistry.is_loaded():
		return 0
	if not (player.get("employees", null) is Array):
		return 0
	if not (player.get("reserve_employees", null) is Array):
		return 0
	if not (player.get("busy_marketers", null) is Array):
		return 0

	var paid_employee_count := EmployeeRulesClass.count_paid_employees(player)
	var salary_cost := _get_player_salary_cost(player)
	return paid_employee_count * salary_cost

func _get_player_salary_cost(player: Dictionary) -> int:
	var salary_cost := 0
	if _game_state != null and (_game_state.rules is Dictionary):
		salary_cost = int((_game_state.rules as Dictionary).get("salary_cost", 0))

	var override_val = player.get("salary_cost_override", null)
	if override_val is int:
		salary_cost = maxi(0, int(override_val))
	elif override_val is float:
		var f: float = float(override_val)
		if f == floor(f):
			salary_cost = maxi(0, int(f))

	return maxi(0, salary_cost)

func _refresh_inventory_ui(inv: Dictionary, fridge_capacity: int) -> void:
	if not is_instance_valid(inventory_header) or not is_instance_valid(inventory_tokens_flow):
		return

	# 计算库存总量
	var total_items := 0
	for k in inv.keys():
		total_items += int(inv.get(k, 0))

	if fridge_capacity < 0:
		inventory_header.text = "📦 库存 (%d)" % total_items
	else:
		inventory_header.text = "📦 库存 (%d/%d)" % [total_items, fridge_capacity]

	for c in inventory_tokens_flow.get_children():
		if is_instance_valid(c):
			c.queue_free()

	_ensure_skin()

	var keys := inv.keys()
	keys.sort()

	var added := 0
	for k in keys:
		var product_id := str(k)
		var count := int(inv.get(product_id, 0))
		if count <= 0:
			continue
		inventory_tokens_flow.add_child(_build_inventory_token_item(product_id, count))
		added += 1

	if added <= 0:
		var empty := Label.new()
		empty.text = "无"
		UiStylesClass.apply_label_hint_dark(empty)
		var fs := 13
		if Globals != null:
			fs = int(Globals.get_scaled_font_size(13))
		empty.add_theme_font_size_override("font_size", fs)
		inventory_tokens_flow.add_child(empty)

func _build_inventory_token_item(product_id: String, count: int) -> Control:
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 4)

	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(22, 22)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture = _get_product_icon_texture(product_id)
	hbox.add_child(icon)

	var label := Label.new()
	label.text = "×%d" % count
	var fs := 14
	if Globals != null:
		fs = int(Globals.get_scaled_font_size(14))
	label.add_theme_font_size_override("font_size", fs)
	label.add_theme_color_override("font_color", Color(0.17, 0.13, 0.09, 1))
	hbox.add_child(label)

	var name := _get_product_display_name(product_id)
	hbox.tooltip_text = "%s ×%d" % [name, count]
	return hbox

func _get_product_display_name(product_id: String) -> String:
	if product_id.is_empty():
		return ""
	var pid := str(product_id)
	if pid == "cola":
		pid = "soda"
	if ProductRegistryClass.is_loaded():
		var def_val = ProductRegistryClass.get_def(pid)
		if def_val != null and (def_val is ProductDef):
			var def: ProductDef = def_val
			if not def.name.is_empty():
				return def.name
	return pid

func _get_product_icon_texture(product_id: String) -> Texture2D:
	_ensure_skin()
	if _skin == null or not _skin.has_method("get_product_icon_texture"):
		return null
	var pid := str(product_id)
	if pid == "cola":
		pid = "soda"
	return _skin.get_product_icon_texture(pid)

func _get_fridge_capacity_for_player(player: Dictionary) -> int:
	if player == null:
		return -1
	var milestones_val = player.get("milestones", null)
	if not (milestones_val is Array):
		return -1
	if not MilestoneRegistry.is_loaded():
		return -1

	var milestones: Array = milestones_val
	var has_fridge := false
	var capacity := 0

	for i in range(milestones.size()):
		var mid_val = milestones[i]
		if not (mid_val is String):
			continue
		var mid: String = str(mid_val)
		if mid.is_empty():
			continue
		var def_val = MilestoneRegistry.get_def(mid)
		if not (def_val is MilestoneDef):
			continue
		var def: MilestoneDef = def_val
		for e_i in range(def.effects.size()):
			var eff_val = def.effects[e_i]
			if not (eff_val is Dictionary):
				continue
			var eff: Dictionary = eff_val
			var type_val = eff.get("type", null)
			if not (type_val is String):
				continue
			if str(type_val) != "gain_fridge":
				continue
			var value_val = eff.get("value", null)
			if value_val is int:
				has_fridge = true
				capacity = maxi(capacity, int(value_val))
			elif value_val is float:
				var f: float = float(value_val)
				if f == int(f):
					has_fridge = true
					capacity = maxi(capacity, int(f))

	return capacity if has_fridge else -1

# === 里程碑紧凑显示 ===
func _refresh_milestones_compact() -> void:
	if not is_instance_valid(milestones_list):
		return

	var row_sep := 4
	if Globals != null:
		row_sep = maxi(2, int(Globals.get_scaled_font_size(4)))
	milestones_list.add_theme_constant_override("separation", row_sep)

	for c in milestones_list.get_children():
		if is_instance_valid(c):
			c.queue_free()

	if _game_state == null:
		_add_milestone_empty_label()
		return

	var view_id := _resolve_view_player_id()
	if view_id < 0 or view_id >= _game_state.players.size():
		_add_milestone_empty_label()
		return

	var player_val = _game_state.players[view_id]
	var player: Dictionary = player_val if player_val is Dictionary else {}
	var player_milestones: Array = Array(player.get("milestones", []))
	var claimed_set := {}
	for pm in player_milestones:
		var pm_id := str(pm).strip_edges()
		if pm_id.is_empty():
			continue
		claimed_set[pm_id] = true

	# 构建里程碑池计数
	var pool_counts := {}
	for v in _game_state.milestone_pool:
		var mid := str(v)
		if mid.is_empty():
			continue
		pool_counts[mid] = int(pool_counts.get(mid, 0)) + 1

	var all_ids := _get_all_milestone_ids_for_left_panel()
	if all_ids.is_empty():
		_add_milestone_empty_label()
		return

	var entries: Array[Dictionary] = []
	for ms_id in all_ids:
		var def = MilestoneRegistry.get_def(ms_id) if MilestoneRegistry.is_loaded() else null
		var category := _get_milestone_category(ms_id, def)
		var accent: Color = _get_milestone_accent_color(ms_id, category)
		entries.append({
			"id": ms_id,
			"def": def,
			"is_claimed": bool(claimed_set.get(ms_id, false)),
			"in_pool": int(pool_counts.get(ms_id, 0)) > 0,
			"color_rank": _get_milestone_color_sort_rank(accent),
			"category_rank": _get_milestone_category_sort_rank(category),
			"display_name": _get_milestone_display_name(ms_id, def),
		})

	if entries.size() > 1:
		entries.sort_custom(Callable(self, "_sort_milestones_compact_entries"))

	for entry in entries:
		var row := _create_milestone_compact_row(
			str(entry.get("id", "")),
			entry.get("def", null),
			bool(entry.get("is_claimed", false)),
			bool(entry.get("in_pool", false))
		)
		milestones_list.add_child(row)

func _add_milestone_empty_label() -> void:
	var empty := Label.new()
	empty.text = "暂无里程碑"
	UiStylesClass.apply_label_hint_dark(empty)
	var fs := 16
	if Globals != null:
		fs = int(Globals.get_scaled_font_size(16))
	empty.add_theme_font_size_override("font_size", fs)
	milestones_list.add_child(empty)

func _create_milestone_compact_row(milestone_id: String, milestone_def, is_claimed: bool, in_pool: bool) -> Control:
	var wrapper := Control.new()
	var row_min_h := 36
	if Globals != null:
		row_min_h = maxi(32, int(Globals.get_scaled_font_size(36)))
	wrapper.custom_minimum_size = Vector2(0, row_min_h)
	wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# 使用 PASS 让滚轮事件可以上传到 ScrollContainer，避免里程碑过多时无法滚动。
	wrapper.mouse_filter = Control.MOUSE_FILTER_PASS
	wrapper.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	var category := _get_milestone_category(milestone_id, milestone_def)
	var accent: Color = _get_milestone_accent_color(milestone_id, category)
	var scroll_gutter := _get_milestone_scroll_gutter()

	var card := PanelContainer.new()
	card.anchor_right = 1.0
	card.anchor_bottom = 1.0
	card.offset_right = -scroll_gutter
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_theme_stylebox_override("panel", _build_milestone_row_style(accent, is_claimed, in_pool))
	wrapper.add_child(card)

	var margin := MarginContainer.new()
	margin.anchor_right = 1.0
	margin.anchor_bottom = 1.0
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 7)
	margin.add_theme_constant_override("margin_right", 6)
	margin.add_theme_constant_override("margin_top", 2)
	margin.add_theme_constant_override("margin_bottom", 2)
	card.add_child(margin)

	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 8)
	margin.add_child(row)

	# 状态图标
	var icon_label := Label.new()
	var fs_icon := 18
	if Globals != null:
		fs_icon = int(Globals.get_scaled_font_size(18))
	icon_label.add_theme_font_size_override("font_size", fs_icon)

	if is_claimed:
		icon_label.text = "✓"
		icon_label.add_theme_color_override("font_color", MILESTONE_COLOR_CLAIMED)
	elif in_pool:
		icon_label.text = "○"
		icon_label.add_theme_color_override("font_color", MILESTONE_COLOR_AVAILABLE)
	else:
		icon_label.text = "○"
		icon_label.add_theme_color_override("font_color", MILESTONE_COLOR_GONE)

	row.add_child(icon_label)

	# 里程碑名称
	var name_label := Label.new()
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var fs_name := 18
	if Globals != null:
		fs_name = int(Globals.get_scaled_font_size(18))
	name_label.add_theme_font_size_override("font_size", fs_name)

	name_label.text = _get_milestone_display_name(milestone_id, milestone_def)
	if is_claimed:
		UiStylesClass.apply_label_dark(name_label)
	elif in_pool:
		UiStylesClass.apply_label_dark(name_label)
	else:
		UiStylesClass.apply_label_hint_dark(name_label)
		name_label.modulate.a = 0.85

	row.add_child(name_label)

	if not is_claimed and not in_pool:
		var strike := ColorRect.new()
		strike.mouse_filter = Control.MOUSE_FILTER_IGNORE
		strike.anchor_right = 1.0
		strike.anchor_top = 0.5
		strike.anchor_bottom = 0.5
		strike.offset_right = -scroll_gutter
		strike.offset_top = -1
		strike.offset_bottom = 1
		strike.color = Color(MILESTONE_COLOR_GONE.r, MILESTONE_COLOR_GONE.g, MILESTONE_COLOR_GONE.b, 0.95)
		wrapper.add_child(strike)

	# Tooltip: 里程碑效果描述
	var tip := _get_milestone_tooltip(milestone_id)
	wrapper.tooltip_text = tip
	row.tooltip_text = tip
	icon_label.tooltip_text = tip
	name_label.tooltip_text = tip
	wrapper.mouse_entered.connect(Callable(self, "_on_milestone_mouse_entered").bind(milestone_id, wrapper))
	wrapper.mouse_exited.connect(_on_milestone_mouse_exited)
	wrapper.gui_input.connect(Callable(self, "_on_milestone_gui_input").bind(milestone_id, wrapper))

	return wrapper

func _build_milestone_row_style(accent: Color, is_claimed: bool, in_pool: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	var bg_alpha := 0.18
	var border_alpha := 0.72
	if is_claimed:
		bg_alpha = 0.24
		border_alpha = 0.84
	elif in_pool:
		bg_alpha = 0.18
		border_alpha = 0.72
	else:
		bg_alpha = 0.10
		border_alpha = 0.36

	style.bg_color = Color(accent.r, accent.g, accent.b, bg_alpha)
	style.border_color = Color(accent.r, accent.g, accent.b, border_alpha)
	style.border_width_left = 3
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.set_corner_radius_all(5)
	return style

func _sort_milestones_compact_entries(a: Dictionary, b: Dictionary) -> bool:
	var color_a := int(a.get("color_rank", 999))
	var color_b := int(b.get("color_rank", 999))
	if color_a != color_b:
		return color_a < color_b

	var category_a := int(a.get("category_rank", 999))
	var category_b := int(b.get("category_rank", 999))
	if category_a != category_b:
		return category_a < category_b

	var name_a := str(a.get("display_name", ""))
	var name_b := str(b.get("display_name", ""))
	var name_cmp := name_a.naturalnocasecmp_to(name_b)
	if name_cmp != 0:
		return name_cmp < 0

	var id_a := str(a.get("id", ""))
	var id_b := str(b.get("id", ""))
	return id_a.naturalnocasecmp_to(id_b) < 0

func _get_milestone_color_sort_rank(accent: Color) -> int:
	if accent.is_equal_approx(MILESTONE_PALETTE_PURPLE):
		return 10
	if accent.is_equal_approx(MILESTONE_PALETTE_GRAY):
		return 20
	if accent.is_equal_approx(MILESTONE_PALETTE_MARKETING_BLUE):
		return 30
	if accent.is_equal_approx(MILESTONE_PALETTE_PRODUCE_GREEN):
		return 40
	if accent.is_equal_approx(MILESTONE_PALETTE_PROCURE_GREEN):
		return 50
	if accent.is_equal_approx(MILESTONE_PALETTE_PRICE_ORANGE):
		return 60
	if accent.is_equal_approx(MILESTONE_PALETTE_COFFEE_MINT):
		return 70
	if accent.is_equal_approx(MILESTONE_PALETTE_KETCHUP_DARK):
		return 80
	return 999

func _get_milestone_category_sort_rank(category: String) -> int:
	match category:
		"employee":
			return 10
		"finance":
			return 20
		"general":
			return 30
		"marketing":
			return 40
		"ops":
			return 50
		"expansion":
			return 60
		_:
			return 99

func _get_milestone_display_name(milestone_id: String, milestone_def) -> String:
	if milestone_def != null and milestone_def is MilestoneDef:
		var def: MilestoneDef = milestone_def
		var name := str(def.name).strip_edges()
		if not name.is_empty():
			return name
	return milestone_id

func _get_milestone_scroll_gutter() -> int:
	if Globals != null:
		return maxi(12, int(Globals.get_scaled_font_size(MILESTONE_SCROLL_GUTTER)))
	return MILESTONE_SCROLL_GUTTER

func _get_milestone_accent_color(milestone_id: String, category: String) -> Color:
	var mid := milestone_id.strip_edges()
	if MILESTONE_COLOR_BY_ID.has(mid):
		var c = MILESTONE_COLOR_BY_ID[mid]
		if c is Color:
			return c
	return _get_milestone_category_color(category)

func _get_milestone_category(milestone_id: String, milestone_def) -> String:
	if milestone_def != null and milestone_def is MilestoneDef:
		var def: MilestoneDef = milestone_def
		for e_val in def.effects:
			if not (e_val is Dictionary):
				continue
			var e: Dictionary = e_val
			var eff_type := str(e.get("type", "")).strip_edges()
			if eff_type.is_empty():
				continue
			var c := str(MILESTONE_EFFECT_CATEGORY.get(eff_type, "")).strip_edges()
			if not c.is_empty():
				return c
		for eid_val in def.effect_ids:
			var eid := str(eid_val).to_lower()
			if eid.find(":marketing:") >= 0:
				return "marketing"
			if eid.find(":dinnertime:") >= 0:
				return "ops"
			if eid.find(":payday:") >= 0:
				return "finance"

	var id := milestone_id.to_lower()
	if id.find("marketing") >= 0 or id.find("radio") >= 0 or id.find("billboard") >= 0 or id.find("airplane") >= 0:
		return "marketing"
	if id.find("hire") >= 0 or id.find("train") >= 0 or id.find("waitress") >= 0 or id.find("errand_boy") >= 0 or id.find("cart_operator") >= 0 or id.find("brand_") >= 0 or id.find("campaign_") >= 0 or id.find("recruit") >= 0:
		return "employee"
	if id.find("have_") >= 0 or id.find("pay_") >= 0 or id.find("price") >= 0 or id.find("discount") >= 0 or id.find("cfo") >= 0:
		return "finance"
	if id.find("new_restaurant") >= 0 or id.find("house") >= 0 or id.find("lobbyist") >= 0 or id.find("rural") >= 0:
		return "expansion"
	if id.find("produced") >= 0 or id.find("sold") >= 0 or id.find("drink") >= 0 or id.find("burger") >= 0 or id.find("pizza") >= 0 or id.find("lemonade") >= 0 or id.find("beer") >= 0 or id.find("coke") >= 0 or id.find("coffee") >= 0:
		return "ops"
	return "general"

func _get_milestone_category_color(category: String) -> Color:
	if MILESTONE_CATEGORY_COLORS.has(category):
		var c = MILESTONE_CATEGORY_COLORS[category]
		if c is Color:
			return c
	var fallback = MILESTONE_CATEGORY_COLORS.get("general", Color(0.42, 0.36, 0.28, 1.0))
	return fallback if fallback is Color else Color(0.42, 0.36, 0.28, 1.0)

func _get_all_milestone_ids_for_left_panel() -> Array[String]:
	var set := {}
	if MilestoneRegistry.is_loaded():
		for mid0 in MilestoneRegistry.get_all_ids():
			var mid_a := str(mid0).strip_edges()
			if mid_a.is_empty():
				continue
			set[mid_a] = true

	if _game_state != null:
		if _game_state.milestone_pool is Array:
			for v in Array(_game_state.milestone_pool):
				var mid_p := str(v).strip_edges()
				if mid_p.is_empty():
					continue
				set[mid_p] = true

		if _game_state.players is Array:
			for p_val in _game_state.players:
				if not (p_val is Dictionary):
					continue
				var p: Dictionary = p_val
				for m in Array(p.get("milestones", [])):
					var mid_m := str(m).strip_edges()
					if mid_m.is_empty():
						continue
					set[mid_m] = true

	var ids: Array[String] = []
	for k in set.keys():
		ids.append(str(k))
	ids.sort()
	return ids

func _get_milestone_tooltip(milestone_id: String) -> String:
	if not MilestoneRegistry.is_loaded():
		return milestone_id

	var def_val = MilestoneRegistry.get_def(milestone_id)
	if not (def_val is MilestoneDef):
		return milestone_id

	var def: MilestoneDef = def_val
	var lines: Array[String] = []
	lines.append(def.name if not def.name.is_empty() else milestone_id)

	return "\n".join(lines)

func _get_preview_manager():
	var tree := get_tree()
	if tree == null:
		return null
	for n in tree.get_nodes_in_group("employee_card_preview_manager"):
		if n != null and is_instance_valid(n):
			if n.has_method("request_milestone_preview") or n.has_method("show_milestone_immediate"):
				return n
	return null

func _on_milestone_mouse_entered(milestone_id: String, control: Control) -> void:
	var mgr = _get_preview_manager()
	if mgr == null:
		return
	if control == null or not is_instance_valid(control):
		return
	if not mgr.has_method("request_milestone_preview"):
		return
	var pos: Vector2 = control.get_global_rect().position + (control.size / 2.0)
	mgr.request_milestone_preview(str(milestone_id), pos)

func _on_milestone_mouse_exited() -> void:
	var mgr = _get_preview_manager()
	if mgr == null:
		return
	if mgr.has_method("hide_preview"):
		mgr.hide_preview()

func _on_milestone_gui_input(event: InputEvent, milestone_id: String, control: Control) -> void:
	if not (event is InputEventMouseButton):
		return
	var e: InputEventMouseButton = event
	if e.button_index != MOUSE_BUTTON_LEFT or not e.pressed:
		return
	var mgr = _get_preview_manager()
	if mgr == null:
		return
	if control == null or not is_instance_valid(control):
		return
	if not mgr.has_method("show_milestone_immediate"):
		return
	var pos: Vector2 = control.get_global_rect().position + (control.size / 2.0)
	mgr.show_milestone_immediate(str(milestone_id), pos)

func _role_to_category(role: String) -> String:
	match role:
		"manager", "recruit_train":
			return "管理"
		"produce_food", "procure_drink":
			return "厨房"
		"marketing":
			return "营销"
		_:
			return "其他"

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
	if not (event is InputEventMouseButton):
		return
	var e: InputEventMouseButton = event
	if e.button_index != MOUSE_BUTTON_LEFT or not e.pressed:
		return
	set_view_player(player_id)

func _on_view_logs_pressed() -> void:
	logs_requested.emit()
