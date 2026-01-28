# ProductionPanel used-state sync regression test
# 目标：当面板内部缓存的“已使用员工”状态残留时，set_used_employee_counts 必须能覆盖为基于计数的结果。
class_name ProductionPanelUsedCountsSyncTest
extends RefCounted

const ProductionPanelScene = preload("res://ui/components/production_panel/production_panel.tscn")

static func run() -> Result:
	if ProductionPanelScene == null:
		return Result.failure("预加载 production_panel.tscn 失败（PackedScene 为空）")

	var panel = ProductionPanelScene.instantiate()
	if panel == null or not is_instance_valid(panel):
		return Result.failure("实例化 ProductionPanel 失败（instantiate 为空）")

	# drinks：先制造“残留禁用态”，再用空计数覆盖，应全部清空
	if panel.has_method("set_production_type"):
		panel.set_production_type("drinks")
	panel.set("_used_employee_keys_by_mode", {
		"food": {"burger_cook#1": true},
		"drinks": {"zeppelin_pilot#1": true, "zeppelin_pilot#2": true},
	})
	if panel.has_method("set_used_employee_counts"):
		panel.set_used_employee_counts({})
	else:
		_safe_free(panel)
		return Result.failure("ProductionPanel 缺少 set_used_employee_counts")

	var used_after = panel.get("_used_employee_keys_by_mode")
	if not (used_after is Dictionary):
		_safe_free(panel)
		return Result.failure("_used_employee_keys_by_mode 类型错误（期望 Dictionary）")
	var used_map: Dictionary = used_after
	var drinks_val = used_map.get("drinks", null)
	if not (drinks_val is Dictionary):
		_safe_free(panel)
		return Result.failure("_used_employee_keys_by_mode.drinks 类型错误（期望 Dictionary）")
	if not (drinks_val as Dictionary).is_empty():
		_safe_free(panel)
		return Result.failure("drinks 用空计数覆盖后应清空，但实际=%s" % str(drinks_val))

	# food 不应被 drinks 覆盖影响
	var food_val = used_map.get("food", null)
	if not (food_val is Dictionary):
		_safe_free(panel)
		return Result.failure("_used_employee_keys_by_mode.food 类型错误（期望 Dictionary）")
	if (food_val as Dictionary).is_empty():
		_safe_free(panel)
		return Result.failure("food 不应被 drinks 覆盖清空（期望保留），但为空")

	# food：写入计数后应生成对应 key（employee_id#idx）
	panel.set_production_type("food")
	panel.set_used_employee_counts({"burger_cook": 2})

	used_after = panel.get("_used_employee_keys_by_mode")
	used_map = used_after if (used_after is Dictionary) else {}
	food_val = used_map.get("food", null)
	if not (food_val is Dictionary):
		_safe_free(panel)
		return Result.failure("_used_employee_keys_by_mode.food 类型错误（期望 Dictionary）")
	var food_used: Dictionary = food_val
	if not food_used.has("burger_cook#1") or not food_used.has("burger_cook#2") or food_used.has("burger_cook#3"):
		_safe_free(panel)
		return Result.failure("food key 生成不符合预期: %s" % str(food_used.keys()))

	_safe_free(panel)
	return Result.success()

static func _safe_free(node: Node) -> void:
	if node != null and is_instance_valid(node):
		node.free()

