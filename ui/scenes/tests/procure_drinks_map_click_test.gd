extends Node

const WorkingPanelsClass = preload("res://ui/scenes/game/panel/working/panels.gd")
const MapControllerClass = preload("res://ui/scenes/game/map_interaction/controller.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const EmployeeRulesClass = preload("res://core/rules/employee_rules.gd")

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
		print("[ProcureDrinksMapClickTest] FAIL %s" % str(r.error))
		exit_code = 1
	get_tree().quit(exit_code)

func _run() -> Result:
	print("[ProcureDrinksMapClickTest] START args=%s" % str(OS.get_cmdline_user_args()))

	var registry_engine := GameEngine.new()
	var init := registry_engine.initialize(2, 12345)
	if not init.ok:
		return Result.failure("初始化测试注册表失败: %s" % init.error)

	var state := GameState.new()
	state.phase = DefsClass.PHASE_WORKING
	state.sub_phase = DefsClass.SUB_PHASE_GET_DRINKS
	state.turn_order = [0]
	state.current_player_index = 0
	state.players = [{
		"id": 0,
		"employees": [],
		"reserve_employees": [],
		"busy_marketers": [],
		"employees_staff_ids": [],
		"reserve_staff_ids": [],
		"busy_staff_ids": [],
		"staff_registry": {},
		"inventory": {},
	}]
	state.round_state = {
		"staff_usage": {},
		"staff_train_event_counts": {},
	}
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
		var staff_id := cases.find(emp_id) + 1
		var registry := {}
		registry[staff_id] = {
			"staff_id": staff_id,
			"employee_type": emp_id,
			"created_round": int(state.round_number),
		}
		var player0: Dictionary = state.players[0]
		player0["employees"] = [emp_id]
		player0["employees_staff_ids"] = [staff_id]
		player0["staff_registry"] = registry
		state.players[0] = player0
		state.next_staff_id = staff_id + 1

		var providers_read := EmployeeRulesClass.try_get_drinks_procurers_for_working(state, 0)
		if not providers_read.ok:
			return Result.failure("测试状态读取采购员工 provider 失败: employee=%s error=%s" % [emp_id, providers_read.error])
		var providers: Array = providers_read.value
		if providers.is_empty():
			return Result.failure("测试状态未生成采购员工 provider: employee=%s" % emp_id)

		_working_panels.show_production_panel("drinks")

		if _map_controller.get_mode() != "procure_drinks":
			return Result.failure("进入选点模式失败: employee=%s mode=%s" % [emp_id, _map_controller.get_mode()])

		if not is_instance_valid(_working_panels.production_panel) or not _working_panels.production_panel.visible:
			return Result.failure("production_panel 未显示: employee=%s" % emp_id)

		if _working_panels.production_panel.has_method("get_selected_employee_type"):
			var selected_type := str(_working_panels.production_panel.call("get_selected_employee_type")).strip_edges()
			if selected_type != emp_id:
				return Result.failure("production_panel 默认选中员工错误: expected=%s got=%s" % [emp_id, selected_type])

		# 模拟执行/刷新链路清空地图选点后，面板在同一上下文重开且仍选中同一员工。
		# 这时 ProductionPanel 不会触发 producer_changed，ProductionController 必须显式同步当前选择。
		_map_controller.clear_selection()
		_working_panels.show_production_panel("drinks")
		if _map_controller.get_mode() != "procure_drinks":
			return Result.failure("同一采购员重开面板后未重新进入选点模式: employee=%s mode=%s" % [emp_id, _map_controller.get_mode()])

	if registry_engine != null and registry_engine.has_method("dispose"):
		registry_engine.dispose()
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
