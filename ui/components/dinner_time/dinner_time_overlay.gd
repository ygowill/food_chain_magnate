# 晚餐时间覆盖层组件
# 显示顾客需求匹配和订单处理流程
class_name DinnerTimeOverlay
extends Control

signal order_confirmed(restaurant_id: String, house_id: String, products: Dictionary)
signal phase_completed()

@onready var title_label: Label = $TopBar/TitleLabel
@onready var progress_label: Label = $TopBar/ProgressLabel
@onready var orders_container: VBoxContainer = $CenterPanel/MarginContainer/VBoxContainer/ScrollContainer/OrdersContainer
@onready var next_btn: Button = $BottomBar/NextButton
@onready var auto_btn: Button = $BottomBar/AutoButton

var _pending_orders: Array[Dictionary] = []  # [{house_id, demands, matched_restaurant, products}]
var _completed_orders: Array[Dictionary] = []
var _current_order_idx: int = 0
var _order_items: Array[OrderItem] = []

var _auto_mode: bool = false

func _ready() -> void:
	if next_btn != null:
		next_btn.pressed.connect(_on_next_pressed)
	if auto_btn != null:
		auto_btn.pressed.connect(_on_auto_pressed)

	visible = false

func set_pending_orders(orders: Array[Dictionary]) -> void:
	_pending_orders = orders.duplicate(true)
	_completed_orders.clear()
	_current_order_idx = 0
	_rebuild_order_list()
	_update_progress()

func show_overlay() -> void:
	visible = true
	_rebuild_order_list()

func hide_overlay() -> void:
	visible = false

func _rebuild_order_list() -> void:
	# 清除旧项
	for item in _order_items:
		if is_instance_valid(item):
			item.queue_free()
	_order_items.clear()

	if orders_container == null:
		return

	for i in range(_pending_orders.size()):
		var order: Dictionary = _pending_orders[i]

		var item := OrderItem.new()
		item.order_index = i
		item.order_data = order
		item.is_current = (i == _current_order_idx)
		item.is_completed = (i < _current_order_idx)
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

	# 更新按钮状态
	if next_btn != null:
		if _current_order_idx >= _pending_orders.size():
			next_btn.text = "完成"
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

func _on_auto_pressed() -> void:
	_auto_mode = not _auto_mode
	if auto_btn != null:
		auto_btn.text = "自动: 开" if _auto_mode else "自动: 关"

	if _auto_mode:
		_on_next_pressed()


# === 内部类：订单项 ===
class OrderItem extends PanelContainer:
	signal order_selected(index: int)

	var order_index: int = 0
	var order_data: Dictionary = {}
	var is_current: bool = false
	var is_completed: bool = false

	var _house_label: Label
	var _restaurant_label: Label
	var _products_label: Label
	var _status_icon: Label

	const PRODUCT_ICONS: Dictionary = {
		"burger": "🍔",
		"pizza": "🍕",
		"drink": "🥤",
		"lemonade": "🍋",
		"beer": "🍺",
	}

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

		# 房屋信息
		_house_label = Label.new()
		_house_label.add_theme_font_size_override("font_size", 14)
		info_box.add_child(_house_label)

		# 餐厅信息
		_restaurant_label = Label.new()
		_restaurant_label.add_theme_font_size_override("font_size", 12)
		_restaurant_label.add_theme_color_override("font_color", Color(0.6, 0.7, 0.8, 1))
		info_box.add_child(_restaurant_label)

		# 产品列表
		_products_label = Label.new()
		_products_label.add_theme_font_size_override("font_size", 14)
		hbox.add_child(_products_label)

		update_display()
		_update_style()

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton:
			if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
				if not is_completed:
					order_selected.emit(order_index)

	func update_display() -> void:
		var house_id: String = str(order_data.get("house_id", ""))
		var restaurant_id: String = str(order_data.get("matched_restaurant", ""))
		var products: Dictionary = order_data.get("products", {})
		var demands: Dictionary = order_data.get("demands", {})

		if _house_label != null:
			var demand_str := ""
			for prod_type in demands.keys():
				var count: int = int(demands[prod_type])
				var icon: String = PRODUCT_ICONS.get(prod_type, "?")
				demand_str += "%s×%d " % [icon, count]
			_house_label.text = "房屋 %s: %s" % [house_id, demand_str]

		if _restaurant_label != null:
			if restaurant_id.is_empty():
				_restaurant_label.text = "未匹配餐厅"
				_restaurant_label.add_theme_color_override("font_color", Color(0.8, 0.5, 0.5, 1))
			else:
				_restaurant_label.text = "餐厅: %s" % restaurant_id

		if _products_label != null:
			var prod_str := ""
			for prod_type in products.keys():
				var count: int = int(products[prod_type])
				var icon: String = PRODUCT_ICONS.get(prod_type, "?")
				prod_str += "%s×%d " % [icon, count]
			_products_label.text = prod_str if not prod_str.is_empty() else "-"

		if _status_icon != null:
			if is_completed:
				_status_icon.text = "✓"
				_status_icon.add_theme_color_override("font_color", Color(0.5, 0.8, 0.5, 1))
			elif is_current:
				_status_icon.text = "→"
				_status_icon.add_theme_color_override("font_color", Color(0.9, 0.8, 0.4, 1))
			else:
				_status_icon.text = "○"
				_status_icon.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 1))

		_update_style()

	func _update_style() -> void:
		var style := StyleBoxFlat.new()
		if is_completed:
			style.bg_color = Color(0.15, 0.2, 0.15, 0.7)
		elif is_current:
			style.bg_color = Color(0.2, 0.22, 0.18, 0.9)
			style.border_color = Color(0.8, 0.7, 0.3, 0.7)
			style.set_border_width_all(2)
		else:
			style.bg_color = Color(0.15, 0.17, 0.2, 0.8)
		style.set_corner_radius_all(6)
		add_theme_stylebox_override("panel", style)
