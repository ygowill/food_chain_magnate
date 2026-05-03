# ReserveCardSelectionModal：等待态不泄露卡片信息
extends RefCounted

const ModalScene = preload("res://ui/components/modal_panel/reserve_card_selection_modal.tscn")

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
		return Result.failure("实例化 ReserveCardSelectionModal 失败")

	_bind_modal_nodes(modal)
	if modal.has_method("_ready"):
		modal.call("_ready")

	# 交互态：应展示卡片信息（desc 非空）
	if not modal.has_method("setup"):
		_safe_free(modal)
		return Result.failure("ReserveCardSelectionModal 缺少 setup")
	modal.call("setup", state, 0)

	var btn0 = modal.get("card_button_0")
	var desc0 = modal.get("card_desc_0")
	if not is_instance_valid(btn0) or not (btn0 is TextureButton):
		_safe_free(modal)
		return Result.failure("card_button_0 应为 TextureButton")
	if not is_instance_valid(desc0) or not (desc0 is Label):
		_safe_free(modal)
		return Result.failure("card_desc_0 无效（节点结构变更）")
	if bool((btn0 as TextureButton).disabled):
		_safe_free(modal)
		return Result.failure("交互态下 card_button_0 不应禁用")
	if (btn0 as TextureButton).texture_normal == null:
		_safe_free(modal)
		return Result.failure("交互态下 card_button_0 应展示卡图")
	if str((desc0 as Label).text).strip_edges().is_empty():
		_safe_free(modal)
		return Result.failure("交互态下 card_desc_0 不应为空（应展示卡片信息）")

	# 等待态：不得展示任何卡片信息（desc 为空，按钮禁用）
	if not modal.has_method("setup_waiting"):
		_safe_free(modal)
		return Result.failure("ReserveCardSelectionModal 缺少 setup_waiting")
	modal.call("setup_waiting", 0)

	if not bool((btn0 as TextureButton).disabled):
		_safe_free(modal)
		return Result.failure("等待态下 card_button_0 应禁用")
	if (btn0 as TextureButton).texture_normal != null:
		_safe_free(modal)
		return Result.failure("等待态下 card_button_0 不应保留卡图")
	if not str((desc0 as Label).text).strip_edges().is_empty():
		_safe_free(modal)
		return Result.failure("等待态下 card_desc_0 应为空（不得泄露卡片信息）")

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

	# ReserveCardSelectionModal
	modal.set("selection_label", modal.get_node("Panel/MarginContainer/VBoxContainer/ContentHost/VBoxContainer/SelectionLabel"))
	modal.set("card_button_0", modal.get_node("Panel/MarginContainer/VBoxContainer/ContentHost/VBoxContainer/CardsRow/CardButton0"))
	modal.set("card_button_1", modal.get_node("Panel/MarginContainer/VBoxContainer/ContentHost/VBoxContainer/CardsRow/CardButton1"))
	modal.set("card_button_2", modal.get_node("Panel/MarginContainer/VBoxContainer/ContentHost/VBoxContainer/CardsRow/CardButton2"))
	modal.set("card_image_0", modal.get_node("Panel/MarginContainer/VBoxContainer/ContentHost/VBoxContainer/CardsRow/CardButton0/Content/VBoxContainer/CardImage"))
	modal.set("card_image_1", modal.get_node("Panel/MarginContainer/VBoxContainer/ContentHost/VBoxContainer/CardsRow/CardButton1/Content/VBoxContainer/CardImage"))
	modal.set("card_image_2", modal.get_node("Panel/MarginContainer/VBoxContainer/ContentHost/VBoxContainer/CardsRow/CardButton2/Content/VBoxContainer/CardImage"))
	modal.set("card_title_0", modal.get_node("Panel/MarginContainer/VBoxContainer/ContentHost/VBoxContainer/CardsRow/CardButton0/Content/VBoxContainer/CardTitle"))
	modal.set("card_title_1", modal.get_node("Panel/MarginContainer/VBoxContainer/ContentHost/VBoxContainer/CardsRow/CardButton1/Content/VBoxContainer/CardTitle"))
	modal.set("card_title_2", modal.get_node("Panel/MarginContainer/VBoxContainer/ContentHost/VBoxContainer/CardsRow/CardButton2/Content/VBoxContainer/CardTitle"))
	modal.set("card_desc_0", modal.get_node("Panel/MarginContainer/VBoxContainer/ContentHost/VBoxContainer/CardsRow/CardButton0/Content/VBoxContainer/CardDesc"))
	modal.set("card_desc_1", modal.get_node("Panel/MarginContainer/VBoxContainer/ContentHost/VBoxContainer/CardsRow/CardButton1/Content/VBoxContainer/CardDesc"))
	modal.set("card_desc_2", modal.get_node("Panel/MarginContainer/VBoxContainer/ContentHost/VBoxContainer/CardsRow/CardButton2/Content/VBoxContainer/CardDesc"))

static func _safe_free(node: Node) -> void:
	if node != null and is_instance_valid(node):
		node.free()
