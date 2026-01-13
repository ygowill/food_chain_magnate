# 顺序选择遮罩面板（OrderOfBusiness）
class_name TurnOrderSelectionModal
extends "res://ui/components/modal_panel/modal_panel_base.gd"

@onready var selection_label: Label = $Panel/MarginContainer/VBoxContainer/ContentHost/VBoxContainer/SelectionLabel
@onready var track: Control = $Panel/MarginContainer/VBoxContainer/ContentHost/VBoxContainer/TurnOrderTrack

var _selected_position: int = -1

func _ready() -> void:
	super._ready()
	set_title_text("选择顺序位置")
	set_confirm_text("确认选择")
	set_cancel_text("关闭")
	set_confirm_enabled(false)

	if is_instance_valid(track) and track.has_signal("position_selected"):
		if not track.position_selected.is_connected(_on_position_selected):
			track.position_selected.connect(_on_position_selected)

func setup(state: GameState, current_player_id: int, selections: Dictionary) -> void:
	_selected_position = -1
	set_confirm_enabled(false)
	var current_name := Globals.get_player_name(current_player_id) if Globals != null else ("玩家%d" % (current_player_id + 1))
	set_title_text("选择顺序位置｜当前: %s" % current_name)
	if is_instance_valid(selection_label):
		selection_label.text = "当前玩家：%s，请选择一个空位" % current_name

	if not is_instance_valid(track):
		return
	if track.has_method("set_player_count"):
		track.call("set_player_count", state.players.size())
	if track.has_method("set_current_selections"):
		track.call("set_current_selections", selections)
	if track.has_method("set_selectable"):
		track.call("set_selectable", true, current_player_id)
		if track.has_method("highlight_available_positions"):
			track.call("highlight_available_positions")

func _on_position_selected(position: int) -> void:
	_selected_position = position
	set_confirm_enabled(true)
	if is_instance_valid(selection_label):
		selection_label.text = "当前选择: 顺位 %d" % (position + 1)

func _on_confirm_pressed() -> void:
	if _selected_position < 0:
		return
	completed.emit({"position": _selected_position})
