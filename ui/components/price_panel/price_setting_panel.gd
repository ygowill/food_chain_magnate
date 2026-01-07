# 价格设置面板组件
# 强制动作确认面板：不做逐产品改价（以 gameplay/actions/* 为准）
class_name PriceSettingPanel
extends Control

signal price_confirmed(action_id: String)
signal cancelled()

@onready var title_label: Label = $MarginContainer/VBoxContainer/TitleLabel
@onready var products_container: VBoxContainer = $MarginContainer/VBoxContainer/ScrollContainer/ProductsContainer
@onready var confirm_btn: Button = $MarginContainer/VBoxContainer/ButtonRow/ConfirmButton
@onready var cancel_btn: Button = $MarginContainer/VBoxContainer/ButtonRow/CancelButton

var _current_prices: Dictionary = {}
var _mode: String = "price"  # price | discount | luxury
var _action_id: String = "set_price"

func _ready() -> void:
	if confirm_btn != null:
		confirm_btn.pressed.connect(_on_confirm_pressed)
	if cancel_btn != null:
		cancel_btn.pressed.connect(_on_cancel_pressed)

	_rebuild_content()

func set_mode(mode: String) -> void:
	_mode = mode
	match _mode:
		"discount":
			_action_id = "set_discount"
		"luxury":
			_action_id = "set_luxury_price"
		_:
			_action_id = "set_price"

	if title_label != null:
		if _mode == "discount":
			title_label.text = "设置折扣"
		elif _mode == "luxury":
			title_label.text = "设置奢侈品价格"
		else:
			title_label.text = "设置价格"
	_rebuild_content()

func set_current_prices(prices: Dictionary) -> void:
	_current_prices = prices.duplicate()
	_rebuild_content()

func _rebuild_content() -> void:
	if products_container == null:
		return

	for child in products_container.get_children():
		if is_instance_valid(child):
			child.queue_free()

	var info := Label.new()
	info.autowrap_mode = TextServer.AUTOWRAP_WORD
	info.add_theme_font_size_override("font_size", 13)
	info.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8, 1))
	info.text = _get_action_description()
	products_container.add_child(info)

	var hint := Label.new()
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 1))
	hint.text = "该动作不需要选择产品或输入价格，确认即可执行。"
	products_container.add_child(hint)

func _get_action_description() -> String:
	match _mode:
		"discount":
			return "强制动作：激活折扣经理效果（基础单价 -$3）。"
		"luxury":
			return "强制动作：激活奢侈品经理效果（基础单价 +$10）。"
		_:
			return "强制动作：激活定价经理效果（基础单价 -$1）。"

func _on_confirm_pressed() -> void:
	price_confirmed.emit(_action_id)

func _on_cancel_pressed() -> void:
	cancelled.emit()
