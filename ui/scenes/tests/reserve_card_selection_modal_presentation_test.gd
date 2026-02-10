class_name ReserveCardSelectionModalPresentationTest
extends RefCounted

const ModalScene = preload("res://ui/components/modal_panel/reserve_card_selection_modal.tscn")

static func run() -> Result:
	var base_engine := GameEngine.new()
	var base_init: Result = base_engine.initialize(2, 12345)
	if not base_init.ok:
		return Result.failure("初始化失败(base): %s" % base_init.error)
	var base_state := base_engine.get_state()
	if base_state == null:
		return Result.failure("base_state 为空")

	var modal_base = ModalScene.instantiate()
	if modal_base == null or not is_instance_valid(modal_base):
		return Result.failure("实例化 ReserveCardSelectionModal(base) 失败")
	_bind_modal_nodes(modal_base)
	if modal_base.has_method("_ready"):
		modal_base.call("_ready")
	if not modal_base.has_method("setup"):
		_safe_free(modal_base)
		return Result.failure("ReserveCardSelectionModal 缺少 setup")
	modal_base.call("setup", base_state, 0)

	var base_desc0 = modal_base.get("card_desc_0")
	if not (base_desc0 is Label):
		_safe_free(modal_base)
		return Result.failure("base: card_desc_0 无效（节点结构变更）")
	if str((base_desc0 as Label).text).find("起始现金") < 0:
		_safe_free(modal_base)
		return Result.failure("base: 应展示起始现金字段（Reserve Prices 不启用）")
	_safe_free(modal_base)

	var rp_engine := GameEngine.new()
	var rp_init: Result = rp_engine.initialize(2, 12345, [
		"base_rules",
		"base_products",
		"base_pieces",
		"base_tiles",
		"base_maps",
		"base_employees",
		"base_milestones",
		"base_marketing",
		"reserve_prices",
	])
	if not rp_init.ok:
		return Result.failure("初始化失败(reserve_prices): %s" % rp_init.error)
	var rp_state := rp_engine.get_state()
	if rp_state == null:
		return Result.failure("rp_state 为空")

	var modal_rp = ModalScene.instantiate()
	if modal_rp == null or not is_instance_valid(modal_rp):
		return Result.failure("实例化 ReserveCardSelectionModal(reserve_prices) 失败")
	_bind_modal_nodes(modal_rp)
	if modal_rp.has_method("_ready"):
		modal_rp.call("_ready")
	modal_rp.call("setup", rp_state, 0)

	var rp_desc0 = modal_rp.get("card_desc_0")
	if not (rp_desc0 is Label):
		_safe_free(modal_rp)
		return Result.failure("reserve_prices: card_desc_0 无效（节点结构变更）")
	var rp_text := str((rp_desc0 as Label).text)
	if rp_text.find("基础单价候选") < 0:
		_safe_free(modal_rp)
		return Result.failure("reserve_prices: 应展示基础单价候选字段")
	if rp_text.find("起始现金") >= 0:
		_safe_free(modal_rp)
		return Result.failure("reserve_prices: 不应展示起始现金字段")

	var hint = modal_rp.get("hint_label")
	if hint is Label:
		var h := str((hint as Label).text)
		if h.find("基础单价") < 0 and h.find("首次破产") < 0:
			_safe_free(modal_rp)
			return Result.failure("reserve_prices: hint 应提示基础单价/首次破产规则")

	_safe_free(modal_rp)
	return Result.success({})

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
	modal.set("card_title_0", modal.get_node("Panel/MarginContainer/VBoxContainer/ContentHost/VBoxContainer/CardsRow/CardButton0/Content/VBoxContainer/CardTitle"))
	modal.set("card_title_1", modal.get_node("Panel/MarginContainer/VBoxContainer/ContentHost/VBoxContainer/CardsRow/CardButton1/Content/VBoxContainer/CardTitle"))
	modal.set("card_title_2", modal.get_node("Panel/MarginContainer/VBoxContainer/ContentHost/VBoxContainer/CardsRow/CardButton2/Content/VBoxContainer/CardTitle"))
	modal.set("card_desc_0", modal.get_node("Panel/MarginContainer/VBoxContainer/ContentHost/VBoxContainer/CardsRow/CardButton0/Content/VBoxContainer/CardDesc"))
	modal.set("card_desc_1", modal.get_node("Panel/MarginContainer/VBoxContainer/ContentHost/VBoxContainer/CardsRow/CardButton1/Content/VBoxContainer/CardDesc"))
	modal.set("card_desc_2", modal.get_node("Panel/MarginContainer/VBoxContainer/ContentHost/VBoxContainer/CardsRow/CardButton2/Content/VBoxContainer/CardDesc"))

static func _safe_free(node: Node) -> void:
	if node != null and is_instance_valid(node):
		node.free()

