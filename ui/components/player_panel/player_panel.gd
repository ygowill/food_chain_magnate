# 玩家信息面板组件
# 显示所有玩家的摘要信息，高亮当前玩家
class_name PlayerPanel
extends Control

signal player_selected(player_id: int)

@onready var items_container: VBoxContainer = $MarginContainer/VBoxContainer/ItemsContainer

var _game_state: GameState = null
var _current_player_id: int = -1
var _view_player_id: int = -1
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
	_ensure_player_items()
	refresh()

func _ensure_player_items() -> void:
	var target_count := 0
	if _game_state != null and (_game_state.players is Array):
		target_count = _game_state.players.size()

	if _player_items.size() == target_count:
		var all_valid := true
		for it in _player_items:
			if not is_instance_valid(it):
				all_valid = false
				break
		if all_valid:
			return

	_rebuild_player_items()

func set_current_player(player_id: int) -> void:
	_current_player_id = player_id
	_update_highlight()

func set_view_player(player_id: int) -> void:
	_view_player_id = player_id
	_update_highlight()

func refresh() -> void:
	if _game_state == null:
		return

	for i in range(_player_items.size()):
		if i < _game_state.players.size():
			var player: Dictionary = _game_state.players[i]
			_player_items[i].update_data(player)

	_update_highlight()

func apply_font_settings() -> void:
	for item in _player_items:
		if is_instance_valid(item) and item.has_method("apply_font_settings"):
			item.apply_font_settings()

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
		item.player_color = Globals.get_player_color(i)
		item.item_clicked.connect(_on_player_item_clicked)
		items_container.add_child(item)
		_player_items.append(item)

func _update_highlight() -> void:
	var view_id := _view_player_id
	if _game_state != null and (view_id < 0 or view_id >= _game_state.players.size()):
		view_id = _current_player_id
	for item in _player_items:
		if is_instance_valid(item):
			item.set_selection(item.player_id == _current_player_id, item.player_id == view_id)

func _on_player_item_clicked(player_id: int) -> void:
	player_selected.emit(player_id)
