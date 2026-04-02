# GameOver：仅剩一名未弃权玩家时，应立刻弹出终局结算面板
extends RefCounted

const GameScene: PackedScene = preload("res://ui/scenes/game/game.tscn")
const TestPhaseUtilsClass = preload("res://core/tests/test_phase_utils.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")

static func run() -> Result:
	_clear_event_bus_history()
	if Globals != null:
		Globals.reset_game_config()

	var engine := GameEngine.new()
	var init_r := engine.initialize(2, 12345)
	if not init_r.ok:
		_clear_event_bus_history()
		return Result.failure("initialize 失败: %s" % init_r.error)
	var setup_r := TestPhaseUtilsClass.complete_setup(engine)
	if not setup_r.ok:
		_clear_event_bus_history()
		return Result.failure("complete_setup 失败: %s" % setup_r.error)

	if Globals != null:
		Globals.current_game_engine = engine
		Globals.is_game_active = true

	var tree_val = Engine.get_main_loop()
	var tree: SceneTree = tree_val if tree_val is SceneTree else null
	if tree == null or tree.root == null:
		_clear_event_bus_history()
		return Result.failure("SceneTree.root 不可用")
	if GameScene == null:
		_clear_event_bus_history()
		return Result.failure("GameScene preload 失败")

	var game = GameScene.instantiate()
	if game == null or not is_instance_valid(game):
		_clear_event_bus_history()
		return Result.failure("实例化 Game 失败")
	tree.root.add_child(game)

	await tree.process_frame
	await tree.process_frame
	await tree.process_frame

	var forfeit_r := engine.execute_command(Command.create("forfeit_player", 0, {}))
	if not forfeit_r.ok:
		_cleanup_game_node(game)
		_clear_event_bus_history()
		return Result.failure("forfeit_player 失败: %s" % forfeit_r.error)
	if game.has_method("_update_ui"):
		game.call("_update_ui")
	await tree.process_frame

	var state: GameState = engine.get_state()
	if state == null:
		_cleanup_game_node(game)
		_clear_event_bus_history()
		return Result.failure("forfeit 后 state 为空")
	if str(state.phase) != DefsClass.PHASE_GAME_OVER:
		_cleanup_game_node(game)
		_clear_event_bus_history()
		return Result.failure("应立刻进入 GameOver，实际: %s" % str(state.phase))

	var game_over_val = state.round_state.get("game_over", null) if state.round_state is Dictionary else null
	if not (game_over_val is Dictionary):
		_cleanup_game_node(game)
		_clear_event_bus_history()
		return Result.failure("缺少 round_state.game_over")
	var game_over: Dictionary = Dictionary(game_over_val)
	if str(game_over.get("reason", "")) != "last_player_standing":
		_cleanup_game_node(game)
		_clear_event_bus_history()
		return Result.failure("game_over.reason 错误: %s" % str(game_over))

	var panel := _find_node_by_name_recursive(game, "GameOverPanel")
	if panel == null:
		_cleanup_game_node(game)
		_clear_event_bus_history()
		return Result.failure("GameOverPanel 未创建")
	if panel is CanvasItem and not bool((panel as CanvasItem).visible):
		_cleanup_game_node(game)
		_clear_event_bus_history()
		return Result.failure("GameOverPanel 已创建但不可见")

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

static func _clear_event_bus_history() -> void:
	if EventBus == null:
		return
	if EventBus.has_method("clear_history_and_reset_sequence"):
		EventBus.clear_history_and_reset_sequence()
	elif EventBus.has_method("clear_history"):
		EventBus.clear_history()
