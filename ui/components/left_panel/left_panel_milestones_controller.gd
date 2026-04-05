# LeftPanel：里程碑紧凑显示（左侧面板）
extends RefCounted

const UiStylesClass = preload("res://ui/utils/ui_styles.gd")
const CheckmarkIconClass = preload("res://ui/components/left_panel/checkmark_icon.gd")
const StatusDotIconClass = preload("res://ui/components/common/status_dot_icon.gd")
const UiPointerInputClass = preload("res://ui/utils/pointer_input.gd")

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

var _panel = null
var _snapshot: Dictionary = {}

func setup(panel) -> void:
	_panel = panel

func refresh() -> void:
	if _panel == null or not is_instance_valid(_panel):
		return
	_refresh_milestones_compact()

func _refresh_milestones_compact() -> void:
	if not is_instance_valid(_panel.milestones_list):
		return

	var row_sep := 4
	if Globals != null:
		row_sep = maxi(2, int(Globals.get_scaled_font_size(4)))
	_panel.milestones_list.add_theme_constant_override("separation", row_sep)

	if _panel._game_state == null:
		if _snapshot == {"empty": true}:
			return
		_snapshot = {"empty": true}
		_clear_rows()
		_add_milestone_empty_label()
		return

	var view_id: int = int(_panel._resolve_view_player_id())
	if view_id < 0 or view_id >= _panel._game_state.players.size():
		if _snapshot == {"empty": true}:
			return
		_snapshot = {"empty": true}
		_clear_rows()
		_add_milestone_empty_label()
		return

	var player_val = _panel._game_state.players[view_id]
	var player: Dictionary = player_val if player_val is Dictionary else {}
	var player_milestones: Array = Array(player.get("milestones", []))
	var snapshot := {
		"view_player_id": view_id,
		"player_milestones": player_milestones.duplicate(true),
		"pool": Array(_panel._game_state.milestone_pool).duplicate(true),
	}
	if snapshot == _snapshot:
		return
	_snapshot = snapshot
	_clear_rows()
	var claimed_set := {}
	for pm in player_milestones:
		var pm_id := str(pm).strip_edges()
		if pm_id.is_empty():
			continue
		claimed_set[pm_id] = true

	# 构建里程碑池计数
	var pool_counts := {}
	for v in _panel._game_state.milestone_pool:
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
		_panel.milestones_list.add_child(row)

func _clear_rows() -> void:
	for c in _panel.milestones_list.get_children():
		if is_instance_valid(c):
			c.queue_free()

func _add_milestone_empty_label() -> void:
	var empty := Label.new()
	empty.text = "暂无里程碑"
	UiStylesClass.apply_label_hint_dark(empty)
	var fs := 16
	if Globals != null:
		fs = int(Globals.get_scaled_font_size(16))
	empty.add_theme_font_size_override("font_size", fs)
	_panel.milestones_list.add_child(empty)

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
	var fs_icon := 18
	if Globals != null:
		fs_icon = int(Globals.get_scaled_font_size(18))
	var icon_container := CenterContainer.new()
	# Add padding so the checkmark icon never looks clipped at small sizes (esp. in Web export).
	icon_container.custom_minimum_size = Vector2(fs_icon + 6, fs_icon + 6)
	icon_container.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	if is_claimed:
		var icon_draw := CheckmarkIconClass.new()
		icon_draw.custom_minimum_size = Vector2(fs_icon, fs_icon)
		icon_draw.color = MILESTONE_COLOR_CLAIMED
		icon_container.add_child(icon_draw)
	elif in_pool:
		var icon_draw := StatusDotIconClass.new()
		icon_draw.custom_minimum_size = Vector2(fs_icon, fs_icon)
		icon_draw.color = MILESTONE_COLOR_AVAILABLE
		icon_draw.filled = false
		icon_container.add_child(icon_draw)
	else:
		var icon_draw := StatusDotIconClass.new()
		icon_draw.custom_minimum_size = Vector2(fs_icon, fs_icon)
		icon_draw.color = MILESTONE_COLOR_GONE
		icon_draw.filled = false
		icon_container.add_child(icon_draw)

	row.add_child(icon_container)

	# 里程碑名称
	var name_label := Label.new()
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	name_label.max_lines_visible = 1
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.clip_text = true
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
	icon_container.tooltip_text = tip
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

	if _panel._game_state != null:
		if _panel._game_state.milestone_pool is Array:
			for v in Array(_panel._game_state.milestone_pool):
				var mid_p := str(v).strip_edges()
				if mid_p.is_empty():
					continue
				set[mid_p] = true

		if _panel._game_state.players is Array:
			for p_val in _panel._game_state.players:
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
	if _panel == null or not is_instance_valid(_panel):
		return null
	var tree = _panel.get_tree()
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
	if not UiPointerInputClass.is_primary_press(event):
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
