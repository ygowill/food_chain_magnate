extends RefCounted

const DemandVariantHelpersClass = preload("res://modules/dinnertime_demand_variant_helpers.gd")

const MODULE_ID := "noodles"
const PRODUCT_ID := "noodles"
const EXTRA_LUXURY_MANAGER_PATCH_ID := "extra_luxury_manager"

func register(registrar) -> Result:
	var r = registrar.register_dinnertime_demand_provider(
		"%s:demand_variants" % MODULE_ID,
		Callable(self, "_get_demand_variants"),
		100
	)
	if not r.ok:
		return r

	# 受控 patch：kitchen_trainee -> noodle_cook（对齐 pizza_cook 等基础训练链）
	r = registrar.register_employee_patch("kitchen_trainee", {
		"add_train_to": ["noodle_cook"]
	})
	if not r.ok:
		return r

	# 额外 +1 张奢侈品经理（多模块同时使用时只加一次）
	r = registrar.register_employee_pool_patch(EXTRA_LUXURY_MANAGER_PATCH_ID, "luxury_manager", 1)
	if not r.ok:
		return r

	return Result.success()

func _get_demand_variants(_state: GameState, _house_id: String, _house: Dictionary, base_required: Dictionary) -> Array[Dictionary]:
	var variants: Array[Dictionary] = []
	if base_required == null or not (base_required is Dictionary):
		return variants
	if base_required.has("coffee"):
		return variants

	var total := DemandVariantHelpersClass.sum_required_counts(base_required)
	if total <= 0:
		return variants

	var v := DemandVariantHelpersClass.build_replace_all_variant(MODULE_ID, PRODUCT_ID, total, 90)
	if not v.is_empty():
		variants.append(v)
	return variants
