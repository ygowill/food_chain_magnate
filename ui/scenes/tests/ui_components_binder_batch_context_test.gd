class_name UiComponentsBinderBatchContextTest
extends RefCounted

const UiComponentsBinderClass = preload("res://ui/scenes/game/panel/ui_components_binder.gd")
const GameEngineClass = preload("res://core/engine/game_engine.gd")

class _PlayerPanelSpy:
	extends RefCounted

	var batch_count: int = 0
	var legacy_game_state_count: int = 0
	var legacy_current_count: int = 0
	var legacy_view_count: int = 0

	func set_display_context(_state: GameState, _current_player_id: int, _view_player_id: int) -> void:
		batch_count += 1

	func set_game_state(_state: GameState) -> void:
		legacy_game_state_count += 1

	func set_current_player(_player_id: int) -> void:
		legacy_current_count += 1

	func set_view_player(_player_id: int) -> void:
		legacy_view_count += 1

class _LeftPanelSpy:
	extends RefCounted

	var batch_count: int = 0
	var legacy_game_state_count: int = 0
	var legacy_current_count: int = 0

	func set_display_context(_state: GameState, _current_player_id: int, _view_player_id: int) -> void:
		batch_count += 1

	func set_game_state(_state: GameState) -> void:
		legacy_game_state_count += 1

	func set_current_player(_player_id: int) -> void:
		legacy_current_count += 1

class _TurnOrderDisplaySpy:
	extends RefCounted

	var player_count_calls: int = 0
	var batch_count: int = 0
	var legacy_game_state_count: int = 0
	var legacy_selection_count: int = 0
	var legacy_current_count: int = 0

	func set_player_count(_count: int) -> void:
		player_count_calls += 1

	func set_display_context(_state: GameState, _selections: Dictionary, _current_player_id: int) -> void:
		batch_count += 1

	func set_game_state(_state: GameState) -> void:
		legacy_game_state_count += 1

	func set_current_selections(_selections: Dictionary) -> void:
		legacy_selection_count += 1

	func set_current_player(_player_id: int) -> void:
		legacy_current_count += 1

class _ActionPanelSpy:
	extends RefCounted

	var batch_count: int = 0
	var legacy_game_state_count: int = 0
	var legacy_current_count: int = 0
	var map_skin_calls: int = 0
	var action_registry_calls: int = 0

	func set_display_context(_state: GameState, _player_id: int) -> void:
		batch_count += 1

	func set_game_state(_state: GameState) -> void:
		legacy_game_state_count += 1

	func set_current_player(_player_id: int) -> void:
		legacy_current_count += 1

	func set_map_skin(_skin) -> void:
		map_skin_calls += 1

	func set_action_registry(_registry) -> void:
		action_registry_calls += 1

class _FakeScene:
	extends RefCounted

	var player_panel = _PlayerPanelSpy.new()
	var left_panel = _LeftPanelSpy.new()
	var turn_order_track = null
	var turn_order_display = _TurnOrderDisplaySpy.new()
	var inventory_panel = null
	var action_panel = _ActionPanelSpy.new()
	var hand_area = null
	var company_structure = null
	var game_engine: GameEngine = null

class _FakeController:
	extends RefCounted

	var _scene = _FakeScene.new()
	var _view_player_id: int = -1
	var _restructuring_controller = null

	func _init(engine: GameEngine) -> void:
		_scene.game_engine = engine

	func _get_effective_view_player_id(state: GameState, requested_view_id: int) -> int:
		if requested_view_id >= 0:
			return requested_view_id
		return int(state.get_current_player_id())

	func _get_current_map_skin():
		return null

static func run(seed_val: int = 12345) -> Result:
	var prev_mode = NetContext.mode if NetContext != null else 0
	var prev_local_player_id := int(NetContext.local_player_id) if NetContext != null else -1

	var engine := GameEngineClass.new()
	var init_r := engine.initialize(2, seed_val)
	if not init_r.ok:
		return _finish(Result.failure("初始化失败: %s" % init_r.error), engine, prev_mode, prev_local_player_id)

	if NetContext != null:
		NetContext.mode = NetContext.Mode.HOTSEAT
		NetContext.local_player_id = -1

	var controller := _FakeController.new(engine)
	var binder := UiComponentsBinderClass.new(controller)
	binder.sync(engine.get_state())

	var player_panel: _PlayerPanelSpy = controller._scene.player_panel
	if player_panel.batch_count != 1:
		return _finish(Result.failure("PlayerPanel 应走批量接口，实际=%d" % player_panel.batch_count), engine, prev_mode, prev_local_player_id)
	if player_panel.legacy_game_state_count != 0 or player_panel.legacy_current_count != 0 or player_panel.legacy_view_count != 0:
		return _finish(
			Result.failure(
				"PlayerPanel 不应回退到旧接口，实际 state=%d current=%d view=%d"
					% [player_panel.legacy_game_state_count, player_panel.legacy_current_count, player_panel.legacy_view_count]
			),
			engine,
			prev_mode,
			prev_local_player_id
		)

	var left_panel: _LeftPanelSpy = controller._scene.left_panel
	if left_panel.batch_count != 1:
		return _finish(Result.failure("LeftPanel 应走批量接口，实际=%d" % left_panel.batch_count), engine, prev_mode, prev_local_player_id)
	if left_panel.legacy_game_state_count != 0 or left_panel.legacy_current_count != 0:
		return _finish(
			Result.failure(
				"LeftPanel 不应回退到旧接口，实际 state=%d current=%d"
					% [left_panel.legacy_game_state_count, left_panel.legacy_current_count]
			),
			engine,
			prev_mode,
			prev_local_player_id
		)

	var turn_order_display: _TurnOrderDisplaySpy = controller._scene.turn_order_display
	if turn_order_display.player_count_calls != 1 or turn_order_display.batch_count != 1:
		return _finish(
			Result.failure(
				"TurnOrderDisplay 应走批量接口，实际 player_count=%d batch=%d"
					% [turn_order_display.player_count_calls, turn_order_display.batch_count]
			),
			engine,
			prev_mode,
			prev_local_player_id
		)
	if turn_order_display.legacy_game_state_count != 0 or turn_order_display.legacy_selection_count != 0 or turn_order_display.legacy_current_count != 0:
		return _finish(
			Result.failure(
				"TurnOrderDisplay 不应回退到旧接口，实际 state=%d selection=%d current=%d"
					% [
						turn_order_display.legacy_game_state_count,
						turn_order_display.legacy_selection_count,
						turn_order_display.legacy_current_count
					]
			),
			engine,
			prev_mode,
			prev_local_player_id
		)

	var action_panel: _ActionPanelSpy = controller._scene.action_panel
	if action_panel.batch_count != 1:
		return _finish(Result.failure("ActionPanel 应走批量接口，实际=%d" % action_panel.batch_count), engine, prev_mode, prev_local_player_id)
	if action_panel.legacy_game_state_count != 0 or action_panel.legacy_current_count != 0:
		return _finish(
			Result.failure(
				"ActionPanel 不应回退到旧接口，实际 state=%d current=%d"
					% [action_panel.legacy_game_state_count, action_panel.legacy_current_count]
			),
			engine,
			prev_mode,
			prev_local_player_id
		)
	if action_panel.map_skin_calls != 1 or action_panel.action_registry_calls != 1:
		return _finish(
			Result.failure(
				"ActionPanel 仍应同步 map_skin / registry，实际 map_skin=%d registry=%d"
					% [action_panel.map_skin_calls, action_panel.action_registry_calls]
			),
			engine,
			prev_mode,
			prev_local_player_id
		)

	return _finish(Result.success({}), engine, prev_mode, prev_local_player_id)

static func _finish(result: Result, engine: GameEngine, prev_mode, prev_local_player_id: int) -> Result:
	if engine != null and engine.has_method("dispose"):
		engine.dispose()
	if NetContext != null:
		NetContext.mode = prev_mode
		NetContext.local_player_id = prev_local_player_id
	return result
