# 发薪日面板组件
# 显示员工薪资计算，支持解雇选择
class_name PaydayPanel
extends Control

signal fire_employees(items: Array)
signal pay_confirmed()
signal right_panel_footer_changed()

const EmployeeCardClass = preload("res://ui/components/employee_card/employee_card.gd")
const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")
const EmployeeRulesClass = preload("res://core/rules/employee_rules.gd")
const EffectIdsSegmentInvokerClass = preload("res://core/rules/effect_ids_segment_invoker.gd")
const IntValueParseHelpersClass = preload("res://core/utils/int_value_parse_helpers.gd")
const MilestoneEffectQueriesClass = preload("res://core/rules/milestone_effect_queries.gd")
const MilestoneRegistryClass = preload("res://core/data/milestone_registry.gd")
const ProductRegistryClass = preload("res://core/data/product_registry.gd")
const PlayerStateAccessClass = preload("res://core/state/player_state_access.gd")
const UiNodeAccessClass = preload("res://ui/utils/node_access.gd")
const UiRebuildHelpersClass = preload("res://ui/utils/rebuild_helpers.gd")
const UiStylesClass = preload("res://ui/utils/ui_styles.gd")

const _BUTTON_ROW_PATH := NodePath("MarginContainer/VBoxContainer/ButtonRow")

@onready var salary_list_container: VBoxContainer = $MarginContainer/VBoxContainer/ScrollContainer/SalaryListContainer
@onready var scroll_container: ScrollContainer = $MarginContainer/VBoxContainer/ScrollContainer
@onready var base_label: Label = $MarginContainer/VBoxContainer/SummarySection/BaseLabel
@onready var discount_label: Label = $MarginContainer/VBoxContainer/SummarySection/DiscountLabel
@onready var details_container: VBoxContainer = $MarginContainer/VBoxContainer/SummarySection/DetailsContainer
@onready var total_label: Label = $MarginContainer/VBoxContainer/SummarySection/TotalLabel
@onready var cash_label: Label = $MarginContainer/VBoxContainer/SummarySection/CashLabel
@onready var fire_btn: Button = $MarginContainer/VBoxContainer/ButtonRow/FireButton
@onready var pay_btn: Button = $MarginContainer/VBoxContainer/ButtonRow/PayButton

var _employee_registry = null
var _active_employees: Array[String] = []
var _reserve_employees: Array[String] = []
var _busy_marketers: Array[String] = []
var _salary_items: Dictionary = {}  # item_key -> SalaryItem
var _selected_item_keys: Array[String] = []

var _player_cash: int = 0
var _embedded_in_right_panel: bool = false
var _base_custom_minimum_size: Vector2 = Vector2.ZERO

var _state: GameState = null
var _player_id: int = -1
var _effect_registry = null

func set_embedded_in_right_panel(embedded: bool) -> void:
	_embedded_in_right_panel = embedded
	if _base_custom_minimum_size == Vector2.ZERO:
		_base_custom_minimum_size = custom_minimum_size
	custom_minimum_size = Vector2.ZERO if embedded else _base_custom_minimum_size

	UiNodeAccessClass.set_control_visible(self, _BUTTON_ROW_PATH, not embedded)

	_apply_embedding_layout()
	right_panel_footer_changed.emit()

func right_panel_get_footer_config() -> Dictionary:
	if fire_btn == null or pay_btn == null:
		return {}
	return {
		"show_cancel": true,
		"cancel_text": "取消",
		"cancel_enabled": true,
		"show_secondary": true,
		"secondary_text": str(fire_btn.text),
		"secondary_enabled": not fire_btn.disabled,
		"show_primary": true,
		"primary_text": str(pay_btn.text),
		"primary_enabled": not pay_btn.disabled,
	}

func right_panel_footer_primary() -> void:
	_on_pay_pressed()

func right_panel_footer_secondary() -> void:
	_on_fire_pressed()

func _ready() -> void:
	if _base_custom_minimum_size == Vector2.ZERO:
		_base_custom_minimum_size = custom_minimum_size
	if fire_btn != null:
		fire_btn.pressed.connect(_on_fire_pressed)
		fire_btn.disabled = true
	if pay_btn != null:
		pay_btn.pressed.connect(_on_pay_pressed)
	UiStylesClass.apply_button_primary(pay_btn)
	UiStylesClass.apply_button_secondary(fire_btn)
	_apply_embedding_layout()
	# show_payday_panel 可能在节点 _ready 前调用 set_context/set_employees；
	# 这里补一次 refresh，确保 summary/明细在首次显示时已正确渲染。
	refresh()
	right_panel_footer_changed.emit()

func set_employee_registry(registry) -> void:
	_employee_registry = registry

func set_context(state: GameState, player_id: int, effect_registry = null) -> void:
	_state = state
	_player_id = player_id
	_effect_registry = effect_registry
	if _state != null and _player_id >= 0:
		var player := _state.get_player(_player_id)
		if not player.is_empty():
			_player_cash = int(player.get("cash", 0))
	_update_summary()

func set_employees(active_employees: Array[String], reserve_employees: Array[String], busy_marketers: Array[String]) -> void:
	_active_employees = active_employees.duplicate()
	_reserve_employees = reserve_employees.duplicate()
	_busy_marketers = busy_marketers.duplicate()
	_selected_item_keys.clear()
	_rebuild_salary_list()
	_update_summary()

func set_player_cash(cash: int) -> void:
	_player_cash = cash
	_update_summary()

func calculate_total() -> int:
	var breakdown := _compute_breakdown(_get_current_player_snapshot())
	if breakdown.is_empty():
		return 0
	return int(breakdown.get("due_total", 0))

func refresh() -> void:
	_rebuild_salary_list()
	_update_summary()

func _apply_embedding_layout() -> void:
	if scroll_container != null:
		scroll_container.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO if _embedded_in_right_panel else ScrollContainer.SCROLL_MODE_DISABLED

func _rebuild_salary_list() -> void:
	# 清除旧列表
	UiRebuildHelpersClass.free_nodes_dict(_salary_items)
	_salary_items.clear()

	if salary_list_container == null:
		return

	var player := _get_current_player_snapshot()

	_build_salary_items_for_list(player, _active_employees, "active")
	_build_salary_items_for_list(player, _reserve_employees, "reserve")
	_build_salary_items_for_list(player, _busy_marketers, "busy")
	right_panel_footer_changed.emit()

func _build_salary_items_for_list(player: Dictionary, list: Array[String], location: String) -> void:
	var index := 0
	for emp_id in list:
		var employee_id := str(emp_id)
		var item_key := "%s:%s:%d" % [location, employee_id, index]
		index += 1

		var emp_def := _get_employee_def(employee_id)
		var requires_salary := EmployeeRulesClass.requires_salary(employee_id, player)
		var can_be_fired := bool(emp_def.get("can_be_fired", true))

		var item := SalaryItem.new()
		item.item_key = item_key
		item.employee_id = employee_id
		item.location = location
		item.employee_def = emp_def
		item.requires_salary = requires_salary
		item.is_busy = (location == "busy")
		item.can_be_fired = can_be_fired
		item.salary_amount = _get_salary_cost_for_player(player) if requires_salary else 0
		item.fire_toggled.connect(_on_item_toggled)

		salary_list_container.add_child(item)
		_salary_items[item_key] = item

func _get_employee_def(employee_type: String) -> Dictionary:
	if _employee_registry != null and _employee_registry.has_method("get_employee"):
		var emp = _employee_registry.get_employee(employee_type)
		if emp != null and emp.has_method("to_dict"):
			return emp.to_dict()

	if EmployeeRegistryClass.is_loaded():
		var def_val = EmployeeRegistryClass.get_def(employee_type)
		if def_val != null and def_val.has_method("to_dict"):
			return def_val.to_dict()

	return {"id": employee_type, "name": employee_type}

func _get_current_player_snapshot() -> Dictionary:
	if _state == null or _player_id < 0:
		return {}
	return _state.get_player(_player_id)

func _get_salary_cost_for_player(player: Dictionary) -> int:
	if _state == null:
		return 5
	var base_salary_cost: int = _state.get_rule_int("salary_cost")
	var salary_cost := base_salary_cost
	if player.has("salary_cost_override"):
		var override_val = player.get("salary_cost_override", null)
		if override_val is int and int(override_val) >= 0:
			salary_cost = int(override_val)
	return maxi(0, salary_cost)

func _update_summary() -> void:
	var current_player := _get_current_player_snapshot()
	var current_breakdown := _compute_breakdown(current_player)
	var preview_player := _build_preview_player_after_selected_fires()
	var preview_breakdown := _compute_breakdown(preview_player) if not _selected_item_keys.is_empty() else {}

	_update_details_ui(current_breakdown, preview_breakdown)
	_update_item_fire_enabled_states(current_player, current_breakdown)

	if fire_btn != null:
		fire_btn.disabled = _selected_item_keys.is_empty()

	if pay_btn != null:
		var can_advance := bool(current_breakdown.get("can_advance", false))
		pay_btn.disabled = not can_advance
	right_panel_footer_changed.emit()

func _on_item_toggled(item_key: String, selected: bool) -> void:
	if selected:
		if not _selected_item_keys.has(item_key):
			_selected_item_keys.append(item_key)
	else:
		_selected_item_keys.erase(item_key)
	_update_summary()

func _on_fire_pressed() -> void:
	if _selected_item_keys.is_empty():
		return

	var items: Array = []
	for k in _selected_item_keys:
		if not _salary_items.has(k):
			continue
		var item_val = _salary_items[k]
		if not is_instance_valid(item_val):
			continue
		var item: SalaryItem = item_val
		items.append({
			"employee_id": item.employee_id,
			"location": item.location,
		})
	fire_employees.emit(items)

func _on_pay_pressed() -> void:
	pay_confirmed.emit()

func _build_preview_player_after_selected_fires() -> Dictionary:
	var player := _get_current_player_snapshot()
	if player.is_empty():
		return {}

	var preview: Dictionary = player.duplicate(true)
	preview["employees"] = Array(preview.get("employees", [])).duplicate()
	preview["reserve_employees"] = Array(preview.get("reserve_employees", [])).duplicate()
	preview["busy_marketers"] = Array(preview.get("busy_marketers", [])).duplicate()

	for k in _selected_item_keys:
		if not _salary_items.has(k):
			continue
		var item_val = _salary_items[k]
		if not is_instance_valid(item_val):
			continue
		var item: SalaryItem = item_val
		var arr_key := "employees"
		match item.location:
			"active":
				arr_key = "employees"
			"reserve":
				arr_key = "reserve_employees"
			"busy":
				arr_key = "busy_marketers"
			_:
				arr_key = "employees"
		if preview.has(arr_key) and (preview[arr_key] is Array):
			var arr: Array = preview[arr_key]
			var idx := arr.find(item.employee_id)
			if idx >= 0:
				arr.remove_at(idx)
			preview[arr_key] = arr

	return preview

func _compute_breakdown(player: Dictionary) -> Dictionary:
	if _state == null or player.is_empty():
		return {}

	var base_salary_cost: int = _state.get_rule_int("salary_cost")
	var salary_cost := base_salary_cost
	if player.has("salary_cost_override"):
		var override_val = player.get("salary_cost_override", null)
		if override_val is int and int(override_val) >= 0:
			salary_cost = int(override_val)

	var paid_employee_count := EmployeeRulesClass.count_paid_employees(player)
	var base_due_amount: int = paid_employee_count * maxi(0, salary_cost)

	var milestones: Array = []
	var milestones_read := PlayerStateAccessClass.require_milestones(player, "player", "PaydayPanel: ")
	if milestones_read.ok:
		milestones = milestones_read.value
	elif player.has("milestones") and (player["milestones"] is Array):
		milestones = player["milestones"]

	var delta_entries: Array[Dictionary] = []
	var delta_total := 0
	if not milestones.is_empty() and MilestoneRegistryClass.is_loaded():
		var entries_read := MilestoneEffectQueriesClass.collect_effect_entries(milestones, "salary_total_delta", "PaydayPanel: ", "player.milestones")
		if entries_read.ok:
			for entry_val in Array(entries_read.value):
				if not (entry_val is Dictionary):
					continue
				var entry: Dictionary = entry_val
				var eff_val = entry.get("effect", null)
				if not (eff_val is Dictionary):
					continue
				var eff: Dictionary = eff_val

				var mid := str(entry.get("milestone_id", "")).strip_edges()
				if mid.is_empty():
					continue

				var v_read := IntValueParseHelpersClass.parse_int_value(eff.get("value", 0), "%s.salary_total_delta.value" % mid)
				if not v_read.ok:
					continue
				var v := int(v_read.value)
				if v == 0:
					continue
				delta_total += v
				delta_entries.append({"milestone_id": mid, "value": v})

	# 折扣：优先使用 EffectRegistry（支持模块动态 effect）；缺失时退化为静态 EmployeeDef.effect_ids 扫描。
	var discount_recruit_capacity := 0
	var discount_sources: Dictionary = {}
	if _effect_registry != null and (player.get("employees", null) is Array):
		var ctx := {"salary_discount_recruit_capacity": 0}
		for emp_val in Array(player.get("employees", [])):
			if not (emp_val is String):
				continue
			var emp_id := str(emp_val).strip_edges()
			if emp_id.is_empty():
				continue
			var def_val = EmployeeRegistryClass.get_def(emp_id)
			if def_val == null or not (def_val is EmployeeDef):
				continue
			var def: EmployeeDef = def_val
			var before := int(ctx.get("salary_discount_recruit_capacity", 0))
			var inv := EffectIdsSegmentInvokerClass.invoke_effect_ids_by_segment(
				_effect_registry,
				def.effect_ids,
				":payday:salary_discount:",
				[_state, _player_id, ctx, emp_id],
				"PaydayPanelSalaryDiscount",
				"EmployeeDef[%s].effect_ids" % emp_id
			)
			if not inv.ok:
				continue
			var after := int(ctx.get("salary_discount_recruit_capacity", 0))
			var delta := after - before
			if delta > 0:
				discount_sources[emp_id] = int(discount_sources.get(emp_id, 0)) + delta
		var cap_val = ctx.get("salary_discount_recruit_capacity", 0)
		if cap_val is int:
			discount_recruit_capacity = int(cap_val)
		elif cap_val is float:
			var f: float = float(cap_val)
			if f == floor(f):
				discount_recruit_capacity = int(f)
	else:
		var discount_info := _collect_payday_salary_discount_capacity_from_active(player)
		discount_recruit_capacity = int(discount_info.get("total", 0))
		discount_sources = discount_info.get("sources", {})

	var used_recruit := 0
	if _state.round_state is Dictionary and _state.round_state.has("recruit_used"):
		var ru_val = _state.round_state.get("recruit_used", null)
		if ru_val is Dictionary:
			var ru: Dictionary = ru_val
			var v2 = ru.get(_player_id, null)
			if v2 == null and ru.has(str(_player_id)):
				v2 = ru.get(str(_player_id), null)
			if v2 is int:
				used_recruit = int(v2)

	var total_recruit_capacity: int = EmployeeRulesClass.get_recruit_limit(player)
	var non_discount_recruit_capacity: int = total_recruit_capacity - discount_recruit_capacity
	non_discount_recruit_capacity = maxi(0, non_discount_recruit_capacity)
	var used_from_discount: int = maxi(0, used_recruit - non_discount_recruit_capacity)
	used_from_discount = mini(used_from_discount, discount_recruit_capacity)
	var unused_discount_actions: int = maxi(0, discount_recruit_capacity - used_from_discount)
	var discount_amount: int = unused_discount_actions * base_salary_cost

	var due_total := maxi(0, base_due_amount + delta_total - discount_amount)

	var cash: int = int(player.get("cash", 0))
	var pay_with_tokens := bool(player.get("salary_pay_with_tokens", false))
	var allow_unpaid := bool(player.get("salary_allow_unpaid", false))

	var inventory: Dictionary = {}
	var inventory_read := PlayerStateAccessClass.require_inventory(player, "player", "PaydayPanel: ")
	if inventory_read.ok:
		inventory = inventory_read.value
	elif player.has("inventory") and (player["inventory"] is Dictionary):
		inventory = player["inventory"]

	var tokens_available := 0
	if pay_with_tokens:
		tokens_available = _count_food_drink_tokens(inventory)

	var tokens_used := 0
	if pay_with_tokens and tokens_available > 0 and paid_employee_count > 0:
		var need := _compute_min_tokens_needed(
			paid_employee_count, salary_cost, delta_total, discount_amount, cash
		)
		tokens_used = mini(tokens_available, need)

	var due_cash := maxi(0, (paid_employee_count - tokens_used) * maxi(0, salary_cost) + delta_total - discount_amount)
	var can_advance := allow_unpaid or cash >= due_cash

	return {
		"base_salary_cost": base_salary_cost,
		"salary_cost": salary_cost,
		"paid_employee_count": paid_employee_count,
		"base_due": base_due_amount,
		"milestone_delta_entries": delta_entries,
		"milestone_delta": delta_total,
		"discount_sources": discount_sources,
		"salary_discount_recruit_capacity": discount_recruit_capacity,
		"salary_discount_used_from_discount": used_from_discount,
		"salary_discount_unused_actions": unused_discount_actions,
		"salary_discount": discount_amount,
		"recruit_used": used_recruit,
		"due_total": due_total,
		"pay_with_tokens": pay_with_tokens,
		"tokens_available": tokens_available,
		"tokens_used": tokens_used,
		"due_cash": due_cash,
		"cash": cash,
		"allow_unpaid": allow_unpaid,
		"can_advance": can_advance,
	}

func _update_details_ui(breakdown: Dictionary, preview_breakdown: Dictionary = {}) -> void:
	if base_label != null:
		var base_due := int(breakdown.get("base_due", 0))
		var paid_count := int(breakdown.get("paid_employee_count", 0))
		var salary_cost := int(breakdown.get("salary_cost", 0))
		base_label.text = "薪资总额: $%d（%d人 × $%d）" % [base_due, paid_count, salary_cost]

	if discount_label != null:
		discount_label.visible = true
		discount_label.text = "减免明细"

	if details_container != null:
		for c in details_container.get_children():
			if is_instance_valid(c):
				c.queue_free()

		var discount_amount := int(breakdown.get("salary_discount", 0))
		var unused_discount_actions := int(breakdown.get("salary_discount_unused_actions", 0))
		var base_salary_cost := int(breakdown.get("base_salary_cost", 0))
		var discount_sources: Dictionary = breakdown.get("discount_sources", {})
		if discount_amount > 0:
			_add_detail_line("招聘折扣: -$%d（未用 %d 次 × $%d）" % [discount_amount, unused_discount_actions, base_salary_cost], Color(0.28, 0.55, 0.22, 1))
			var keys: Array[String] = []
			for k in discount_sources.keys():
				keys.append(str(k))
			keys.sort()
			for emp_id in keys:
				var emp_def := _get_employee_def(emp_id)
				var emp_name := str(emp_def.get("name", emp_id))
				_add_detail_line("  - %s（%s）: %d 次" % [emp_name, emp_id, int(discount_sources.get(emp_id, 0))], Color(0.45, 0.6, 0.45, 1))

		var entries: Array = breakdown.get("milestone_delta_entries", [])
		for entry_val in entries:
			if not (entry_val is Dictionary):
				continue
			var entry: Dictionary = entry_val
			var mid := str(entry.get("milestone_id", "")).strip_edges()
			var v := int(entry.get("value", 0))
			if v == 0:
				continue
			var sign := "+" if v > 0 else "-"
			var ms_name := mid
			if MilestoneRegistryClass.is_loaded():
				var def_val = MilestoneRegistryClass.get_def(mid)
				if def_val != null and (def_val is MilestoneDef):
					var def: MilestoneDef = def_val
					if not str(def.name).strip_edges().is_empty():
						ms_name = "%s（%s）" % [str(def.name), mid]
			_add_detail_line("里程碑(%s): %s$%d" % [ms_name, sign, abs(v)], Color(0.28, 0.55, 0.22, 1) if v < 0 else Color(0.73, 0.23, 0.18, 1))

		var pay_with_tokens := bool(breakdown.get("pay_with_tokens", false))
		if pay_with_tokens:
			var tokens_available := int(breakdown.get("tokens_available", 0))
			var tokens_used := int(breakdown.get("tokens_used", 0))
			_add_detail_line("Token 抵扣: %d（可用 %d）" % [tokens_used, tokens_available], Color(0.5, 0.45, 0.35, 1))
			_add_detail_line("现金需支付: $%d" % int(breakdown.get("due_cash", 0)), Color(0.5, 0.45, 0.35, 1))

		if not preview_breakdown.is_empty():
			var after_due := int(preview_breakdown.get("due_total", 0))
			var after_cash := int(preview_breakdown.get("due_cash", 0))
			_add_detail_line("解雇选中后: 实际需支付 $%d（现金 $%d）" % [after_due, after_cash], Color(0.5, 0.45, 0.35, 1))

	if total_label != null:
		var due_total := int(breakdown.get("due_total", 0))
		total_label.text = "实际需支付: $%d" % due_total

	if cash_label != null:
		cash_label.text = "当前现金: $%d" % int(breakdown.get("cash", _player_cash))
		var due_cash := int(breakdown.get("due_cash", int(breakdown.get("due_total", 0))))
		var allow_unpaid := bool(breakdown.get("allow_unpaid", false))
		if allow_unpaid:
			cash_label.add_theme_color_override("font_color", Color(0.5, 0.45, 0.35, 1))
		elif int(breakdown.get("cash", _player_cash)) < due_cash:
			cash_label.add_theme_color_override("font_color", Color(0.73, 0.23, 0.18, 1))
		else:
			cash_label.add_theme_color_override("font_color", Color(0.28, 0.55, 0.22, 1))

func _add_detail_line(text: String, color: Color) -> void:
	if details_container == null:
		return
	var l := Label.new()
	l.text = str(text)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", color)
	details_container.add_child(l)

func _update_item_fire_enabled_states(player: Dictionary, breakdown: Dictionary) -> void:
	var can_fire_busy := _can_fire_busy_marketer_now(player, breakdown)
	for key in _salary_items.keys():
		var item_val = _salary_items[key]
		if not is_instance_valid(item_val):
			continue
		var item: SalaryItem = item_val
		var enabled := true
		if not item.can_be_fired:
			enabled = false
		elif item.location == "busy":
			enabled = can_fire_busy and item.requires_salary
		item.set_fire_enabled(enabled)
		item.set_selected(_selected_item_keys.has(str(key)))

func _can_fire_busy_marketer_now(player: Dictionary, breakdown: Dictionary) -> bool:
	if _state == null or player.is_empty():
		return false
	if not (player.has("busy_marketers") and (player["busy_marketers"] is Array)):
		return false
	var busy: Array = player["busy_marketers"]
	var has_paid_busy := false
	for v in busy:
		var emp_id := str(v)
		if emp_id.is_empty():
			continue
		if EmployeeRulesClass.requires_salary(emp_id, player):
			has_paid_busy = true
			break
	if not has_paid_busy:
		return false

	# 必须已不存在其它需要薪水的员工（在岗/待命）
	for key in ["employees", "reserve_employees"]:
		var arr_val = player.get(key, null)
		if not (arr_val is Array):
			continue
		for v2 in Array(arr_val):
			var eid := str(v2)
			if eid.is_empty():
				continue
			if EmployeeRulesClass.requires_salary(eid, player):
				return false

	var cash: int = int(breakdown.get("cash", 0))
	var due_cash: int = int(breakdown.get("due_cash", 0))
	return cash < due_cash

static func _collect_payday_salary_discount_capacity_from_active(player: Dictionary) -> Dictionary:
	var emp_val = player.get("employees", null)
	if not (emp_val is Array):
		return {"total": 0, "sources": {}}
	var employees: Array = emp_val

	var sources: Dictionary = {}
	var total := 0
	for v in employees:
		if not (v is String):
			continue
		var emp_id: String = str(v)
		if emp_id.is_empty():
			continue
		var def_val = EmployeeRegistryClass.get_def(emp_id)
		if def_val == null or not (def_val is EmployeeDef):
			continue
		var def: EmployeeDef = def_val

		var has_discount := false
		for eff_id in def.effect_ids:
			var s: String = str(eff_id)
			if s.find(":payday:salary_discount:") >= 0:
				has_discount = true
				break
		if not has_discount:
			continue

		var cap := int(def.recruit_capacity)
		if cap <= 0:
			continue
		total += cap
		sources[emp_id] = int(sources.get(emp_id, 0)) + cap

	return {"total": total, "sources": sources}

static func _count_food_drink_tokens(inventory: Dictionary) -> int:
	var total := 0
	for k in inventory.keys():
		var product_id: String = str(k)
		var def = ProductRegistryClass.get_def(product_id)
		if def == null or not (def is ProductDef):
			continue
		var product: ProductDef = def
		if product.has_tag("salary_token_ineligible"):
			continue
		if not (product.has_tag("food") or product.has_tag("drink")):
			continue
		var v = inventory.get(k, 0)
		if v is int and int(v) > 0:
			total += int(v)
	return total

static func _compute_min_tokens_needed(
	paid_employee_count: int,
	salary_cost: int,
	milestone_delta: int,
	discount_amount: int,
	cash_available: int
) -> int:
	if paid_employee_count <= 0:
		return 0
	for t in range(paid_employee_count + 1):
		var due_cash := maxi(0, (paid_employee_count - t) * salary_cost + milestone_delta - discount_amount)
		if cash_available >= due_cash:
			return t
	return paid_employee_count


# === 内部类：薪资列表项 ===
class SalaryItem extends PanelContainer:
	signal fire_toggled(item_key: String, selected: bool)

	var item_key: String = ""
	var employee_id: String = ""
	var location: String = ""
	var employee_def: Dictionary = {}
	var requires_salary: bool = false
	var is_busy: bool = false
	var salary_amount: int = 0
	var can_be_fired: bool = true
	var _fire_enabled: bool = true

	var _fire_checkbox: CheckBox
	var _name_label: Label
	var _salary_label: Label
	var _status_label: Label
	var _location_label: Label

	const EmployeeRoleColorsClass = preload("res://ui/visual/employee_role_colors.gd")

	func _ready() -> void:
		_build_ui()

	func _build_ui() -> void:
		custom_minimum_size = Vector2(0, 40)

		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.92, 0.88, 0.78, 0.95)
		style.set_corner_radius_all(4)
		add_theme_stylebox_override("panel", style)

		var hbox := HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 10)
		add_child(hbox)

		# 解雇复选框
		_fire_checkbox = CheckBox.new()
		_fire_checkbox.toggled.connect(_on_checkbox_toggled)
		hbox.add_child(_fire_checkbox)

		# 角色颜色条
		var role_color := ColorRect.new()
		role_color.custom_minimum_size = Vector2(6, 30)
		var role: String = str(employee_def.get("role", "special"))
		role_color.color = Color(EmployeeRoleColorsClass.role_to_color_hex(role))
		hbox.add_child(role_color)

		# 员工名称
		_name_label = Label.new()
		_name_label.add_theme_font_size_override("font_size", 14)
		_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hbox.add_child(_name_label)

		_location_label = Label.new()
		_location_label.add_theme_font_size_override("font_size", 12)
		_location_label.add_theme_color_override("font_color", Color(0.5, 0.45, 0.35, 1))
		hbox.add_child(_location_label)

		# 状态标签（忙碌）
		_status_label = Label.new()
		_status_label.add_theme_font_size_override("font_size", 12)
		hbox.add_child(_status_label)

		# 薪资标签
		_salary_label = Label.new()
		_salary_label.add_theme_font_size_override("font_size", 14)
		_salary_label.custom_minimum_size = Vector2(60, 0)
		_salary_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		hbox.add_child(_salary_label)

		update_display()

	func set_fire_enabled(enabled: bool) -> void:
		_fire_enabled = enabled
		update_display()

	func set_selected(selected: bool) -> void:
		if _fire_checkbox != null:
			_fire_checkbox.set_pressed_no_signal(selected)

	func update_display() -> void:
		if _name_label != null:
			var name: String = str(employee_def.get("name", employee_id))
			_name_label.text = name

		if _salary_label != null:
			if requires_salary:
				_salary_label.text = "$%d" % salary_amount
				_salary_label.add_theme_color_override("font_color", Color(0.73, 0.23, 0.18, 1))
			else:
				_salary_label.text = "-"
				_salary_label.add_theme_color_override("font_color", Color(0.5, 0.45, 0.35, 1))

		if _location_label != null:
			match location:
				"active":
					_location_label.text = "[在岗]"
				"reserve":
					_location_label.text = "[待命]"
				"busy":
					_location_label.text = "[忙碌]"
				_:
					_location_label.text = ""

		if _status_label != null:
			_status_label.text = ""

		if _fire_checkbox != null:
			_fire_checkbox.disabled = (not can_be_fired) or (not _fire_enabled)

	func _on_checkbox_toggled(toggled: bool) -> void:
		fire_toggled.emit(item_key, toggled)
