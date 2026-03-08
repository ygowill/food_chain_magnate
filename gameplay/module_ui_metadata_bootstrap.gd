# 模块 UI 元数据装配（gameplay 层）
# 目的：
# - 将 UI metadata 的 registry 装配从 core/engine/modules_v2.gd 挪到 gameplay 层
# - 保持运行时入口显式调用，避免 core 在初始化时承担 UI 展示职责
class_name ModuleUiMetadataBootstrap
extends RefCounted

const ModuleUiMetadataClass = preload("res://gameplay/module_ui_metadata.gd")
const PieceUiHintsRegistryClass = preload("res://core/rules/piece_ui_hints_registry.gd")
const EffectUiTextRegistryClass = preload("res://core/rules/effect_ui_text_registry.gd")
const MapOverlayProviderRegistryClass = preload("res://core/rules/map_overlay_provider_registry.gd")

static func reset() -> void:
	ModuleUiMetadataClass.reset()
	PieceUiHintsRegistryClass.reset()
	EffectUiTextRegistryClass.reset()
	MapOverlayProviderRegistryClass.reset()

static func apply(engine) -> Result:
	reset()
	if engine == null:
		return Result.failure("ModuleUiMetadataBootstrap.apply: engine 为空")

	var ui_extensions = engine.get_module_ui_extensions_v2() if engine != null and engine.has_method("get_module_ui_extensions_v2") else null
	if ui_extensions == null:
		return Result.failure("ModuleUiMetadataBootstrap.apply: engine.module_ui_extensions_v2 为空")

	var metadata_apply := ModuleUiMetadataClass.configure_from_ui_extensions(ui_extensions)
	if not metadata_apply.ok:
		return Result.failure("ModuleUiMetadataBootstrap: %s" % metadata_apply.error)

	var piece_apply := PieceUiHintsRegistryClass.configure_from_module_ui_metadata(ModuleUiMetadataClass)
	if not piece_apply.ok:
		return Result.failure("ModuleUiMetadataBootstrap: %s" % piece_apply.error)

	var effect_apply := EffectUiTextRegistryClass.configure_from_module_ui_metadata(ModuleUiMetadataClass)
	if not effect_apply.ok:
		return Result.failure("ModuleUiMetadataBootstrap: %s" % effect_apply.error)

	var overlay_apply := MapOverlayProviderRegistryClass.configure_from_module_ui_metadata(ModuleUiMetadataClass)
	if not overlay_apply.ok:
		return Result.failure("ModuleUiMetadataBootstrap: %s" % overlay_apply.error)

	var phase_action_modal_count := 0
	var metadata_counts = metadata_apply.value if (metadata_apply.value is Dictionary) else {}
	if metadata_counts is Dictionary:
		phase_action_modal_count = int((metadata_counts as Dictionary).get("phase_action_modals", 0))

	var piece_hint_count := 0
	if piece_apply.value is int:
		piece_hint_count = int(piece_apply.value)

	var effect_text_count := 0
	if effect_apply.value is Dictionary:
		effect_text_count = int((effect_apply.value as Dictionary).get("effects", 0))

	var overlay_provider_count := 0
	if overlay_apply.value is int:
		overlay_provider_count = int(overlay_apply.value)

	return Result.success({
		"phase_action_modals": phase_action_modal_count,
		"piece_hints": piece_hint_count,
		"effect_texts": effect_text_count,
		"map_overlay_providers": overlay_provider_count,
	})
