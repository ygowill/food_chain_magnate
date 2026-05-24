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
	var right_panel_sync_calls: int = 0

	func _sync_right_panel_docked_view() -> void:
		right_panel_sync_calls += 1

class _ActionPanelSpy:
	extends RefCounted

	var _enabled_by_action: Dictionary = {}

	func _init(enabled_by_action: Dictionary = {}) -> void:
		_enabled_by_action = enabled_by_action.duplicate()

	func is_globally_disabled() -> bool:
		return false

	func get_action_enabled(action_id: String) -> bool:
		return bool(_enabled_by_action.get(str(action_id).strip_edges(), true))

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

class _PhasePanelSyncSpy:
	extends RefCounted

	var sync_calls: int = 0
	var last_force_refresh: bool = false
	var recruit_panel = null
	var train_panel = null
	var price_panel = null
	var production_panel = null
	var milestone_panel = null
	var marketing_panel = null
	var restaurant_placement_overlay = null
	var house_placement_overlay = null
	var piece_placement_overlay = null
	var payday_panel = null

	func sync(_state: GameState, force_full_refresh: bool = false) -> void:
		sync_calls += 1
		last_force_refresh = bool(force_full_refresh)

	func get_active_context_overlay():
		return null

class _PanelSpy:
	extends RefCounted

	var visible: bool = true
	var _action_id: String = ""
	var _mode: String = ""

	func _init(action_id: String = "", mode: String = "") -> void:
		_action_id = action_id
		_mode = mode

	func get_action_id() -> String:
		return _action_id

	func get_mode() -> String:
		return _mode

class _WorkingPanelsSpy:
	extends RefCounted

	var sync_calls: int = 0
	var recruit_panel = null
	var train_panel = null
	var production_panel = null
	var price_panel = null

	func sync(_state: GameState, _force_full_refresh: bool = false) -> void:
		sync_calls += 1

class _PlacementOverlaysSpy:
	extends RefCounted

	var sync_calls: int = 0
	var restaurant_placement_overlay = null
	var house_placement_overlay = null
	var piece_placement_overlay = null

	func sync(_state: GameState, _force_full_refresh: bool = false) -> void:
		sync_calls += 1

	func get_active_context_overlay():
		return null

static func run() -> Result:
	var hide_r := _case_hides_non_initiatable_visible_action_surfaces()
	if not hide_r.ok:
		return hide_r

	var scene := _FakeScene.new()
	scene.action_panel = _ActionPanelSpy.new()

	var controller = GamePanelControllerClass.new(scene, null, null, Callable(), Callable())
	controller._ui_components_binder = null
	controller._views_controller = null
	var working_panels := _PhasePanelSyncSpy.new()
	var marketing_panels := _PhasePanelSyncSpy.new()
	var placement_overlays := _PhasePanelSyncSpy.new()
	var end_panels := _PhasePanelSyncSpy.new()
	controller._working_panels = working_panels
	controller._marketing_panels = marketing_panels
	controller._placement_overlays = placement_overlays
	controller._end_panels = end_panels

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
	if working_panels.sync_calls != 1 or marketing_panels.sync_calls != 1 or placement_overlays.sync_calls != 1 or end_panels.sync_calls != 1:
		return _finish(
			Result.failure(
				"partial sync_action_state 应同步已打开阶段面板，实际 working=%d marketing=%d placement=%d end=%d"
					% [working_panels.sync_calls, marketing_panels.sync_calls, placement_overlays.sync_calls, end_panels.sync_calls]
			),
			controller,
			scene
		)

	return _finish(Result.success({}), controller, scene)

static func _case_hides_non_initiatable_visible_action_surfaces() -> Result:
	var scene := _FakeScene.new()
	scene.action_panel = _ActionPanelSpy.new({
		"set_price": false,
		"place_restaurant": false,
	})

	var controller = GamePanelControllerClass.new(scene, null, null, Callable(), Callable())
	controller._ui_components_binder = null
	controller._views_controller = null
	var working_panels := _WorkingPanelsSpy.new()
	var price_panel := _PanelSpy.new("set_price", "")
	working_panels.price_panel = price_panel
	var placement_overlays := _PlacementOverlaysSpy.new()
	var restaurant_overlay := _PanelSpy.new("", "place_restaurant")
	placement_overlays.restaurant_placement_overlay = restaurant_overlay
	controller._working_panels = working_panels
	controller._marketing_panels = _PhasePanelSyncSpy.new()
	controller._placement_overlays = placement_overlays
	controller._end_panels = _PhasePanelSyncSpy.new()
	controller._modals_controller = _ModalsControllerSpy.new()
	controller._restructuring_controller = _RestructuringControllerSpy.new()

	var state := GameStateClass.new()
	state.players = [{}, {}]
	state.phase = DefsClass.PHASE_WORKING
	state.sub_phase = DefsClass.SUB_PHASE_PLACE_RESTAURANTS
	controller.sync_action_state(state, false)

	if bool(price_panel.visible):
		return _finish(Result.failure("partial sync 应隐藏已不可启动的 price panel"), controller, scene)
	if bool(restaurant_overlay.visible):
		return _finish(Result.failure("partial sync 应隐藏已不可启动的 restaurant placement overlay"), controller, scene)

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
