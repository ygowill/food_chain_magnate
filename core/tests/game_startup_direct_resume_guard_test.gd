# Game 场景：冷启动直达恢复时不应先初始化本地对局
class_name GameStartupDirectResumeGuardTest
extends RefCounted

const GameScript = preload("res://ui/scenes/game/game.gd")
const GameEngineClass = preload("res://core/engine/game_engine.gd")
const GameDefaultsClass = preload("res://core/engine/game_defaults.gd")

static func run() -> Result:
	if Globals == null:
		return Result.failure("Globals autoload missing")

	var prev_engine = Globals.current_game_engine
	var prev_is_game_active := bool(Globals.is_game_active)
	var game = GameScript.new()

	Globals.current_game_engine = null
	Globals.is_game_active = false
	if not bool(game.call("_should_defer_local_game_init", true)):
		_safe_free(game)
		return _restore_and_fail(prev_engine, prev_is_game_active, "startup_direct_resume=true 时应跳过本地初始化")
	if bool(game.call("_should_defer_local_game_init", false)):
		_safe_free(game)
		return _restore_and_fail(prev_engine, prev_is_game_active, "普通进入 Game 时不应跳过本地初始化")

	var engine = GameEngineClass.new()
	var init_r: Result = engine.initialize(2, 12345, [], GameDefaultsClass.DEFAULT_MODULES_V2_BASE_DIR, [], [-1, -1])
	if not init_r.ok:
		_safe_free(game)
		return _restore_and_fail(prev_engine, prev_is_game_active, "初始化测试 engine 失败: %s" % init_r.error)
	Globals.set_current_game_engine(engine)
	if bool(game.call("_should_defer_local_game_init", true)):
		engine.dispose()
		_safe_free(game)
		return _restore_and_fail(prev_engine, prev_is_game_active, "已有有效 engine 时不应继续跳过初始化分支")

	engine.dispose()
	_safe_free(game)
	_restore(prev_engine, prev_is_game_active)
	return Result.success()

static func _restore(prev_engine, prev_is_game_active: bool) -> void:
	Globals.current_game_engine = prev_engine
	Globals.is_game_active = prev_is_game_active

static func _restore_and_fail(prev_engine, prev_is_game_active: bool, message: String) -> Result:
	_restore(prev_engine, prev_is_game_active)
	return Result.failure(message)

static func _safe_free(node) -> void:
	if node == null or not is_instance_valid(node):
		return
	if node is Node:
		(node as Node).free()
