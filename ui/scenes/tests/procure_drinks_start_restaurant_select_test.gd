# 多餐厅：支持通过地图点击/数字快捷键选择饮料采购起点餐厅（UI 侧交互测试）
class_name ProcureDrinksStartRestaurantSelectTest
extends RefCounted

const ProcureControllerClass = preload("res://ui/scenes/game/game_panel_working_drinks_procurement_controller.gd")
const MapControllerClass = preload("res://ui/scenes/game/game_map_interaction_controller.gd")
const InputControllerClass = preload("res://ui/scenes/game/game_input_controller.gd")
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

	# 进入道路采购模式：默认选中第一家餐厅（按 id 升序确定性）。
	procure.on_drinks_producer_changed(state, "truck_driver")
	if map_controller.get_mode() != "procure_drinks":
		return Result.failure("进入选点模式失败: mode=%s" % map_controller.get_mode())
	if panel.selected_restaurant_id != "rest_0":
		return Result.failure("默认起点餐厅错误: expected=rest_0 got=%s" % panel.selected_restaurant_id)

	# 数字快捷键：2 -> rest_1
	var input_controller = InputControllerClass.new(null, null, null, map_controller, null, null, null, null)
	var key := InputEventKey.new()
	key.pressed = true
	key.keycode = KEY_2
	if not input_controller.handle_unhandled_input(key):
		return Result.failure("KEY_2 未被处理（预期应切换起点餐厅）")
	if panel.selected_restaurant_id != "rest_1":
		return Result.failure("数字快捷键切换失败: expected=rest_1 got=%s" % panel.selected_restaurant_id)

	# 地图点击：点击餐厅入口格应切换起点餐厅
	map_controller._on_map_cell_selected(Vector2i(2, 2))
	if panel.selected_restaurant_id != "rest_0":
		return Result.failure("点击餐厅切换失败: expected=rest_0 got=%s" % panel.selected_restaurant_id)
	map_controller._on_map_cell_selected(Vector2i(7, 2))
	if panel.selected_restaurant_id != "rest_1":
		return Result.failure("点击餐厅切换失败: expected=rest_1 got=%s" % panel.selected_restaurant_id)

	# Hover 预览：至少选 1 个进货点后，悬停餐厅应写入 preview 文案；离开后清空
	map_controller._on_map_cell_selected(Vector2i(1, 1))
	var hover_pos := Vector2i(2, 2)
	if panel.selected_restaurant_id == "rest_0":
		hover_pos = Vector2i(7, 2)
	map_controller._on_map_cell_hovered(hover_pos)
	if panel.hover_preview_text.is_empty() or not panel.hover_preview_text.begins_with("预览："):
		return Result.failure("hover 预览文案未写入: %s" % panel.hover_preview_text)
	map_controller._on_map_cell_hovered(Vector2i(-1, -1))
	if not panel.hover_preview_text.is_empty():
		return Result.failure("离开 hover 后预览文案应清空: %s" % panel.hover_preview_text)

	return Result.success({
		"selected_restaurant_id": panel.selected_restaurant_id,
	})
