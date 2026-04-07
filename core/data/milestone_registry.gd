# 里程碑注册表（Strict Mode）
# 说明：
# - V2：里程碑定义来自启用模块集合构建的 ContentCatalog（不再从 data/ 目录懒加载）
# - Registry 仅作为“当前对局内容”的便捷查询层；在 GameEngine.initialize 装配阶段配置
class_name MilestoneRegistry
extends RefCounted

const MilestoneDefClass = preload("res://core/data/milestone_def.gd")
const CatalogRegistryHelpersClass = preload("res://core/utils/catalog_registry_helpers.gd")
const CatalogRegistryBundleClass = preload("res://core/engine/game_engine/catalog_registry_bundle.gd")

static var _current_bundle = CatalogRegistryBundleClass.new()

static func _get_bundle():
	if _current_bundle == null:
		_current_bundle = CatalogRegistryBundleClass.new()
	return _current_bundle

static func _resolve_bundle(bundle = null):
	if bundle != null:
		return bundle
	return _get_bundle()

static func set_current_bundle(bundle) -> void:
	_current_bundle = bundle if bundle != null else CatalogRegistryBundleClass.new()

static func reset_current_bundle() -> void:
	_current_bundle = null

static func _ensure_loaded() -> void:
	var bundle = _get_bundle()
	assert(bool(bundle.milestone_loaded), "MilestoneRegistry 未初始化：请通过模块系统 V2 装配 ContentCatalog")

static func is_loaded() -> bool:
	return bool(_get_bundle().milestone_loaded)

static func configure_from_catalog(catalog, bundle = null) -> Result:
	if catalog == null:
		return Result.failure("MilestoneRegistry.configure_from_catalog: catalog 为空")
	if not (catalog.milestones is Dictionary):
		return Result.failure("MilestoneRegistry.configure_from_catalog: catalog.milestones 类型错误（期望 Dictionary）")

	var out_read := CatalogRegistryHelpersClass.build_string_keyed_defs(
		catalog.milestones,
		MilestoneDefClass,
		"MilestoneRegistry.configure_from_catalog",
		"milestones",
		"MilestoneDef"
	)
	if not out_read.ok:
		return out_read

	var target = _resolve_bundle(bundle)
	target.milestone_defs = out_read.value
	target.milestone_loaded = true
	return Result.success(target.milestone_defs.size())

static func get_def(milestone_id: String) -> Variant:
	_ensure_loaded()
	return _get_bundle().milestone_defs.get(milestone_id, null)

static func has(milestone_id: String) -> bool:
	_ensure_loaded()
	return _get_bundle().milestone_defs.has(milestone_id)

static func get_all_ids() -> Array[String]:
	_ensure_loaded()
	var ids: Array[String] = []
	for k in _get_bundle().milestone_defs.keys():
		ids.append(str(k))
	ids.sort()
	return ids

static func reset() -> void:
	var target = _get_bundle()
	target.milestone_defs.clear()
	target.milestone_loaded = false
