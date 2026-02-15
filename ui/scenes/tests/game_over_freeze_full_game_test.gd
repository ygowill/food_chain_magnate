# GameOver：从完整 Game 场景触发终局不应卡死
# 覆盖手工复核用例：logs/event_log_game_over_bankruptcy.json
class_name GameOverFreezeFullGameTest
extends RefCounted

const GameScene: PackedScene = preload("res://ui/scenes/game/game.tscn")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const ActionIdsClass = preload("res://core/actions/action_ids.gd")

const SAVE_RES_PATH := "res://.savings/manual_cases/logs/event_log_game_over_bankruptcy.json"


static func run() -> Result:
	_clear_event_bus_history()

	if Globals != null:
		Globals.reset_game_config()

	var abs_path := ProjectSettings.globalize_path(SAVE_RES_PATH)
	var engine := GameEngine.new()
	var load := engine.load_from_file(abs_path)
	if not load.ok:
		_clear_event_bus_history()
		return Result.failure("load failed: %s" % load.error)
	if engine.get_state() == null:
		_clear_event_bus_history()
		return Result.failure("load succeeded but state is null")

	# 注入已加载的引擎，使 Game 场景复用它（避免 Game._initialize_game 覆盖配置）
	if Globals != null:
		Globals.current_game_engine = engine
		Globals.is_game_active = true

	var tree_val = Engine.get_main_loop()
	var tree: SceneTree = tree_val if tree_val is SceneTree else null
	if tree == null or tree.root == null:
		_clear_event_bus_history()
		return Result.failure("SceneTree.root is not available")

	if GameScene == null:
		_clear_event_bus_history()
		return Result.failure("preload game.tscn failed (PackedScene is null)")

	var game = GameScene.instantiate()
	if game == null:
		_clear_event_bus_history()
		return Result.failure("instantiate game.tscn failed (null)")

	tree.root.add_child(game)

	# 等待 Game._ready 初始化控制器（避免“命令控制器未就绪”）
	await tree.process_frame
	await tree.process_frame
	await tree.process_frame

	var state: GameState = engine.get_state()
	if state == null:
		_cleanup_game_node(game)
		_clear_event_bus_history()
		return Result.failure("state is null after game scene init")

	var actor_id := int(state.get_current_player_id())

	print("[GameOverFreezeFullGameTest] STEP skip_sub_phase")
	var skip_sub_r_val = game.call("_execute_command", Command.create(ActionIdsClass.SKIP_SUB_PHASE, actor_id))
	var skip_sub_r: Result = skip_sub_r_val if (skip_sub_r_val is Result) else null
	if skip_sub_r == null or not skip_sub_r.ok:
		_cleanup_game_node(game)
		_clear_event_bus_history()
		return Result.failure("skip_sub_phase failed: %s" % (skip_sub_r.error if skip_sub_r != null else "null result"))

	state = engine.get_state()
	if state == null:
		_cleanup_game_node(game)
		_clear_event_bus_history()
		return Result.failure("state is null after skip_sub_phase")
	actor_id = int(state.get_current_player_id())

	print("[GameOverFreezeFullGameTest] STEP skip")
	var skip_r_val = game.call("_execute_command", Command.create(ActionIdsClass.SKIP, actor_id))
	var skip_r: Result = skip_r_val if (skip_r_val is Result) else null
	if skip_r == null or not skip_r.ok:
		_cleanup_game_node(game)
		_clear_event_bus_history()
		return Result.failure("skip failed: %s" % (skip_r.error if skip_r != null else "null result"))

	state = engine.get_state()
	if state == null:
		_cleanup_game_node(game)
		_clear_event_bus_history()
		return Result.failure("state is null after skip")
	if str(state.phase) != DefsClass.PHASE_GAME_OVER:
		_cleanup_game_node(game)
		_clear_event_bus_history()
		return Result.failure("expected phase=%s; got %s" % [DefsClass.PHASE_GAME_OVER, str(state.phase)])

	# 等待一帧，给 UI 同步/弹窗创建机会（避免误判）
	await tree.process_frame

	var panel := _find_node_by_name_recursive(game, "GameOverPanel")
	if panel == null:
		_cleanup_game_node(game)
		_clear_event_bus_history()
		return Result.failure("GameOverPanel not found in game scene tree")
	if panel is CanvasItem and not bool((panel as CanvasItem).visible):
		_cleanup_game_node(game)
		_clear_event_bus_history()
		return Result.failure("GameOverPanel found but not visible")

	_cleanup_game_node(game)
	_clear_event_bus_history()
	if Globals != null:
		Globals.reset_game_config()
	return Result.success()


static func _find_node_by_name_recursive(root: Node, target_name: String) -> Node:
	if root == null or not is_instance_valid(root):
		return null
	if str(root.name) == target_name:
		return root
	for ch in root.get_children():
		if not (ch is Node):
			continue
		var found := _find_node_by_name_recursive(ch as Node, target_name)
		if found != null:
			return found
	return null

static func _cleanup_game_node(game: Node) -> void:
	if game == null or not is_instance_valid(game):
		return
	game.queue_free()
	# 不 await：调用方已处于测试流程中，依赖外层 drain frames 即可。

static func _clear_event_bus_history() -> void:
	if EventBus == null:
		return
	if EventBus.has_method("clear_history_and_reset_sequence"):
		EventBus.clear_history_and_reset_sequence()
	elif EventBus.has_method("clear_history"):
		EventBus.clear_history()

