extends RefCounted

const EFFECT_ID := "fry_chefs:dinnertime:sale_house_bonus:fry_chef"

func register(registrar) -> Result:
	var r = registrar.register_effect(EFFECT_ID, Callable(self, "_effect_sale_house_bonus_plus_10"))
	if not r.ok:
		return r

	# 培训：可从任何厨师（汉堡、披萨、寿司、面条）培训而来
	for target_id in ["burger_cook", "burger_chef", "pizza_cook", "pizza_chef", "noodles_cook", "sushi_cook"]:
		r = registrar.register_employee_patch(target_id, {"add_train_to": ["fry_chef"]})
		if not r.ok:
			return r

	return Result.success()

func _effect_sale_house_bonus_plus_10(_state: GameState, _player_id: int, ctx: Dictionary) -> Result:
	if ctx == null or not (ctx is Dictionary):
		return Result.failure("fry_chefs:sale_house_bonus: ctx 类型错误（期望 Dictionary）")
	if not ctx.has("bonus") or not (ctx["bonus"] is int):
		return Result.failure("fry_chefs:sale_house_bonus: ctx.bonus 缺失或类型错误（期望 int）")
	if not ctx.has("has_non_drink_food") or not (ctx["has_non_drink_food"] is bool):
		return Result.failure("fry_chefs:sale_house_bonus: ctx.has_non_drink_food 缺失或类型错误（期望 bool）")

	if not bool(ctx["has_non_drink_food"]):
		return Result.success()

	ctx["bonus"] = int(ctx["bonus"]) + 10
	return Result.success()

