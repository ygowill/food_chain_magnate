class_name RuralMarketeersGiantBillboardOverlay
extends Control

signal placement_confirmed(side: String, product: String)
signal ui_state_changed()

const ActionPanelContextScenePath := "res://modules/rural_marketeers/ui/components/giant_billboard/action_panel_giant_billboard_context.gd"

var _available_sides: Array[String] = []
var _available_products: Array[String] = []
var _selected_side: String = ""
var _selected_product: String = ""

var _validation_ok: bool = true
var _validation_message: String = ""

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func set_available_sides(sides: Array[String]) -> void:
	var out: Array[String] = []
	var seen := {}
	for v in sides:
		var s := str(v).strip_edges()
		if s.is_empty() or seen.has(s):
			continue
		seen[s] = true
		out.append(s)
	_available_sides = out
	if _selected_side.is_empty() or not _available_sides.has(_selected_side):
		_selected_side = _available_sides[0] if not _available_sides.is_empty() else ""
	ui_state_changed.emit()

func get_available_sides() -> Array[String]:
	return _available_sides.duplicate()

func set_selected_side(side: String) -> void:
	var s := str(side).strip_edges()
	if s.is_empty() or not _available_sides.has(s):
		return
	_selected_side = s
	ui_state_changed.emit()

func get_selected_side() -> String:
	return _selected_side

func set_available_products(products: Array[String]) -> void:
	var out: Array[String] = []
	var seen := {}
	for v in products:
		var p := str(v).strip_edges()
		if p.is_empty() or seen.has(p):
			continue
		seen[p] = true
		out.append(p)
	out.sort()
	_available_products = out
	if _selected_product.is_empty() or not _available_products.has(_selected_product):
		_selected_product = _available_products[0] if not _available_products.is_empty() else ""
	ui_state_changed.emit()

func get_available_products() -> Array[String]:
	return _available_products.duplicate()

func set_selected_product(product: String) -> void:
	var p := str(product).strip_edges()
	if p.is_empty() or not _available_products.has(p):
		return
	_selected_product = p
	ui_state_changed.emit()

func get_selected_product() -> String:
	return _selected_product

func set_validation(valid: bool, message: String = "") -> void:
	_validation_ok = bool(valid)
	_validation_message = str(message).strip_edges()
	ui_state_changed.emit()

func can_confirm() -> bool:
	return _validation_ok and (not _selected_side.is_empty()) and (not _selected_product.is_empty())

func request_confirm() -> void:
	if not can_confirm():
		return
	placement_confirmed.emit(_selected_side, _selected_product)

func request_cancel() -> void:
	visible = false
	ui_state_changed.emit()

func get_hint_text() -> String:
	if not _validation_ok and not _validation_message.is_empty():
		return "无法放置：%s" % _validation_message
	return "选择方向与产品后确认：放置后乡村营销员将永久忙碌"

func get_action_panel_context_spec() -> Dictionary:
	return {
		"title": "📣 放置巨型广告牌",
		"hint": get_hint_text(),
		"confirm_text": "确认放置",
		"cancel_text": "取消",
		"custom_scene": ActionPanelContextScenePath,
	}

