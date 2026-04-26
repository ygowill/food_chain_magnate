# UI helper: resolve modules v2 base_dir (supports ';' separated dirs).
class_name ModulesBaseDir
extends RefCounted

const GameDefaultsClass = preload("res://core/engine/game_defaults.gd")
const ModuleDirSpecClass = preload("res://core/modules/v2/module_dir_spec.gd")

static func get_base_dir() -> String:
	var base_dir := ""
	var tree = Engine.get_main_loop()
	if tree is SceneTree:
		var globals = (tree as SceneTree).root.get_node_or_null("Globals")
		if globals != null:
			base_dir = str(globals.get("modules_v2_base_dir")).strip_edges()
	if base_dir.is_empty():
		base_dir = str(GameDefaultsClass.DEFAULT_MODULES_V2_BASE_DIR).strip_edges()
	return ModuleDirSpecClass.primary_base_dir(base_dir, GameDefaultsClass.DEFAULT_MODULES_V2_BASE_DIR)
