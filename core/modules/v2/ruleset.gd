# 模块系统 V2：Ruleset（每局由启用模块注册得到的规则集合）
class_name RulesetV2
extends RefCounted

const SettlementRegistryClass = preload("res://core/rules/settlement_registry.gd")
const EffectRegistryClass = preload("res://core/rules/effect_registry.gd")
const MilestoneEffectRegistryClass = preload("res://core/rules/milestone_effect_registry.gd")
const MapGenerationRegistryClass = preload("res://core/rules/map_generation_registry.gd")
const PhaseDefsClass = preload("res://core/engine/phase_manager/definitions.gd")

const PatchesHelperClass = preload("res://core/modules/v2/ruleset/patches.gd")
const SubPhaseRegistrationHelperClass = preload("res://core/modules/v2/ruleset/sub_phase_registration.gd")
const ActionRegistrationHelperClass = preload("res://core/modules/v2/ruleset/action_registration.gd")
const ProviderRegistrationHelperClass = preload("res://core/modules/v2/ruleset/provider_registration.gd")
const StateAndOrderHelperClass = preload("res://core/modules/v2/ruleset/state_and_order.gd")

const PhaseHooksHelperClass = preload("res://core/modules/v2/ruleset/phase_hooks.gd")
const ContentValidationHelperClass = preload("res://core/modules/v2/ruleset/content_validation.gd")

var settlement_registry = SettlementRegistryClass.new()
var effect_registry = EffectRegistryClass.new()
var milestone_effect_registry = MilestoneEffectRegistryClass.new()
var map_generation_registry = MapGenerationRegistryClass.new()
var employee_patches: Array[Dictionary] = []  # [{target_id, patch, source}]
var milestone_patches: Array[Dictionary] = []  # [{target_id, patch, source}]
var phase_hooks: Array[Dictionary] = []  # [{phase, hook_type, callback, priority, source}]
var sub_phase_hooks: Array[Dictionary] = []  # [{sub_phase, hook_type, callback, priority, source}]
var named_sub_phase_hooks: Array[Dictionary] = []  # [{sub_phase, hook_type, callback, priority, source}]
var action_executors: Array = []  # Array[ActionExecutor]
var action_validators: Array[Dictionary] = []  # [{action_id, validator_id, callback, priority, source}]
var global_action_validators: Array[Dictionary] = []  # [{validator_id, callback, priority, source}]
var action_availability_overrides: Array[Dictionary] = []  # [{action_id, points, priority, source}]
var marketing_type_registrations: Array[Dictionary] = []  # [{type_id, requires_edge, range_handler, source}]
var marketing_initiation_providers: Array[Dictionary] = []  # [{id, callback, priority, source}]
var bankruptcy_handlers: Array[Dictionary] = []  # [{kind, callback, source}]
var dinnertime_demand_providers: Array[Dictionary] = []  # [{id, callback, priority, source}]
var dinnertime_route_purchase_providers: Array[Dictionary] = []  # [{id, callback, priority, source}]
var employee_pool_patches: Array[Dictionary] = []  # [{id, employee_id, delta, source}]
var working_sub_phase_insertions: Array[Dictionary] = []  # [{sub_phase, after, before, priority, source}]
var working_sub_phase_name_hooks: Array[Dictionary] = []  # [{sub_phase, hook_type, callback, priority, source}]
var cleanup_sub_phase_insertions: Array[Dictionary] = []  # [{sub_phase, after, before, priority, source}]
var cleanup_sub_phase_name_hooks: Array[Dictionary] = []  # [{sub_phase, hook_type, callback, priority, source}]
var phase_order_override = null  # {order:Array[String], priority:int, source:String}
var working_sub_phase_order_override = null  # {order:Array[String], priority:int, source:String}
var cleanup_sub_phase_order_override = null  # {order:Array[String], priority:int, source:String}
var settlement_triggers_override: Array[Dictionary] = []  # [{phase, timing, points, source}]
var phase_sub_phase_order_overrides: Array[Dictionary] = []  # [{phase, order, priority, source}]
var state_initializers: Array[Dictionary] = []  # [{id, callback, priority, source}]
var _entry_instances: Array = []

func retain_entry_instance(inst) -> void:
	if inst == null:
		return
	_entry_instances.append(inst)

func register_employee_patch(target_employee_id: String, patch: Dictionary, source_module_id: String = "") -> Result:
	return PatchesHelperClass.register_employee_patch(self, target_employee_id, patch, source_module_id)

func register_milestone_patch(target_milestone_id: String, patch: Dictionary, source_module_id: String = "") -> Result:
	return PatchesHelperClass.register_milestone_patch(self, target_milestone_id, patch, source_module_id)

func apply_employee_patches(catalog) -> Result:
	return PatchesHelperClass.apply_employee_patches(self, catalog)

func apply_milestone_patches(catalog) -> Result:
	return PatchesHelperClass.apply_milestone_patches(self, catalog)

func register_phase_hook(phase: int, hook_type: int, callback: Callable, priority: int = 100, source_module_id: String = "") -> Result:
	if not callback.is_valid():
		return Result.failure("RulesetV2: phase hook callback 无效")
	if phase < 0 or phase > PhaseDefsClass.Phase.GAME_OVER:
		return Result.failure("RulesetV2: phase hook phase 越界: %d" % phase)
	if hook_type < 0 or hook_type > 3:
		return Result.failure("RulesetV2: phase hook hook_type 越界: %d" % hook_type)
	phase_hooks.append({
		"phase": phase,
		"hook_type": hook_type,
		"callback": callback,
		"priority": priority,
		"source": source_module_id,
	})
	return Result.success()

func register_sub_phase_hook(sub_phase: int, hook_type: int, callback: Callable, priority: int = 100, source_module_id: String = "") -> Result:
	if not callback.is_valid():
		return Result.failure("RulesetV2: sub_phase hook callback 无效")
	if sub_phase < 0 or sub_phase > PhaseDefsClass.WorkingSubPhase.PLACE_RESTAURANTS:
		return Result.failure("RulesetV2: sub_phase hook sub_phase 越界: %d" % sub_phase)
	if hook_type < 0 or hook_type > 3:
		return Result.failure("RulesetV2: sub_phase hook hook_type 越界: %d" % hook_type)
	sub_phase_hooks.append({
		"sub_phase": sub_phase,
		"hook_type": hook_type,
		"callback": callback,
		"priority": priority,
		"source": source_module_id,
	})
	return Result.success()

func register_named_sub_phase_hook(sub_phase_name: String, hook_type: int, callback: Callable, priority: int = 100, source_module_id: String = "") -> Result:
	if sub_phase_name.is_empty():
		return Result.failure("RulesetV2: named_sub_phase_hook sub_phase_name 不能为空")
	if not callback.is_valid():
		return Result.failure("RulesetV2: named_sub_phase_hook callback 无效")
	named_sub_phase_hooks.append({
		"sub_phase": sub_phase_name,
		"hook_type": hook_type,
		"callback": callback,
		"priority": int(priority),
		"source": source_module_id,
	})
	return Result.success()

func register_working_sub_phase_insertion(
	sub_phase_name: String,
	after_sub_phase_name: String,
	before_sub_phase_name: String,
	priority: int = 100,
	source_module_id: String = ""
) -> Result:
	return SubPhaseRegistrationHelperClass.register_working_sub_phase_insertion(
		self,
		sub_phase_name,
		after_sub_phase_name,
		before_sub_phase_name,
		priority,
		source_module_id
	)

func register_working_sub_phase_hook(
	sub_phase_name: String,
	hook_type: int,
	callback: Callable,
	priority: int = 100,
	source_module_id: String = ""
) -> Result:
	return SubPhaseRegistrationHelperClass.register_working_sub_phase_hook(
		self,
		sub_phase_name,
		hook_type,
		callback,
		priority,
		source_module_id
	)

func register_cleanup_sub_phase_insertion(
	sub_phase_name: String,
	after_sub_phase_name: String,
	before_sub_phase_name: String,
	priority: int = 100,
	source_module_id: String = ""
) -> Result:
	return SubPhaseRegistrationHelperClass.register_cleanup_sub_phase_insertion(
		self,
		sub_phase_name,
		after_sub_phase_name,
		before_sub_phase_name,
		priority,
		source_module_id
	)

func register_cleanup_sub_phase_hook(
	sub_phase_name: String,
	hook_type: int,
	callback: Callable,
	priority: int = 100,
	source_module_id: String = ""
) -> Result:
	return SubPhaseRegistrationHelperClass.register_cleanup_sub_phase_hook(
		self,
		sub_phase_name,
		hook_type,
		callback,
		priority,
		source_module_id
	)

func register_action_executor(executor, source_module_id: String = "") -> Result:
	return ActionRegistrationHelperClass.register_action_executor(self, executor, source_module_id)

func register_marketing_type(type_id: String, config: Dictionary, range_handler: Callable, source_module_id: String = "") -> Result:
	return ActionRegistrationHelperClass.register_marketing_type(self, type_id, config, range_handler, source_module_id)

func register_action_validator(action_id: String, validator_id: String, callback: Callable, priority: int = 100, source_module_id: String = "") -> Result:
	return ActionRegistrationHelperClass.register_action_validator(self, action_id, validator_id, callback, priority, source_module_id)

func register_global_action_validator(validator_id: String, callback: Callable, priority: int = 100, source_module_id: String = "") -> Result:
	return ActionRegistrationHelperClass.register_global_action_validator(self, validator_id, callback, priority, source_module_id)

func register_action_availability_override(action_id: String, points: Array, priority: int = 100, source_module_id: String = "") -> Result:
	return ActionRegistrationHelperClass.register_action_availability_override(self, action_id, points, priority, source_module_id)

func register_marketing_initiation_provider(provider_id: String, callback: Callable, priority: int = 100, source_module_id: String = "") -> Result:
	return ProviderRegistrationHelperClass.register_marketing_initiation_provider(self, provider_id, callback, priority, source_module_id)

func register_bankruptcy_handler(kind: String, callback: Callable, source_module_id: String = "") -> Result:
	return ProviderRegistrationHelperClass.register_bankruptcy_handler(self, kind, callback, source_module_id)

func register_dinnertime_demand_provider(provider_id: String, callback: Callable, priority: int = 100, source_module_id: String = "") -> Result:
	return ProviderRegistrationHelperClass.register_dinnertime_demand_provider(self, provider_id, callback, priority, source_module_id)

func register_dinnertime_route_purchase_provider(provider_id: String, callback: Callable, priority: int = 100, source_module_id: String = "") -> Result:
	return ProviderRegistrationHelperClass.register_dinnertime_route_purchase_provider(self, provider_id, callback, priority, source_module_id)

func register_state_initializer(initializer_id: String, callback: Callable, priority: int = 100, source_module_id: String = "") -> Result:
	return StateAndOrderHelperClass.register_state_initializer(self, initializer_id, callback, priority, source_module_id)

func apply_state_initializers(state: GameState, rng_manager = null) -> Result:
	return StateAndOrderHelperClass.apply_state_initializers(self, state, rng_manager)

func register_employee_pool_patch(patch_id: String, employee_id: String, delta: int, source_module_id: String = "") -> Result:
	return StateAndOrderHelperClass.register_employee_pool_patch(self, patch_id, employee_id, delta, source_module_id)

func register_phase_order_override(order_names: Array, priority: int = 100, source_module_id: String = "") -> Result:
	return StateAndOrderHelperClass.register_phase_order_override(self, order_names, priority, source_module_id)

func register_working_sub_phase_order_override(order_names: Array, priority: int = 100, source_module_id: String = "") -> Result:
	return StateAndOrderHelperClass.register_working_sub_phase_order_override(self, order_names, priority, source_module_id)

func register_cleanup_sub_phase_order_override(order_names: Array, priority: int = 100, source_module_id: String = "") -> Result:
	return StateAndOrderHelperClass.register_cleanup_sub_phase_order_override(self, order_names, priority, source_module_id)

func register_settlement_triggers_override(phase: int, timing: String, points: Array, priority: int = 100, source_module_id: String = "") -> Result:
	return StateAndOrderHelperClass.register_settlement_triggers_override(self, phase, timing, points, priority, source_module_id)

func register_phase_sub_phase_order_override(phase: int, order_names: Array, priority: int = 100, source_module_id: String = "") -> Result:
	return StateAndOrderHelperClass.register_phase_sub_phase_order_override(self, phase, order_names, priority, source_module_id)

func apply_hooks_to_phase_manager(phase_manager) -> Result:
	return PhaseHooksHelperClass.apply(self, phase_manager)

func validate_content_effect_handlers(catalog) -> Result:
	return ContentValidationHelperClass.validate_effect_handlers(self, catalog)

func validate_content_milestone_effect_handlers(catalog) -> Result:
	return ContentValidationHelperClass.validate_milestone_effect_handlers(self, catalog)

