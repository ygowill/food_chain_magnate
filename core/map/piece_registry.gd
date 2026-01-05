# 建筑件注册表（Strict Mode）
# 说明：
# - V2：PieceDef 来自启用模块集合构建的 ContentCatalog
# - Registry 仅作为“当前对局内容”的便捷查询层；在 GameEngine.initialize 装配阶段配置
class_name PieceRegistry
extends RefCounted

const PieceDefClass = preload("res://core/map/piece_def.gd")

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

	var out: Dictionary = {}
	for piece_id_val in catalog.pieces.keys():
		if not (piece_id_val is String):
			return Result.failure("PieceRegistry.configure_from_catalog: pieces key 类型错误（期望 String）")
		var piece_id: String = str(piece_id_val)
		if piece_id.is_empty():
			return Result.failure("PieceRegistry.configure_from_catalog: pieces key 不能为空")
		var def_val = catalog.pieces.get(piece_id, null)
		if def_val == null:
			return Result.failure("PieceRegistry.configure_from_catalog: pieces[%s] 为空" % piece_id)
		if not (def_val is PieceDefClass):
			return Result.failure("PieceRegistry.configure_from_catalog: pieces[%s] 类型错误（期望 PieceDef）" % piece_id)
		var def: PieceDef = def_val
		if def.id != piece_id:
			return Result.failure("PieceRegistry.configure_from_catalog: pieces[%s].id 不一致: %s" % [piece_id, def.id])
		out[piece_id] = def

	_pieces = out
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

