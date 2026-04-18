# CommandRunnerEventBuild：Payday 事件拆分
# 用途：从 round_state.payday 中推导 payday 结算报告事件（日志/展示语义）。
extends RefCounted

const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const EconomyRulesClass = preload("res://core/rules/economy_rules.gd")
const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")
const EmployeeRulesClass = preload("res://core/rules/employee_rules.gd")
const MilestoneEffectQueriesClass = preload("res://core/rules/milestone_effect_queries.gd")
const MilestoneRegistryClass = preload("res://core/data/milestone_registry.gd")

static func build_payday_report_events(old_state: GameState, new_state: GameState) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if old_state == null or new_state == null:
		return events
	if str(old_state.phase) != DefsClass.PHASE_PAYDAY:
		return events
	if str(old_state.phase) == str(new_state.phase):
		return events

	var report_payday: Dictionary = {}
	if new_state.round_state is Dictionary:
		var v2 = Dictionary(new_state.round_state).get("payday", null)
		if v2 is Dictionary:
			report_payday = _enrich_payday_report_for_log(old_state, Dictionary(v2).duplicate(true))
	events.append({
		"type": EventBus.EventType.PAYDAY_REPORT,
		"data": {
			"round": old_state.round_number,
			"from_phase": str(old_state.phase),
			"to_phase": str(new_state.phase),
			"report": report_payday,
		}
	})
	return events

static func _enrich_payday_report_for_log(payday_state: GameState, report: Dictionary) -> Dictionary:
	if payday_state == null:
		return report
	if report == null or not (report is Dictionary) or report.is_empty():
		return report

	var details_val = report.get("details", null)
	if not (details_val is Array):
		return report

	var details: Array = details_val
	var enriched_details: Array[Dictionary] = []
	for item_val in details:
		if not (item_val is Dictionary):
			continue
		var item: Dictionary = Dictionary(item_val).duplicate(true)
		var player_id := int(item.get("player_id", -1))
		if not _has_player(payday_state, player_id):
			enriched_details.append(item)
			continue

		var player: Dictionary = payday_state.players[player_id]
		var salary_cost := _get_player_salary_cost(payday_state, player)
		var employees := _collect_player_payday_employees(player, salary_cost)
		var tokens_used := _sum_token_payment(item.get("paid_with_tokens", {}))
		var paid_employee_count := int(item.get("paid_employee_count", 0))
		var milestone_delta := int(item.get("milestone_delta", 0))
		var discount_amount := int(item.get("salary_discount", 0))
		var used_from_discount := maxi(0, int(item.get("salary_discount_recruit_capacity", 0)) - int(item.get("salary_discount_unused_actions", 0)))

		item["base_salary_cost"] = payday_state.get_rule_int("salary_cost")
		item["salary_cost"] = salary_cost
		item["employees"] = employees
		item["paid_employee_ids"] = _get_paid_employee_ids(employees)
		item["salary_base_total"] = int(item.get("base_due", 0))
		item["salary_reductions_total"] = maxi(0, int(item.get("base_due", 0)) - int(item.get("due", 0)))
		item["due_cash"] = maxi(0, (paid_employee_count - tokens_used) * salary_cost + milestone_delta - discount_amount)
		item["tokens_used"] = tokens_used
		item["tokens_available"] = _count_salary_tokens(player)
		item["salary_discount_sources"] = _build_salary_discount_sources(player, used_from_discount)
		item["milestone_salary_adjustments"] = _get_salary_total_delta_entries(player)

		enriched_details.append(item)

	report["details"] = enriched_details
	return report

static func _has_player(state: GameState, player_id: int) -> bool:
	if state == null or not (state.players is Array):
		return false
	return player_id >= 0 and player_id < state.players.size() and state.players[player_id] is Dictionary

static func _get_player_salary_cost(state: GameState, player: Dictionary) -> int:
	if state == null:
		return 0
	var salary_cost := state.get_rule_int("salary_cost")
	var override_val = player.get("salary_cost_override", null)
	if override_val is int and int(override_val) >= 0:
		salary_cost = int(override_val)
	return maxi(0, salary_cost)

static func _collect_player_payday_employees(player: Dictionary, salary_cost: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var locations: Array[Dictionary] = [
		{"key": "employees", "location": "active"},
		{"key": "reserve_employees", "location": "reserve"},
		{"key": "busy_marketers", "location": "busy"},
	]
	for loc_val in locations:
		var loc: Dictionary = loc_val
		var key := str(loc.get("key", "")).strip_edges()
		var location := str(loc.get("location", "")).strip_edges()
		if key.is_empty() or location.is_empty():
			continue
		var list_val = player.get(key, null)
		if not (list_val is Array):
			continue
		var employees: Array = list_val
		for emp_val in employees:
			if not (emp_val is String):
				continue
			var employee_id := str(emp_val).strip_edges()
			if employee_id.is_empty():
				continue
			var def_val = EmployeeRegistryClass.get_def(employee_id)
			if def_val == null or not (def_val is EmployeeDef):
				continue
			var def: EmployeeDef = def_val
			var requires_salary := EmployeeRulesClass.requires_salary(employee_id, player)
			out.append({
				"employee_id": employee_id,
				"name": str(def.name),
				"location": location,
				"requires_salary": requires_salary,
				"base_requires_salary": bool(def.salary),
				"salary_cost": salary_cost if requires_salary else 0,
				"salary_waived_reasons": _get_salary_waived_reasons(employee_id, def, player, requires_salary),
			})
	return out

static func _get_salary_waived_reasons(employee_id: String, def: EmployeeDef, player: Dictionary, requires_salary: bool) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if requires_salary or def == null:
		return out

	if not bool(def.salary):
		out.append({
			"type": "employee_no_base_salary",
			"label": "员工本身无需工资",
			"employee_id": employee_id,
		})

	var milestones_val = player.get("milestones", null)
	var milestones: Array = milestones_val if (milestones_val is Array) else []
	if milestones.is_empty():
		var no_salary_val = player.get("no_salary_employee_ids", null)
		if no_salary_val is Array and Array(no_salary_val).has(employee_id):
			out.append({
				"type": "employee_no_salary",
				"label": "里程碑/效果免薪",
				"employee_id": employee_id,
			})
		return out

	var employee_no_salary_read := MilestoneEffectQueriesClass.collect_effect_entries(
		milestones,
		"employee_no_salary",
		"PaydayEvents: ",
		"player.milestones"
	)
	if employee_no_salary_read.ok:
		for entry_val in Array(employee_no_salary_read.value):
			if not (entry_val is Dictionary):
				continue
			var entry: Dictionary = entry_val
			var eff_val = entry.get("effect", null)
			if not (eff_val is Dictionary):
				continue
			var eff: Dictionary = eff_val
			if str(eff.get("target", "")).strip_edges() != employee_id:
				continue
			var mid := str(entry.get("milestone_id", "")).strip_edges()
			out.append({
				"type": "employee_no_salary",
				"label": "里程碑/效果免薪",
				"milestone_id": mid,
				"milestone_name": _milestone_name(mid),
				"employee_id": employee_id,
			})

	if EmployeeRulesClass._is_marketing_employee_def(def):
		var marketing_no_salary_read := MilestoneEffectQueriesClass.collect_effect_entries(
			milestones,
			"marketing_no_salary",
			"PaydayEvents: ",
			"player.milestones"
		)
		if marketing_no_salary_read.ok:
			for entry_val2 in Array(marketing_no_salary_read.value):
				if not (entry_val2 is Dictionary):
					continue
				var entry2: Dictionary = entry_val2
				var mid2 := str(entry2.get("milestone_id", "")).strip_edges()
				out.append({
					"type": "marketing_no_salary",
					"label": "营销员工免薪",
					"milestone_id": mid2,
					"milestone_name": _milestone_name(mid2),
					"employee_id": employee_id,
				})

	if out.is_empty():
		var no_salary_val2 = player.get("no_salary_employee_ids", null)
		if no_salary_val2 is Array and Array(no_salary_val2).has(employee_id):
			out.append({
				"type": "employee_no_salary",
				"label": "里程碑/效果免薪",
				"employee_id": employee_id,
			})

	return out

static func _get_salary_total_delta_entries(player: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var milestones_val = player.get("milestones", null)
	if not (milestones_val is Array):
		return out
	var milestones: Array = milestones_val
	var entries_read := MilestoneEffectQueriesClass.collect_effect_entries(
		milestones,
		"salary_total_delta",
		"PaydayEvents: ",
		"player.milestones"
	)
	if not entries_read.ok:
		return out

	for entry_val in Array(entries_read.value):
		if not (entry_val is Dictionary):
			continue
		var entry: Dictionary = entry_val
		var eff_val = entry.get("effect", null)
		if not (eff_val is Dictionary):
			continue
		var eff: Dictionary = eff_val
		var value_val = eff.get("value", null)
		if not (value_val is int or value_val is float):
			continue
		var amount := int(value_val)
		if amount == 0:
			continue
		var mid := str(entry.get("milestone_id", "")).strip_edges()
		out.append({
			"milestone_id": mid,
			"milestone_name": _milestone_name(mid),
			"amount": amount,
		})
	return out

static func _build_salary_discount_sources(player: Dictionary, used_from_discount: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var employees_val = player.get("employees", null)
	if not (employees_val is Array):
		return out
	var employees: Array = employees_val
	var remaining_used := maxi(0, used_from_discount)
	for emp_val in employees:
		if not (emp_val is String):
			continue
		var emp_id := str(emp_val).strip_edges()
		if emp_id.is_empty():
			continue
		var def_val = EmployeeRegistryClass.get_def(emp_id)
		if def_val == null or not (def_val is EmployeeDef):
			continue
		var def: EmployeeDef = def_val
		if not _employee_has_salary_discount_effect(def):
			continue
		var cap := int(def.recruit_capacity)
		if cap <= 0:
			continue
		var used_actions := mini(remaining_used, cap)
		remaining_used = maxi(0, remaining_used - used_actions)
		var unused_actions := maxi(0, cap - used_actions)
		out.append({
			"employee_id": emp_id,
			"name": str(def.name),
			"capacity": cap,
			"used_actions": used_actions,
			"unused_actions": unused_actions,
		})
	return out

static func _employee_has_salary_discount_effect(def: EmployeeDef) -> bool:
	if def == null:
		return false
	for eff_id in def.effect_ids:
		if str(eff_id).find(":payday:salary_discount:") >= 0:
			return true
	return false

static func _sum_token_payment(paid_with_tokens_val) -> int:
	if not (paid_with_tokens_val is Dictionary):
		return 0
	var total := 0
	var paid_with_tokens: Dictionary = paid_with_tokens_val
	for product_id in paid_with_tokens.keys():
		var amount_val = paid_with_tokens.get(product_id, 0)
		if amount_val is int:
			total += int(amount_val)
	return total

static func _count_salary_tokens(player: Dictionary) -> int:
	var inventory_val = player.get("inventory", null)
	if not (inventory_val is Dictionary):
		return 0
	var inventory: Dictionary = inventory_val
	var total := 0
	for product_id in inventory.keys():
		if not EconomyRulesClass.is_salary_token_eligible_product(str(product_id)):
			continue
		var amount_val = inventory.get(product_id, 0)
		if amount_val is int and int(amount_val) > 0:
			total += int(amount_val)
	return total

static func _milestone_name(milestone_id: String) -> String:
	var mid := str(milestone_id).strip_edges()
	if mid.is_empty():
		return ""
	if not MilestoneRegistryClass.is_loaded():
		return mid
	var def_val = MilestoneRegistryClass.get_def(mid)
	if def_val != null and def_val is MilestoneDef:
		var name := str((def_val as MilestoneDef).name).strip_edges()
		if not name.is_empty():
			return name
	return mid

static func _get_paid_employee_ids(employee_items: Array) -> Array[String]:
	var out: Array[String] = []
	for item_val in employee_items:
		if not (item_val is Dictionary):
			continue
		var item: Dictionary = item_val
		if not bool(item.get("requires_salary", false)):
			continue
		var employee_id := str(item.get("employee_id", "")).strip_edges()
		if employee_id.is_empty():
			continue
		out.append(employee_id)
	return out
