extends Node

const WorkingPanelsClass = preload("res://ui/scenes/game/panel/working/panels.gd")
const MapControllerClass = preload("res://ui/scenes/game/map_interaction/controller.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")

class FakeEngine extends RefCounted:
	var _state: GameState = null

	func _init(state: GameState) -> void:
		_state = state

	func get_state() -> GameState:
		return _state

var game_engine = null
var _map_controller = null
var _working_panels = null

func _ready() -> void:
	if not _should_autorun():
		return

	var exit_code := 0
	var r := _run()
	if not r.ok:
		exit_code = 1
	get_tree().quit(exit_code)

func _run() -> Result:
	print("[ProcureDrinksMapClickTest] START args=%s" % str(OS.get_cmdline_user_args()))

	var state := GameState.new()
	state.phase = DefsClass.PHASE_WORKING
	state.sub_phase = DefsClass.SUB_PHASE_GET_DRINKS
	state.turn_order = [0]
	state.current_player_index = 0
	state.players = [{
		"id": 0,
		"employees": [],
		"inventory": {},
	}]
	state.map = {
		"grid_size": Vector2i(5, 5),
		"tile_grid_size": Vector2i(1, 1),
		"drink_sources": [
			{"world_pos": Vector2i(1, 1), "type": "soda", "tile_id": "__test__"},
		],
		"restaurants": {
			"rest_0": {
				"restaurant_id": "rest_0",
				"owner": 0,
				"entrance_pos": Vector2i(2, 2)
			}
		},
	}

	game_engine = FakeEngine.new(state)
	_map_controller = MapControllerClass.new(self, null, null)
	_working_panels = WorkingPanelsClass.new(
		self,
		_map_controller,
		Callable(self, "_execute_command"),
		Callable(self, "_hide_all_phase_panels"),
		Callable(self, "_center_popup"),
		null
	)

	var cases: Array[String] = ["cart_operator", "truck_driver", "zeppelin_pilot"]
	for emp_id in cases:
		var player0: Dictionary = state.players[0]
		player0["employees"] = [emp_id]
		state.players[0] = player0

		_working_panels.show_production_panel("drinks")

		if _map_controller.get_mode() != "procure_drinks":
			return Result.failure("进入选点模式失败: employee=%s mode=%s" % [emp_id, _map_controller.get_mode()])

		if not is_instance_valid(_working_panels.production_panel) or not _working_panels.production_panel.visible:
			return Result.failure("production_panel 未显示: employee=%s" % emp_id)

		# 点击一个饮料点：应当更新 production_panel 的选点计数
		var pos: Vector2i = state.map["drink_sources"][0]["world_pos"]
		_map_controller._on_map_cell_selected(pos)

		# ProductionPanel 内部会缓存 selected_sources_count；这里用它验证“点击有响应”。
		var count := int(_working_panels.production_panel._drinks_selected_sources_count)
		if count != 1:
			return Result.failure("点击未生效: employee=%s expected=1 got=%d" % [emp_id, count])

	print("[ProcureDrinksMapClickTest] PASS employees=cart_operator,truck_driver,zeppelin_pilot")
	return Result.success()

func _execute_command(_cmd: Command) -> Result:
	# 本测试不覆盖执行命令（只覆盖 UI 选点 -> 状态更新链路）。
	return Result.success()

func _hide_all_phase_panels() -> void:
	if _working_panels != null:
		_working_panels.hide()
	if _map_controller != null:
		_map_controller.clear_selection()

func _center_popup(_panel: Control) -> void:
	return

func _should_autorun() -> bool:
	var args := OS.get_cmdline_user_args()
	if args.has("autorun") or args.has("--autorun"):
		return true
	return OS.has_feature("headless")
