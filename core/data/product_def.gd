# 产品定义
# 解析模块 content/products/*.json 中的产品数据（id/name/tags）。
class_name ProductDef
extends RefCounted

var id: String = ""
var name: String = ""
var tags: Array[String] = []
var starting_inventory: int = 0

static func from_dict(data: Dictionary) -> Result:
	var def = (load("res://core/data/product_def.gd") as Script).new()

	var id_read := _parse_string(data.get("id", null), "ProductDef.id", false)
	if not id_read.ok:
		return id_read
	def.id = id_read.value
	if def.id == "drink":
		return Result.failure("ProductDef.id 不允许为保留字: drink")

	var name_read := _parse_string(data.get("name", null), "ProductDef.name", false)
	if not name_read.ok:
		return name_read
	def.name = name_read.value

	var tags_read := _parse_string_array(data.get("tags", []), "ProductDef.tags", true)
	if not tags_read.ok:
		return tags_read
	def.tags = tags_read.value

	var start_read := _parse_non_negative_int(data.get("starting_inventory", 0), "ProductDef.starting_inventory")
	if not start_read.ok:
		return start_read
	def.starting_inventory = int(start_read.value)

	return Result.success(def)

static func from_json(json_string: String) -> Result:
	var parsed = JSON.parse_string(json_string)
	if parsed == null or not (parsed is Dictionary):
		return Result.failure("ProductDef JSON 解析失败（期望 Dictionary）")
	return from_dict(parsed)

static func load_from_file(path: String) -> Result:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return Result.failure("无法打开产品定义文件: %s" % path)
	var json := file.get_as_text()
	file.close()
	return from_json(json)

func has_tag(tag: String) -> bool:
	return tags.has(tag)

func is_drink() -> bool:
	return has_tag("drink")

func to_dict() -> Dictionary:
	return {
		"id": id,
		"name": name,
		"tags": tags,
		"starting_inventory": starting_inventory,
	}

static func _parse_string(value, path: String, allow_empty: bool) -> Result:
	if not (value is String):
		return Result.failure("%s 类型错误（期望 String）" % path)
	var s: String = value
	if not allow_empty and s.is_empty():
		return Result.failure("%s 不能为空" % path)
	return Result.success(s)

static func _parse_string_array(value, path: String, allow_empty: bool) -> Result:
	if value == null:
		if allow_empty:
			return Result.success([])
		return Result.failure("%s 缺失" % path)
	if not (value is Array):
		return Result.failure("%s 类型错误（期望 Array[String]）" % path)
	var any: Array = value
	var out: Array[String] = []
	for i in range(any.size()):
		var item = any[i]
		var s_read := _parse_string(item, "%s[%d]" % [path, i], false)
		if not s_read.ok:
			return s_read
		out.append(s_read.value)
	if not allow_empty and out.is_empty():
		return Result.failure("%s 不能为空" % path)
	return Result.success(out)

static func _parse_non_negative_int(value, path: String) -> Result:
	if value is int:
		if int(value) < 0:
			return Result.failure("%s 不能为负数: %d" % [path, int(value)])
		return Result.success(int(value))
	if value is float:
		var f: float = float(value)
		if f != floor(f):
			return Result.failure("%s 必须为整数（不允许小数）" % path)
		var i: int = int(f)
		if i < 0:
			return Result.failure("%s 不能为负数: %d" % [path, i])
		return Result.success(i)
	return Result.failure("%s 类型错误（期望 int）" % path)
