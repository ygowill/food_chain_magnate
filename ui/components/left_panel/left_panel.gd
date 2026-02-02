# 左侧信息面板（P3/P4：渐进式落地）
# - 玩家纵向 Tab：切换 view_player
# - 摘要区：展示查看玩家的关键信息
# - Tab：员工（在职在上、手牌在下）/里程碑（日志为独立面板，由 Game 负责切换）
class_name LeftPanel
extends Control

signal logs_requested()

const UiSkinCacheClass = preload("res://ui/visual/ui_skin_cache.gd")
const MapCanvasDrawerClass = preload("res://ui/scenes/game/map_canvas_drawer.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const LeftPanelEmployeeIconsControllerClass = preload("res://ui/components/left_panel/left_panel_employee_icons_controller.gd")
const LeftPanelTurnLogControllerClass = preload("res://ui/components/left_panel/left_panel_turn_log_controller.gd")

@onready var player_tabs: HBoxContainer = $MarginContainer/HBoxContainer/PlayerTabs
@onready var summary_row: Control = $MarginContainer/HBoxContainer/Content/SummaryRow
@onready var summary_label: Label = $MarginContainer/HBoxContainer/Content/SummaryRow/SummaryLabel
@onready var inventory_title_label: Label = $MarginContainer/HBoxContainer/Content/SummaryRow/InventoryTitleLabel
@onready var inventory_tokens: HFlowContainer = $MarginContainer/HBoxContainer/Content/SummaryRow/InventoryTokens
@onready var tab_container: TabContainer = $MarginContainer/HBoxContainer/Content/TabContainer
@onready var hand_host: Control = get_node_or_null("MarginContainer/HBoxContainer/Content/TabContainer/Employees/EmployeesScroll/EmployeesContent/HandSection")
@onready var company_host: Control = get_node_or_null("MarginContainer/HBoxContainer/Content/TabContainer/Employees/EmployeesScroll/EmployeesContent/CompanySection")
@onready var milestone_panel: Control = $MarginContainer/HBoxContainer/Content/TabContainer/Milestones/MilestonePanel

@onready var hand_management_row: Control = $MarginContainer/HBoxContainer/Content/TabContainer/Employees/EmployeesScroll/EmployeesContent/HandSection/HandIconGroups/HandManagementRow
@onready var hand_kitchen_row: Control = $MarginContainer/HBoxContainer/Content/TabContainer/Employees/EmployeesScroll/EmployeesContent/HandSection/HandIconGroups/HandKitchenRow
@onready var hand_marketing_row: Control = $MarginContainer/HBoxContainer/Content/TabContainer/Employees/EmployeesScroll/EmployeesContent/HandSection/HandIconGroups/HandMarketingRow
@onready var hand_other_row: Control = $MarginContainer/HBoxContainer/Content/TabContainer/Employees/EmployeesScroll/EmployeesContent/HandSection/HandIconGroups/HandOtherRow
@onready var hand_management_icons: VBoxContainer = $MarginContainer/HBoxContainer/Content/TabContainer/Employees/EmployeesScroll/EmployeesContent/HandSection/HandIconGroups/HandManagementRow/Icons
@onready var hand_kitchen_icons: VBoxContainer = $MarginContainer/HBoxContainer/Content/TabContainer/Employees/EmployeesScroll/EmployeesContent/HandSection/HandIconGroups/HandKitchenRow/Icons
@onready var hand_marketing_icons: VBoxContainer = $MarginContainer/HBoxContainer/Content/TabContainer/Employees/EmployeesScroll/EmployeesContent/HandSection/HandIconGroups/HandMarketingRow/Icons
@onready var hand_other_icons: VBoxContainer = $MarginContainer/HBoxContainer/Content/TabContainer/Employees/EmployeesScroll/EmployeesContent/HandSection/HandIconGroups/HandOtherRow/Icons

@onready var company_management_row: Control = $MarginContainer/HBoxContainer/Content/TabContainer/Employees/EmployeesScroll/EmployeesContent/CompanySection/CompanyIconGroups/CompanyManagementRow
@onready var company_kitchen_row: Control = $MarginContainer/HBoxContainer/Content/TabContainer/Employees/EmployeesScroll/EmployeesContent/CompanySection/CompanyIconGroups/CompanyKitchenRow
@onready var company_marketing_row: Control = $MarginContainer/HBoxContainer/Content/TabContainer/Employees/EmployeesScroll/EmployeesContent/CompanySection/CompanyIconGroups/CompanyMarketingRow
@onready var company_other_row: Control = $MarginContainer/HBoxContainer/Content/TabContainer/Employees/EmployeesScroll/EmployeesContent/CompanySection/CompanyIconGroups/CompanyOtherRow
@onready var company_management_icons: VBoxContainer = $MarginContainer/HBoxContainer/Content/TabContainer/Employees/EmployeesScroll/EmployeesContent/CompanySection/CompanyIconGroups/CompanyManagementRow/Icons
@onready var company_kitchen_icons: VBoxContainer = $MarginContainer/HBoxContainer/Content/TabContainer/Employees/EmployeesScroll/EmployeesContent/CompanySection/CompanyIconGroups/CompanyKitchenRow/Icons
@onready var company_marketing_icons: VBoxContainer = $MarginContainer/HBoxContainer/Content/TabContainer/Employees/EmployeesScroll/EmployeesContent/CompanySection/CompanyIconGroups/CompanyMarketingRow/Icons
@onready var company_other_icons: VBoxContainer = $MarginContainer/HBoxContainer/Content/TabContainer/Employees/EmployeesScroll/EmployeesContent/CompanySection/CompanyIconGroups/CompanyOtherRow/Icons

@onready var turn_log_section: Control = $MarginContainer/HBoxContainer/Content/TurnLogSection
@onready var turn_log_toggle_button: Button = $MarginContainer/HBoxContainer/Content/TurnLogSection/MarginContainer/VBoxContainer/HeaderRow/ToggleButton
@onready var turn_log_to_logs_button: Button = $MarginContainer/HBoxContainer/Content/TurnLogSection/MarginContainer/VBoxContainer/HeaderRow/ToLogsButton
@onready var turn_log_lines: VBoxContainer = $MarginContainer/HBoxContainer/Content/TurnLogSection/MarginContainer/VBoxContainer/LogLines

const TAB_EMPLOYEES := 0
const TAB_MILESTONES := 1

const PRODUCT_NAMES: Dictionary = {
	"burger": "汉堡",
	"pizza": "披萨",
	"lemonade": "柠檬水",
	"beer": "啤酒",
	"soda": "苏打",
}

const EMPLOYEE_CATEGORY_ORDER := ["管理", "厨房", "营销", "其他"]
const EMPLOYEE_CATEGORY_ICON: Dictionary = {
	"管理": "👔",
	"厨房": "👨‍🍳",
	"营销": "📢",
	"其他": "⭐",
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
	_init_tab_titles()
	if is_instance_valid(summary_label):
		summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if is_instance_valid(tab_container):
		tab_container.tab_changed.connect(_on_tab_changed)
	_rebuild_player_tabs()
	apply_font_settings()
	_refresh()

func _ensure_controllers() -> void:
	if _employee_icons_controller == null or not is_instance_valid(_employee_icons_controller):
		_employee_icons_controller = LeftPanelEmployeeIconsControllerClass.new()
	if _employee_icons_controller != null and is_instance_valid(_employee_icons_controller):
		_employee_icons_controller.setup(self)

	if _turn_log_controller == null or not is_instance_valid(_turn_log_controller):
		_turn_log_controller = LeftPanelTurnLogControllerClass.new()
	if _turn_log_controller != null and is_instance_valid(_turn_log_controller):
		_turn_log_controller.setup(self)

func _init_tab_titles() -> void:
	if not is_instance_valid(tab_container):
		return
	# 依赖节点顺序：Employees / Milestones
	if tab_container.get_tab_count() >= 1:
		tab_container.set_tab_title(TAB_EMPLOYEES, "员工")
	if tab_container.get_tab_count() >= 2:
		tab_container.set_tab_title(TAB_MILESTONES, "里程碑")

func apply_font_settings() -> void:
	var fs_summary := 16
	var fs_sub := 14
	if Globals != null:
		fs_summary = int(Globals.get_scaled_font_size(16))
		fs_sub = int(Globals.get_scaled_font_size(14))

	if is_instance_valid(summary_label):
		summary_label.add_theme_font_size_override("font_size", fs_summary)
	if is_instance_valid(inventory_title_label):
		inventory_title_label.add_theme_font_size_override("font_size", fs_sub)

func set_game_state(state: GameState) -> void:
	_game_state = state
	_rebuild_player_logo_ids()
	_ensure_skin()
	var count := 0
	if state != null and state.players is Array:
		count = state.players.size()
	if count != _player_count:
		_player_count = count
		_rebuild_player_tabs()
	else:
		_update_player_tab_icons()
	_refresh_milestones()
	_maybe_auto_select_tab_for_phase()
	_refresh()

func set_current_player(player_id: int) -> void:
	_current_player_id = player_id
	_update_tab_styles()

func set_view_player(player_id: int) -> void:
	_ensure_controllers()
	_view_player_id = player_id
	_update_tab_styles()
	_refresh_summary()
	if _employee_icons_controller != null and is_instance_valid(_employee_icons_controller):
		_employee_icons_controller.refresh()
	_refresh_milestones()
	if _turn_log_controller != null and is_instance_valid(_turn_log_controller):
		_turn_log_controller.refresh()

func select_tab(tab_id: String) -> void:
	if not is_instance_valid(tab_container):
		return
	match tab_id:
		"hand":
			tab_container.current_tab = TAB_EMPLOYEES
		"company":
			tab_container.current_tab = TAB_EMPLOYEES
		"milestones":
			tab_container.current_tab = TAB_MILESTONES
		"logs":
			logs_requested.emit()

func bind_game_log_panel(panel: Node) -> void:
	_ensure_controllers()
	if panel == null or not is_instance_valid(panel):
		return
	if _turn_log_controller != null and is_instance_valid(_turn_log_controller):
		_turn_log_controller.bind_log_panel(panel)

# 兼容旧调用：不再 reparent 到 Logs Tab（日志视图由 Game 负责切换）
func attach_game_log_panel(panel: Node) -> void:
	bind_game_log_panel(panel)

func attach_hand_area(panel: Node) -> void:
	_attach_panel_to_host(panel, hand_host)
	_attached_hand_area = panel

func detach_hand_area(panel: Node, target_parent: Node) -> void:
	_detach_panel_to_parent(panel, target_parent)
	_attached_hand_area = null

func attach_company_structure(panel: Node) -> void:
	_attach_panel_to_host(panel, company_host)
	_attached_company_structure = panel

func detach_company_structure(panel: Node, target_parent: Node) -> void:
	_detach_panel_to_parent(panel, target_parent)
	_attached_company_structure = null

func _attach_panel_to_host(panel: Node, host: Node) -> void:
	if panel == null or not is_instance_valid(panel):
		return
	if host == null or not is_instance_valid(host):
		return
	if not (panel is Control):
		return

	var c: Control = panel
	if c.get_parent() != host:
		var old_parent := c.get_parent()
		if is_instance_valid(old_parent):
			old_parent.remove_child(c)
		host.add_child(c)

	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.offset_left = 0
	c.offset_top = 0
	c.offset_right = 0
	c.offset_bottom = 0

func _detach_panel_to_parent(panel: Node, target_parent: Node) -> void:
	if panel == null or not is_instance_valid(panel):
		return
	if target_parent == null or not is_instance_valid(target_parent):
		return
	if panel.get_parent() == target_parent:
		return

	var old_parent := panel.get_parent()
	if is_instance_valid(old_parent):
		old_parent.remove_child(panel)
	target_parent.add_child(panel)

	if panel is Control:
		var c: Control = panel
		c.set_anchors_preset(Control.PRESET_FULL_RECT)
		c.offset_left = 0
		c.offset_top = 0
		c.offset_right = 0
		c.offset_bottom = 0

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
		btn.custom_minimum_size = Vector2(52, 52)
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

	var logo_count := MapCanvasDrawerClass.RESTAURANT_LOGO_PIECE_IDS.size()
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
	if not (_skin.has_method("get_piece_texture")):
		return null
	var logo_count := MapCanvasDrawerClass.RESTAURANT_LOGO_PIECE_IDS.size()
	if logo_count <= 0:
		return null
	var logo_id := int(_player_restaurant_logo_ids.get(player_id, -1))
	if logo_id < 0 or logo_id >= logo_count:
		logo_id = _fallback_logo_id_for_player(player_id, _fallback_logo_ids)
	var key: String = MapCanvasDrawerClass.RESTAURANT_LOGO_PIECE_IDS[logo_id]
	return _skin.get_piece_texture(key)

func _apply_player_tab_icon(btn: Button, player_id: int) -> void:
	if btn == null or not is_instance_valid(btn):
		return
	var tex := _get_player_restaurant_logo_texture(player_id)
	if tex != null:
		btn.text = ""
		btn.icon = tex
		btn.expand_icon = true
		btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
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

		var color := Globals.get_player_color(i)
		var is_current := i == _current_player_id
		var is_view := i == view_id

		var bg := Color("#f4edd1")
		bg.a = 0.95

		var normal := StyleBoxFlat.new()
		normal.bg_color = bg
		normal.border_color = Color(color.r, color.g, color.b, 0.85)
		normal.set_border_width_all(1)
		normal.set_corner_radius_all(26)

		var pressed := StyleBoxFlat.new()
		pressed.bg_color = bg
		pressed.border_color = color
		pressed.set_border_width_all(3 if is_view else 1)
		pressed.set_corner_radius_all(26)

		# 当前行动玩家：额外高亮边框（优先级高于 view）
		if is_current:
			var current_border := Color(0.95, 0.95, 0.95, 0.9)
			pressed.border_color = current_border
			pressed.set_border_width_all(3)
			if not is_view:
				normal.border_color = current_border
				normal.set_border_width_all(3)

		btn.add_theme_stylebox_override("normal", normal)
		btn.add_theme_stylebox_override("pressed", pressed)
		btn.add_theme_stylebox_override("hover", pressed)

		btn.add_theme_color_override("font_color", Color(0.15, 0.15, 0.15, 0.9))

func _refresh() -> void:
	_ensure_controllers()
	_refresh_summary()
	if _employee_icons_controller != null and is_instance_valid(_employee_icons_controller):
		_employee_icons_controller.refresh()
	_update_tab_styles()
	if _turn_log_controller != null and is_instance_valid(_turn_log_controller):
		_turn_log_controller.refresh()

func _refresh_summary() -> void:
	if not is_instance_valid(summary_label):
		return
	if _game_state == null:
		summary_label.text = "查看: -"
		_refresh_inventory_ui({}, -1)
		return

	var view_id := _resolve_view_player_id()
	if view_id < 0 or view_id >= _game_state.players.size():
		summary_label.text = "查看: -"
		_refresh_inventory_ui({}, -1)
		return

	var player_val = _game_state.players[view_id]
	var player: Dictionary = player_val if player_val is Dictionary else {}

	var cash := int(player.get("cash", 0))

	var line1_parts: Array[String] = []
	line1_parts.append("查看: %s" % Globals.get_player_name(view_id))
	line1_parts.append("💰 $%d" % cash)

	var emp_parts := _build_employee_summary_parts(player)
	var emp_text := "员工: 0"
	if not emp_parts.is_empty():
		emp_text = "员工: %s" % " ".join(emp_parts)

	summary_label.text = "%s\n%s" % [" | ".join(line1_parts), emp_text]

	var inv_val = player.get("inventory", {})
	var inv: Dictionary = inv_val if inv_val is Dictionary else {}
	_refresh_inventory_ui(inv, _get_fridge_capacity_for_player(player))

func _refresh_inventory_ui(inv: Dictionary, fridge_capacity: int) -> void:
	if not is_instance_valid(inventory_title_label) or not is_instance_valid(inventory_tokens):
		return

	if fridge_capacity < 0:
		inventory_title_label.text = "库存（无冰箱）"
	else:
		inventory_title_label.text = "库存（冰箱：总量≤%d）" % fridge_capacity

	for c in inventory_tokens.get_children():
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
		inventory_tokens.add_child(_build_inventory_token_item(product_id, count))
		added += 1

	if added <= 0:
		var empty := Label.new()
		empty.text = "无"
		empty.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 0.9))
		var fs := 14
		if Globals != null:
			fs = int(Globals.get_scaled_font_size(14))
		empty.add_theme_font_size_override("font_size", fs)
		inventory_tokens.add_child(empty)

func _build_inventory_token_item(product_id: String, count: int) -> Control:
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 2)

	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(18, 18)
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
	label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.95, 1))
	hbox.add_child(label)

	var name := str(PRODUCT_NAMES.get(product_id, product_id))
	hbox.tooltip_text = "%s ×%d" % [name, count]
	return hbox

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

func _build_employee_summary_parts(player: Dictionary) -> Array[String]:
	if player == null:
		return []

	var counts: Dictionary = {}
	for cat in EMPLOYEE_CATEGORY_ORDER:
		counts[cat] = 0

	var sources := [
		player.get("employees", []),
		player.get("reserve_employees", []),
		player.get("busy_marketers", []),
	]

	for src_val in sources:
		for e_val in Array(src_val):
			var emp_id := str(e_val).strip_edges()
			if emp_id.is_empty():
				continue
			var cat := "其他"
			if EmployeeRegistry.is_loaded():
				var def_val = EmployeeRegistry.get_def(emp_id)
				if def_val is EmployeeDef:
					var def: EmployeeDef = def_val
					cat = _role_to_category(def.get_role())
			counts[cat] = int(counts.get(cat, 0)) + 1

	var out: Array[String] = []
	for cat2 in EMPLOYEE_CATEGORY_ORDER:
		var n := int(counts.get(cat2, 0))
		if n <= 0:
			continue
		var icon := str(EMPLOYEE_CATEGORY_ICON.get(cat2, cat2))
		out.append("%s×%d" % [icon, n])
	return out

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

func _refresh_milestones() -> void:
	if not is_instance_valid(milestone_panel):
		return
	if _game_state == null:
		return
	if not (_game_state.players is Array) or _game_state.players.is_empty():
		return

	var view_id := _resolve_view_player_id()
	var player_val = _game_state.players[view_id]
	var player: Dictionary = player_val if player_val is Dictionary else {}

	if milestone_panel.has_method("set_milestone_pool"):
		milestone_panel.call("set_milestone_pool", _game_state.milestone_pool)
	if milestone_panel.has_method("set_player_milestones"):
		milestone_panel.call("set_player_milestones", player.get("milestones", []))
	if milestone_panel.has_method("set_global_view"):
		milestone_panel.call("set_global_view", false)
	if milestone_panel.has_method("set_rules"):
		milestone_panel.call("set_rules", _game_state.rules if (_game_state.rules is Dictionary) else {})
	if milestone_panel.has_method("refresh"):
		milestone_panel.call("refresh")

func _maybe_auto_select_tab_for_phase() -> void:
	if _game_state == null:
		return
	if not is_instance_valid(tab_container):
		return

	var phase := str(_game_state.phase)
	if phase == _last_phase:
		return
	_last_phase = phase

	if phase == DefsClass.PHASE_RESTRUCTURING:
		tab_container.current_tab = TAB_EMPLOYEES

func _resolve_view_player_id() -> int:
	if _game_state == null:
		return 0
	var view_id := _view_player_id
	if view_id < 0 or view_id >= _game_state.players.size():
		# 联机模式：默认查看本地玩家，避免跟随 current_player 造成误导。
		if NetContext != null and NetContext.mode == NetContext.Mode.ONLINE_CLIENT and int(NetContext.local_player_id) >= 0:
			view_id = int(NetContext.local_player_id)
		else:
			view_id = _current_player_id
	if view_id < 0 or view_id >= _game_state.players.size():
		view_id = 0
	view_id = clamp(view_id, 0, maxi(0, _game_state.players.size() - 1))
	return view_id

func _on_tab_changed(_tab_index: int) -> void:
	_update_tab_styles()

func _on_player_tab_pressed(player_id: int) -> void:
	set_view_player(player_id)

func _on_player_tab_toggled(pressed: bool, player_id: int) -> void:
	if not pressed:
		return
	set_view_player(player_id)
