# 游戏主场景脚本
extends Control

# UI 节点引用
@onready var round_label: Label = $TopBar/RoundLabel
@onready var phase_label: Label = $TopBar/PhaseLabel
@onready var bank_label: Label = $TopBar/BankLabel
@onready var current_player_label: Label = $TopBar/CurrentPlayerLabel
@onready var state_hash_label: Label = $BottomBar/StateHashLabel
@onready var command_count_label: Label = $BottomBar/CommandCountLabel
@onready var menu_dialog: Window = $MenuDialog
@onready var debug_dialog: Window = $DebugDialog
@onready var debug_text: TextEdit = $DebugDialog/VBoxContainer/DebugText
@onready var map_view: ScrollContainer = $MainContent/CenterSplit/GameArea/MapView
@onready var map_canvas: Control = $MainContent/CenterSplit/GameArea/MapView/Canvas
@onready var game_log_panel: GameLogPanel = $MainContent/GameLogPanel

const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")
const MarketingRegistryClass = preload("res://core/data/marketing_registry.gd")
const PlacementValidatorClass = preload("res://core/map/placement_validator.gd")
const PieceDefClass = preload("res://core/map/piece_def.gd")
const EmployeeRulesClass = preload("res://core/rules/employee_rules.gd")

# 新 UI 组件引用
@onready var player_panel: Control = $MainContent/CenterSplit/RightPanel/PlayerPanel
@onready var turn_order_track: Control = $MainContent/CenterSplit/RightPanel/TurnOrderTrack
@onready var inventory_panel: Control = $MainContent/CenterSplit/RightPanel/InventoryPanel
@onready var action_panel: Control = $MainContent/CenterSplit/RightPanel/ActionPanel
@onready var hand_area: Control = $BottomPanel/HandArea
@onready var company_structure: Control = $BottomPanel/CompanyStructure

# P0 阶段面板（按需显示）
var recruit_panel: Control = null
var train_panel: Control = null
var payday_panel: Control = null
var game_over_panel: Control = null
var bank_break_panel: Control = null

# P1 阶段面板（按需显示）
var marketing_panel: Control = null
var price_panel: Control = null
var production_panel: Control = null
var restaurant_placement_overlay: Control = null
var house_placement_overlay: Control = null
var milestone_panel: Control = null
var dinner_time_overlay: Control = null

# P2 覆盖层和管理器（常驻或按需）
var distance_overlay: Control = null
var marketing_range_overlay: Control = null
var demand_indicator: Control = null
var settings_dialog: Window = null
var help_tooltip_manager: CanvasLayer = null
var ui_animation_manager: Node = null
var zoom_control: Control = null

# P0 预加载场景
const RecruitPanelScene = preload("res://ui/components/recruit_panel/recruit_panel.tscn")
const TrainPanelScene = preload("res://ui/components/train_panel/train_panel.tscn")
const PaydayPanelScene = preload("res://ui/components/payday_panel/payday_panel.tscn")
const GameOverPanelScene = preload("res://ui/components/game_over/game_over_panel.tscn")
const BankBreakPanelScene = preload("res://ui/components/bank_break/bank_break_panel.tscn")

# P1 预加载场景
const MarketingPanelScene = preload("res://ui/components/marketing_panel/marketing_panel.tscn")
const PricePanelScene = preload("res://ui/components/price_panel/price_setting_panel.tscn")
const ProductionPanelScene = preload("res://ui/components/production_panel/production_panel.tscn")
const RestaurantPlacementScene = preload("res://ui/components/restaurant_placement/restaurant_placement_overlay.tscn")
const HousePlacementScene = preload("res://ui/components/house_placement/house_placement_overlay.tscn")
const MilestonePanelScene = preload("res://ui/components/milestone_panel/milestone_panel.tscn")
const DinnerTimeOverlayScene = preload("res://ui/components/dinner_time/dinner_time_overlay.tscn")

# P2 预加载场景
const DistanceOverlayScene = preload("res://ui/overlays/distance_overlay.tscn")
const MarketingRangeOverlayScene = preload("res://ui/overlays/marketing_range_overlay.tscn")
const DemandIndicatorScene = preload("res://ui/components/demand_indicator/demand_indicator.tscn")
const SettingsDialogScene = preload("res://ui/dialogs/settings_dialog.tscn")
const HelpTooltipManagerScene = preload("res://ui/components/help_tooltip/help_tooltip_manager.tscn")
const UIAnimationManagerScene = preload("res://ui/visual/ui_animation_manager.tscn")
const ZoomControlScene = preload("res://ui/components/zoom_control/zoom_control.tscn")

# 游戏状态
var game_engine: GameEngine = null
var _last_bank_total: int = 0
var _last_bank_broke_count: int = 0
var _map_selection_mode: String = ""
var _map_selection_payload: Dictionary = {}
var _restaurant_valid_anchors: Dictionary = {} # Vector2i -> true

func _ready() -> void:
	GameLog.info("Game", "游戏场景已加载")
	_initialize_p2_managers()
	_initialize_game()
	_connect_signals()
	_connect_event_log()
	_update_ui()

func _initialize_p2_managers() -> void:
	# 初始化帮助提示管理器
	if help_tooltip_manager == null:
		help_tooltip_manager = HelpTooltipManagerScene.instantiate()
		add_child(help_tooltip_manager)

	# 初始化动画管理器
	if ui_animation_manager == null:
		ui_animation_manager = UIAnimationManagerScene.instantiate()
		add_child(ui_animation_manager)

	# 初始化游戏日志面板（但不显示）
	if is_instance_valid(game_log_panel):
		game_log_panel.visible = true

	# 初始化缩放控制
	_initialize_zoom_control()

func _connect_event_log() -> void:
	if not is_instance_valid(game_log_panel):
		return

	game_log_panel.clear_logs()
	game_log_panel.add_system_log("事件日志已启用")

	var event_types: Array[String] = [
		EventBus.EventType.PHASE_CHANGED,
		EventBus.EventType.SUB_PHASE_CHANGED,
		EventBus.EventType.ROUND_STARTED,
		EventBus.EventType.PLAYER_TURN_STARTED,
		EventBus.EventType.PLAYER_TURN_ENDED,
		EventBus.EventType.PLAYER_CASH_CHANGED,
		EventBus.EventType.EMPLOYEE_RECRUITED,
		EventBus.EventType.EMPLOYEE_TRAINED,
		EventBus.EventType.EMPLOYEE_FIRED,
		EventBus.EventType.RESTAURANT_PLACED,
		EventBus.EventType.RESTAURANT_MOVED,
		EventBus.EventType.HOUSE_PLACED,
		EventBus.EventType.GARDEN_ADDED,
		EventBus.EventType.FOOD_PRODUCED,
		EventBus.EventType.DRINKS_PROCURED,
		EventBus.EventType.MILESTONE_ACHIEVED,
	]

	for t in event_types:
		EventBus.subscribe(t, Callable(self, "_on_eventbus_event"), 100, "GameScene")

func _on_eventbus_event(event: Dictionary) -> void:
	if not is_instance_valid(game_log_panel):
		return
	if not (event is Dictionary) or event.is_empty():
		return

	var t: String = str(event.get("type", ""))
	var data: Dictionary = event.get("data", {})

	match t:
		EventBus.EventType.PHASE_CHANGED:
			game_log_panel.add_phase_log("%s -> %s (回合 %d)" % [
				str(data.get("old_phase", "")),
				str(data.get("new_phase", "")),
				int(data.get("round", -1)),
			], data)
		EventBus.EventType.SUB_PHASE_CHANGED:
			game_log_panel.add_phase_log("子阶段: %s -> %s" % [
				str(data.get("old_sub_phase", "")),
				str(data.get("new_sub_phase", "")),
			], data)
		EventBus.EventType.ROUND_STARTED:
			game_log_panel.add_phase_log("回合开始: %d" % int(data.get("round", -1)), data)
		EventBus.EventType.PLAYER_TURN_STARTED:
			game_log_panel.add_phase_log("玩家 %d 开始回合" % (int(data.get("player_id", -1)) + 1), data)
		EventBus.EventType.PLAYER_TURN_ENDED:
			game_log_panel.add_phase_log("玩家 %d 结束回合 (%s)" % [
				int(data.get("player_id", -1)) + 1,
				str(data.get("action", "")),
			], data)
		EventBus.EventType.PLAYER_CASH_CHANGED:
			game_log_panel.add_event_log("玩家 %d 现金变化: %d -> %d (%+d)" % [
				int(data.get("player_id", -1)) + 1,
				int(data.get("old_cash", 0)),
				int(data.get("new_cash", 0)),
				int(data.get("delta", 0)),
			], data)
		EventBus.EventType.EMPLOYEE_RECRUITED:
			game_log_panel.add_player_log(int(data.get("player_id", -1)), "招聘 %s" % str(data.get("employee_type", "")), data)
		EventBus.EventType.EMPLOYEE_TRAINED:
			game_log_panel.add_player_log(int(data.get("player_id", -1)), "培训 %s -> %s" % [
				str(data.get("from_employee", "")),
				str(data.get("to_employee", "")),
			], data)
		EventBus.EventType.EMPLOYEE_FIRED:
			game_log_panel.add_player_log(int(data.get("player_id", -1)), "解雇 %s" % str(data.get("employee_id", "")), data)
		EventBus.EventType.RESTAURANT_PLACED:
			game_log_panel.add_player_log(int(data.get("player_id", -1)), "放置餐厅", data)
		EventBus.EventType.RESTAURANT_MOVED:
			game_log_panel.add_player_log(int(data.get("player_id", -1)), "移动餐厅", data)
		EventBus.EventType.HOUSE_PLACED:
			game_log_panel.add_player_log(int(data.get("player_id", -1)), "放置房屋", data)
		EventBus.EventType.GARDEN_ADDED:
			game_log_panel.add_player_log(int(data.get("player_id", -1)), "添加花园", data)
		EventBus.EventType.FOOD_PRODUCED:
			game_log_panel.add_player_log(int(data.get("player_id", -1)), "生产 %s" % str(data.get("product", "")), data)
		EventBus.EventType.DRINKS_PROCURED:
			game_log_panel.add_player_log(int(data.get("player_id", -1)), "采购饮料", data)
		EventBus.EventType.MILESTONE_ACHIEVED:
			game_log_panel.add_event_log("里程碑达成: %s" % str(data.get("milestone_id", "")), data)
		_:
			game_log_panel.add_debug_log("%s: %s" % [t, str(data)], data)

func _initialize_zoom_control() -> void:
	if zoom_control == null:
		zoom_control = ZoomControlScene.instantiate()
		# 连接信号
		if zoom_control.has_signal("zoom_in_pressed"):
			zoom_control.zoom_in_pressed.connect(_on_zoom_in_pressed)
		if zoom_control.has_signal("zoom_out_pressed"):
			zoom_control.zoom_out_pressed.connect(_on_zoom_out_pressed)
		if zoom_control.has_signal("reset_pressed"):
			zoom_control.reset_pressed.connect(_on_zoom_reset_pressed)
		if zoom_control.has_signal("fit_pressed"):
			zoom_control.fit_pressed.connect(_on_zoom_fit_pressed)

		# 将缩放控制添加到地图区域
		# 查找 GameArea 节点并添加
		var game_area := get_node_or_null("MainContent/CenterSplit/GameArea")
		if game_area != null:
			zoom_control.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
			zoom_control.position = Vector2(-50, -160)
			game_area.add_child(zoom_control)
		else:
			add_child(zoom_control)

	# 连接 map_view 的缩放变化信号
	if is_instance_valid(map_view) and map_view.has_signal("zoom_changed"):
		if not map_view.zoom_changed.is_connected(_on_map_zoom_changed):
			map_view.zoom_changed.connect(_on_map_zoom_changed)

func _initialize_game() -> void:
	game_engine = GameEngine.new()
	var init_result := game_engine.initialize(Globals.player_count, Globals.random_seed, Globals.enabled_modules_v2, Globals.modules_v2_base_dir)
	if not init_result.ok:
		GameLog.error("Game", "游戏初始化失败: %s" % init_result.error)
		return

	Globals.current_game_engine = game_engine
	Globals.is_game_active = true

	GameLog.info("Game", "游戏初始化完成 - 玩家数: %d, 种子: %d" % [
		Globals.player_count,
		Globals.random_seed
	])
	GameLog.info("Game", "初始状态:\n%s" % game_engine.get_state().dump())

	# 用于检测银行破产弹窗
	var state := game_engine.get_state()
	_last_bank_total = int(state.bank.get("total", 0))
	_last_bank_broke_count = int(state.bank.get("broke_count", 0))

func _connect_signals() -> void:
	# 连接 action_panel 信号
	if is_instance_valid(action_panel) and action_panel.has_signal("action_requested"):
		action_panel.action_requested.connect(_on_action_requested)

	# 连接 turn_order_track 信号
	if is_instance_valid(turn_order_track) and turn_order_track.has_signal("position_selected"):
		turn_order_track.position_selected.connect(_on_turn_order_position_selected)

	# 连接 hand_area 信号
	if is_instance_valid(hand_area) and hand_area.has_signal("cards_selected"):
		hand_area.cards_selected.connect(_on_hand_cards_selected)

	# 连接 company_structure 信号
	if is_instance_valid(company_structure) and company_structure.has_signal("structure_changed"):
		company_structure.structure_changed.connect(_on_company_structure_changed)

	# 连接地图选点信号（用于营销/放置等交互）
	if is_instance_valid(map_canvas):
		if map_canvas.has_signal("cell_selected"):
			map_canvas.cell_selected.connect(_on_map_cell_selected)
		if map_canvas.has_signal("cell_hovered"):
			map_canvas.cell_hovered.connect(_on_map_cell_hovered)

func _update_ui() -> void:
	if game_engine == null:
		return

	var state := game_engine.get_state()
	round_label.text = "回合: %d" % state.round_number
	phase_label.text = "阶段: %s%s" % [
		state.phase,
		(" / %s" % state.sub_phase) if not state.sub_phase.is_empty() else ""
	]
	current_player_label.text = "玩家: %d" % (state.get_current_player_id() + 1)
	bank_label.text = "银行: $%d" % state.bank.get("total", 0)

	# 计算状态哈希（截断显示）
	var full_hash := state.compute_hash()
	state_hash_label.text = "Hash: %s..." % full_hash.substr(0, 8)

	# 命令计数
	command_count_label.text = "命令: %d" % game_engine.get_command_history().size()

	# 地图渲染（M2 接入）
	if is_instance_valid(map_view) and map_view.has_method("set_game_state"):
		map_view.call("set_game_state", state)

	# 更新新 UI 组件
	_update_ui_components(state)
	_sync_phase_panels(state)

	# 检查银行破产事件
	_check_bank_break(state)

	# 检查游戏结束
	if state.phase == "GameOver":
		_show_game_over()

	# 晚餐时间：只读可视化（来自 round_state["dinnertime"]）
	_update_dinnertime_overlay(state)
	_update_demand_indicator(state)

	if is_instance_valid(debug_dialog) and debug_dialog.visible:
		_update_debug_text()

func _update_ui_components(state: GameState) -> void:
	var current_player_id := state.get_current_player_id()
	var current_player: Dictionary = state.get_current_player()

	# 玩家面板
	if is_instance_valid(player_panel) and player_panel.has_method("set_game_state"):
		player_panel.set_game_state(state)
		if player_panel.has_method("set_current_player"):
			player_panel.set_current_player(current_player_id)

	# 顺序轨
	if is_instance_valid(turn_order_track):
		if turn_order_track.has_method("set_player_count"):
			turn_order_track.set_player_count(state.players.size())
		if turn_order_track.has_method("set_current_selections"):
			# 构建选择映射：position -> player_id
			# - OrderOfBusiness 阶段：使用 round_state.order_of_business.picks（position -> player_id/-1）
			# - 其他阶段：使用 state.turn_order（position -> player_id）
			var selections := {}
			if state.phase == "OrderOfBusiness" and (state.round_state is Dictionary):
				var rs: Dictionary = state.round_state
				var oob_val = rs.get("order_of_business", null)
				if oob_val is Dictionary:
					var oob: Dictionary = oob_val
					var picks_val = oob.get("picks", null)
					if picks_val is Array:
						var picks: Array = picks_val
						for pos in range(min(picks.size(), state.players.size())):
							var pid: int = int(picks[pos])
							if pid >= 0:
								selections[pos] = pid
			else:
				for i in range(state.turn_order.size()):
					if i < state.players.size():
						selections[i] = state.turn_order[i]
			turn_order_track.set_current_selections(selections)
		if turn_order_track.has_method("set_selectable"):
			var can_select := state.phase == "OrderOfBusiness"
			turn_order_track.set_selectable(can_select, current_player_id)
			if can_select and turn_order_track.has_method("highlight_available_positions"):
				turn_order_track.highlight_available_positions()

	# 库存面板
	if is_instance_valid(inventory_panel) and inventory_panel.has_method("set_inventory"):
		var inventory: Dictionary = current_player.get("inventory", {})
		inventory_panel.set_inventory(inventory)

	# 动作面板
	if is_instance_valid(action_panel):
		if action_panel.has_method("set_game_state"):
			action_panel.set_game_state(state)
		if action_panel.has_method("set_current_player"):
			action_panel.set_current_player(current_player_id)
		if action_panel.has_method("set_action_registry") and game_engine != null:
			var registry = game_engine.get_action_registry() if game_engine.has_method("get_action_registry") else null
			if registry != null:
				action_panel.set_action_registry(registry)

	# 员工手牌区
	if is_instance_valid(hand_area) and hand_area.has_method("set_employees"):
		var employees: Array[String] = []
		var reserve: Array[String] = []
		var busy: Array[String] = []

		for e in Array(current_player.get("employees", [])):
			employees.append(str(e))
		for e in Array(current_player.get("reserve_employees", [])):
			reserve.append(str(e))
		for e in Array(current_player.get("busy_marketers", [])):
			busy.append(str(e))

		hand_area.set_employees(employees, reserve, busy)

	# 公司结构面板
	if is_instance_valid(company_structure) and company_structure.has_method("set_player_data"):
		company_structure.set_player_data(current_player)

func _sync_phase_panels(state: GameState) -> void:
	_sync_recruit_panel(state)
	_sync_train_panel(state)
	_sync_marketing_panel(state)
	_sync_production_panel(state)
	_sync_payday_panel(state)
	_sync_price_panel(state)
	_sync_restaurant_placement_overlay(state)
	_sync_house_placement_overlay(state)

func _sync_recruit_panel(state: GameState) -> void:
	if state == null:
		return
	if not is_instance_valid(recruit_panel) or not recruit_panel.visible:
		return
	# 离开对应子阶段后，自动隐藏（避免跨阶段残留导致 UI 误导）
	if state.phase != "Working" or state.sub_phase != "Recruit":
		recruit_panel.visible = false
		return
	if recruit_panel.has_method("set_recruit_count"):
		var actor := state.get_current_player_id()
		var counts := _compute_recruit_counts(state, actor)
		recruit_panel.set_recruit_count(int(counts.remaining), int(counts.total))

func _sync_train_panel(state: GameState) -> void:
	if state == null:
		return
	if not is_instance_valid(train_panel) or not train_panel.visible:
		return
	if state.phase != "Working" or state.sub_phase != "Train":
		train_panel.visible = false
		return

func _sync_marketing_panel(state: GameState) -> void:
	if state == null:
		return
	if not is_instance_valid(marketing_panel) or not marketing_panel.visible:
		return
	if state.phase != "Working" or state.sub_phase != "Marketing":
		marketing_panel.visible = false
		_clear_map_selection()
		return

func _sync_production_panel(state: GameState) -> void:
	if state == null:
		return
	if not is_instance_valid(production_panel) or not production_panel.visible:
		return
	if state.phase != "Working":
		production_panel.visible = false
		return
	if state.sub_phase != "GetFood" and state.sub_phase != "GetDrinks":
		production_panel.visible = false
		return

func _sync_payday_panel(state: GameState) -> void:
	if state == null:
		return
	if not is_instance_valid(payday_panel) or not payday_panel.visible:
		return
	if state.phase != "Payday":
		payday_panel.visible = false
		return

func _sync_price_panel(state: GameState) -> void:
	if state == null:
		return
	if not is_instance_valid(price_panel) or not price_panel.visible:
		return
	if state.phase != "Working":
		price_panel.visible = false
		return

func _sync_restaurant_placement_overlay(state: GameState) -> void:
	if state == null:
		return
	if not is_instance_valid(restaurant_placement_overlay) or not restaurant_placement_overlay.visible:
		return

	var allowed := false
	if state.phase == "Setup":
		allowed = true
	elif state.phase == "Working" and state.sub_phase == "PlaceRestaurants":
		allowed = true

	if not allowed:
		restaurant_placement_overlay.visible = false
		_clear_map_selection()
		return

func _sync_house_placement_overlay(state: GameState) -> void:
	if state == null:
		return
	if not is_instance_valid(house_placement_overlay) or not house_placement_overlay.visible:
		return
	if state.phase != "Working" or state.sub_phase != "PlaceHouses":
		house_placement_overlay.visible = false
		_clear_map_selection()
		return

func _on_menu_pressed() -> void:
	GameLog.info("Game", "打开游戏菜单")
	menu_dialog.show()

func _on_menu_dialog_close_requested() -> void:
	menu_dialog.hide()

func _on_resume_pressed() -> void:
	GameLog.info("Game", "继续游戏")
	menu_dialog.hide()

func _on_save_pressed() -> void:
	GameLog.info("Game", "保存游戏")
	if game_engine == null:
		GameLog.warn("Game", "游戏引擎未初始化，无法保存")
		menu_dialog.hide()
		return

	var path := "user://savegame.json"
	var save_result := game_engine.save_to_file(path)
	if not save_result.ok:
		GameLog.error("Game", "保存失败: %s" % save_result.error)
	else:
		GameLog.info("Game", "已保存到: %s" % path)
	menu_dialog.hide()

func _on_quit_to_menu_pressed() -> void:
	GameLog.info("Game", "返回主菜单")
	Globals.reset_game_config()
	SceneManager.goto_main_menu()

func _on_debug_pressed() -> void:
	GameLog.info("Game", "打开调试窗口")
	_update_debug_text()
	debug_dialog.show()

func _on_debug_dialog_close_requested() -> void:
	debug_dialog.hide()

func _update_debug_text() -> void:
	if game_engine == null:
		return
	if not is_instance_valid(debug_text):
		return
	var state := game_engine.get_state()

	var lines: Array[String] = []
	lines.append("round=%d phase=%s sub_phase=%s current_player=%d" % [
		state.round_number,
		state.phase,
		state.sub_phase,
		state.get_current_player_id(),
	])
	lines.append("")
	lines.append("bank=%s" % str(state.bank))
	lines.append("")
	lines.append("marketing_instances=%s" % str(state.marketing_instances))
	lines.append("")
	lines.append("round_state=%s" % str(state.round_state))

	debug_text.text = "\n".join(lines)

func _execute_command(command: Command) -> Result:
	if game_engine == null:
		return Result.failure("游戏引擎未初始化")

	var result := game_engine.execute_command(command)
	if not result.ok:
		GameLog.warn("Game", "命令执行失败: %s" % result.error)
	else:
		GameLog.info("Game", "命令执行成功: %s" % command.action_id)

	_update_ui()
	return result

func _check_bank_break(state: GameState) -> void:
	if state == null:
		return
	if not (state.bank is Dictionary):
		return

	var bank: Dictionary = state.bank
	var broke_count := int(bank.get("broke_count", 0))
	var bank_total := int(bank.get("total", 0))

	if broke_count > _last_bank_broke_count:
		_show_bank_break_panel(broke_count, _last_bank_total, bank_total)

	_last_bank_broke_count = broke_count
	_last_bank_total = bank_total

func _begin_map_selection(mode: String, payload: Dictionary = {}) -> void:
	_map_selection_mode = mode
	_map_selection_payload = payload.duplicate(true)
	if mode != "restaurant_placement":
		_restaurant_valid_anchors.clear()
		if is_instance_valid(map_canvas) and map_canvas.has_method("clear_cell_highlights"):
			map_canvas.call("clear_cell_highlights")

func _clear_map_selection() -> void:
	_map_selection_mode = ""
	_map_selection_payload.clear()
	if is_instance_valid(map_canvas) and map_canvas.has_method("clear_structure_preview"):
		map_canvas.call("clear_structure_preview")
	if is_instance_valid(map_canvas) and map_canvas.has_method("clear_cell_highlights"):
		map_canvas.call("clear_cell_highlights")
	_restaurant_valid_anchors.clear()

func _on_map_cell_selected(world_pos: Vector2i) -> void:
	if world_pos == Vector2i(-1, -1):
		return

	match _map_selection_mode:
		"marketing":
			if is_instance_valid(marketing_panel) and marketing_panel.visible and marketing_panel.has_method("set_selected_target"):
				marketing_panel.set_selected_target(world_pos)

			var mt := str(_map_selection_payload.get("marketing_type", ""))
			var range_val := int(_map_selection_payload.get("range", 0))
			if not mt.is_empty():
				preview_marketing_range(world_pos, range_val, mt)
		"restaurant_placement":
			# 仅允许点击“高亮的合法格”
			if _restaurant_valid_anchors.is_empty() or not _restaurant_valid_anchors.has(world_pos):
				if is_instance_valid(restaurant_placement_overlay) and restaurant_placement_overlay.visible and restaurant_placement_overlay.has_method("set_validation"):
					restaurant_placement_overlay.set_validation(false, "请选择绿色高亮的可放置格")
				return
			if is_instance_valid(restaurant_placement_overlay) and restaurant_placement_overlay.visible and restaurant_placement_overlay.has_method("set_selected_position"):
				restaurant_placement_overlay.set_selected_position(world_pos)
		"house_placement":
			if is_instance_valid(house_placement_overlay) and house_placement_overlay.visible and house_placement_overlay.has_method("set_selected_position"):
				house_placement_overlay.set_selected_position(world_pos)
		_:
			pass

func _on_map_cell_hovered(world_pos: Vector2i) -> void:
	if _map_selection_mode != "marketing":
		return
	if world_pos == Vector2i(-1, -1):
		hide_marketing_range_overlay()
		return

	var mt := str(_map_selection_payload.get("marketing_type", ""))
	var range_val := int(_map_selection_payload.get("range", 0))
	if mt.is_empty():
		return

	preview_marketing_range(world_pos, range_val, mt)

func _on_marketing_map_selection_requested(marketing_type: String, range_val: int) -> void:
	_begin_map_selection("marketing", {
		"marketing_type": marketing_type,
		"range": range_val,
	})
	hide_marketing_range_overlay()

func _build_marketing_marketer_entries(current_player: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if current_player.is_empty():
		return out
	if not EmployeeRegistryClass.is_loaded():
		return out

	var employees_val = current_player.get("employees", null)
	if not (employees_val is Array):
		return out
	var employees: Array = employees_val

	var busy_val = current_player.get("busy_marketers", [])
	var busy: Array = busy_val if busy_val is Array else []

	var employee_counts: Dictionary = {}
	for e in employees:
		if not (e is String):
			continue
		var emp_id := str(e)
		if emp_id.is_empty():
			continue
		employee_counts[emp_id] = int(employee_counts.get(emp_id, 0)) + 1

	var busy_counts: Dictionary = {}
	for b in busy:
		if not (b is String):
			continue
		var emp_id2 := str(b)
		if emp_id2.is_empty():
			continue
		busy_counts[emp_id2] = int(busy_counts.get(emp_id2, 0)) + 1

	for emp_id3_val in employee_counts.keys():
		var emp_id3 := str(emp_id3_val)
		if emp_id3.is_empty():
			continue
		var total_count := int(employee_counts.get(emp_id3, 0))
		var busy_count := int(busy_counts.get(emp_id3, 0))
		var available_count := maxi(0, total_count - busy_count)
		if available_count <= 0:
			continue

		var def_val = EmployeeRegistryClass.get_def(emp_id3)
		if def_val == null or not (def_val is EmployeeDef):
			continue
		var def: EmployeeDef = def_val

		var max_duration := int(def.marketing_max_duration)
		if max_duration <= 0:
			continue

		var marketing_types: Array[String] = []
		var type_set: Dictionary = {}
		for tag in def.usage_tags:
			var t := str(tag)
			if not t.begins_with("use:marketing:"):
				continue
			var type_id := t.substr("use:marketing:".length())
			if type_id.is_empty():
				continue
			type_set[type_id] = true
		for k in type_set.keys():
			marketing_types.append(str(k))
		marketing_types.sort()

		for mt in marketing_types:
			for i in range(available_count):
				out.append({
					"id": emp_id3,
					"type": mt,
					"max_duration": max_duration,
				})

	return out

func _build_available_marketing_boards_by_type(state: GameState) -> Dictionary:
	var out: Dictionary = {}
	if state == null:
		return out
	if not MarketingRegistryClass.is_loaded():
		return out

	var used: Dictionary = {}

	for inst_val in state.marketing_instances:
		if not (inst_val is Dictionary):
			continue
		var inst: Dictionary = inst_val
		var bn_val = inst.get("board_number", null)
		if bn_val is int:
			used[int(bn_val)] = true
		elif bn_val is float:
			var f: float = float(bn_val)
			if f == floor(f):
				used[int(f)] = true

	if state.map.has("marketing_placements") and (state.map["marketing_placements"] is Dictionary):
		var placements: Dictionary = state.map["marketing_placements"]
		for k in placements.keys():
			if not (k is String):
				continue
			var s := str(k)
			if not s.is_valid_int():
				continue
			var bn := int(s)
			if bn > 0:
				used[bn] = true

	var player_count := state.players.size()
	for bn2 in MarketingRegistryClass.get_all_board_numbers():
		if used.has(bn2):
			continue
		var def_val2 = MarketingRegistryClass.get_def(bn2)
		if def_val2 == null or not def_val2.has_method("is_available_for_player_count"):
			continue
		if not def_val2.is_available_for_player_count(player_count):
			continue
		var type_id2 := str(def_val2.type)
		if type_id2.is_empty():
			continue
		if not out.has(type_id2):
			out[type_id2] = []
		var arr: Array = out[type_id2]
		arr.append(bn2)
		out[type_id2] = arr

	for tid in out.keys():
		var arr2: Array = out[tid]
		arr2.sort()
		out[tid] = arr2

	return out

func _on_advance_phase_pressed() -> void:
	_execute_command(Command.create_system("advance_phase"))

func _on_advance_sub_phase_pressed() -> void:
	_execute_command(Command.create_system("advance_phase", {"target": "sub_phase"}))

func _on_skip_pressed() -> void:
	if game_engine == null:
		return
	var current_player_id := game_engine.get_state().get_current_player_id()
	_execute_command(Command.create("skip", current_player_id))

# 获取当前状态的关键值（用于调试）
func get_key_values() -> Dictionary:
	if game_engine != null:
		return game_engine.get_state().extract_key_values()
	return {}

# === 动作信号处理 ===

func _on_action_requested(action_id: String, params: Dictionary) -> void:
	if game_engine == null:
		return

	var current_player_id := game_engine.get_state().get_current_player_id()

	# 根据 action_id 处理不同动作
	match action_id:
		# 系统动作
		"advance_phase":
			_execute_command(Command.create_system("advance_phase", params))
		"skip":
			_execute_command(Command.create("skip", current_player_id, params))
		"choose_turn_order":
			# 选择顺序通过点击顺序轨完成；这里仅做引导高亮
			if is_instance_valid(turn_order_track) and turn_order_track.has_method("highlight_available_positions"):
				turn_order_track.highlight_available_positions()

		# P0 动作 - 需要弹出面板
		"recruit":
			_show_recruit_panel()
		"train":
			_show_train_panel()
		"fire":
			_show_payday_panel()

		# P1 动作 - 需要弹出面板
		"initiate_marketing":
			_show_marketing_panel()
		"set_price", "set_luxury_price", "set_discount":
			_show_price_panel(action_id)
		"produce_food":
			_show_production_panel("food")
		"procure_drinks":
			_show_production_panel("drinks")
		"place_restaurant", "move_restaurant":
			_show_restaurant_placement(action_id, params)
		"place_house", "add_garden":
			_show_house_placement(action_id, params)

		# 其他动作直接创建命令
		_:
			_execute_command(Command.create(action_id, current_player_id, params))

func _on_turn_order_position_selected(position: int) -> void:
	if game_engine == null:
		return
	var current_player_id := game_engine.get_state().get_current_player_id()
	_execute_command(Command.create("choose_turn_order", current_player_id, {"position": position}))

func _on_hand_cards_selected(employee_ids: Array[String]) -> void:
	# 可用于重组阶段的员工选择
	GameLog.info("Game", "选中员工: %s" % str(employee_ids))

func _on_company_structure_changed(new_structure: Dictionary) -> void:
	# 可用于提交公司结构变更
	GameLog.info("Game", "公司结构变更: %s" % str(new_structure))

# === 阶段面板管理 ===

func _show_recruit_panel() -> void:
	_hide_all_phase_panels()

	if recruit_panel == null:
		recruit_panel = RecruitPanelScene.instantiate()
		recruit_panel.recruit_requested.connect(_on_recruit_requested)
		add_child(recruit_panel)

	# 设置数据
	var state := game_engine.get_state()

	if recruit_panel.has_method("set_employee_pool"):
		recruit_panel.set_employee_pool(state.employee_pool)

	if recruit_panel.has_method("set_recruit_count"):
		var actor := state.get_current_player_id()
		var counts := _compute_recruit_counts(state, actor)
		recruit_panel.set_recruit_count(int(counts.remaining), int(counts.total))

	recruit_panel.visible = true
	_center_popup(recruit_panel)

func _compute_recruit_counts(state: GameState, player_id: int) -> Dictionary:
	if state == null:
		return {"remaining": 0, "total": 0}
	var total: int = EmployeeRulesClass.get_recruit_limit_for_working(state, player_id)
	var used: int = EmployeeRulesClass.get_action_count(state, player_id, "recruit")
	return {"remaining": maxi(0, total - used), "total": total}

func _show_train_panel() -> void:
	_hide_all_phase_panels()

	if train_panel == null:
		train_panel = TrainPanelScene.instantiate()
		train_panel.train_requested.connect(_on_train_requested)
		add_child(train_panel)

	# 设置数据
	var state := game_engine.get_state()
	var current_player: Dictionary = state.get_current_player()

	if train_panel.has_method("set_employee_pool"):
		train_panel.set_employee_pool(state.employee_pool)

	if train_panel.has_method("set_trainable_employees"):
		var reserve: Array[String] = []
		for e in Array(current_player.get("reserve_employees", [])):
			reserve.append(str(e))
		train_panel.set_trainable_employees(reserve)

	if train_panel.has_method("set_train_count"):
		var round_state: Dictionary = state.round_state
		var remaining: int = int(round_state.get("train_remaining", 0))
		var total: int = int(round_state.get("train_total", 0))
		train_panel.set_train_count(remaining, total)

	train_panel.visible = true
	_center_popup(train_panel)

func _show_payday_panel() -> void:
	_hide_all_phase_panels()

	if payday_panel == null:
		payday_panel = PaydayPanelScene.instantiate()
		payday_panel.fire_employees.connect(_on_fire_employees)
		payday_panel.pay_confirmed.connect(_on_pay_confirmed)
		add_child(payday_panel)

	# 设置数据
	var state := game_engine.get_state()
	var current_player: Dictionary = state.get_current_player()

	if payday_panel.has_method("set_employees"):
		var employees: Array[String] = []
		var busy: Array[String] = []
		for e in Array(current_player.get("employees", [])):
			employees.append(str(e))
		for e in Array(current_player.get("busy_marketers", [])):
			busy.append(str(e))
		payday_panel.set_employees(employees, busy)

	if payday_panel.has_method("set_player_cash"):
		payday_panel.set_player_cash(int(current_player.get("cash", 0)))

	if payday_panel.has_method("set_discount"):
		var round_state: Dictionary = state.round_state
		var discount: int = int(round_state.get("salary_discount", 0))
		payday_panel.set_discount(discount)

	payday_panel.visible = true
	_center_popup(payday_panel)

func _show_game_over() -> void:
	_hide_all_phase_panels()

	if game_over_panel == null:
		game_over_panel = GameOverPanelScene.instantiate()
		game_over_panel.return_to_menu_requested.connect(_on_game_over_return)
		game_over_panel.play_again_requested.connect(_on_game_over_play_again)
		add_child(game_over_panel)

	if game_over_panel.has_method("set_final_state"):
		game_over_panel.set_final_state(game_engine.get_state())

	if game_over_panel.has_method("show_with_animation"):
		game_over_panel.show_with_animation()
	else:
		game_over_panel.visible = true

func _hide_all_phase_panels() -> void:
	# P0 面板
	if is_instance_valid(recruit_panel):
		recruit_panel.visible = false
	if is_instance_valid(train_panel):
		train_panel.visible = false
	if is_instance_valid(payday_panel):
		payday_panel.visible = false
	if is_instance_valid(bank_break_panel):
		bank_break_panel.visible = false

	# P1 面板
	if is_instance_valid(marketing_panel):
		marketing_panel.visible = false
	if is_instance_valid(price_panel):
		price_panel.visible = false
	if is_instance_valid(production_panel):
		production_panel.visible = false
	if is_instance_valid(milestone_panel):
		milestone_panel.visible = false
	if is_instance_valid(dinner_time_overlay):
		dinner_time_overlay.visible = false

	# 同时隐藏覆盖层
	_hide_all_overlays()
	_clear_map_selection()
	hide_marketing_range_overlay()

func _center_popup(panel: Control) -> void:
	if panel == null:
		return
	# 居中显示
	await get_tree().process_frame
	var viewport_size := get_viewport_rect().size
	var panel_size := panel.size
	panel.position = (viewport_size - panel_size) / 2

# === 阶段面板信号处理 ===

func _on_recruit_requested(employee_type: String) -> void:
	if game_engine == null:
		return
	var current_player_id := game_engine.get_state().get_current_player_id()
	var result := _execute_command(Command.create("recruit", current_player_id, {"employee_type": employee_type}))

	if result.ok:
		# 刷新面板数据
		var state := game_engine.get_state()
		if is_instance_valid(recruit_panel) and recruit_panel.has_method("set_employee_pool"):
			recruit_panel.set_employee_pool(state.employee_pool)
		_sync_recruit_panel(state)

func _on_train_requested(from_employee: String, to_employee: String) -> void:
	if game_engine == null:
		return
	var current_player_id := game_engine.get_state().get_current_player_id()
	var result := _execute_command(Command.create("train", current_player_id, {
		"from_employee": from_employee,
		"to_employee": to_employee
	}))

	if result.ok:
		# 刷新面板数据
		_show_train_panel()

func _on_fire_employees(employee_ids: Array[String]) -> void:
	if game_engine == null:
		return
	var current_player_id := game_engine.get_state().get_current_player_id()

	for emp_id in employee_ids:
		_execute_command(Command.create("fire", current_player_id, {"employee_id": emp_id}))

	# 刷新面板数据
	if is_instance_valid(payday_panel):
		_show_payday_panel()

func _on_pay_confirmed() -> void:
	_hide_all_phase_panels()
	# 发薪日结束后自动推进阶段
	_execute_command(Command.create_system("advance_phase"))

func _on_game_over_return() -> void:
	Globals.reset_game_config()
	SceneManager.goto_main_menu()

func _on_game_over_play_again() -> void:
	# 使用相同设置重新开始
	SceneManager.goto_game()

# === P1 面板管理 ===

func _show_marketing_panel() -> void:
	_hide_all_phase_panels()

	if marketing_panel == null:
		marketing_panel = MarketingPanelScene.instantiate()
		if marketing_panel.has_signal("marketing_requested"):
			marketing_panel.marketing_requested.connect(_on_marketing_requested)
		if marketing_panel.has_signal("cancelled"):
			marketing_panel.cancelled.connect(_on_panel_cancelled)
		add_child(marketing_panel)

	var state := game_engine.get_state()
	var current_player: Dictionary = state.get_current_player()

	_clear_map_selection()

	if marketing_panel.has_method("clear_selection"):
		marketing_panel.clear_selection()

	# 让面板在选择类型后进入“地图选点”模式
	if marketing_panel.has_method("set_map_selection_callback"):
		marketing_panel.set_map_selection_callback(Callable(self, "_on_marketing_map_selection_requested"))

	# 设置可用营销员（按 usage_tags 计算；并考虑 busy_marketers 的数量）
	if marketing_panel.has_method("set_available_marketers"):
		marketing_panel.set_available_marketers(_build_marketing_marketer_entries(current_player))

	# 设置可用营销板件（按 player_count/已占用过滤）
	if marketing_panel.has_method("set_available_boards"):
		marketing_panel.set_available_boards(_build_available_marketing_boards_by_type(state))

	marketing_panel.visible = true
	_center_popup(marketing_panel)

func _show_price_panel(action_id: String) -> void:
	_hide_all_phase_panels()

	if price_panel == null:
		price_panel = PricePanelScene.instantiate()
		if price_panel.has_signal("price_confirmed"):
			price_panel.price_confirmed.connect(_on_price_confirmed)
		if price_panel.has_signal("cancelled"):
			price_panel.cancelled.connect(_on_panel_cancelled)
		add_child(price_panel)

	var state := game_engine.get_state()
	var current_player: Dictionary = state.get_current_player()

	# 根据动作类型设置面板模式
	if price_panel.has_method("set_mode"):
		match action_id:
			"set_price":
				price_panel.set_mode("price")
			"set_luxury_price":
				price_panel.set_mode("luxury")
			"set_discount":
				price_panel.set_mode("discount")

	# 设置当前价格数据
	if price_panel.has_method("set_current_prices"):
		var prices: Dictionary = current_player.get("prices", {})
		price_panel.set_current_prices(prices)

	price_panel.visible = true
	_center_popup(price_panel)

func _show_production_panel(production_type: String) -> void:
	_hide_all_phase_panels()

	if production_panel == null:
		production_panel = ProductionPanelScene.instantiate()
		if production_panel.has_signal("production_requested"):
			production_panel.production_requested.connect(_on_production_requested)
		if production_panel.has_signal("cancelled"):
			production_panel.cancelled.connect(_on_panel_cancelled)
		add_child(production_panel)

	var state := game_engine.get_state()
	var current_player: Dictionary = state.get_current_player()

	# 设置生产类型
	if production_panel.has_method("set_production_type"):
		production_panel.set_production_type(production_type)

	# 设置可用厨房员工
	if production_panel.has_method("set_available_producers"):
		var producers: Array[String] = []
		if EmployeeRegistryClass.is_loaded():
			for e in Array(current_player.get("employees", [])):
				if not (e is String):
					continue
				var emp_id := str(e)
				if emp_id.is_empty():
					continue
				var def_val = EmployeeRegistryClass.get_def(emp_id)
				if def_val == null or not (def_val is EmployeeDef):
					continue
				var def: EmployeeDef = def_val
				if production_type == "food" and def.can_produce():
					producers.append(emp_id)
				elif production_type == "drinks" and def.can_procure():
					producers.append(emp_id)
		else:
			for e in Array(current_player.get("employees", [])):
				producers.append(str(e))
		production_panel.set_available_producers(producers)

	# 设置当前库存
	if production_panel.has_method("set_current_inventory"):
		production_panel.set_current_inventory(current_player.get("inventory", {}))

	production_panel.visible = true
	_center_popup(production_panel)

func _show_restaurant_placement(action_id: String, params: Dictionary) -> void:
	_hide_all_phase_panels()

	if restaurant_placement_overlay == null:
		restaurant_placement_overlay = RestaurantPlacementScene.instantiate()
		if restaurant_placement_overlay.has_signal("placement_confirmed"):
			restaurant_placement_overlay.placement_confirmed.connect(_on_restaurant_placement_confirmed)
		if restaurant_placement_overlay.has_signal("cancelled"):
			restaurant_placement_overlay.cancelled.connect(_on_overlay_cancelled)
		if restaurant_placement_overlay.has_signal("preview_requested"):
			restaurant_placement_overlay.preview_requested.connect(_on_restaurant_preview_requested)
		if restaurant_placement_overlay.has_signal("preview_cleared"):
			restaurant_placement_overlay.preview_cleared.connect(_on_restaurant_preview_cleared)
		if restaurant_placement_overlay.has_signal("highlight_requested"):
			restaurant_placement_overlay.highlight_requested.connect(_on_restaurant_highlight_requested)
		add_child(restaurant_placement_overlay)

	var state := game_engine.get_state()
	var current_player: Dictionary = state.get_current_player()

	# 先进入“地图选点模式”，让 overlay 发出的高亮/预览信号不会被忽略
	_begin_map_selection("restaurant_placement", {"action_id": action_id})
	restaurant_placement_overlay.visible = true

	# 设置操作模式
	if restaurant_placement_overlay.has_method("set_mode"):
		restaurant_placement_overlay.set_mode(action_id)

	# 设置地图数据
	if restaurant_placement_overlay.has_method("set_map_data"):
		restaurant_placement_overlay.set_map_data(state.map)

	# 如果是移动餐厅，设置选中的餐厅
	if action_id == "move_restaurant":
		if restaurant_placement_overlay.has_method("set_available_restaurants"):
			var ids: Array[String] = []
			for rid in Array(current_player.get("restaurants", [])):
				ids.append(str(rid))
			restaurant_placement_overlay.set_available_restaurants(ids)

		if params.has("restaurant_id") and restaurant_placement_overlay.has_method("set_selected_restaurant"):
			restaurant_placement_overlay.set_selected_restaurant(str(params.restaurant_id))
	_on_restaurant_preview_cleared()

func _show_house_placement(action_id: String, params: Dictionary) -> void:
	_hide_all_phase_panels()

	if house_placement_overlay == null:
		house_placement_overlay = HousePlacementScene.instantiate()
		if house_placement_overlay.has_signal("house_placement_confirmed"):
			house_placement_overlay.house_placement_confirmed.connect(_on_house_placement_confirmed)
		if house_placement_overlay.has_signal("garden_confirmed"):
			house_placement_overlay.garden_confirmed.connect(_on_garden_confirmed)
		if house_placement_overlay.has_signal("cancelled"):
			house_placement_overlay.cancelled.connect(_on_overlay_cancelled)
		add_child(house_placement_overlay)

	var state := game_engine.get_state()

	# 设置操作模式
	if house_placement_overlay.has_method("set_mode"):
		house_placement_overlay.set_mode(action_id)

	# 设置地图数据
	if house_placement_overlay.has_method("set_map_data"):
		house_placement_overlay.set_map_data(state.map)

	house_placement_overlay.visible = true
	_begin_map_selection("house_placement", {"action_id": action_id})

func _show_milestone_panel() -> void:
	_hide_all_phase_panels()

	if milestone_panel == null:
		milestone_panel = MilestonePanelScene.instantiate()
		if milestone_panel.has_signal("cancelled"):
			milestone_panel.cancelled.connect(_on_panel_cancelled)
		add_child(milestone_panel)

	var state := game_engine.get_state()
	var current_player: Dictionary = state.get_current_player()

	# 设置里程碑数据
	if milestone_panel.has_method("set_milestone_pool"):
		milestone_panel.set_milestone_pool(state.milestone_pool)

	if milestone_panel.has_method("set_player_milestones"):
		milestone_panel.set_player_milestones(current_player.get("milestones", []))

	milestone_panel.visible = true
	_center_popup(milestone_panel)

func _show_bank_break_panel(broke_count: int, bank_before: int, bank_after: int) -> void:
	_hide_all_phase_panels()

	if bank_break_panel == null:
		bank_break_panel = BankBreakPanelScene.instantiate()
		if bank_break_panel.has_signal("bankruptcy_acknowledged"):
			bank_break_panel.bankruptcy_acknowledged.connect(_on_bank_break_acknowledged)
		if bank_break_panel.has_signal("game_end_triggered"):
			bank_break_panel.game_end_triggered.connect(_on_bank_break_game_end_triggered)
		add_child(bank_break_panel)

	if bank_break_panel.has_method("set_bankruptcy_info"):
		bank_break_panel.set_bankruptcy_info(broke_count, bank_before, bank_after)

	if bank_break_panel.has_method("show_with_animation"):
		bank_break_panel.show_with_animation()
	else:
		bank_break_panel.visible = true

	_center_popup(bank_break_panel)

# === P1 面板信号处理 ===

func _on_marketing_requested(employee_type: String, board_number: int, position: Vector2i, product: String, duration: int) -> void:
	if game_engine == null:
		return
	var current_player_id := game_engine.get_state().get_current_player_id()
	var result := _execute_command(Command.create("initiate_marketing", current_player_id, {
		"employee_type": employee_type,
		"board_number": board_number,
		"position": [position.x, position.y],
		"product": product,
		"duration": duration
	}))

	if result.ok:
		_clear_map_selection()
		hide_marketing_range_overlay()
		_hide_all_phase_panels()

func _on_price_confirmed(action_id: String) -> void:
	if game_engine == null:
		return
	var current_player_id := game_engine.get_state().get_current_player_id()
	if action_id.is_empty():
		return
	var result := _execute_command(Command.create(action_id, current_player_id))

	if result.ok:
		_hide_all_phase_panels()

func _on_production_requested(employee_type: String, product_type: String) -> void:
	if game_engine == null:
		return
	var current_player_id := game_engine.get_state().get_current_player_id()
	var action_id := "produce_food" if product_type == "food" else "procure_drinks"
	var result := _execute_command(Command.create(action_id, current_player_id, {
		"employee_type": employee_type
	}))

	if result.ok:
		# 刷新生产面板
		if is_instance_valid(production_panel):
			var state := game_engine.get_state()
			var current_player: Dictionary = state.get_current_player()
			if production_panel.has_method("set_current_inventory"):
				production_panel.set_current_inventory(current_player.get("inventory", {}))

func _on_restaurant_placement_confirmed(position: Vector2i, rotation: int, restaurant_id: String) -> void:
	if game_engine == null:
		return
	var current_player_id := game_engine.get_state().get_current_player_id()
	var params := {
		"position": [position.x, position.y],
		"rotation": rotation
	}
	var action_id := "place_restaurant"
	if not restaurant_id.is_empty():
		action_id = "move_restaurant"
		params["restaurant_id"] = restaurant_id

	var result := _execute_command(Command.create(action_id, current_player_id, params))
	if result.ok:
		_clear_map_selection()
		_hide_all_overlays()
	else:
		# 在覆盖层内显示错误（A：不弹窗）
		if is_instance_valid(restaurant_placement_overlay) and restaurant_placement_overlay.has_method("set_validation"):
			restaurant_placement_overlay.set_validation(false, result.error)

func _on_restaurant_preview_cleared() -> void:
	if is_instance_valid(map_canvas) and map_canvas.has_method("clear_structure_preview"):
		map_canvas.call("clear_structure_preview")
	if is_instance_valid(restaurant_placement_overlay) and restaurant_placement_overlay.has_method("set_validation"):
		restaurant_placement_overlay.set_validation(true, "")

func _on_restaurant_highlight_requested(mode: String, rotation: int, restaurant_id: String) -> void:
	if _map_selection_mode != "restaurant_placement":
		return
	if not (is_instance_valid(restaurant_placement_overlay) and restaurant_placement_overlay.visible):
		return
	if game_engine == null:
		return
	var state := game_engine.get_state()
	if state == null:
		return

	var actor: int = state.get_current_player_id()
	var action_id := "place_restaurant" if mode != "move_restaurant" else "move_restaurant"

	# move_restaurant：未选择餐厅前不高亮
	if action_id == "move_restaurant" and restaurant_id.is_empty():
		_restaurant_valid_anchors.clear()
		if is_instance_valid(map_canvas) and map_canvas.has_method("clear_cell_highlights"):
			map_canvas.call("clear_cell_highlights")
		return

	var executor = game_engine.get_action_registry().get_executor(action_id)
	if executor == null:
		return

	if not (state.map is Dictionary):
		return
	if not state.map.has("grid_size") or not (state.map["grid_size"] is Vector2i):
		return
	var grid_size: Vector2i = state.map["grid_size"]
	var map_origin = state.map.get("map_origin", Vector2i.ZERO)
	if not (map_origin is Vector2i):
		map_origin = Vector2i.ZERO

	var anchors: Array[Vector2i] = []
	var anchor_set := {}

	for y in range(grid_size.y):
		for x in range(grid_size.x):
			var world_anchor = Vector2i(x, y) - map_origin

			var p := {"position": [world_anchor.x, world_anchor.y], "rotation": rotation}
			if action_id == "move_restaurant":
				p["restaurant_id"] = restaurant_id
			var cmd := Command.create(action_id, actor, p)
			cmd.phase = state.phase
			cmd.sub_phase = state.sub_phase

			var r: Result = executor.validate(state, cmd)
			if not r.ok:
				continue
			if anchor_set.has(world_anchor):
				continue
			anchor_set[world_anchor] = true
			anchors.append(world_anchor)

	_restaurant_valid_anchors = anchor_set
	if is_instance_valid(map_canvas) and map_canvas.has_method("set_cell_highlights"):
		map_canvas.call("set_cell_highlights", anchors)

func _on_restaurant_preview_requested(mode: String, position: Vector2i, rotation: int, restaurant_id: String) -> void:
	if game_engine == null:
		return
	var state := game_engine.get_state()
	if state == null:
		return

	var actor: int = state.get_current_player_id()
	var action_id := "place_restaurant" if mode != "move_restaurant" else "move_restaurant"

	# footprint 预览：尽量不依赖校验成功
	var piece_registry: Dictionary = game_engine.game_data.pieces if game_engine.game_data != null else {}
	if not piece_registry.has("restaurant") or not (piece_registry["restaurant"] is PieceDef):
		piece_registry["restaurant"] = PieceDefClass.create_restaurant()
	var piece_def_val = piece_registry.get("restaurant", null)
	var piece_def: PieceDef = piece_def_val if piece_def_val is PieceDef else PieceDefClass.create_restaurant()
	var footprint_cells: Array[Vector2i] = piece_def.get_world_cells(position, rotation)

	# UI 校验：用核心 PlacementValidator + 与动作一致的 ignore_cells 语义
	var ctx := {
		"cells": state.map.cells,
		"grid_size": state.map.grid_size,
		"map_origin": state.map.get("map_origin", Vector2i.ZERO),
		"houses": state.map.houses,
		"restaurants": state.map.restaurants,
	}

	var extra := {}
	if action_id == "move_restaurant" and not restaurant_id.is_empty():
		if state.map.restaurants.has(restaurant_id):
			var rest: Dictionary = state.map.restaurants[restaurant_id]
			if rest.has("cells") and (rest["cells"] is Array):
				extra["ignore_structure_cells"] = rest["cells"]

	var validate_r: Result = PlacementValidatorClass.validate_restaurant_placement(
		ctx,
		position,
		rotation,
		piece_registry,
		actor,
		state.phase == "Setup",
		extra
	)

	var valid := validate_r.ok
	var message := "" if valid else validate_r.error

	# 额外约束：与动作执行器一致的“回合/次数/数量”检查（避免只靠放置校验导致误导）
	# 这里用执行器 validate（包含员工/回合等规则），确保提示与真实执行一致
	var cmd_params := {"position": [position.x, position.y], "rotation": rotation}
	if action_id == "move_restaurant" and not restaurant_id.is_empty():
		cmd_params["restaurant_id"] = restaurant_id
	var cmd := Command.create(action_id, actor, cmd_params)
	cmd.phase = state.phase
	cmd.sub_phase = state.sub_phase
	var executor = game_engine.get_action_registry().get_executor(action_id)
	if executor != null:
		var ex_r: Result = executor.validate(state, cmd)
		if not ex_r.ok:
			valid = false
			message = ex_r.error

	if is_instance_valid(map_canvas) and map_canvas.has_method("set_structure_preview"):
		map_canvas.call("set_structure_preview", footprint_cells, valid)
	if is_instance_valid(restaurant_placement_overlay) and restaurant_placement_overlay.has_method("set_validation"):
		restaurant_placement_overlay.set_validation(valid, message)

func _on_house_placement_confirmed(position: Vector2i, rotation: int) -> void:
	if game_engine == null:
		return
	var current_player_id := game_engine.get_state().get_current_player_id()

	var result := _execute_command(Command.create("place_house", current_player_id, {
		"position": [position.x, position.y],
		"rotation": rotation
	}))
	if result.ok:
		_clear_map_selection()
		_hide_all_overlays()

func _on_garden_confirmed(house_id: String, direction: String) -> void:
	if game_engine == null:
		return
	var current_player_id := game_engine.get_state().get_current_player_id()
	if house_id.is_empty() or direction.is_empty():
		return

	var result := _execute_command(Command.create("add_garden", current_player_id, {
		"house_id": house_id,
		"direction": direction
	}))
	if result.ok:
		_clear_map_selection()
		_hide_all_overlays()

func _on_bank_break_acknowledged() -> void:
	_hide_all_phase_panels()
	_update_ui()

func _on_bank_break_game_end_triggered() -> void:
	_hide_all_phase_panels()
	_update_ui()

func _on_panel_cancelled() -> void:
	_clear_map_selection()
	hide_marketing_range_overlay()
	_hide_all_phase_panels()

func _on_overlay_cancelled() -> void:
	_clear_map_selection()
	_hide_all_overlays()

# === Dinnertime 可视化（只读）===

func _update_dinnertime_overlay(state: GameState) -> void:
	if state == null:
		_hide_dinnertime_overlay()
		return
	if state.phase != "Dinnertime":
		_hide_dinnertime_overlay()
		return
	if is_instance_valid(bank_break_panel) and bank_break_panel.visible:
		return

	_ensure_dinnertime_overlay()
	if not is_instance_valid(dinner_time_overlay):
		return
	if dinner_time_overlay.visible:
		return

	var orders := _build_dinnertime_orders(state)
	if dinner_time_overlay.has_method("set_pending_orders"):
		dinner_time_overlay.set_pending_orders(orders)
	if dinner_time_overlay.has_method("show_overlay"):
		dinner_time_overlay.show_overlay()
	else:
		dinner_time_overlay.visible = true

func _ensure_dinnertime_overlay() -> void:
	if dinner_time_overlay != null and is_instance_valid(dinner_time_overlay):
		return

	dinner_time_overlay = DinnerTimeOverlayScene.instantiate()
	if is_instance_valid(dinner_time_overlay):
		if dinner_time_overlay.has_signal("phase_completed"):
			dinner_time_overlay.phase_completed.connect(_on_dinnertime_phase_completed)
		add_child(dinner_time_overlay)

func _hide_dinnertime_overlay() -> void:
	if is_instance_valid(dinner_time_overlay):
		dinner_time_overlay.visible = false

func _on_dinnertime_phase_completed() -> void:
	_hide_dinnertime_overlay()

func _build_dinnertime_orders(state: GameState) -> Array[Dictionary]:
	var orders: Array[Dictionary] = []
	if state == null:
		return orders
	if not (state.round_state is Dictionary):
		return orders

	var dt_val = (state.round_state as Dictionary).get("dinnertime", null)
	if not (dt_val is Dictionary):
		return orders
	var dt: Dictionary = dt_val

	var raw_orders: Array[Dictionary] = []

	var sales_val = dt.get("sales", [])
	if sales_val is Array:
		for sale_val in sales_val:
			if not (sale_val is Dictionary):
				continue
			var sale: Dictionary = sale_val
			var house_id := str(sale.get("house_id", ""))
			if house_id.is_empty():
				continue
			var house_number := _coerce_int(sale.get("house_number", -1))
			var required := _normalize_count_dict(sale.get("required", {}))
			var rest_id := str(sale.get("winner_restaurant_id", ""))
			raw_orders.append({
				"house_number": house_number,
				"house_id": house_id,
				"demands": required.duplicate(true),
				"matched_restaurant": rest_id,
				"products": required.duplicate(true),
			})

	var skipped_val = dt.get("skipped", [])
	if skipped_val is Array:
		for sk_val in skipped_val:
			if not (sk_val is Dictionary):
				continue
			var sk: Dictionary = sk_val
			var house_id2 := str(sk.get("house_id", ""))
			if house_id2.is_empty():
				continue
			var house_number2 := _coerce_int(sk.get("house_number", -1))
			raw_orders.append({
				"house_number": house_number2,
				"house_id": house_id2,
				"demands": _build_house_demand_counts_from_map(state, house_id2),
				"matched_restaurant": "",
				"products": {},
			})

	raw_orders.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("house_number", -1)) < int(b.get("house_number", -1))
	)

	for o in raw_orders:
		orders.append(o)
	return orders

func _build_house_demand_counts_from_map(state: GameState, house_id: String) -> Dictionary:
	var out: Dictionary = {}
	if state == null:
		return out
	if house_id.is_empty():
		return out
	if not (state.map is Dictionary):
		return out
	var houses_val = (state.map as Dictionary).get("houses", null)
	if not (houses_val is Dictionary):
		return out
	var house_val = (houses_val as Dictionary).get(house_id, null)
	if not (house_val is Dictionary):
		return out
	var demands_val = (house_val as Dictionary).get("demands", null)
	if not (demands_val is Array):
		return out

	for d_val in demands_val:
		if not (d_val is Dictionary):
			continue
		var d: Dictionary = d_val
		var product_id := str(d.get("product", ""))
		if product_id.is_empty():
			continue
		out[product_id] = int(out.get(product_id, 0)) + 1

	return out

func _normalize_count_dict(val) -> Dictionary:
	var out: Dictionary = {}
	if not (val is Dictionary):
		return out
	var d: Dictionary = val
	for k in d.keys():
		var key := str(k)
		if key.is_empty():
			continue
		out[key] = _coerce_int(d.get(k, 0))
	return out

func _coerce_int(v) -> int:
	if v is int:
		return int(v)
	if v is float:
		var f: float = float(v)
		return int(floor(f))
	if v is String:
		var s := str(v)
		if s.is_valid_int():
			return int(s)
	return 0

func _update_demand_indicator(state: GameState) -> void:
	if state == null:
		_hide_demand_indicator()
		return
	if state.phase != "Dinnertime":
		_hide_demand_indicator()
		return
	if is_instance_valid(bank_break_panel) and bank_break_panel.visible:
		_hide_demand_indicator()
		return

	_ensure_demand_indicator()
	if not is_instance_valid(demand_indicator):
		return

	_sync_demand_indicator_transform()

	if demand_indicator.has_method("set_house_demands"):
		demand_indicator.set_house_demands(_build_dinnertime_demand_indicator_data(state))

	demand_indicator.visible = true

func _ensure_demand_indicator() -> void:
	if demand_indicator == null or not is_instance_valid(demand_indicator):
		demand_indicator = DemandIndicatorScene.instantiate()

	var parent: Node = map_canvas if is_instance_valid(map_canvas) else self
	if is_instance_valid(demand_indicator) and demand_indicator.get_parent() != parent:
		var old_parent := demand_indicator.get_parent()
		if old_parent != null:
			old_parent.remove_child(demand_indicator)
		parent.add_child(demand_indicator)

func _sync_demand_indicator_transform() -> void:
	if not is_instance_valid(demand_indicator):
		return
	if not is_instance_valid(map_canvas):
		return

	var cell_size := 40
	if map_canvas.has_method("get_cell_size"):
		cell_size = int(map_canvas.call("get_cell_size"))

	var world_origin := Vector2i.ZERO
	if map_canvas.has_method("get_world_origin"):
		var wo = map_canvas.call("get_world_origin")
		if wo is Vector2i:
			world_origin = wo

	if demand_indicator.has_method("set_tile_size"):
		demand_indicator.call("set_tile_size", Vector2(float(cell_size), float(cell_size)))
	if demand_indicator.has_method("set_map_offset"):
		demand_indicator.call("set_map_offset", Vector2(float(-world_origin.x * cell_size), float(-world_origin.y * cell_size)))

func _hide_demand_indicator() -> void:
	if is_instance_valid(demand_indicator):
		if demand_indicator.has_method("clear_all"):
			demand_indicator.clear_all()
		demand_indicator.visible = false

func _build_dinnertime_demand_indicator_data(state: GameState) -> Dictionary:
	var out: Dictionary = {}
	if state == null:
		return out
	if not (state.round_state is Dictionary):
		return out
	var dt_val = (state.round_state as Dictionary).get("dinnertime", null)
	if not (dt_val is Dictionary):
		return out
	var dt: Dictionary = dt_val

	var sales_val = dt.get("sales", [])
	if sales_val is Array:
		for sale_val in sales_val:
			if not (sale_val is Dictionary):
				continue
			var sale: Dictionary = sale_val
			var house_id := str(sale.get("house_id", ""))
			if house_id.is_empty():
				continue
			var pos := _get_house_anchor_world_pos(state, house_id)
			if pos == Vector2i(-1, -1):
				continue
			var required := _normalize_count_dict(sale.get("required", {}))
			if required.is_empty():
				continue
			out[house_id] = {
				"demands": required,
				"position": pos,
				"satisfied": true,
			}

	return out

func _get_house_anchor_world_pos(state: GameState, house_id: String) -> Vector2i:
	if state == null:
		return Vector2i(-1, -1)
	if house_id.is_empty():
		return Vector2i(-1, -1)
	if not (state.map is Dictionary):
		return Vector2i(-1, -1)
	var houses_val = (state.map as Dictionary).get("houses", null)
	if not (houses_val is Dictionary):
		return Vector2i(-1, -1)
	var house_val = (houses_val as Dictionary).get(house_id, null)
	if not (house_val is Dictionary):
		return Vector2i(-1, -1)
	var anchor_val = (house_val as Dictionary).get("anchor_pos", null)
	if anchor_val is Vector2i:
		return anchor_val
	var cells_val = (house_val as Dictionary).get("cells", null)
	if cells_val is Array and not (cells_val as Array).is_empty():
		var first = (cells_val as Array)[0]
		if first is Vector2i:
			return first
	return Vector2i(-1, -1)

# === P2 覆盖层管理 ===

func show_distance_overlay(from_position: Vector2i, to_positions: Array[Vector2i]) -> void:
	if distance_overlay == null:
		distance_overlay = DistanceOverlayScene.instantiate()
		add_child(distance_overlay)

	if distance_overlay.has_method("set_map_data"):
		var state := game_engine.get_state()
		distance_overlay.set_map_data(state.map)

	if distance_overlay.has_method("show_distances"):
		distance_overlay.show_distances(from_position, to_positions)

	distance_overlay.visible = true

func hide_distance_overlay() -> void:
	if is_instance_valid(distance_overlay):
		distance_overlay.visible = false

func show_marketing_range_overlay(campaigns: Array[Dictionary]) -> void:
	_ensure_marketing_range_overlay()
	if not is_instance_valid(marketing_range_overlay):
		return

	if marketing_range_overlay.has_method("set_campaigns"):
		marketing_range_overlay.set_campaigns(campaigns)

	marketing_range_overlay.visible = true

func hide_marketing_range_overlay() -> void:
	if is_instance_valid(marketing_range_overlay):
		marketing_range_overlay.visible = false
		if marketing_range_overlay.has_method("clear_all"):
			marketing_range_overlay.clear_all()

func preview_marketing_range(position: Vector2i, range_val: int, marketing_type: String) -> void:
	if marketing_type.is_empty():
		hide_marketing_range_overlay()
		return

	_ensure_marketing_range_overlay()
	if not is_instance_valid(marketing_range_overlay):
		return

	if marketing_range_overlay.has_method("show_preview"):
		marketing_range_overlay.show_preview(position, range_val, marketing_type)

	marketing_range_overlay.visible = true

func _ensure_marketing_range_overlay() -> void:
	if marketing_range_overlay == null or not is_instance_valid(marketing_range_overlay):
		marketing_range_overlay = MarketingRangeOverlayScene.instantiate()

	var parent: Node = map_canvas if is_instance_valid(map_canvas) else self
	if is_instance_valid(marketing_range_overlay) and marketing_range_overlay.get_parent() != parent:
		var old_parent := marketing_range_overlay.get_parent()
		if old_parent != null:
			old_parent.remove_child(marketing_range_overlay)
		parent.add_child(marketing_range_overlay)

	_sync_marketing_range_overlay_transform()

func _sync_marketing_range_overlay_transform() -> void:
	if not is_instance_valid(marketing_range_overlay):
		return
	if not is_instance_valid(map_canvas):
		return

	var cell_size := 40
	if map_canvas.has_method("get_cell_size"):
		cell_size = int(map_canvas.call("get_cell_size"))

	var world_origin := Vector2i.ZERO
	if map_canvas.has_method("get_world_origin"):
		var wo = map_canvas.call("get_world_origin")
		if wo is Vector2i:
			world_origin = wo

	if marketing_range_overlay.has_method("set_tile_size"):
		marketing_range_overlay.call("set_tile_size", Vector2(float(cell_size), float(cell_size)))
	if marketing_range_overlay.has_method("set_map_offset"):
		marketing_range_overlay.call("set_map_offset", Vector2(float(-world_origin.x * cell_size), float(-world_origin.y * cell_size)))

# === P2 工具方法 ===

func toggle_game_log() -> void:
	if is_instance_valid(game_log_panel):
		game_log_panel.visible = not game_log_panel.visible

func show_settings_dialog() -> void:
	if settings_dialog == null:
		settings_dialog = SettingsDialogScene.instantiate()
		add_child(settings_dialog)

	if settings_dialog.has_method("show_dialog"):
		settings_dialog.show_dialog()
	else:
		settings_dialog.show()

func get_ui_animation_manager() -> Node:
	return ui_animation_manager

# === 辅助方法 ===

func _hide_all_overlays() -> void:
	if is_instance_valid(restaurant_placement_overlay):
		restaurant_placement_overlay.visible = false
	if is_instance_valid(house_placement_overlay):
		house_placement_overlay.visible = false
	if is_instance_valid(distance_overlay):
		distance_overlay.visible = false
	if is_instance_valid(marketing_range_overlay):
		marketing_range_overlay.visible = false
	if is_instance_valid(demand_indicator):
		demand_indicator.visible = false
	if is_instance_valid(map_canvas) and map_canvas.has_method("clear_structure_preview"):
		map_canvas.call("clear_structure_preview")
	if is_instance_valid(map_canvas) and map_canvas.has_method("clear_cell_highlights"):
		map_canvas.call("clear_cell_highlights")
	_restaurant_valid_anchors.clear()

# === 缩放控制 ===

func _on_zoom_in_pressed() -> void:
	if is_instance_valid(map_view) and map_view.has_method("zoom_in"):
		map_view.zoom_in()

func _on_zoom_out_pressed() -> void:
	if is_instance_valid(map_view) and map_view.has_method("zoom_out"):
		map_view.zoom_out()

func _on_zoom_reset_pressed() -> void:
	if is_instance_valid(map_view) and map_view.has_method("reset_zoom"):
		map_view.reset_zoom()

func _on_zoom_fit_pressed() -> void:
	if is_instance_valid(map_view) and map_view.has_method("fit_to_view"):
		map_view.fit_to_view()

func _on_map_zoom_changed(zoom_level: float) -> void:
	if is_instance_valid(zoom_control) and zoom_control.has_method("set_zoom_level"):
		zoom_control.set_zoom_level(zoom_level)
