# Game scene：后台 UI 预热控制器
# 负责：在不阻塞首帧交互的前提下，后台构建较重的面板（EmployeeTree / Milestones / ReserveArea）。
class_name GameBackgroundWarmupController
extends RefCounted

const PerfTraceClass = preload("res://core/debug/perf_trace.gd")

var _host: Node = null
var _get_game_engine: Callable = Callable()
var _panel_controller: Object = null
var _map_canvas: Control = null

var _started: bool = false

func _init(host: Node, get_game_engine: Callable, panel_controller: Object, map_canvas: Control) -> void:
	_host = host
	_get_game_engine = get_game_engine
	_panel_controller = panel_controller
	_map_canvas = map_canvas

func dispose() -> void:
	_host = null
	_get_game_engine = Callable()
	_panel_controller = null
	_map_canvas = null

func start_background_ui_warmup() -> void:
	if _started:
		return
	_started = true

	var span_warmup := PerfTraceClass.begin_span("game:background_ui_warmup")
	# 让游戏 UI 先进入可交互状态，再开始后台构建。
	if _host != null and is_instance_valid(_host):
		await _host.get_tree().process_frame
		await _host.get_tree().process_frame
	if _host == null or not is_instance_valid(_host):
		return

	var engine_val = _get_game_engine.call() if _get_game_engine.is_valid() else null
	var game_engine: GameEngine = engine_val if engine_val is GameEngine else null
	if game_engine == null or _panel_controller == null:
		return
	var state := game_engine.get_state()
	if state == null:
		return

	# 复用 MapCanvas 的 MapSkin；避免后台预热时触发 MapSkinBuilder 重复加载。
	var skin = null
	if is_instance_valid(_map_canvas) and _map_canvas.has_method("get_skin"):
		skin = _map_canvas.call("get_skin")

	# 1) 升级路线（EmployeeTree）
	var tree = _panel_controller.call("get_employee_tree_panel") if _panel_controller.has_method("get_employee_tree_panel") else null
	if is_instance_valid(tree) and tree.has_method("begin_background_build"):
		var span_tree := PerfTraceClass.begin_span("warmup:employee_tree")
		tree.call("begin_background_build")
		if tree.has_signal("build_finished"):
			await tree.build_finished
		PerfTraceClass.end_span(span_tree)
	if _host != null and is_instance_valid(_host):
		await _host.get_tree().process_frame
	if _host == null or not is_instance_valid(_host):
		return

	# 2) 里程碑全屏视图
	if skin != null:
		var ms = _panel_controller.call("get_milestone_full_screen_view") if _panel_controller.has_method("get_milestone_full_screen_view") else null
		if is_instance_valid(ms) and ms.has_method("begin_background_build"):
			var span_ms := PerfTraceClass.begin_span("warmup:milestones")
			ms.call("begin_background_build", state, skin)
			if ms.has_signal("build_finished"):
				await ms.build_finished
			PerfTraceClass.end_span(span_ms)
	if _host != null and is_instance_valid(_host):
		await _host.get_tree().process_frame
	if _host == null or not is_instance_valid(_host):
		return

	# 3) 供应堆全屏视图
	if skin != null:
		var supply = _panel_controller.call("get_reserve_area_full_screen_view") if _panel_controller.has_method("get_reserve_area_full_screen_view") else null
		if is_instance_valid(supply) and supply.has_method("begin_background_build"):
			var span_supply := PerfTraceClass.begin_span("warmup:supply_pile")
			supply.call("begin_background_build", state, skin)
			if supply.has_signal("build_finished"):
				await supply.build_finished
			PerfTraceClass.end_span(span_supply)

	PerfTraceClass.end_span(span_warmup)
