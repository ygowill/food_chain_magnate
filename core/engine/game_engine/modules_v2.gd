# GameEngine：模块系统 V2（Strict Mode）装配/校验/重置
# 说明：
# - 该文件只负责“装配与全局 registry 初始化”，不负责 GameState 初始化/命令执行。
# - 设计目标：把 GameEngine.gd 中与模块系统相关的细节集中到单文件，降低主类体积与漂移风险。
extends RefCounted

const ContentCatalogClass = preload("res://core/modules/v2/content_catalog.gd")
const ContentCatalogLoaderV2Class = preload("res://core/modules/v2/content_catalog_loader.gd")
const ModulePackageLoaderV2Class = preload("res://core/modules/v2/module_package_loader.gd")
const ModulePlanBuilderV2Class = preload("res://core/modules/v2/module_plan_builder.gd")
const RulesetLoaderV2Class = preload("res://core/modules/v2/ruleset_loader.gd")
const ModuleDirSpecClass = preload("res://core/modules/v2/module_dir_spec.gd")

const ProductRegistryClass = preload("res://core/data/product_registry.gd")
const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")
const MarketingRegistryClass = preload("res://core/data/marketing_registry.gd")
const MilestoneRegistryClass = preload("res://core/data/milestone_registry.gd")

const MarketingTypeRegistryClass = preload("res://core/rules/marketing_type_registry.gd")
const BankruptcyRegistryClass = preload("res://core/rules/bankruptcy_registry.gd")
const DinnertimeDemandRegistryClass = preload("res://core/rules/dinnertime_demand_registry.gd")
const DinnertimeRoutePurchaseRegistryClass = preload("res://core/rules/dinnertime_route_purchase_registry.gd")
const MarketingInitiationRegistryClass = preload("res://core/rules/marketing_initiation_registry.gd")
const EmployeePoolPatchRegistryClass = preload("res://core/rules/employee_pool_patch_registry.gd")
const MilestoneEffectRegistryClass = preload("res://core/rules/milestone_effect_registry.gd")

const TileRegistryClass = preload("res://core/map/tile_registry.gd")
const PieceRegistryClass = preload("res://core/map/piece_registry.gd")

static func reset(engine) -> void:
	if engine == null:
		return

	var empty_plan: Array[String] = []
	engine.module_plan_v2 = empty_plan
	engine.module_manifests_v2 = {}
	engine.content_catalog_v2 = ContentCatalogClass.new()
	engine.ruleset_v2 = null
	engine.modules_v2_base_dir = ""

	ProductRegistryClass.reset()
	EmployeeRegistryClass.reset()
	MarketingRegistryClass.reset()
	MarketingTypeRegistryClass.reset()
	BankruptcyRegistryClass.reset()
	DinnertimeDemandRegistryClass.reset()
	DinnertimeRoutePurchaseRegistryClass.reset()
	MarketingInitiationRegistryClass.reset()
	EmployeePoolPatchRegistryClass.reset()
	MilestoneRegistryClass.reset()
	MilestoneEffectRegistryClass.reset_current()
	TileRegistryClass.reset()
	PieceRegistryClass.reset()

	if engine.phase_manager != null and engine.phase_manager.has_method("set_settlement_registry"):
		engine.phase_manager.set_settlement_registry(null)
	if engine.phase_manager != null and engine.phase_manager.has_method("set_effect_registry"):
		engine.phase_manager.set_effect_registry(null)

static func apply(engine, module_ids: Array[String], base_dir: String) -> Result:
	if engine == null:
		return Result.failure("内部错误：GameEngine 为空")

	engine.modules_v2_base_dir = base_dir
	var empty_plan: Array[String] = []
	engine.module_plan_v2 = empty_plan
	engine.module_manifests_v2 = {}
	engine.content_catalog_v2 = ContentCatalogClass.new()
	engine.ruleset_v2 = null

	if module_ids.is_empty():
		return Result.failure("模块系统 V2：enabled_modules_v2 不能为空（严格模式）")
	var base_dirs_read := ModuleDirSpecClass.parse_base_dirs(base_dir)
	if not base_dirs_read.ok:
		return Result.failure("模块系统 V2：modules_v2_base_dir 不能为空")
	var base_dirs: Array[String] = base_dirs_read.value

	var manifests_read := ModulePackageLoaderV2Class.load_all_from_dirs(base_dirs)
	if not manifests_read.ok:
		return Result.failure("模块系统 V2：加载模块包失败: %s" % manifests_read.error)
	var manifests: Dictionary = manifests_read.value
	engine.module_manifests_v2 = manifests

	var plan_read := ModulePlanBuilderV2Class.build_plan(manifests, module_ids)
	if not plan_read.ok:
		return Result.failure("模块系统 V2：构建模块启用计划失败: %s" % plan_read.error)
	engine.module_plan_v2 = Array(plan_read.value, TYPE_STRING, "", null)

	var catalog_read := ContentCatalogLoaderV2Class.load_for_modules_from_dirs(base_dirs, engine.module_plan_v2)
	if not catalog_read.ok:
		return Result.failure("模块系统 V2：加载模块内容失败: %s" % catalog_read.error)
	engine.content_catalog_v2 = catalog_read.value

	var ruleset_read := RulesetLoaderV2Class.build_for_plan(engine.module_manifests_v2, engine.module_plan_v2)
	if not ruleset_read.ok:
		return Result.failure("模块系统 V2：加载模块规则失败: %s" % ruleset_read.error)
	engine.ruleset_v2 = ruleset_read.value

	# V2：模块注册的营销类型（供 MarketingRange/Placement 插拔）
	var mk_types_apply := MarketingTypeRegistryClass.configure_from_ruleset(engine.ruleset_v2)
	if not mk_types_apply.ok:
		return Result.failure("模块系统 V2：%s" % mk_types_apply.error)

	# V2：模块注册的破产处理器（供 Reserve Prices 等模块替换规则）
	var bankruptcy_apply := BankruptcyRegistryClass.configure_from_ruleset(engine.ruleset_v2)
	if not bankruptcy_apply.ok:
		return Result.failure("模块系统 V2：%s" % bankruptcy_apply.error)

	# V2：模块注册的晚餐需求替代方案（寿司/面条/泡菜等）
	var demand_apply := DinnertimeDemandRegistryClass.configure_from_ruleset(engine.ruleset_v2)
	if not demand_apply.ok:
		return Result.failure("模块系统 V2：%s" % demand_apply.error)

	# V2：模块注册的晚餐“路上购买/结算”逻辑（Coffee 等）
	var route_apply := DinnertimeRoutePurchaseRegistryClass.configure_from_ruleset(engine.ruleset_v2)
	if not route_apply.ok:
		return Result.failure("模块系统 V2：%s" % route_apply.error)

	# V2：模块注册的 employee_pool 调整（例如“额外 +1 张 luxury_manager”）
	var pool_patch_apply := EmployeePoolPatchRegistryClass.configure_from_ruleset(engine.ruleset_v2)
	if not pool_patch_apply.ok:
		return Result.failure("模块系统 V2：%s" % pool_patch_apply.error)

	# V2：模块注册的发起营销扩展逻辑（Campaign/Brand 等）
	var mk_init_apply := MarketingInitiationRegistryClass.configure_from_ruleset(engine.ruleset_v2)
	if not mk_init_apply.ok:
		return Result.failure("模块系统 V2：%s" % mk_init_apply.error)

	# V2：允许模块对已加载内容做受控 patch（例如跨模块培训链）
	var emp_patch_apply: Result = engine.ruleset_v2.apply_employee_patches(engine.content_catalog_v2)
	if not emp_patch_apply.ok:
		return Result.failure("模块系统 V2：%s" % emp_patch_apply.error)

	# V2：允许模块对里程碑做受控 patch（例如 Hard Choices：过期回合）
	var ms_patch_apply: Result = engine.ruleset_v2.apply_milestone_patches(engine.content_catalog_v2)
	if not ms_patch_apply.ok:
		return Result.failure("模块系统 V2：%s" % ms_patch_apply.error)

	if engine.phase_manager != null and engine.phase_manager.has_method("set_settlement_registry"):
		engine.phase_manager.set_settlement_registry(engine.ruleset_v2.settlement_registry)
	if engine.phase_manager != null and engine.phase_manager.has_method("set_effect_registry"):
		engine.phase_manager.set_effect_registry(engine.ruleset_v2.effect_registry)

	# V2：模块注册的 phase/sub_phase hooks
	if engine.phase_manager != null and engine.ruleset_v2 != null and engine.ruleset_v2.has_method("apply_hooks_to_phase_manager"):
		var hook_apply: Result = engine.ruleset_v2.apply_hooks_to_phase_manager(engine.phase_manager)
		if not hook_apply.ok:
			return Result.failure("模块系统 V2：%s" % hook_apply.error)
	if engine.phase_manager != null and engine.phase_manager.has_method("validate_required_primary_settlements"):
		var required_check: Result = engine.phase_manager.validate_required_primary_settlements()
		if not required_check.ok:
			return Result.failure("模块系统 V2：缺少必需结算器: %s" % required_check.error)

	# strict：所有 content 引用的 effect_id 必须有 handler（否则 init fail）
	var effect_check: Result = engine.ruleset_v2.validate_content_effect_handlers(engine.content_catalog_v2)
	if not effect_check.ok:
		return Result.failure("模块系统 V2：%s" % effect_check.error)

	# strict：所有里程碑 effects.type 必须有 handler（否则 init fail）
	var ms_effect_check: Result = engine.ruleset_v2.validate_content_milestone_effect_handlers(engine.content_catalog_v2)
	if not ms_effect_check.ok:
		return Result.failure("模块系统 V2：%s" % ms_effect_check.error)

	MilestoneEffectRegistryClass.set_current(engine.ruleset_v2.milestone_effect_registry)

	var prod_reg := ProductRegistryClass.configure_from_catalog(engine.content_catalog_v2)
	if not prod_reg.ok:
		return Result.failure("模块系统 V2：配置 ProductRegistry 失败: %s" % prod_reg.error)

	# 所有 content 引用的 product 必须存在（否则 init fail）
	var product_ref_check := _validate_content_product_references(engine.content_catalog_v2)
	if not product_ref_check.ok:
		return Result.failure("模块系统 V2：%s" % product_ref_check.error)

	# strict：员工培训链 train_to 引用必须存在（否则 init fail）
	var train_ref_check := _validate_employee_train_to_references(engine.content_catalog_v2)
	if not train_ref_check.ok:
		return Result.failure("模块系统 V2：%s" % train_ref_check.error)

	var emp_reg := EmployeeRegistryClass.configure_from_catalog(engine.content_catalog_v2)
	if not emp_reg.ok:
		return Result.failure("模块系统 V2：配置 EmployeeRegistry 失败: %s" % emp_reg.error)
	var mk_reg := MarketingRegistryClass.configure_from_catalog(engine.content_catalog_v2)
	if not mk_reg.ok:
		return Result.failure("模块系统 V2：配置 MarketingRegistry 失败: %s" % mk_reg.error)
	var ms_reg := MilestoneRegistryClass.configure_from_catalog(engine.content_catalog_v2)
	if not ms_reg.ok:
		return Result.failure("模块系统 V2：配置 MilestoneRegistry 失败: %s" % ms_reg.error)
	var tile_reg := TileRegistryClass.configure_from_catalog(engine.content_catalog_v2)
	if not tile_reg.ok:
		return Result.failure("模块系统 V2：配置 TileRegistry 失败: %s" % tile_reg.error)
	var piece_reg := PieceRegistryClass.configure_from_catalog(engine.content_catalog_v2)
	if not piece_reg.ok:
		return Result.failure("模块系统 V2：配置 PieceRegistry 失败: %s" % piece_reg.error)

	return Result.success().with_warnings(ruleset_read.warnings)

static func validate_starting_inventory_products(cfg) -> Result:
	if cfg == null:
		return Result.failure("GameConfig 为空")

	if not (cfg.player_starting_inventory is Dictionary):
		return Result.failure("GameConfig.player.starting_inventory 类型错误（期望 Dictionary）")
	var inv: Dictionary = cfg.player_starting_inventory

	if not ProductRegistryClass.is_loaded():
		return Result.failure("ProductRegistry 未初始化")
	var product_ids: Array[String] = ProductRegistryClass.get_all_ids()
	if product_ids.is_empty():
		return Result.failure("ProductRegistry.products 为空：必须至少定义 1 个产品")

	var extras: Array[String] = []
	for k in inv.keys():
		if not (k is String):
			return Result.failure("GameConfig.player.starting_inventory key 类型错误（期望 String）")
		var key: String = str(k)
		if not ProductRegistryClass.has(key):
			extras.append(key)

	if not extras.is_empty():
		extras.sort()
		return Result.failure("GameConfig.player.starting_inventory 存在未知产品: %s" % ", ".join(extras))

	return Result.success()

static func _validate_employee_train_to_references(catalog) -> Result:
	if catalog == null:
		return Result.failure("ContentCatalog 为空")
	if not (catalog.employees is Dictionary):
		return Result.failure("catalog.employees 类型错误（期望 Dictionary）")

	for emp_id_val in catalog.employees.keys():
		if not (emp_id_val is String):
			return Result.failure("catalog.employees key 类型错误（期望 String）")
		var emp_id: String = str(emp_id_val)
		if emp_id.is_empty():
			return Result.failure("catalog.employees key 不能为空")
		var def_val = catalog.employees.get(emp_id, null)
		if def_val == null:
			return Result.failure("catalog.employees[%s] 为空" % emp_id)
		if not (def_val is EmployeeDef):
			return Result.failure("catalog.employees[%s] 类型错误（期望 EmployeeDef）" % emp_id)
		var def: EmployeeDef = def_val

		for i in range(def.train_to.size()):
			var to_val = def.train_to[i]
			if not (to_val is String):
				return Result.failure("employees[%s].train_to[%d] 类型错误（期望 String）" % [emp_id, i])
			var to_id: String = str(to_val)
			if to_id.is_empty():
				return Result.failure("employees[%s].train_to[%d] 不能为空" % [emp_id, i])
			if not catalog.employees.has(to_id):
				return Result.failure("员工培训链引用不存在: %s.train_to -> %s" % [emp_id, to_id])

	return Result.success()

static func _validate_content_product_references(catalog) -> Result:
	if catalog == null:
		return Result.failure("ContentCatalog 为空")

	if not ProductRegistryClass.is_loaded():
		return Result.failure("ProductRegistry 未初始化")

	# === employees.produces.food_type ===
	if not (catalog.employees is Dictionary):
		return Result.failure("catalog.employees 类型错误（期望 Dictionary）")
	for emp_id_val in catalog.employees.keys():
		if not (emp_id_val is String):
			return Result.failure("catalog.employees key 类型错误（期望 String）")
		var emp_id: String = str(emp_id_val)
		var emp_def_val = catalog.employees.get(emp_id, null)
		if emp_def_val == null:
			return Result.failure("catalog.employees[%s] 为空" % emp_id)
		if not (emp_def_val is EmployeeDef):
			return Result.failure("catalog.employees[%s] 类型错误（期望 EmployeeDef）" % emp_id)
		var emp_def: EmployeeDef = emp_def_val
		if emp_def.can_produce():
			var food_type: String = emp_def.produces_food_type
			var check := _validate_product_reference(food_type, "EmployeeDef[%s].produces.food_type" % emp_id, false, "food")
			if not check.ok:
				return check

	# === tiles.drink_sources[*].type ===
	if not (catalog.tiles is Dictionary):
		return Result.failure("catalog.tiles 类型错误（期望 Dictionary）")
	for tile_id_val in catalog.tiles.keys():
		if not (tile_id_val is String):
			return Result.failure("catalog.tiles key 类型错误（期望 String）")
		var tile_id: String = str(tile_id_val)
		var tile_def_val = catalog.tiles.get(tile_id, null)
		if tile_def_val == null:
			return Result.failure("catalog.tiles[%s] 为空" % tile_id)
		if not (tile_def_val is TileDef):
			return Result.failure("catalog.tiles[%s] 类型错误（期望 TileDef）" % tile_id)
		var tile_def: TileDef = tile_def_val
		for i in range(tile_def.drink_sources.size()):
			var src_val = tile_def.drink_sources[i]
			if not (src_val is Dictionary):
				return Result.failure("TileDef[%s].drink_sources[%d] 类型错误（期望 Dictionary）" % [tile_id, i])
			var src: Dictionary = src_val
			var t_val = src.get("type", null)
			if not (t_val is String):
				return Result.failure("TileDef[%s].drink_sources[%d].type 类型错误（期望 String）" % [tile_id, i])
			var drink_type: String = str(t_val)
			var check2 := _validate_product_reference(drink_type, "TileDef[%s].drink_sources[%d].type" % [tile_id, i], false, "drink")
			if not check2.ok:
				return check2

	# === milestones trigger/effects 中的 product 引用 ===
	if not (catalog.milestones is Dictionary):
		return Result.failure("catalog.milestones 类型错误（期望 Dictionary）")
	for mid_val in catalog.milestones.keys():
		if not (mid_val is String):
			return Result.failure("catalog.milestones key 类型错误（期望 String）")
		var mid: String = str(mid_val)
		var ms_def_val = catalog.milestones.get(mid, null)
		if ms_def_val == null:
			return Result.failure("catalog.milestones[%s] 为空" % mid)
		if not (ms_def_val is MilestoneDef):
			return Result.failure("catalog.milestones[%s] 类型错误（期望 MilestoneDef）" % mid)
		var ms_def: MilestoneDef = ms_def_val

		var filter_check := _validate_product_keys_in_variant(ms_def.trigger_filter, "MilestoneDef[%s].trigger.filter" % mid)
		if not filter_check.ok:
			return filter_check

		for e_i in range(ms_def.effects.size()):
			var eff_val = ms_def.effects[e_i]
			var eff_check := _validate_product_keys_in_variant(eff_val, "MilestoneDef[%s].effects[%d]" % [mid, e_i])
			if not eff_check.ok:
				return eff_check

	return Result.success()

static func _validate_product_keys_in_variant(value, path: String) -> Result:
	if value is Dictionary:
		var d: Dictionary = value
		for k in d.keys():
			var key: String = str(k)
			var child_path := "%s.%s" % [path, key]
			if key == "product":
				var p_val = d.get(k, null)
				if not (p_val is String):
					return Result.failure("%s 类型错误（期望 String）" % child_path)
				var p: String = str(p_val)
				var pr := _validate_product_reference(p, child_path, true, "")
				if not pr.ok:
					return pr
			var nested := _validate_product_keys_in_variant(d.get(k, null), child_path)
			if not nested.ok:
				return nested
		return Result.success()
	if value is Array:
		var a: Array = value
		for i in range(a.size()):
			var nested2 := _validate_product_keys_in_variant(a[i], "%s[%d]" % [path, i])
			if not nested2.ok:
				return nested2
		return Result.success()
	return Result.success()

static func _validate_product_reference(product_id: String, path: String, allow_drink_category: bool, required_tag: String) -> Result:
	if product_id.is_empty():
		return Result.failure("%s 不能为空" % path)
	if allow_drink_category and product_id == "drink":
		return Result.success()
	if product_id == "drink":
		return Result.failure("%s 不允许为保留字: drink" % path)
	if not ProductRegistryClass.has(product_id):
		return Result.failure("%s 未知产品: %s" % [path, product_id])

	if not required_tag.is_empty():
		var def = ProductRegistryClass.get_def(product_id)
		if def == null:
			return Result.failure("%s 未知产品: %s" % [path, product_id])
		if not def.has_method("has_tag") or not def.has_tag(required_tag):
			return Result.failure("%s 必须带 tag=%s，实际: %s" % [path, required_tag, product_id])

	return Result.success()
