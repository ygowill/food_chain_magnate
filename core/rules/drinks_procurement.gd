# 饮料采购规则（从 ProcureDrinksAction 抽离）
# 负责：起点餐厅解析、默认路线生成、路线校验、沿路线拾取来源等纯规则逻辑。
class_name DrinksProcurement
extends RefCounted

const PlanResolverClass = preload("res://core/rules/drinks_procurement/plan_resolver.gd")
const MilestoneBonusesClass = preload("res://core/rules/drinks_procurement/milestone_bonuses.gd")

static func resolve_procurement_plan(
	state: GameState,
	command: Command,
	restaurant_ids: Array[String],
	emp_def: EmployeeDef
) -> Result:
	return PlanResolverClass.resolve_procurement_plan(state, command, restaurant_ids, emp_def)

static func serialize_route(route: Array) -> Array:
	var out: Array = []
	for p in route:
		assert(p is Vector2i, "route 元素必须为 Vector2i")
		var v: Vector2i = p
		out.append([v.x, v.y])
	return out

static func get_drinks_per_source_bonus_from_milestones(state: GameState, player_id: int) -> Result:
	return MilestoneBonusesClass.get_drinks_per_source_bonus_from_milestones(state, player_id)

static func get_drinks_per_source_delta_for_employee_from_milestones(state: GameState, player_id: int, employee_id: String) -> Result:
	return MilestoneBonusesClass.get_drinks_per_source_delta_for_employee_from_milestones(state, player_id, employee_id)

static func _get_distance_range_bonus_from_milestones(state: GameState, player_id: int, employee_id: String) -> Result:
	return MilestoneBonusesClass.get_distance_range_bonus_from_milestones(state, player_id, employee_id)
