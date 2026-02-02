# Game scene：存档/回放选择控制器
# 负责：SaveLoadDialog 的生命周期与回调分发（保存/回放加载）
class_name GameSaveLoadController
extends RefCounted

var _scene = null
var _save_load_dialog_script: Script = null
var _save_load_dialog = null
var _context: String = ""
var _on_replay_selected: Callable = Callable()

func _init(scene, save_load_dialog_script: Script, on_replay_selected: Callable) -> void:
	_scene = scene
	_save_load_dialog_script = save_load_dialog_script
	_on_replay_selected = on_replay_selected

func open_for_save(engine: GameEngine) -> void:
	if engine == null:
		GameLog.warn("Game", "游戏引擎未初始化，无法打开存档对话框")
		return
	_ensure_dialog()
	_context = "save"
	if _save_load_dialog != null and is_instance_valid(_save_load_dialog):
		_save_load_dialog.open_for_save(engine)

func open_for_replay() -> void:
	_ensure_dialog()
	_context = "replay"
	if _save_load_dialog != null and is_instance_valid(_save_load_dialog):
		_save_load_dialog.open_for_replay()

func _ensure_dialog() -> void:
	if _save_load_dialog != null and is_instance_valid(_save_load_dialog):
		return
	if _scene == null:
		return
	if _save_load_dialog_script == null:
		return

	_save_load_dialog = _save_load_dialog_script.new()
	_scene.add_child(_save_load_dialog)

	if _save_load_dialog.has_signal("load_selected"):
		if not _save_load_dialog.load_selected.is_connected(_on_save_load_selected):
			_save_load_dialog.load_selected.connect(_on_save_load_selected)
	if _save_load_dialog.has_signal("save_completed"):
		if not _save_load_dialog.save_completed.is_connected(_on_save_completed):
			_save_load_dialog.save_completed.connect(_on_save_completed)

func _on_save_load_selected(path: String) -> void:
	if path.is_empty():
		return

	if _context == "replay":
		var cb := _on_replay_selected
		if cb.is_valid():
			cb.call(path)
		return

	# 预留：未来可支持“游戏内载入存档”
	GameLog.warn("Game", "未支持的存档载入上下文: %s (%s)" % [_context, path])

func _on_save_completed(path: String) -> void:
	if path.is_empty():
		return
	GameLog.info("Game", "存档已保存: %s" % path)

