# game.tscn Smoke Test（Headless / Autorun）
# 目标：验证主游戏场景可加载、初始化完成，并能正常释放（避免脚本报错/节点路径漂移）。
extends Control

const GameScene: PackedScene = preload("res://ui/scenes/game/game.tscn")

@onready var output: RichTextLabel = $Root/Output
@onready var run_button: Button = $Root/TopBar/RunButton

var _exit_code: int = 0
var _game_instance: Node = null

func _ready() -> void:
	if is_instance_valid(output):
		output.clear()
		output.append_text("Game.tscn Smoke Test：加载 → 初始化 → 释放。\n")
		output.append_text("提示：CLI 可用 `-- --autorun` 自动执行并退出。\n")

	if _should_autorun():
		_exit_code = await _run_test()
		get_tree().quit(_exit_code)

func _on_back_pressed() -> void:
	SceneManager.go_back()

func _on_run_pressed() -> void:
	if is_instance_valid(run_button):
		run_button.disabled = true
	_exit_code = await _run_test()
	if is_instance_valid(run_button):
		run_button.disabled = false

func _run_test() -> int:
	if is_instance_valid(output):
		output.append_text("\n--- 开始测试 ---\n")
	print("[GameSmokeTest] START args=%s" % str(OS.get_cmdline_user_args()))

	if GameScene == null:
		return await _fail("预加载 game.tscn 失败（PackedScene 为空）")

	var inst = GameScene.instantiate()
	if inst == null:
		return await _fail("实例化 game.tscn 失败（instantiate 为空）")

	add_child(inst)
	_game_instance = inst

	# 等待若干帧，确保 _ready/_process_frame 已运行
	await get_tree().process_frame
	await get_tree().process_frame

	# 基本健康检查：Game.gd 初始化会写入 Globals.current_game_engine / is_game_active
	if Globals.current_game_engine == null:
		return await _fail("Globals.current_game_engine 为空（game 初始化失败或未完成）")
	if not bool(Globals.is_game_active):
		return await _fail("Globals.is_game_active 为 false（game 初始化失败或未完成）")

	await _cleanup()

	if is_instance_valid(output):
		output.append_text("PASS\n")
	print("[GameSmokeTest] PASS")
	return 0

func _cleanup() -> void:
	if is_instance_valid(_game_instance):
		_game_instance.queue_free()
		_game_instance = null
	await get_tree().process_frame
	Globals.reset_game_config()

func _fail(msg: String) -> int:
	if is_instance_valid(output):
		output.append_text("FAIL: %s\n" % msg)
	push_error("[GameSmokeTest] FAIL: %s" % msg)
	print("[GameSmokeTest] FAIL: %s" % msg)
	await _cleanup()
	return 1

func _should_autorun() -> bool:
	var args := OS.get_cmdline_user_args()
	if args.has("autorun") or args.has("--autorun"):
		return true
	return OS.has_feature("headless")

