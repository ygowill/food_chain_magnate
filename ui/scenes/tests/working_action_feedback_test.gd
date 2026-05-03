class_name WorkingActionFeedbackTest
extends RefCounted

const WorkingActionFeedbackControllerClass = preload("res://ui/scenes/game/overlay/working_action_feedback.gd")
const OnlineResyncControllerClass = preload("res://ui/scenes/game/controllers/online_resync_controller.gd")
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

class _FakeReplayEngine:
	extends RefCounted

	var command_history: Array = []
	var event_sink = null

	func set_event_sink(sink) -> void:
		event_sink = sink

	func get_event_sink():
		return event_sink

	func execute_command(cmd, _is_replay: bool = false) -> Result:
		if event_sink != null and event_sink.has_method("emit_event"):
			event_sink.emit_event(EventBus.EventType.FOOD_PRODUCED, {"player_id": 0})
		else:
			EventBus.emit_event(EventBus.EventType.FOOD_PRODUCED, {"player_id": 0})
		command_history.append(cmd)
		return Result.success({})

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
	r = await _case_burst_layer_caps_feedback_nodes()
	if not r.ok:
		return r
	r = await _case_player_restaurant_feedback_uses_single_anchor()
	if not r.ok:
		return r
	r = _case_online_replay_records_without_notifying_subscribers()
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

static func _case_burst_layer_caps_feedback_nodes() -> Result:
	var scene := _FakeScene.new()
	var canvas := _FakeMapCanvas.new()
	canvas.size = Vector2(640, 480)
	scene.add_child(canvas)
	Engine.get_main_loop().root.add_child(scene)

	var engine := _FakeEngine.new()
	engine.state = _make_feedback_state()
	scene.game_engine = engine

	var controller = WorkingActionFeedbackControllerClass.new(scene, canvas)
	for i in range(24):
		controller.call("_play_event", {
			"type": EventBus.EventType.FOOD_PRODUCED,
			"data": {
				"player_id": 0,
				"restaurant_id": "rest_0",
				"food_type": "burger",
				"amount": i + 1,
			},
			"__feedback_phase": DefsClass.PHASE_WORKING,
		})

	var layer := canvas.get_node_or_null("WorkingActionFeedbackLayer")
	if layer == null:
		return await _finish(Result.failure("大量文字反馈应创建 WorkingActionFeedbackLayer"), controller, scene)
	var burst_nodes := 0
	for child in layer.get_children():
		if str(child.name) == "WorkingActionFeedbackBurst":
			burst_nodes += 1
	if burst_nodes != 1:
		return await _finish(Result.failure("大量文字反馈应复用单个绘制层，实际节点数: %d" % burst_nodes), controller, scene)
	var active_bursts := int(controller.call("get_debug_active_burst_count"))
	if active_bursts > 8:
		return await _finish(Result.failure("文字反馈应有硬上限，实际: %d" % active_bursts), controller, scene)
	var effect_nodes := int(controller.call("get_debug_effect_node_count"))
	if effect_nodes > 18:
		return await _finish(Result.failure("反馈动效节点应有硬上限，实际: %d" % effect_nodes), controller, scene)

	return await _finish(Result.success({}), controller, scene)

static func _case_player_restaurant_feedback_uses_single_anchor() -> Result:
	var scene := _FakeScene.new()
	var canvas := _FakeMapCanvas.new()
	canvas.size = Vector2(960, 480)
	scene.add_child(canvas)
	Engine.get_main_loop().root.add_child(scene)

	var engine := _FakeEngine.new()
	engine.state = _make_feedback_state()
	engine.state.players[0]["restaurants"] = ["rest_0", "rest_far"]
	engine.state.map["restaurants"]["rest_far"] = {
		"owner": 0,
		"cells": [[20, 0], [21, 0], [20, 1], [21, 1]],
	}
	scene.game_engine = engine

	var controller = WorkingActionFeedbackControllerClass.new(scene, canvas)
	var default_rect: Rect2 = controller.call("_get_player_restaurant_rect", engine.state, 0, "")
	if int(round(default_rect.size.x)) != 64 or int(round(default_rect.size.y)) != 64:
		return await _finish(Result.failure("未指定餐厅时反馈应选单个餐厅锚点，实际 rect=%s" % str(default_rect)), controller, scene)
	if default_rect.position.distance_to(Vector2.ZERO) > 0.1:
		return await _finish(Result.failure("未指定餐厅时应优先使用玩家餐厅列表首项，实际 rect=%s" % str(default_rect)), controller, scene)
	var preferred_rect: Rect2 = controller.call("_get_player_restaurant_rect", engine.state, 0, "rest_far")
	if int(round(preferred_rect.position.x)) != 640 or int(round(preferred_rect.size.x)) != 64:
		return await _finish(Result.failure("指定 restaurant_id 时反馈应锚定指定餐厅，实际 rect=%s" % str(preferred_rect)), controller, scene)

	return await _finish(Result.success({}), controller, scene)

static func _make_feedback_state() -> GameState:
	var state := GameState.new()
	state.phase = DefsClass.PHASE_WORKING
	state.sub_phase = DefsClass.SUB_PHASE_PLACE_RESTAURANTS
	state.players = [{
		"restaurants": ["rest_0"],
	}]
	state.map = {
		"restaurants": {
			"rest_0": {
				"owner": 0,
				"cells": [[0, 0], [1, 0], [0, 1], [1, 1]],
			},
		},
	}
	return state

static func _case_online_replay_records_without_notifying_subscribers() -> Result:
	EventBus.clear_history_and_reset_sequence()
	var received: Array[Dictionary] = []
	var source := "WorkingActionFeedbackTestRecordOnly"
	var callback := func(event: Dictionary) -> void:
		received.append(event)
	EventBus.subscribe(EventBus.EventType.FOOD_PRODUCED, callback, 100, source)

	var engine := _FakeReplayEngine.new()
	var controller = OnlineResyncControllerClass.new(
		null,
		null,
		Callable(),
		Callable(),
		Callable(),
		Callable(),
		Callable(),
		Callable(),
		Callable(),
		Callable(),
		Callable(),
		Callable(),
		Callable(),
		Callable(),
		Callable()
	)
	var replay_r: Result = controller.call("_execute_replay_command_record_only", engine, Command.create("fake_replay", 0, {}))
	EventBus.unsubscribe_all_from_source(source)
	var history := EventBus.get_history()
	EventBus.clear_history_and_reset_sequence()
	if not replay_r.ok:
		return replay_r
	if not received.is_empty():
		return Result.failure("联机 replay record-only 事件不应通知订阅者，实际收到: %d" % received.size())
	for event_val in history:
		if event_val is Dictionary and str(event_val.get("type", "")) == EventBus.EventType.FOOD_PRODUCED:
			return Result.success({})
	return Result.failure("联机 replay record-only 事件应写入 EventBus.history")

static func _finish(result: Result, controller, scene: Node) -> Result:
	if controller != null:
		controller.dispose()
	if scene != null and is_instance_valid(scene):
		scene.queue_free()
	await Engine.get_main_loop().process_frame
	return result
