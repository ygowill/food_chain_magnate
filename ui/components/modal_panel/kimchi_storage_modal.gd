# 清理阶段：泡菜冰柜储存选择遮罩面板
class_name KimchiStorageModal
extends "res://ui/components/modal_panel/modal_panel_base.gd"

const ProductRegistryClass = preload("res://core/data/product_registry.gd")

const PRODUCT_ID := "kimchi"

@onready var info_label: Label = $Panel/MarginContainer/VBoxContainer/ContentHost/VBoxContainer/InfoLabel
@onready var detail_label: Label = $Panel/MarginContainer/VBoxContainer/ContentHost/VBoxContainer/DetailLabel

func _ready() -> void:
	super._ready()

	set_title_text("泡菜冰柜")
	set_confirm_text("存泡菜")
	set_cancel_text("不存泡菜")

	if is_instance_valid(hint_label):
		hint_label.text = "存泡菜：最多保留 10 个泡菜，并丢弃其它食物/饮料。｜不存泡菜：丢弃所有泡菜。"

func setup(state: GameState, current_player_id: int) -> void:
	_set_buttons_enabled(true)
	_set_labels_invalid("")

	if state == null or current_player_id < 0 or current_player_id >= state.players.size():
		_set_labels_invalid("状态无效")
		_set_buttons_enabled(false)
		return

	if not ProductRegistryClass.is_loaded():
		_set_labels_invalid("ProductRegistry 未初始化")
		_set_buttons_enabled(false)
		return

	var p_val = state.players[current_player_id]
	if not (p_val is Dictionary):
		_set_labels_invalid("玩家数据无效")
		_set_buttons_enabled(false)
		return
	var player: Dictionary = p_val

	var inv_val = player.get("inventory", null)
	if not (inv_val is Dictionary):
		_set_labels_invalid("库存数据无效")
		_set_buttons_enabled(false)
		return
	var inv: Dictionary = inv_val
	var count: int = maxi(0, int(inv.get(PRODUCT_ID, 0)))

	var name := Globals.get_player_name(current_player_id) if Globals != null else ("玩家%d" % (current_player_id + 1))
	if is_instance_valid(info_label):
		info_label.text = "当前玩家：%s｜泡菜库存：%d" % [name, count]

	var clamp_note := ""
	if count > 10:
		clamp_note = "（若存泡菜，将保留 10 个，其余将被丢弃）"
	if is_instance_valid(detail_label):
		detail_label.text = "请选择是否存泡菜%s" % clamp_note

func _on_confirm_pressed() -> void:
	_set_buttons_enabled(false)
	completed.emit({"store": true})

func _on_cancel_pressed() -> void:
	_set_buttons_enabled(false)
	completed.emit({"store": false})

func _set_buttons_enabled(enabled: bool) -> void:
	set_confirm_enabled(enabled)
	if is_instance_valid(cancel_button):
		cancel_button.disabled = not enabled

func _set_labels_invalid(msg: String) -> void:
	if is_instance_valid(info_label):
		info_label.text = msg
	if is_instance_valid(detail_label):
		detail_label.text = ""

