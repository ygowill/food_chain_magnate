# 模块 UI 元数据容器（由 gameplay 层装配，避免 core 直接承担 UI 场景路径注册职责）
class_name ModuleUiMetadata
extends RefCounted

static var _phase_action_modal_by_key: Dictionary = {} # "%s|%s" % [phase, kind] -> {scene_path, priority, source}
static var _loaded: bool = false

static func reset() -> void:
	_phase_action_modal_by_key = {}
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

	var list_val = ui_extensions.get("phase_action_ui_modals")
	if not (list_val is Array):
		return Result.failure("ModuleUiMetadata.configure_from_ruleset: ui_extensions.phase_action_ui_modals 缺失或类型错误（期望 Array）")

	_phase_action_modal_by_key.clear()

	var list: Array = list_val
	for i in range(list.size()):
		var item_val = list[i]
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

	return Result.success({
		"phase_action_modals": _phase_action_modal_by_key.size(),
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

static func _build_phase_action_modal_key(phase_name: String, kind: String) -> String:
	var phase := str(phase_name).strip_edges()
	var modal_kind := str(kind).strip_edges()
	if phase.is_empty() or modal_kind.is_empty():
		return ""
	return "%s|%s" % [phase, modal_kind]
