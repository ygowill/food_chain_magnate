# 模块系统 V2：RulesetBuilder（供模块 entry_script 注册规则）
class_name RulesetBuilderV2
extends RefCounted

const RulesetV2Class = preload("res://core/modules/v2/ruleset.gd")
const UiExtensionsClass = preload("res://core/modules/v2/ruleset/ui_extensions.gd")

var ruleset = null
var ui_extensions = null

func _init() -> void:
	ruleset = RulesetV2Class.new()
	ui_extensions = UiExtensionsClass.new()

func for_module(module_id: String) -> RulesetRegistrarV2:
	return RulesetRegistrarV2.new(ruleset, ui_extensions, module_id)

class RulesetRegistrarV2:
	extends RefCounted

	var _ruleset = null
	var _ui_extensions = null
	var _module_id: String = ""

	func _init(ruleset_in, ui_extensions_in, module_id_in: String) -> void:
		_ruleset = ruleset_in
		_ui_extensions = ui_extensions_in
		_module_id = module_id_in

	func retain_entry_instance(inst) -> void:
		# Callables don't keep objects alive; retain module-owned instances so registered callbacks stay valid.
		if _ruleset != null and _ruleset.has_method("retain_entry_instance"):
			_ruleset.retain_entry_instance(inst)

	func register_primary_settlement(phase: int, point: int, callback: Callable) -> Result:
		return _ruleset.settlement_registry.register_primary(phase, point, callback, _module_id)

	func register_extension_settlement(phase: int, point: int, callback: Callable, priority: int = 100) -> Result:
		return _ruleset.settlement_registry.register_extension(phase, point, callback, priority, _module_id)

	func register_effect(effect_id: String, callback: Callable) -> Result:
		return _ruleset.effect_registry.register_effect(effect_id, callback, _module_id)

	func register_milestone_effect(effect_type: String, callback: Callable) -> Result:
		return _ruleset.milestone_effect_registry.register_effect_type(effect_type, callback, _module_id)

	func register_primary_map_generator(callback: Callable) -> Result:
		return _ruleset.map_generation_registry.register_primary(callback, _module_id)

	func register_map_candidate_selector(callback: Callable) -> Result:
		return _ruleset.map_generation_registry.register_candidate_selector(callback, _module_id)

	func register_employee_patch(target_employee_id: String, patch: Dictionary) -> Result:
		return _ruleset.register_employee_patch(target_employee_id, patch, _module_id)

	func register_milestone_patch(target_milestone_id: String, patch: Dictionary) -> Result:
		return _ruleset.register_milestone_patch(target_milestone_id, patch, _module_id)

	func register_phase_hook(phase: int, hook_type: int, callback: Callable, priority: int = 100) -> Result:
		return _ruleset.register_phase_hook(phase, hook_type, callback, priority, _module_id)

	func register_sub_phase_hook(sub_phase: int, hook_type: int, callback: Callable, priority: int = 100) -> Result:
		return _ruleset.register_sub_phase_hook(sub_phase, hook_type, callback, priority, _module_id)

	func register_named_sub_phase_hook(sub_phase_name: String, hook_type: int, callback: Callable, priority: int = 100) -> Result:
		return _ruleset.register_named_sub_phase_hook(sub_phase_name, hook_type, callback, priority, _module_id)

	func register_working_sub_phase_insertion(sub_phase_name: String, after_sub_phase_name: String, before_sub_phase_name: String, priority: int = 100) -> Result:
		return _ruleset.register_working_sub_phase_insertion(sub_phase_name, after_sub_phase_name, before_sub_phase_name, priority, _module_id)

	func register_working_sub_phase_hook(sub_phase_name: String, hook_type: int, callback: Callable, priority: int = 100) -> Result:
		return _ruleset.register_working_sub_phase_hook(sub_phase_name, hook_type, callback, priority, _module_id)

	func register_cleanup_sub_phase_insertion(sub_phase_name: String, after_sub_phase_name: String, before_sub_phase_name: String, priority: int = 100) -> Result:
		return _ruleset.register_cleanup_sub_phase_insertion(sub_phase_name, after_sub_phase_name, before_sub_phase_name, priority, _module_id)

	func register_cleanup_sub_phase_hook(sub_phase_name: String, hook_type: int, callback: Callable, priority: int = 100) -> Result:
		return _ruleset.register_cleanup_sub_phase_hook(sub_phase_name, hook_type, callback, priority, _module_id)

	func register_working_sub_phase_order_override(order_names: Array, priority: int = 100) -> Result:
		return _ruleset.register_working_sub_phase_order_override(order_names, priority, _module_id)

	func register_cleanup_sub_phase_order_override(order_names: Array, priority: int = 100) -> Result:
		return _ruleset.register_cleanup_sub_phase_order_override(order_names, priority, _module_id)

	func register_settlement_triggers_override(phase: int, timing: String, points: Array, priority: int = 100) -> Result:
		return _ruleset.register_settlement_triggers_override(phase, timing, points, priority, _module_id)

	func register_timeline_settlement_event_policy(phase: int, point: int, policy: Dictionary, priority: int = 100) -> Result:
		return _ruleset.register_timeline_settlement_event_policy(phase, point, policy, priority, _module_id)

	func register_phase_sub_phase_order_override(phase: int, order_names: Array, priority: int = 100) -> Result:
		return _ruleset.register_phase_sub_phase_order_override(phase, order_names, priority, _module_id)

	func register_action_executor(executor) -> Result:
		return _ruleset.register_action_executor(executor, _module_id)

	func register_action_validator(action_id: String, validator_id: String, callback: Callable, priority: int = 100) -> Result:
		return _ruleset.register_action_validator(action_id, validator_id, callback, priority, _module_id)

	func register_global_action_validator(validator_id: String, callback: Callable, priority: int = 100) -> Result:
		return _ruleset.register_global_action_validator(validator_id, callback, priority, _module_id)

	func register_action_availability_override(action_id: String, points: Array, priority: int = 100) -> Result:
		return _ruleset.register_action_availability_override(action_id, points, priority, _module_id)

	func register_marketing_type(type_id: String, config: Dictionary, range_handler: Callable) -> Result:
		return _ruleset.register_marketing_type(type_id, config, range_handler, _module_id)

	func register_marketing_initiation_provider(provider_id: String, callback: Callable, priority: int = 100) -> Result:
		return _ruleset.register_marketing_initiation_provider(provider_id, callback, priority, _module_id)

	func register_bankruptcy_handler(kind: String, callback: Callable) -> Result:
		return _ruleset.register_bankruptcy_handler(kind, callback, _module_id)

	func register_dinnertime_demand_provider(provider_id: String, callback: Callable, priority: int = 100) -> Result:
		return _ruleset.register_dinnertime_demand_provider(provider_id, callback, priority, _module_id)

	func register_dinnertime_route_purchase_provider(provider_id: String, callback: Callable, priority: int = 100) -> Result:
		return _ruleset.register_dinnertime_route_purchase_provider(provider_id, callback, priority, _module_id)

	func register_placement_conflict_provider(provider_id: String, callback: Callable, priority: int = 100) -> Result:
		return _ruleset.register_placement_conflict_provider(provider_id, callback, priority, _module_id)

	func register_range_origin_provider(provider_id: String, callback: Callable, priority: int = 100) -> Result:
		return _ruleset.register_range_origin_provider(provider_id, callback, priority, _module_id)

	func register_phase_action_ui_modal(phase_name: String, kind: String, scene_path: String, priority: int = 100) -> Result:
		if _ui_extensions == null or not _ui_extensions.has_method("register_phase_action_ui_modal"):
			return Result.failure("RulesetRegistrarV2: ui_extensions 缺少 register_phase_action_ui_modal")
		return _ui_extensions.register_phase_action_ui_modal(phase_name, kind, scene_path, priority, _module_id)

	func register_map_overlay_provider(provider_id: String, callback: Callable, priority: int = 100) -> Result:
		if _ui_extensions == null or not _ui_extensions.has_method("register_map_overlay_provider"):
			return Result.failure("RulesetRegistrarV2: ui_extensions 缺少 register_map_overlay_provider")
		return _ui_extensions.register_map_overlay_provider(provider_id, callback, priority, _module_id)

	func register_reserve_supply_provider(provider_id: String, callback: Callable, priority: int = 100) -> Result:
		if _ui_extensions == null or not _ui_extensions.has_method("register_reserve_supply_provider"):
			return Result.failure("RulesetRegistrarV2: ui_extensions 缺少 register_reserve_supply_provider")
		return _ui_extensions.register_reserve_supply_provider(provider_id, callback, priority, _module_id)

	func register_piece_ui_hint(piece_id: String, hints: Dictionary, priority: int = 100) -> Result:
		if _ui_extensions == null or not _ui_extensions.has_method("register_piece_ui_hint"):
			return Result.failure("RulesetRegistrarV2: ui_extensions 缺少 register_piece_ui_hint")
		return _ui_extensions.register_piece_ui_hint(piece_id, hints, priority, _module_id)

	func register_effect_ui_text(effect_id: String, text: String, priority: int = 100) -> Result:
		if _ui_extensions == null or not _ui_extensions.has_method("register_effect_ui_text"):
			return Result.failure("RulesetRegistrarV2: ui_extensions 缺少 register_effect_ui_text")
		return _ui_extensions.register_effect_ui_text(effect_id, text, priority, _module_id)

	func register_milestone_effect_ui_text(effect_type: String, text: String, priority: int = 100) -> Result:
		if _ui_extensions == null or not _ui_extensions.has_method("register_milestone_effect_ui_text"):
			return Result.failure("RulesetRegistrarV2: ui_extensions 缺少 register_milestone_effect_ui_text")
		return _ui_extensions.register_milestone_effect_ui_text(effect_type, text, priority, _module_id)

	func register_employee_pool_patch(patch_id: String, employee_id: String, delta: int) -> Result:
		return _ruleset.register_employee_pool_patch(patch_id, employee_id, delta, _module_id)

	func register_phase_order_override(phase_order_names: Array, priority: int = 100) -> Result:
		return _ruleset.register_phase_order_override(phase_order_names, priority, _module_id)

	func register_state_initializer(initializer_id: String, callback: Callable, priority: int = 100) -> Result:
		return _ruleset.register_state_initializer(initializer_id, callback, priority, _module_id)

	func register_round_state_int_key_dict_schema(schema_id: String, path: Array, priority: int = 100) -> Result:
		return _ruleset.register_state_int_key_dict_schema(schema_id, "round_state", path, priority, _module_id)

	func register_map_int_key_dict_schema(schema_id: String, path: Array, priority: int = 100) -> Result:
		return _ruleset.register_state_int_key_dict_schema(schema_id, "map", path, priority, _module_id)
