extends RefCounted

const DemandVariantHelpersClass = preload("res://core/modules/v2/dinnertime_demand_variant_helpers.gd")

const MODULE_ID := "sushi"
const PRODUCT_ID := "sushi"
const EXTRA_LUXURY_MANAGER_PATCH_ID := "extra_luxury_manager"

func register(registrar) -> Result:
	var r = registrar.register_dinnertime_demand_provider(
		"%s:demand_variants" % MODULE_ID,
		Callable(self, "_get_demand_variants"),
		100
	)
	if not r.ok:
		return r

	# 受控 patch：kitchen_trainee -> sushi_cook（对齐 pizza_cook 等基础训练链）
	r = registrar.register_employee_patch("kitchen_trainee", {
		"add_train_to": ["sushi_cook"]
	})
	if not r.ok:
		return r

	# 额外 +1 张奢侈品经理（多模块同时使用时只加一次）
	r = registrar.register_employee_pool_patch(EXTRA_LUXURY_MANAGER_PATCH_ID, "luxury_manager", 1)
	if not r.ok:
		return r

	return Result.success()

func _get_demand_variants(_state: GameState, _house_id: String, house: Dictionary, base_required: Dictionary) -> Result:
	var variants: Array[Dictionary] = []
	if base_required == null or not (base_required is Dictionary):
		return Result.failure("%s: demand_variants: base_required 类型错误（期望 Dictionary）" % MODULE_ID)
	if house == null or not (house is Dictionary):
		return Result.failure("%s: demand_variants: house 类型错误（期望 Dictionary）" % MODULE_ID)
	if not bool(house.get("has_garden", false)):
		return Result.success(variants)
	if base_required.has("coffee"):
		return Result.success(variants)

	var total := DemandVariantHelpersClass.sum_required_counts(base_required)
	if total <= 0:
		return Result.success(variants)

	var v := DemandVariantHelpersClass.build_replace_all_variant(MODULE_ID, PRODUCT_ID, total, 30)
	if not v.is_empty():
		variants.append(v)
	return Result.success(variants)
