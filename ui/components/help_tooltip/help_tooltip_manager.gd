# 帮助提示管理器
# 全局悬停帮助提示系统
class_name HelpTooltipManager
extends CanvasLayer

signal tooltip_shown(key: String)
signal tooltip_hidden()

@onready var tooltip_panel: PanelContainer = $TooltipPanel
@onready var title_label: Label = $TooltipPanel/MarginContainer/VBoxContainer/TitleLabel
@onready var content_label: RichTextLabel = $TooltipPanel/MarginContainer/VBoxContainer/ContentLabel

# 帮助文本数据库
var HELP_DATABASE: Dictionary = {
	# 阶段说明
	"phase_setup": {
		"title": "设置阶段",
		"content": "开局放置初始餐厅。通常需要每位玩家放置 1 个餐厅后才能进入下一阶段。"
	},
	"phase_restructuring": {
		"title": "重组阶段",
		"content": "在此阶段，你可以调整公司结构。将员工放入卡槽中，CEO下方最多可放置的卡槽数取决于管理能力。"
	},
	"phase_order_of_business": {
		"title": "决定顺序",
		"content": "根据公司结构中的空余卡槽数量决定选择顺序。空余卡槽多的玩家先选择。选择后点击顺序轨上的位置确定本回合行动顺序。"
	},
	"phase_working": {
		"title": "工作时间",
		"content": "按照选定的顺序，玩家依次执行各项工作：招聘、培训、营销、生产食物、采购饮料、放置房屋、放置餐厅。"
	},
	"phase_dinner_time": {
		"title": "晚餐时间",
		"content": "顾客根据需求和距离选择餐厅。餐厅必须满足顾客的全部需求才能获得收入。距离越近的餐厅优先级越高。"
	},
	"phase_payday": {
		"title": "发薪日",
		"content": "支付员工薪水（每人$5）。可以在支付前解雇员工。如果现金不足，必须解雇员工直到能够支付。"
	},
	"phase_marketing": {
		"title": "营销结算",
		"content": "按营销板件编号顺序结算营销活动：在影响范围内的房屋生成需求，并减少活动持续时间；到期后回收营销员并移除放置。"
	},
	"phase_cleanup": {
		"title": "清理阶段",
		"content": "回合收尾阶段：清理库存、处理阶段性标记并准备进入下一回合。"
	},
	"phase_game_over": {
		"title": "游戏结束",
		"content": "游戏已结束。你可以查看结果并返回主菜单或重新开始。"
	},

	# 员工类型
	"employee_recruiter": {
		"title": "招聘员",
		"content": "可以招聘新员工。招聘次数等于所有在岗招聘员的招聘能力之和。"
	},
	"employee_trainer": {
		"title": "培训员",
		"content": "可以培训待命区的员工。培训时将原员工卡放回供应区，获得目标职位的新卡。"
	},
	"employee_marketer": {
		"title": "营销员",
		"content": "可以发起营销活动。不同类型的营销员有不同的影响范围和持续时间。"
	},
	"employee_kitchen": {
		"title": "厨房员工",
		"content": "可以生产食物。生产数量取决于员工的生产能力。"
	},
	"employee_buyer": {
		"title": "采购员",
		"content": "可以采购饮料。采购数量取决于员工的采购能力。"
	},

	# 游戏机制
	"mechanic_turn_order": {
		"title": "回合顺序",
		"content": "回合顺序决定了工作阶段的行动顺序。选择靠后的位置可能错过某些机会，但在晚餐时间处理顾客时会有优势。"
	},
	"mechanic_marketing": {
		"title": "营销机制",
		"content": "营销活动会在范围内的房屋产生需求。需求类型取决于营销类型。营销活动会持续直到营销员回到待命区。"
	},
	"mechanic_distance": {
		"title": "距离计算",
		"content": "距离以道路格数计算。顾客会选择能满足需求的最近餐厅。如果距离相同，则按照回合顺序决定。"
	},
	"mechanic_bank": {
		"title": "银行破产",
		"content": "当银行资金耗尽时触发破产。首次破产后银行获得额外资金。第二次破产后游戏在本回合结束时结束。"
	},

	# UI元素
	"ui_employee_card": {
		"title": "员工卡",
		"content": "显示员工的职位、能力和薪水。点击可选中，拖拽可调整位置。"
	},
	"ui_inventory": {
		"title": "库存面板",
		"content": "显示当前持有的产品数量。冰箱容量限制可存储的产品总数。"
	},
	"ui_action_panel": {
		"title": "动作面板",
		"content": "显示当前可执行的动作。灰色按钮表示该动作当前不可用。"
	},
}

var _current_key: String = ""
var _show_delay: float = 0.5
var _hide_delay: float = 0.1
var _show_timer: Timer = null
var _is_visible: bool = false

func _ready() -> void:
	# 创建延迟定时器
	_show_timer = Timer.new()
	_show_timer.one_shot = true
	_show_timer.timeout.connect(_on_show_timer_timeout)
	add_child(_show_timer)

	if tooltip_panel != null:
		tooltip_panel.visible = false

func request_tooltip(key: String, position: Vector2) -> void:
	if key == _current_key and _is_visible:
		_update_position(position)
		return

	_current_key = key
	_show_timer.stop()
	_show_timer.start(_show_delay)

	# 预设位置
	_update_position(position)

func hide_tooltip() -> void:
	_current_key = ""
	_show_timer.stop()

	if tooltip_panel != null:
		tooltip_panel.visible = false

	_is_visible = false
	tooltip_hidden.emit()

func show_immediate(key: String, position: Vector2) -> void:
	_current_key = key
	_show_timer.stop()
	_show_tooltip(key, position)

func _on_show_timer_timeout() -> void:
	if _current_key.is_empty():
		return

	var mouse_pos := get_viewport().get_mouse_position()
	_show_tooltip(_current_key, mouse_pos)

func _show_tooltip(key: String, position: Vector2) -> void:
	if not HELP_DATABASE.has(key):
		return

	var data: Dictionary = HELP_DATABASE[key]

	if title_label != null:
		title_label.text = str(data.get("title", ""))

	if content_label != null:
		content_label.text = str(data.get("content", ""))

	_update_position(position)

	if tooltip_panel != null:
		tooltip_panel.visible = true

	_is_visible = true
	tooltip_shown.emit(key)

func _update_position(position: Vector2) -> void:
	if tooltip_panel == null:
		return

	var viewport_size := get_viewport().get_visible_rect().size
	var panel_size := tooltip_panel.size

	# 默认显示在鼠标右下方
	var target_pos := position + Vector2(15, 15)

	# 边界检测
	if target_pos.x + panel_size.x > viewport_size.x:
		target_pos.x = position.x - panel_size.x - 10
	if target_pos.y + panel_size.y > viewport_size.y:
		target_pos.y = position.y - panel_size.y - 10

	# 确保不超出左上边界
	target_pos.x = maxf(5, target_pos.x)
	target_pos.y = maxf(5, target_pos.y)

	tooltip_panel.position = target_pos

func register_control(control: Control, help_key: String) -> void:
	control.mouse_entered.connect(_on_control_mouse_entered.bind(control, help_key))
	control.mouse_exited.connect(_on_control_mouse_exited)

func _on_control_mouse_entered(control: Control, help_key: String) -> void:
	var global_pos := control.get_global_rect().position + control.size / 2
	request_tooltip(help_key, global_pos)

func _on_control_mouse_exited() -> void:
	hide_tooltip()

# 添加自定义帮助条目
func add_help_entry(key: String, title: String, content: String) -> void:
	HELP_DATABASE[key] = {
		"title": title,
		"content": content,
	}
