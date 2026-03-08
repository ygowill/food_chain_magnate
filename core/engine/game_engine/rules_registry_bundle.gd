# 每局 rules registry bundle（用于逐步替代 static 当前会话态）
class_name RulesRegistryBundle
extends RefCounted

var marketing_types: Dictionary = {}
var marketing_type_loaded: bool = false

var bankruptcy_first_break_handler: Callable = Callable()
var bankruptcy_first_break_source: String = ""
var bankruptcy_loaded: bool = false

var marketing_initiation_providers: Array = []
var marketing_initiation_loaded: bool = false

var placement_conflict_providers: Array = []
var placement_conflict_loaded: bool = false

var range_origin_providers: Array = []
var range_origin_loaded: bool = false

var employee_pool_patches: Array = []
var employee_pool_patch_loaded: bool = false

var dinnertime_route_purchase_providers: Array = []
var dinnertime_route_purchase_loaded: bool = false

var dinnertime_demand_providers: Array = []
var dinnertime_demand_loaded: bool = false

var state_int_key_dict_schemas: Array = []
var state_schema_loaded: bool = false

func clear() -> void:
	marketing_types.clear()
	marketing_type_loaded = false

	bankruptcy_first_break_handler = Callable()
	bankruptcy_first_break_source = ""
	bankruptcy_loaded = false

	marketing_initiation_providers = []
	marketing_initiation_loaded = false

	placement_conflict_providers = []
	placement_conflict_loaded = false

	range_origin_providers = []
	range_origin_loaded = false

	employee_pool_patches = []
	employee_pool_patch_loaded = false

	dinnertime_route_purchase_providers = []
	dinnertime_route_purchase_loaded = false

	dinnertime_demand_providers = []
	dinnertime_demand_loaded = false

	state_int_key_dict_schemas = []
	state_schema_loaded = false
