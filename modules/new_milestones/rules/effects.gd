extends RefCounted

const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")

const EFFECT_ID_FIRST_MARKETEER_DISTANCE := "new_milestones:dinnertime:distance_delta:first_marketeer_used"
const EFFECT_ID_FIRST_MARKETEER_DEMAND_CASH := "new_milestones:marketing:demand_cash:first_marketeer_used"

func register(registrar) -> Result:
	var r = registrar.register_effect(EFFECT_ID_FIRST_MARKETEER_DISTANCE, Callable(self, "_effect_first_marketeer_distance_minus_two"))
	if not r.ok:
		return r
	r = registrar.register_effect(EFFECT_ID_FIRST_MARKETEER_DEMAND_CASH, Callable(self, "_effect_first_marketeer_demand_cash_bonus"))
	if not r.ok:
		return r
	return Result.success()

func _effect_first_marketeer_distance_minus_two(_state: GameState, _player_id: int, ctx: Dictionary) -> Result:
	if ctx == null or not (ctx is Dictionary):
		return Result.failure("new_milestones:first_marketeer_used: ctx 类型错误（期望 Dictionary）")
	if not ctx.has("distance") or not (ctx["distance"] is int):
		return Result.failure("new_milestones:first_marketeer_used: ctx.distance 缺失或类型错误（期望 int）")
	if not ctx.has("allow_negative") or not (ctx["allow_negative"] is bool):
		return Result.failure("new_milestones:first_marketeer_used: ctx.allow_negative 缺失或类型错误（期望 bool）")
	ctx["allow_negative"] = true
	ctx["distance"] = int(ctx["distance"]) - 2
	return Result.success()

func _effect_first_marketeer_demand_cash_bonus(_state: GameState, _player_id: int, ctx: Dictionary) -> Result:
	if ctx == null or not (ctx is Dictionary):
		return Result.failure("new_milestones:first_marketeer_used: ctx 类型错误（期望 Dictionary）")
	if not ctx.has("demands_added") or not (ctx["demands_added"] is int):
		return Result.failure("new_milestones:first_marketeer_used: ctx.demands_added 缺失或类型错误（期望 int）")
	if not ctx.has("cash_bonus") or not (ctx["cash_bonus"] is int):
		return Result.failure("new_milestones:first_marketeer_used: ctx.cash_bonus 缺失或类型错误（期望 int）")
	if not ctx.has("marketing_instance") or not (ctx["marketing_instance"] is Dictionary):
		return Result.failure("new_milestones:first_marketeer_used: ctx.marketing_instance 缺失或类型错误（期望 Dictionary）")
	var inst: Dictionary = ctx["marketing_instance"]
	if not inst.has("employee_type") or not (inst["employee_type"] is String):
		return Result.failure("new_milestones:first_marketeer_used: marketing_instance.employee_type 缺失或类型错误（期望 String）")
	var employee_type: String = str(inst["employee_type"])
	if employee_type.is_empty():
		return Result.failure("new_milestones:first_marketeer_used: marketing_instance.employee_type 不能为空")

	var emp_def = EmployeeRegistryClass.get_def(employee_type)
	if emp_def == null:
		return Result.success()

	var is_marketeer := false
	for t in emp_def.usage_tags:
		if t is String and str(t).begins_with("use:marketing:"):
			is_marketeer = true
			break
	if not is_marketeer:
		return Result.success()

	var demands_added: int = int(ctx["demands_added"])
	if demands_added <= 0:
		return Result.success()

	ctx["cash_bonus"] = int(ctx["cash_bonus"]) + demands_added * 5
	return Result.success()

