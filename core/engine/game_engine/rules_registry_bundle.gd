# 每局 rules registry bundle（用于逐步替代 static 当前会话态）
class_name RulesRegistryBundle
extends RefCounted

var marketing_types: Dictionary = {}
var marketing_type_loaded: bool = false

var bankruptcy_first_break_handler: Callable = Callable()
var bankruptcy_first_break_source: String = ""
var bankruptcy_loaded: bool = false

func clear() -> void:
	marketing_types.clear()
	marketing_type_loaded = false

	bankruptcy_first_break_handler = Callable()
	bankruptcy_first_break_source = ""
	bankruptcy_loaded = false
