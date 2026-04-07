# 员工注册表（Strict Mode）
# 说明：
# - V2：员工定义来自启用模块集合构建的 ContentCatalog（不再从 data/ 目录懒加载）
# - Registry 仅作为“当前对局内容”的便捷查询层；在 GameEngine.initialize 装配阶段配置
class_name EmployeeRegistry
extends RefCounted

const EmployeeDefClass = preload("res://core/data/employee_def.gd")
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
	return bool(_get_bundle().employee_loaded)

static func _ensure_loaded() -> void:
	var bundle = _get_bundle()
	assert(bool(bundle.employee_loaded), "EmployeeRegistry 未初始化：请通过模块系统 V2 装配 ContentCatalog")

static func configure_from_catalog(catalog, bundle = null) -> Result:
	if catalog == null:
		return Result.failure("EmployeeRegistry.configure_from_catalog: catalog 为空")
	if not (catalog.employees is Dictionary):
		return Result.failure("EmployeeRegistry.configure_from_catalog: catalog.employees 类型错误（期望 Dictionary）")

	var out_read := CatalogRegistryHelpersClass.build_string_keyed_defs(
		catalog.employees,
		EmployeeDefClass,
		"EmployeeRegistry.configure_from_catalog",
		"employees",
		"EmployeeDef"
	)
	if not out_read.ok:
		return out_read

	var target = _resolve_bundle(bundle)
	target.employee_defs = out_read.value
	target.employee_loaded = true
	return Result.success(target.employee_defs.size())

static func get_def(employee_id: String) -> Variant:
	_ensure_loaded()
	return _get_bundle().employee_defs.get(employee_id, null)

static func check_requires_salary(employee_id: String) -> bool:
	var emp = get_def(employee_id)
	assert(emp != null, "未知员工: %s" % employee_id)
	return emp.salary

static func has(employee_id: String) -> bool:
	_ensure_loaded()
	return _get_bundle().employee_defs.has(employee_id)

static func get_all_ids() -> Array[String]:
	_ensure_loaded()
	var ids: Array[String] = []
	for id in _get_bundle().employee_defs.keys():
		ids.append(id)
	ids.sort()
	return ids

static func get_count() -> int:
	_ensure_loaded()
	return _get_bundle().employee_defs.size()

static func reset() -> void:
	var target = _get_bundle()
	target.employee_defs.clear()
	target.employee_loaded = false

static func dump() -> String:
	_ensure_loaded()
	var output := "=== EmployeeRegistry ===\n"
	output += "Total employees: %d\n" % _get_bundle().employee_defs.size()
	output += "\nEmployees:\n"

	var ids := get_all_ids()
	for id in ids:
		var emp = _get_bundle().employee_defs[id]
		output += "  - %s: %s (salary: %s)\n" % [id, emp.name, emp.salary]

	return output
