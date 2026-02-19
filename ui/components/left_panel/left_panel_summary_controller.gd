# LeftPanel：玩家概览卡（现金/员工/餐厅/薪资）与库存区渲染
extends RefCounted

const ProductRegistryClass = preload("res://core/data/product_registry.gd")
const UiStylesClass = preload("res://ui/utils/ui_styles.gd")
const EmployeeRulesClass = preload("res://core/rules/employee_rules.gd")

var _panel = null

func setup(panel) -> void:
	_panel = panel

func refresh() -> void:
	if _panel == null or not is_instance_valid(_panel):
		return
	_refresh_summary()

func count_total_employees(player: Dictionary) -> int:
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

func count_restaurants(player: Dictionary) -> int:
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

func count_milestones(player: Dictionary) -> int:
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

func get_player_salary_cost(player: Dictionary) -> int:
	var salary_cost := 0
	if _panel != null and is_instance_valid(_panel) and _panel._game_state != null and (_panel._game_state.rules is Dictionary):
		salary_cost = int((_panel._game_state.rules as Dictionary).get("salary_cost", 0))

	var override_val = player.get("salary_cost_override", null)
	if override_val is int:
		salary_cost = maxi(0, int(override_val))
	elif override_val is float:
		var f: float = float(override_val)
		if f == floor(f):
			salary_cost = maxi(0, int(f))

	return maxi(0, salary_cost)

func _refresh_summary() -> void:
	if _panel._game_state == null:
		_set_summary_empty()
		return

	var view_id: int = int(_panel._resolve_view_player_id())
	if view_id < 0 or view_id >= _panel._game_state.players.size():
		_set_summary_empty()
		return

	var player_val = _panel._game_state.players[view_id]
	var player: Dictionary = player_val if player_val is Dictionary else {}

	# 餐厅图标
	if is_instance_valid(_panel.restaurant_icon):
		var tex = _panel._get_player_restaurant_logo_texture(view_id)
		_panel.restaurant_icon.texture = tex

	# 玩家名称
	if is_instance_valid(_panel.player_name_label):
		_panel.player_name_label.text = Globals.get_player_name(view_id)

	# 现金
	var cash := int(_panel.cash_overrides.get(view_id, player.get("cash", 0)))
	if is_instance_valid(_panel.cash_label):
		_panel.cash_label.text = "$%d" % cash

	# 员工总数
	var emp_count := count_total_employees(player)
	if is_instance_valid(_panel.employee_count_label):
		_panel.employee_count_label.text = "%d人" % emp_count

	# 餐厅数
	var rest_count := count_restaurants(player)
	if is_instance_valid(_panel.restaurant_count_label):
		_panel.restaurant_count_label.text = "%d店" % rest_count

	# 每回合薪资
	var total_salary := _calculate_total_salary(player)
	if is_instance_valid(_panel.salary_label):
		_panel.salary_label.text = "$%d/回合" % total_salary

	# 库存
	var inv_val = player.get("inventory", {})
	var inv: Dictionary = inv_val if inv_val is Dictionary else {}
	_refresh_inventory_ui(inv, _get_fridge_capacity_for_player(player))

func _set_summary_empty() -> void:
	if is_instance_valid(_panel.restaurant_icon):
		_panel.restaurant_icon.texture = null
	if is_instance_valid(_panel.player_name_label):
		_panel.player_name_label.text = "-"
	if is_instance_valid(_panel.cash_label):
		_panel.cash_label.text = "$0"
	if is_instance_valid(_panel.employee_count_label):
		_panel.employee_count_label.text = "0人"
	if is_instance_valid(_panel.restaurant_count_label):
		_panel.restaurant_count_label.text = "0店"
	if is_instance_valid(_panel.salary_label):
		_panel.salary_label.text = "$0/回合"
	_refresh_inventory_ui({}, -1)

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
	var salary_cost := get_player_salary_cost(player)
	return paid_employee_count * salary_cost

func _refresh_inventory_ui(inv: Dictionary, fridge_capacity: int) -> void:
	if not is_instance_valid(_panel.inventory_header) or not is_instance_valid(_panel.inventory_tokens_flow):
		return

	# 计算库存总量
	var total_items := 0
	for k in inv.keys():
		total_items += int(inv.get(k, 0))

	if fridge_capacity < 0:
		_panel.inventory_header.text = "库存 (%d)" % total_items
	else:
		_panel.inventory_header.text = "库存 (%d/%d)" % [total_items, fridge_capacity]

	for c in _panel.inventory_tokens_flow.get_children():
		if is_instance_valid(c):
			c.queue_free()

	_panel._ensure_skin()

	var keys := inv.keys()
	keys.sort()

	var added := 0
	for k in keys:
		var product_id := str(k)
		var count := int(inv.get(product_id, 0))
		if count <= 0:
			continue
		_panel.inventory_tokens_flow.add_child(_build_inventory_token_item(product_id, count))
		added += 1

	if added <= 0:
		var empty := Label.new()
		empty.text = "无"
		UiStylesClass.apply_label_hint_dark(empty)
		var fs := 13
		if Globals != null:
			fs = int(Globals.get_scaled_font_size(13))
		empty.add_theme_font_size_override("font_size", fs)
		_panel.inventory_tokens_flow.add_child(empty)

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
	_panel._ensure_skin()
	if _panel._skin == null or not _panel._skin.has_method("get_product_icon_texture"):
		return null
	var pid := str(product_id)
	if pid == "cola":
		pid = "soda"
	return _panel._skin.get_product_icon_texture(pid)

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
