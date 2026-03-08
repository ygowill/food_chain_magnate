# GameEngine 显式依赖容器（逐步替代 ProjectSettings / autoload 隐式注入）
class_name GameEngineDependencies
extends RefCounted

var action_setup_provider = null
var command_runner_event_build_provider = null
var restaurant_logo_assignment_provider = null
var game_config_overrides = null
var game_option_overrides = null
var command_runner_debug_options = null
var event_sink = null

func clear() -> void:
	action_setup_provider = null
	command_runner_event_build_provider = null
	restaurant_logo_assignment_provider = null
	game_config_overrides = null
	game_option_overrides = null
	command_runner_debug_options = null
	event_sink = null
