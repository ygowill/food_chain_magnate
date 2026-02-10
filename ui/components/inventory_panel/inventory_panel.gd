# 库存面板组件
# 显示玩家的食物/饮品库存
class_name InventoryPanel
extends Control

signal product_clicked(product_id: String)

const UiSkinCacheClass = preload("res://ui/visual/ui_skin_cache.gd")
const UiRebuildHelpersClass = preload("res://ui/utils/rebuild_helpers.gd")
const ModulesBaseDirClass = preload("res://ui/utils/modules_base_dir.gd")

@onready var title_label: Label = $MarginContainer/VBoxContainer/TitleLabel
@onready var items_container: GridContainer = $MarginContainer/VBoxContainer/ItemsContainer

var _inventory: Dictionary = {}  # product_id -> count
var _fridge_capacity: int = -1   # -1 表示无冰箱
var _product_items: Dictionary = {}  # product_id -> ProductItem
var _prev_inventory: Dictionary = {}

var _visual_modules: Array[String] = []
var _skin = null

func _ready() -> void:
	_build_ui()

func _build_ui() -> void:
	if items_container != null:
		items_container.columns = 3

func set_visual_modules(modules: Array[String]) -> void:
	_visual_modules = Array(modules, TYPE_STRING, "", null)
	_skin = null
	_ensure_skin()
	_rebuild_items()

func set_inventory(inventory: Dictionary) -> void:
	_prev_inventory = _inventory.duplicate(true)
	_inventory = inventory.duplicate(true)
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
	UiRebuildHelpersClass.free_children(items_container)
	_product_items.clear()

	_ensure_skin()

	# 创建新项
	var sorted_ids: Array = _inventory.keys()
	sorted_ids.sort()

	for product_id in sorted_ids:
		var count: int = int(_inventory.get(product_id, 0))
		if count <= 0:
			continue

		var prev_count: int = int(_prev_inventory.get(product_id, 0))
		var delta: int = count - prev_count

		var item := ProductItem.new()
		item.product_id = str(product_id)
		item.count = count
		item.icon_texture = _get_product_icon_texture(item.product_id)
		item.item_clicked.connect(_on_product_clicked)
		items_container.add_child(item)
		_product_items[str(product_id)] = item
		item.animate_change(delta)

func _update_capacity_display() -> void:
	if not is_instance_valid(title_label):
		return

	if _fridge_capacity < 0:
		title_label.text = "库存（无冰箱）"
	else:
		title_label.text = "库存（冰箱：总量≤%d）" % _fridge_capacity

func _on_product_clicked(product_id: String) -> void:
	product_clicked.emit(product_id)

func apply_font_settings() -> void:
	for pid in _product_items.keys():
		var item = _product_items.get(pid, null)
		if is_instance_valid(item) and item.has_method("apply_font_settings"):
			item.apply_font_settings()

func _ensure_skin() -> void:
	if _skin != null:
		return

	var base_dir := ModulesBaseDirClass.get_base_dir()

	var mods := _visual_modules
	if mods.is_empty() and Globals != null and (Globals.enabled_modules_v2 is Array):
		mods = Array(Globals.enabled_modules_v2, TYPE_STRING, "", null)

	_skin = UiSkinCacheClass.get_skin_for_modules(base_dir, mods, 40)

func _get_product_icon_texture(product_id: String) -> Texture2D:
	_ensure_skin()
	if _skin == null or not _skin.has_method("get_product_icon_texture"):
		return null
	var pid := str(product_id)
	if pid == "cola":
		pid = "soda"
	return _skin.get_product_icon_texture(pid)


# === 内部类：单个产品项 ===
class ProductItem extends PanelContainer:
	signal item_clicked(product_id: String)

	const ProductRegistryClass = preload("res://core/data/product_registry.gd")

	var product_id: String = ""
	var count: int = 0
	var icon_texture: Texture2D = null

	var _icon: TextureRect
	var _count_label: Label
	var _highlighted: bool = false

	func _ready() -> void:
		_build_ui()
		gui_input.connect(_on_gui_input)
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	func _build_ui() -> void:
		custom_minimum_size = Vector2(60, 60)

		var vbox := VBoxContainer.new()
		vbox.alignment = BoxContainer.ALIGNMENT_CENTER
		add_child(vbox)

		# 产品图标
		_icon = TextureRect.new()
		_icon.custom_minimum_size = Vector2(32, 32)
		_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_icon.texture = icon_texture
		vbox.add_child(_icon)

		# 数量标签
		_count_label = Label.new()
		_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(_count_label)

		apply_font_settings()
		_update_display()
		_update_style()

	func apply_font_settings() -> void:
		var fs := 12
		if Globals != null:
			fs = int(Globals.get_scaled_font_size(12))
		if _count_label != null:
			_count_label.add_theme_font_size_override("font_size", fs)

	func _update_display() -> void:
		if _count_label != null:
			var name := _get_product_display_name(product_id)
			_count_label.text = "%s\n×%d" % [name, count]
		if _icon != null:
			_icon.texture = icon_texture

	func _get_product_display_name(pid_in: String) -> String:
		if pid_in.is_empty():
			return ""
		var pid := str(pid_in)
		if pid == "cola":
			pid = "soda"
		if ProductRegistryClass.is_loaded():
			var def_val = ProductRegistryClass.get_def(pid)
			if def_val != null and (def_val is ProductDef):
				var def: ProductDef = def_val
				if not def.name.is_empty():
					return def.name
		return pid

	func set_highlighted(highlighted: bool) -> void:
		_highlighted = highlighted
		_update_style()

	func animate_change(delta: int) -> void:
		if delta == 0:
			return
		if OS.has_feature("headless"):
			return

		var pulse := Color(0.6, 1.0, 0.6, 1) if delta > 0 else Color(1.0, 0.6, 0.6, 1)
		var tween := create_tween()
		tween.tween_property(self, "modulate", pulse, 0.08)
		tween.tween_property(self, "modulate", Color(1, 1, 1, 1), 0.25)

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
