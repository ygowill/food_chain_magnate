# RulesetV2 facade -> ui_extensions 回归测试
class_name RulesetUiExtensionsFacadeTest
extends RefCounted

const PieceUiHintsRegistryClass = preload("res://core/rules/piece_ui_hints_registry.gd")
const EffectUiTextRegistryClass = preload("res://core/rules/effect_ui_text_registry.gd")
const MapOverlayProviderRegistryClass = preload("res://core/rules/map_overlay_provider_registry.gd")

static func run() -> Result:
	var ruleset := RulesetV2.new()
	var ui_extensions = ruleset.get_ui_extensions()
	if ui_extensions == null or not (ui_extensions is Object):
		return Result.failure("RulesetV2.get_ui_extensions() 未返回有效对象")

	var modal_r := ruleset.register_phase_action_ui_modal(
		"cleanup",
		"kimchi",
		"res://ui/scenes/game/modals/kimchi_modal.tscn",
		100,
		"test_module"
	)
	if not modal_r.ok:
		return Result.failure("register_phase_action_ui_modal 失败: %s" % modal_r.error)
	if ruleset.get_phase_action_ui_modal_scene_path("cleanup", "kimchi") != "res://ui/scenes/game/modals/kimchi_modal.tscn":
		return Result.failure("RulesetV2 facade 未透传 phase_action_ui_modal 查询")

	var hint_r := ruleset.register_piece_ui_hint("test_module:road", {"kind": "road"}, 100, "test_module")
	if not hint_r.ok:
		return Result.failure("register_piece_ui_hint 失败: %s" % hint_r.error)

	var effect_r := ruleset.register_effect_ui_text("test_module:effect", "effect text", 100, "test_module")
	if not effect_r.ok:
		return Result.failure("register_effect_ui_text 失败: %s" % effect_r.error)

	var milestone_r := ruleset.register_milestone_effect_ui_text("test_module:milestone", "milestone text", 100, "test_module")
	if not milestone_r.ok:
		return Result.failure("register_milestone_effect_ui_text 失败: %s" % milestone_r.error)

	var overlay_provider := func(_map_data: Dictionary) -> Dictionary:
		return {
			"pending_road_connection_dirs_by_pos": {
				Vector2i(1, 2): {"N": true},
			},
			"roadworks_marker_world_positions": [Vector2i(3, 4)],
		}

	var overlay_r := ruleset.register_map_overlay_provider(
		"test_overlay",
		overlay_provider,
		100,
		"test_module"
	)
	if not overlay_r.ok:
		return Result.failure("register_map_overlay_provider 失败: %s" % overlay_r.error)

	var phase_modals_val = ui_extensions.get("phase_action_ui_modals")
	if not (phase_modals_val is Array) or phase_modals_val.size() != 1:
		return Result.failure("ui_extensions.phase_action_ui_modals 未收到 facade 注册结果")

	PieceUiHintsRegistryClass.reset()
	EffectUiTextRegistryClass.reset()
	MapOverlayProviderRegistryClass.reset()

	var piece_registry_r := PieceUiHintsRegistryClass.configure_from_ruleset(ruleset)
	if not piece_registry_r.ok:
		return Result.failure("PieceUiHintsRegistry.configure_from_ruleset 失败: %s" % piece_registry_r.error)
	if PieceUiHintsRegistryClass.get_kind("test_module:road") != "road":
		return Result.failure("PieceUiHintsRegistry 未能从 ui_extensions 读取 hints")

	var effect_registry_r := EffectUiTextRegistryClass.configure_from_ruleset(ruleset)
	if not effect_registry_r.ok:
		return Result.failure("EffectUiTextRegistry.configure_from_ruleset 失败: %s" % effect_registry_r.error)
	if EffectUiTextRegistryClass.get_effect_id_text("test_module:effect") != "effect text":
		return Result.failure("EffectUiTextRegistry 未能从 ui_extensions 读取 effect 文案")
	if EffectUiTextRegistryClass.get_milestone_effect_type_text("test_module:milestone") != "milestone text":
		return Result.failure("EffectUiTextRegistry 未能从 ui_extensions 读取 milestone 文案")

	var overlay_registry_r := MapOverlayProviderRegistryClass.configure_from_ruleset(ruleset)
	if not overlay_registry_r.ok:
		return Result.failure("MapOverlayProviderRegistry.configure_from_ruleset 失败: %s" % overlay_registry_r.error)
	var pending_dirs := MapOverlayProviderRegistryClass.get_pending_road_connection_dirs({"ok": true})
	var dirs_val = pending_dirs.get(Vector2i(1, 2), null)
	if not (dirs_val is Dictionary) or not (dirs_val as Dictionary).has("N"):
		return Result.failure("MapOverlayProviderRegistry 未能从 ui_extensions 读取 overlay provider")
	var markers := MapOverlayProviderRegistryClass.get_roadworks_marker_world_positions({"ok": true})
	if markers.size() != 1 or markers[0] != Vector2i(3, 4):
		return Result.failure("MapOverlayProviderRegistry overlay 输出不符合预期")

	ruleset.dispose()
	var disposed_modals = ui_extensions.get("phase_action_ui_modals")
	if not (disposed_modals is Array) or not disposed_modals.is_empty():
		return Result.failure("RulesetV2.dispose() 未清空 ui_extensions")

	return Result.success({
		"phase_action_modals": 1,
		"piece_ui_hints": 1,
		"effect_ui_texts": 1,
		"map_overlay_providers": 1,
	})
