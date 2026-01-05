# 模块系统 V2：模块包 manifest（module.json）
class_name ModuleManifest
extends RefCounted

const SUPPORTED_SCHEMA_VERSION := 1

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
	var script = load("res://core/modules/v2/module_manifest.gd")
	if script == null:
		return Result.failure("内部错误：无法加载 module_manifest.gd")
	var out = script.new()

	var schema_read := _parse_int_required(data.get("schema_version", null), "schema_version")
	if not schema_read.ok:
		return schema_read
	out.schema_version = int(schema_read.value)
	if out.schema_version != SUPPORTED_SCHEMA_VERSION:
		return Result.failure("不支持的 module.json.schema_version: %d (期望: %d)" % [out.schema_version, SUPPORTED_SCHEMA_VERSION])

	var id_read := _parse_string_required(data.get("id", null), "id")
	if not id_read.ok:
		return id_read
	out.id = id_read.value

	var name_val = data.get("name", null)
	if name_val == null:
		out.name = out.id
	else:
		var name_read := _parse_string_allow_empty(name_val, "name")
		if not name_read.ok:
			return name_read
		out.name = name_read.value
		if out.name.is_empty():
			out.name = out.id

	var version_read := _parse_string_required(data.get("version", null), "version")
	if not version_read.ok:
		return version_read
	out.version = version_read.value

	var priority_val = data.get("priority", 100)
	var priority_read := _parse_int_optional(priority_val, "priority")
	if not priority_read.ok:
		return priority_read
	out.priority = int(priority_read.value)

	var deps_read := _parse_string_array_optional(data.get("dependencies", []), "dependencies")
	if not deps_read.ok:
		return deps_read
	out.dependencies = deps_read.value

	var conflicts_read := _parse_string_array_optional(data.get("conflicts", []), "conflicts")
	if not conflicts_read.ok:
		return conflicts_read
	out.conflicts = conflicts_read.value

	var entry_val = data.get("entry_script", "")
	var entry_read := _parse_string_allow_empty(entry_val, "entry_script")
	if not entry_read.ok:
		return entry_read
	out.entry_script = entry_read.value

	var provides_val = data.get("provides", {})
	if provides_val == null:
		out.provides = {}
	elif not (provides_val is Dictionary):
		return Result.failure("provides 类型错误（期望 Dictionary）")
	else:
		out.provides = provides_val.duplicate(true)

	return Result.success(out)

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

# === 严格解析辅助（允许 JSON 数字以整值 float 表示）===

static func _parse_string_required(value, path: String) -> Result:
	if not (value is String):
		return Result.failure("%s 类型错误（期望 String）" % path)
	var s: String = value
	if s.is_empty():
		return Result.failure("%s 不能为空" % path)
	return Result.success(s)

static func _parse_string_allow_empty(value, path: String) -> Result:
	if not (value is String):
		return Result.failure("%s 类型错误（期望 String）" % path)
	return Result.success(str(value))

static func _parse_int_required(value, path: String) -> Result:
	if value is int:
		return Result.success(int(value))
	if value is float:
		var f: float = float(value)
		if f != floor(f):
			return Result.failure("%s 必须为整数，实际: %s" % [path, str(value)])
		return Result.success(int(f))
	return Result.failure("%s 类型错误（期望整数）" % path)

static func _parse_int_optional(value, path: String) -> Result:
	if value == null:
		return Result.success(0)
	return _parse_int_required(value, path)

static func _parse_string_array_optional(value, path: String) -> Result:
	if value == null:
		return Result.success([])
	if not (value is Array):
		return Result.failure("%s 类型错误（期望 Array[String]）" % path)
	var any: Array = value
	var out: Array[String] = []
	for i in range(any.size()):
		var item = any[i]
		if not (item is String):
			return Result.failure("%s[%d] 类型错误（期望 String）" % [path, i])
		var s: String = str(item)
		if s.is_empty():
			return Result.failure("%s[%d] 不能为空" % [path, i])
		out.append(s)
	return Result.success(out)
