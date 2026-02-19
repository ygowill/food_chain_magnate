# Game scene：调试面板控制器
# 负责：DebugPanel 的创建、显示/隐藏、命令执行信号绑定与引擎切换。
class_name GameDebugPanelController
extends RefCounted

var _host: Node = null
var _debug_panel_scene: PackedScene = null
var _get_game_engine: Callable = Callable()
var _on_debug_command_executed: Callable = Callable()
var _ui_sync_controller: Object = null

var _debug_panel: Window = null

func _init(
	host: Node,
	debug_panel_scene: PackedScene,
	get_game_engine: Callable,
	on_debug_command_executed: Callable,
	ui_sync_controller: Object
) -> void:
	_host = host
	_debug_panel_scene = debug_panel_scene
	_get_game_engine = get_game_engine
	_on_debug_command_executed = on_debug_command_executed
	_ui_sync_controller = ui_sync_controller

func dispose() -> void:
	_host = null
	_debug_panel_scene = null
	_get_game_engine = Callable()
	_on_debug_command_executed = Callable()
	_ui_sync_controller = null
	_debug_panel = null

func setup_debug_panel() -> void:
	if not DebugFlags.is_debug_mode():
		return
	if _debug_panel != null and is_instance_valid(_debug_panel):
		return
	if _debug_panel_scene == null:
		return

	_debug_panel = _debug_panel_scene.instantiate()
	if is_instance_valid(_host) and _host.has_method("add_child"):
		_host.add_child(_debug_panel)

	var engine_val = _get_game_engine.call() if _get_game_engine.is_valid() else null
	var game_engine: GameEngine = engine_val if engine_val is GameEngine else null
	if game_engine != null and _debug_panel.has_method("set_game_engine"):
		_debug_panel.call("set_game_engine", game_engine)
	_debug_panel.hide()

	# 连接命令执行信号以刷新 UI
	if _on_debug_command_executed.is_valid() and _debug_panel.has_signal("command_executed"):
		var sig := Signal(_debug_panel, &"command_executed")
		if not sig.is_connected(_on_debug_command_executed):
			sig.connect(_on_debug_command_executed)

	if is_instance_valid(_ui_sync_controller) and _ui_sync_controller.has_method("set_debug_panel"):
		_ui_sync_controller.call("set_debug_panel", _debug_panel)

func on_debug_panel_toggled(visible: bool) -> void:
	if not DebugFlags.is_debug_mode():
		if _debug_panel != null and is_instance_valid(_debug_panel):
			_debug_panel.hide()
		return

	if visible:
		if _debug_panel == null or not is_instance_valid(_debug_panel):
			_debug_panel = null
			setup_debug_panel()
		if _debug_panel != null and is_instance_valid(_debug_panel):
			_debug_panel.show()
			if _debug_panel.has_method("refresh_state"):
				_debug_panel.call("refresh_state")
	else:
		if _debug_panel != null and is_instance_valid(_debug_panel):
			_debug_panel.hide()

func set_game_engine(engine: GameEngine) -> void:
	if _debug_panel != null and is_instance_valid(_debug_panel) and _debug_panel.has_method("set_game_engine"):
		_debug_panel.call("set_game_engine", engine)
