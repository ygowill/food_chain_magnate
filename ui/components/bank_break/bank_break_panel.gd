# 银行破产面板组件
# 显示银行破产事件，处理首次/二次破产逻辑
class_name BankBreakPanel
extends Control

signal bankruptcy_acknowledged()
signal game_end_triggered()

@onready var title_label: Label = $CenterContainer/Panel/MarginContainer/VBoxContainer/TitleLabel
@onready var message_label: Label = $CenterContainer/Panel/MarginContainer/VBoxContainer/MessageLabel
@onready var details_container: VBoxContainer = $CenterContainer/Panel/MarginContainer/VBoxContainer/DetailsContainer
@onready var continue_btn: Button = $CenterContainer/Panel/MarginContainer/VBoxContainer/ContinueButton

var _bankruptcy_count: int = 0
var _is_game_ending: bool = false
var _bank_total_before: int = 0
var _bank_total_after: int = 0

func _ready() -> void:
	if continue_btn != null:
		continue_btn.pressed.connect(_on_continue_pressed)

	# 初始隐藏
	visible = false

func set_bankruptcy_info(count: int, bank_before: int, bank_after: int) -> void:
	_bankruptcy_count = count
	_bank_total_before = bank_before
	_bank_total_after = bank_after
	_is_game_ending = count >= 2

	_update_display()

func show_with_animation() -> void:
	visible = true
	modulate = Color(1, 1, 1, 0)

	var tween := create_tween()
	tween.tween_property(self, "modulate", Color(1, 1, 1, 1), 0.4)

func _update_display() -> void:
	if title_label != null:
		if _is_game_ending:
			title_label.text = "银行二次破产！"
			title_label.add_theme_color_override("font_color", Color(0.9, 0.3, 0.3, 1))
		else:
			title_label.text = "银行首次破产"
			title_label.add_theme_color_override("font_color", Color(0.9, 0.7, 0.3, 1))

	if message_label != null:
		if _is_game_ending:
			message_label.text = "银行已第二次破产，游戏即将结束！\n完成本回合后进行最终结算。"
		else:
			message_label.text = "银行资金已耗尽，触发首次破产。\n银行将获得额外资金继续运营。"

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

	# 添加详情行
	var before_row := _create_detail_row("破产前银行余额", "$%d" % _bank_total_before)
	details_container.add_child(before_row)

	if not _is_game_ending:
		# 首次破产：显示注资信息
		var inject_amount := 50  # 默认注资金额，可从 GameState 获取
		var inject_row := _create_detail_row("银行注资", "+$%d" % inject_amount, Color(0.5, 0.8, 0.5, 1))
		details_container.add_child(inject_row)

		var after_row := _create_detail_row("破产后银行余额", "$%d" % _bank_total_after)
		details_container.add_child(after_row)

	# 破产次数
	var sep := HSeparator.new()
	details_container.add_child(sep)

	var count_row := _create_detail_row("累计破产次数", "%d / 2" % _bankruptcy_count)
	details_container.add_child(count_row)

	if _is_game_ending:
		var warning_label := Label.new()
		warning_label.text = "⚠ 达到破产上限，游戏将在本回合结束后结算"
		warning_label.add_theme_font_size_override("font_size", 14)
		warning_label.add_theme_color_override("font_color", Color(0.9, 0.5, 0.3, 1))
		warning_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		warning_label.autowrap_mode = TextServer.AUTOWRAP_WORD
		details_container.add_child(warning_label)

func _create_detail_row(label_text: String, value_text: String, value_color: Color = Color(0.9, 0.9, 0.9, 1)) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)

	var label := Label.new()
	label.text = label_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 1))
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
