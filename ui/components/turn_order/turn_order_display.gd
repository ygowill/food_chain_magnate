# 顶部顺序显示（展示用）
# 以紧凑形式显示玩家回合顺序位置，高亮当前行动玩家。
class_name TurnOrderDisplay
extends Control

@onready var slots_container: HBoxContainer = $SlotsContainer

var _player_count: int = 0
var _current_selections: Dictionary = {} # position -> player_id
var _current_player_id: int = -1
var _slot_nodes: Array[OrderBadge] = []

func _ready() -> void:
	_rebuild()

func set_player_count(count: int) -> void:
	_player_count = clamp(count, 0, 5)
	_rebuild()

func set_current_selections(selections: Dictionary) -> void:
	_current_selections = selections.duplicate()
	_update_display()

func set_current_player(player_id: int) -> void:
	_current_player_id = player_id
	_update_display()

func _rebuild() -> void:
	for slot in _slot_nodes:
		if is_instance_valid(slot):
			slot.queue_free()
	_slot_nodes.clear()

	if not is_instance_valid(slots_container):
		return

	for i in range(_player_count):
		var badge := OrderBadge.new()
		badge.slot_position = i
		slots_container.add_child(badge)
		_slot_nodes.append(badge)

	_update_display()

func _update_display() -> void:
	for slot in _slot_nodes:
		if not is_instance_valid(slot):
			continue

		var pos := slot.slot_position
		if _current_selections.has(pos):
			var pid := int(_current_selections[pos])
			slot.set_player(pid, Globals.get_player_color(pid), pid == _current_player_id)
		else:
			slot.set_empty(pos == 0 and _player_count == 0)


class OrderBadge extends PanelContainer:
	var slot_position: int = 0

	var _label: Label
	var _player_id: int = -1
	var _player_color: Color = Color(0.7, 0.7, 0.7, 1)
	var _is_current: bool = false
	var _occupied: bool = false

	func _ready() -> void:
		custom_minimum_size = Vector2(26, 26)
		_label = Label.new()
		_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_label.add_theme_font_size_override("font_size", 12)
		add_child(_label)
		_update()

	func set_player(player_id: int, color: Color, is_current: bool) -> void:
		_player_id = player_id
		_player_color = color
		_is_current = is_current
		_occupied = true
		_update()

	func set_empty(_unused: bool = false) -> void:
		_player_id = -1
		_player_color = Color(0.35, 0.35, 0.4, 0.8)
		_is_current = false
		_occupied = false
		_update()

	func _update() -> void:
		if _label != null:
			_label.text = str(slot_position + 1)

		var style := StyleBoxFlat.new()
		style.bg_color = Color(_player_color.r, _player_color.g, _player_color.b, 0.28) if _occupied else Color(0.15, 0.15, 0.18, 0.8)
		style.border_color = Color(0.95, 0.95, 0.95, 0.95) if _is_current else (_player_color if _occupied else Color(0.3, 0.3, 0.35, 0.6))
		style.set_border_width_all(2 if _is_current else 1)
		style.set_corner_radius_all(13)
		add_theme_stylebox_override("panel", style)

		if _occupied:
			tooltip_text = "顺位 %d: %s" % [slot_position + 1, Globals.get_player_name(_player_id)]
		else:
			tooltip_text = "顺位 %d: （空）" % (slot_position + 1)
