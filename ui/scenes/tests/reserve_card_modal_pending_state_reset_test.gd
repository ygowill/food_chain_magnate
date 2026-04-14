# ReserveCard modal：延迟打开流程若中途失效，不应永久残留 blocking modal 状态
class_name ReserveCardModalPendingStateResetTest
extends RefCounted

const ControllerClass = preload("res://ui/scenes/game/panel/modals_controller.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")


class _DummyEngine extends RefCounted:
	var state: GameState = null

	func get_state() -> GameState:
		return state


class _DummyScene extends Control:
	var game_engine = null

	func _ensure_game_menu_closed_for_blocking_modal() -> void:
		pass


static func run() -> Result:
	var tree_val = Engine.get_main_loop()
	var tree: SceneTree = tree_val if tree_val is SceneTree else null
	if tree == null or tree.root == null:
		return Result.failure("SceneTree.root 不可用")

	var engine := GameEngine.new()
	var init_r := engine.initialize(2, 12345)
	if not init_r.ok:
		return Result.failure("initialize 失败: %s" % init_r.error)

	var state: GameState = engine.get_state()
	state.phase = DefsClass.PHASE_SETUP
	state.sub_phase = DefsClass.SUB_PHASE_RESERVE_CARDS
	state.turn_order = [0, 1]
	state.current_player_index = 0

	var dummy_engine := _DummyEngine.new()
	dummy_engine.state = state
	var scene := _DummyScene.new()
	scene.game_engine = dummy_engine
	tree.root.add_child(scene)
	await tree.process_frame

	var controller = ControllerClass.new(scene, Callable())
	var modal := Control.new()
	modal.visible = false
	scene.add_child(modal)
	await tree.process_frame

	controller._reserve_card_modal = modal
	controller._pending_reserve_card_open_player_id = 1
	controller._pending_reserve_card_open_interactive = true
	controller._pending_reserve_card_open_attempts = 0
	controller._reserve_card_open_routine_running = true

	await controller._deferred_open_reserve_card_modal()

	if controller.has_open_modal_ui():
		_cleanup(scene)
		return Result.failure("deferred reserve-card open 中断后不应残留 blocking modal 状态")
	if int(controller._pending_reserve_card_open_player_id) != -1:
		_cleanup(scene)
		return Result.failure("pending_reserve_card_open_player_id 未清理: %d" % int(controller._pending_reserve_card_open_player_id))
	if bool(controller._reserve_card_open_routine_running):
		_cleanup(scene)
		return Result.failure("reserve_card_open_routine_running 未清理")

	_cleanup(scene)
	return Result.success({})


static func _cleanup(scene: Node) -> void:
	if scene != null and is_instance_valid(scene):
		scene.queue_free()
