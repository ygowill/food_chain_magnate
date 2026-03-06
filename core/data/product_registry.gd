# 产品注册表（Strict Mode）
# 说明：
# - V2：产品定义来自启用模块集合构建的 ContentCatalog（不再从 data/ 目录懒加载）
class_name ProductRegistry
extends RefCounted

const ProductDefClass = preload("res://core/data/product_def.gd")
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
	_current_bundle = CatalogRegistryBundleClass.new()

static func _ensure_loaded() -> void:
	var bundle = _get_bundle()
	assert(bool(bundle.product_loaded), "ProductRegistry 未初始化：请通过模块系统 V2 装配 ContentCatalog")

static func is_loaded() -> bool:
	return bool(_get_bundle().product_loaded)

static func configure_from_catalog(catalog, bundle = null) -> Result:
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

	var target = _resolve_bundle(bundle)
	target.product_defs = out_read.value
	target.product_loaded = true
	return Result.success(target.product_defs.size())

static func get_def(product_id: String) -> Variant:
	_ensure_loaded()
	return _get_bundle().product_defs.get(product_id, null)

static func has(product_id: String) -> bool:
	_ensure_loaded()
	return _get_bundle().product_defs.has(product_id)

static func is_drink(product_id: String) -> bool:
	_ensure_loaded()
	var def_val = _get_bundle().product_defs.get(product_id, null)
	if def_val == null:
		return false
	var def = def_val
	return def.is_drink()

static func has_any_with_tag(tag: String) -> bool:
	_ensure_loaded()
	if tag.is_empty():
		return false
	for pid in _get_bundle().product_defs.keys():
		var def_val = _get_bundle().product_defs.get(pid, null)
		if def_val is ProductDefClass:
			if def_val.has_tag(tag):
				return true
	return false

static func get_all_ids() -> Array[String]:
	_ensure_loaded()
	var ids: Array[String] = []
	for k in _get_bundle().product_defs.keys():
		if k is String:
			ids.append(str(k))
	ids.sort()
	return ids

static func get_count() -> int:
	_ensure_loaded()
	return _get_bundle().product_defs.size()

static func reset() -> void:
	var target = _get_bundle()
	target.product_defs.clear()
	target.product_loaded = false
