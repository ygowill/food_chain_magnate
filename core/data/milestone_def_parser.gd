# MilestoneDef Dictionary 解析（从 milestone_def.gd 抽离）
# 目的：缩短 MilestoneDef 单文件体积，将“严格解析/校验”职责集中到解析器中。
extends RefCounted

const DataParseHelpersClass = preload("res://core/data/parse_helpers.gd")

static func parse_fields_from_dict(data: Dictionary) -> Result:
	if not (data is Dictionary):
		return Result.failure("MilestoneDef.from_dict: data 类型错误（期望 Dictionary）")

	var id_read := DataParseHelpersClass.parse_string(data.get("id", null), "MilestoneDef.id", false)
	if not id_read.ok:
		return id_read

	var name_read := DataParseHelpersClass.parse_string(data.get("name", null), "MilestoneDef.name", false)
	if not name_read.ok:
		return name_read

	var trigger_val = data.get("trigger", null)
	if not (trigger_val is Dictionary):
		return Result.failure("MilestoneDef.trigger 缺失或类型错误（期望 Dictionary）")
	var trigger: Dictionary = trigger_val

	var event_read := DataParseHelpersClass.parse_string(trigger.get("event", null), "MilestoneDef.trigger.event", false)
	if not event_read.ok:
		return event_read

	var filter_val = trigger.get("filter", {})
	if not (filter_val is Dictionary):
		return Result.failure("MilestoneDef.trigger.filter 类型错误（期望 Dictionary）")
	var trigger_filter: Dictionary = filter_val

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
		var type_read := DataParseHelpersClass.parse_string(effect.get("type", null), "MilestoneDef.effects[%d].type" % i, false)
		if not type_read.ok:
			return type_read

	var exclusive_read := DataParseHelpersClass.parse_string(data.get("exclusive_type", null), "MilestoneDef.exclusive_type", false)
	if not exclusive_read.ok:
		return exclusive_read

	var exp_val = data.get("expires_at", null)
	var expires_at = null
	if exp_val != null:
		var exp_read := DataParseHelpersClass.parse_non_negative_int(exp_val, "MilestoneDef.expires_at")
		if not exp_read.ok:
			return exp_read
		expires_at = int(exp_read.value)

	var pool_val = data.get("pool", null)
	if not (pool_val is Dictionary):
		return Result.failure("MilestoneDef.pool 缺失或类型错误（期望 Dictionary）")
	var pool: Dictionary = pool_val
	if not pool.has("enabled"):
		return Result.failure("MilestoneDef.pool 缺少 enabled")
	var enabled_val = pool.get("enabled", null)
	if not (enabled_val is bool):
		return Result.failure("MilestoneDef.pool.enabled 类型错误（期望 bool）")

	# pool.count（可选）：同一里程碑在 supply 中的拷贝数（用于“每人一张”类供给）
	var pool_count := 1
	if pool.has("count"):
		var count_val = pool.get("count", null)
		var count_read := DataParseHelpersClass.parse_non_negative_int(count_val, "MilestoneDef.pool.count")
		if not count_read.ok:
			return count_read
		pool_count = int(count_read.value)
		if pool_count <= 0:
			return Result.failure("MilestoneDef.pool.count 必须 > 0，实际: %d" % pool_count)

	# effect_ids（可选）：用于 EffectRegistry（M5）
	var effect_ids: Array[String] = []
	if data.has("effect_ids"):
		var effect_ids_read := DataParseHelpersClass.parse_string_array(data.get("effect_ids", null), "MilestoneDef.effect_ids", true)
		if not effect_ids_read.ok:
			return effect_ids_read
		effect_ids = effect_ids_read.value
		for i in range(effect_ids.size()):
			var eid: String = effect_ids[i]
			var colon_idx := eid.find(":")
			if colon_idx <= 0 or colon_idx >= eid.length() - 1:
				return Result.failure("MilestoneDef.effect_ids[%d] 必须为 module_id:...，实际: %s" % [i, eid])

	return Result.success({
		"id": id_read.value,
		"name": name_read.value,
		"trigger_event": event_read.value,
		"trigger_filter": trigger_filter,
		"effects": e,
		"effect_ids": effect_ids,
		"exclusive_type": exclusive_read.value,
		"expires_at": expires_at,
		"pool_enabled": bool(enabled_val),
		"pool_count": pool_count,
	})

