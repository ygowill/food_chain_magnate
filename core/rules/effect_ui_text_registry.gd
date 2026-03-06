# Effect UI Text Registry (modules-v2 aware)
# Purpose: keep module-specific effect_id / effect_type text out of core UI panels.
class_name EffectUiTextRegistry
extends RefCounted

static var _effect_id_text_by_id: Dictionary = {} # effect_id -> {text, priority, source}
static var _milestone_effect_text_by_type: Dictionary = {} # effect_type -> {text, priority, source}
static var _loaded: bool = false

static func reset() -> void:
	_effect_id_text_by_id = {}
	_milestone_effect_text_by_type = {}
	_loaded = true

static func is_loaded() -> bool:
	return _loaded

static func configure_from_ruleset(ruleset) -> Result:
	if not _loaded:
		return Result.failure("EffectUiTextRegistry 未初始化：请先调用 reset()")
	if ruleset == null:
		return Result.failure("EffectUiTextRegistry.configure_from_ruleset: ruleset 为空")
	if not (ruleset is RulesetV2):
		return Result.failure("EffectUiTextRegistry.configure_from_ruleset: ruleset 类型错误（期望 RulesetV2）")
	if not ruleset.has_method("get_ui_extensions"):
		return Result.failure("EffectUiTextRegistry.configure_from_ruleset: ruleset 缺少 get_ui_extensions")

	var ui_extensions = ruleset.get_ui_extensions()
	if ui_extensions == null or not (ui_extensions is Object):
		return Result.failure("EffectUiTextRegistry.configure_from_ruleset: ruleset.get_ui_extensions() 返回值类型错误（期望 Object）")

	var effect_items = ui_extensions.get("effect_ui_texts")
	if not (effect_items is Array):
		return Result.failure("EffectUiTextRegistry.configure_from_ruleset: ui_extensions.effect_ui_texts 缺失或类型错误（期望 Array）")
	var milestone_items = ui_extensions.get("milestone_effect_ui_texts")
	if not (milestone_items is Array):
		return Result.failure("EffectUiTextRegistry.configure_from_ruleset: ui_extensions.milestone_effect_ui_texts 缺失或类型错误（期望 Array）")

	_effect_id_text_by_id.clear()
	_milestone_effect_text_by_type.clear()

	for i in range(effect_items.size()):
		var item_val = effect_items[i]
		if not (item_val is Dictionary):
			return Result.failure("EffectUiTextRegistry: effect_ui_texts[%d] 类型错误（期望 Dictionary）" % i)
		var item: Dictionary = item_val

		var id_val = item.get("effect_id", null)
		if not (id_val is String):
			return Result.failure("EffectUiTextRegistry: effect_ui_texts[%d].effect_id 类型错误（期望 String）" % i)
		var effect_id: String = str(id_val).strip_edges()
		if effect_id.is_empty():
			return Result.failure("EffectUiTextRegistry: effect_ui_texts[%d].effect_id 不能为空" % i)

		var text_val = item.get("text", null)
		if not (text_val is String):
			return Result.failure("EffectUiTextRegistry: effect_ui_texts[%d].text 类型错误（期望 String）: %s" % [i, effect_id])
		var text: String = str(text_val).strip_edges()
		if text.is_empty():
			return Result.failure("EffectUiTextRegistry: effect_ui_texts[%d].text 不能为空: %s" % [i, effect_id])

		var prio: int = int(item.get("priority", 100))
		var prev = _effect_id_text_by_id.get(effect_id, null)
		var prev_pri: int = int(prev.get("priority", -2147483648)) if (prev is Dictionary) else -2147483648
		if prev == null or prio >= prev_pri:
			_effect_id_text_by_id[effect_id] = {
				"text": text,
				"priority": prio,
				"source": str(item.get("source", "")),
			}

	for j in range(milestone_items.size()):
		var item2_val = milestone_items[j]
		if not (item2_val is Dictionary):
			return Result.failure("EffectUiTextRegistry: milestone_effect_ui_texts[%d] 类型错误（期望 Dictionary）" % j)
		var item2: Dictionary = item2_val

		var t_val = item2.get("effect_type", null)
		if not (t_val is String):
			return Result.failure("EffectUiTextRegistry: milestone_effect_ui_texts[%d].effect_type 类型错误（期望 String）" % j)
		var effect_type: String = str(t_val).strip_edges()
		if effect_type.is_empty():
			return Result.failure("EffectUiTextRegistry: milestone_effect_ui_texts[%d].effect_type 不能为空" % j)

		var text2_val = item2.get("text", null)
		if not (text2_val is String):
			return Result.failure("EffectUiTextRegistry: milestone_effect_ui_texts[%d].text 类型错误（期望 String）: %s" % [j, effect_type])
		var text2: String = str(text2_val).strip_edges()
		if text2.is_empty():
			return Result.failure("EffectUiTextRegistry: milestone_effect_ui_texts[%d].text 不能为空: %s" % [j, effect_type])

		var prio2: int = int(item2.get("priority", 100))
		var prev2 = _milestone_effect_text_by_type.get(effect_type, null)
		var prev2_pri: int = int(prev2.get("priority", -2147483648)) if (prev2 is Dictionary) else -2147483648
		if prev2 == null or prio2 >= prev2_pri:
			_milestone_effect_text_by_type[effect_type] = {
				"text": text2,
				"priority": prio2,
				"source": str(item2.get("source", "")),
			}

	return Result.success({
		"effects": _effect_id_text_by_id.size(),
		"milestone_effects": _milestone_effect_text_by_type.size(),
	})

static func get_effect_id_text(effect_id: String) -> String:
	if not _loaded:
		return ""
	var eid := str(effect_id).strip_edges()
	if eid.is_empty():
		return ""
	var val = _effect_id_text_by_id.get(eid, null)
	if not (val is Dictionary):
		return ""
	return str((val as Dictionary).get("text", "")).strip_edges()

static func get_milestone_effect_type_text(effect_type: String) -> String:
	if not _loaded:
		return ""
	var t := str(effect_type).strip_edges()
	if t.is_empty():
		return ""
	var val = _milestone_effect_text_by_type.get(t, null)
	if not (val is Dictionary):
		return ""
	return str((val as Dictionary).get("text", "")).strip_edges()
