class_name ModuleUiMetadataBootstrapTest
extends RefCounted

const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const PieceUiHintsRegistryClass = preload("res://core/rules/piece_ui_hints_registry.gd")
const EffectUiTextRegistryClass = preload("res://core/rules/effect_ui_text_registry.gd")
const MapOverlayProviderRegistryClass = preload("res://core/rules/map_overlay_provider_registry.gd")
const ModuleUiMetadataClass = preload("res://gameplay/module_ui_metadata.gd")
const ModuleUiMetadataBootstrapClass = preload("res://gameplay/module_ui_metadata_bootstrap.gd")

static func run(seed_val: int = 12345) -> Result:
	ModuleUiMetadataBootstrapClass.reset()

	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val, [
		"base_rules",
		"base_products",
		"base_pieces",
		"base_tiles",
		"base_maps",
		"base_employees",
		"base_milestones",
		"base_marketing",
		"kimchi",
		"ketchup_mechanism",
		"lobbyists",
		"rural_marketeers",
	])
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)

	var r1 := _assert_engine_initialize_no_longer_populates_ui_metadata()
	if not r1.ok:
		return r1

	var apply_r := ModuleUiMetadataBootstrapClass.apply(engine)
	if not apply_r.ok:
		return Result.failure("UI metadata 装配失败: %s" % apply_r.error)

	var r2 := _assert_bootstrap_populates_ui_metadata()
	if not r2.ok:
		return r2

	return Result.success({
		"phase_action_modal": ModuleUiMetadataClass.get_phase_action_ui_modal_scene_path(DefsClass.PHASE_CLEANUP, "kimchi"),
	})

static func _assert_engine_initialize_no_longer_populates_ui_metadata() -> Result:
	if not ModuleUiMetadataClass.get_phase_action_ui_modal_scene_path(DefsClass.PHASE_CLEANUP, "kimchi").is_empty():
		return Result.failure("engine.initialize 后不应直接装配 phase action UI modal")
	if not PieceUiHintsRegistryClass.get_kind("lobbyists_park_line").is_empty():
		return Result.failure("engine.initialize 后不应直接装配 piece UI hints")
	if not EffectUiTextRegistryClass.get_effect_id_text("ketchup_mechanism:dinnertime:distance_delta:ketchup").is_empty():
		return Result.failure("engine.initialize 后不应直接装配 effect UI texts")
	var overlays := MapOverlayProviderRegistryClass.get_pending_road_connection_dirs(_build_lobbyists_map_data())
	if not overlays.is_empty():
		return Result.failure("engine.initialize 后不应直接装配 map overlay providers")
	return Result.success()

static func _assert_bootstrap_populates_ui_metadata() -> Result:
	var kimchi_path := ModuleUiMetadataClass.get_phase_action_ui_modal_scene_path(DefsClass.PHASE_CLEANUP, "kimchi")
	if kimchi_path.is_empty():
		return Result.failure("bootstrap 后 kimchi phase action modal 未注册")
	if ModuleUiMetadataClass.get_piece_ui_hint_entries().is_empty():
		return Result.failure("bootstrap 后 ModuleUiMetadata 未缓存 piece_ui_hints")
	if ModuleUiMetadataClass.get_effect_ui_text_entries().is_empty():
		return Result.failure("bootstrap 后 ModuleUiMetadata 未缓存 effect_ui_texts")
	if ModuleUiMetadataClass.get_milestone_effect_ui_text_entries().is_empty():
		return Result.failure("bootstrap 后 ModuleUiMetadata 未缓存 milestone_effect_ui_texts")
	if ModuleUiMetadataClass.get_map_overlay_provider_entries().is_empty():
		return Result.failure("bootstrap 后 ModuleUiMetadata 未缓存 map_overlay_providers")
	if PieceUiHintsRegistryClass.get_kind("lobbyists_park_line") != "park":
		return Result.failure("bootstrap 后 lobbyists_park_line kind 未注册")
	if EffectUiTextRegistryClass.get_effect_id_text("ketchup_mechanism:dinnertime:distance_delta:ketchup").is_empty():
		return Result.failure("bootstrap 后 ketchup effect UI text 未注册")
	var overlays := MapOverlayProviderRegistryClass.get_pending_road_connection_dirs(_build_lobbyists_map_data())
	if overlays.is_empty():
		return Result.failure("bootstrap 后 map overlay provider 未注册")
	return Result.success()

static func _build_lobbyists_map_data() -> Dictionary:
	return {
		"lobbyists_pending_roads": [
			{
				"segments_by_pos": {
					"2,3": [{"dirs": ["N", "E"]}],
				},
			},
		],
		"lobbyists_roadworks_markers": {
			"2,3": true,
		},
	}
