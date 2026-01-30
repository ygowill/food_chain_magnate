# TurnOrderSelectionModal：联机等待态也显示顺位进度；非当前玩家不可交互
extends RefCounted

const ModalScene = preload("res://ui/components/modal_panel/turn_order_selection_modal.tscn")

static func run() -> Result:
	var engine := GameEngine.new()
	var init: Result = engine.initialize(2, 12345)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)

	var state := engine.get_state()
	if state == null:
		return Result.failure("state 为空")

	var modal = ModalScene.instantiate()
	if modal == null or not is_instance_valid(modal):
		return Result.failure("实例化 TurnOrderSelectionModal 失败")

	_bind_modal_nodes(modal)
	_bind_turn_order_display_nodes(modal)
	if modal.has_method("_ready"):
		modal.call("_ready")

	if not modal.has_method("setup"):
		_safe_free(modal)
		return Result.failure("TurnOrderSelectionModal 缺少 setup")

	var selections := {}

	# 交互态：确认按钮可见但初始禁用；点击空位后启用确认
	modal.call("setup", state, 0, selections, true, 0)
	var confirm = modal.get("confirm_button")
	var selection_label = modal.get("selection_label")
	var display = modal.get("display")

	if not is_instance_valid(confirm) or not (confirm is Button):
		_safe_free(modal)
		return Result.failure("confirm_button 无效（节点结构变更）")
	if not bool((confirm as Button).visible):
		_safe_free(modal)
		return Result.failure("交互态下 confirm_button 应可见")
	if not bool((confirm as Button).disabled):
		_safe_free(modal)
		return Result.failure("交互态下 confirm_button 初始应禁用")
	if is_instance_valid(selection_label) and (selection_label is Label):
		if not str((selection_label as Label).text).contains("轮到你行动"):
			_safe_free(modal)
			return Result.failure("交互态下 selection_label 文案异常: %s" % str((selection_label as Label).text))

	if not is_instance_valid(display):
		_safe_free(modal)
		return Result.failure("display 无效（节点结构变更）")
	if not bool(display.get("_selectable")):
		_safe_free(modal)
		return Result.failure("交互态下 TurnOrderDisplay 应可选择（_selectable=true）")

	var slots_val = display.get("_slot_nodes")
	var slots: Array = slots_val if slots_val is Array else []
	if slots.is_empty():
		_safe_free(modal)
		return Result.failure("TurnOrderDisplay 未生成 slot_nodes（player_count=%d）" % int(state.players.size()))
	var badge0 = slots[0]
	if badge0 == null or not is_instance_valid(badge0):
		_safe_free(modal)
		return Result.failure("slot_nodes[0] 无效")
	badge0.emit_signal("clicked", 0)

	if bool((confirm as Button).disabled):
		_safe_free(modal)
		return Result.failure("点击空位后 confirm_button 应启用")

	# 等待态：确认按钮隐藏，且不可点击空位改变选择
	modal.call("setup", state, 0, selections, false, 1)

	if bool((confirm as Button).visible):
		_safe_free(modal)
		return Result.failure("等待态下 confirm_button 应隐藏")
	if not bool((confirm as Button).disabled):
		_safe_free(modal)
		return Result.failure("等待态下 confirm_button 应禁用")
	if is_instance_valid(selection_label) and (selection_label is Label):
		if not str((selection_label as Label).text).contains("正在选择顺位"):
			_safe_free(modal)
			return Result.failure("等待态下 selection_label 文案异常: %s" % str((selection_label as Label).text))
	if bool(display.get("_selectable")):
		_safe_free(modal)
		return Result.failure("等待态下 TurnOrderDisplay 不应可选择（_selectable=false）")

	badge0.emit_signal("clicked", 0)
	var selected_pos := int(modal.get("_selected_position"))
	if selected_pos != -1:
		_safe_free(modal)
		return Result.failure("等待态下不应设置 _selected_position，但得到 %d" % selected_pos)

	var ok := Result.success()
	_safe_free(modal)
	return ok

static func _bind_modal_nodes(modal) -> void:
	if modal == null or not is_instance_valid(modal):
		return

	# Base (ModalPanelBase)
	modal.set("overlay", modal.get_node("Overlay"))
	modal.set("panel", modal.get_node("Panel"))
	modal.set("title_label", modal.get_node("Panel/MarginContainer/VBoxContainer/TitleRow/TitleLabel"))
	modal.set("content_host", modal.get_node("Panel/MarginContainer/VBoxContainer/ContentHost"))
	modal.set("confirm_button", modal.get_node("Panel/MarginContainer/VBoxContainer/ButtonRow/ConfirmButton"))
	modal.set("cancel_button", modal.get_node("Panel/MarginContainer/VBoxContainer/ButtonRow/CancelButton"))
	modal.set("hint_label", modal.get_node("Panel/MarginContainer/VBoxContainer/HintLabel"))

	# TurnOrderSelectionModal
	modal.set("selection_label", modal.get_node("Panel/MarginContainer/VBoxContainer/ContentHost/VBoxContainer/SelectionLabel"))
	modal.set("display", modal.get_node("Panel/MarginContainer/VBoxContainer/ContentHost/VBoxContainer/TurnOrderDisplay"))

static func _bind_turn_order_display_nodes(modal) -> void:
	if modal == null or not is_instance_valid(modal):
		return
	var display = modal.get("display")
	if display == null or not is_instance_valid(display):
		return
	var slots_container = display.get_node_or_null("SlotsContainer")
	if slots_container != null and is_instance_valid(slots_container):
		display.set("slots_container", slots_container)

static func _safe_free(node: Node) -> void:
	if node != null and is_instance_valid(node):
		node.free()
