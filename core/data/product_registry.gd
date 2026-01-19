# 产品注册表（Strict Mode）
# 说明：
# - V2：产品定义来自启用模块集合构建的 ContentCatalog（不再从 data/ 目录懒加载）
class_name ProductRegistry
extends RefCounted

const ProductDefClass = preload("res://core/data/product_def.gd")
const CatalogRegistryHelpersClass = preload("res://core/utils/catalog_registry_helpers.gd")

static var _defs: Dictionary = {}  # product_id -> ProductDef
static var _loaded: bool = false

static func _ensure_loaded() -> void:
	assert(_loaded, "ProductRegistry 未初始化：请通过模块系统 V2 装配 ContentCatalog")

static func is_loaded() -> bool:
	return _loaded

static func configure_from_catalog(catalog) -> Result:
	if catalog == null:
		return Result.failure("ProductRegistry.configure_from_catalog: catalog 为空")
	if not (catalog.products is Dictionary):
		return Result.failure("ProductRegistry.configure_from_catalog: catalog.products 类型错误（期望 Dictionary）")

	var out_read := CatalogRegistryHelpersClass.build_string_keyed_defs(
		catalog.products,
		ProductDefClass,
		"ProductRegistry.configure_from_catalog",
		"products",
		"ProductDef"
	)
	if not out_read.ok:
		return out_read

	_defs = out_read.value
	_loaded = true
	return Result.success(_defs.size())

static func get_def(product_id: String) -> Variant:
	_ensure_loaded()
	return _defs.get(product_id, null)

static func has(product_id: String) -> bool:
	_ensure_loaded()
	return _defs.has(product_id)

static func is_drink(product_id: String) -> bool:
	_ensure_loaded()
	var def_val = _defs.get(product_id, null)
	if def_val == null:
		return false
	var def = def_val
	return def.is_drink()

static func has_any_with_tag(tag: String) -> bool:
	_ensure_loaded()
	if tag.is_empty():
		return false
	for pid in _defs.keys():
		var def_val = _defs.get(pid, null)
		if def_val is ProductDefClass:
			if def_val.has_tag(tag):
				return true
	return false

static func get_all_ids() -> Array[String]:
	_ensure_loaded()
	var ids: Array[String] = []
	for k in _defs.keys():
		if k is String:
			ids.append(str(k))
	ids.sort()
	return ids

static func get_count() -> int:
	_ensure_loaded()
	return _defs.size()

static func reset() -> void:
	_defs.clear()
	_loaded = false
