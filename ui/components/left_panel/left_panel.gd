# 左侧信息面板（P3/P4：渐进式落地）
# - 玩家纵向 Tab：切换 view_player
# - 摘要区：展示查看玩家的关键信息
# - Tab：手牌/公司结构/里程碑（日志为独立面板，由 Game 负责切换）
class_name LeftPanel
extends Control

signal player_selected(player_id: int)
signal logs_requested()

@onready var player_tabs: VBoxContainer = $MarginContainer/HBoxContainer/PlayerTabs
@onready var summary_row: Control = $MarginContainer/HBoxContainer/Content/SummaryRow
@onready var summary_label: Label = $MarginContainer/HBoxContainer/Content/SummaryRow/SummaryLabel
@onready var tab_container: TabContainer = $MarginContainer/HBoxContainer/Content/TabContainer
@onready var hand_host: Control = $MarginContainer/HBoxContainer/Content/TabContainer/Hand/HandHost
@onready var company_host: Control = $MarginContainer/HBoxContainer/Content/TabContainer/Company/CompanyHost
@onready var milestone_panel: Control = $MarginContainer/HBoxContainer/Content/TabContainer/Milestones/MilestonePanel

@onready var hand_management_row: Control = $MarginContainer/HBoxContainer/Content/TabContainer/Hand/HandHost/HandIconScroll/HandIconGroups/HandManagementRow
@onready var hand_kitchen_row: Control = $MarginContainer/HBoxContainer/Content/TabContainer/Hand/HandHost/HandIconScroll/HandIconGroups/HandKitchenRow
@onready var hand_marketing_row: Control = $MarginContainer/HBoxContainer/Content/TabContainer/Hand/HandHost/HandIconScroll/HandIconGroups/HandMarketingRow
@onready var hand_other_row: Control = $MarginContainer/HBoxContainer/Content/TabContainer/Hand/HandHost/HandIconScroll/HandIconGroups/HandOtherRow
@onready var hand_management_icons: VBoxContainer = $MarginContainer/HBoxContainer/Content/TabContainer/Hand/HandHost/HandIconScroll/HandIconGroups/HandManagementRow/Icons
@onready var hand_kitchen_icons: VBoxContainer = $MarginContainer/HBoxContainer/Content/TabContainer/Hand/HandHost/HandIconScroll/HandIconGroups/HandKitchenRow/Icons
@onready var hand_marketing_icons: VBoxContainer = $MarginContainer/HBoxContainer/Content/TabContainer/Hand/HandHost/HandIconScroll/HandIconGroups/HandMarketingRow/Icons
@onready var hand_other_icons: VBoxContainer = $MarginContainer/HBoxContainer/Content/TabContainer/Hand/HandHost/HandIconScroll/HandIconGroups/HandOtherRow/Icons

@onready var company_management_row: Control = $MarginContainer/HBoxContainer/Content/TabContainer/Company/CompanyHost/CompanyIconScroll/CompanyIconGroups/CompanyManagementRow
@onready var company_kitchen_row: Control = $MarginContainer/HBoxContainer/Content/TabContainer/Company/CompanyHost/CompanyIconScroll/CompanyIconGroups/CompanyKitchenRow
@onready var company_marketing_row: Control = $MarginContainer/HBoxContainer/Content/TabContainer/Company/CompanyHost/CompanyIconScroll/CompanyIconGroups/CompanyMarketingRow
@onready var company_other_row: Control = $MarginContainer/HBoxContainer/Content/TabContainer/Company/CompanyHost/CompanyIconScroll/CompanyIconGroups/CompanyOtherRow
@onready var company_management_icons: VBoxContainer = $MarginContainer/HBoxContainer/Content/TabContainer/Company/CompanyHost/CompanyIconScroll/CompanyIconGroups/CompanyManagementRow/Icons
@onready var company_kitchen_icons: VBoxContainer = $MarginContainer/HBoxContainer/Content/TabContainer/Company/CompanyHost/CompanyIconScroll/CompanyIconGroups/CompanyKitchenRow/Icons
@onready var company_marketing_icons: VBoxContainer = $MarginContainer/HBoxContainer/Content/TabContainer/Company/CompanyHost/CompanyIconScroll/CompanyIconGroups/CompanyMarketingRow/Icons
@onready var company_other_icons: VBoxContainer = $MarginContainer/HBoxContainer/Content/TabContainer/Company/CompanyHost/CompanyIconScroll/CompanyIconGroups/CompanyOtherRow/Icons

@onready var turn_log_section: Control = $MarginContainer/HBoxContainer/Content/TurnLogSection
@onready var turn_log_toggle_button: Button = $MarginContainer/HBoxContainer/Content/TurnLogSection/MarginContainer/VBoxContainer/HeaderRow/ToggleButton
@onready var turn_log_to_logs_button: Button = $MarginContainer/HBoxContainer/Content/TurnLogSection/MarginContainer/VBoxContainer/HeaderRow/ToLogsButton
@onready var turn_log_lines: VBoxContainer = $MarginContainer/HBoxContainer/Content/TurnLogSection/MarginContainer/VBoxContainer/LogLines

const TAB_HAND := 0
const TAB_COMPANY := 1
const TAB_MILESTONES := 2

const PRODUCT_NAMES: Dictionary = {
	"burger": "汉堡",
	"pizza": "披萨",
	"cola": "可乐",
	"lemonade": "柠檬水",
	"beer": "啤酒",
}

const PRODUCT_EMOJI: Dictionary = {
	"burger": "🍔",
	"pizza": "🍕",
	"cola": "🥤",
	"lemonade": "🥤",
	"beer": "🍺",
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

var _tab_buttons: Array[Button] = []
var _attached_log_panel: Node = null
var _attached_hand_area: Node = null
var _attached_company_structure: Node = null
var _last_phase: String = ""

func _ready() -> void:
	_init_tab_titles()
	if is_instance_valid(summary_label):
		summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if is_instance_valid(tab_container):
		tab_container.tab_changed.connect(_on_tab_changed)
	if is_instance_valid(turn_log_toggle_button):
		turn_log_toggle_button.toggled.connect(_on_turn_log_toggled)
	if is_instance_valid(turn_log_to_logs_button):
		turn_log_to_logs_button.pressed.connect(_on_turn_log_to_logs_pressed)
	_rebuild_player_tabs()
	_refresh()

func _init_tab_titles() -> void:
	if not is_instance_valid(tab_container):
		return
	# 依赖节点顺序：Hand / Company / Milestones
	if tab_container.get_tab_count() >= 1:
		tab_container.set_tab_title(TAB_HAND, "手牌")
	if tab_container.get_tab_count() >= 2:
		tab_container.set_tab_title(TAB_COMPANY, "在职")
	if tab_container.get_tab_count() >= 3:
		tab_container.set_tab_title(TAB_MILESTONES, "里程碑")

func set_game_state(state: GameState) -> void:
	_game_state = state
	var count := 0
	if state != null and state.players is Array:
		count = state.players.size()
	if count != _player_count:
		_player_count = count
		_rebuild_player_tabs()
	_refresh_milestones()
	_maybe_auto_select_tab_for_phase()
	_refresh()

func set_current_player(player_id: int) -> void:
	_current_player_id = player_id
	_update_tab_styles()

func set_view_player(player_id: int) -> void:
	_view_player_id = player_id
	_update_tab_styles()
	_refresh_summary()
	_refresh_employee_icons()
	_refresh_milestones()
	_refresh_turn_log()

func select_tab(tab_id: String) -> void:
	if not is_instance_valid(tab_container):
		return
	match tab_id:
		"hand":
			tab_container.current_tab = TAB_HAND
		"company":
			tab_container.current_tab = TAB_COMPANY
		"milestones":
			tab_container.current_tab = TAB_MILESTONES
		"logs":
			logs_requested.emit()

func bind_game_log_panel(panel: Node) -> void:
	if panel == null or not is_instance_valid(panel):
		return
	_detach_log_panel_signals()
	_attached_log_panel = panel
	_attach_log_panel_signals()
	_refresh_turn_log()

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
		btn.custom_minimum_size = Vector2(44, 44)
		btn.text = str(i + 1)
		btn.toggled.connect(_on_player_tab_toggled.bind(i))
		player_tabs.add_child(btn)
		_tab_buttons.append(btn)

	_update_tab_styles()

func _update_tab_styles() -> void:
	for i in range(_tab_buttons.size()):
		var btn := _tab_buttons[i]
		if not is_instance_valid(btn):
			continue

		btn.set_pressed_no_signal(i == _view_player_id)

		var color := Globals.get_player_color(i)
		var is_current := i == _current_player_id
		var is_view := i == _view_player_id

		var normal := StyleBoxFlat.new()
		normal.bg_color = Color(0.12, 0.12, 0.14, 0.85)
		normal.border_color = Color(0.25, 0.25, 0.3, 0.7)
		normal.set_border_width_all(1)
		normal.set_corner_radius_all(8)

		var pressed := StyleBoxFlat.new()
		pressed.bg_color = Color(color.r, color.g, color.b, 0.28) if is_view else normal.bg_color
		pressed.border_color = color if is_view else normal.border_color
		pressed.set_border_width_all(2 if is_view else 1)
		pressed.set_corner_radius_all(8)

		# 当前行动玩家：额外高亮边框（优先级高于 view）
		if is_current:
			pressed.border_color = Color(0.95, 0.95, 0.95, 0.9)
			pressed.set_border_width_all(2)
			if not is_view:
				normal.border_color = pressed.border_color
				normal.set_border_width_all(2)

		btn.add_theme_stylebox_override("normal", normal)
		btn.add_theme_stylebox_override("pressed", pressed)
		btn.add_theme_stylebox_override("hover", pressed)

		btn.add_theme_color_override("font_color", Color(1, 1, 1, 1))

func _refresh() -> void:
	_refresh_summary()
	_refresh_employee_icons()
	_update_tab_styles()
	_refresh_turn_log()

func _refresh_employee_icons() -> void:
	_clear_employee_icon_containers()

	if _game_state == null or not (_game_state.players is Array) or _game_state.players.is_empty():
		_update_employee_row_visibility()
		return

	var view_id := _resolve_view_player_id()
	if view_id < 0 or view_id >= _game_state.players.size():
		_update_employee_row_visibility()
		return

	var player_val = _game_state.players[view_id]
	var player: Dictionary = player_val if player_val is Dictionary else {}

	_build_hand_employee_icons(player)
	_build_company_employee_icons(player)
	_update_employee_row_visibility()

func _clear_employee_icon_containers() -> void:
	for c in [
		hand_management_icons,
		hand_kitchen_icons,
		hand_marketing_icons,
		hand_other_icons,
		company_management_icons,
		company_kitchen_icons,
		company_marketing_icons,
		company_other_icons,
	]:
		_clear_container_children(c)

func _clear_container_children(container: Node) -> void:
	if container == null or not is_instance_valid(container):
		return
	for ch in container.get_children():
		if is_instance_valid(ch):
			ch.queue_free()

func _build_hand_employee_icons(player: Dictionary) -> void:
	if player == null:
		return

	var reserve: Array[String] = []
	var busy: Array[String] = []

	for e in Array(player.get("reserve_employees", [])):
		var s := str(e).strip_edges()
		if not s.is_empty():
			reserve.append(s)
	for e2 in Array(player.get("busy_marketers", [])):
		var s2 := str(e2).strip_edges()
		if not s2.is_empty():
			busy.append(s2)

	reserve.sort()
	busy.sort()

	for emp_id in reserve:
		_add_employee_entry_to_category(_get_hand_icons_for_category(_get_employee_category(emp_id)), emp_id, false)
	for emp_id2 in busy:
		_add_employee_entry_to_category(_get_hand_icons_for_category(_get_employee_category(emp_id2)), emp_id2, true)

func _build_company_employee_icons(player: Dictionary) -> void:
	if player == null:
		return

	var employees: Array[String] = []
	for e in Array(player.get("employees", [])):
		var s := str(e).strip_edges()
		if not s.is_empty():
			employees.append(s)
	employees.sort()

	for emp_id in employees:
		_add_employee_entry_to_category(_get_company_icons_for_category(_get_employee_category(emp_id)), emp_id, false)

func _add_employee_entry_to_category(container: VBoxContainer, employee_id: String, busy: bool) -> void:
	if container == null or not is_instance_valid(container):
		return

	var emp_id := str(employee_id).strip_edges()
	if emp_id.is_empty():
		return

	var name := _get_employee_display_name(emp_id)
	var label_text := "• %s" % name
	if name != emp_id:
		label_text = "• %s (%s)" % [name, emp_id]
	if busy:
		label_text += "（忙）"

	var line := Label.new()
	line.text = label_text
	line.autowrap_mode = TextServer.AUTOWRAP_WORD
	line.add_theme_font_size_override("font_size", 14)
	if busy:
		line.add_theme_color_override("font_color", Color(0.9, 0.8, 0.5, 1))
	else:
		line.add_theme_color_override("font_color", Color(0.9, 0.9, 0.95, 1))
	container.add_child(line)

func _get_employee_display_name(employee_id: String) -> String:
	var emp_id := str(employee_id).strip_edges()
	if emp_id.is_empty():
		return ""
	if EmployeeRegistry.is_loaded():
		var def_val = EmployeeRegistry.get_def(emp_id)
		if def_val is EmployeeDef:
			var def: EmployeeDef = def_val
			var name := def.name.strip_edges()
			if not name.is_empty():
				return name
	return emp_id

func _get_employee_category(employee_id: String) -> String:
	var emp_id := str(employee_id).strip_edges()
	if emp_id.is_empty():
		return "其他"

	if EmployeeRegistry.is_loaded():
		var def_val = EmployeeRegistry.get_def(emp_id)
		if def_val is EmployeeDef:
			var def: EmployeeDef = def_val
			return _role_to_category(def.get_role())

	return "其他"

func _get_hand_icons_for_category(category: String) -> VBoxContainer:
	match category:
		"管理":
			return hand_management_icons
		"厨房":
			return hand_kitchen_icons
		"营销":
			return hand_marketing_icons
		_:
			return hand_other_icons

func _get_company_icons_for_category(category: String) -> VBoxContainer:
	match category:
		"管理":
			return company_management_icons
		"厨房":
			return company_kitchen_icons
		"营销":
			return company_marketing_icons
		_:
			return company_other_icons

func _update_employee_row_visibility() -> void:
	if is_instance_valid(hand_management_row) and is_instance_valid(hand_management_icons):
		hand_management_row.visible = hand_management_icons.get_child_count() > 0
	if is_instance_valid(hand_kitchen_row) and is_instance_valid(hand_kitchen_icons):
		hand_kitchen_row.visible = hand_kitchen_icons.get_child_count() > 0
	if is_instance_valid(hand_marketing_row) and is_instance_valid(hand_marketing_icons):
		hand_marketing_row.visible = hand_marketing_icons.get_child_count() > 0
	if is_instance_valid(hand_other_row) and is_instance_valid(hand_other_icons):
		hand_other_row.visible = hand_other_icons.get_child_count() > 0

	if is_instance_valid(company_management_row) and is_instance_valid(company_management_icons):
		company_management_row.visible = company_management_icons.get_child_count() > 0
	if is_instance_valid(company_kitchen_row) and is_instance_valid(company_kitchen_icons):
		company_kitchen_row.visible = company_kitchen_icons.get_child_count() > 0
	if is_instance_valid(company_marketing_row) and is_instance_valid(company_marketing_icons):
		company_marketing_row.visible = company_marketing_icons.get_child_count() > 0
	if is_instance_valid(company_other_row) and is_instance_valid(company_other_icons):
		company_other_row.visible = company_other_icons.get_child_count() > 0

func _refresh_summary() -> void:
	if not is_instance_valid(summary_label):
		return
	if _game_state == null:
		summary_label.text = "查看: -"
		return

	var view_id := _view_player_id
	if view_id < 0 or view_id >= _game_state.players.size():
		view_id = _current_player_id
	if view_id < 0 or view_id >= _game_state.players.size():
		view_id = 0
	if view_id < 0 or view_id >= _game_state.players.size():
		summary_label.text = "查看: -"
		return

	var player_val = _game_state.players[view_id]
	var player: Dictionary = player_val if player_val is Dictionary else {}

	var cash := int(player.get("cash", 0))
	var inv_val = player.get("inventory", {})
	var inv: Dictionary = inv_val if inv_val is Dictionary else {}

	var line1_parts: Array[String] = []
	line1_parts.append("查看: %s" % Globals.get_player_name(view_id))
	line1_parts.append("💰 $%d" % cash)

	var inv_parts: Array[String] = []
	var keys := inv.keys()
	keys.sort()
	for k in keys:
		var pid := str(k)
		var count := int(inv.get(pid, 0))
		if count <= 0:
			continue
		var emoji := str(PRODUCT_EMOJI.get(pid, ""))
		if not emoji.is_empty():
			inv_parts.append("%s×%d" % [emoji, count])
		else:
			var name := str(PRODUCT_NAMES.get(pid, pid))
			inv_parts.append("%s×%d" % [name, count])
		if inv_parts.size() >= 4:
			break
	var inv_text := "库存: 无"
	if not inv_parts.is_empty():
		inv_text = "库存: %s" % " ".join(inv_parts)

	var emp_parts := _build_employee_summary_parts(player)
	var emp_text := "员工: 0"
	if not emp_parts.is_empty():
		emp_text = "员工: %s" % " ".join(emp_parts)

	summary_label.text = "%s\n%s | %s" % [
		" | ".join(line1_parts),
		inv_text,
		emp_text
	]

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

	if phase == "Restructuring":
		tab_container.current_tab = TAB_COMPANY

func _resolve_view_player_id() -> int:
	if _game_state == null:
		return 0
	var view_id := _view_player_id
	if view_id < 0 or view_id >= _game_state.players.size():
		view_id = _current_player_id
	if view_id < 0 or view_id >= _game_state.players.size():
		view_id = 0
	view_id = clamp(view_id, 0, maxi(0, _game_state.players.size() - 1))
	return view_id

func _attach_log_panel_signals() -> void:
	if _attached_log_panel == null or not is_instance_valid(_attached_log_panel):
		return
	if _attached_log_panel.has_signal("log_added"):
		var sig = _attached_log_panel.log_added
		if sig is Signal:
			if not sig.is_connected(_on_log_added):
				sig.connect(_on_log_added)

func _detach_log_panel_signals() -> void:
	if _attached_log_panel == null or not is_instance_valid(_attached_log_panel):
		_attached_log_panel = null
		return
	if _attached_log_panel.has_signal("log_added"):
		var sig = _attached_log_panel.log_added
		if sig is Signal:
			if sig.is_connected(_on_log_added):
				sig.disconnect(_on_log_added)
	_attached_log_panel = null

func _on_log_added(_entry: Dictionary) -> void:
	_refresh_turn_log()

func _refresh_turn_log() -> void:
	if not is_instance_valid(turn_log_lines):
		return

	for c in turn_log_lines.get_children():
		if is_instance_valid(c):
			c.queue_free()

	if _attached_log_panel == null or not is_instance_valid(_attached_log_panel):
		_add_turn_log_line("（未绑定日志面板）", Color(0.6, 0.6, 0.6, 0.9))
		return
	if not _attached_log_panel.has_method("get_entries"):
		_add_turn_log_line("（日志面板不支持 get_entries）", Color(0.6, 0.6, 0.6, 0.9))
		return

	var view_id := _resolve_view_player_id()
	var entries_val = _attached_log_panel.call("get_entries")
	if not (entries_val is Array):
		_add_turn_log_line("（日志数据异常）", Color(0.6, 0.6, 0.6, 0.9))
		return
	var entries: Array = entries_val

	var start_idx := 0
	var round_number := int(_game_state.round_number) if _game_state != null else -1
	var round_start_idx := _find_round_start_entry_index(entries, round_number)
	if round_start_idx >= 0:
		start_idx = round_start_idx + 1

	var matched: Array[Dictionary] = []
	for i in range(start_idx, entries.size()):
		var e_val = entries[i]
		if not (e_val is Dictionary):
			continue
		var e: Dictionary = e_val
		if _entry_matches_view_player(e, view_id):
			matched.append(e)

	var n := matched.size()
	var max_lines := 6
	var start := maxi(0, n - max_lines)
	if n <= 0:
		_add_turn_log_line("（暂无该玩家日志）", Color(0.6, 0.6, 0.6, 0.9))
		return
	for i in range(start, n):
		var e: Dictionary = matched[i]
		var msg := str(e.get("message", ""))
		msg = msg.strip_edges()
		if msg.is_empty():
			continue
		_add_turn_log_line(msg, Color(0.85, 0.85, 0.9, 1))

func _find_round_start_entry_index(entries: Array, round_number: int) -> int:
	if round_number < 0:
		return -1
	if entries == null or entries.is_empty():
		return -1

	for i in range(entries.size() - 1, -1, -1):
		var e_val = entries[i]
		if not (e_val is Dictionary):
			continue
		var e: Dictionary = e_val

		var t_val = e.get("type", null)
		var t := int(t_val) if (t_val is int or t_val is float) else -1
		if t != 1: # GameLogPanel.LogType.PHASE
			continue

		var msg := str(e.get("message", "")).strip_edges()
		if not msg.begins_with("回合开始"):
			continue

		var details_val = e.get("details", null)
		if not (details_val is Dictionary):
			continue
		var details: Dictionary = details_val
		var r_val = details.get("round", null)
		var r := -1
		if r_val is int:
			r = int(r_val)
		elif r_val is float:
			var f: float = float(r_val)
			if f == floor(f):
				r = int(f)
		if r == round_number:
			return i

	return -1

func _entry_matches_view_player(entry: Dictionary, view_id: int) -> bool:
	if entry == null or entry.is_empty():
		return false

	var details_val = entry.get("details", null)
	if details_val is Dictionary:
		var details: Dictionary = details_val
		var pid_val = details.get("player_id", null)
		if pid_val is int:
			return int(pid_val) == view_id
		if pid_val is float:
			var f: float = float(pid_val)
			if f == floor(f):
				return int(f) == view_id

	var t_val = entry.get("type", null)
	var t := int(t_val) if (t_val is int or t_val is float) else -1
	if t == 2: # GameLogPanel.LogType.PLAYER
		var msg := str(entry.get("message", ""))
		return msg.begins_with("玩家%d:" % (view_id + 1))

	return false

func _add_turn_log_line(text: String, color: Color) -> void:
	if not is_instance_valid(turn_log_lines):
		return
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", color)
	turn_log_lines.add_child(l)

func _on_turn_log_toggled(pressed: bool) -> void:
	if is_instance_valid(turn_log_lines):
		turn_log_lines.visible = pressed
	if is_instance_valid(turn_log_toggle_button):
		turn_log_toggle_button.text = ("▼ 本回合日志" if pressed else "▶ 本回合日志")

func _on_turn_log_to_logs_pressed() -> void:
	logs_requested.emit()
	if is_instance_valid(turn_log_toggle_button) and not turn_log_toggle_button.button_pressed:
		turn_log_toggle_button.button_pressed = true
		_on_turn_log_toggled(true)

func _on_tab_changed(_tab_index: int) -> void:
	_update_tab_styles()

func _on_player_tab_pressed(player_id: int) -> void:
	player_selected.emit(player_id)

func _on_player_tab_toggled(pressed: bool, player_id: int) -> void:
	if not pressed:
		return
	player_selected.emit(player_id)
