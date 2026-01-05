# 营销板件注册表（Strict Mode）
# 说明：
# - V2：营销板件定义来自启用模块集合构建的 ContentCatalog（不再从 data/ 目录懒加载）
# - Registry 仅作为“当前对局内容”的便捷查询层；在 GameEngine.initialize 装配阶段配置
class_name MarketingRegistry
extends RefCounted

const MarketingDefClass = preload("res://core/data/marketing_def.gd")

static var _defs: Dictionary = {}  # board_number -> MarketingDef
static var _loaded: bool = false

static func _ensure_loaded() -> void:
	assert(_loaded, "MarketingRegistry 未初始化：请通过模块系统 V2 装配 ContentCatalog")

static func is_loaded() -> bool:
	return _loaded

static func configure_from_catalog(catalog) -> Result:
	if catalog == null:
		return Result.failure("MarketingRegistry.configure_from_catalog: catalog 为空")
	if not (catalog.marketing is Dictionary):
		return Result.failure("MarketingRegistry.configure_from_catalog: catalog.marketing 类型错误（期望 Dictionary）")

	var out: Dictionary = {}
	for bn_val in catalog.marketing.keys():
		if not (bn_val is int):
			return Result.failure("MarketingRegistry.configure_from_catalog: marketing key 类型错误（期望 int）")
		var bn: int = int(bn_val)
		if bn <= 0:
			return Result.failure("MarketingRegistry.configure_from_catalog: marketing key 必须 > 0")

		var def_val = catalog.marketing.get(bn, null)
		if def_val == null:
			return Result.failure("MarketingRegistry.configure_from_catalog: marketing[%d] 为空" % bn)
		if not (def_val is MarketingDefClass):
			return Result.failure("MarketingRegistry.configure_from_catalog: marketing[%d] 类型错误（期望 MarketingDef）" % bn)
		var def: MarketingDef = def_val
		if int(def.board_number) != bn:
			return Result.failure("MarketingRegistry.configure_from_catalog: marketing[%d].board_number 不一致: %d" % [bn, def.board_number])

		out[bn] = def

	_defs = out
	_loaded = true
	return Result.success(_defs.size())

static func get_def(board_number: int) -> Variant:
	_ensure_loaded()
	return _defs.get(board_number, null)

static func has(board_number: int) -> bool:
	_ensure_loaded()
	return _defs.has(board_number)

static func get_all_board_numbers() -> Array[int]:
	_ensure_loaded()
	var nums: Array[int] = []
	for k in _defs.keys():
		nums.append(int(k))
	nums.sort()
	return nums

static func get_count() -> int:
	_ensure_loaded()
	return _defs.size()

static func reset() -> void:
	_defs.clear()
	_loaded = false
