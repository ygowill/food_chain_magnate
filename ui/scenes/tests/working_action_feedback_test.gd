class_name WorkingActionFeedbackTest
extends RefCounted

const WorkingActionFeedbackControllerClass = preload("res://ui/scenes/game/overlay/working_action_feedback.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")

class _FakeEngine:
	extends RefCounted

	var state: GameState = null
	var command_history: Array = []

	func get_state() -> GameState:
		return state

class _FakeScene:
	extends Control

	var game_engine = null

class _FakeMapCanvas:
	extends Control

	func get_world_origin() -> Vector2i:
		return Vector2i.ZERO

	func get_cell_size() -> float:
		return 32.0

static func run() -> Result:
	var r := await _case_restaurant_moved_feedback_survives_overlay_clear()
	if not r.ok:
		return r
	r = await _case_command_phase_is_used_for_feedback_gate()
	if not r.ok:
		return r
	r = await _case_event_sequence_reset_keeps_feedback_alive()
	if not r.ok:
		return r
	return Result.success({})

static func _case_restaurant_moved_feedback_survives_overlay_clear() -> Result:
	var scene := _FakeScene.new()
	var canvas := _FakeMapCanvas.new()
	canvas.size = Vector2(640, 480)
	scene.add_child(canvas)
	Engine.get_main_loop().root.add_child(scene)

	var engine := _FakeEngine.new()
	engine.state = GameState.new()
	engine.state.phase = DefsClass.PHASE_WORKING
	engine.state.sub_phase = DefsClass.SUB_PHASE_PLACE_RESTAURANTS
	scene.game_engine = engine

	var controller = WorkingActionFeedbackControllerClass.new(scene, canvas)
	controller.call("_play_event", {
		"type": EventBus.EventType.RESTAURANT_MOVED,
		"data": {
			"restaurant_id": "rest_1",
			"from_cells": [[1, 1], [2, 1], [1, 2], [2, 2]],
			"to_cells": [[5, 1], [6, 1], [5, 2], [6, 2]],
		},
		"__feedback_phase": DefsClass.PHASE_WORKING,
	})

	var layer := canvas.get_node_or_null("WorkingActionFeedbackLayer")
	if layer == null:
		return await _finish(Result.failure("restaurant_moved 应创建 WorkingActionFeedbackLayer"), controller, scene)
	if layer.get_node_or_null("WorkingActionFeedbackMoveGhost") == null:
		return await _finish(Result.failure("restaurant_moved 应创建移动 ghost 动画节点"), controller, scene)
	if layer.get_node_or_null("WorkingActionFeedbackBurst") == null:
		return await _finish(Result.failure("restaurant_moved 应创建“移动餐厅”文字反馈节点"), controller, scene)

	controller.clear()
	if layer.get_node_or_null("WorkingActionFeedbackMoveGhost") == null:
		return await _finish(Result.failure("hide_all_overlays 清理时不应打断移动 ghost 动画"), controller, scene)
	if layer.get_node_or_null("WorkingActionFeedbackBurst") == null:
		return await _finish(Result.failure("hide_all_overlays 清理时不应打断移动文字反馈"), controller, scene)

	return await _finish(Result.success({}), controller, scene)

static func _case_command_phase_is_used_for_feedback_gate() -> Result:
	var scene := _FakeScene.new()
	var canvas := _FakeMapCanvas.new()
	canvas.size = Vector2(640, 480)
	scene.add_child(canvas)
	Engine.get_main_loop().root.add_child(scene)

	var engine := _FakeEngine.new()
	engine.state = GameState.new()
	engine.state.phase = DefsClass.PHASE_DINNERTIME
	engine.state.sub_phase = ""
	var command := Command.create("move_restaurant", 0, {})
	command.phase = DefsClass.PHASE_WORKING
	command.sub_phase = DefsClass.SUB_PHASE_PLACE_RESTAURANTS
	engine.command_history = [command]
	scene.game_engine = engine

	var controller = WorkingActionFeedbackControllerClass.new(scene, canvas)
	var phase_info: Dictionary = controller.call("_read_event_command_phase", {
		"type": EventBus.EventType.RESTAURANT_MOVED,
		"data": {"command_index": 0},
	})
	if str(phase_info.get("phase", "")) != DefsClass.PHASE_WORKING:
		return await _finish(Result.failure("反馈应读取触发命令所在阶段，实际: %s" % str(phase_info)), controller, scene)
	if str(phase_info.get("sub_phase", "")) != DefsClass.SUB_PHASE_PLACE_RESTAURANTS:
		return await _finish(Result.failure("反馈应读取触发命令所在子阶段，实际: %s" % str(phase_info)), controller, scene)

	return await _finish(Result.success({}), controller, scene)

static func _case_event_sequence_reset_keeps_feedback_alive() -> Result:
	var controller = WorkingActionFeedbackControllerClass.new(null, null)
	if not bool(controller.call("_accept_event_sequence", 18)):
		return Result.failure("首次事件序号应被接受")
	if not bool(controller.call("_accept_event_sequence", 19)):
		return Result.failure("递增事件序号应被接受")
	if not bool(controller.call("_accept_event_sequence", 2)):
		return Result.failure("回退重建后重置的小序号应被接受，避免新分支反馈丢失")
	if not bool(controller.call("_accept_event_sequence", 3)):
		return Result.failure("重置后的后续事件序号应继续被接受")
	controller.dispose()
	return Result.success({})

static func _finish(result: Result, controller, scene: Node) -> Result:
	if controller != null:
		controller.dispose()
	if scene != null and is_instance_valid(scene):
		scene.queue_free()
	await Engine.get_main_loop().process_frame
	return result
