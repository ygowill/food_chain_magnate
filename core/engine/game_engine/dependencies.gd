# GameEngine 显式依赖容器（逐步替代 ProjectSettings / autoload 隐式注入）
class_name GameEngineDependencies
extends RefCounted

var action_setup_provider = null
var command_runner_event_build_provider = null

func clear() -> void:
	action_setup_provider = null
	command_runner_event_build_provider = null
