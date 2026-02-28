# 晚餐时间覆盖层组件
# 显示顾客需求匹配和订单处理流程
class_name DinnerTimeOverlay
extends Control

signal order_confirmed(restaurant_id: String, house_id: String, products: Dictionary)
signal phase_completed()

const UiSkinCacheClass = preload("res://ui/visual/ui_skin_cache.gd")
const ModulesBaseDirClass = preload("res://ui/utils/modules_base_dir.gd")
const UiStylesClass = preload("res://ui/utils/ui_styles.gd")

@onready var title_label: Label = $Layout/TopBarMargin/TopBar/TitleLabel
@onready var progress_label: Label = $Layout/TopBarMargin/TopBar/ProgressLabel
@onready var header_label: Label = $Layout/CenterMargin/CenterPanel/MarginContainer/VBoxContainer/HeaderLabel
@onready var orders_container: VBoxContainer = $Layout/CenterMargin/CenterPanel/MarginContainer/VBoxContainer/ScrollContainer/OrdersContainer
@onready var next_btn: Button = $Layout/BottomBarMargin/BottomBar/NextButton
@onready var auto_btn: Button = $Layout/BottomBarMargin/BottomBar/AutoButton
@onready var center_margin: MarginContainer = $Layout/CenterMargin
@onready var _center_panel: PanelContainer = $Layout/CenterMargin/CenterPanel

var _pending_orders: Array[Dictionary] = []  # [{house_id, demands, matched_restaurant, products}]
var _completed_orders: Array[Dictionary] = []
var _current_order_idx: int = 0
var _order_items: Array[OrderItem] = []

var _auto_mode: bool = false
var _visual_modules: Array[String] = []
var _skin = null
var _summary_data: Dictionary = {}
var _summary_shown: bool = false

func _ready() -> void:
	if next_btn != null:
		next_btn.pressed.connect(_on_next_pressed)
	if auto_btn != null:
		auto_btn.pressed.connect(_on_auto_pressed)

	# 应用对话框表面样式
	if _center_panel != null:
		UiStylesClass.apply_dialog_surface(_center_panel)

	if header_label != null:
		UiStylesClass.apply_label_dark(header_label)

	if next_btn != null:
		UiStylesClass.apply_button_primary(next_btn)
	if auto_btn != null:
		UiStylesClass.apply_button_secondary(auto_btn)

	resized.connect(_on_overlay_resized)
	_update_responsive_margins()

	visible = false

func set_pending_orders(orders: Array[Dictionary]) -> void:
	_pending_orders = orders.duplicate(true)
	_completed_orders.clear()
	_current_order_idx = 0
	_rebuild_order_list()
	_update_progress()

func set_summary_data(dt: Dictionary) -> void:
	_summary_data = dt

static func build_orders_from_settlement(dt: Dictionary) -> Array[Dictionary]:
	var orders: Array[Dictionary] = []
	var sales_val = dt.get("sales", [])
	var sales_arr: Array = sales_val if sales_val is Array else []
	for i in range(sales_arr.size()):
		var sale = sales_arr[i]
		if not (sale is Dictionary):
			continue
		var req: Dictionary = sale.get("required", {})
		var house_id := str(sale.get("house_id", ""))
		var house_number_val = sale.get("house_number", house_id)
		orders.append({
			"house_id": house_id,
			"house_number": str(house_number_val),
			"demands": req,
			"matched_restaurant": str(sale.get("winner_restaurant_id", "")),
			"products": req,
			"revenue": int(sale.get("revenue", 0)),
			"distance": int(sale.get("distance", 0)),
			"steps": int(sale.get("steps", 0)),
			"score": int(sale.get("score", 0)),
			"unit_price": int(sale.get("unit_price", 0)),
			"decision_unit_price": int(sale.get("decision_unit_price", sale.get("unit_price", 0))),
			"quantity": int(sale.get("quantity", 0)),
			"has_garden": bool(sale.get("has_garden", false)),
			"price_part": int(sale.get("price_part", 0)),
			"bonus": int(sale.get("bonus", 0)),
			"house_bonus": int(sale.get("house_bonus", 0)),
			"demand_variant_id": str(sale.get("demand_variant_id", "")),
			"winner_owner": int(sale.get("winner_owner", -1)),
			"sale_index": i,
			"is_skipped": false,
		})
	for skip in dt.get("skipped", []):
		if not (skip is Dictionary):
			continue
		var house_id := str(skip.get("house_id", ""))
		var house_number_val = skip.get("house_number", house_id)
		orders.append({
			"house_id": house_id,
			"house_number": str(house_number_val),
			"demands": skip.get("required", {}),
			"matched_restaurant": "",
			"products": {},
			"revenue": 0,
			"distance": 0,
			"steps": 0,
			"score": 0,
			"winner_owner": -1,
			"demand_cards": int(skip.get("demands", 0)),
			"has_garden": bool(skip.get("has_garden", false)),
			"is_apartment": bool(skip.get("is_apartment", false)),
			"demand_variant_id": "",
			"is_skipped": true,
		})
	orders.sort_custom(func(a, b):
		var an: int = _parse_house_number(a.get("house_number", ""))
		var bn: int = _parse_house_number(b.get("house_number", ""))
		if an != bn:
			return an < bn
		return str(a.get("house_id", "")) < str(b.get("house_id", ""))
	)
	return orders

static func _parse_house_number(value) -> int:
	if value is int:
		return int(value)
	if value is float:
		var f: float = float(value)
		if f == floor(f):
			return int(f)
	if value is String:
		var s: String = str(value)
		if s.is_valid_int():
			return s.to_int()
	return 999999

func set_visual_modules(modules: Array[String]) -> void:
	_visual_modules = Array(modules, TYPE_STRING, "", null)
	_skin = null
	_ensure_skin()
	_update_item_skins()

func show_overlay() -> void:
	visible = true
	_update_responsive_margins()
	_rebuild_order_list()

func hide_overlay() -> void:
	visible = false

func _on_overlay_resized() -> void:
	_update_responsive_margins()

func _update_responsive_margins() -> void:
	if center_margin == null:
		return

	var viewport_w := int(get_viewport_rect().size.x)
	var min_margin := 12
	var desired_panel_w := 480

	var margin_lr := min_margin
	if viewport_w > 0:
		var max_panel_w := viewport_w - (min_margin * 2)
		var target_panel_w := mini(desired_panel_w, maxi(0, max_panel_w))
		if target_panel_w > 0:
			margin_lr = maxi(min_margin, int(round(float(viewport_w - target_panel_w) * 0.5)))
		margin_lr = mini(margin_lr, int(floor(float(viewport_w) * 0.5)))

	center_margin.add_theme_constant_override("margin_left", margin_lr)
	center_margin.add_theme_constant_override("margin_right", margin_lr)

func _rebuild_order_list() -> void:
	# 清除旧项
	for item in _order_items:
		if is_instance_valid(item):
			item.queue_free()
	_order_items.clear()

	if orders_container == null:
		return

	_ensure_skin()

	for i in range(_pending_orders.size()):
		var order: Dictionary = _pending_orders[i]

		var item := OrderItem.new()
		item.order_index = i
		item.order_data = order
		item.is_current = (i == _current_order_idx)
		item.is_completed = (i < _current_order_idx)
		item.skin = _skin
		item.order_selected.connect(_on_order_selected)
		orders_container.add_child(item)
		_order_items.append(item)

func _update_progress() -> void:
	if progress_label != null:
		var completed := _current_order_idx
		var total := _pending_orders.size()
		progress_label.text = "进度: %d / %d" % [completed, total]

	# 更新订单项状态
	for i in range(_order_items.size()):
		var item: OrderItem = _order_items[i]
		if is_instance_valid(item):
			item.is_current = (i == _current_order_idx)
			item.is_completed = (i < _current_order_idx)
			item.update_display()

	# 汇总：所有订单展示完后显示收入汇总
	if _current_order_idx >= _pending_orders.size() and orders_container != null:
		_show_summary()

	# 更新按钮状态
	if next_btn != null:
		if _current_order_idx >= _pending_orders.size():
			next_btn.text = "确认结算"
		else:
			next_btn.text = "下一个"

func _on_order_selected(index: int) -> void:
	if index < _current_order_idx:
		return  # 不能选择已完成的订单

	_current_order_idx = index
	_update_progress()

func _on_next_pressed() -> void:
	if _current_order_idx >= _pending_orders.size():
		# 全部完成
		phase_completed.emit()
		hide_overlay()
		return

	var order: Dictionary = _pending_orders[_current_order_idx]
	var restaurant_id: String = str(order.get("matched_restaurant", ""))
	var house_id: String = str(order.get("house_id", ""))
	var products: Dictionary = order.get("products", {})

	order_confirmed.emit(restaurant_id, house_id, products)

	_completed_orders.append(order)
	_current_order_idx += 1
	_update_progress()

	# 自动模式下继续处理
	if _auto_mode and _current_order_idx < _pending_orders.size():
		await get_tree().create_timer(0.3).timeout
		_on_next_pressed()

func _show_summary() -> void:
	if _summary_shown or orders_container == null:
		return
	_summary_shown = true

	var sep := HSeparator.new()
	orders_container.add_child(sep)

	var total_income: Array = _summary_data.get("total_income", [])
	var income_tips: Array = _summary_data.get("income_tips", [])
	var income_cfo: Array = _summary_data.get("income_cfo_bonus", [])

	var lbl := Label.new()
	lbl.add_theme_font_size_override("font_size", 14)
	UiStylesClass.apply_label_dark(lbl)
	var lines := "--- 本轮收入汇总 ---"
	for pid in range(total_income.size()):
		var total_val := int(total_income[pid])
		var tips_val := int(income_tips[pid]) if pid < income_tips.size() else 0
		var cfo_val := int(income_cfo[pid]) if pid < income_cfo.size() else 0
		if total_val <= 0 and tips_val <= 0:
			continue
		var line := "\n玩家 %d: $%d" % [pid, total_val]
		if tips_val > 0:
			line += " (小费 $%d)" % tips_val
		if cfo_val > 0:
			line += " (CFO +$%d)" % cfo_val
		lines += line
	lbl.text = lines
	orders_container.add_child(lbl)

func _on_auto_pressed() -> void:
	_auto_mode = not _auto_mode
	if auto_btn != null:
		auto_btn.text = "自动: 开" if _auto_mode else "自动: 关"

	if _auto_mode:
		_on_next_pressed()

func _ensure_skin() -> void:
	if _skin != null:
		return

	var base_dir := ModulesBaseDirClass.get_base_dir()

	var mods := _visual_modules
	if mods.is_empty() and Globals != null and (Globals.enabled_modules_v2 is Array):
		mods = Array(Globals.enabled_modules_v2, TYPE_STRING, "", null)

	_skin = UiSkinCacheClass.get_skin_for_modules(base_dir, mods, 40)

func _update_item_skins() -> void:
	for item in _order_items:
		if not is_instance_valid(item):
			continue
		item.skin = _skin
		item.update_display()


# === 内部类：订单项 ===
class OrderItem extends PanelContainer:
	signal order_selected(index: int)

	var order_index: int = 0
	var order_data: Dictionary = {}
	var is_current: bool = false
	var is_completed: bool = false
	var skin = null

	var _house_label: Label
	var _restaurant_label: Label
	var _details_label: Label
	var _status_icon: Label
	var _demands_container: HBoxContainer
	var _products_container: HBoxContainer

	func _ready() -> void:
		_build_ui()

	func _build_ui() -> void:
		custom_minimum_size = Vector2(400, 60)
		mouse_filter = Control.MOUSE_FILTER_STOP

		var hbox := HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 12)
		add_child(hbox)

		# 状态图标
		_status_icon = Label.new()
		_status_icon.custom_minimum_size = Vector2(24, 24)
		_status_icon.add_theme_font_size_override("font_size", 16)
		_status_icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_status_icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		hbox.add_child(_status_icon)

		# 信息区
		var info_box := VBoxContainer.new()
		info_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info_box.add_theme_constant_override("separation", 2)
		hbox.add_child(info_box)

		# 房屋信息 + 需求图标
		var house_row := HBoxContainer.new()
		house_row.add_theme_constant_override("separation", 6)
		info_box.add_child(house_row)

		_house_label = Label.new()
		_house_label.add_theme_font_size_override("font_size", 14)
		UiStylesClass.apply_label_dark(_house_label)
		house_row.add_child(_house_label)

		_demands_container = HBoxContainer.new()
		_demands_container.add_theme_constant_override("separation", 2)
		_demands_container.alignment = BoxContainer.ALIGNMENT_BEGIN
		house_row.add_child(_demands_container)

		# 餐厅信息
		_restaurant_label = Label.new()
		_restaurant_label.add_theme_font_size_override("font_size", 12)
		_restaurant_label.autowrap_mode = TextServer.AUTOWRAP_WORD
		UiStylesClass.apply_label_dark(_restaurant_label)
		info_box.add_child(_restaurant_label)

		# 明细信息（价格/距离等）
		_details_label = Label.new()
		_details_label.add_theme_font_size_override("font_size", 11)
		_details_label.autowrap_mode = TextServer.AUTOWRAP_WORD
		UiStylesClass.apply_label_hint_dark(_details_label)
		info_box.add_child(_details_label)

		# 产品列表（实际售出）
		_products_container = HBoxContainer.new()
		_products_container.add_theme_constant_override("separation", 2)
		_products_container.alignment = BoxContainer.ALIGNMENT_CENTER
		hbox.add_child(_products_container)

		update_display()
		_update_style()

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton:
			if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
				if not is_completed:
					order_selected.emit(order_index)

	func update_display() -> void:
		var house_id: String = str(order_data.get("house_id", ""))
		var house_number: String = str(order_data.get("house_number", house_id))
		var restaurant_id: String = str(order_data.get("matched_restaurant", ""))
		var products: Dictionary = order_data.get("products", {})
		var demands: Dictionary = order_data.get("demands", {})
		var is_skipped: bool = bool(order_data.get("is_skipped", false))
		var winner_owner: int = int(order_data.get("winner_owner", -1))
		var distance: int = int(order_data.get("distance", 0))
		var steps: int = int(order_data.get("steps", 0))
		var score: int = int(order_data.get("score", 0))
		var unit_price: int = int(order_data.get("unit_price", 0))
		var decision_unit_price: int = int(order_data.get("decision_unit_price", unit_price))
		var quantity: int = int(order_data.get("quantity", 0))
		var has_garden: bool = bool(order_data.get("has_garden", false))
		var is_apartment: bool = bool(order_data.get("is_apartment", false))
		var demand_variant_id: String = str(order_data.get("demand_variant_id", ""))

		if _house_label != null:
			var name := "房屋 %s" % house_number
			if not house_id.is_empty() and house_id != house_number:
				name += " (%s)" % house_id
			var tags: Array[String] = []
			if has_garden:
				tags.append("花园")
			if is_apartment:
				tags.append("公寓")
			if not tags.is_empty():
				name += " · " + " / ".join(tags)
			name += ":"
			_house_label.text = name

		if _demands_container != null:
			for child in _demands_container.get_children():
				child.queue_free()

			var dkeys := demands.keys()
			dkeys.sort()
			for prod_type in dkeys:
				var count: int = int(demands.get(prod_type, 0))
				if count <= 0:
					continue
				_add_product_icon_with_count(_demands_container, str(prod_type), count, 16)

			# 兼容旧存档：skipped 可能缺少 required，仅保留 demands 计数
			if _demands_container.get_child_count() <= 0 and is_skipped:
				var demand_cards: int = int(order_data.get("demand_cards", 0))
				if demand_cards > 0:
					var hint := Label.new()
					hint.add_theme_font_size_override("font_size", 12)
					UiStylesClass.apply_label_hint_dark(hint)
					hint.text = "(需求×%d)" % demand_cards
					_demands_container.add_child(hint)

		var revenue: int = int(order_data.get("revenue", 0))

		if _restaurant_label != null:
			if is_skipped or restaurant_id.is_empty():
				_restaurant_label.text = "无餐厅满足需求"
				UiStylesClass.apply_label_error(_restaurant_label)
			else:
				var owner_txt := ("玩家 %d" % (winner_owner + 1)) if winner_owner >= 0 else "未知玩家"
				var info := "餐厅: %s · %s" % [restaurant_id, owner_txt]
				_restaurant_label.text = info
				UiStylesClass.apply_label_dark(_restaurant_label)

		if _details_label != null:
			if is_skipped or restaurant_id.is_empty():
				var demand_cards: int = int(order_data.get("demand_cards", 0))
				var detail := ""
				if demand_cards > 0:
					detail = "需求卡: %d" % demand_cards
				if not detail.is_empty():
					_details_label.text = detail
				else:
					_details_label.text = ""
			else:
				var parts: Array[String] = []
				if demand_variant_id != "" and demand_variant_id != "base":
					parts.append("变体:%s" % demand_variant_id)
				parts.append("距离:%d(步:%d)" % [distance, steps])
				parts.append("得分:%d" % score)
				parts.append("单价:$%d(判定:$%d) ×%d" % [unit_price, decision_unit_price, quantity])
				parts.append("收入:$%d (单价部分:$%d + 奖励:$%d)" % [revenue, int(order_data.get("price_part", 0)), int(order_data.get("bonus", 0))])
				var house_bonus: int = int(order_data.get("house_bonus", 0))
				if house_bonus != 0:
					parts.append("房屋奖金:$%d" % house_bonus)
				_details_label.text = " · ".join(parts)

		if _products_container != null:
			for child in _products_container.get_children():
				child.queue_free()

			var pkeys := products.keys()
			pkeys.sort()
			for prod_type in pkeys:
				var count: int = int(products.get(prod_type, 0))
				if count <= 0:
					continue
				_add_product_icon_with_count(_products_container, str(prod_type), count, 16)

			if _products_container.get_child_count() <= 0:
				var dash := Label.new()
				dash.add_theme_font_size_override("font_size", 14)
				UiStylesClass.apply_label_hint_dark(dash)
				dash.text = "-"
				_products_container.add_child(dash)

		if _status_icon != null:
			if is_completed:
				_status_icon.text = "✓"
				_status_icon.add_theme_color_override("font_color", Color(0.28, 0.55, 0.22, 1))
			elif is_current:
				_status_icon.text = "→"
				_status_icon.add_theme_color_override("font_color", Color(0.73, 0.23, 0.18, 0.8))
			else:
				_status_icon.text = "○"
				_status_icon.add_theme_color_override("font_color", Color(0.5, 0.45, 0.35, 1))

		_update_style()

	func _add_product_icon_with_count(parent: HBoxContainer, product_id: String, count: int, size_px: int) -> void:
		if parent == null:
			return

		var pid := str(product_id)
		if pid == "cola":
			pid = "soda"

		var tex: Texture2D = null
		if skin != null and skin.has_method("get_product_icon_texture"):
			tex = skin.get_product_icon_texture(pid)

		var slot := Control.new()
		slot.custom_minimum_size = Vector2(float(size_px), float(size_px))
		slot.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		parent.add_child(slot)

		var icon_rect := TextureRect.new()
		icon_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_rect.texture = tex
		icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(icon_rect)

		if count > 1:
			var count_label := Label.new()
			count_label.add_theme_font_size_override("font_size", 14)
			UiStylesClass.apply_label_dark(count_label)
			count_label.text = "×%d" % count
			parent.add_child(count_label)

	func _update_style() -> void:
		var is_skipped: bool = bool(order_data.get("is_skipped", false))
		var style := StyleBoxFlat.new()
		if is_completed:
			style.bg_color = Color(0.95, 0.91, 0.82, 0.9)
		elif is_current:
			style.bg_color = Color(0.92, 0.88, 0.78, 0.95)
			style.border_color = Color(0.8, 0.7, 0.3, 0.7)
			style.set_border_width_all(2)
		elif is_skipped:
			style.bg_color = Color(0.97, 0.92, 0.90, 0.9)
			style.border_color = Color(0.73, 0.23, 0.18, 0.35)
			style.set_border_width_all(1)
		else:
			style.bg_color = Color(0.95, 0.91, 0.82, 0.85)
		style.set_corner_radius_all(6)
		add_theme_stylebox_override("panel", style)
