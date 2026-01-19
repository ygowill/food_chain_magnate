# 建筑件注册表（Strict Mode）
# 说明：
# - V2：PieceDef 来自启用模块集合构建的 ContentCatalog
# - Registry 仅作为“当前对局内容”的便捷查询层；在 GameEngine.initialize 装配阶段配置
class_name PieceRegistry
extends RefCounted

const PieceDefClass = preload("res://core/map/piece_def.gd")
const CatalogRegistryHelpersClass = preload("res://core/utils/catalog_registry_helpers.gd")

static var _pieces: Dictionary = {}  # piece_id -> PieceDef
static var _loaded: bool = false

static func is_loaded() -> bool:
	return _loaded

static func _ensure_loaded() -> void:
	assert(_loaded, "PieceRegistry 未初始化：请通过模块系统 V2 装配 ContentCatalog")

static func configure_from_catalog(catalog) -> Result:
	if catalog == null:
		return Result.failure("PieceRegistry.configure_from_catalog: catalog 为空")
	if not (catalog.pieces is Dictionary):
		return Result.failure("PieceRegistry.configure_from_catalog: catalog.pieces 类型错误（期望 Dictionary）")

	var out_read := CatalogRegistryHelpersClass.build_string_keyed_defs(
		catalog.pieces,
		PieceDefClass,
		"PieceRegistry.configure_from_catalog",
		"pieces",
		"PieceDef"
	)
	if not out_read.ok:
		return out_read

	_pieces = out_read.value
	_loaded = true
	return Result.success(_pieces.size())

static func get_def(piece_id: String) -> Variant:
	_ensure_loaded()
	return _pieces.get(piece_id, null)

static func has(piece_id: String) -> bool:
	_ensure_loaded()
	return _pieces.has(piece_id)

static func get_all_ids() -> Array[String]:
	_ensure_loaded()
	var ids: Array[String] = []
	for k in _pieces.keys():
		ids.append(str(k))
	ids.sort()
	return ids

static func get_all_defs() -> Dictionary:
	_ensure_loaded()
	return _pieces.duplicate()

static func get_count() -> int:
	_ensure_loaded()
	return _pieces.size()

static func reset() -> void:
	_pieces.clear()
	_loaded = false
