# 动作面板组件
# 显示当前阶段可用的动作，支持触发执行
class_name ActionPanel
extends Control

signal action_requested(action_id: String, params: Dictionary)

@onready var items_container: VBoxContainer = $MarginContainer/VBoxContainer/ItemsContainer

var _action_registry = null  # ActionRegistry
var _game_state: GameState = null
var _current_player_id: int = -1
var _action_buttons: Dictionary = {}  # action_id -> ActionButton

# 不在 UI 中展示的内部动作
const HIDDEN_ACTION_IDS := {
	"end_turn": true,
	"advance_phase": true,
}

# 动作显示名称映射
const ACTION_DISPLAY_NAMES: Dictionary = {
	"advance_phase": "推进阶段",
	"skip": "确认结束",
	"skip_sub_phase": "跳过子阶段",
	"choose_turn_order": "选择顺序",
	"recruit": "招聘",
	"train": "培训",
	"initiate_marketing": "发起营销",
	"produce_food": "生产食物",
	"procure_drinks": "采购饮料",
	"place_house": "放置房屋",
	"add_garden": "添加花园",
	"place_restaurant": "放置餐厅",
	"move_restaurant": "移动餐厅",
	"set_price": "设定价格",
	"set_luxury_price": "设定奢侈品价格",
	"set_discount": "设定折扣",
	"fire": "解雇员工",
}

# 动作说明映射
const ACTION_DESCRIPTIONS: Dictionary = {
	"advance_phase": "强制推进到下一阶段",
	"skip": "确认结束本阶段/子阶段",
	"skip_sub_phase": "跳过当前子阶段（Working）",
	"choose_turn_order": "在顺序轨上选择位置",
	"recruit": "招聘一名入门级员工",
	"train": "培训待命区的员工",
	"initiate_marketing": "发起营销活动",
	"produce_food": "使用厨房员工生产食物",
	"procure_drinks": "使用采购员获取饮料",
	"place_house": "放置新房屋",
	"add_garden": "为房屋添加花园",
	"place_restaurant": "放置新餐厅",
	"move_restaurant": "移动已有餐厅",
	"set_price": "设定产品价格",
	"set_luxury_price": "设定奢侈品价格",
	"set_discount": "设定折扣",
	"fire": "解雇员工",
}

func _ready() -> void:
	_build_ui()

func _build_ui() -> void:
	if items_container != null:
		items_container.add_theme_constant_override("separation", 4)

func set_action_registry(registry) -> void:
	_action_registry = registry
	refresh()

func set_game_state(state: GameState) -> void:
	_game_state = state
	refresh()

func set_current_player(player_id: int) -> void:
	_current_player_id = player_id
	refresh()

func set_available_actions(action_ids: Array[String]) -> void:
	_rebuild_action_buttons(action_ids)

func set_action_enabled(action_id: String, enabled: bool) -> void:
	if _action_buttons.has(action_id):
		var btn: ActionButton = _action_buttons[action_id]
		if is_instance_valid(btn):
			btn.set_enabled(enabled)

func refresh() -> void:
	if _game_state == null:
		_rebuild_action_buttons([])
		return

	var available_ids: Array[String] = []
	var executable_ids: Array[String] = []

	# 通过 ActionRegistry 获取可用动作
	if _action_registry != null and _action_registry.has_method("get_available_actions"):
		available_ids = _action_registry.get_available_actions(_game_state)
		if _current_player_id >= 0:
			# UI 侧需要“可启动”判定：允许先点击进入面板/选点，再补齐参数执行
			if _action_registry.has_method("get_player_initiatable_actions"):
				executable_ids = _action_registry.get_player_initiatable_actions(_game_state, _current_player_id)
			elif _action_registry.has_method("get_player_available_actions"):
				executable_ids = _action_registry.get_player_available_actions(_game_state, _current_player_id)
	else:
		# 备用：根据阶段硬编码部分常用动作
		available_ids = _get_fallback_actions(_game_state.phase, _game_state.sub_phase)

	# 隐藏内部动作
	var visible_ids: Array[String] = []
	for aid in available_ids:
		if HIDDEN_ACTION_IDS.has(aid):
			continue
		visible_ids.append(aid)

	var visible_executable: Array[String] = []
	for aid2 in executable_ids:
		if HIDDEN_ACTION_IDS.has(aid2):
			continue
		visible_executable.append(aid2)

	# Working：仅当当前子阶段存在可做动作时，才显示“跳过子阶段”
	if _game_state.phase == "Working" and visible_ids.has("skip_sub_phase"):
		var has_real_actions := false
		for aidx in visible_executable:
			if aidx == "skip" or aidx == "skip_sub_phase":
				continue
			has_real_actions = true
			break
		if not has_real_actions:
			var filtered: Array[String] = []
			for aid4 in visible_ids:
				if aid4 == "skip_sub_phase":
					continue
				filtered.append(aid4)
			visible_ids = filtered

	_rebuild_action_buttons(visible_ids)

	# 若能计算“当前玩家可执行动作”，则对不可执行动作做灰显
	if not visible_executable.is_empty():
		for aid3 in visible_ids:
			var enabled := visible_executable.has(aid3)
			# 保留调试用强制推进按钮
			if aid3 == "advance_phase":
				enabled = true
			set_action_enabled(aid3, enabled)

func _get_fallback_actions(phase: String, sub_phase: String) -> Array[String]:
	var result: Array[String] = ["skip"]

	match phase:
		"Setup":
			result.append("place_restaurant")
		"OrderOfBusiness":
			result.append("choose_turn_order")
		"Working":
			match sub_phase:
				"Recruit":
					result.append("recruit")
				"Train":
					result.append("train")
				"Marketing":
					result.append("initiate_marketing")
				"GetFood":
					result.append("produce_food")
				"GetDrinks":
					result.append("procure_drinks")
				"PlaceHouses":
					result.append("place_house")
					result.append("add_garden")
				"PlaceRestaurants":
					result.append("place_restaurant")
					result.append("move_restaurant")
		"Payday":
			result.append("fire")

	return result

func _rebuild_action_buttons(action_ids: Array[String]) -> void:
	# 清除旧按钮
	for btn in _action_buttons.values():
		if is_instance_valid(btn):
			btn.queue_free()
	_action_buttons.clear()

	if items_container == null:
		return

	# 创建新按钮
	for action_id in action_ids:
		var btn := ActionButton.new()
		btn.action_id = action_id
		btn.display_name = ACTION_DISPLAY_NAMES.get(action_id, action_id)
		btn.description = ACTION_DESCRIPTIONS.get(action_id, "")
		btn.action_clicked.connect(_on_action_clicked)
		items_container.add_child(btn)
		_action_buttons[action_id] = btn

func _on_action_clicked(action_id: String) -> void:
	action_requested.emit(action_id, {})


# === 内部类：动作按钮 ===
class ActionButton extends Button:
	signal action_clicked(action_id: String)

	var action_id: String = ""
	var display_name: String = ""
	var description: String = ""

	func _ready() -> void:
		_build_ui()
		pressed.connect(_on_pressed)
		mouse_entered.connect(_on_mouse_entered)
		mouse_exited.connect(_on_mouse_exited)

	func _build_ui() -> void:
		custom_minimum_size = Vector2(180, 36)
		text = display_name if not display_name.is_empty() else action_id
		add_theme_font_size_override("font_size", 14)

	func set_enabled(enabled: bool) -> void:
		disabled = not enabled
		modulate = Color(1, 1, 1, 1) if enabled else Color(0.5, 0.5, 0.5, 0.7)

	func _on_pressed() -> void:
		action_clicked.emit(action_id)

	func _on_mouse_entered() -> void:
		if not description.is_empty():
			tooltip_text = description

	func _on_mouse_exited() -> void:
		tooltip_text = ""
