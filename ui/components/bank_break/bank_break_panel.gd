# 银行破产面板组件
# 显示银行破产事件，处理首次/二次破产逻辑
class_name BankBreakPanel
extends Control

const UiStylesClass = preload("res://ui/utils/ui_styles.gd")
const ReserveCardsViewDataClass = preload("res://ui/components/reserve_cards/reserve_cards_view_data.gd")
const WarningIconTexture: Texture2D = preload("res://assets/images/ui_icons/kenney_game/warning.png")

signal bankruptcy_acknowledged()
signal game_end_triggered()

@onready var title_label: Label = $CenterContainer/Panel/MarginContainer/VBoxContainer/TitleLabel
@onready var message_label: Label = $CenterContainer/Panel/MarginContainer/VBoxContainer/MessageLabel
@onready var details_container: VBoxContainer = $CenterContainer/Panel/MarginContainer/VBoxContainer/DetailsContainer
@onready var continue_btn: Button = $CenterContainer/Panel/MarginContainer/VBoxContainer/ContinueButton
@onready var background_rect: ColorRect = $Background
@onready var _content_panel: PanelContainer = $CenterContainer/Panel

var _bankruptcy_count: int = 0
var _is_game_ending: bool = false
var _max_breaks: int = 2
var _event_kind: String = ""
var _bank_total_before: int = 0
var _bank_total_after: int = 0
var _event_data: Dictionary = {}

func _ready() -> void:
	if continue_btn != null:
		continue_btn.pressed.connect(_on_continue_pressed)

	# 应用对话框表面样式
	if _content_panel != null:
		UiStylesClass.apply_dialog_surface(_content_panel)
	if background_rect != null:
		UiStylesClass.apply_overlay_dim(background_rect)

	# 初始隐藏
	visible = false

func set_bankruptcy_info(count: int, bank_before: int, bank_after: int, event_data: Dictionary = {}) -> void:
	_bankruptcy_count = count
	_bank_total_before = bank_before
	_bank_total_after = bank_after
	_event_data = event_data.duplicate(true)
	_event_kind = str(_event_data.get("kind", "")).strip_edges()
	_max_breaks = _read_max_breaks(_event_data)
	_is_game_ending = count >= _max_breaks

	_update_display()

func _read_max_breaks(event_data: Dictionary) -> int:
	var v = event_data.get("max_breaks", 2)
	if v is int:
		return clampi(int(v), 1, 2)
	if v is float:
		var f: float = float(v)
		if f == floor(f):
			return clampi(int(f), 1, 2)
	return 2

func show_with_animation() -> void:
	visible = true
	modulate = Color(1, 1, 1, 0)

	var tween := create_tween()
	tween.tween_property(self, "modulate", Color(1, 1, 1, 1), 0.4)

func _update_display() -> void:
	var kind := _event_kind
	if kind.is_empty():
		kind = "second" if _bankruptcy_count >= 2 else "first"
	var is_first := kind == "first"
	var is_second := kind == "second"

	if title_label != null:
		if is_second:
			title_label.text = "银行二次破产！"
		elif is_first:
			title_label.text = "银行首次破产！" if _is_game_ending else "银行首次破产"
		else:
			title_label.text = "银行破产"
		title_label.add_theme_color_override("font_color", Color(0.73, 0.23, 0.18, 1) if _is_game_ending else Color(0.17, 0.13, 0.09, 1))

	if message_label != null:
		if _is_game_ending:
			if is_second:
				message_label.text = "银行已第二次破产，游戏即将结束！\n完成本回合后进行最终结算。"
			else:
				message_label.text = "银行已破产且达到破产上限，游戏即将结束！\n完成本回合后进行最终结算。"
		else:
			message_label.text = "银行资金已耗尽，触发首次破产。\n银行将获得额外资金继续运营。" if is_first else "银行资金已耗尽，触发破产事件。"

	_rebuild_details()

	if continue_btn != null:
		if _is_game_ending:
			continue_btn.text = "进入最终回合"
		else:
			continue_btn.text = "继续游戏"

func _rebuild_details() -> void:
	if details_container == null:
		return

	# 清除旧内容
	for child in details_container.get_children():
		child.queue_free()

	var before_total := _bank_total_before
	if _event_data.has("bank_total_before"):
		before_total = int(_event_data.get("bank_total_before", before_total))
	var after_total := _bank_total_after
	if _event_data.has("bank_total_after"):
		after_total = int(_event_data.get("bank_total_after", after_total))

	# 添加详情行
	var before_row := _create_detail_row("破产前银行余额", "$%d" % before_total)
	details_container.add_child(before_row)

	var kind := str(_event_data.get("kind", "")).strip_edges()
	if kind.is_empty():
		kind = "second" if _bankruptcy_count >= 2 else "first"
	if kind == "first":
		# 首次破产：显示注资和各玩家揭示的储备卡详情
		var inject_amount := int(_event_data.get("reserve_added", maxi(0, after_total - before_total)))
		var inject_row := _create_detail_row("银行注资", "+$%d" % inject_amount, Color(0.28, 0.55, 0.22, 1))
		details_container.add_child(inject_row)

		var after_row := _create_detail_row("破产后银行余额", "$%d" % after_total)
		details_container.add_child(after_row)

		var revealed_cards := _read_revealed_cards()
		if not revealed_cards.is_empty():
			details_container.add_child(HSeparator.new())
			for item in revealed_cards:
				var pid := int(item.get("player_id", -1))
				var row := _create_detail_row(
					"%s 储备卡" % _player_display_name(pid),
					_format_revealed_card(item)
				)
				details_container.add_child(row)

	# 破产次数
	var sep := HSeparator.new()
	details_container.add_child(sep)

	var count_row := _create_detail_row("累计破产次数", "%d / %d" % [_bankruptcy_count, _max_breaks])
	details_container.add_child(count_row)

	if _is_game_ending:
		var warning_row := HBoxContainer.new()
		warning_row.add_theme_constant_override("separation", 8)
		details_container.add_child(warning_row)

		var warning_icon := TextureRect.new()
		warning_icon.custom_minimum_size = Vector2(16, 16)
		warning_icon.texture = WarningIconTexture
		warning_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		warning_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		warning_icon.modulate = Color(0.73, 0.23, 0.18, 0.9)
		warning_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		warning_row.add_child(warning_icon)

		var warning_label := Label.new()
		warning_label.text = "达到破产上限，游戏将在本回合结束后结算"
		warning_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		warning_label.add_theme_font_size_override("font_size", 14)
		warning_label.add_theme_color_override("font_color", Color(0.73, 0.23, 0.18, 0.9))
		warning_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		warning_label.autowrap_mode = TextServer.AUTOWRAP_WORD
		warning_row.add_child(warning_label)

	var trigger_reason := str(_event_data.get("trigger_reason", "")).strip_edges()
	if not trigger_reason.is_empty():
		details_container.add_child(_create_detail_row("触发原因", trigger_reason))

	var required_payment := int(_event_data.get("required_payment", 0))
	if required_payment > 0:
		details_container.add_child(_create_detail_row("触发支付额", "$%d" % required_payment))

func _create_detail_row(label_text: String, value_text: String, value_color: Color = Color(0.17, 0.13, 0.09, 1)) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)

	var label := Label.new()
	label.text = label_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color(0.5, 0.45, 0.35, 1))
	row.add_child(label)

	var value := Label.new()
	value.text = value_text
	value.add_theme_font_size_override("font_size", 14)
	value.add_theme_color_override("font_color", value_color)
	row.add_child(value)

	return row

func _on_continue_pressed() -> void:
	if _is_game_ending:
		game_end_triggered.emit()
	else:
		bankruptcy_acknowledged.emit()

	_hide_with_animation()

func _hide_with_animation() -> void:
	var tween := create_tween()
	tween.tween_property(self, "modulate", Color(1, 1, 1, 0), 0.3)
	tween.tween_callback(func(): visible = false)

func _read_revealed_cards() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var revealed_val = _event_data.get("revealed_cards", null)
	if not (revealed_val is Array):
		return out
	for item_val in revealed_val:
		if not (item_val is Dictionary):
			continue
		out.append((item_val as Dictionary).duplicate(true))
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("player_id", -1)) < int(b.get("player_id", -1))
	)
	return out

func _player_display_name(player_id: int) -> String:
	if player_id >= 0 and Globals != null and Globals.has_method("get_player_name"):
		var name := str(Globals.get_player_name(player_id)).strip_edges()
		if not name.is_empty():
			return name
	if player_id >= 0:
		return "玩家 %d" % (player_id + 1)
	return "玩家 ?"

func _format_revealed_card(item: Dictionary) -> String:
	var card_val = item.get("card", null)
	var card: Dictionary = card_val if card_val is Dictionary else {}
	var selected_index := int(item.get("selected_index", -1))
	return ReserveCardsViewDataClass.format_revealed_card_summary(card, selected_index)
