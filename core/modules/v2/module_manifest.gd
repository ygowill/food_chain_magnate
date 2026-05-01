# 模块系统 V2：模块包 manifest（module.json）
class_name ModuleManifest
extends RefCounted

const SUPPORTED_SCHEMA_VERSION := 1
const DataParseHelpersClass = preload("res://core/data/parse_helpers.gd")

var schema_version: int = SUPPORTED_SCHEMA_VERSION
var id: String = ""
var name: String = ""
var version: String = ""
var priority: int = 100
var dependencies: Array[String] = []
var conflicts: Array[String] = []
var entry_script: String = ""
var provides: Dictionary = {}  # 扩展字段（例如 effects/settlements 等）

static func from_json(json_string: String) -> Result:
	var parsed = JSON.parse_string(json_string)
	if parsed == null or not (parsed is Dictionary):
		return Result.failure("ModuleManifest JSON 解析失败（期望 Dictionary）")
	return from_dict(parsed)

static func load_from_file(path: String) -> Result:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return Result.failure("无法打开 module.json: %s" % path)
	var json := file.get_as_text()
	file.close()
	return from_json(json)

static func from_dict(data: Dictionary) -> Result:
	var out := ModuleManifest.new()

	var schema_read := DataParseHelpersClass.parse_int(data.get("schema_version", null), "schema_version")
	if not schema_read.ok:
		return schema_read
	out.schema_version = int(schema_read.value)
	if out.schema_version != SUPPORTED_SCHEMA_VERSION:
		return Result.failure("不支持的 module.json.schema_version: %d (期望: %d)" % [out.schema_version, SUPPORTED_SCHEMA_VERSION])

	var id_read := DataParseHelpersClass.parse_string(data.get("id", null), "id", false)
	if not id_read.ok:
		return id_read
	out.id = id_read.value

	var name_val = data.get("name", null)
	if name_val == null:
		out.name = out.id
	else:
		var name_read := DataParseHelpersClass.parse_string(name_val, "name", true)
		if not name_read.ok:
			return name_read
		out.name = name_read.value
		if out.name.is_empty():
			out.name = out.id

	var version_read := DataParseHelpersClass.parse_string(data.get("version", null), "version", false)
	if not version_read.ok:
		return version_read
	out.version = version_read.value

	var priority_val = data.get("priority", 100)
	var priority_read = Result.success(0) if priority_val == null else DataParseHelpersClass.parse_int(priority_val, "priority")
	if not priority_read.ok:
		return priority_read
	out.priority = int(priority_read.value)

	var deps_val_read := _require_field(data, "dependencies")
	if not deps_val_read.ok:
		return deps_val_read
	var deps_val = deps_val_read.value
	var deps_read := DataParseHelpersClass.parse_string_array(deps_val, "dependencies", true)
	if not deps_read.ok:
		return deps_read
	out.dependencies = deps_read.value

	var conflicts_val_read := _require_field(data, "conflicts")
	if not conflicts_val_read.ok:
		return conflicts_val_read
	var conflicts_val = conflicts_val_read.value
	var conflicts_read := DataParseHelpersClass.parse_string_array(conflicts_val, "conflicts", true)
	if not conflicts_read.ok:
		return conflicts_read
	out.conflicts = conflicts_read.value

	var entry_val_read := _require_field(data, "entry_script")
	if not entry_val_read.ok:
		return entry_val_read
	var entry_val = entry_val_read.value
	var entry_read := DataParseHelpersClass.parse_string(entry_val, "entry_script", true)
	if not entry_read.ok:
		return entry_read
	out.entry_script = entry_read.value

	var provides_val_read := _require_field(data, "provides")
	if not provides_val_read.ok:
		return provides_val_read
	var provides_val = provides_val_read.value
	if not (provides_val is Dictionary):
		return Result.failure("provides 类型错误（期望 Dictionary）")
	out.provides = provides_val.duplicate(true)

	return Result.success(out)

static func _require_field(data: Dictionary, field_name: String) -> Result:
	if not data.has(field_name):
		return Result.failure("module.json.%s 缺失" % field_name)
	return Result.success(data.get(field_name, null))

func to_dict() -> Dictionary:
	return {
		"schema_version": schema_version,
		"id": id,
		"name": name,
		"version": version,
		"priority": priority,
		"dependencies": dependencies,
		"conflicts": conflicts,
		"entry_script": entry_script,
		"provides": provides,
	}
