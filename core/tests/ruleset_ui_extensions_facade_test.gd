# RulesetV2 UI 扩展 holder 回归测试
class_name RulesetUiExtensionsFacadeTest
extends RefCounted

const RulesetUiExtensionsClass = preload("res://core/modules/v2/ruleset/ui_extensions.gd")
const PieceUiHintsRegistryClass = preload("res://core/rules/piece_ui_hints_registry.gd")
const EffectUiTextRegistryClass = preload("res://core/rules/effect_ui_text_registry.gd")
const MapOverlayProviderRegistryClass = preload("res://core/rules/map_overlay_provider_registry.gd")
const ModuleUiMetadataClass = preload("res://gameplay/module_ui_metadata.gd")

static func run() -> Result:
	var ruleset := RulesetV2.new()
	if ruleset.has_method("get_ui_extensions"):
		return Result.failure("RulesetV2 不应继续暴露 get_ui_extensions facade")
	if ruleset.has_method("register_phase_action_ui_modal"):
		return Result.failure("RulesetV2 不应继续暴露 register_phase_action_ui_modal facade")

	var ui_extensions := RulesetUiExtensionsClass.new()

	var modal_r := ui_extensions.register_phase_action_ui_modal(
		"cleanup",
		"kimchi",
		"res://ui/scenes/game/modals/kimchi_modal.tscn",
		100,
		"test_module"
	)
	if not modal_r.ok:
		return Result.failure("ui_extensions.register_phase_action_ui_modal 失败: %s" % modal_r.error)
	if ui_extensions.get_phase_action_ui_modal_scene_path("cleanup", "kimchi") != "res://ui/scenes/game/modals/kimchi_modal.tscn":
		return Result.failure("RulesetV2UiExtensions 未透传 phase_action_ui_modal 查询")

	var hint_r := ui_extensions.register_piece_ui_hint("test_module:road", {"kind": "road"}, 100, "test_module")
	if not hint_r.ok:
		return Result.failure("ui_extensions.register_piece_ui_hint 失败: %s" % hint_r.error)

	var effect_r := ui_extensions.register_effect_ui_text("test_module:effect", "effect text", 100, "test_module")
	if not effect_r.ok:
		return Result.failure("ui_extensions.register_effect_ui_text 失败: %s" % effect_r.error)

	var milestone_r := ui_extensions.register_milestone_effect_ui_text("test_module:milestone", "milestone text", 100, "test_module")
	if not milestone_r.ok:
		return Result.failure("ui_extensions.register_milestone_effect_ui_text 失败: %s" % milestone_r.error)

	var overlay_provider := func(_map_data: Dictionary) -> Dictionary:
		return {
			"pending_road_connection_dirs_by_pos": {
				Vector2i(1, 2): {"N": true},
			},
			"roadworks_marker_world_positions": [Vector2i(3, 4)],
		}

	var overlay_r := ui_extensions.register_map_overlay_provider(
		"test_overlay",
		overlay_provider,
		100,
		"test_module"
	)
	if not overlay_r.ok:
		return Result.failure("ui_extensions.register_map_overlay_provider 失败: %s" % overlay_r.error)

	var supply_r := ui_extensions.register_reserve_supply_provider(
		"test_module:supply",
		func(_state: GameState) -> Dictionary:
			return {"test_supply_remaining": 2},
		100,
		"test_module"
	)
	if not supply_r.ok:
		return Result.failure("ui_extensions.register_reserve_supply_provider 失败: %s" % supply_r.error)

	var phase_modals_val = ui_extensions.get("phase_action_ui_modals")
	if not (phase_modals_val is Array) or phase_modals_val.size() != 1:
		return Result.failure("ui_extensions.phase_action_ui_modals 未收到注册结果")

	ModuleUiMetadataClass.reset()
	var metadata_r := ModuleUiMetadataClass.configure_from_ui_extensions(ui_extensions)
	if not metadata_r.ok:
		return Result.failure("ModuleUiMetadata.configure_from_ui_extensions 失败: %s" % metadata_r.error)

	if ModuleUiMetadataClass.get_piece_ui_hint_entries().size() != 1:
		return Result.failure("ModuleUiMetadata 未缓存 piece_ui_hints")
	if ModuleUiMetadataClass.get_effect_ui_text_entries().size() != 1:
		return Result.failure("ModuleUiMetadata 未缓存 effect_ui_texts")
	if ModuleUiMetadataClass.get_milestone_effect_ui_text_entries().size() != 1:
		return Result.failure("ModuleUiMetadata 未缓存 milestone_effect_ui_texts")
	if ModuleUiMetadataClass.get_map_overlay_provider_entries().size() != 1:
		return Result.failure("ModuleUiMetadata 未缓存 map_overlay_providers")
	if ModuleUiMetadataClass.get_reserve_supply_provider_entries().size() != 1:
		return Result.failure("ModuleUiMetadata 未缓存 reserve_supply_providers")

	PieceUiHintsRegistryClass.reset()
	EffectUiTextRegistryClass.reset()
	MapOverlayProviderRegistryClass.reset()

	var piece_registry_r := PieceUiHintsRegistryClass.configure_from_module_ui_metadata(ModuleUiMetadataClass)
	if not piece_registry_r.ok:
		return Result.failure("PieceUiHintsRegistry.configure_from_module_ui_metadata 失败: %s" % piece_registry_r.error)
	if PieceUiHintsRegistryClass.get_kind("test_module:road") != "road":
		return Result.failure("PieceUiHintsRegistry 未能从 ModuleUiMetadata 读取 hints")

	var effect_registry_r := EffectUiTextRegistryClass.configure_from_module_ui_metadata(ModuleUiMetadataClass)
	if not effect_registry_r.ok:
		return Result.failure("EffectUiTextRegistry.configure_from_module_ui_metadata 失败: %s" % effect_registry_r.error)
	if EffectUiTextRegistryClass.get_effect_id_text("test_module:effect") != "effect text":
		return Result.failure("EffectUiTextRegistry 未能从 ModuleUiMetadata 读取 effect 文案")
	if EffectUiTextRegistryClass.get_milestone_effect_type_text("test_module:milestone") != "milestone text":
		return Result.failure("EffectUiTextRegistry 未能从 ModuleUiMetadata 读取 milestone 文案")

	var overlay_registry_r := MapOverlayProviderRegistryClass.configure_from_module_ui_metadata(ModuleUiMetadataClass)
	if not overlay_registry_r.ok:
		return Result.failure("MapOverlayProviderRegistry.configure_from_module_ui_metadata 失败: %s" % overlay_registry_r.error)
	var pending_dirs := MapOverlayProviderRegistryClass.get_pending_road_connection_dirs({"ok": true})
	var dirs_val = pending_dirs.get(Vector2i(1, 2), null)
	if not (dirs_val is Dictionary) or not (dirs_val as Dictionary).has("N"):
		return Result.failure("MapOverlayProviderRegistry 未能从 ModuleUiMetadata 读取 overlay provider")
	var markers := MapOverlayProviderRegistryClass.get_roadworks_marker_world_positions({"ok": true})
	if markers.size() != 1 or markers[0] != Vector2i(3, 4):
		return Result.failure("MapOverlayProviderRegistry overlay 输出不符合预期")

	ui_extensions.clear()
	var disposed_modals = ui_extensions.get("phase_action_ui_modals")
	if not (disposed_modals is Array) or not disposed_modals.is_empty():
		return Result.failure("RulesetV2UiExtensions.clear() 未清空 ui_extensions")
	var disposed_supply_providers = ui_extensions.get("reserve_supply_providers")
	if not (disposed_supply_providers is Array) or not disposed_supply_providers.is_empty():
		return Result.failure("RulesetV2UiExtensions.clear() 未清空 reserve_supply_providers")

	ruleset.dispose()
	return Result.success({
		"phase_action_modals": 1,
		"piece_ui_hints": 1,
		"effect_ui_texts": 1,
		"map_overlay_providers": 1,
		"reserve_supply_providers": 1,
	})
