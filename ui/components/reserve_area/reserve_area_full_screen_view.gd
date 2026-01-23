# 供应堆全屏视图（TopBar）
# - 分类展示当前对局“未使用/未放置”的 piece（包含模块引入的新 piece）
# - 纯展示（不提供点击联动）
# - ESC 关闭；关闭只隐藏自身，不影响底层面板显示状态
class_name ReserveAreaFullScreenView
extends Control

signal close_requested()
signal build_finished()

@onready var sections: VBoxContainer = $MarginContainer/VBoxContainer/ScrollContainer/Sections
@onready var scroll_container: ScrollContainer = $MarginContainer/VBoxContainer/ScrollContainer
@onready var loading_center: Control = $MarginContainer/VBoxContainer/LoadingCenter
@onready var close_button: Button = $MarginContainer/VBoxContainer/HeaderRow/CloseButton
@onready var zoom_out_button: Button = $MarginContainer/VBoxContainer/HeaderRow/ZoomOutButton
@onready var zoom_slider: HSlider = $MarginContainer/VBoxContainer/HeaderRow/ZoomSlider
@onready var zoom_in_button: Button = $MarginContainer/VBoxContainer/HeaderRow/ZoomInButton
@onready var zoom_label: Label = $MarginContainer/VBoxContainer/HeaderRow/ZoomLabel

const MapSkinBuilderClass = preload("res://ui/visual/map_skin_builder.gd")
const MapCanvasDrawerClass = preload("res://ui/scenes/game/map_canvas_drawer.gd")
const MarketingRegistryClass = preload("res://core/data/marketing_registry.gd")
const PieceRegistryClass = preload("res://core/map/piece_registry.gd")
const MapUtilsClass = preload("res://core/map/map_utils.gd")

var _skin = null
var _skin_key: String = ""
var _build_in_progress: bool = false
var _last_build_key: String = ""
var _pending_state = null

const BASE_CELL_SIZE := 40
const ZOOM_MIN_PERCENT := 50
const ZOOM_MAX_PERCENT := 200
const ZOOM_STEP_PERCENT := 10

var _zoom_percent: int = 100
var _cell_size: int = BASE_CELL_SIZE

func _ready() -> void:
	set_process_unhandled_input(true)
	if is_instance_valid(close_button):
		close_button.pressed.connect(_on_close_pressed)
	if is_instance_valid(zoom_out_button):
		zoom_out_button.pressed.connect(_on_zoom_out_pressed)
	if is_instance_valid(zoom_in_button):
		zoom_in_button.pressed.connect(_on_zoom_in_pressed)
	if is_instance_valid(zoom_slider):
		zoom_slider.value_changed.connect(_on_zoom_slider_changed)
		_apply_zoom_percent(int(round(zoom_slider.value)), false)
	else:
		_apply_zoom_percent(_zoom_percent, false)
	_set_loading_visible(false)
	visible = false

func set_skin(skin) -> void:
	# 允许外部（例如 MapCanvas）注入已构建的 MapSkin，避免重复 build 导致卡顿。
	_skin = skin

func open_with_state(state: GameState, skin_override = null) -> void:
	visible = true
	begin_background_build(state, skin_override)

func begin_background_build(state: GameState, skin_override = null) -> void:
	if state == null:
		return
	_pending_state = state

	if skin_override != null:
		set_skin(skin_override)
	else:
		_ensure_skin_for_state(state)

	var build_key := _compute_build_key(state)
	if not _build_in_progress and not _last_build_key.is_empty() and build_key == _last_build_key:
		_set_loading_visible(false)
		build_finished.emit()
		return

	if _build_in_progress:
		return

	_build_in_progress = true
	_set_loading_visible(true)
	call_deferred("_run_background_rebuild", state, build_key)

func _set_loading_visible(loading: bool) -> void:
	if is_instance_valid(loading_center):
		loading_center.visible = loading
	if is_instance_valid(scroll_container):
		scroll_container.visible = not loading

func _apply_zoom_percent(pct: int, update_slider: bool = true) -> void:
	var p := clampi(int(pct), ZOOM_MIN_PERCENT, ZOOM_MAX_PERCENT)
	if _zoom_percent == p and not update_slider:
		return
	_zoom_percent = p
	_cell_size = maxi(1, int(round(float(BASE_CELL_SIZE) * float(_zoom_percent) / 100.0)))

	if is_instance_valid(zoom_label):
		zoom_label.text = "%d%%" % _zoom_percent
	if update_slider and is_instance_valid(zoom_slider):
		zoom_slider.value = float(_zoom_percent)

	_apply_cell_size_to_existing_tokens()

func _apply_cell_size_to_existing_tokens() -> void:
	if sections == null:
		return
	_apply_cell_size_recursive(sections)

func _apply_cell_size_recursive(node: Node) -> void:
	if node == null or not is_instance_valid(node):
		return
	if node.has_method("set_cell_size"):
		node.call("set_cell_size", _cell_size)
	for c in node.get_children():
		if c is Node:
			_apply_cell_size_recursive(c)

func _on_zoom_out_pressed() -> void:
	_apply_zoom_percent(_zoom_percent - ZOOM_STEP_PERCENT, true)

func _on_zoom_in_pressed() -> void:
	_apply_zoom_percent(_zoom_percent + ZOOM_STEP_PERCENT, true)

func _on_zoom_slider_changed(value: float) -> void:
	_apply_zoom_percent(int(round(value)), false)

func request_close() -> void:
	if not visible:
		return
	visible = false
	close_requested.emit()

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event != null and event.is_action_pressed("ui_cancel"):
		accept_event()
		request_close()

func _on_close_pressed() -> void:
	request_close()

func _ensure_skin_for_state(state: GameState) -> void:
	var modules: Array[String] = []
	if state.modules is Array:
		modules = Array(state.modules, TYPE_STRING, "", null)
	var base_dir := Globals.modules_v2_base_dir if Globals != null else "res://modules"
	var key := "%s|%s" % [base_dir, ",".join(modules)]
	if _skin != null and key == _skin_key:
		return

	var build := MapSkinBuilderClass.build_for_modules(base_dir, modules, 40)
	if build.ok:
		_skin = build.value
		_skin_key = key
	else:
		_skin = null
		_skin_key = ""

func _rebuild_from_state(state: GameState) -> void:
	if sections == null:
		return
	for c in sections.get_children():
		if is_instance_valid(c):
			c.queue_free()

	_add_house_numbers_section(state)
	_add_garden_section(state)
	_add_marketing_boards_section(state)
	_add_module_supplies_section(state)
	_add_player_token_supplies_section(state)

func _run_background_rebuild(state: GameState, build_key: String) -> void:
	# 先让“加载中...”有机会显示出来（避免 open 同帧就做重建导致看不到占位）。
	await get_tree().process_frame
	if not is_instance_valid(self):
		return
	if state == null:
		_build_in_progress = false
		_set_loading_visible(false)
		build_finished.emit()
		return

	if sections == null or not is_instance_valid(sections):
		_build_in_progress = false
		return

	for c in sections.get_children():
		if is_instance_valid(c):
			c.queue_free()

	_add_house_numbers_section(state)
	await get_tree().process_frame
	if not is_instance_valid(self):
		return

	_add_garden_section(state)
	await get_tree().process_frame
	if not is_instance_valid(self):
		return

	_add_marketing_boards_section(state)
	await get_tree().process_frame
	if not is_instance_valid(self):
		return

	_add_module_supplies_section(state)
	await get_tree().process_frame
	if not is_instance_valid(self):
		return

	_add_player_token_supplies_section(state)

	_last_build_key = build_key
	_build_in_progress = false
	_set_loading_visible(false)
	build_finished.emit()

	# 若构建期间 state 发生变化，则按新的 key 再次触发后台重建。
	if _pending_state != null and is_instance_valid(self):
		var pending_key := _compute_build_key(_pending_state)
		if pending_key != _last_build_key:
			begin_background_build(_pending_state, _skin)

func _compute_build_key(state: GameState) -> String:
	if state == null:
		return ""
	var modules_key := ""
	if state.modules is Array:
		modules_key = ",".join(Array(state.modules, TYPE_STRING, "", null))

	var map_key := ""
	if state.map is Dictionary:
		var m: Dictionary = state.map
		var hn_val = m.get("house_number_supply_remaining", [])
		if hn_val is Array:
			var nums: Array[int] = []
			for v in Array(hn_val):
				if v is int:
					nums.append(int(v))
				elif v is float:
					var f: float = float(v)
					if f == floor(f):
						nums.append(int(f))
			nums.sort()
			var num_strs: Array[String] = []
			for n in nums:
				num_strs.append(str(n))
			map_key += "hn=" + ",".join(num_strs)

		var g = m.get("garden_supply_remaining", 0)
		if g is int or g is float:
			map_key += "|g=" + str(int(g))

		var mk := ""
		var placements_val = m.get("marketing_placements", null)
		if placements_val is Dictionary:
			var ks: Array[String] = []
			for k in Dictionary(placements_val).keys():
				ks.append(str(k))
			ks.sort()
			mk = ",".join(ks)
		map_key += "|mp=" + mk

		var supply_parts: Array[String] = []
		for k2 in m.keys():
			var key2 := str(k2)
			if not key2.ends_with("_supply_remaining"):
				continue
			if key2 == "house_number_supply_remaining" or key2 == "garden_supply_remaining" or key2 == "tile_supply_remaining":
				continue
			var v2 = m.get(k2, null)
			if v2 is int or v2 is float:
				var c2 := int(v2)
				if c2 > 0:
					supply_parts.append("%s=%d" % [key2, c2])
		supply_parts.sort()
		map_key += "|sup=" + ";".join(supply_parts)

	var player_parts: Array[String] = []
	for pid in range(state.players.size()):
		var p_val = state.players[pid]
		if not (p_val is Dictionary):
			player_parts.append("")
			continue
		var p: Dictionary = p_val
		var items: Array[String] = []
		for k3 in p.keys():
			var key3 := str(k3)
			if not key3.ends_with("_tokens_remaining"):
				continue
			var v3 = p.get(k3, null)
			if v3 is int or v3 is float:
				var c3 := int(v3)
				if c3 > 0:
					items.append("%s=%d" % [key3, c3])
		items.sort()
		player_parts.append(";".join(items))

	return "%s|%s|%s" % [modules_key, map_key, "|".join(player_parts)]

func _add_section(title: String) -> HFlowContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sections.add_child(box)

	var label := Label.new()
	label.text = title
	label.add_theme_font_size_override("font_size", Globals.get_scaled_font_size(16) if Globals != null else 16)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(label)

	var flow := HFlowContainer.new()
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	flow.alignment = FlowContainer.ALIGNMENT_CENTER
	flow.add_theme_constant_override("h_separation", 10)
	flow.add_theme_constant_override("v_separation", 10)
	box.add_child(flow)
	return flow

func _add_house_numbers_section(state: GameState) -> void:
	if state == null or not (state.map is Dictionary):
		return
	var supply_val = state.map.get("house_number_supply_remaining", null)
	if not (supply_val is Array):
		return
	var supply: Array = supply_val
	if supply.is_empty():
		return

	var nums: Array[int] = []
	for v in supply:
		if v is int:
			nums.append(int(v))
		elif v is float:
			var f: float = float(v)
			if f == floor(f):
				nums.append(int(f))
	nums.sort()

	var flow := _add_section("房屋编号（未使用 %d）" % nums.size())
	for n in nums:
		var token := HouseWithGardenNumberToken.new()
		token.house_number = n
		token.set_skin(_skin)
		token.set_cell_size(_cell_size)
		flow.add_child(token)

func _add_garden_section(state: GameState) -> void:
	if state == null or not (state.map is Dictionary):
		return
	var v = state.map.get("garden_supply_remaining", null)
	if not (v is int or v is float):
		return
	var count := int(v)
	if count <= 0:
		return
	var flow := _add_section("花园（剩余 %d）" % count)
	var token := GardenExtensionToken.new()
	token.count = count
	token.set_skin(_skin)
	token.set_cell_size(_cell_size)
	token.tooltip_text = "花园 ×%d" % count
	flow.add_child(token)

func _add_marketing_boards_section(state: GameState) -> void:
	if state == null:
		return
	if not MarketingRegistryClass.is_loaded():
		return

	var used := {}
	if state.map is Dictionary and state.map.has("marketing_placements") and (state.map["marketing_placements"] is Dictionary):
		var placements: Dictionary = state.map["marketing_placements"]
		for k in placements.keys():
			used[str(k)] = true

	var player_count := state.players.size()

	var by_type: Dictionary = {} # type -> Array[Dictionary{bn,def}]
	for bn in MarketingRegistryClass.get_all_board_numbers():
		var def_val = MarketingRegistryClass.get_def(bn)
		if def_val == null or not (def_val is MarketingDef):
			continue
		var def: MarketingDef = def_val
		if def.has_method("is_available_for_player_count") and not def.is_available_for_player_count(player_count):
			continue
		if used.has(str(bn)):
			continue
		var t := str(def.type).strip_edges()
		if t.is_empty():
			t = "default"
		if not by_type.has(t):
			by_type[t] = []
		var arr: Array = by_type[t]
		arr.append({"bn": bn, "def": def})
		by_type[t] = arr

	if by_type.is_empty():
		return

	var order := ["billboard", "mailbox", "radio", "airplane"]
	for t in order:
		if not by_type.has(t):
			continue
		_add_marketing_type_section(t, Array(by_type[t]))

	# 未知/扩展类型
	for t2 in by_type.keys():
		var type_id := str(t2)
		if order.has(type_id):
			continue
		_add_marketing_type_section(type_id, Array(by_type[t2]))

func _add_marketing_type_section(type_id: String, entries: Array) -> void:
	if entries.is_empty():
		return
	var title := "营销板件：%s（未使用 %d）" % [_get_marketing_type_name(type_id), entries.size()]
	var flow := _add_section(title)
	for e in entries:
		if not (e is Dictionary):
			continue
		var d: Dictionary = e
		var bn := int(d.get("bn", 0))
		var def_val = d.get("def", null)
		if bn <= 0 or not (def_val is MarketingDef):
			continue
		var def: MarketingDef = def_val
		var token := MarketingBoardToken.new()
		token.set_skin(_skin)
		token.set_cell_size(_cell_size)
		token.board_number = bn
		token.marketing_type = type_id
		token.footprint_size = def.footprint_size
		flow.add_child(token)

func _get_marketing_type_name(type_id: String) -> String:
	match str(type_id):
		"billboard":
			return "广告牌"
		"mailbox":
			return "邮箱"
		"radio":
			return "电波"
		"airplane":
			return "飞机"
		_:
			return str(type_id)

func _add_module_supplies_section(state: GameState) -> void:
	if state == null or not (state.map is Dictionary):
		return

	# 收集模块 supply：state.map.*_supply_remaining（排除 base 与 tile）
	var entries: Array[Dictionary] = []
	for k in state.map.keys():
		var key := str(k)
		if not key.ends_with("_supply_remaining"):
			continue
		if key == "house_number_supply_remaining" or key == "garden_supply_remaining" or key == "tile_supply_remaining":
			continue
		var v = state.map.get(k, null)
		if v is int:
			if int(v) > 0:
				entries.append({"key": key, "count": int(v)})
		elif v is float:
			var f: float = float(v)
			if f == floor(f) and int(f) > 0:
				entries.append({"key": key, "count": int(f)})

	if entries.is_empty():
		return

	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("key", "")) < str(b.get("key", ""))
	)

	var module_ids: Array[String] = []
	if state.modules is Array:
		module_ids = Array(state.modules, TYPE_STRING, "", null)

	var piece_ids: Array[String] = []
	if PieceRegistryClass.is_loaded():
		piece_ids = PieceRegistryClass.get_all_ids()

	var flow := _add_section("模块板件（全局供给）")
	for e in entries:
		var key: String = str(e.get("key", ""))
		var count := int(e.get("count", 0))
		if key.is_empty() or count <= 0:
			continue
		var base := key.trim_suffix("_supply_remaining")
		if _is_excluded_piece_id(base):
			continue
		var piece_id := _guess_piece_id_for_supply(base, module_ids, piece_ids)
		if _is_excluded_piece_id(piece_id):
			continue
		var token := PieceFootprintToken.new()
		token.piece_id = piece_id
		token.count = count
		token.set_skin(_skin)
		token.set_cell_size(_cell_size)
		token.tooltip_text = "%s ×%d" % [base, count]
		flow.add_child(token)

func _is_excluded_piece_id(id_str: String) -> bool:
	# 用户已澄清：不展示地图扩展 tile 与餐厅（但模块引入的新 piece 需要展示）。
	var s := str(id_str).strip_edges()
	if s.is_empty():
		return false
	var l := s.to_lower()
	if l == "tile" or l.begins_with("tile_"):
		return true
	if l == "restaurant" or l.begins_with("restaurant_"):
		return true
	return false

func _guess_piece_id_for_supply(base: String, module_ids: Array[String], piece_ids: Array[String]) -> String:
	var b := str(base).strip_edges()
	if b.is_empty():
		return b
	if not piece_ids.is_empty():
		if piece_ids.has(b):
			return b
		for pid in piece_ids:
			if pid.begins_with(b + "_"):
				return pid
		for mid in module_ids:
			var prefix := str(mid) + "_"
			if b.begins_with(prefix):
				var rem := b.substr(prefix.length())
				if rem.is_empty():
					continue
				if piece_ids.has(rem):
					return rem
				for pid2 in piece_ids:
					if pid2.find(rem) >= 0:
						return pid2
		var parts := b.split("_")
		if parts.size() > 0:
			var needle := str(parts[parts.size() - 1])
			if piece_ids.has(needle):
				return needle
			for pid3 in piece_ids:
				if pid3.find(needle) >= 0:
					return pid3
	return b

func _add_player_token_supplies_section(state: GameState) -> void:
	# 玩家侧 tokens_remaining：仅展示存在对应 piece_id 的条目（例如 coffee_shop_tokens_remaining -> coffee_shop）
	if state == null:
		return
	if not PieceRegistryClass.is_loaded():
		return

	var any := false
	for pid in range(state.players.size()):
		var p_val = state.players[pid]
		if not (p_val is Dictionary):
			continue
		var p: Dictionary = p_val
		for k in p.keys():
			var key := str(k)
			if not key.ends_with("_tokens_remaining"):
				continue
			var v = p.get(k, null)
			if not (v is int or v is float):
				continue
			var count := int(v)
			if count <= 0:
				continue
			var piece_id := key.trim_suffix("_tokens_remaining")
			if piece_id.is_empty():
				continue
			if _is_excluded_piece_id(piece_id):
				continue
			if not PieceRegistryClass.has(piece_id):
				continue
			any = true
			break
		if any:
			break

	if not any:
		return

	for pid2 in range(state.players.size()):
		var p_val2 = state.players[pid2]
		if not (p_val2 is Dictionary):
			continue
		var p2: Dictionary = p_val2
		var items: Array[Dictionary] = []
		for k2 in p2.keys():
			var key2 := str(k2)
			if not key2.ends_with("_tokens_remaining"):
				continue
			var v2 = p2.get(k2, null)
			if not (v2 is int or v2 is float):
				continue
			var count2 := int(v2)
			if count2 <= 0:
				continue
			var piece_id2 := key2.trim_suffix("_tokens_remaining")
			if piece_id2.is_empty():
				continue
			if _is_excluded_piece_id(piece_id2):
				continue
			if not PieceRegistryClass.has(piece_id2):
				continue
			items.append({"piece_id": piece_id2, "count": count2})

		if items.is_empty():
			continue
		items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return str(a.get("piece_id", "")) < str(b.get("piece_id", ""))
		)

		var name := Globals.get_player_name(pid2) if Globals != null else ("玩家%d" % (pid2 + 1))
		var flow := _add_section("%s（玩家板件）" % name)
		for it in items:
			var pid_str := str(it.get("piece_id", ""))
			var cnt := int(it.get("count", 0))
			if pid_str.is_empty() or cnt <= 0:
				continue
			var token := PieceFootprintToken.new()
			token.piece_id = pid_str
			token.count = cnt
			token.set_skin(_skin)
			token.set_cell_size(_cell_size)
			token.tooltip_text = "%s ×%d" % [pid_str, cnt]
			flow.add_child(token)


# === 内部类：通用 token（贴图 + badge）===
class IconToken extends PanelContainer:
	var texture: Texture2D = null
	var badge_text: String = ""

	var _tex_rect: TextureRect
	var _badge_label: Label

	func _ready() -> void:
		_build_ui()
		_update_ui()

	func _build_ui() -> void:
		mouse_filter = Control.MOUSE_FILTER_PASS
		custom_minimum_size = Vector2(80, 80)
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.12, 0.12, 0.14, 0.92)
		style.border_color = Color(0.25, 0.25, 0.3, 0.6)
		style.set_border_width_all(1)
		style.set_corner_radius_all(10)
		add_theme_stylebox_override("panel", style)

		var container := Control.new()
		container.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(container)
		container.set_anchors_preset(Control.PRESET_FULL_RECT)

		_tex_rect = TextureRect.new()
		_tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_tex_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		_tex_rect.offset_left = 10
		_tex_rect.offset_top = 10
		_tex_rect.offset_right = -10
		_tex_rect.offset_bottom = -10
		container.add_child(_tex_rect)

		_badge_label = Label.new()
		_badge_label.add_theme_font_size_override("font_size", Globals.get_scaled_font_size(12) if Globals != null else 12)
		_badge_label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
		_badge_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_badge_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		_badge_label.set_anchors_preset(Control.PRESET_FULL_RECT)
		_badge_label.offset_left = 8
		_badge_label.offset_top = 6
		_badge_label.offset_right = -8
		_badge_label.offset_bottom = -6
		container.add_child(_badge_label)

	func _update_ui() -> void:
		if _tex_rect != null:
			_tex_rect.texture = texture
		if _badge_label != null:
			_badge_label.text = badge_text


# === 房屋编号 token（按地图真实风格绘制：house_with_garden）===
class HouseWithGardenNumberToken extends Control:
	var house_number: int = -1

	var _skin = null
	var _cell_size: int = 40

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_PASS
		custom_minimum_size = Vector2(float(_cell_size * 2), float(_cell_size * 3))
		var t := str(house_number) if house_number > 0 else ""
		tooltip_text = "房屋 %s" % t if not t.is_empty() else "房屋"
		queue_redraw()

	func set_skin(skin) -> void:
		_skin = skin
		queue_redraw()

	func set_cell_size(cell_size: int) -> void:
		_cell_size = maxi(1, int(cell_size))
		custom_minimum_size = Vector2(float(_cell_size * 2), float(_cell_size * 3))
		queue_redraw()

	func _world_to_view(world_pos: Vector2i) -> Vector2i:
		# 该 token 内部使用“局部网格”（world==view），以复用 MapCanvasDrawer 的绘制逻辑。
		return world_pos

	func _draw() -> void:
		if _skin == null:
			return
		# MapCanvasDrawer._draw_house_and_garden 依赖 canvas._skin / canvas._world_to_view()
		self._skin = _skin
		var info := {
			"piece_id": "house_with_garden",
			"rotation": 0,
			"house_id": str(house_number) if house_number > 0 else "",
			"min": Vector2i(0, 0),
			"max": Vector2i(1, 2), # 2x3（house 2x2 + garden 2x1）
		}
		MapCanvasDrawerClass._draw_house_and_garden(self, _cell_size, Vector2i.ZERO, info, 1.0)


# === 花园 token（按地图风格绘制 2x1 花园扩展 + 数量角标）===
class GardenExtensionToken extends Control:
	var count: int = 0

	var _skin = null
	var _cell_size: int = 40

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_PASS
		custom_minimum_size = Vector2(float(_cell_size * 2), float(_cell_size))
		queue_redraw()

	func set_skin(skin) -> void:
		_skin = skin
		queue_redraw()

	func set_cell_size(cell_size: int) -> void:
		_cell_size = maxi(1, int(cell_size))
		custom_minimum_size = Vector2(float(_cell_size * 2), float(_cell_size))
		queue_redraw()

	func _draw() -> void:
		var rect := Rect2(Vector2.ZERO, custom_minimum_size)
		var bg := Color("#22C55E")
		bg.a = 0.30
		draw_rect(rect, bg, true)

		if _skin != null:
			var tex: Texture2D = _skin.get_piece_texture("garden_large")
			var pad := maxf(2.0, float(_cell_size) * 0.10)
			var inner := rect.grow(-pad)
			MapCanvasDrawerClass._draw_texture_aspect_fit(self, tex, inner, Color(1, 1, 1, 0.9), "center")

		if count > 0:
			# 复用营销板件的编号角标样式（白底圆 + 黑字），用于展示剩余数量。
			MapCanvasDrawerClass._draw_marketing_board_number_badge(self, rect, int(count), _cell_size, 1.0)


# === 营销板件 token（复用 MapCanvasDrawer 的绘制风格）===
class MarketingBoardToken extends Control:
	var board_number: int = 0
	var marketing_type: String = ""
	var footprint_size: Vector2i = Vector2i.ONE

	var _skin = null
	var _cell_size: int = 40

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_PASS
		_update_min_size()

	func set_skin(skin) -> void:
		_skin = skin
		queue_redraw()

	func set_cell_size(cell_size: int) -> void:
		_cell_size = maxi(1, int(cell_size))
		_update_min_size()
		queue_redraw()

	func _update_min_size() -> void:
		var size := Vector2(maxi(1, footprint_size.x) * _cell_size, maxi(1, footprint_size.y) * _cell_size)
		custom_minimum_size = size

	func _draw() -> void:
		if _skin == null:
			return
		var placement := {
			"type": marketing_type,
			"board_number": board_number,
			"footprint_size": footprint_size,
			"rotation": 0,
		}
		# MapCanvasDrawer._draw_marketing_placement 依赖 canvas._skin
		self._skin = _skin
		MapCanvasDrawerClass._draw_marketing_placement(self, _cell_size, placement, 1.0, Rect2(Vector2.ZERO, custom_minimum_size))


# === 通用 piece token：按 PieceRegistry footprint 1:1 预览 + 数量角标 ===
class PieceFootprintToken extends Control:
	var piece_id: String = ""
	var count: int = 0

	var _skin = null
	var _cell_size: int = 40
	var _size_cells: Vector2i = Vector2i.ONE

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_PASS
		_recompute_footprint()
		_update_min_size()
		queue_redraw()

	func set_skin(skin) -> void:
		_skin = skin
		queue_redraw()

	func set_cell_size(cell_size: int) -> void:
		_cell_size = maxi(1, int(cell_size))
		_update_min_size()
		queue_redraw()

	func _recompute_footprint() -> void:
		_size_cells = Vector2i.ONE
		if piece_id.is_empty():
			return
		if not PieceRegistryClass.is_loaded():
			return
		var def_val = PieceRegistryClass.get_def(piece_id) if PieceRegistryClass.has(piece_id) else null
		if not (def_val is PieceDef):
			return
		var def: PieceDef = def_val
		var cells: Array[Vector2i] = MapUtilsClass.get_footprint_cells(def.footprint_mask, def.anchor, Vector2i.ZERO, 0)
		var bounds: Dictionary = MapUtilsClass.get_footprint_bounds(cells)
		var size_val = bounds.get("size", Vector2i.ONE)
		if size_val is Vector2i:
			var s: Vector2i = size_val
			if s.x > 0 and s.y > 0:
				_size_cells = s

	func _update_min_size() -> void:
		custom_minimum_size = Vector2(float(maxi(1, _size_cells.x) * _cell_size), float(maxi(1, _size_cells.y) * _cell_size))

	func _draw() -> void:
		var rect := Rect2(Vector2.ZERO, custom_minimum_size)
		var bg := Color(0.12, 0.12, 0.14, 0.92)
		draw_rect(rect, bg, true)
		draw_rect(rect, Color(0.25, 0.25, 0.3, 0.6), false, 1.0)

		if _skin != null and not piece_id.is_empty():
			var tex: Texture2D = _skin.get_piece_texture(piece_id)
			var offset_px: Vector2i = _skin.get_piece_offset_px(piece_id)
			var scale: Vector2 = _skin.get_piece_scale(piece_id)
			var pos_px := Vector2(float(offset_px.x), float(offset_px.y))
			var size_px := Vector2(float(_size_cells.x * _cell_size), float(_size_cells.y * _cell_size)) * scale
			draw_texture_rect(tex, Rect2(pos_px, size_px), false, Color(1, 1, 1, 0.85))

		if count > 0:
			_draw_count_badge(rect, count)

	func _draw_count_badge(rect: Rect2, c: int) -> void:
		var text := "×%d" % int(c)
		var pad := maxf(2.0, float(_cell_size) * 0.06)
		var font: Font = ThemeDB.fallback_font
		var font_size := maxi(10, int(round(float(_cell_size) * 0.32)))
		var est_char_w := float(font_size) * 0.6
		var w := maxf(float(font_size), est_char_w * float(text.length()) + pad * 2.0)
		var h := float(font_size) + pad * 2.0
		var box := Rect2(Vector2(rect.size.x - w - pad, pad), Vector2(w, h))
		draw_rect(box, Color(0, 0, 0, 0.55), true)
		var baseline := Vector2(box.position.x, box.position.y + box.size.y * 0.5 + float(font_size) * 0.35)
		draw_string(font, baseline, text, HORIZONTAL_ALIGNMENT_CENTER, box.size.x, font_size, Color(1, 1, 1, 0.95))
