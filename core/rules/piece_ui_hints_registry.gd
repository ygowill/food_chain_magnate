# Piece UI hints registry (modules-v2 aware)
# Purpose: keep "module piece classification / rendering hints" out of core UI code.
class_name PieceUiHintsRegistry
extends RefCounted

static var _hints_by_piece_id: Dictionary = {} # piece_id -> {kind?, road_overlay?}
static var _priority_by_piece_id: Dictionary = {} # piece_id -> int
static var _loaded: bool = false

static func reset() -> void:
	_hints_by_piece_id = {}
	_priority_by_piece_id = {}
	_loaded = true

static func is_loaded() -> bool:
	return _loaded

static func configure_from_module_ui_metadata(module_ui_metadata) -> Result:
	if not _loaded:
		return Result.failure("PieceUiHintsRegistry 未初始化：请先调用 reset()")
	if module_ui_metadata == null:
		return Result.failure("PieceUiHintsRegistry.configure_from_module_ui_metadata: module_ui_metadata 为空")
	if not (module_ui_metadata is Object):
		return Result.failure("PieceUiHintsRegistry.configure_from_module_ui_metadata: module_ui_metadata 类型错误（期望 Object）")
	if not module_ui_metadata.has_method("get_piece_ui_hint_entries"):
		return Result.failure("PieceUiHintsRegistry.configure_from_module_ui_metadata: module_ui_metadata 缺少 get_piece_ui_hint_entries")

	var list_val = module_ui_metadata.get_piece_ui_hint_entries()
	if not (list_val is Array):
		return Result.failure("PieceUiHintsRegistry.configure_from_module_ui_metadata: piece_ui_hint_entries 缺失或类型错误（期望 Array）")

	return _configure_from_entries(list_val)

static func get_hints(piece_id: String) -> Dictionary:
	if not _loaded:
		return {}
	var pid := str(piece_id).strip_edges()
	if pid.is_empty():
		return {}
	var val = _hints_by_piece_id.get(pid, null)
	return val if (val is Dictionary) else {}

static func get_kind(piece_id: String) -> String:
	var hints := get_hints(piece_id)
	var kind_val = hints.get("kind", "")
	return str(kind_val).strip_edges() if (kind_val is String) else ""

static func get_road_overlay(piece_id: String) -> Dictionary:
	var hints := get_hints(piece_id)
	var ov_val = hints.get("road_overlay", null)
	return ov_val if (ov_val is Dictionary) else {}

static func _configure_from_entries(list_val) -> Result:
	if not (list_val is Array):
		return Result.failure("PieceUiHintsRegistry: piece_ui_hints 缺失或类型错误（期望 Array）")

	_hints_by_piece_id.clear()
	_priority_by_piece_id.clear()

	var list: Array = list_val
	for i in range(list.size()):
		var item_val = list[i]
		if not (item_val is Dictionary):
			return Result.failure("PieceUiHintsRegistry: piece_ui_hints[%d] 类型错误（期望 Dictionary）" % i)
		var item: Dictionary = item_val

		var piece_id_val = item.get("piece_id", null)
		if not (piece_id_val is String):
			return Result.failure("PieceUiHintsRegistry: piece_ui_hints[%d].piece_id 类型错误（期望 String）" % i)
		var piece_id: String = str(piece_id_val).strip_edges()
		if piece_id.is_empty():
			return Result.failure("PieceUiHintsRegistry: piece_ui_hints[%d].piece_id 不能为空" % i)

		var hints_val = item.get("hints", null)
		if not (hints_val is Dictionary):
			return Result.failure("PieceUiHintsRegistry: piece_ui_hints[%d].hints 类型错误（期望 Dictionary）: %s" % [i, piece_id])
		var hints: Dictionary = hints_val

		var prio: int = int(item.get("priority", 100))

		var prev_pri: int = int(_priority_by_piece_id.get(piece_id, -2147483648))
		if not _priority_by_piece_id.has(piece_id) or prio >= prev_pri:
			_priority_by_piece_id[piece_id] = prio
			_hints_by_piece_id[piece_id] = hints

	return Result.success(_hints_by_piece_id.size())
