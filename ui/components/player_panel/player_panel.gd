# 玩家信息面板组件
# 显示所有玩家的摘要信息，高亮当前玩家
class_name PlayerPanel
extends Control

signal player_selected(player_id: int)

const PLAYER_COLORS: Array[Color] = [
	Color(0.9, 0.3, 0.3, 1),  # 红
	Color(0.3, 0.6, 0.9, 1),  # 蓝
	Color(0.3, 0.8, 0.4, 1),  # 绿
	Color(0.9, 0.7, 0.2, 1),  # 黄
	Color(0.7, 0.4, 0.9, 1),  # 紫
]

@onready var items_container: VBoxContainer = $MarginContainer/VBoxContainer/ItemsContainer

var _game_state: GameState = null
var _current_player_id: int = -1
var _player_items: Array[PlayerInfoItem] = []

func _ready() -> void:
	_build_ui()

func _build_ui() -> void:
	if items_container == null:
		items_container = VBoxContainer.new()
		items_container.name = "ItemsContainer"
		add_child(items_container)
	items_container.add_theme_constant_override("separation", 4)

func set_game_state(state: GameState) -> void:
	_game_state = state
	_rebuild_player_items()
	refresh()

func set_current_player(player_id: int) -> void:
	_current_player_id = player_id
	_update_highlight()

func refresh() -> void:
	if _game_state == null:
		return

	for i in range(_player_items.size()):
		if i < _game_state.players.size():
			var player: Dictionary = _game_state.players[i]
			_player_items[i].update_data(player)

	_update_highlight()

func _rebuild_player_items() -> void:
	# 清除旧项
	for item in _player_items:
		if is_instance_valid(item):
			item.queue_free()
	_player_items.clear()

	if _game_state == null:
		return

	# 创建新项
	for i in range(_game_state.players.size()):
		var item := PlayerInfoItem.new()
		item.player_id = i
		item.player_color = PLAYER_COLORS[i % PLAYER_COLORS.size()]
		item.item_clicked.connect(_on_player_item_clicked)
		items_container.add_child(item)
		_player_items.append(item)

func _update_highlight() -> void:
	for item in _player_items:
		if is_instance_valid(item):
			item.set_highlighted(item.player_id == _current_player_id)

func _on_player_item_clicked(player_id: int) -> void:
	player_selected.emit(player_id)
