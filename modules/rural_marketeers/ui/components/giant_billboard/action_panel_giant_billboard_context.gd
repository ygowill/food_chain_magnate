extends VBoxContainer

const ProductRegistryClass = preload("res://core/data/product_registry.gd")
const UiStylesClass = preload("res://ui/utils/ui_styles.gd")

var _overlay: Node = null
var _syncing: bool = false

var _side_label: Label = null
var _side_option: OptionButton = null
var _product_label: Label = null
var _product_option: OptionButton = null

func _ready() -> void:
	_build_ui()

func bind_overlay(overlay: Node) -> void:
	_overlay = overlay
	sync_from_overlay()

func sync_from_overlay() -> void:
	if _overlay == null or not is_instance_valid(_overlay):
		return
	if _side_option == null or _product_option == null:
		return

	_syncing = true
	_rebuild_side_options()
	_rebuild_product_options()
	_syncing = false

func _build_ui() -> void:
	if _side_option != null:
		return

	size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var side_row := HBoxContainer.new()
	side_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(side_row)

	_side_label = Label.new()
	_side_label.text = "方向"
	_side_label.size_flags_horizontal = Control.SIZE_FILL
	UiStylesClass.apply_label_dark(_side_label)
	side_row.add_child(_side_label)

	_side_option = OptionButton.new()
	_side_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiStylesClass.apply_option_button_field(_side_option)
	side_row.add_child(_side_option)
	if not _side_option.item_selected.is_connected(_on_side_selected):
		_side_option.item_selected.connect(_on_side_selected)

	var product_row := HBoxContainer.new()
	product_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(product_row)

	_product_label = Label.new()
	_product_label.text = "产品"
	_product_label.size_flags_horizontal = Control.SIZE_FILL
	UiStylesClass.apply_label_dark(_product_label)
	product_row.add_child(_product_label)

	_product_option = OptionButton.new()
	_product_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiStylesClass.apply_option_button_field(_product_option)
	product_row.add_child(_product_option)
	if not _product_option.item_selected.is_connected(_on_product_selected):
		_product_option.item_selected.connect(_on_product_selected)

func _rebuild_side_options() -> void:
	var sides: Array[String] = []
	var selected := ""

	if _overlay.has_method("get_available_sides"):
		var v = _overlay.call("get_available_sides")
		if v is Array:
			for x in Array(v):
				var s := str(x).strip_edges()
				if not s.is_empty():
					sides.append(s)
	if _overlay.has_method("get_selected_side"):
		selected = str(_overlay.call("get_selected_side")).strip_edges()

	_side_option.clear()
	for i in range(sides.size()):
		var side := sides[i]
		_side_option.add_item(_format_side(side))
		_side_option.set_item_metadata(i, side)

	# Selection
	var selected_index := 0
	for i in range(_side_option.get_item_count()):
		if str(_side_option.get_item_metadata(i)) == selected:
			selected_index = i
			break
	if _side_option.get_item_count() > 0:
		_side_option.select(selected_index)

func _rebuild_product_options() -> void:
	var products: Array[String] = []
	var selected := ""

	if _overlay.has_method("get_available_products"):
		var v = _overlay.call("get_available_products")
		if v is Array:
			for x in Array(v):
				var s := str(x).strip_edges()
				if not s.is_empty():
					products.append(s)
	if _overlay.has_method("get_selected_product"):
		selected = str(_overlay.call("get_selected_product")).strip_edges()

	_product_option.clear()
	for i in range(products.size()):
		var pid := products[i]
		_product_option.add_item(_format_product(pid))
		_product_option.set_item_metadata(i, pid)

	# Selection
	var selected_index := 0
	for i in range(_product_option.get_item_count()):
		if str(_product_option.get_item_metadata(i)) == selected:
			selected_index = i
			break
	if _product_option.get_item_count() > 0:
		_product_option.select(selected_index)

func _on_side_selected(index: int) -> void:
	if _syncing:
		return
	if _overlay == null or not is_instance_valid(_overlay):
		return
	if not _overlay.has_method("set_selected_side"):
		return
	var side := str(_side_option.get_item_metadata(index)).strip_edges()
	_overlay.call("set_selected_side", side)

func _on_product_selected(index: int) -> void:
	if _syncing:
		return
	if _overlay == null or not is_instance_valid(_overlay):
		return
	if not _overlay.has_method("set_selected_product"):
		return
	var pid := str(_product_option.get_item_metadata(index)).strip_edges()
	_overlay.call("set_selected_product", pid)

func _format_side(side: String) -> String:
	var s := str(side).strip_edges()
	if s == "N":
		return "北 (N)"
	if s == "E":
		return "东 (E)"
	if s == "S":
		return "南 (S)"
	if s == "W":
		return "西 (W)"
	return s

func _format_product(product_id: String) -> String:
	var pid := str(product_id).strip_edges()
	var name := pid
	if not pid.is_empty() and ProductRegistryClass.is_loaded():
		var def_val = ProductRegistryClass.get_def(pid)
		if def_val is ProductDef:
			name = str((def_val as ProductDef).name).strip_edges()
	return "%s (%s)" % [name if not name.is_empty() else pid, pid]
