# 每局 rules registry bundle（用于逐步替代 static 当前会话态）
class_name RulesRegistryBundle
extends RefCounted

var marketing_types: Dictionary = {}
var marketing_type_loaded: bool = false

func clear() -> void:
	marketing_types.clear()
	marketing_type_loaded = false
