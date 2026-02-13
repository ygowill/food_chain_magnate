# UI helper: resolve modules v2 base_dir (supports ';' separated dirs).
class_name ModulesBaseDir
extends RefCounted

const GameDefaultsClass = preload("res://core/engine/game_defaults.gd")
const ModuleDirSpecClass = preload("res://core/modules/v2/module_dir_spec.gd")

static func get_base_dir() -> String:
	var base_dir := ""
	if Globals != null:
		base_dir = str(Globals.modules_v2_base_dir).strip_edges()
	if base_dir.is_empty():
		base_dir = str(GameDefaultsClass.DEFAULT_MODULES_V2_BASE_DIR).strip_edges()
	return ModuleDirSpecClass.primary_base_dir(base_dir, GameDefaultsClass.DEFAULT_MODULES_V2_BASE_DIR)
