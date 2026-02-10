# 银行储备卡选择遮罩面板（Setup/ReserveCards）
# - 强制弹窗：不可取消；确认后执行 select_reserve_card 命令
class_name ReserveCardSelectionModal
extends "res://ui/components/modal_panel/modal_panel_base.gd"

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
	allow_peek_map = false
	super._ready()

	set_title_text("选择银行储备卡")
	set_confirm_text("确认选择")
	set_cancel_text("")
	set_confirm_enabled(false)

	# 强制选择：隐藏取消按钮，并忽略 ESC
	if is_instance_valid(cancel_button):
		cancel_button.visible = false

	if is_instance_valid(hint_label):
		hint_label.text = "请确保其他玩家未看到你的选择；确认后不可更改。"

	# 并列卡片选择：三张卡只能选其一
	_bind_card_button(card_button_0, 0)
	_bind_card_button(card_button_1, 1)
	_bind_card_button(card_button_2, 2)

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
		desc_label.text = "图片占位\n基础单价候选：$%d\n首次破产后按多数决定（平局 20 > 5 > 10）" % t

		var summary := "储备卡 %d：基础单价候选 $%d" % [index + 1, t]
		while _card_summaries.size() <= index:
			_card_summaries.append("")
		_card_summaries[index] = summary
	else:
		var cash: int = int(c.get("cash", 0))
		var slots: int = int(c.get("ceo_slots", 0))

		title_label.text = "储备卡 %d（类型 %d）" % [index + 1, t]
		desc_label.text = "图片占位\n起始现金：+$%d\nCEO 卡槽：%d" % [cash, slots]

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

	var summary := ""
	if index >= 0 and index < _card_summaries.size():
		summary = _card_summaries[index]
	if summary.is_empty():
		selection_label.text = "已选择储备卡 %d，请确认" % (index + 1)
	else:
		selection_label.text = "当前选择：%s\n（确认后不可更改）" % summary

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
