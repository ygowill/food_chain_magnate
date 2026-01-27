# 多餐厅：飞艇采购饮料起点应由玩家选择（UI 侧属性测试）
# 覆盖 issue_tracker #22：多餐厅时不应自动锁定第一家餐厅，应提示可选起点 tiles。
class_name AirProcureStartTileChoiceTest
extends RefCounted

const WorkingPanelsClass = preload("res://ui/scenes/game/game_panel_working_panels.gd")
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

class DummyOverlay:
	extends RefCounted
	var calls: Array[Dictionary] = []

	func show_procurement_route_overlay(entrance_pos: Vector2i, route: Array[Vector2i], picked_sources: Array[Vector2i] = [], options: Dictionary = {}) -> void:
		calls.append({
			"entrance_pos": entrance_pos,
			"route": route.duplicate(),
			"picked_sources": picked_sources.duplicate(),
			"options": options.duplicate(true),
		})

static func run() -> Result:
	# 构造一个最小 state：2 个餐厅入口分别落在 tile(0,0)/(1,0)。
	var state: GameState = GameStateClass.new()
	state.turn_order = [0]
	state.current_player_index = 0
	state.phase = DefsClass.PHASE_WORKING
	state.sub_phase = DefsClass.SUB_PHASE_GET_DRINKS
	state.map = {
		"grid_size": Vector2i(10, 5), # 2x1 tiles，tile_size=5
		"tile_grid_size": Vector2i(2, 1),
		"map_origin": Vector2i.ZERO,
		"restaurants": {
			"rest_0": {"restaurant_id": "rest_0", "owner": 0, "entrance_pos": Vector2i(2, 2)},
			"rest_1": {"restaurant_id": "rest_1", "owner": 0, "entrance_pos": Vector2i(7, 2)},
		},
	}

	var scene := DummyScene.new()
	scene.game_engine = DummyEngine.new(state)

	var overlay := DummyOverlay.new()
	var panels = WorkingPanelsClass.new(scene, null, Callable(), Callable(), Callable(), overlay)

	# 选择飞艇驾驶员（air procure）：多餐厅时应展示“起点 tile 可选”高亮，而不是自动选第一家。
	panels._on_producer_changed("zeppelin_pilot", "drinks")

	if overlay.calls.size() != 1:
		return Result.failure("多餐厅飞艇采购：应触发一次起点 tiles overlay，实际 calls=%d" % overlay.calls.size())

	var call0: Dictionary = overlay.calls[0]
	var opts_val = call0.get("options", null)
	if not (opts_val is Dictionary):
		return Result.failure("overlay options 类型错误")
	var opts: Dictionary = opts_val

	if not bool(opts.get("tile_mode", false)):
		return Result.failure("overlay.tile_mode 期望为 true")
	if int(opts.get("tile_size_cells", -1)) != 5:
		return Result.failure("overlay.tile_size_cells 期望为 5，实际: %s" % str(opts.get("tile_size_cells", null)))

	var legal_val = opts.get("legal_tiles", null)
	if not (legal_val is Array):
		return Result.failure("overlay.legal_tiles 类型错误")
	var legal: Array = legal_val

	var expected := [Vector2i(0, 0), Vector2i(1, 0)]
	if legal != expected:
		return Result.failure("overlay.legal_tiles=%s (期望 %s)" % [str(legal), str(expected)])

	if panels._procure_selected_tiles.size() != 0:
		return Result.failure("多餐厅飞艇采购：不应自动选定起点 tile，实际 selected_tiles=%s" % str(panels._procure_selected_tiles))
	if not str(panels._procure_air_start_restaurant_id).is_empty():
		return Result.failure("多餐厅飞艇采购：不应自动选定起点餐厅，实际=%s" % str(panels._procure_air_start_restaurant_id))

	return Result.success({
		"legal_tiles": legal,
	})
