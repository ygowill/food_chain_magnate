# 里程碑定义
# 解析模块 content/milestones/*.json 中的里程碑数据（id/trigger/effects/expires_at）。
class_name MilestoneDef
extends RefCounted

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
	var def := MilestoneDef.new()

	var id_read := _parse_string(data.get("id", null), "MilestoneDef.id", false)
	if not id_read.ok:
		return id_read
	def.id = id_read.value

	var name_read := _parse_string(data.get("name", null), "MilestoneDef.name", false)
	if not name_read.ok:
		return name_read
	def.name = name_read.value

	var trigger_val = data.get("trigger", null)
	if not (trigger_val is Dictionary):
		return Result.failure("MilestoneDef.trigger 缺失或类型错误（期望 Dictionary）")
	var trigger: Dictionary = trigger_val

	var event_read := _parse_string(trigger.get("event", null), "MilestoneDef.trigger.event", false)
	if not event_read.ok:
		return event_read
	def.trigger_event = event_read.value

	var filter_val = trigger.get("filter", {})
	if not (filter_val is Dictionary):
		return Result.failure("MilestoneDef.trigger.filter 类型错误（期望 Dictionary）")
	def.trigger_filter = filter_val

	var effects_val = data.get("effects", null)
	if not (effects_val is Array):
		return Result.failure("MilestoneDef.effects 缺失或类型错误（期望 Array）")
	var e: Array = effects_val
	if e.is_empty():
		return Result.failure("MilestoneDef.effects 不能为空")
	for i in range(e.size()):
		var item = e[i]
		if not (item is Dictionary):
			return Result.failure("MilestoneDef.effects[%d] 类型错误（期望 Dictionary）" % i)
		var effect: Dictionary = item
		var type_read := _parse_string(effect.get("type", null), "MilestoneDef.effects[%d].type" % i, false)
		if not type_read.ok:
			return type_read
	def.effects = e

	var exclusive_read := _parse_string(data.get("exclusive_type", null), "MilestoneDef.exclusive_type", false)
	if not exclusive_read.ok:
		return exclusive_read
	def.exclusive_type = exclusive_read.value

	var exp_val = data.get("expires_at", null)
	if exp_val == null:
		def.expires_at = null
	else:
		var exp_read := _parse_non_negative_int(exp_val, "MilestoneDef.expires_at")
		if not exp_read.ok:
			return exp_read
		def.expires_at = int(exp_read.value)

	var pool_val = data.get("pool", null)
	if not (pool_val is Dictionary):
		return Result.failure("MilestoneDef.pool 缺失或类型错误（期望 Dictionary）")
	var pool: Dictionary = pool_val
	if not pool.has("enabled"):
		return Result.failure("MilestoneDef.pool 缺少 enabled")
	var enabled_val = pool.get("enabled", null)
	if not (enabled_val is bool):
		return Result.failure("MilestoneDef.pool.enabled 类型错误（期望 bool）")
	def.pool_enabled = bool(enabled_val)

	# pool.count（可选）：同一里程碑在 supply 中的拷贝数（用于“每人一张”类供给）
	def.pool_count = 1
	if pool.has("count"):
		var count_val = pool.get("count", null)
		var count_read := _parse_non_negative_int(count_val, "MilestoneDef.pool.count")
		if not count_read.ok:
			return count_read
		def.pool_count = int(count_read.value)
		if def.pool_count <= 0:
			return Result.failure("MilestoneDef.pool.count 必须 > 0，实际: %d" % def.pool_count)

	# effect_ids（可选）：用于 EffectRegistry（M5）
	if data.has("effect_ids"):
		var effect_ids_read := _parse_string_array(data.get("effect_ids", null), "MilestoneDef.effect_ids", true)
		if not effect_ids_read.ok:
			return effect_ids_read
		def.effect_ids = effect_ids_read.value
		for i in range(def.effect_ids.size()):
			var eid: String = def.effect_ids[i]
			var colon_idx := eid.find(":")
			if colon_idx <= 0 or colon_idx >= eid.length() - 1:
				return Result.failure("MilestoneDef.effect_ids[%d] 必须为 module_id:...，实际: %s" % [i, eid])
	else:
		def.effect_ids = []

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

# === 严格解析辅助 ===

static func _parse_string(value, path: String, allow_empty: bool) -> Result:
	if not (value is String):
		return Result.failure("%s 类型错误（期望 String）" % path)
	var s: String = value
	if not allow_empty and s.is_empty():
		return Result.failure("%s 不能为空" % path)
	return Result.success(s)

static func _parse_int(value, path: String) -> Result:
	if value is int:
		return Result.success(int(value))
	if value is float:
		var f: float = float(value)
		if f != floor(f):
			return Result.failure("%s 必须为整数，实际: %s" % [path, str(value)])
		return Result.success(int(f))
	return Result.failure("%s 类型错误（期望整数）" % path)

static func _parse_non_negative_int(value, path: String) -> Result:
	var r := _parse_int(value, path)
	if not r.ok:
		return r
	if int(r.value) < 0:
		return Result.failure("%s 必须 >= 0，实际: %d" % [path, int(r.value)])
	return r

static func _parse_string_array(value, path: String, allow_empty: bool) -> Result:
	if not (value is Array):
		return Result.failure("%s 类型错误（期望 Array[String]）" % path)
	var out: Array[String] = []
	for i in range(value.size()):
		var item = value[i]
		var s_read := _parse_string(item, "%s[%d]" % [path, i], false)
		if not s_read.ok:
			return s_read
		out.append(s_read.value)
	if not allow_empty and out.is_empty():
		return Result.failure("%s 不能为空" % path)
	return Result.success(out)

func matches(event_name: String, context: Dictionary) -> bool:
	if trigger_event.is_empty() or trigger_event != event_name:
		return false
	if trigger_filter.is_empty():
		return true

	for k in trigger_filter.keys():
		var expected = trigger_filter.get(k, null)
		var actual = context.get(k, null)
		if expected is Dictionary:
			var expected_dict: Dictionary = expected
			# 支持数值比较：{"paid": {"gte": 20}}
			if expected_dict.has("gte"):
				var limit_val = expected_dict.get("gte", null)
				if not ((limit_val is int or limit_val is float) and (actual is int or actual is float)):
					return false
				if float(actual) < float(limit_val):
					return false
				continue
			if expected_dict.has("gt"):
				var limit_val = expected_dict.get("gt", null)
				if not ((limit_val is int or limit_val is float) and (actual is int or actual is float)):
					return false
				if float(actual) <= float(limit_val):
					return false
				continue
			if expected_dict.has("lte"):
				var limit_val = expected_dict.get("lte", null)
				if not ((limit_val is int or limit_val is float) and (actual is int or actual is float)):
					return false
				if float(actual) > float(limit_val):
					return false
				continue
			if expected_dict.has("lt"):
				var limit_val = expected_dict.get("lt", null)
				if not ((limit_val is int or limit_val is float) and (actual is int or actual is float)):
					return false
				if float(actual) >= float(limit_val):
					return false
				continue
			if expected_dict.has("eq"):
				var eq_val = expected_dict.get("eq", null)
				if typeof(actual) != typeof(eq_val):
					return false
				if actual != eq_val:
					return false
				continue
			if expected_dict.has("in"):
				var in_val = expected_dict.get("in", null)
				if not (in_val is Array):
					return false
				var arr: Array = in_val
				if arr.find(actual) == -1 and arr.find(str(actual)) == -1:
					return false
				continue
			# 未知比较器：视为不匹配（Fail Close）
			return false
		match typeof(expected):
			TYPE_INT, TYPE_FLOAT:
				if actual == null:
					return false
				if int(actual) != int(expected):
					return false
			TYPE_BOOL:
				if actual == null:
					return false
				if bool(actual) != bool(expected):
					return false
			_:
				if str(actual) != str(expected):
					return false

	return true

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
