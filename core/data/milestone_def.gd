# 里程碑定义
# 解析模块 content/milestones/*.json 中的里程碑数据（id/trigger/effects/expires_at）。
class_name MilestoneDef
extends RefCounted

const MilestoneDefParserClass = preload("res://core/data/milestone_def_parser.gd")
const TriggerFilterClass = preload("res://core/data/milestone_trigger_filter.gd")

var id: String = ""
var name: String = ""
var trigger_event: String = ""
var trigger_filter: Dictionary = {}
var effects: Array = []
var effect_ids: Array[String] = []
var exclusive_type: String = ""
var expires_at = null  # int | null
var pool_enabled: bool = true
var pool_count: int = 1

static func from_dict(data: Dictionary) -> Result:
	var fields_read := MilestoneDefParserClass.parse_fields_from_dict(data)
	if not fields_read.ok:
		return fields_read
	var f: Dictionary = fields_read.value

	var def := MilestoneDef.new()
	def.id = str(f.get("id", ""))
	def.name = str(f.get("name", ""))
	def.trigger_event = str(f.get("trigger_event", ""))
	def.trigger_filter = f.get("trigger_filter", {})
	def.effects = f.get("effects", [])
	def.effect_ids = f.get("effect_ids", [])
	def.exclusive_type = str(f.get("exclusive_type", ""))
	def.expires_at = f.get("expires_at", null)
	def.pool_enabled = bool(f.get("pool_enabled", true))
	def.pool_count = int(f.get("pool_count", 1))

	return Result.success(def)

static func from_json(json_string: String) -> Result:
	var parsed = JSON.parse_string(json_string)
	if parsed == null or not (parsed is Dictionary):
		return Result.failure("MilestoneDef JSON 解析失败（期望 Dictionary）")
	return from_dict(parsed)

static func load_from_file(path: String) -> Result:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return Result.failure("无法打开里程碑定义文件: %s" % path)
	var json := file.get_as_text()
	file.close()
	return from_json(json)

func matches(event_name: String, context: Dictionary) -> bool:
	if trigger_event.is_empty() or trigger_event != event_name:
		return false
	return TriggerFilterClass.matches_filter(trigger_filter, context)

func to_dict() -> Dictionary:
	var pool: Dictionary = {"enabled": pool_enabled}
	if pool_count > 1:
		pool["count"] = pool_count
	return {
		"id": id,
		"name": name,
		"trigger": {
			"event": trigger_event,
			"filter": trigger_filter
		},
		"effects": effects,
		"effect_ids": effect_ids,
		"exclusive_type": exclusive_type,
		"expires_at": expires_at,
		"pool": pool
	}
