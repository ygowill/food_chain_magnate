# 场景管理器
# 负责场景切换、过渡动画和场景栈管理
extends Node

# 信号
signal scene_changing(from_scene: String, to_scene: String)
signal scene_changed(scene_name: String)

# 场景路径常量
const SCENE_MAIN_MENU := "res://ui/scenes/main_menu.tscn"
const SCENE_GAME_SETUP := "res://ui/scenes/setup/game_setup.tscn"
const SCENE_GAME := "res://ui/scenes/game/game.tscn"
const SCENE_TILE_EDITOR := "res://ui/scenes/tools/tile_editor.tscn"
const SCENE_REPLAY_TEST := "res://ui/scenes/tests/replay_test.tscn"

# 当前场景
var current_scene: Node = null
var current_scene_path: String = ""

# 场景栈（用于返回）
var scene_stack: Array[String] = []

func _ready() -> void:
	# 获取当前场景
	var root := get_tree().root
	current_scene = root.get_child(root.get_child_count() - 1)
	GameLog.info("SceneManager", "场景管理器初始化完成")

# 切换场景
func goto_scene(path: String, push_to_stack: bool = true) -> void:
	GameLog.info("SceneManager", "切换场景: %s -> %s" % [current_scene_path, path])

	# 发射信号
	scene_changing.emit(current_scene_path, path)

	# 添加到栈
	if push_to_stack and not current_scene_path.is_empty():
		scene_stack.append(current_scene_path)

	# 延迟切换，确保当前帧完成
	call_deferred("_deferred_goto_scene", path)

func _deferred_goto_scene(path: String) -> void:
	# 释放当前场景
	if current_scene:
		current_scene.free()

	# 加载新场景
	var packed_scene := ResourceLoader.load(path) as PackedScene
	if packed_scene == null:
		GameLog.error("SceneManager", "无法加载场景: %s" % path)
		return

	current_scene = packed_scene.instantiate()
	current_scene_path = path

	# 添加到场景树
	get_tree().root.add_child(current_scene)
	get_tree().current_scene = current_scene

	# 发射信号
	scene_changed.emit(path)
	GameLog.info("SceneManager", "场景加载完成: %s" % path)

# 返回上一个场景
func go_back() -> bool:
	if scene_stack.is_empty():
		GameLog.warn("SceneManager", "场景栈为空，无法返回")
		return false

	var previous_scene = scene_stack.pop_back()
	goto_scene(previous_scene, false)
	return true

# 清空场景栈
func clear_stack() -> void:
	scene_stack.clear()

# 便捷方法
func goto_main_menu() -> void:
	clear_stack()
	goto_scene(SCENE_MAIN_MENU, false)

func goto_game_setup() -> void:
	goto_scene(SCENE_GAME_SETUP)

func goto_game() -> void:
	goto_scene(SCENE_GAME)

func goto_tile_editor() -> void:
	goto_scene(SCENE_TILE_EDITOR)

func goto_replay_test() -> void:
	goto_scene(SCENE_REPLAY_TEST)

# 重新加载当前场景
func reload_current_scene() -> void:
	if not current_scene_path.is_empty():
		goto_scene(current_scene_path, false)

# 获取当前场景名称
func get_current_scene_name() -> String:
	return current_scene_path.get_file().get_basename()

# 检查是否可以返回
func can_go_back() -> bool:
	return not scene_stack.is_empty()
