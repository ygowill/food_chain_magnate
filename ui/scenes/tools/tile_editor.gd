# 板块编辑器（M2 交付物）
extends Control

const TileDefClass = preload("res://core/map/tile_def.gd")
const PieceDefClass = preload("res://core/map/piece_def.gd")
const GameDefaultsClass = preload("res://core/engine/game_defaults.gd")
const ModuleDirSpecClass = preload("res://core/modules/v2/module_dir_spec.gd")
const Storage = preload("res://ui/scenes/tools/tile_editor/storage.gd")
const CellModel = preload("res://ui/scenes/tools/tile_editor/cell_model.gd")

@onready var tile_select: OptionButton = $Root/TopBar/TileSelect
@onready var tile_id_edit: LineEdit = $Root/TopBar/TileIdEdit
@onready var status_label: Label = $Root/TopBar/StatusLabel

@onready var grid: GridContainer = $Root/Body/HSplit/GridScroll/Grid

@onready var selected_cell_label: Label = $Root/Body/HSplit/Inspector/SelectedCellLabel
@onready var blocked_check: CheckButton = $Root/Body/HSplit/Inspector/BlockedCheck

@onready var road_n: CheckBox = $Root/Body/HSplit/Inspector/RoadRow/RoadN
@onready var road_e: CheckBox = $Root/Body/HSplit/Inspector/RoadRow/RoadE
@onready var road_s: CheckBox = $Root/Body/HSplit/Inspector/RoadRow/RoadS
@onready var road_w: CheckBox = $Root/Body/HSplit/Inspector/RoadRow/RoadW
@onready var road_bridge: CheckButton = $Root/Body/HSplit/Inspector/RoadBridge
@onready var road_segments_list: ItemList = $Root/Body/HSplit/Inspector/RoadSegmentsList

@onready var drink_type_edit: LineEdit = $Root/Body/HSplit/Inspector/DrinkRow/DrinkTypeEdit

@onready var piece_select: OptionButton = $Root/Body/HSplit/Inspector/PrintedRow/PieceSelect
@onready var printed_house_id: LineEdit = $Root/Body/HSplit/Inspector/PrintedRow/HouseIdEdit
@onready var printed_house_number: SpinBox = $Root/Body/HSplit/Inspector/PrintedRow/HouseNumberSpin
@onready var printed_rotation: OptionButton = $Root/Body/HSplit/Inspector/PrintedRow/RotationSelect
@onready var printed_list: ItemList = $Root/Body/HSplit/Inspector/PrintedList

var _tile_paths: Dictionary = {} # tile_id -> res://...json
var _piece_ids: Array[String] = []

var current_tile: TileDef = null
var current_tile_path: String = ""

var selected_local: Vector2i = Vector2i.ZERO
var _cell_buttons: Array[Button] = []

func _ready() -> void:
	_build_grid_buttons()
	_load_piece_ids()
	_load_tile_index()
	_refresh_selectors()
	_load_first_tile()
	_select_cell(Vector2i.ZERO)

func _get_primary_modules_base_dir() -> String:
	return ModuleDirSpecClass.primary_base_dir(
		str(Globals.modules_v2_base_dir),
		GameDefaultsClass.DEFAULT_MODULES_V2_BASE_DIR
	)

func _get_user_tiles_dir() -> String:
	return "user://tile_editor/tiles"

func _on_back_pressed() -> void:
	SceneManager.go_back()

func _on_load_pressed() -> void:
	var id := _get_selected_tile_id()
	if id.is_empty():
		_set_status("没有可加载的板块", true)
		return
	_load_tile(id)

func _on_new_pressed() -> void:
	var new_id := tile_id_edit.text.strip_edges()
	if new_id.is_empty():
		new_id = "tile_new"
	tile_id_edit.text = new_id
	current_tile = TileDefClass.create_empty(new_id)
	current_tile.display_name = "板块 %s" % new_id
	current_tile_path = ""
	_set_status("已创建新板块: %s" % new_id, false)
	_refresh_all()

func _on_save_pressed() -> void:
	if current_tile == null:
		_set_status("没有可保存的板块", true)
		return

	var new_id := tile_id_edit.text.strip_edges()
	if new_id.is_empty():
		_set_status("tile_id 不能为空", true)
		return

	current_tile.id = new_id
	if current_tile.display_name.is_empty():
		current_tile.display_name = "板块 %s" % new_id

	current_tile._ensure_road_grid()

	var validate := current_tile.validate()
	if not validate.ok:
		_set_status("验证失败: %s" % validate.error, true)
		return

	var path := current_tile_path
	if path.is_empty():
		path = ""

	var write := Storage.write_tile_json(
		current_tile,
		new_id,
		path,
		_get_primary_modules_base_dir(),
		_get_user_tiles_dir()
	)
	if not write.ok:
		_set_status(write.error, true)
		return
	assert(write.value is Dictionary and write.value.has("path"), "TileEditor: write_tile_json 返回值缺少 path")
	var saved_path: String = str(write.value["path"])
	var used_user_dir := bool(write.value.get("used_user_dir", false))

	current_tile_path = saved_path
	_tile_paths[new_id] = saved_path
	if used_user_dir:
		_set_status("已保存到 user://（导出环境 res:// 可能只读）: %s" % saved_path, false)
	else:
		_set_status("已保存: %s" % saved_path, false)
	_load_tile_index()
	_refresh_selectors()
	_refresh_all()

func _on_validate_pressed() -> void:
	if current_tile == null:
		_set_status("没有可验证的板块", true)
		return
	var result := current_tile.validate()
	if result.ok:
		_set_status("验证通过", false)
	else:
		_set_status("验证失败: %s" % result.error, true)

func _on_blocked_toggled(toggled_on: bool) -> void:
	if current_tile == null:
		return
	current_tile.set_blocked(selected_local, toggled_on)
	_refresh_cell(selected_local)

func _on_add_road_pressed() -> void:
	if current_tile == null:
		return
	var dirs: Array[String] = []
	if road_n.button_pressed:
		dirs.append("N")
	if road_e.button_pressed:
		dirs.append("E")
	if road_s.button_pressed:
		dirs.append("S")
	if road_w.button_pressed:
		dirs.append("W")
	if dirs.is_empty():
		_set_status("请至少选择一个方向", true)
		return

	current_tile.add_road_segment(selected_local, dirs, road_bridge.button_pressed)
	_refresh_cell(selected_local)
	_refresh_road_segments_list()

func _on_clear_road_pressed() -> void:
	if current_tile == null:
		return
	current_tile.clear_road_segments(selected_local)
	_refresh_cell(selected_local)
	_refresh_road_segments_list()

func _on_set_drink_pressed() -> void:
	if current_tile == null:
		return
	var drink_type := drink_type_edit.text.strip_edges()
	if drink_type.is_empty():
		_set_status("饮品类型不能为空", true)
		return
	CellModel.remove_drink_source_at(current_tile, selected_local)
	current_tile.add_drink_source(selected_local, drink_type)
	_refresh_cell(selected_local)

func _on_clear_drink_pressed() -> void:
	if current_tile == null:
		return
	CellModel.remove_drink_source_at(current_tile, selected_local)
	_refresh_cell(selected_local)

func _on_add_printed_pressed() -> void:
	if current_tile == null:
		return
	var piece_id := _get_selected_piece_id()
	if piece_id.is_empty():
		_set_status("请选择 piece_id", true)
		return

	var rot := int(printed_rotation.get_item_text(printed_rotation.selected).to_int())
	var house_id := printed_house_id.text.strip_edges()
	var house_number := int(printed_house_number.value)

	if house_id.is_empty():
		current_tile.add_printed_structure(piece_id, selected_local, rot)
	else:
		current_tile.add_printed_structure(piece_id, selected_local, rot, house_id, house_number)

	_refresh_cell(selected_local)
	_refresh_printed_list()

func _on_remove_printed_pressed() -> void:
	if current_tile == null:
		return
	var idx := printed_list.get_selected_items()
	if idx.is_empty():
		return
	var i := int(idx[0])
	if i < 0 or i >= current_tile.printed_structures.size():
		return
	current_tile.printed_structures.remove_at(i)
	_refresh_all()

func _build_grid_buttons() -> void:
	grid.columns = TileDefClass.TILE_SIZE
	_cell_buttons.clear()

	for y in range(TileDefClass.TILE_SIZE):
		for x in range(TileDefClass.TILE_SIZE):
			var btn := Button.new()
			btn.custom_minimum_size = Vector2(56, 56)
			btn.text = "."
			btn.toggle_mode = false
			btn.pressed.connect(_on_cell_pressed.bind(Vector2i(x, y)))
			grid.add_child(btn)
			_cell_buttons.append(btn)

func _on_cell_pressed(pos: Vector2i) -> void:
	_select_cell(pos)

func _load_piece_ids() -> void:
	var read := Storage.load_piece_ids(_get_primary_modules_base_dir())
	if not read.ok:
		_set_status(read.error, true)
		return
	assert(read.value is Array, "TileEditor._load_piece_ids: 返回值类型错误（期望 Array）")
	_piece_ids = Array(read.value, TYPE_STRING, "", null)
	piece_select.clear()
	for id in _piece_ids:
		piece_select.add_item(id)

	printed_rotation.clear()
	for rot in [0, 90, 180, 270]:
		printed_rotation.add_item(str(rot))
	printed_rotation.select(0)

func _load_tile_index() -> void:
	var read := Storage.load_tile_paths(_get_primary_modules_base_dir(), _get_user_tiles_dir())
	if not read.ok:
		_set_status(read.error, true)
		return
	assert(read.value is Dictionary, "TileEditor._load_tile_index: 返回值类型错误（期望 Dictionary）")
	_tile_paths = read.value

func _refresh_selectors() -> void:
	var ids: Array[String] = []
	for key in _tile_paths.keys():
		ids.append(str(key))
	ids.sort()

	var current_id := tile_id_edit.text.strip_edges()
	tile_select.clear()
	for id in ids:
		tile_select.add_item(id)

	if not current_id.is_empty():
		for i in range(tile_select.get_item_count()):
			if tile_select.get_item_text(i) == current_id:
				tile_select.select(i)
				break

func _load_first_tile() -> void:
	var id := _get_selected_tile_id()
	if not id.is_empty():
		_load_tile(id)

func _load_tile(tile_id: String) -> void:
	var path: String = _tile_paths.get(tile_id, "")
	if path.is_empty():
		_set_status("找不到板块文件: %s" % tile_id, true)
		return
	var tile_result := TileDefClass.load_from_file(path)
	if not tile_result.ok:
		_set_status("无法加载板块: %s (%s)" % [path, tile_result.error], true)
		return
	current_tile = tile_result.value
	current_tile_path = path
	tile_id_edit.text = current_tile.id
	_set_status("已加载: %s" % path, false)
	_refresh_all()

func _refresh_all() -> void:
	_refresh_grid()
	_refresh_road_segments_list()
	_refresh_printed_list()
	_refresh_cell_inspector()

func _refresh_grid() -> void:
	for y in range(TileDefClass.TILE_SIZE):
		for x in range(TileDefClass.TILE_SIZE):
			_refresh_cell(Vector2i(x, y))

func _refresh_cell(local_pos: Vector2i) -> void:
	var idx := local_pos.y * TileDefClass.TILE_SIZE + local_pos.x
	if idx < 0 or idx >= _cell_buttons.size():
		return
	var btn := _cell_buttons[idx]

	if current_tile == null:
		btn.text = "."
		return

	var tags: Array[String] = []
	if current_tile.is_blocked_at(local_pos):
		tags.append("X")

	var segs: Array = current_tile.get_road_segments_at(local_pos)
	if not segs.is_empty():
		tags.append("R%d" % segs.size())

	var drink = CellModel.get_drink_source_at(current_tile, local_pos)
	if drink != null:
		tags.append("D")

	if CellModel.has_printed_anchor_at(current_tile, local_pos):
		tags.append("P")

	btn.text = "." if tags.is_empty() else "\n".join(tags)
	btn.modulate = Color(1, 1, 1, 1) if local_pos != selected_local else Color(0.75, 0.95, 1.0, 1)

func _refresh_cell_inspector() -> void:
	selected_cell_label.text = "选中格子: (%d, %d)" % [selected_local.x, selected_local.y]
	if current_tile == null:
		blocked_check.button_pressed = false
		drink_type_edit.text = ""
		return

	blocked_check.button_pressed = current_tile.is_blocked_at(selected_local)
	var drink = CellModel.get_drink_source_at(current_tile, selected_local)
	drink_type_edit.text = drink.get("type", "") if drink != null else ""

func _refresh_road_segments_list() -> void:
	road_segments_list.clear()
	if current_tile == null:
		return

	var segs: Array = current_tile.get_road_segments_at(selected_local)
	for seg in segs:
		var dirs: Array = seg.get("dirs", [])
		var bridge: bool = bool(seg.get("bridge", false))
		road_segments_list.add_item("%s%s" % [",".join(dirs), " (bridge)" if bridge else ""])

func _refresh_printed_list() -> void:
	printed_list.clear()
	if current_tile == null:
		return

	for i in range(current_tile.printed_structures.size()):
		var s: Dictionary = current_tile.printed_structures[i]
		var piece_id: String = str(s.get("piece_id", ""))
		var anchor: Vector2i = s.get("anchor", Vector2i.ZERO)
		var rot: int = int(s.get("rotation", 0))
		var house_id: String = str(s.get("house_id", ""))
		var house_number = s.get("house_number", null)

		var suffix := ""
		if not house_id.is_empty():
			suffix = " #%s(%s)" % [house_id, str(house_number)]

		printed_list.add_item("%s @(%d,%d) r%d%s" % [piece_id, anchor.x, anchor.y, rot, suffix])

func _select_cell(local_pos: Vector2i) -> void:
	selected_local = local_pos
	_refresh_grid()
	_refresh_cell_inspector()
	_refresh_road_segments_list()

func _get_selected_tile_id() -> String:
	if tile_select.get_item_count() <= 0:
		return ""
	return tile_select.get_item_text(tile_select.selected)

func _get_selected_piece_id() -> String:
	if piece_select.get_item_count() <= 0:
		return ""
	return piece_select.get_item_text(piece_select.selected)

func _set_status(message: String, is_error: bool) -> void:
	status_label.text = message
	status_label.modulate = Color(1, 0.6, 0.6, 1) if is_error else Color(0.8, 1, 0.8, 1)
