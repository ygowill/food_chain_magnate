# 公司结构面板组件：内部卡槽
class_name CompanyStructureCardSlot
extends PanelContainer

signal card_placed(slot_index: int, employee_id: String)
signal card_removed(slot_index: int, employee_id: String)

const EmployeeCardClass = preload("res://ui/components/employee_card/employee_card.gd")

var slot_index: int = 0
var _card: EmployeeCard = null
var _drop_highlighted: bool = false

func _ready() -> void:
	_build_ui()

func _build_ui() -> void:
	custom_minimum_size = EmployeeCardClass.COMPACT_SIZE
	_apply_style()

	# 空卡槽提示
	var hint := Label.new()
	hint.text = "空卡槽"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color(0.4, 0.4, 0.4, 0.6))
	hint.name = "Hint"
	add_child(hint)

func set_drop_highlighted(highlighted: bool) -> void:
	if _drop_highlighted == highlighted:
		return
	_drop_highlighted = highlighted
	_apply_style()

func get_slot_index() -> int:
	return slot_index

func _apply_style() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.15, 0.18, 0.8)
	if _drop_highlighted:
		style.border_color = Color(0.8, 0.7, 0.3, 0.9)
		style.set_border_width_all(3)
	else:
		style.border_color = Color(0.3, 0.3, 0.35, 0.6)
		style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	add_theme_stylebox_override("panel", style)

func place_card(card: EmployeeCard) -> void:
	if _card != null:
		remove_card()

	_card = card
	add_child(_card)

	var hint := get_node_or_null("Hint")
	if hint != null:
		hint.visible = false

	card_placed.emit(slot_index, _card.employee_id)

func remove_card() -> void:
	if _card == null:
		return

	var emp_id := _card.employee_id
	_card.queue_free()
	_card = null

	var hint := get_node_or_null("Hint")
	if hint != null:
		hint.visible = true

	card_removed.emit(slot_index, emp_id)

func has_card() -> bool:
	return _card != null and is_instance_valid(_card)

func get_employee_id() -> String:
	if _card != null:
		return _card.employee_id
	return ""
