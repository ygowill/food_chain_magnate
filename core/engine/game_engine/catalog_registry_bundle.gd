# 每局 catalog registry bundle（用于逐步替代 static 当前会话态）
class_name CatalogRegistryBundle
extends RefCounted

var product_defs: Dictionary = {}
var product_loaded: bool = false

var employee_defs: Dictionary = {}
var employee_loaded: bool = false

var marketing_defs: Dictionary = {}
var marketing_loaded: bool = false

var milestone_defs: Dictionary = {}
var milestone_loaded: bool = false

var tile_defs: Dictionary = {}
var tile_loaded: bool = false

var piece_defs: Dictionary = {}
var piece_loaded: bool = false

func clear() -> void:
	product_defs.clear()
	product_loaded = false

	employee_defs.clear()
	employee_loaded = false

	marketing_defs.clear()
	marketing_loaded = false

	milestone_defs.clear()
	milestone_loaded = false

	tile_defs.clear()
	tile_loaded = false

	piece_defs.clear()
	piece_loaded = false
