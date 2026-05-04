class_name GamePanelControllerPartialModalSyncTest
extends RefCounted

const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const GamePanelControllerClass = preload("res://ui/scenes/game/panel/controller.gd")
const GameStateClass = preload("res://core/state/game_state.gd")

class _FakeScene:
	extends Node

	var action_panel = null
	var action_flow_controls = null
	var game_engine = null

class _ActionPanelSpy:
	extends RefCounted

	func is_globally_disabled() -> bool:
		return false

class _ModalsControllerSpy:
	extends RefCounted

	var sync_for_state_calls: int = 0
	var last_phase: String = ""
	var last_cover: Rect2 = Rect2()

	func get_modal_cover_rect() -> Rect2:
		return Rect2(Vector2(10, 20), Vector2(300, 200))

	func sync_for_state(state: GameState, covered: Rect2) -> void:
		sync_for_state_calls += 1
		last_phase = str(state.phase) if state != null else ""
		last_cover = covered

	func has_dismissed_reserve_card_modal() -> bool:
		return false

class _RestructuringControllerSpy:
	extends RefCounted

	var sync_modal_calls: int = 0

	func sync_modal(_state: GameState, _covered: Rect2, requested_view_player_id: int) -> int:
		sync_modal_calls += 1
		return requested_view_player_id

	func has_dismissed_restructuring_modal(_state: GameState) -> bool:
		return false

static func run() -> Result:
	var scene := _FakeScene.new()
	scene.action_panel = _ActionPanelSpy.new()

	var controller = GamePanelControllerClass.new(scene, null, null, Callable(), Callable())
	controller._ui_components_binder = null
	controller._views_controller = null
	controller._working_panels = null
	controller._marketing_panels = null
	controller._placement_overlays = null
	controller._end_panels = null

	var modals := _ModalsControllerSpy.new()
	var restructuring := _RestructuringControllerSpy.new()
	controller._modals_controller = modals
	controller._restructuring_controller = restructuring

	var state := _build_order_of_business_state()
	controller.sync_action_state(state, false)

	if modals.sync_for_state_calls != 1:
		return _finish(
			Result.failure("partial sync_action_state 应同步 modal 进度，实际=%d" % modals.sync_for_state_calls),
			controller,
			scene
		)
	if modals.last_phase != DefsClass.PHASE_ORDER_OF_BUSINESS:
		return _finish(
			Result.failure("modal sync 收到的 phase 错误，实际=%s" % modals.last_phase),
			controller,
			scene
		)
	if modals.last_cover.position != Vector2(10, 20) or modals.last_cover.size != Vector2(300, 200):
		return _finish(
			Result.failure("modal sync 未使用 modals_controller 的 cover rect，实际=%s" % str(modals.last_cover)),
			controller,
			scene
		)
	if restructuring.sync_modal_calls != 1:
		return _finish(
			Result.failure("partial sync_action_state 应同步 restructuring modal，实际=%d" % restructuring.sync_modal_calls),
			controller,
			scene
		)

	return _finish(Result.success({}), controller, scene)

static func _build_order_of_business_state() -> GameState:
	var state := GameStateClass.new()
	state.players = [{}, {}]
	state.phase = DefsClass.PHASE_ORDER_OF_BUSINESS
	state.turn_order = [0, 1]
	state.current_player_index = 1
	state.round_state = {
		"order_of_business": {
			"picks": [0, -1],
			"finalized": false,
			"previous_turn_order": [0, 1],
		}
	}
	return state

static func _finish(result: Result, controller, scene: Node) -> Result:
	if controller != null and controller.has_method("dispose"):
		controller.dispose()
	if scene != null and is_instance_valid(scene):
		scene.free()
	return result
