# RulesetV2：UI 扩展 holder（供 facade 转发，便于后续整体迁出 core）
class_name RulesetV2UiExtensions
extends RefCounted

var phase_action_ui_modals: Array[Dictionary] = []  # [{phase, kind, scene_path, priority, source}]
var map_overlay_providers: Array[Dictionary] = []  # [{id, callback, priority, source}]
var piece_ui_hints: Array[Dictionary] = []  # [{piece_id, hints, priority, source}]
var effect_ui_texts: Array[Dictionary] = []  # [{effect_id, text, priority, source}]
var milestone_effect_ui_texts: Array[Dictionary] = []  # [{effect_type, text, priority, source}]

func clear() -> void:
	phase_action_ui_modals.clear()
	map_overlay_providers.clear()
	piece_ui_hints.clear()
	effect_ui_texts.clear()
	milestone_effect_ui_texts.clear()

func register_phase_action_ui_modal(
	phase_name: String,
	kind: String,
	scene_path: String,
	priority: int = 100,
	source_module_id: String = ""
) -> Result:
	var phase := str(phase_name).strip_edges()
	if phase.is_empty():
		return Result.failure("RulesetV2: phase_action_ui_modal.phase_name 不能为空")
	var k := str(kind).strip_edges()
	if k.is_empty():
		return Result.failure("RulesetV2: phase_action_ui_modal.kind 不能为空")
	var path := str(scene_path).strip_edges()
	if path.is_empty():
		return Result.failure("RulesetV2: phase_action_ui_modal.scene_path 不能为空")
	if not path.begins_with("res://"):
		return Result.failure("RulesetV2: phase_action_ui_modal.scene_path 必须以 res:// 开头: %s" % path)

	var entry := {
		"phase": phase,
		"kind": k,
		"scene_path": path,
		"priority": int(priority),
		"source": str(source_module_id),
	}

	for i in range(phase_action_ui_modals.size()):
		var prev_val = phase_action_ui_modals[i]
		if not (prev_val is Dictionary):
			continue
		var prev: Dictionary = prev_val
		if str(prev.get("phase", "")).strip_edges() != phase:
			continue
		if str(prev.get("kind", "")).strip_edges() != k:
			continue
		var prev_src := str(prev.get("source", "")).strip_edges()
		phase_action_ui_modals[i] = entry
		if not prev_src.is_empty():
			return Result.success().with_warning("phase action ui modal 覆盖: %s:%s (%s -> %s)" % [phase, k, prev_src, str(source_module_id)])
		return Result.success()

	phase_action_ui_modals.append(entry)
	return Result.success()

func get_phase_action_ui_modal_scene_path(phase_name: String, kind: String) -> String:
	var phase := str(phase_name).strip_edges()
	var k := str(kind).strip_edges()
	if phase.is_empty() or k.is_empty():
		return ""

	var best_path := ""
	var best_pri := -2147483648
	for e_val in phase_action_ui_modals:
		if not (e_val is Dictionary):
			continue
		var e: Dictionary = e_val
		if str(e.get("phase", "")).strip_edges() != phase:
			continue
		if str(e.get("kind", "")).strip_edges() != k:
			continue
		var pri := int(e.get("priority", 100))
		if best_path.is_empty() or pri >= best_pri:
			best_pri = pri
			best_path = str(e.get("scene_path", "")).strip_edges()
	return best_path

func register_map_overlay_provider(provider_id: String, callback: Callable, priority: int = 100, source_module_id: String = "") -> Result:
	var id := str(provider_id).strip_edges()
	if id.is_empty():
		return Result.failure("RulesetV2: map_overlay_provider.id 不能为空")
	if not callback.is_valid():
		return Result.failure("RulesetV2: map_overlay_provider.callback 无效: %s" % id)

	var entry := {
		"id": id,
		"callback": callback,
		"priority": int(priority),
		"source": str(source_module_id),
	}

	for i in range(map_overlay_providers.size()):
		var prev_val = map_overlay_providers[i]
		if not (prev_val is Dictionary):
			continue
		var prev: Dictionary = prev_val
		if str(prev.get("id", "")).strip_edges() != id:
			continue
		var prev_src := str(prev.get("source", "")).strip_edges()
		map_overlay_providers[i] = entry
		if not prev_src.is_empty():
			return Result.success().with_warning("map overlay provider 覆盖: %s (%s -> %s)" % [id, prev_src, str(source_module_id)])
		return Result.success()

	map_overlay_providers.append(entry)
	return Result.success()

func register_piece_ui_hint(piece_id: String, hints: Dictionary, priority: int = 100, source_module_id: String = "") -> Result:
	var pid := str(piece_id).strip_edges()
	if pid.is_empty():
		return Result.failure("RulesetV2: piece_ui_hint.piece_id 不能为空")
	if hints == null or not (hints is Dictionary):
		return Result.failure("RulesetV2: piece_ui_hint.hints 类型错误（期望 Dictionary）: %s" % pid)

	var kind_val = hints.get("kind", null)
	if kind_val != null:
		if not (kind_val is String) or str(kind_val).strip_edges().is_empty():
			return Result.failure("RulesetV2: piece_ui_hint.kind 类型错误或为空（期望非空 String）: %s" % pid)

	var overlay_val = hints.get("road_overlay", null)
	if overlay_val != null and not (overlay_val is Dictionary):
		return Result.failure("RulesetV2: piece_ui_hint.road_overlay 类型错误（期望 Dictionary）: %s" % pid)

	piece_ui_hints.append({
		"piece_id": pid,
		"hints": hints,
		"priority": int(priority),
		"source": str(source_module_id),
	})
	return Result.success()

func register_effect_ui_text(effect_id: String, text: String, priority: int = 100, source_module_id: String = "") -> Result:
	var eid := str(effect_id).strip_edges()
	if eid.is_empty():
		return Result.failure("RulesetV2: effect_ui_text.effect_id 不能为空")
	if eid.find(":") <= 0:
		return Result.failure("RulesetV2: effect_ui_text.effect_id 必须为 module_id:...，实际: %s" % eid)

	var s := str(text).strip_edges()
	if s.is_empty():
		return Result.failure("RulesetV2: effect_ui_text.text 不能为空: %s" % eid)

	if not source_module_id.is_empty():
		var prefix := "%s:" % str(source_module_id)
		if not eid.begins_with(prefix):
			return Result.failure("RulesetV2: effect_ui_text.effect_id 必须以 source module_id 作为前缀: %s (expected_prefix=%s)" % [eid, prefix])

	effect_ui_texts.append({
		"effect_id": eid,
		"text": s,
		"priority": int(priority),
		"source": str(source_module_id),
	})
	return Result.success()

func register_milestone_effect_ui_text(effect_type: String, text: String, priority: int = 100, source_module_id: String = "") -> Result:
	var t := str(effect_type).strip_edges()
	if t.is_empty():
		return Result.failure("RulesetV2: milestone_effect_ui_text.effect_type 不能为空")

	var s := str(text).strip_edges()
	if s.is_empty():
		return Result.failure("RulesetV2: milestone_effect_ui_text.text 不能为空: %s" % t)

	if not source_module_id.is_empty() and t.find(":") > 0:
		var prefix := "%s:" % str(source_module_id)
		if not t.begins_with(prefix):
			return Result.failure("RulesetV2: milestone_effect_ui_text.effect_type 必须以 source module_id 作为前缀: %s (expected_prefix=%s)" % [t, prefix])

	milestone_effect_ui_texts.append({
		"effect_type": t,
		"text": s,
		"priority": int(priority),
		"source": str(source_module_id),
	})
	return Result.success()
