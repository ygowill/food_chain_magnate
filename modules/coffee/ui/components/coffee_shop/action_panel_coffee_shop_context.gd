extends VBoxContainer

var _overlay: Node = null
var _syncing: bool = false

var _shop_row: HBoxContainer = null
var _shop_label: Label = null
var _shop_option: OptionButton = null

func _ready() -> void:
	_build_ui()

func bind_overlay(overlay: Node) -> void:
	_overlay = overlay
	sync_from_overlay()

func sync_from_overlay() -> void:
	if _overlay == null or not is_instance_valid(_overlay):
		return
	if _shop_row == null or _shop_option == null:
		return

	var mode := ""
	if _overlay.has_method("get_mode"):
		mode = str(_overlay.call("get_mode")).strip_edges()

	_shop_row.visible = (mode == "move")
	if not _shop_row.visible:
		return

	_syncing = true
	_rebuild_shop_options()
	_syncing = false

func _build_ui() -> void:
	if _shop_option != null:
		return

	size_flags_horizontal = Control.SIZE_EXPAND_FILL

	_shop_row = HBoxContainer.new()
	_shop_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_shop_row)

	_shop_label = Label.new()
	_shop_label.text = "移动哪一家"
	_shop_label.size_flags_horizontal = Control.SIZE_FILL
	_shop_row.add_child(_shop_label)

	_shop_option = OptionButton.new()
	_shop_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_shop_row.add_child(_shop_option)
	if not _shop_option.item_selected.is_connected(_on_shop_selected):
		_shop_option.item_selected.connect(_on_shop_selected)

func _rebuild_shop_options() -> void:
	if _overlay == null or not is_instance_valid(_overlay):
		return

	var shops: Array[Dictionary] = []
	if _overlay.has_method("get_available_shops"):
		var v = _overlay.call("get_available_shops")
		if v is Array:
			for d in Array(v):
				if d is Dictionary:
					shops.append(Dictionary(d))

	var selected := ""
	if _overlay.has_method("get_selected_from_shop_id"):
		selected = str(_overlay.call("get_selected_from_shop_id")).strip_edges()

	_shop_option.clear()
	for i in range(shops.size()):
		var d: Dictionary = shops[i]
		var sid := str(d.get("shop_id", "")).strip_edges()
		if sid.is_empty():
			continue
		var pos_val = d.get("anchor_pos", null)
		var pos: Vector2i = pos_val if pos_val is Vector2i else Vector2i(-1, -1)
		var label := sid
		if pos != Vector2i(-1, -1):
			label = "%s (%d,%d)" % [sid, pos.x, pos.y]
		_shop_option.add_item(label)
		var idx := _shop_option.get_item_count() - 1
		_shop_option.set_item_metadata(idx, sid)

	var selected_index := 0
	for i in range(_shop_option.get_item_count()):
		if str(_shop_option.get_item_metadata(i)) == selected:
			selected_index = i
			break
	if _shop_option.get_item_count() > 0:
		_shop_option.select(selected_index)

func _on_shop_selected(index: int) -> void:
	if _syncing:
		return
	if _overlay == null or not is_instance_valid(_overlay):
		return
	if not _overlay.has_method("set_selected_from_shop_id"):
		return
	var sid := str(_shop_option.get_item_metadata(index)).strip_edges()
	_overlay.call("set_selected_from_shop_id", sid)

