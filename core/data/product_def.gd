# 产品定义
# 解析模块 content/products/*.json 中的产品数据（id/name/tags）。
class_name ProductDef
extends RefCounted

const DataParseHelpersClass = preload("res://core/data/parse_helpers.gd")

var id: String = ""
var name: String = ""
var tags: Array[String] = []
var starting_inventory: int = 0

static func from_dict(data: Dictionary) -> Result:
	var def := ProductDef.new()

	var id_read := DataParseHelpersClass.parse_string(data.get("id", null), "ProductDef.id", false)
	if not id_read.ok:
		return id_read
	def.id = id_read.value
	if def.id == "drink":
		return Result.failure("ProductDef.id 不允许为保留字: drink")

	var name_read := DataParseHelpersClass.parse_string(data.get("name", null), "ProductDef.name", false)
	if not name_read.ok:
		return name_read
	def.name = name_read.value

	var tags_read := DataParseHelpersClass.parse_string_array(data.get("tags", []), "ProductDef.tags", true)
	if not tags_read.ok:
		return tags_read
	def.tags = tags_read.value

	var start_read := DataParseHelpersClass.parse_non_negative_int(data.get("starting_inventory", 0), "ProductDef.starting_inventory")
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
