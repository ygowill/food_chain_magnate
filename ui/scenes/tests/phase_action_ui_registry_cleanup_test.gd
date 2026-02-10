class_name PhaseActionUiRegistryCleanupTest
extends RefCounted

const PhaseActionUiRegistryClass = preload("res://ui/scenes/game/phase_action_ui_registry.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")

class StubController:
	extends RefCounted
	var calls: Array[String] = []

	func show_kimchi_storage_modal(_state: GameState, _current_player_id: int, _covered: Rect2) -> void:
		calls.append("show_kimchi")

	func show_fridge_keep_modal(_state: GameState, _current_player_id: int, _covered: Rect2) -> void:
		calls.append("show_fridge")

	func hide_kimchi_storage_modal() -> void:
		calls.append("hide_kimchi")

	func hide_fridge_keep_modal() -> void:
		calls.append("hide_fridge")

static func run() -> Result:
	var covered := Rect2(Vector2.ZERO, Vector2(10, 10))

	var state := GameState.new()
	state.phase = DefsClass.PHASE_CLEANUP

	# 新格式：kimchi
	state.round_state = {
		"pending_phase_actions": {
			DefsClass.PHASE_CLEANUP: [
				{"kind": "kimchi", "player_id": 0},
			],
		},
	}
	var c1 := StubController.new()
	PhaseActionUiRegistryClass.sync_cleanup_pending_modals(c1, state, 0, covered, true)
	if str(c1.calls) != str(["show_kimchi", "hide_fridge"]):
		return Result.failure("新格式 kimchi 路由错误: %s" % str(c1.calls))

	# 新格式：fridge_keep
	state.round_state = {
		"pending_phase_actions": {
			DefsClass.PHASE_CLEANUP: [
				{"kind": "fridge_keep", "player_id": 0},
			],
		},
	}
	var c2 := StubController.new()
	PhaseActionUiRegistryClass.sync_cleanup_pending_modals(c2, state, 0, covered, true)
	if str(c2.calls) != str(["show_fridge", "hide_kimchi"]):
		return Result.failure("新格式 fridge_keep 路由错误: %s" % str(c2.calls))

	# 旧格式：kimchi
	state.round_state = {
		"pending_phase_actions": {
			DefsClass.PHASE_CLEANUP: [0],
		},
		"cleanup": {
			"pending_choice_kind": "kimchi",
		},
	}
	var c3 := StubController.new()
	PhaseActionUiRegistryClass.sync_cleanup_pending_modals(c3, state, 0, covered, true)
	if str(c3.calls) != str(["show_kimchi", "hide_fridge"]):
		return Result.failure("旧格式 kimchi 路由错误: %s" % str(c3.calls))

	# 旧格式：默认（非 kimchi -> fridge_keep）
	state.round_state = {
		"pending_phase_actions": {
			DefsClass.PHASE_CLEANUP: [0],
		},
		"cleanup": {
			"pending_choice_kind": "",
		},
	}
	var c4 := StubController.new()
	PhaseActionUiRegistryClass.sync_cleanup_pending_modals(c4, state, 0, covered, true)
	if str(c4.calls) != str(["show_fridge", "hide_kimchi"]):
		return Result.failure("旧格式默认路由错误: %s" % str(c4.calls))

	# 非交互：应隐藏两者
	state.round_state = {
		"pending_phase_actions": {
			DefsClass.PHASE_CLEANUP: [
				{"kind": "kimchi", "player_id": 0},
			],
		},
	}
	var c5 := StubController.new()
	PhaseActionUiRegistryClass.sync_cleanup_pending_modals(c5, state, 0, covered, false)
	if str(c5.calls) != str(["hide_fridge", "hide_kimchi"]):
		return Result.failure("非交互隐藏行为错误: %s" % str(c5.calls))

	# 非当前玩家：应隐藏两者
	state.round_state = {
		"pending_phase_actions": {
			DefsClass.PHASE_CLEANUP: [
				{"kind": "kimchi", "player_id": 1},
			],
		},
	}
	var c6 := StubController.new()
	PhaseActionUiRegistryClass.sync_cleanup_pending_modals(c6, state, 0, covered, true)
	if str(c6.calls) != str(["hide_fridge", "hide_kimchi"]):
		return Result.failure("非当前玩家隐藏行为错误: %s" % str(c6.calls))

	return Result.success({
		"ok": true,
	})

