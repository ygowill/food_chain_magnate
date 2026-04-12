# Setup 教学 target 回归测试
# 防止开局页结构调整后，导览无法定位玩家人数 / 游戏选项 / 模块区 / 开始按钮。
class_name SetupTutorialTargetsContractTest
extends RefCounted

const GameSetupScene: PackedScene = preload("res://ui/scenes/setup/game_setup.tscn")
const REQUIRED_VISIBLE_KEYS: Array[String] = [
	"player_count_section",
	"game_options_section",
	"first_time_option",
	"modules_section",
	"start_button",
]

static func run() -> Result:
	var tree := _get_tree()
	if tree == null or tree.root == null:
		return Result.failure("SceneTree.root 不可用")
	if GameSetupScene == null:
		return Result.failure("GameSetupScene preload 失败")

	var tutorial_snapshot := _capture_tutorial_settings()
	var setup = null

	_prepare_tutorial_flags_for_test()

	setup = GameSetupScene.instantiate()
	if setup == null or not is_instance_valid(setup):
		_restore_tutorial_settings(tutorial_snapshot)
		return Result.failure("实例化 game_setup.tscn 失败")

	tree.root.add_child(setup)
	var ctrl = await _wait_for_controller(setup, "_tutorials_controller", tree, 12)
	if ctrl == null:
		await _cleanup_node(setup, tree)
		_restore_tutorial_settings(tutorial_snapshot)
		return Result.failure("GameSetupTutorialsController 未创建")
	if not ctrl.has_method("get_tutorial_targets"):
		await _cleanup_node(setup, tree)
		_restore_tutorial_settings(tutorial_snapshot)
		return Result.failure("GameSetupTutorialsController 缺少 get_tutorial_targets")

	var targets := await _wait_for_targets(ctrl, REQUIRED_VISIBLE_KEYS, tree, 18)
	for key in REQUIRED_VISIBLE_KEYS:
		if not _is_visible_control(targets.get(key, null)):
			await _cleanup_node(setup, tree)
			_restore_tutorial_settings(tutorial_snapshot)
			return Result.failure("Setup tutorial target 缺失或不可见: %s" % key)

	await _cleanup_node(setup, tree)
	_restore_tutorial_settings(tutorial_snapshot)
	return Result.success({
		"keys": REQUIRED_VISIBLE_KEYS.size(),
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

static func _capture_tutorial_settings() -> Dictionary:
	return {
		"tutorial_enabled": Globals.tutorial_enabled,
		"tutorial_pending_game_ui_tour": Globals.tutorial_pending_game_ui_tour,
		"tutorial_pending_flow_tutorial": Globals.tutorial_pending_flow_tutorial,
	}

static func _prepare_tutorial_flags_for_test() -> void:
	Globals.tutorial_enabled = false
	Globals.tutorial_pending_game_ui_tour = false
	Globals.tutorial_pending_flow_tutorial = false

static func _restore_tutorial_settings(snapshot: Dictionary) -> void:
	Globals.tutorial_enabled = bool(snapshot.get("tutorial_enabled", true))
	Globals.tutorial_pending_game_ui_tour = bool(snapshot.get("tutorial_pending_game_ui_tour", false))
	Globals.tutorial_pending_flow_tutorial = bool(snapshot.get("tutorial_pending_flow_tutorial", false))

static func _cleanup_node(node: Node, tree: SceneTree) -> void:
	if node != null and is_instance_valid(node):
		node.queue_free()
	if tree != null:
		await tree.process_frame
		await tree.process_frame
