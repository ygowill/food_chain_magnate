# 库存面板组件
# 显示玩家的食物/饮品库存
class_name InventoryPanel
extends Control

signal product_clicked(product_id: String)

@onready var items_container: GridContainer = $MarginContainer/VBoxContainer/ItemsContainer

var _inventory: Dictionary = {}  # product_id -> count
var _fridge_capacity: int = -1   # -1 表示无冰箱
var _product_items: Dictionary = {}  # product_id -> ProductItem

func _ready() -> void:
	_build_ui()

func _build_ui() -> void:
	if items_container != null:
		items_container.columns = 3

func set_inventory(inventory: Dictionary) -> void:
	_inventory = inventory.duplicate()
	_rebuild_items()

func set_fridge_capacity(capacity: int) -> void:
	_fridge_capacity = capacity
	_update_capacity_display()

func highlight_product(product_id: String) -> void:
	for pid in _product_items.keys():
		var item: ProductItem = _product_items[pid]
		if is_instance_valid(item):
			item.set_highlighted(pid == product_id)

func _rebuild_items() -> void:
	# 清除旧项
	for child in items_container.get_children():
		child.queue_free()
	_product_items.clear()

	# 创建新项
	var sorted_ids: Array = _inventory.keys()
	sorted_ids.sort()

	for product_id in sorted_ids:
		var count: int = int(_inventory.get(product_id, 0))
		if count <= 0:
			continue

		var item := ProductItem.new()
		item.product_id = str(product_id)
		item.count = count
		item.item_clicked.connect(_on_product_clicked)
		items_container.add_child(item)
		_product_items[str(product_id)] = item

func _update_capacity_display() -> void:
	# TODO: 显示冰箱容量限制
	pass

func _on_product_clicked(product_id: String) -> void:
	product_clicked.emit(product_id)


# === 内部类：单个产品项 ===
class ProductItem extends PanelContainer:
	signal item_clicked(product_id: String)

	var product_id: String = ""
	var count: int = 0

	var _icon: TextureRect
	var _count_label: Label
	var _highlighted: bool = false

	# 产品显示名称映射
	const PRODUCT_NAMES: Dictionary = {
		"burger": "汉堡",
		"pizza": "披萨",
		"cola": "可乐",
		"lemonade": "柠檬水",
		"beer": "啤酒",
	}

	# 产品颜色映射
	const PRODUCT_COLORS: Dictionary = {
		"burger": Color(0.8, 0.6, 0.3, 1),
		"pizza": Color(0.9, 0.5, 0.3, 1),
		"cola": Color(0.3, 0.3, 0.8, 1),
		"lemonade": Color(0.9, 0.9, 0.3, 1),
		"beer": Color(0.7, 0.5, 0.2, 1),
	}

	func _ready() -> void:
		_build_ui()
		gui_input.connect(_on_gui_input)
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	func _build_ui() -> void:
		custom_minimum_size = Vector2(60, 60)

		var vbox := VBoxContainer.new()
		vbox.alignment = BoxContainer.ALIGNMENT_CENTER
		add_child(vbox)

		# 图标（用颜色方块代替）
		_icon = TextureRect.new()
		_icon.custom_minimum_size = Vector2(32, 32)
		_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		vbox.add_child(_icon)

		# 颜色指示
		var color_rect := ColorRect.new()
		color_rect.custom_minimum_size = Vector2(32, 32)
		color_rect.color = PRODUCT_COLORS.get(product_id, Color(0.5, 0.5, 0.5, 1))
		vbox.add_child(color_rect)

		# 数量标签
		_count_label = Label.new()
		_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_count_label.add_theme_font_size_override("font_size", 14)
		vbox.add_child(_count_label)

		_update_display()
		_update_style()

	func _update_display() -> void:
		if _count_label != null:
			var name: String = PRODUCT_NAMES.get(product_id, product_id)
			_count_label.text = "%s x%d" % [name, count]

	func set_highlighted(highlighted: bool) -> void:
		_highlighted = highlighted
		_update_style()

	func _update_style() -> void:
		var style := StyleBoxFlat.new()
		if _highlighted:
			style.bg_color = Color(0.4, 0.6, 0.3, 0.6)
			style.border_color = Color(0.6, 0.8, 0.4, 0.8)
			style.set_border_width_all(2)
		else:
			style.bg_color = Color(0.2, 0.22, 0.25, 0.8)
		style.set_corner_radius_all(4)
		add_theme_stylebox_override("panel", style)

	func _on_gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton:
			var e: InputEventMouseButton = event
			if e.button_index == MOUSE_BUTTON_LEFT and e.pressed:
				item_clicked.emit(product_id)
