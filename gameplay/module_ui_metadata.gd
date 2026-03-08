# 模块 UI 元数据容器（由 gameplay 层装配，避免 core 直接承担 UI 场景路径注册职责）
class_name ModuleUiMetadata
extends RefCounted

static var _phase_action_modal_by_key: Dictionary = {} # "%s|%s" % [phase, kind] -> {scene_path, priority, source}
static var _piece_ui_hints: Array = []
static var _effect_ui_texts: Array = []
static var _milestone_effect_ui_texts: Array = []
static var _map_overlay_providers: Array = []
static var _loaded: bool = false

static func reset() -> void:
	_phase_action_modal_by_key = {}
	_piece_ui_hints = []
	_effect_ui_texts = []
	_milestone_effect_ui_texts = []
	_map_overlay_providers = []
	_loaded = true

static func is_loaded() -> bool:
	return _loaded

static func configure_from_ruleset(ruleset) -> Result:
	if not _loaded:
		return Result.failure("ModuleUiMetadata 未初始化：请先调用 reset()")
	if ruleset == null:
		return Result.failure("ModuleUiMetadata.configure_from_ruleset: ruleset 为空")
	if not (ruleset is Object):
		return Result.failure("ModuleUiMetadata.configure_from_ruleset: ruleset 类型错误（期望 Object）")
	if not ruleset.has_method("get_ui_extensions"):
		return Result.failure("ModuleUiMetadata.configure_from_ruleset: ruleset 缺少 get_ui_extensions")

	var ui_extensions = ruleset.get_ui_extensions()
	if ui_extensions == null or not (ui_extensions is Object):
		return Result.failure("ModuleUiMetadata.configure_from_ruleset: ruleset.get_ui_extensions() 返回值类型错误（期望 Object）")

	var modal_items = ui_extensions.get("phase_action_ui_modals")
	if not (modal_items is Array):
		return Result.failure("ModuleUiMetadata.configure_from_ruleset: ui_extensions.phase_action_ui_modals 缺失或类型错误（期望 Array）")

	var piece_hint_items = ui_extensions.get("piece_ui_hints")
	if not (piece_hint_items is Array):
		return Result.failure("ModuleUiMetadata.configure_from_ruleset: ui_extensions.piece_ui_hints 缺失或类型错误（期望 Array）")

	var effect_text_items = ui_extensions.get("effect_ui_texts")
	if not (effect_text_items is Array):
		return Result.failure("ModuleUiMetadata.configure_from_ruleset: ui_extensions.effect_ui_texts 缺失或类型错误（期望 Array）")

	var milestone_effect_text_items = ui_extensions.get("milestone_effect_ui_texts")
	if not (milestone_effect_text_items is Array):
		return Result.failure("ModuleUiMetadata.configure_from_ruleset: ui_extensions.milestone_effect_ui_texts 缺失或类型错误（期望 Array）")

	var overlay_provider_items = ui_extensions.get("map_overlay_providers")
	if not (overlay_provider_items is Array):
		return Result.failure("ModuleUiMetadata.configure_from_ruleset: ui_extensions.map_overlay_providers 缺失或类型错误（期望 Array）")

	_phase_action_modal_by_key.clear()

	var modal_list: Array = modal_items
	for i in range(modal_list.size()):
		var item_val = modal_list[i]
		if not (item_val is Dictionary):
			return Result.failure("ModuleUiMetadata: phase_action_ui_modals[%d] 类型错误（期望 Dictionary）" % i)
		var item: Dictionary = item_val

		var phase_val = item.get("phase", null)
		if not (phase_val is String):
			return Result.failure("ModuleUiMetadata: phase_action_ui_modals[%d].phase 类型错误（期望 String）" % i)
		var phase_name := str(phase_val).strip_edges()
		if phase_name.is_empty():
			return Result.failure("ModuleUiMetadata: phase_action_ui_modals[%d].phase 不能为空" % i)

		var kind_val = item.get("kind", null)
		if not (kind_val is String):
			return Result.failure("ModuleUiMetadata: phase_action_ui_modals[%d].kind 类型错误（期望 String）" % i)
		var kind := str(kind_val).strip_edges()
		if kind.is_empty():
			return Result.failure("ModuleUiMetadata: phase_action_ui_modals[%d].kind 不能为空" % i)

		var path_val = item.get("scene_path", null)
		if not (path_val is String):
			return Result.failure("ModuleUiMetadata: phase_action_ui_modals[%d].scene_path 类型错误（期望 String）" % i)
		var scene_path := str(path_val).strip_edges()
		if scene_path.is_empty():
			return Result.failure("ModuleUiMetadata: phase_action_ui_modals[%d].scene_path 不能为空" % i)
		if not scene_path.begins_with("res://"):
			return Result.failure("ModuleUiMetadata: phase_action_ui_modals[%d].scene_path 必须以 res:// 开头: %s" % [i, scene_path])

		var priority := int(item.get("priority", 100))
		var source := str(item.get("source", "")).strip_edges()
		var key := _build_phase_action_modal_key(phase_name, kind)
		var prev_val = _phase_action_modal_by_key.get(key, null)
		if not (prev_val is Dictionary) or priority >= int((prev_val as Dictionary).get("priority", -2147483648)):
			_phase_action_modal_by_key[key] = {
				"scene_path": scene_path,
				"priority": priority,
				"source": source,
			}

	_piece_ui_hints = (piece_hint_items as Array).duplicate()
	_effect_ui_texts = (effect_text_items as Array).duplicate()
	_milestone_effect_ui_texts = (milestone_effect_text_items as Array).duplicate()
	_map_overlay_providers = (overlay_provider_items as Array).duplicate()

	return Result.success({
		"phase_action_modals": _phase_action_modal_by_key.size(),
		"piece_ui_hints": _piece_ui_hints.size(),
		"effect_ui_texts": _effect_ui_texts.size(),
		"milestone_effect_ui_texts": _milestone_effect_ui_texts.size(),
		"map_overlay_providers": _map_overlay_providers.size(),
	})

static func get_phase_action_ui_modal_scene_path(phase_name: String, kind: String) -> String:
	if not _loaded:
		return ""
	var key := _build_phase_action_modal_key(phase_name, kind)
	if key.is_empty():
		return ""
	var val = _phase_action_modal_by_key.get(key, null)
	if not (val is Dictionary):
		return ""
	return str((val as Dictionary).get("scene_path", "")).strip_edges()

static func get_piece_ui_hint_entries() -> Array:
	if not _loaded:
		return []
	return _piece_ui_hints.duplicate()

static func get_effect_ui_text_entries() -> Array:
	if not _loaded:
		return []
	return _effect_ui_texts.duplicate()

static func get_milestone_effect_ui_text_entries() -> Array:
	if not _loaded:
		return []
	return _milestone_effect_ui_texts.duplicate()

static func get_map_overlay_provider_entries() -> Array:
	if not _loaded:
		return []
	return _map_overlay_providers.duplicate()

static func _build_phase_action_modal_key(phase_name: String, kind: String) -> String:
	var phase := str(phase_name).strip_edges()
	var modal_kind := str(kind).strip_edges()
	if phase.is_empty() or modal_kind.is_empty():
		return ""
	return "%s|%s" % [phase, modal_kind]
