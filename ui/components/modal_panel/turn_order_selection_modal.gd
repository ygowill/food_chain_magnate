# 顺序选择遮罩面板（OrderOfBusiness）
class_name TurnOrderSelectionModal
extends "res://ui/components/modal_panel/modal_panel_base.gd"

@onready var selection_label: Label = $Panel/MarginContainer/VBoxContainer/ContentHost/VBoxContainer/SelectionLabel
@onready var display: Control = $Panel/MarginContainer/VBoxContainer/ContentHost/VBoxContainer/TurnOrderDisplay

var _selected_position: int = -1
var _interactive: bool = true
var _base_selections: Dictionary = {}
var _acting_player_id: int = -1

func _ready() -> void:
	super._ready()
	set_title_text("选择顺序位置")
	set_confirm_text("确认选择")
	set_cancel_text("关闭")
	set_confirm_enabled(false)
	if is_instance_valid(selection_label):
		UiStylesClass.apply_label_dark(selection_label)
	if is_instance_valid(hint_label):
		UiStylesClass.apply_label_hint_dark(hint_label)

	if is_instance_valid(display) and display.has_signal("position_selected"):
		if not display.position_selected.is_connected(_on_position_selected):
			display.position_selected.connect(_on_position_selected)

func setup(state: GameState, current_player_id: int, selections: Dictionary, interactive: bool = true, local_player_id: int = -1) -> void:
	_interactive = bool(interactive)
	_selected_position = -1
	_base_selections = selections.duplicate(true)
	_acting_player_id = int(current_player_id)
	set_confirm_enabled(false)
	if is_instance_valid(confirm_button):
		confirm_button.visible = _interactive
	var current_name := Globals.get_player_name(current_player_id) if Globals != null else ("玩家%d" % (current_player_id + 1))
	set_title_text("选择顺序位置｜当前: %s" % current_name)
	if is_instance_valid(selection_label):
		if _interactive:
			selection_label.text = "轮到你行动：请选择一个空位"
		else:
			var extra := ""
			if local_player_id >= 0:
				for pos in selections.keys():
					if int(selections[pos]) == int(local_player_id):
						extra = "（你已选择：顺位 %d）" % (int(pos) + 1)
						break
			selection_label.text = "当前玩家：%s 正在选择顺位%s" % [current_name, extra]

	if not is_instance_valid(display):
		return
	if display.has_method("set_game_state"):
		display.call("set_game_state", state)
	if display.has_method("set_player_count"):
		display.call("set_player_count", state.players.size())
	if display.has_method("set_current_selections"):
		display.call("set_current_selections", selections)
	if display.has_method("set_current_player"):
		# 非当前玩家（等待态）也应能看到“当前玩家”指示。
		display.call("set_current_player", current_player_id)
	if display.has_method("set_selectable"):
		display.call("set_selectable", _interactive)

func _on_position_selected(position: int) -> void:
	if not _interactive:
		return
	_selected_position = position
	set_confirm_enabled(true)
	if is_instance_valid(selection_label):
		selection_label.text = "当前选择: 顺位 %d" % (position + 1)
	if is_instance_valid(display) and display.has_method("set_current_selections") and _acting_player_id >= 0:
		var preview := _base_selections.duplicate(true)
		preview[position] = _acting_player_id
		display.call("set_current_selections", preview)

func _on_confirm_pressed() -> void:
	if _selected_position < 0:
		return
	completed.emit({"position": _selected_position})
