# 板块注册表（Strict Mode）
# 说明：
# - V2：TileDef 来自启用模块集合构建的 ContentCatalog
# - Registry 仅作为“当前对局内容”的便捷查询层；在 GameEngine.initialize 装配阶段配置
class_name TileRegistry
extends RefCounted

const TileDefClass = preload("res://core/map/tile_def.gd")
const CatalogRegistryHelpersClass = preload("res://core/utils/catalog_registry_helpers.gd")

static var _tiles: Dictionary = {}  # tile_id -> TileDef
static var _loaded: bool = false

static func is_loaded() -> bool:
	return _loaded

static func _ensure_loaded() -> void:
	assert(_loaded, "TileRegistry 未初始化：请通过模块系统 V2 装配 ContentCatalog")

static func configure_from_catalog(catalog) -> Result:
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

	_tiles = out_read.value
	_loaded = true
	return Result.success(_tiles.size())

static func get_def(tile_id: String) -> Variant:
	_ensure_loaded()
	return _tiles.get(tile_id, null)

static func has(tile_id: String) -> bool:
	_ensure_loaded()
	return _tiles.has(tile_id)

static func get_all_ids() -> Array[String]:
	_ensure_loaded()
	var ids: Array[String] = []
	for k in _tiles.keys():
		ids.append(str(k))
	ids.sort()
	return ids

static func get_count() -> int:
	_ensure_loaded()
	return _tiles.size()

static func reset() -> void:
	_tiles.clear()
	_loaded = false
