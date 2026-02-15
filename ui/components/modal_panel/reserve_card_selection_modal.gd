# 银行储备卡选择遮罩面板（Setup/ReserveCards）
# - 强制弹窗：不可取消；确认后执行 select_reserve_card 命令
class_name ReserveCardSelectionModal
extends "res://ui/components/modal_panel/modal_panel_base.gd"

const ReserveUiStylesClass = preload("res://ui/utils/ui_styles.gd")
const FIXED_PANEL_HEIGHT := 440.0
const MIN_PANEL_WIDTH := 720.0

@onready var selection_label: Label = $Panel/MarginContainer/VBoxContainer/ContentHost/VBoxContainer/SelectionLabel
@onready var card_button_0: Button = $Panel/MarginContainer/VBoxContainer/ContentHost/VBoxContainer/CardsRow/CardButton0
@onready var card_button_1: Button = $Panel/MarginContainer/VBoxContainer/ContentHost/VBoxContainer/CardsRow/CardButton1
@onready var card_button_2: Button = $Panel/MarginContainer/VBoxContainer/ContentHost/VBoxContainer/CardsRow/CardButton2

@onready var card_title_0: Label = $Panel/MarginContainer/VBoxContainer/ContentHost/VBoxContainer/CardsRow/CardButton0/Content/VBoxContainer/CardTitle
@onready var card_title_1: Label = $Panel/MarginContainer/VBoxContainer/ContentHost/VBoxContainer/CardsRow/CardButton1/Content/VBoxContainer/CardTitle
@onready var card_title_2: Label = $Panel/MarginContainer/VBoxContainer/ContentHost/VBoxContainer/CardsRow/CardButton2/Content/VBoxContainer/CardTitle

@onready var card_desc_0: Label = $Panel/MarginContainer/VBoxContainer/ContentHost/VBoxContainer/CardsRow/CardButton0/Content/VBoxContainer/CardDesc
@onready var card_desc_1: Label = $Panel/MarginContainer/VBoxContainer/ContentHost/VBoxContainer/CardsRow/CardButton1/Content/VBoxContainer/CardDesc
@onready var card_desc_2: Label = $Panel/MarginContainer/VBoxContainer/ContentHost/VBoxContainer/CardsRow/CardButton2/Content/VBoxContainer/CardDesc

var _selected_index: int = -1
var _card_summaries: Array[String] = []
var _card_button_group: ButtonGroup = ButtonGroup.new()

func _ready() -> void:
	allow_cancel = false
	allow_peek_map = false
	super._ready()
	set_process(false)
	_apply_visual_styles()

	set_title_text("选择银行储备卡")
	set_confirm_text("确认选择")
	set_cancel_text("")
	set_confirm_enabled(false)

	if is_instance_valid(hint_label):
		hint_label.text = "请确保其他玩家未看到你的选择；确认后不可更改。"

	# 并列卡片选择：三张卡只能选其一
	_bind_card_button(card_button_0, 0)
	_bind_card_button(card_button_1, 1)
	_bind_card_button(card_button_2, 2)

func _apply_visual_styles() -> void:
	if is_instance_valid(title_label):
		ReserveUiStylesClass.apply_label_dark(title_label)
	if is_instance_valid(selection_label):
		ReserveUiStylesClass.apply_label_dark(selection_label)
	if is_instance_valid(hint_label):
		ReserveUiStylesClass.apply_label_error(hint_label)

	for btn in [card_button_0, card_button_1, card_button_2]:
		if btn is Button and is_instance_valid(btn):
			ReserveUiStylesClass.apply_button_secondary(btn)

	for label in [card_title_0, card_title_1, card_title_2]:
		if label is Label and is_instance_valid(label):
			ReserveUiStylesClass.apply_label_dark(label)

	for label in [card_desc_0, card_desc_1, card_desc_2]:
		if label is Label and is_instance_valid(label):
			ReserveUiStylesClass.apply_label_hint_dark(label)

func open(_covered_rect: Rect2) -> void:
	# 储备卡选择为强制弹窗，直接使用 viewport 区域，避免局部覆盖区坐标导致面板越界。
	var viewport_rect := get_viewport_rect()
	super.open(Rect2(Vector2.ZERO, viewport_rect.size))
	set_process(true)

func close() -> void:
	set_process(false)
	super.close()

func _process(_delta: float) -> void:
	if not visible:
		return
	_center_panel()

func _center_panel() -> void:
	var p := panel
	if not is_instance_valid(p):
		return

	var viewport_size := get_viewport_rect().size
	var viewport_max_w := maxf(0.0, viewport_size.x - 24.0)
	var viewport_max_h := maxf(0.0, viewport_size.y - 24.0)

	var panel_width := p.size.x
	if panel_width <= 0.0:
		panel_width = p.get_combined_minimum_size().x
	if panel_width <= 0.0:
		panel_width = p.custom_minimum_size.x
	panel_width = maxf(panel_width, MIN_PANEL_WIDTH)

	var panel_height := FIXED_PANEL_HEIGHT
	var max_w := maxf(0.0, size.x - 24.0)
	var max_h := maxf(0.0, size.y - 24.0)
	if max_w > 0.0:
		panel_width = min(panel_width, max_w)
	if max_h > 0.0:
		panel_height = min(panel_height, max_h)
	# 绝对不允许超出 viewport 可视高度。
	if viewport_max_w > 0.0:
		panel_width = min(panel_width, viewport_max_w)
	if viewport_max_h > 0.0:
		panel_height = min(panel_height, viewport_max_h)

	p.custom_minimum_size = Vector2(panel_width, panel_height)
	p.size = Vector2(panel_width, panel_height)

	var x := (size.x - panel_width) / 2.0
	var y := (size.y - panel_height) / 2.0
	x = clampf(x, 12.0, maxf(12.0, size.x - panel_width - 12.0))
	y = clampf(y, 12.0, maxf(12.0, size.y - panel_height - 12.0))

	# 二次夹紧到 viewport，避免覆盖区域偏移时面板溢出到屏幕外。
	var global_x := position.x + x
	var global_y := position.y + y
	var max_global_x := maxf(12.0, viewport_size.x - panel_width - 12.0)
	var max_global_y := maxf(12.0, viewport_size.y - panel_height - 12.0)
	global_x = clampf(global_x, 12.0, max_global_x)
	global_y = clampf(global_y, 12.0, max_global_y)
	x = global_x - position.x
	y = global_y - position.y

	p.position = Vector2(x, y)

func setup(state: GameState, current_player_id: int) -> void:
	allow_peek_map = false
	_selected_index = -1
	_card_summaries.clear()
	set_confirm_text("确认选择")
	set_confirm_enabled(false)

	if is_instance_valid(hint_label):
		hint_label.text = "请确保其他玩家未看到你的选择；确认后不可更改。"

	var name := Globals.get_player_name(current_player_id) if Globals != null else ("玩家%d" % (current_player_id + 1))
	set_title_text("选择银行储备卡｜当前: %s" % name)
	if is_instance_valid(selection_label):
		selection_label.text = "当前玩家：%s，请选择一张储备卡（其他玩家不应看到）" % name

	_reset_card_buttons()

	if state == null or current_player_id < 0 or current_player_id >= state.players.size():
		return
	var p_val = state.players[current_player_id]
	if not (p_val is Dictionary):
		return
	var player: Dictionary = p_val
	var cards_val = player.get("reserve_cards", null)
	if not (cards_val is Array):
		return
	var cards: Array = cards_val

	var has_any_bank_fields := false
	var has_any_price_only := false
	for c_val in cards:
		if not (c_val is Dictionary):
			continue
		var c: Dictionary = c_val
		var has_bank_fields := (
			c.has("cash") and (c.get("cash", null) is int)
			and c.has("ceo_slots") and (c.get("ceo_slots", null) is int)
		)
		if has_bank_fields:
			has_any_bank_fields = true
		else:
			has_any_price_only = true

	if is_instance_valid(hint_label):
		if has_any_price_only and not has_any_bank_fields:
			hint_label.text = (
				"请确保其他玩家未看到你的选择；确认后不可更改。\n"
				+ "提示：本局储备卡不再影响起始现金/CEO 卡槽；银行首次破产后按多数类型决定基础单价（平局 20 > 5 > 10）。"
			)
		elif has_any_price_only and has_any_bank_fields:
			hint_label.text = (
				"请确保其他玩家未看到你的选择；确认后不可更改。\n"
				+ "提示：储备卡字段不一致，将按卡片字段分别展示。"
			)

	_apply_card(0, cards)
	_apply_card(1, cards)
	_apply_card(2, cards)

func setup_waiting(current_player_id: int) -> void:
	# 联机：等待其他玩家选择（不展示任何卡片信息）
	allow_peek_map = true
	_selected_index = -1
	_card_summaries.clear()
	set_confirm_text("等待中")
	set_confirm_enabled(false)

	if is_instance_valid(hint_label):
		hint_label.text = "该选择对其他玩家保密。请等待对方完成。（Space 可暂时查看地图）"

	var name := Globals.get_player_name(current_player_id) if Globals != null else ("玩家%d" % (current_player_id + 1))
	set_title_text("选择银行储备卡｜等待: %s" % name)
	if is_instance_valid(selection_label):
		selection_label.text = "等待玩家：%s 选择储备卡..." % name

	_reset_card_buttons()
	for i in range(3):
		var btn: Button = _get_card_button(i)
		var title_label: Label = _get_card_title_label(i)
		var desc_label: Label = _get_card_desc_label(i)
		if is_instance_valid(btn):
			btn.disabled = true
			btn.visible = true
			btn.button_pressed = false
		if is_instance_valid(title_label):
			title_label.text = "保密中"
		if is_instance_valid(desc_label):
			desc_label.text = ""

func _on_confirm_pressed() -> void:
	if _selected_index < 0:
		return
	completed.emit({"selected_index": _selected_index})

func _on_cancel_pressed() -> void:
	# 强制弹窗：不允许取消
	return

func _bind_card_button(btn: Button, index: int) -> void:
	if not is_instance_valid(btn):
		return

	btn.toggle_mode = true
	btn.button_group = _card_button_group
	btn.disabled = true

	if not btn.pressed.is_connected(_on_card_pressed.bind(index)):
		btn.pressed.connect(_on_card_pressed.bind(index))

func _reset_card_buttons() -> void:
	_reset_card_button(card_button_0, card_title_0, card_desc_0)
	_reset_card_button(card_button_1, card_title_1, card_desc_1)
	_reset_card_button(card_button_2, card_title_2, card_desc_2)

func _reset_card_button(btn: Button, title_label: Label, desc_label: Label) -> void:
	if is_instance_valid(btn):
		btn.disabled = true
		btn.visible = true
		btn.button_pressed = false
	if is_instance_valid(title_label):
		title_label.text = "储备卡"
	if is_instance_valid(desc_label):
		desc_label.text = ""

func _apply_card(index: int, cards: Array) -> void:
	var btn: Button = _get_card_button(index)
	var title_label: Label = _get_card_title_label(index)
	var desc_label: Label = _get_card_desc_label(index)

	if not is_instance_valid(btn) or not is_instance_valid(title_label) or not is_instance_valid(desc_label):
		return

	if index < 0 or index >= cards.size():
		btn.visible = false
		return

	var c_val = cards[index]
	if not (c_val is Dictionary):
		btn.visible = false
		return
	var c: Dictionary = c_val

	var t: int = int(c.get("type", 0))
	var has_bank_fields := (
		c.has("cash") and (c.get("cash", null) is int)
		and c.has("ceo_slots") and (c.get("ceo_slots", null) is int)
	)

	if not has_bank_fields:
		title_label.text = "储备卡 %d（价格 $%d）" % [index + 1, t]
		desc_label.text = "基础单价候选：$%d\n首次破产后按多数决定（平局 20 > 5 > 10）" % t

		var summary := "储备卡 %d：基础单价候选 $%d" % [index + 1, t]
		while _card_summaries.size() <= index:
			_card_summaries.append("")
		_card_summaries[index] = summary
	else:
		var cash: int = int(c.get("cash", 0))
		var slots: int = int(c.get("ceo_slots", 0))

		title_label.text = "储备卡 %d（类型 %d）" % [index + 1, t]
		desc_label.text = "起始现金：+$%d\nCEO 卡槽：%d" % [cash, slots]

		var summary := "储备卡 %d：类型 %d，+$%d，CEO 卡槽=%d" % [index + 1, t, cash, slots]
		while _card_summaries.size() <= index:
			_card_summaries.append("")
		_card_summaries[index] = summary

	btn.disabled = false

func _on_card_pressed(index: int) -> void:
	_selected_index = int(index)
	set_confirm_enabled(true)

	if not is_instance_valid(selection_label):
		return

	selection_label.text = "已选择储备卡 %d。（确认后不可更改）" % (index + 1)

func _get_card_button(index: int) -> Button:
	match index:
		0: return card_button_0
		1: return card_button_1
		2: return card_button_2
		_: return null

func _get_card_title_label(index: int) -> Label:
	match index:
		0: return card_title_0
		1: return card_title_1
		2: return card_title_2
		_: return null

func _get_card_desc_label(index: int) -> Label:
	match index:
		0: return card_desc_0
		1: return card_desc_1
		2: return card_desc_2
		_: return null
