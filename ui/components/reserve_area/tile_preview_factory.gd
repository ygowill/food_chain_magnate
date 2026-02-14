# 为 ReserveArea 的 tile token 提供可选模块预览实例，避免 UI 硬编码模块目录。
extends RefCounted

const GameDefaultsClass = preload("res://core/engine/game_defaults.gd")
const ModuleDirSpecClass = preload("res://core/modules/v2/module_dir_spec.gd")
const ModulePackageLoaderClass = preload("res://core/modules/v2/module_package_loader.gd")

const _TARGET_MODULE_ID := "lobbyists"
const _TARGET_SCRIPT_SUBPATH := "ui/components/lobbyists_extra_tile/tile_preview.gd"

static var _tile_preview_script: Script = null
static var _tile_preview_script_loaded: bool = false

static func create_preview() -> Control:
	var script := _resolve_tile_preview_script()
	if script == null:
		return null
	var node = script.new()
	if node is Control:
		return node
	return null

static func _resolve_tile_preview_script() -> Script:
	if _tile_preview_script_loaded:
		return _tile_preview_script
	_tile_preview_script_loaded = true

	var base_dir_spec := ""
	if Globals != null:
		base_dir_spec = str(Globals.modules_v2_base_dir).strip_edges()
	if base_dir_spec.is_empty():
		base_dir_spec = str(GameDefaultsClass.DEFAULT_MODULES_V2_BASE_DIR).strip_edges()

	var base_dirs_read := ModuleDirSpecClass.parse_base_dirs(base_dir_spec)
	if not base_dirs_read.ok:
		return null
	var base_dirs: Array = base_dirs_read.value

	var root_read := ModulePackageLoaderClass.resolve_module_root(base_dirs, _TARGET_MODULE_ID)
	if not root_read.ok:
		return null
	var module_root := str(root_read.value).strip_edges()
	if module_root.is_empty():
		return null

	var script_path := module_root.path_join(_TARGET_SCRIPT_SUBPATH)
	var script_val = load(script_path)
	if script_val is Script:
		_tile_preview_script = script_val
	return _tile_preview_script
