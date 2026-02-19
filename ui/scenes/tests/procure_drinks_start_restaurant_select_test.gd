# 多餐厅：支持通过地图点击/数字快捷键选择饮料采购起点餐厅（UI 侧交互测试）
class_name ProcureDrinksStartRestaurantSelectTest
extends RefCounted

const ProcureControllerClass = preload("res://ui/scenes/game/panel/working/procurement/controller.gd")
const MapControllerClass = preload("res://ui/scenes/game/map_interaction/controller.gd")
const InputControllerClass = preload("res://ui/scenes/game/controllers/input_controller.gd")
const GameStateClass = preload("res://core/state/game_state.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")

class DummyScene:
	extends RefCounted
	var game_engine = null

class DummyPanel:
	extends RefCounted
	var visible: bool = true
	var selected_restaurant_id: String = ""
	var hover_preview_text: String = ""

	func set_drinks_procure_restaurants(restaurants: Array[Dictionary], selected_id: String, _require_selection: bool) -> void:
		selected_restaurant_id = str(selected_id).strip_edges()

	func set_drinks_procurement_state(_selected_sources_count: int, _confirm_ready: bool, _error_text: String = "") -> void:
		return

	func set_drinks_hover_preview_text(text: String) -> void:
		hover_preview_text = str(text).strip_edges()

static func run() -> Result:
	var state: GameState = GameStateClass.new()
	state.turn_order = [0]
	state.current_player_index = 0
	state.phase = DefsClass.PHASE_WORKING
	state.sub_phase = DefsClass.SUB_PHASE_GET_DRINKS
	state.map = {
		"grid_size": Vector2i(10, 5),
		"tile_grid_size": Vector2i(2, 1),
		"map_origin": Vector2i.ZERO,
		"drink_sources": [
			{"world_pos": Vector2i(1, 1), "type": "soda", "tile_id": "__test__"},
		],
		"restaurants": {
			"rest_0": {"restaurant_id": "rest_0", "owner": 0, "entrance_pos": Vector2i(2, 2)},
			"rest_1": {"restaurant_id": "rest_1", "owner": 0, "entrance_pos": Vector2i(7, 2)},
		},
	}

	var engine := GameEngine.new()
	engine.state = state

	var scene := DummyScene.new()
	scene.game_engine = engine

	var map_controller = MapControllerClass.new(scene, null, null)
	var panel := DummyPanel.new()
	var procure = ProcureControllerClass.new(scene, map_controller, null)
	procure.set_production_panel(panel)
	var input_controller = null

	# 进入道路采购模式：默认选中第一家餐厅（按 id 升序确定性）。
	procure.on_drinks_producer_changed(state, "truck_driver")
	if map_controller.get_mode() != "procure_drinks":
		return _finish(Result.failure("进入选点模式失败: mode=%s" % map_controller.get_mode()), map_controller, procure, input_controller, engine)
	if panel.selected_restaurant_id != "rest_0":
		return _finish(Result.failure("默认起点餐厅错误: expected=rest_0 got=%s" % panel.selected_restaurant_id), map_controller, procure, input_controller, engine)

	# 数字快捷键：2 -> rest_1
	input_controller = InputControllerClass.new(null, null, null, map_controller, null, null, null, null)
	var key := InputEventKey.new()
	key.pressed = true
	key.keycode = KEY_2
	if not input_controller.handle_unhandled_input(key):
		return _finish(Result.failure("KEY_2 未被处理（预期应切换起点餐厅）"), map_controller, procure, input_controller, engine)
	if panel.selected_restaurant_id != "rest_1":
		return _finish(Result.failure("数字快捷键切换失败: expected=rest_1 got=%s" % panel.selected_restaurant_id), map_controller, procure, input_controller, engine)

	# 地图点击：点击餐厅入口格应切换起点餐厅
	map_controller._on_map_cell_selected(Vector2i(2, 2))
	if panel.selected_restaurant_id != "rest_0":
		return _finish(Result.failure("点击餐厅切换失败: expected=rest_0 got=%s" % panel.selected_restaurant_id), map_controller, procure, input_controller, engine)
	map_controller._on_map_cell_selected(Vector2i(7, 2))
	if panel.selected_restaurant_id != "rest_1":
		return _finish(Result.failure("点击餐厅切换失败: expected=rest_1 got=%s" % panel.selected_restaurant_id), map_controller, procure, input_controller, engine)

	# Hover 预览：至少选 1 个进货点后，悬停餐厅应写入 preview 文案；离开后清空
	map_controller._on_map_cell_selected(Vector2i(1, 1))
	var hover_pos := Vector2i(2, 2)
	if panel.selected_restaurant_id == "rest_0":
		hover_pos = Vector2i(7, 2)
	map_controller._on_map_cell_hovered(hover_pos)
	if panel.hover_preview_text.is_empty() or not panel.hover_preview_text.begins_with("预览："):
		return _finish(Result.failure("hover 预览文案未写入: %s" % panel.hover_preview_text), map_controller, procure, input_controller, engine)
	map_controller._on_map_cell_hovered(Vector2i(-1, -1))
	if not panel.hover_preview_text.is_empty():
		return _finish(Result.failure("离开 hover 后预览文案应清空: %s" % panel.hover_preview_text), map_controller, procure, input_controller, engine)

	return _finish(Result.success({
		"selected_restaurant_id": panel.selected_restaurant_id,
	}), map_controller, procure, input_controller, engine)

static func _finish(result: Result, map_controller, procure_controller, input_controller, engine) -> Result:
	if map_controller != null and is_instance_valid(map_controller) and map_controller.has_method("dispose"):
		map_controller.dispose()
	if procure_controller != null and is_instance_valid(procure_controller) and procure_controller.has_method("dispose"):
		procure_controller.dispose()
	if input_controller != null and is_instance_valid(input_controller) and input_controller.has_method("dispose"):
		input_controller.dispose()
	if engine != null and engine.has_method("dispose"):
		engine.dispose()
	return result
