# 顺序轨组件
# 显示玩家回合顺序，支持在 OrderOfBusiness 阶段选择位置
class_name TurnOrderTrack
extends Control

signal position_selected(position: int)

const PLAYER_COLORS: Array[Color] = [
	Color(0.9, 0.3, 0.3, 1),  # 红
	Color(0.3, 0.6, 0.9, 1),  # 蓝
	Color(0.3, 0.8, 0.4, 1),  # 绿
	Color(0.9, 0.7, 0.2, 1),  # 黄
	Color(0.7, 0.4, 0.9, 1),  # 紫
]

@onready var slots_container: HBoxContainer = $MarginContainer/VBoxContainer/SlotsContainer

var _player_count: int = 2
var _current_selections: Dictionary = {}  # position -> player_id
var _selectable: bool = false
var _selecting_player_id: int = -1
var _slot_nodes: Array[OrderSlot] = []

func _ready() -> void:
	_rebuild_slots()

func set_player_count(count: int) -> void:
	_player_count = clamp(count, 2, 5)
	_rebuild_slots()

func set_current_selections(selections: Dictionary) -> void:
	_current_selections = selections.duplicate()
	_update_display()

func set_selectable(can_select: bool, player_id: int) -> void:
	_selectable = can_select
	_selecting_player_id = player_id
	_update_display()

func highlight_available_positions() -> void:
	for slot in _slot_nodes:
		if is_instance_valid(slot):
			var is_available := not _current_selections.has(slot.slot_position)
			slot.set_highlighted(is_available and _selectable)

func _rebuild_slots() -> void:
	# 清除旧卡槽
	for slot in _slot_nodes:
		if is_instance_valid(slot):
			slot.queue_free()
	_slot_nodes.clear()

	if slots_container == null:
		return

	# 创建新卡槽
	for i in range(_player_count):
		var slot := OrderSlot.new()
		slot.slot_position = i
		slot.slot_clicked.connect(_on_slot_clicked)
		slots_container.add_child(slot)
		_slot_nodes.append(slot)

	_update_display()

func _update_display() -> void:
	for slot in _slot_nodes:
		if not is_instance_valid(slot):
			continue

		var pos := slot.slot_position

		# 检查是否已被选择
		if _current_selections.has(pos):
			var player_id: int = int(_current_selections[pos])
			var color: Color = PLAYER_COLORS[player_id % PLAYER_COLORS.size()]
			slot.set_occupied(true, player_id, color)
			slot.set_highlighted(false)
		else:
			slot.set_occupied(false, -1, Color.WHITE)
			slot.set_highlighted(_selectable)

		slot.set_clickable(_selectable and not _current_selections.has(pos))

func _on_slot_clicked(position: int) -> void:
	if not _selectable:
		return
	if _current_selections.has(position):
		return  # 已被占用

	position_selected.emit(position)


# === 内部类：顺序槽 ===
class OrderSlot extends PanelContainer:
	signal slot_clicked(position: int)

	var slot_position: int = 0

	var _occupied: bool = false
	var _player_id: int = -1
	var _player_color: Color = Color.WHITE
	var _highlighted: bool = false
	var _clickable: bool = false

	var _number_label: Label
	var _player_indicator: ColorRect

	func _ready() -> void:
		_build_ui()
		gui_input.connect(_on_gui_input)

	func _build_ui() -> void:
		custom_minimum_size = Vector2(60, 80)

		var vbox := VBoxContainer.new()
		vbox.alignment = BoxContainer.ALIGNMENT_CENTER
		add_child(vbox)

		# 位置编号
		_number_label = Label.new()
		_number_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_number_label.add_theme_font_size_override("font_size", 20)
		vbox.add_child(_number_label)

		# 玩家指示器
		_player_indicator = ColorRect.new()
		_player_indicator.custom_minimum_size = Vector2(40, 30)
		_player_indicator.visible = false
		vbox.add_child(_player_indicator)

		_update_display()
		_update_style()

	func set_occupied(occupied: bool, player_id: int, color: Color) -> void:
		_occupied = occupied
		_player_id = player_id
		_player_color = color
		_update_display()
		_update_style()

	func set_highlighted(highlighted: bool) -> void:
		_highlighted = highlighted
		_update_style()

	func set_clickable(clickable: bool) -> void:
		_clickable = clickable
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if clickable else Control.CURSOR_ARROW

	func _update_display() -> void:
		if _number_label != null:
			_number_label.text = str(slot_position + 1)

		if _player_indicator != null:
			_player_indicator.visible = _occupied
			if _occupied:
				_player_indicator.color = _player_color

	func _update_style() -> void:
		var style := StyleBoxFlat.new()

		if _occupied:
			style.bg_color = Color(0.2, 0.25, 0.3, 0.9)
			style.border_color = _player_color
			style.set_border_width_all(2)
		elif _highlighted:
			style.bg_color = Color(0.25, 0.35, 0.25, 0.8)
			style.border_color = Color(0.5, 0.8, 0.5, 0.8)
			style.set_border_width_all(2)
		else:
			style.bg_color = Color(0.15, 0.15, 0.18, 0.8)
			style.border_color = Color(0.3, 0.3, 0.35, 0.5)
			style.set_border_width_all(1)

		style.set_corner_radius_all(6)
		add_theme_stylebox_override("panel", style)

	func _on_gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton:
			var e: InputEventMouseButton = event
			if e.button_index == MOUSE_BUTTON_LEFT and e.pressed and _clickable:
				slot_clicked.emit(slot_position)
