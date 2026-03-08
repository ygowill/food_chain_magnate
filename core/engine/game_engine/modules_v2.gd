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
const PlacementConflictRegistryClass = preload("res://core/rules/placement_conflict_registry.gd")
const RangeOriginRegistryClass = preload("res://core/rules/range_origin_registry.gd")
const StateSchemaRegistryClass = preload("res://core/state/state_schema_registry.gd")

const TileRegistryClass = preload("res://core/map/tile_registry.gd")
const PieceRegistryClass = preload("res://core/map/piece_registry.gd")
const PerfTraceClass = preload("res://core/debug/perf_trace.gd")
const ValidationsClass = preload("res://core/engine/game_engine/modules_v2_validations.gd")

static func reset(engine) -> void:
	if engine == null:
		return

	var old_ruleset = engine.ruleset_v2
	if old_ruleset != null and old_ruleset.has_method("dispose"):
		old_ruleset.dispose()
	var old_catalog = engine.content_catalog_v2
	if old_catalog != null and old_catalog.has_method("clear"):
		old_catalog.clear()
	var old_ui_extensions = engine.module_ui_extensions_v2
	if old_ui_extensions != null and old_ui_extensions.has_method("clear"):
		old_ui_extensions.clear()

	var empty_plan: Array[String] = []
	engine.module_plan_v2 = empty_plan
	engine.module_manifests_v2 = {}
	engine.content_catalog_v2 = ContentCatalogClass.new()
	engine.ruleset_v2 = null
	engine.module_ui_extensions_v2 = null
	engine.modules_v2_base_dir = ""
	if engine.catalog_registry_bundle != null and engine.catalog_registry_bundle.has_method("clear"):
		engine.catalog_registry_bundle.clear()
	if engine.rules_registry_bundle != null and engine.rules_registry_bundle.has_method("clear"):
		engine.rules_registry_bundle.clear()
	if engine.has_method("activate_registry_bundles"):
		engine.activate_registry_bundles()

	MarketingTypeRegistryClass.reset()
	BankruptcyRegistryClass.reset()
	DinnertimeDemandRegistryClass.reset()
	DinnertimeRoutePurchaseRegistryClass.reset()
	MarketingInitiationRegistryClass.reset()
	EmployeePoolPatchRegistryClass.reset()
	PlacementConflictRegistryClass.reset()
	RangeOriginRegistryClass.reset()
	StateSchemaRegistryClass.reset()
	MilestoneEffectRegistryClass.reset_current()

	if engine.phase_manager != null and engine.phase_manager.has_method("set_settlement_registry"):
		engine.phase_manager.set_settlement_registry(null)
	if engine.phase_manager != null and engine.phase_manager.has_method("set_effect_registry"):
		engine.phase_manager.set_effect_registry(null)
	if engine.phase_manager != null and engine.phase_manager.has_method("reset_hooks"):
		engine.phase_manager.reset_hooks()

static func apply(engine, module_ids: Array[String], base_dir: String) -> Result:
	if engine == null:
		return Result.failure("内部错误：GameEngine 为空")

	var span_total := PerfTraceClass.begin_span("modules_v2:apply")
	engine.modules_v2_base_dir = base_dir
	var empty_plan: Array[String] = []
	engine.module_plan_v2 = empty_plan
	engine.module_manifests_v2 = {}
	engine.content_catalog_v2 = ContentCatalogClass.new()
	engine.ruleset_v2 = null
	engine.module_ui_extensions_v2 = null
	if engine.catalog_registry_bundle != null and engine.catalog_registry_bundle.has_method("clear"):
		engine.catalog_registry_bundle.clear()
	if engine.rules_registry_bundle != null and engine.rules_registry_bundle.has_method("clear"):
		engine.rules_registry_bundle.clear()
	if engine.has_method("activate_registry_bundles"):
		engine.activate_registry_bundles()
	MarketingTypeRegistryClass.reset()
	BankruptcyRegistryClass.reset()
	MarketingInitiationRegistryClass.reset()
	PlacementConflictRegistryClass.reset()

	if module_ids.is_empty():
		return Result.failure("模块系统 V2：enabled_modules_v2 不能为空（严格模式）")
	var span_base_dirs := PerfTraceClass.begin_span("modules_v2:parse_base_dirs")
	var base_dirs_read := ModuleDirSpecClass.parse_base_dirs(base_dir)
	PerfTraceClass.end_span(span_base_dirs)
	if not base_dirs_read.ok:
		return Result.failure("模块系统 V2：modules_v2_base_dir 不能为空")
	var base_dirs: Array[String] = base_dirs_read.value

	var span_manifests := PerfTraceClass.begin_span("modules_v2:load_all_manifests")
	var manifests_read := ModulePackageLoaderV2Class.load_all_from_dirs(base_dirs)
	PerfTraceClass.end_span(span_manifests)
	if not manifests_read.ok:
		return Result.failure("模块系统 V2：加载模块包失败: %s" % manifests_read.error)
	var manifests: Dictionary = manifests_read.value
	engine.module_manifests_v2 = manifests

	var span_plan := PerfTraceClass.begin_span("modules_v2:build_plan")
	var plan_read := ModulePlanBuilderV2Class.build_plan(manifests, module_ids)
	PerfTraceClass.end_span(span_plan)
	if not plan_read.ok:
		return Result.failure("模块系统 V2：构建模块启用计划失败: %s" % plan_read.error)
	engine.module_plan_v2 = Array(plan_read.value, TYPE_STRING, "", null)

	var span_catalog := PerfTraceClass.begin_span("modules_v2:load_content_catalog")
	var catalog_read := ContentCatalogLoaderV2Class.load_for_modules_from_dirs(base_dirs, engine.module_plan_v2)
	PerfTraceClass.end_span(span_catalog)
	if not catalog_read.ok:
		return Result.failure("模块系统 V2：加载模块内容失败: %s" % catalog_read.error)
	engine.content_catalog_v2 = catalog_read.value

	var span_ruleset := PerfTraceClass.begin_span("modules_v2:build_ruleset")
	var ruleset_read := RulesetLoaderV2Class.build_for_plan(engine.module_manifests_v2, engine.module_plan_v2)
	PerfTraceClass.end_span(span_ruleset)
	if not ruleset_read.ok:
		return Result.failure("模块系统 V2：加载模块规则失败: %s" % ruleset_read.error)
	if not (ruleset_read.value is Dictionary):
		return Result.failure("模块系统 V2：ruleset loader 返回值类型错误（期望 Dictionary）")
	var ruleset_payload: Dictionary = ruleset_read.value
	engine.ruleset_v2 = ruleset_payload.get("ruleset", null)
	engine.module_ui_extensions_v2 = ruleset_payload.get("ui_extensions", null)
	if engine.ruleset_v2 == null:
		return Result.failure("模块系统 V2：ruleset loader 未返回 ruleset")
	if engine.module_ui_extensions_v2 == null:
		return Result.failure("模块系统 V2：ruleset loader 未返回 ui_extensions")

	var span_ruleset_apply := PerfTraceClass.begin_span("modules_v2:apply_ruleset_registries")
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

	# V2：模块注册的放置冲突查询 provider（用于跨模块冲突检测，避免窥探 state key）
	var conflict_apply := PlacementConflictRegistryClass.configure_from_ruleset(engine.ruleset_v2)
	if not conflict_apply.ok:
		return Result.failure("模块系统 V2：%s" % conflict_apply.error)

	# V2：模块注册的 range 起点扩展（例如 coffee_shop）
	var range_origin_apply := RangeOriginRegistryClass.configure_from_ruleset(engine.ruleset_v2)
	if not range_origin_apply.ok:
		return Result.failure("模块系统 V2：%s" % range_origin_apply.error)

	# V2：模块注册的 state schema（用于反序列化归一化与契约检查）
	var schema_apply := StateSchemaRegistryClass.configure_from_ruleset(engine.ruleset_v2)
	if not schema_apply.ok:
		return Result.failure("模块系统 V2：%s" % schema_apply.error)

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
	PerfTraceClass.end_span(span_ruleset_apply)

	var span_catalog_registries := PerfTraceClass.begin_span("modules_v2:configure_registries_from_catalog")
	var prod_reg := ProductRegistryClass.configure_from_catalog(engine.content_catalog_v2, engine.get_catalog_registry_bundle())
	if not prod_reg.ok:
		return Result.failure("模块系统 V2：配置 ProductRegistry 失败: %s" % prod_reg.error)

	# 所有 content 引用的 product 必须存在（否则 init fail）
	var product_ref_check := ValidationsClass.validate_content_product_references(engine.content_catalog_v2)
	if not product_ref_check.ok:
		return Result.failure("模块系统 V2：%s" % product_ref_check.error)

	# strict：员工培训链 train_to 引用必须存在（否则 init fail）
	var train_ref_check := ValidationsClass.validate_employee_train_to_references(engine.content_catalog_v2)
	if not train_ref_check.ok:
		return Result.failure("模块系统 V2：%s" % train_ref_check.error)

	var emp_reg := EmployeeRegistryClass.configure_from_catalog(engine.content_catalog_v2, engine.get_catalog_registry_bundle())
	if not emp_reg.ok:
		return Result.failure("模块系统 V2：配置 EmployeeRegistry 失败: %s" % emp_reg.error)
	var mk_reg := MarketingRegistryClass.configure_from_catalog(engine.content_catalog_v2, engine.get_catalog_registry_bundle())
	if not mk_reg.ok:
		return Result.failure("模块系统 V2：配置 MarketingRegistry 失败: %s" % mk_reg.error)
	var ms_reg := MilestoneRegistryClass.configure_from_catalog(engine.content_catalog_v2, engine.get_catalog_registry_bundle())
	if not ms_reg.ok:
		return Result.failure("模块系统 V2：配置 MilestoneRegistry 失败: %s" % ms_reg.error)
	var tile_reg := TileRegistryClass.configure_from_catalog(engine.content_catalog_v2, engine.get_catalog_registry_bundle())
	if not tile_reg.ok:
		return Result.failure("模块系统 V2：配置 TileRegistry 失败: %s" % tile_reg.error)
	var piece_reg := PieceRegistryClass.configure_from_catalog(engine.content_catalog_v2, engine.get_catalog_registry_bundle())
	if not piece_reg.ok:
		return Result.failure("模块系统 V2：配置 PieceRegistry 失败: %s" % piece_reg.error)

	if engine.has_method("activate_registry_bundles"):
		engine.activate_registry_bundles()
	PerfTraceClass.end_span(span_catalog_registries)
	PerfTraceClass.end_span(span_total)
	return Result.success().with_warnings(ruleset_read.warnings)

static func validate_starting_inventory_products(cfg) -> Result:
	return ValidationsClass.validate_starting_inventory_products(cfg)
