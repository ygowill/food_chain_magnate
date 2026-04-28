# Game 教学 target 回归测试
# 防止主界面 / 重组弹窗 / 顺位弹窗结构调整后，导览失去聚焦目标。
class_name GameTutorialTargetsContractTest
extends RefCounted

const GameScene: PackedScene = preload("res://ui/scenes/game/game.tscn")
const RestructuringModalScene: PackedScene = preload("res://ui/components/modal_panel/restructuring_modal.tscn")
const TurnOrderSelectionModalScene: PackedScene = preload("res://ui/components/modal_panel/turn_order_selection_modal.tscn")
const GameTutorialTargetsResolverClass = preload("res://ui/scenes/game/controllers/tutorial_targets_resolver.gd")

const REQUIRED_MAIN_KEYS: Array[String] = [
	"status_bar",
	"map_view",
	"action_panel",
	"left_player_overview",
	"left_inventory_section",
	"left_employee_scroll",
	"left_milestones_section",
	"toolbar",
	"toolbar_employee_tree_button",
	"toolbar_log_button",
	"toolbar_milestones_button",
	"toolbar_reserve_area_button",
	"toolbar_reserve_cards_button",
	"toolbar_distance_button",
]

const REQUIRED_STATIC_KEYS: Array[String] = [
	"action_panel_context_panel",
	"action_panel_rotation_row",
	"turn_order_track",
]

const REQUIRED_RESTRUCTURING_KEYS: Array[String] = [
	"restructuring_player_buttons",
	"restructuring_hand_host",
	"restructuring_company_host",
	"restructuring_button_row",
]

const REQUIRED_TURN_ORDER_KEYS: Array[String] = [
	"turn_order_modal_selection_label",
	"turn_order_modal_display",
]

static func run() -> Result:
	var tree := _get_tree()
	if tree == null or tree.root == null:
		return Result.failure("SceneTree.root 不可用")
	if GameScene == null:
		return Result.failure("GameScene preload 失败")
	if RestructuringModalScene == null:
		return Result.failure("RestructuringModalScene preload 失败")
	if TurnOrderSelectionModalScene == null:
		return Result.failure("TurnOrderSelectionModalScene preload 失败")

	var tutorial_snapshot := _capture_tutorial_settings()
	var game = null
	var restructuring_modal = null
	var turn_order_modal = null
	var engine := GameEngine.new()

	_prepare_globals_for_test()

	var init_r := engine.initialize(2, 12345)
	if not init_r.ok:
		_restore_tutorial_settings(tutorial_snapshot)
		if engine.has_method("dispose"):
			engine.dispose()
		return Result.failure("GameEngine.initialize 失败: %s" % init_r.error)

	Globals.set_current_game_engine(engine)

	game = GameScene.instantiate()
	if game == null or not is_instance_valid(game):
		Globals.reset_game_config()
		_restore_tutorial_settings(tutorial_snapshot)
		return Result.failure("实例化 game.tscn 失败")
	tree.root.add_child(game)

	var ctrl = await _wait_for_controller(game, "_tutorials_controller", tree, 12)
	if ctrl == null:
		await _cleanup_nodes([game], tree)
		Globals.reset_game_config()
		_restore_tutorial_settings(tutorial_snapshot)
		return Result.failure("GameTutorialsController 未创建")
	if not ctrl.has_method("get_tutorial_targets"):
		await _cleanup_nodes([game], tree)
		Globals.reset_game_config()
		_restore_tutorial_settings(tutorial_snapshot)
		return Result.failure("GameTutorialsController 缺少 get_tutorial_targets")

	var targets := await _wait_for_targets(ctrl, REQUIRED_MAIN_KEYS, tree, 18)
	for key in REQUIRED_MAIN_KEYS:
		if not _is_visible_control(targets.get(key, null)):
			await _cleanup_nodes([game], tree)
			Globals.reset_game_config()
			_restore_tutorial_settings(tutorial_snapshot)
			return Result.failure("Game tutorial main target 缺失或不可见: %s" % key)
	for key in REQUIRED_STATIC_KEYS:
		if not _is_control(targets.get(key, null)):
			await _cleanup_nodes([game], tree)
			Globals.reset_game_config()
			_restore_tutorial_settings(tutorial_snapshot)
			return Result.failure("Game tutorial static target 缺失: %s" % key)

	restructuring_modal = RestructuringModalScene.instantiate()
	if restructuring_modal == null or not is_instance_valid(restructuring_modal):
		await _cleanup_nodes([game], tree)
		Globals.reset_game_config()
		_restore_tutorial_settings(tutorial_snapshot)
		return Result.failure("实例化 restructuring_modal.tscn 失败")
	tree.root.add_child(restructuring_modal)
	await tree.process_frame

	turn_order_modal = TurnOrderSelectionModalScene.instantiate()
	if turn_order_modal == null or not is_instance_valid(turn_order_modal):
		await _cleanup_nodes([restructuring_modal, game], tree)
		Globals.reset_game_config()
		_restore_tutorial_settings(tutorial_snapshot)
		return Result.failure("实例化 turn_order_selection_modal.tscn 失败")
	tree.root.add_child(turn_order_modal)
	await tree.process_frame

	var resolver = GameTutorialTargetsResolverClass.new(
		game.get("status_bar"),
		game.get("map_view"),
		game.get("action_panel"),
		game.get("left_panel"),
		game.get("toolbar"),
		game.get("turn_order_track"),
		func():
			return restructuring_modal,
		func():
			return turn_order_modal,
		Callable(),
		Callable()
	)
	var modal_targets: Dictionary = resolver.get_targets()
	for key in REQUIRED_RESTRUCTURING_KEYS:
		if not _is_control(modal_targets.get(key, null)):
			if resolver.has_method("dispose"):
				resolver.dispose()
			await _cleanup_nodes([turn_order_modal, restructuring_modal, game], tree)
			Globals.reset_game_config()
			_restore_tutorial_settings(tutorial_snapshot)
			return Result.failure("Game tutorial restructuring target 缺失: %s" % key)
	for key in REQUIRED_TURN_ORDER_KEYS:
		if not _is_control(modal_targets.get(key, null)):
			if resolver.has_method("dispose"):
				resolver.dispose()
			await _cleanup_nodes([turn_order_modal, restructuring_modal, game], tree)
			Globals.reset_game_config()
			_restore_tutorial_settings(tutorial_snapshot)
			return Result.failure("Game tutorial turn order target 缺失: %s" % key)

	if resolver.has_method("dispose"):
		resolver.dispose()
	await _cleanup_nodes([turn_order_modal, restructuring_modal, game], tree)
	Globals.reset_game_config()
	_restore_tutorial_settings(tutorial_snapshot)
	return Result.success({
		"main_keys": REQUIRED_MAIN_KEYS.size(),
		"static_keys": REQUIRED_STATIC_KEYS.size(),
		"restructuring_keys": REQUIRED_RESTRUCTURING_KEYS.size(),
		"turn_order_keys": REQUIRED_TURN_ORDER_KEYS.size(),
	})

static func _get_tree() -> SceneTree:
	var loop = Engine.get_main_loop()
	if loop is SceneTree:
		return loop as SceneTree
	return null

static func _wait_for_controller(host: Node, property_name: String, tree: SceneTree, max_frames: int):
	for _i in range(maxi(1, max_frames)):
		if host != null and is_instance_valid(host):
			var ctrl = host.get(property_name)
			if ctrl != null:
				return ctrl
		await tree.process_frame
	return host.get(property_name) if host != null and is_instance_valid(host) else null

static func _wait_for_targets(ctrl, required_keys: Array[String], tree: SceneTree, max_frames: int) -> Dictionary:
	for _i in range(maxi(1, max_frames)):
		var targets = ctrl.call("get_tutorial_targets")
		if targets is Dictionary and _has_visible_targets(targets, required_keys):
			return targets
		await tree.process_frame
	var last_targets = ctrl.call("get_tutorial_targets")
	if last_targets is Dictionary:
		return last_targets
	return {}

static func _has_visible_targets(targets: Dictionary, required_keys: Array[String]) -> bool:
	for key in required_keys:
		if not _is_visible_control(targets.get(key, null)):
			return false
	return true

static func _is_visible_control(target) -> bool:
	if not (target is Control):
		return false
	var control: Control = target
	return is_instance_valid(control) and control.is_visible_in_tree()

static func _is_control(target) -> bool:
	if not (target is Control):
		return false
	return is_instance_valid(target)

static func _capture_tutorial_settings() -> Dictionary:
	return {
		"tutorial_enabled": Globals.tutorial_enabled,
		"tutorial_setup_tour_seen": Globals.tutorial_setup_tour_seen,
		"tutorial_game_ui_tour_seen": Globals.tutorial_game_ui_tour_seen,
		"tutorial_pending_game_ui_tour": Globals.tutorial_pending_game_ui_tour,
		"tutorial_pending_flow_tutorial": Globals.tutorial_pending_flow_tutorial,
		"tutorial_match_enabled": Globals.tutorial_match_enabled,
	}

static func _prepare_globals_for_test() -> void:
	Globals.tutorial_enabled = false
	Globals.tutorial_setup_tour_seen = true
	Globals.tutorial_game_ui_tour_seen = true
	Globals.tutorial_pending_game_ui_tour = false
	Globals.tutorial_pending_flow_tutorial = false
	Globals.tutorial_match_enabled = false

static func _restore_tutorial_settings(snapshot: Dictionary) -> void:
	Globals.tutorial_enabled = bool(snapshot.get("tutorial_enabled", true))
	Globals.tutorial_setup_tour_seen = bool(snapshot.get("tutorial_setup_tour_seen", false))
	Globals.tutorial_game_ui_tour_seen = bool(snapshot.get("tutorial_game_ui_tour_seen", false))
	Globals.tutorial_pending_game_ui_tour = bool(snapshot.get("tutorial_pending_game_ui_tour", false))
	Globals.tutorial_pending_flow_tutorial = bool(snapshot.get("tutorial_pending_flow_tutorial", false))
	Globals.tutorial_match_enabled = bool(snapshot.get("tutorial_match_enabled", false))

static func _cleanup_nodes(nodes: Array, tree: SceneTree) -> void:
	for node in nodes:
		if node != null and is_instance_valid(node):
			node.queue_free()
	if tree != null:
		await tree.process_frame
		await tree.process_frame
		await tree.process_frame
