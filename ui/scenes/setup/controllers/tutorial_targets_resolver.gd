# GameSetup scene：教学目标解析器
# 负责：
# - 解析 setup 导览所需的稳定 target 字典
# - 隔离 module selector 内部节点路径与主 controller
class_name GameSetupTutorialTargetsResolver
extends RefCounted

var _player_count_section: Control = null
var _modules_section: Control = null
var _start_button: Control = null
var _get_module_selector_tutorial_targets: Callable = Callable()

func _init(
	player_count_section: Control,
	modules_section: Control,
	start_button: Control,
	get_module_selector_tutorial_targets: Callable
) -> void:
	_player_count_section = player_count_section
	_modules_section = modules_section
	_start_button = start_button
	_get_module_selector_tutorial_targets = get_module_selector_tutorial_targets

func dispose() -> void:
	_player_count_section = null
	_modules_section = null
	_start_button = null
	_get_module_selector_tutorial_targets = Callable()

func get_targets() -> Dictionary:
	var module_targets := _get_module_targets()
	return {
		"player_count_section": _player_count_section,
		"game_options_section": module_targets.get("game_options_root", _modules_section),
		"first_time_option": module_targets.get("first_time_option", null),
		"modules_section": _modules_section,
		"start_button": _start_button,
	}

func _get_module_targets() -> Dictionary:
	if not _get_module_selector_tutorial_targets.is_valid():
		return {}
	var val = _get_module_selector_tutorial_targets.call()
	if val is Dictionary:
		return val
	return {}
