extends RefCounted

const EFFECT_ID := "fry_chefs:dinnertime:sale_house_bonus:fry_chef"

func register(registrar) -> Result:
	var r = registrar.register_effect(EFFECT_ID, Callable(self, "_effect_sale_house_bonus_plus_10"))
	if not r.ok:
		return r

	# 培训：可从任何厨师培训而来；其中寿司/面条厨师为可选（不作为模块依赖）。
	for target_id in ["burger_cook", "pizza_cook"]:
		r = registrar.register_employee_patch(target_id, {"add_train_to": ["fry_chef"]})
		if not r.ok:
			return r
	for target_id in ["noodle_cook", "sushi_cook"]:
		r = registrar.register_employee_patch(target_id, {"add_train_to": ["fry_chef"], "optional": true})
		if not r.ok:
			return r

	return Result.success()

func _effect_sale_house_bonus_plus_10(_state: GameState, _player_id: int, ctx: Dictionary) -> Result:
	if ctx == null or not (ctx is Dictionary):
		return Result.failure("fry_chefs:sale_house_bonus: ctx 类型错误（期望 Dictionary）")
	if not ctx.has("bonus") or not (ctx["bonus"] is int):
		return Result.failure("fry_chefs:sale_house_bonus: ctx.bonus 缺失或类型错误（期望 int）")

	ctx["bonus"] = int(ctx["bonus"]) + 10
	if ctx.has("bonus_breakdown") and (ctx["bonus_breakdown"] is Dictionary):
		var breakdown: Dictionary = ctx["bonus_breakdown"]
		breakdown["fry_chef"] = int(breakdown.get("fry_chef", 0)) + 10
		ctx["bonus_breakdown"] = breakdown
	return Result.success()
