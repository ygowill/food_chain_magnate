# 板块注册表（Strict Mode）
# 说明：
# - V2：TileDef 来自启用模块集合构建的 ContentCatalog
# - Registry 仅作为“当前对局内容”的便捷查询层；在 GameEngine.initialize 装配阶段配置
class_name TileRegistry
extends RefCounted

const TileDefClass = preload("res://core/map/tile_def.gd")
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

static func is_loaded() -> bool:
	return bool(_get_bundle().tile_loaded)

static func _ensure_loaded() -> void:
	var bundle = _get_bundle()
	assert(bool(bundle.tile_loaded), "TileRegistry 未初始化：请通过模块系统 V2 装配 ContentCatalog")

static func configure_from_catalog(catalog, bundle = null) -> Result:
	if catalog == null:
		return Result.failure("TileRegistry.configure_from_catalog: catalog 为空")
	if not (catalog.tiles is Dictionary):
		return Result.failure("TileRegistry.configure_from_catalog: catalog.tiles 类型错误（期望 Dictionary）")

	var out_read := CatalogRegistryHelpersClass.build_string_keyed_defs(
		catalog.tiles,
		TileDefClass,
		"TileRegistry.configure_from_catalog",
		"tiles",
		"TileDef"
	)
	if not out_read.ok:
		return out_read

	var target = _resolve_bundle(bundle)
	target.tile_defs = out_read.value
	target.tile_loaded = true
	return Result.success(target.tile_defs.size())

static func get_def(tile_id: String) -> Variant:
	_ensure_loaded()
	return _get_bundle().tile_defs.get(tile_id, null)

static func has(tile_id: String) -> bool:
	_ensure_loaded()
	return _get_bundle().tile_defs.has(tile_id)

static func get_all_ids() -> Array[String]:
	_ensure_loaded()
	var ids: Array[String] = []
	for k in _get_bundle().tile_defs.keys():
		ids.append(str(k))
	ids.sort()
	return ids

static func get_count() -> int:
	_ensure_loaded()
	return _get_bundle().tile_defs.size()

static func reset() -> void:
	var target = _get_bundle()
	target.tile_defs.clear()
	target.tile_loaded = false
