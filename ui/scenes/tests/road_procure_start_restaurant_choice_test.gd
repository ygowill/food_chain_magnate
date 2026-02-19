# 多餐厅：道路采购饮料应提供“起点餐厅”选择（UI 侧属性测试）
# 覆盖：当玩家有多个餐厅时，采购饮料不应只能隐式使用第一家；应向 ProductionPanel 下发可选餐厅列表。
class_name RoadProcureStartRestaurantChoiceTest
extends RefCounted

const ProcureControllerClass = preload("res://ui/scenes/game/panel/working/procurement/controller.gd")
const GameStateClass = preload("res://core/state/game_state.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")

class DummyEngine:
	extends RefCounted
	var _state: GameState

	func _init(state: GameState) -> void:
		_state = state

	func get_state() -> GameState:
		return _state

class DummyScene:
	extends RefCounted
	var game_engine = null

class DummyPanel:
	extends RefCounted
	var calls: Array[Dictionary] = []

	func set_drinks_procure_restaurants(restaurants: Array[Dictionary], selected_restaurant_id: String, require_selection: bool) -> void:
		calls.append({
			"restaurants": restaurants.duplicate(true),
			"selected_restaurant_id": str(selected_restaurant_id),
			"require_selection": bool(require_selection),
		})

static func run() -> Result:
	# 最小 state：2 个餐厅入口 + 任意饮料源（本测试只关心“下发餐厅列表”）。
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

	var scene := DummyScene.new()
	scene.game_engine = DummyEngine.new(state)

	var panel := DummyPanel.new()
	var procure = ProcureControllerClass.new(scene, null, null)
	procure.set_production_panel(panel)

	# 道路采购（非飞艇）：应向面板下发可选餐厅列表，并默认选中第一家（确定性：按 id 升序）。
	procure.on_drinks_producer_changed(state, "truck_driver")

	if panel.calls.size() != 1:
		return Result.failure("应下发一次 set_drinks_procure_restaurants，但 calls=%d" % panel.calls.size())

	var call0: Dictionary = panel.calls[0]
	var arr_val = call0.get("restaurants", null)
	if not (arr_val is Array):
		return Result.failure("restaurants 类型错误")
	var arr: Array = arr_val
	if arr.size() != 2:
		return Result.failure("restaurants 数量错误: %s" % str(arr.size()))

	var s0 := str(call0.get("selected_restaurant_id", "")).strip_edges()
	if s0 != "rest_0":
		return Result.failure("selected_restaurant_id=%s (期望 rest_0)" % s0)

	if bool(call0.get("require_selection", true)):
		return Result.failure("road procure 不应强制选择餐厅（require_selection 期望为 false）")

	return Result.success({
		"restaurants": arr,
		"selected_restaurant_id": s0,
	})

