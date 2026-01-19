# 里程碑注册表（Strict Mode）
# 说明：
# - V2：里程碑定义来自启用模块集合构建的 ContentCatalog（不再从 data/ 目录懒加载）
# - Registry 仅作为“当前对局内容”的便捷查询层；在 GameEngine.initialize 装配阶段配置
class_name MilestoneRegistry
extends RefCounted

const MilestoneDefClass = preload("res://core/data/milestone_def.gd")
const CatalogRegistryHelpersClass = preload("res://core/utils/catalog_registry_helpers.gd")

static var _defs: Dictionary = {}  # id -> MilestoneDef
static var _loaded: bool = false

static func _ensure_loaded() -> void:
	assert(_loaded, "MilestoneRegistry 未初始化：请通过模块系统 V2 装配 ContentCatalog")

static func is_loaded() -> bool:
	return _loaded

static func configure_from_catalog(catalog) -> Result:
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

	_defs = out_read.value
	_loaded = true
	return Result.success(_defs.size())

static func get_def(milestone_id: String) -> Variant:
	_ensure_loaded()
	return _defs.get(milestone_id, null)

static func has(milestone_id: String) -> bool:
	_ensure_loaded()
	return _defs.has(milestone_id)

static func get_all_ids() -> Array[String]:
	_ensure_loaded()
	var ids: Array[String] = []
	for k in _defs.keys():
		ids.append(str(k))
	ids.sort()
	return ids

static func reset() -> void:
	_defs.clear()
	_loaded = false
