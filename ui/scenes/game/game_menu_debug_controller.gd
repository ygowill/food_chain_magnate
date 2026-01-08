# Game scene：菜单/调试控制器
# 负责：菜单按钮、保存/返回主菜单、调试窗口与调试文本刷新
class_name GameMenuDebugController
extends RefCounted

var _scene = null
var _menu_dialog = null
var _debug_dialog = null
var _debug_text = null

func _init(scene, menu_dialog, debug_dialog, debug_text) -> void:
	_scene = scene
	_menu_dialog = menu_dialog
	_debug_dialog = debug_dialog
	_debug_text = debug_text

func open_menu() -> void:
	GameLog.info("Game", "打开游戏菜单")
	if is_instance_valid(_menu_dialog):
		_menu_dialog.show()

func close_menu() -> void:
	if is_instance_valid(_menu_dialog):
		_menu_dialog.hide()

func resume() -> void:
	GameLog.info("Game", "继续游戏")
	close_menu()

func save_game() -> void:
	GameLog.info("Game", "保存游戏")
	if _scene == null:
		return
	var engine = _scene.game_engine
	if engine == null:
		GameLog.warn("Game", "游戏引擎未初始化，无法保存")
		close_menu()
		return

	var path := "user://savegame.json"
	var save_result = engine.save_to_file(path)
	if not save_result.ok:
		GameLog.error("Game", "保存失败: %s" % save_result.error)
	else:
		GameLog.info("Game", "已保存到: %s" % path)
	close_menu()

func quit_to_menu() -> void:
	GameLog.info("Game", "返回主菜单")
	Globals.reset_game_config()
	SceneManager.goto_main_menu()

func open_debug() -> void:
	GameLog.info("Game", "打开调试窗口")
	update_debug_text()
	if is_instance_valid(_debug_dialog):
		_debug_dialog.show()

func close_debug() -> void:
	if is_instance_valid(_debug_dialog):
		_debug_dialog.hide()

func sync_debug_text_if_visible() -> void:
	if is_instance_valid(_debug_dialog) and _debug_dialog.visible:
		update_debug_text()

func update_debug_text() -> void:
	if _scene == null:
		return
	if not is_instance_valid(_debug_text):
		return

	var engine = _scene.game_engine
	if engine == null:
		return
	var state = engine.get_state()

	var lines: Array[String] = []
	lines.append("round=%d phase=%s sub_phase=%s current_player=%d" % [
		state.round_number,
		state.phase,
		state.sub_phase,
		state.get_current_player_id(),
	])
	lines.append("")
	lines.append("bank=%s" % str(state.bank))
	lines.append("")
	lines.append("marketing_instances=%s" % str(state.marketing_instances))
	lines.append("")
	lines.append("round_state=%s" % str(state.round_state))

	_debug_text.text = "\n".join(lines)
