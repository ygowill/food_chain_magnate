# 晚餐结算动画控制器
# 在地图上逐笔播放结算动画，替代旧的模态面板
class_name DinnertimeAnimationController
extends RefCounted

signal settlement_completed()

const OverlayUtilsClass = preload("res://ui/scenes/game/game_overlay_utils.gd")
const MapUtilsClass = preload("res://core/map/map_utils.gd")
const StructuresClass = preload("res://core/map/map_runtime/structures.gd")
const RoadGraphCacheClass = preload("res://core/map/map_runtime/road_graph_cache.gd")
const UiSkinCacheClass = preload("res://ui/visual/ui_skin_cache.gd")
const ModulesBaseDirClass = preload("res://ui/utils/modules_base_dir.gd")
const UiStylesClass = preload("res://ui/utils/ui_styles.gd")
const DinnerTimeOverlayClass = preload("res://ui/components/dinner_time/dinner_time_overlay.gd")
const TextureUtilsClass = preload("res://ui/scenes/game/map_canvas_drawer_texture_utils.gd")

const COIN_TEXTURE_PATH = "res://assets/images/coin_gold.svg"
const COIN_BASE_COUNT := 1
const COIN_PER_AMOUNT := 5
const COIN_MAX_COUNT := 20
const COIN_BASE_SIZE := 24.0
const COIN_SIZE_SCALE := 0.28
const DEMAND_TOKEN_ICON_SCALE := 0.90
const ROUTE_FLASH_ALPHA_MIN := 0.35
const ROUTE_FLASH_ALPHA_MAX := 0.95

enum State { IDLE, PLAYING, DONE }

var _state: int = State.IDLE
var _orders: Array[Dictionary] = []
var _current_idx: int = 0
var _auto_play: bool = false
var _previewing: bool = false

var _scene: Node = null
var _map_canvas = null
var _game_state: GameState = null
var _anim_layer: Control = null
var _map_anim_layer: Control = null
var _control_bar: Control = null
var _highlight_ring: Control = null
var _preview_tokens: Array[Control] = []
var _house_tokens: Dictionary = {} # house_id -> Array[Control]（持久存在，直到该房屋结算播放）
var _route_highlight_nodes: Array[Control] = []
var _route_highlight_tween: Tween = null
var _current_house_id: String = ""
var _skin = null
var _coin_tex: Texture2D = null
var _active_tweens: Array[Tween] = []
var _speed: float = 1.0
var _running_bank_value: int = 0
var _player_running_cash: Dictionary = {}  # player_id -> int
var _started_preview: bool = false
var _layout_last_cell_size: int = -1
var _layout_last_origin: Vector2i = Vector2i(2147483647, 2147483647)
var _layout_stable_ticks: int = 0
var _layout_wait_ticks: int = 0
var _layout_monitor_running: bool = false
var _layout_monitor_cell_size: int = -1
var _layout_monitor_origin: Vector2i = Vector2i(2147483647, 2147483647)
var _layout_start_wait_running: bool = false
var _dinnertime_distance_script = null

# 外部 UI 引用（用于动画目标位置）
var _bank_label: Label = null
var _player_panel = null  # LeftPanel

func start(settlement_data: Dictionary, state: GameState, scene: Node, map_canvas, bank_label: Label, player_panel) -> void:
	_game_state = state
	_scene = scene
	_map_canvas = map_canvas
	_bank_label = bank_label
	_player_panel = player_panel
	_speed = float(Globals.animation_speed) if Globals != null else 1.0

	_orders = DinnerTimeOverlayClass.build_orders_from_settlement(settlement_data)
	_current_idx = 0

	# 计算结算前银行值（当前值 + 所有订单收入总和）
	var total_revenue := 0
	for o in _orders:
		total_revenue += int(o.get("revenue", 0))
	_running_bank_value = int(state.bank.get("total", 0)) + total_revenue
	if is_instance_valid(_bank_label):
		_bank_label.text = "$%d" % _running_bank_value

	# 计算结算前各玩家现金（当前值 - 该玩家所有订单收入）
	_player_running_cash.clear()
	if state.players is Array:
		for i in range(state.players.size()):
			var p: Dictionary = state.players[i] if state.players[i] is Dictionary else {}
			_player_running_cash[i] = int(p.get("cash", 0))
		for o in _orders:
			if bool(o.get("is_skipped", false)):
				continue
			var oid := int(o.get("winner_owner", -1))
			if oid >= 0 and _player_running_cash.has(oid):
				_player_running_cash[oid] -= int(o.get("revenue", 0))
	_apply_cash_overrides()

	_ensure_skin()
	_load_coin_texture()
	_create_anim_layer()
	_create_map_anim_layer()
	_create_control_bar()
	_state = State.PLAYING
	_started_preview = false
	_stop_layout_monitor()
	_stop_layout_start_wait()

	if _orders.is_empty():
		_finish()
		return
	# 等待 MapView auto-fit/zoom 应用完毕（避免 token/highlight 因 cell_size 变化而错位/缩放异常）。
	_layout_last_cell_size = int(_get_cell_size())
	_layout_last_origin = Vector2i.ZERO
	if _map_canvas != null and is_instance_valid(_map_canvas) and _map_canvas.has_method("get_world_origin"):
		var ov = _map_canvas.get_world_origin()
		if ov is Vector2i:
			_layout_last_origin = ov
	_layout_stable_ticks = 0
	_layout_wait_ticks = 0
	_start_when_layout_stable()

func _start_when_layout_stable() -> void:
	if _layout_start_wait_running:
		return
	_layout_start_wait_running = true
	while true:
		if _state != State.PLAYING or _started_preview:
			_layout_start_wait_running = false
			return
		if _scene == null or not is_instance_valid(_scene) or _map_canvas == null or not is_instance_valid(_map_canvas):
			_layout_start_wait_running = false
			return

		var cs := int(_get_cell_size())
		var origin := _get_world_origin()

		if cs != _layout_last_cell_size or origin != _layout_last_origin:
			_layout_last_cell_size = cs
			_layout_last_origin = origin
			_layout_stable_ticks = 0
		else:
			_layout_stable_ticks += 1

		_layout_wait_ticks += 1
		var index_ready := _is_structure_index_ready_for_orders()
		if (_layout_stable_ticks >= 4 and index_ready) or _layout_wait_ticks >= 40:
			_spawn_persistent_demand_tokens()
			_preview_current()
			_started_preview = true
			_start_layout_monitor()
			_layout_start_wait_running = false
			return

		var tree := _scene.get_tree()
		if tree == null:
			_layout_start_wait_running = false
			return
		await tree.process_frame

func _is_structure_index_ready_for_orders() -> bool:
	if _map_canvas == null or not is_instance_valid(_map_canvas):
		return false
	var by_anchor_val = _map_canvas.get("_structures_by_anchor")
	if not (by_anchor_val is Dictionary):
		return false
	var by_anchor: Dictionary = by_anchor_val
	if by_anchor.is_empty():
		return false

	var required: Dictionary = {}
	for order in _orders:
		if bool(order.get("is_skipped", false)):
			continue
		var hid := str(order.get("house_id", "")).strip_edges()
		if not hid.is_empty():
			required[hid] = true
	if required.is_empty():
		return true

	var present: Dictionary = {}
	for k in by_anchor.keys():
		var info_val = by_anchor.get(k, null)
		if not (info_val is Dictionary):
			continue
		var info: Dictionary = info_val
		var hid2 := str(info.get("house_id", "")).strip_edges()
		if not hid2.is_empty():
			present[hid2] = true

	for hid3 in required.keys():
		if not present.has(hid3):
			return false

	return true

func skip_all() -> void:
	_kill_all_tweens()
	_finish()

func advance() -> void:
	if _state != State.PLAYING or not _previewing:
		return
	if _current_idx >= _orders.size():
		_finish()
		return
	_previewing = false
	var order: Dictionary = _orders[_current_idx]
	_current_idx += 1
	_update_control_bar()
	_play_sale_animation(order)

func set_auto_play(enabled: bool) -> void:
	_auto_play = enabled
	if _auto_play and _state == State.PLAYING and _previewing:
		advance()

func dispose() -> void:
	_stop_layout_monitor()
	_stop_layout_start_wait()
	_kill_all_tweens()
	_remove_highlight()
	_house_tokens.clear()
	_clear_cash_overrides()
	if is_instance_valid(_anim_layer):
		_anim_layer.queue_free()
	_anim_layer = null
	if is_instance_valid(_map_anim_layer):
		_map_anim_layer.queue_free()
	_map_anim_layer = null
	if is_instance_valid(_control_bar):
		_control_bar.queue_free()
	_control_bar = null
	_scene = null
	_map_canvas = null
	_game_state = null
	_bank_label = null
	_player_panel = null

# === 内部方法 ===

func _create_anim_layer() -> void:
	if _scene == null:
		return
	_anim_layer = Control.new()
	_anim_layer.name = "DinnertimeAnimLayer"
	_anim_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_anim_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_anim_layer.z_as_relative = false
	_anim_layer.z_index = 1100
	_scene.add_child(_anim_layer)

func _create_map_anim_layer() -> void:
	if _map_canvas == null or not is_instance_valid(_map_canvas):
		return
	if not (_map_canvas is Control):
		return
	_map_anim_layer = Control.new()
	_map_anim_layer.name = "DinnertimeMapAnimLayer"
	_map_anim_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_map_anim_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map_anim_layer.z_as_relative = false
	_map_anim_layer.z_index = 1100
	(_map_canvas as Control).add_child(_map_anim_layer)

func _create_control_bar() -> void:
	if _scene == null:
		return
	_control_bar = _build_control_bar()
	_control_bar.z_as_relative = false
	_control_bar.z_index = 1150
	_scene.add_child(_control_bar)
	_update_control_bar()

func _build_control_bar() -> PanelContainer:
	var bar := PanelContainer.new()
	bar.name = "DinnertimeControlBar"
	bar.anchor_left = 0.5
	bar.anchor_right = 0.5
	bar.anchor_top = 1.0
	bar.anchor_bottom = 1.0
	bar.offset_left = -200
	bar.offset_right = 200
	bar.offset_top = -56
	bar.offset_bottom = -8

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.10, 0.08, 0.88)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(8)
	bar.add_theme_stylebox_override("panel", style)

	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 12)
	bar.add_child(hbox)

	var progress := Label.new()
	progress.name = "ProgressLabel"
	progress.add_theme_font_size_override("font_size", 14)
	progress.add_theme_color_override("font_color", Color(0.9, 0.85, 0.7, 1))
	progress.text = "晚餐结算"
	hbox.add_child(progress)

	var next_btn := Button.new()
	next_btn.name = "NextBtn"
	next_btn.text = "下一笔"
	next_btn.custom_minimum_size = Vector2(80, 32)
	UiStylesClass.apply_button_primary(next_btn)
	next_btn.pressed.connect(_on_next_pressed)
	hbox.add_child(next_btn)

	var skip_btn := Button.new()
	skip_btn.name = "SkipBtn"
	skip_btn.text = "跳过全部"
	skip_btn.custom_minimum_size = Vector2(80, 32)
	UiStylesClass.apply_button_secondary(skip_btn)
	skip_btn.pressed.connect(skip_all)
	hbox.add_child(skip_btn)

	return bar

func _update_control_bar() -> void:
	if not is_instance_valid(_control_bar):
		return
	var lbl: Label = _control_bar.find_child("ProgressLabel", true, false)
	if lbl != null:
		lbl.text = "晚餐结算 (%d/%d)" % [_current_idx, _orders.size()]
	var btn: Button = _control_bar.find_child("NextBtn", true, false)
	if btn != null:
		if _current_idx >= _orders.size() and not _previewing:
			btn.text = "确认结算"
			btn.disabled = false
		elif _previewing:
			btn.text = "下一笔"
			btn.disabled = false
		else:
			btn.text = "播放中…"
			btn.disabled = true

func _on_next_pressed() -> void:
	if _current_idx >= _orders.size() and not _previewing:
		skip_all()
	else:
		advance()

func _preview_current() -> void:
	# 跳过所有 skipped 订单，放置持久 × 标记
	while _current_idx < _orders.size():
		var order: Dictionary = _orders[_current_idx]
		if not bool(order.get("is_skipped", false)):
			break
		_place_persistent_x_mark(order)
		_current_idx += 1

	if _current_idx >= _orders.size():
		_update_control_bar()
		return

	_highlight_house(_orders[_current_idx])
	_previewing = true
	_update_control_bar()
	if _auto_play:
		advance()

func _highlight_house(order: Dictionary) -> void:
	_remove_highlight()
	if not is_instance_valid(_map_anim_layer):
		return
	var house_id := str(order.get("house_id", ""))
	_current_house_id = house_id
	_preview_tokens.clear()
	var rects := _compute_house_rects_from_order(order)
	var has_garden := bool(rects.get("has_garden", false))
	var house_rect: Rect2 = rects.get("house_rect", Rect2())
	var structure_rect: Rect2 = rects.get("structure_rect", Rect2())

	_start_route_highlight_for_order(order)

	var highlight_rect := house_rect
	if has_garden and structure_rect.size != Vector2.ZERO:
		highlight_rect = structure_rect
	if highlight_rect.size == Vector2.ZERO:
		highlight_rect = structure_rect

	_highlight_ring = Control.new()
	_highlight_ring.position = highlight_rect.position
	_highlight_ring.size = highlight_rect.size
	_highlight_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map_anim_layer.add_child(_highlight_ring)
	# 确保高亮在最底层（token/红叉应盖在高亮上）
	if _map_anim_layer.get_child_count() > 1:
		_map_anim_layer.move_child(_highlight_ring, 0)

	var ring := ColorRect.new()
	ring.color = Color(1.0, 0.85, 0.2, 0.35)
	ring.set_anchors_preset(Control.PRESET_FULL_RECT)
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_highlight_ring.add_child(ring)

	var tween := ring.create_tween().set_loops()
	tween.tween_property(ring, "modulate:a", 0.5, 0.5)
	tween.tween_property(ring, "modulate:a", 1.0, 0.5)

	# 预先已生成的 token：直接引用；否则即时生成（回放/异常情况下兜底）。
	if _house_tokens.has(house_id) and (_house_tokens[house_id] is Array):
		var arr: Array = _house_tokens[house_id]
		for n in arr:
			if n is Control and is_instance_valid(n):
				_preview_tokens.append(n)
	else:
		var created := _create_demand_token_nodes(order, house_id, house_rect, structure_rect, has_garden)
		if not created.is_empty():
			_house_tokens[house_id] = created.duplicate()
			for n2 in created:
				if n2 is Control and is_instance_valid(n2):
					_preview_tokens.append(n2)

	var restaurant_rect := _compute_restaurant_rect_from_order(order)
	if restaurant_rect.size != Vector2.ZERO:
		var restaurant_tokens := _create_restaurant_demand_token_nodes(order, restaurant_rect)
		for n3 in restaurant_tokens:
			if n3 is Control and is_instance_valid(n3):
				_preview_tokens.append(n3)

func _get_house_structure_index_info(house_id: String) -> Dictionary:
	if house_id.is_empty():
		return {}
	if _map_canvas == null or not is_instance_valid(_map_canvas):
		return {}
	var by_anchor_val = _map_canvas.get("_structures_by_anchor")
	if not (by_anchor_val is Dictionary):
		return {}
	var by_anchor: Dictionary = by_anchor_val
	for anchor_val in by_anchor.keys():
		if not (anchor_val is Vector2i):
			continue
		var info_val = by_anchor.get(anchor_val, null)
		if not (info_val is Dictionary):
			continue
		var info: Dictionary = info_val
		if str(info.get("house_id", "")) != house_id:
			continue
		return {"anchor": Vector2i(anchor_val), "info": info}
	return {}

func _compute_structure_rect_from_index(cell_size: float, info: Dictionary) -> Rect2:
	var min_pos_val = info.get("min", null)
	var max_pos_val = info.get("max", null)
	if not (min_pos_val is Vector2i) or not (max_pos_val is Vector2i):
		return Rect2()
	var min_pos: Vector2i = min_pos_val
	var max_pos: Vector2i = max_pos_val
	var size_cells := (max_pos - min_pos) + Vector2i.ONE
	return Rect2(
		Vector2(float(min_pos.x) * cell_size, float(min_pos.y) * cell_size),
		Vector2(float(size_cells.x) * cell_size, float(size_cells.y) * cell_size)
	)

func _compute_house_rect_from_anchor(cell_size: float, anchor: Vector2i, rotation: int) -> Rect2:
	if anchor == Vector2i(-1, -1):
		return Rect2()
	var origin := Vector2i.ZERO
	if _map_canvas != null and is_instance_valid(_map_canvas) and _map_canvas.has_method("get_world_origin"):
		var ov = _map_canvas.get_world_origin()
		if ov is Vector2i:
			origin = ov

	var house_mask := [[1, 1], [1, 1]]
	var house_cells_world: Array[Vector2i] = MapUtilsClass.get_footprint_cells(house_mask, Vector2i.ZERO, anchor, rotation)
	if house_cells_world.is_empty():
		return Rect2()

	var hmin := Vector2i(2147483647, 2147483647)
	var hmax := Vector2i(-2147483648, -2147483648)
	for wpos in house_cells_world:
		var vpos: Vector2i = wpos - origin
		hmin.x = min(hmin.x, vpos.x)
		hmin.y = min(hmin.y, vpos.y)
		hmax.x = max(hmax.x, vpos.x)
		hmax.y = max(hmax.y, vpos.y)
	var hsize_cells := (hmax - hmin) + Vector2i.ONE
	return Rect2(
		Vector2(float(hmin.x) * cell_size, float(hmin.y) * cell_size),
		Vector2(float(hsize_cells.x) * cell_size, float(hsize_cells.y) * cell_size)
	)

func _remove_highlight() -> void:
	for token in _preview_tokens:
		if not (token is Control) or not is_instance_valid(token):
			continue
		var ctrl: Control = token
		if ctrl.has_meta("show_on_float_only") and bool(ctrl.get_meta("show_on_float_only")):
			ctrl.queue_free()
	_preview_tokens.clear()
	_clear_route_highlight()
	if is_instance_valid(_highlight_ring):
		_highlight_ring.queue_free()
	_highlight_ring = null

func _spawn_persistent_demand_tokens() -> void:
	if not is_instance_valid(_map_anim_layer) or _skin == null:
		return
	_house_tokens.clear()
	var remaining_houses := _build_remaining_house_id_set()
	if remaining_houses.is_empty():
		return
	var seen: Dictionary = {}
	for order in _orders:
		if bool(order.get("is_skipped", false)):
			continue
		var house_id := str(order.get("house_id", ""))
		if house_id.is_empty() or seen.has(house_id):
			continue
		if not remaining_houses.has(house_id):
			continue
		seen[house_id] = true
		# 与 _highlight_house 保持一致的 rect 计算路径
		var rects := _compute_house_rects_from_order(order)
		var house_rect: Rect2 = rects.get("house_rect", Rect2())
		var structure_rect: Rect2 = rects.get("structure_rect", Rect2())
		var has_garden := bool(rects.get("has_garden", false))
		var created := _create_demand_token_nodes(order, house_id, house_rect, structure_rect, has_garden)
		if not created.is_empty():
			_house_tokens[house_id] = created

func _build_remaining_house_id_set() -> Dictionary:
	var out: Dictionary = {}
	var start_idx := clampi(_current_idx, 0, _orders.size())
	for i in range(start_idx, _orders.size()):
		var order: Dictionary = _orders[i]
		if bool(order.get("is_skipped", false)):
			continue
		var house_id := str(order.get("house_id", "")).strip_edges()
		if house_id.is_empty():
			continue
		out[house_id] = true
	return out

func _start_layout_monitor() -> void:
	if _layout_monitor_running:
		return
	_layout_monitor_running = true
	_layout_monitor_cell_size = int(_get_cell_size())
	_layout_monitor_origin = _get_world_origin()
	_monitor_layout_during_playback()

func _stop_layout_monitor() -> void:
	_layout_monitor_running = false

func _stop_layout_start_wait() -> void:
	_layout_start_wait_running = false

func _monitor_layout_during_playback() -> void:
	while _layout_monitor_running:
		if _state != State.PLAYING:
			_layout_monitor_running = false
			return
		if _map_canvas == null or not is_instance_valid(_map_canvas):
			_layout_monitor_running = false
			return

		var cs := int(_get_cell_size())
		var origin := _get_world_origin()
		if cs != _layout_monitor_cell_size or origin != _layout_monitor_origin:
			_layout_monitor_cell_size = cs
			_layout_monitor_origin = origin
			_on_map_layout_changed()

		if _scene == null or not is_instance_valid(_scene):
			_layout_monitor_running = false
			return
		var tree := _scene.get_tree()
		if tree == null:
			_layout_monitor_running = false
			return
		await tree.process_frame

func _on_map_layout_changed() -> void:
	if not is_instance_valid(_map_anim_layer):
		return
	if not _active_tweens.is_empty():
		return
	_rebuild_preview_layout_for_current_map()

func _rebuild_preview_layout_for_current_map() -> void:
	_remove_highlight()
	_clear_house_token_nodes()
	_spawn_persistent_demand_tokens()

	if _previewing and _current_idx >= 0 and _current_idx < _orders.size():
		var current_order: Dictionary = _orders[_current_idx]
		if not bool(current_order.get("is_skipped", false)):
			_highlight_house(current_order)

func _clear_house_token_nodes() -> void:
	for hid in _house_tokens.keys():
		var arr_val = _house_tokens.get(hid, null)
		if not (arr_val is Array):
			continue
		var arr: Array = arr_val
		for n in arr:
			if n is Control and is_instance_valid(n):
				n.queue_free()
	_house_tokens.clear()
	_preview_tokens.clear()

func _compute_house_rects_from_order(order: Dictionary) -> Dictionary:
	var house_id := str(order.get("house_id", ""))
	var cell_size := maxf(_get_cell_size(), 1.0)
	var has_garden := bool(order.get("has_garden", false))
	var house_rect := Rect2()
	var structure_rect := Rect2()

	var si := _get_house_structure_index_info(house_id)
	if not si.is_empty():
		var anchor: Vector2i = si.get("anchor", Vector2i(-1, -1))
		var info_val = si.get("info", null)
		if anchor != Vector2i(-1, -1) and (info_val is Dictionary):
			var info: Dictionary = info_val
			var piece_id := str(info.get("piece_id", "")).strip_edges()
			var rotation := int(info.get("rotation", 0))
			structure_rect = _compute_structure_rect_from_index(cell_size, info)
			house_rect = _compute_house_rect_from_anchor(cell_size, anchor, rotation)
			if piece_id == "house_with_garden":
				has_garden = true
			elif piece_id == "house":
				has_garden = false

	if house_rect.size == Vector2.ZERO:
		var anchor2 := OverlayUtilsClass.get_house_anchor_world_pos(_game_state, house_id)
		if anchor2 != Vector2i(-1, -1):
			has_garden = has_garden or _get_structure_piece_id_at(anchor2) == "house_with_garden"

		var house_cells := _get_house_core_cells(house_id)
		if house_cells.is_empty():
			house_cells = OverlayUtilsClass.get_house_footprint_cells(_game_state, house_id)
		var structure_cells := OverlayUtilsClass.get_house_footprint_cells(_game_state, house_id)
		house_rect = _get_piece_canvas_rect(house_cells)
		structure_rect = house_rect
		if not structure_cells.is_empty():
			structure_rect = _get_piece_canvas_rect(structure_cells)

	# 最后兜底：存档可能没有 house.anchor_pos/cells；直接从 map.cells 扫描 structure.house_id。
	if house_rect.size == Vector2.ZERO:
		var scanned := _compute_house_rects_from_map_cells(house_id, cell_size)
		if not scanned.is_empty():
			house_rect = scanned.get("house_rect", Rect2())
			structure_rect = scanned.get("structure_rect", house_rect)
			has_garden = bool(scanned.get("has_garden", has_garden))

	return {
		"house_rect": house_rect,
		"structure_rect": structure_rect,
		"has_garden": has_garden,
	}

func _compute_house_rects_from_map_cells(house_id: String, cell_size: float) -> Dictionary:
	if house_id.is_empty() or _game_state == null:
		return {}
	if not (_game_state.map is Dictionary):
		return {}
	if _map_canvas == null or not is_instance_valid(_map_canvas):
		return {}

	var map: Dictionary = _game_state.map
	var map_origin := Vector2i.ZERO
	var origin_val = map.get("map_origin", null)
	if origin_val is Vector2i:
		map_origin = origin_val

	var cells_val = map.get("cells", null)
	if not (cells_val is Array):
		return {}
	var cells: Array = cells_val

	var world_origin := Vector2i.ZERO
	if _map_canvas.has_method("get_world_origin"):
		var wo = _map_canvas.get_world_origin()
		if wo is Vector2i:
			world_origin = wo

	var found_any := false
	var vmin := Vector2i(2147483647, 2147483647)
	var vmax := Vector2i(-2147483648, -2147483648)
	var anchor := Vector2i(-1, -1)
	var rotation := 0
	var piece_id := ""
	var has_garden := false

	for y in range(cells.size()):
		var row_val = cells[y]
		if not (row_val is Array):
			continue
		var row: Array = row_val
		for x in range(row.size()):
			var cell_val = row[x]
			if not (cell_val is Dictionary):
				continue
			var cell: Dictionary = cell_val
			var s_val = cell.get("structure", null)
			if not (s_val is Dictionary):
				continue
			var structure: Dictionary = s_val
			if str(structure.get("house_id", "")).strip_edges() != house_id:
				continue

			found_any = true
			var world_pos := Vector2i(x, y) - map_origin
			var view_pos := world_pos - world_origin
			vmin.x = min(vmin.x, view_pos.x)
			vmin.y = min(vmin.y, view_pos.y)
			vmax.x = max(vmax.x, view_pos.x)
			vmax.y = max(vmax.y, view_pos.y)

			if anchor == Vector2i(-1, -1):
				var a_val = structure.get("parent_anchor", null)
				if a_val is Vector2i:
					anchor = a_val
				var r_val = structure.get("rotation", null)
				if r_val is int:
					rotation = int(r_val)
				elif r_val is float:
					var f: float = float(r_val)
					if f == floor(f):
						rotation = int(f)
				piece_id = str(structure.get("piece_id", "")).strip_edges()
				var hg_val = structure.get("has_garden", null)
				if hg_val is bool:
					has_garden = bool(hg_val)

	if not found_any:
		return {}

	var size_cells := (vmax - vmin) + Vector2i.ONE
	var structure_rect := Rect2(Vector2(float(vmin.x) * cell_size, float(vmin.y) * cell_size), Vector2(float(size_cells.x) * cell_size, float(size_cells.y) * cell_size))
	if piece_id == "house_with_garden":
		has_garden = true
	elif piece_id == "house":
		has_garden = false

	var house_rect := Rect2()
	if anchor != Vector2i(-1, -1):
		var house_mask := [[1, 1], [1, 1]]
		var house_cells_world: Array[Vector2i] = MapUtilsClass.get_footprint_cells(house_mask, Vector2i.ZERO, anchor, rotation)
		if not house_cells_world.is_empty():
			var hmin := Vector2i(2147483647, 2147483647)
			var hmax := Vector2i(-2147483648, -2147483648)
			for wpos in house_cells_world:
				var vpos: Vector2i = wpos - world_origin
				hmin.x = min(hmin.x, vpos.x)
				hmin.y = min(hmin.y, vpos.y)
				hmax.x = max(hmax.x, vpos.x)
				hmax.y = max(hmax.y, vpos.y)
			var hsize_cells := (hmax - hmin) + Vector2i.ONE
			house_rect = Rect2(
				Vector2(float(hmin.x) * cell_size, float(hmin.y) * cell_size),
				Vector2(float(hsize_cells.x) * cell_size, float(hsize_cells.y) * cell_size)
			)

	if house_rect.size == Vector2.ZERO:
		house_rect = structure_rect

	return {
		"house_rect": house_rect,
		"structure_rect": structure_rect,
		"has_garden": has_garden,
	}

func _create_demand_token_nodes(order: Dictionary, house_id: String, house_rect: Rect2, structure_rect: Rect2, has_garden: bool) -> Array[Control]:
	var out: Array[Control] = []
	if not is_instance_valid(_map_anim_layer) or _skin == null:
		return out
	var demands_val = order.get("demands", null)
	if not (demands_val is Dictionary):
		return out
	var demands: Dictionary = demands_val
	if demands.is_empty():
		return out

	var cell_size := maxf(_get_cell_size(), 1.0)

	var product_ids: Array[String] = []
	for k in demands.keys():
		var count := int(demands.get(k, 0))
		if count <= 0:
			continue
		var pid := str(k)
		if pid == "cola":
			pid = "soda"
		for _i in range(count):
			product_ids.append(pid)
	if product_ids.is_empty():
		return out
	product_ids.sort()
	var draw_count: int = min(product_ids.size(), 6)
	var draw_product_ids: Array[String] = product_ids.slice(0, draw_count)

	var demand_key := ",".join(product_ids)
	var seed := _compute_demand_scatter_seed(house_id)
	seed = int((seed ^ _hash_string_32(demand_key)) & 0x7FFFFFFF)

	var reserved: Array[Rect2] = []
	var demand_area_rect := house_rect
	if has_garden and structure_rect.size != Vector2.ZERO:
		demand_area_rect = structure_rect
	if demand_area_rect.size == Vector2.ZERO:
		demand_area_rect = structure_rect

	var house_id_rect_target := house_rect if house_rect.size != Vector2.ZERO else demand_area_rect
	reserved.append(_compute_house_id_rect(cell_size, house_id_rect_target))

	var base_icon_size := cell_size * DEMAND_TOKEN_ICON_SCALE
	var base_min_spacing := maxf(1.0, cell_size * 0.04)

	var slots: Array[Rect2] = []
	var icon_size := base_icon_size
	var min_spacing := base_min_spacing
	var scales := [1.0, 0.86, 0.74, 0.62, 0.50]
	for scale in scales:
		icon_size = base_icon_size * float(scale)
		min_spacing = base_min_spacing * float(scale)
		var scatter_area_rect := demand_area_rect.grow(-cell_size * 0.05)
		slots = _build_demand_token_slots(scatter_area_rect, icon_size, min_spacing, reserved)
		if slots.size() < draw_count:
			slots = _build_demand_token_slots(demand_area_rect, icon_size, min_spacing, reserved)
		if slots.size() >= draw_count:
			break
	if slots.is_empty():
		return out
	var actual_draw_count: int = min(draw_count, slots.size())

	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	rng.state = int(seed)
	_shuffle_rect2_array(rng, slots)

	for i in range(actual_draw_count):
		var pid2: String = str(draw_product_ids[i])
		if pid2.is_empty():
			continue
		var tex: Texture2D = _skin.get_product_icon_texture(pid2)
		if tex == null:
			continue
		var rect := slots[i]
		var token := Control.new()
		token.set_anchors_preset(Control.PRESET_TOP_LEFT)
		token.position = rect.position
		token.size = rect.size
		token.custom_minimum_size = rect.size
		token.pivot_offset = rect.size * 0.5
		token.modulate = Color(1, 1, 1, 0.95)
		token.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_map_anim_layer.add_child(token)

		# 与 MapCanvasDrawer._draw_house_demands 保持一致：使用 aspect_fit 后的实际绘制矩形。
		var fit_rect := TextureUtilsClass.get_texture_aspect_fit_rect(tex, Rect2(Vector2.ZERO, rect.size))
		if fit_rect.size == Vector2.ZERO:
			fit_rect = Rect2(Vector2.ZERO, rect.size)

		var icon := TextureRect.new()
		icon.set_anchors_preset(Control.PRESET_TOP_LEFT)
		icon.position = fit_rect.position
		icon.size = fit_rect.size
		icon.custom_minimum_size = fit_rect.size
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_SCALE
		icon.texture = tex
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		token.add_child(icon)

		out.append(token)
	return out

func _create_restaurant_demand_token_nodes(order: Dictionary, restaurant_rect: Rect2) -> Array[Control]:
	var out: Array[Control] = []
	if not is_instance_valid(_map_anim_layer) or _skin == null:
		return out
	if restaurant_rect.size == Vector2.ZERO:
		return out
	var demands_val = order.get("demands", null)
	if not (demands_val is Dictionary):
		return out
	var demands: Dictionary = demands_val
	if demands.is_empty():
		return out

	var cell_size := maxf(_get_cell_size(), 1.0)

	var product_ids: Array[String] = []
	for k in demands.keys():
		var count := int(demands.get(k, 0))
		if count <= 0:
			continue
		var pid := str(k)
		if pid == "cola":
			pid = "soda"
		for _i in range(count):
			product_ids.append(pid)
	if product_ids.is_empty():
		return out
	product_ids.sort()
	var draw_count: int = min(product_ids.size(), 6)
	var draw_product_ids: Array[String] = product_ids.slice(0, draw_count)

	var house_id := str(order.get("house_id", ""))
	var restaurant_id := str(order.get("matched_restaurant", order.get("winner_restaurant_id", ""))).strip_edges()
	var demand_key := ",".join(product_ids)
	var seed := _compute_demand_scatter_seed("%s:%s:restaurant" % [house_id, restaurant_id])
	seed = int((seed ^ _hash_string_32(demand_key)) & 0x7FFFFFFF)

	var reserved: Array[Rect2] = []
	var base_icon_size := cell_size * DEMAND_TOKEN_ICON_SCALE
	var base_min_spacing := maxf(1.0, cell_size * 0.04)

	var slots: Array[Rect2] = []
	var icon_size := base_icon_size
	var min_spacing := base_min_spacing
	var scales := [1.0, 0.86, 0.74, 0.62, 0.50]
	for scale in scales:
		icon_size = base_icon_size * float(scale)
		min_spacing = base_min_spacing * float(scale)
		var scatter_area_rect := restaurant_rect.grow(-cell_size * 0.08)
		slots = _build_demand_token_slots(scatter_area_rect, icon_size, min_spacing, reserved)
		if slots.size() < draw_count:
			slots = _build_demand_token_slots(restaurant_rect, icon_size, min_spacing, reserved)
		if slots.size() >= draw_count:
			break
	if slots.is_empty():
		return out
	var actual_draw_count: int = min(draw_count, slots.size())

	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	rng.state = int(seed)
	_shuffle_rect2_array(rng, slots)

	for i in range(actual_draw_count):
		var pid2: String = str(draw_product_ids[i])
		if pid2.is_empty():
			continue
		var tex: Texture2D = _skin.get_product_icon_texture(pid2)
		if tex == null:
			continue
		var rect := slots[i]
		var token := Control.new()
		token.set_anchors_preset(Control.PRESET_TOP_LEFT)
		token.position = rect.position
		token.size = rect.size
		token.custom_minimum_size = rect.size
		token.pivot_offset = rect.size * 0.5
		token.modulate = Color(1, 1, 1, 0.95)
		token.visible = false
		token.set_meta("show_on_float_only", true)
		token.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_map_anim_layer.add_child(token)

		var fit_rect := TextureUtilsClass.get_texture_aspect_fit_rect(tex, Rect2(Vector2.ZERO, rect.size))
		if fit_rect.size == Vector2.ZERO:
			fit_rect = Rect2(Vector2.ZERO, rect.size)

		var icon := TextureRect.new()
		icon.set_anchors_preset(Control.PRESET_TOP_LEFT)
		icon.position = fit_rect.position
		icon.size = fit_rect.size
		icon.custom_minimum_size = fit_rect.size
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_SCALE
		icon.texture = tex
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		token.add_child(icon)

		out.append(token)
	return out

func _compute_restaurant_rect_from_order(order: Dictionary) -> Rect2:
	var restaurant_id := str(order.get("matched_restaurant", order.get("winner_restaurant_id", ""))).strip_edges()
	if restaurant_id.is_empty():
		return Rect2()
	var cells := _get_restaurant_cells(restaurant_id)
	if cells.is_empty():
		return Rect2()
	return _get_piece_canvas_rect(cells)

func _get_restaurant_cells(restaurant_id: String) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if restaurant_id.is_empty() or _game_state == null:
		return out
	if not (_game_state.map is Dictionary):
		return out
	var map: Dictionary = _game_state.map

	var restaurants_val = map.get("restaurants", null)
	if restaurants_val is Dictionary:
		var rest_val = (restaurants_val as Dictionary).get(restaurant_id, null)
		if rest_val is Dictionary:
			var rest: Dictionary = rest_val
			var cells_val = rest.get("cells", null)
			if cells_val is Array:
				for c in cells_val:
					if c is Vector2i:
						out.append(c)
	if not out.is_empty():
		return out

	var map_origin := Vector2i.ZERO
	var origin_val = map.get("map_origin", null)
	if origin_val is Vector2i:
		map_origin = origin_val

	var cells_rows_val = map.get("cells", null)
	if not (cells_rows_val is Array):
		return out
	var cells_rows: Array = cells_rows_val

	var seen: Dictionary = {}
	for y in range(cells_rows.size()):
		var row_val = cells_rows[y]
		if not (row_val is Array):
			continue
		var row: Array = row_val
		for x in range(row.size()):
			var cell_val = row[x]
			if not (cell_val is Dictionary):
				continue
			var cell: Dictionary = cell_val
			var s_val = cell.get("structure", null)
			if not (s_val is Dictionary):
				continue
			var structure: Dictionary = s_val
			if str(structure.get("restaurant_id", "")).strip_edges() != restaurant_id:
				continue
			var world_pos := Vector2i(x, y) - map_origin
			if not seen.has(world_pos):
				seen[world_pos] = true
				out.append(world_pos)

	return out

func _start_route_highlight_for_order(order: Dictionary) -> void:
	_clear_route_highlight()
	if not is_instance_valid(_map_anim_layer):
		return

	var path := _compute_route_path_for_order(order)
	if path.is_empty():
		return

	var cell_size := maxf(_get_cell_size(), 1.0)
	var origin := _get_world_origin()
	for world_pos in path:
		var view_pos := world_pos - origin
		var cell := ColorRect.new()
		cell.color = Color(0.15, 1.0, 0.85, 0.35)
		cell.modulate.a = ROUTE_FLASH_ALPHA_MIN
		cell.position = Vector2(float(view_pos.x) * cell_size, float(view_pos.y) * cell_size)
		cell.size = Vector2(cell_size, cell_size)
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_map_anim_layer.add_child(cell)
		_route_highlight_nodes.append(cell)

	if _route_highlight_nodes.is_empty():
		return

	_route_highlight_tween = _map_anim_layer.create_tween().set_loops()
	var flash_dur := maxf(0.08, 0.40 / _speed)
	_route_highlight_tween.tween_method(func(v: float):
		for n in _route_highlight_nodes:
			if n is ColorRect and is_instance_valid(n):
				(n as ColorRect).modulate.a = v
	, ROUTE_FLASH_ALPHA_MIN, ROUTE_FLASH_ALPHA_MAX, flash_dur).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	_route_highlight_tween.tween_method(func(v: float):
		for n in _route_highlight_nodes:
			if n is ColorRect and is_instance_valid(n):
				(n as ColorRect).modulate.a = v
	, ROUTE_FLASH_ALPHA_MAX, ROUTE_FLASH_ALPHA_MIN, flash_dur).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)

func _clear_route_highlight() -> void:
	if is_instance_valid(_route_highlight_tween):
		_route_highlight_tween.kill()
	_route_highlight_tween = null

	for n in _route_highlight_nodes:
		if n is Control and is_instance_valid(n):
			n.queue_free()
	_route_highlight_nodes.clear()

func _compute_route_path_for_order(order: Dictionary) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if _game_state == null:
		return out
	if bool(order.get("is_skipped", false)):
		return out
	if not (_game_state.map is Dictionary):
		return out

	var house_id := str(order.get("house_id", "")).strip_edges()
	var restaurant_id := str(order.get("matched_restaurant", order.get("winner_restaurant_id", ""))).strip_edges()
	if house_id.is_empty() or restaurant_id.is_empty():
		return out

	var road_graph = RoadGraphCacheClass.get_road_graph(_game_state)
	if road_graph == null:
		return out

	var map: Dictionary = _game_state.map
	var grid_size_val = map.get("grid_size", null)
	if not (grid_size_val is Vector2i):
		return out
	var grid_size: Vector2i = grid_size_val

	var house := StructuresClass.get_house(_game_state, house_id)
	var restaurant := StructuresClass.get_restaurant(_game_state, restaurant_id)
	if house.is_empty() or restaurant.is_empty():
		return out

	var dinnertime_distance = _get_dinnertime_distance_script()
	if dinnertime_distance == null:
		return out

	var route_read: Result = dinnertime_distance.get_restaurant_to_house_distance(
		road_graph,
		_game_state,
		grid_size,
		restaurant_id,
		restaurant,
		house_id,
		house
	)
	if not route_read.ok:
		return out
	if not (route_read.value is Dictionary):
		return out
	var route: Dictionary = route_read.value
	var path_val = route.get("path", null)
	if not (path_val is Array):
		return out

	for p in path_val:
		if p is Vector2i:
			out.append(p)

	return out

func _get_dinnertime_distance_script():
	if _dinnertime_distance_script != null:
		return _dinnertime_distance_script
	var base_dir := ModulesBaseDirClass.get_base_dir()
	if base_dir.is_empty():
		return null
	var script_path := base_dir.path_join("base_rules/rules/phase/dinnertime/dinnertime_distance.gd")
	var script_val = load(script_path)
	if script_val == null:
		return null
	_dinnertime_distance_script = script_val
	return _dinnertime_distance_script

func _hash_string_32(text: String) -> int:
	var h: int = 2166136261
	for i in range(text.length()):
		h ^= text.unicode_at(i)
		h = int((h * 16777619) & 0xFFFFFFFF)
	return h

func _compute_demand_scatter_seed(house_id: String) -> int:
	var seed := _hash_string_32(house_id)
	var state_seed := 0
	if _game_state != null:
		state_seed = int(_game_state.seed)
	return int((seed ^ state_seed) & 0x7FFFFFFF)

func _is_scatter_rect_free(candidate: Rect2, taken: Array[Rect2], min_spacing: float) -> bool:
	var grow := maxf(min_spacing, 0.0)
	var cand := candidate.grow(grow)
	for r in taken:
		if cand.intersects(r.grow(grow)):
			return false
	return true

func _shuffle_rect2_array(rng: RandomNumberGenerator, arr: Array[Rect2]) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := arr[i]
		arr[i] = arr[j]
		arr[j] = tmp

func _build_demand_token_slots(area: Rect2, icon_size: float, min_spacing: float, reserved: Array[Rect2]) -> Array[Rect2]:
	var margin := maxf(1.0, min_spacing)
	var min_x := area.position.x + margin
	var min_y := area.position.y + margin
	var max_x := area.position.x + area.size.x - icon_size - margin
	var max_y := area.position.y + area.size.y - icon_size - margin
	if max_x < min_x:
		max_x = min_x
	if max_y < min_y:
		max_y = min_y

	var step := maxf(icon_size + min_spacing, 1.0)
	var cols := maxi(1, int(floor(maxf(0.0, max_x - min_x) / step)) + 1)
	var rows := maxi(1, int(floor(maxf(0.0, max_y - min_y) / step)) + 1)

	var slots: Array[Rect2] = []
	for row in range(rows):
		for col in range(cols):
			var x := min_x + float(col) * step
			var y := min_y + float(row) * step
			x = clampf(x, min_x, max_x)
			y = clampf(y, min_y, max_y)
			var rect := Rect2(Vector2(x, y), Vector2(icon_size, icon_size))
			if _is_scatter_rect_free(rect, reserved, min_spacing):
				slots.append(rect)
	return slots

func _compute_house_id_rect(cell_size: float, structure_rect: Rect2) -> Rect2:
	var pad := maxf(3.0, cell_size * 0.10)
	var bg_size := Vector2(cell_size * 0.90, cell_size * 0.58)
	var pos := structure_rect.position + Vector2(structure_rect.size.x - bg_size.x - pad, pad)
	return Rect2(pos, bg_size)

func _get_house_core_cells(house_id: String) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if _game_state == null:
		return out
	var anchor := OverlayUtilsClass.get_house_anchor_world_pos(_game_state, house_id)
	if anchor == Vector2i(-1, -1):
		return out
	var rotation := _get_structure_rotation_at(anchor)
	var house_mask := [[1, 1], [1, 1]]
	return MapUtilsClass.get_footprint_cells(house_mask, Vector2i.ZERO, anchor, rotation)

func _get_structure_rotation_at(world_anchor: Vector2i) -> int:
	if _game_state == null or not (_game_state.map is Dictionary):
		return 0
	var map: Dictionary = _game_state.map

	var map_origin := Vector2i.ZERO
	var origin_val = map.get("map_origin", null)
	if origin_val is Vector2i:
		map_origin = origin_val

	var cells_val = map.get("cells", null)
	if not (cells_val is Array):
		return 0
	var cells: Array = cells_val
	var idx := world_anchor + map_origin
	if idx.y < 0 or idx.y >= cells.size():
		return 0
	var row_val = cells[idx.y]
	if not (row_val is Array):
		return 0
	var row: Array = row_val
	if idx.x < 0 or idx.x >= row.size():
		return 0
	var cell_val = row[idx.x]
	if not (cell_val is Dictionary):
		return 0
	var cell: Dictionary = cell_val
	var s_val = cell.get("structure", null)
	if not (s_val is Dictionary):
		return 0
	var structure: Dictionary = s_val
	var r_val = structure.get("rotation", 0)
	if r_val is int:
		return int(r_val)
	if r_val is float:
		var f: float = float(r_val)
		if f == floor(f):
			return int(f)
	return 0

func _get_structure_piece_id_at(world_anchor: Vector2i) -> String:
	if _game_state == null or not (_game_state.map is Dictionary):
		return ""
	var map: Dictionary = _game_state.map

	var map_origin := Vector2i.ZERO
	var origin_val = map.get("map_origin", null)
	if origin_val is Vector2i:
		map_origin = origin_val

	var cells_val = map.get("cells", null)
	if not (cells_val is Array):
		return ""
	var cells: Array = cells_val
	var idx := world_anchor + map_origin
	if idx.y < 0 or idx.y >= cells.size():
		return ""
	var row_val = cells[idx.y]
	if not (row_val is Array):
		return ""
	var row: Array = row_val
	if idx.x < 0 or idx.x >= row.size():
		return ""
	var cell_val = row[idx.x]
	if not (cell_val is Dictionary):
		return ""
	var cell: Dictionary = cell_val
	var s_val = cell.get("structure", null)
	if not (s_val is Dictionary):
		return ""
	var structure: Dictionary = s_val
	return str(structure.get("piece_id", "")).strip_edges()

func _place_persistent_x_mark(order: Dictionary) -> void:
	if not is_instance_valid(_map_anim_layer):
		return
	var house_id := str(order.get("house_id", ""))
	var cell_size := maxf(_get_cell_size(), 1.0)
	var rect := Rect2()
	var si := _get_house_structure_index_info(house_id)
	if not si.is_empty():
		var anchor: Vector2i = si.get("anchor", Vector2i(-1, -1))
		var info_val = si.get("info", null)
		if anchor != Vector2i(-1, -1) and (info_val is Dictionary):
			var info: Dictionary = info_val
			rect = _compute_structure_rect_from_index(cell_size, info)
			if rect.size == Vector2.ZERO:
				var rotation := int(info.get("rotation", 0))
				rect = _compute_house_rect_from_anchor(cell_size, anchor, rotation)

	if rect.size == Vector2.ZERO:
		var cells := _get_house_core_cells(house_id)
		if cells.is_empty():
			cells = OverlayUtilsClass.get_house_footprint_cells(_game_state, house_id)
		rect = _get_piece_canvas_rect(cells)
	var pos := rect.position + rect.size * 0.5
	var fs := int(round(maxf(46.0, cell_size * 1.25)))
	var box := Vector2(float(fs) * 1.15, float(fs) * 1.15)

	var shadow := Label.new()
	shadow.text = "✕"
	shadow.add_theme_font_size_override("font_size", fs)
	shadow.add_theme_color_override("font_color", Color(0, 0, 0, 0.75))
	shadow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	shadow.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	shadow.size = box
	shadow.position = pos - box * 0.5 + Vector2(3, 3)
	shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map_anim_layer.add_child(shadow)

	var mark := Label.new()
	mark.text = "✕"
	mark.add_theme_font_size_override("font_size", fs)
	mark.add_theme_color_override("font_color", Color(0.95, 0.25, 0.18, 1))
	mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mark.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	mark.size = box
	mark.position = pos - box * 0.5
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map_anim_layer.add_child(mark)

func _play_sale_animation(sale: Dictionary) -> void:
	var owner_id := int(sale.get("winner_owner", -1))
	var revenue := int(sale.get("revenue", 0))
	var house_id := str(sale.get("house_id", ""))
	_current_house_id = house_id
	_house_tokens.erase(house_id)

	if not is_instance_valid(_anim_layer):
		_preview_current()
		return

	var dur_float := 1.5 / _speed
	var dur_fly := 0.80 / _speed
	var coin_count := _compute_coin_count(revenue)
	var coin_delay_step := 0.0
	if coin_count > 1:
		var start_spread := dur_fly * 0.55
		coin_delay_step = start_spread / float(coin_count - 1)
		coin_delay_step = clampf(coin_delay_step, 0.04 / _speed, 0.14 / _speed)
	var dur_fly_total := dur_fly + float(maxi(0, coin_count - 1)) * coin_delay_step

	# 步骤1: 预览 token 向上漂浮消失
	_float_away_preview_tokens(dur_float)

	# 步骤3: 钱币从银行飞向左侧玩家概览卡 + 数字变化
	var bank_pos := _global_to_layer(_get_bank_label_global_center())
	var target_pos := _global_to_layer(_get_revenue_target_global_center(sale, owner_id))

	var tween := _anim_layer.create_tween()
	_active_tweens.append(tween)

	# 先完成 token 漂浮，再开始金币与数字变化。
	tween.tween_interval(dur_float)
	tween.tween_callback(func():
		_spawn_flying_coins(bank_pos, target_pos, revenue, owner_id, dur_fly, coin_delay_step, coin_count)
	)
	tween.tween_interval(dur_fly_total + 0.3 / _speed)
	tween.finished.connect(func():
		_active_tweens.erase(tween)
		_clear_route_highlight()
		_preview_current()
	)

func _float_away_preview_tokens(dur: float) -> void:
	for token in _preview_tokens:
		if not is_instance_valid(token):
			continue
		if token.has_meta("show_on_float_only") and bool(token.get_meta("show_on_float_only")):
			token.visible = true
			token.modulate = Color(1, 1, 1, 0.95)
		var tw := token.create_tween().set_parallel(true)
		_active_tweens.append(tw)
		var lift := maxf(60.0, _get_cell_size() * 1.8)
		tw.tween_property(token, "position:y", token.position.y - lift, dur).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		tw.tween_property(token, "modulate:a", 0.0, dur).set_ease(Tween.EASE_IN).set_delay(dur * 0.3)
		tw.tween_property(token, "scale", Vector2(0.3, 0.3), dur)
		tw.chain().tween_callback(func():
			if is_instance_valid(token):
				token.queue_free()
			_active_tweens.erase(tw)
		)
	_preview_tokens.clear()

func _compute_coin_count(revenue: int) -> int:
	var rev := int(revenue)
	if rev <= 0:
		return 0
	var extra := int(floor(float(rev) / float(COIN_PER_AMOUNT)))
	var count := COIN_BASE_COUNT + extra
	return clampi(count, COIN_BASE_COUNT, COIN_MAX_COUNT)

func _spawn_flying_coins(from: Vector2, to: Vector2, revenue: int, owner_id: int, dur: float, coin_delay_step: float, coin_count: int) -> void:
	if not is_instance_valid(_anim_layer):
		return
	if revenue <= 0:
		return
	var count := maxi(0, int(coin_count))
	if count <= 0:
		count = _compute_coin_count(revenue)
	var coin_size := COIN_BASE_SIZE * COIN_SIZE_SCALE
	var half := Vector2(coin_size * 0.5, coin_size * 0.5)

	var dir := to - from
	var dist := dir.length()
	if dist < 0.001:
		dir = Vector2(1, 0)
		dist = 1.0
	var arc_height := clampf(dist * 0.25, 36.0, 96.0)
	var start_tl_base := from - half
	var end_tl := to - half
	var ctrl_base := (start_tl_base + end_tl) * 0.5 + Vector2(0, -arc_height)

	for i in range(count):
		var delay := float(i) * coin_delay_step
		var start_tl := start_tl_base
		var ctrl := ctrl_base

		var coin_wrap := Control.new()
		coin_wrap.custom_minimum_size = Vector2(coin_size, coin_size)
		coin_wrap.size = Vector2(coin_size, coin_size)
		coin_wrap.pivot_offset = Vector2(coin_size * 0.5, coin_size * 0.5)
		coin_wrap.position = start_tl
		coin_wrap.modulate.a = 0.0
		coin_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_anim_layer.add_child(coin_wrap)

		if _coin_tex != null:
			var shadow := TextureRect.new()
			shadow.texture = _coin_tex
			shadow.custom_minimum_size = Vector2(coin_size, coin_size)
			shadow.size = Vector2(coin_size, coin_size)
			shadow.position = Vector2(1, 1)
			shadow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			shadow.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			shadow.modulate = Color(0, 0, 0, 0.25)
			shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
			coin_wrap.add_child(shadow)

			var coin := TextureRect.new()
			coin.texture = _coin_tex
			coin.custom_minimum_size = Vector2(coin_size, coin_size)
			coin.size = Vector2(coin_size, coin_size)
			coin.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			coin.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			coin.mouse_filter = Control.MOUSE_FILTER_IGNORE
			coin_wrap.add_child(coin)

		var flip_cycles := 1.0
		var flip_phase := float(i) * 0.45
		var base_rot := (float(i) - float(count - 1) * 0.5) * 0.06
		var fade_in_t := 0.12
		var fade_out_t := 0.10

		var tw := _anim_layer.create_tween()
		_active_tweens.append(tw)
		if delay > 0.0:
			tw.tween_interval(delay)

		tw.tween_method(func(t: float):
			if not is_instance_valid(coin_wrap):
				return

			var omt := 1.0 - t
			var pos := (start_tl * omt * omt) + (ctrl * 2.0 * omt * t) + (end_tl * t * t)
			coin_wrap.position = pos

			var c := cos(t * TAU * flip_cycles + flip_phase)
			var sx := lerpf(0.28, 1.0, absf(c))
			coin_wrap.scale = Vector2(sx, 1.0)
			coin_wrap.rotation = base_rot + sin(t * PI) * 0.08

			var a := 1.0
			if t < fade_in_t:
				a = clampf(t / fade_in_t, 0.0, 1.0)
			elif t > (1.0 - fade_out_t):
				a = clampf((1.0 - t) / fade_out_t, 0.0, 1.0)
			coin_wrap.modulate.a = a
		, 0.0, 1.0, dur).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)

		tw.tween_callback(func():
			if is_instance_valid(coin_wrap):
				coin_wrap.queue_free()
			_active_tweens.erase(tw)
		)

	# 数字动态变化
	var number_dur := maxf(0.01, dur + float(maxi(0, count - 1)) * coin_delay_step)
	_animate_bank_decrease(revenue, number_dur)
	_animate_player_income(owner_id, revenue, number_dur)

func _animate_bank_decrease(amount: int, dur: float) -> void:
	if not is_instance_valid(_bank_label):
		return
	var from_val := _running_bank_value
	_running_bank_value -= amount
	var to_val := _running_bank_value
	var d := maxf(0.01, float(dur))

	var tween := _bank_label.create_tween()
	_active_tweens.append(tween)
	tween.tween_method(func(v: float):
		if is_instance_valid(_bank_label):
			_bank_label.text = "$%d" % int(v)
	, float(from_val), float(to_val), d)
	tween.tween_callback(func():
		_active_tweens.erase(tween)
	)

func _animate_player_income(player_id: int, amount: int, dur: float) -> void:
	if amount <= 0:
		return
	# 滚动概览卡片上的现金数字
	var from_val := int(_player_running_cash.get(player_id, 0))
	_player_running_cash[player_id] = from_val + amount
	var to_val = _player_running_cash[player_id]
	if is_instance_valid(_anim_layer):
		var d := maxf(0.01, float(dur))
		var tw := _anim_layer.create_tween()
		_active_tweens.append(tw)
		tw.tween_method(func(v: float):
			_player_running_cash[player_id] = int(v)
			_apply_cash_overrides()
		, float(from_val), float(to_val), d)
		tw.tween_callback(func(): _active_tweens.erase(tw))

	# 浮动 +$X 标签
	if not is_instance_valid(_anim_layer):
		return
	var pos := _global_to_layer(_get_player_tab_global_center(player_id))
	var lbl := Label.new()
	lbl.text = "+$%d" % amount
	lbl.add_theme_font_size_override("font_size", 16)
	lbl.add_theme_color_override("font_color", Color(0.2, 0.8, 0.2, 1))
	lbl.position = pos - Vector2(20, 10)
	_anim_layer.add_child(lbl)
	var dur2 := 1.5 / _speed
	var tween := _anim_layer.create_tween().set_parallel(true)
	_active_tweens.append(tween)
	tween.tween_property(lbl, "position:y", lbl.position.y - 40, dur2)
	tween.tween_property(lbl, "modulate:a", 0.0, dur2).set_delay(dur2 * 0.5)
	tween.chain().tween_callback(func():
		lbl.queue_free()
		_active_tweens.erase(tween)
	)

func _finish() -> void:
	_state = State.DONE
	_stop_layout_monitor()
	_stop_layout_start_wait()
	_clear_cash_overrides()
	_remove_highlight()
	if is_instance_valid(_control_bar):
		_control_bar.queue_free()
	_control_bar = null
	_clear_anim_layer()
	_clear_map_anim_layer()
	settlement_completed.emit()

func _clear_anim_layer() -> void:
	if is_instance_valid(_anim_layer):
		for child in _anim_layer.get_children():
			child.queue_free()

func _clear_map_anim_layer() -> void:
	if is_instance_valid(_map_anim_layer):
		_clear_route_highlight()
		for child in _map_anim_layer.get_children():
			child.queue_free()
	_house_tokens.clear()
	_preview_tokens.clear()
	_current_house_id = ""

func _kill_all_tweens() -> void:
	for tween in _active_tweens:
		if is_instance_valid(tween):
			tween.kill()
	_active_tweens.clear()
	_clear_anim_layer()
	_clear_map_anim_layer()

func _world_to_screen(world_pos: Vector2i) -> Vector2:
	if world_pos == Vector2i(-1, -1) or _map_canvas == null or not is_instance_valid(_map_canvas):
		return Vector2(400, 300)
	var cs := int(_map_canvas.get_cell_size())
	var view = world_pos - _get_world_origin()
	var local_pos := Vector2(view) * float(cs) + Vector2(cs, cs) * 0.5
	return (_map_canvas as Control).global_position + local_pos

func _get_world_origin() -> Vector2i:
	if _map_canvas != null and is_instance_valid(_map_canvas) and _map_canvas.has_method("get_world_origin"):
		var ov = _map_canvas.get_world_origin()
		if ov is Vector2i:
			return ov
	return Vector2i.ZERO

func _get_cell_size() -> float:
	if _map_canvas != null and is_instance_valid(_map_canvas):
		return float(_map_canvas.get_cell_size())
	return 40.0

func _get_piece_screen_rect(cells: Array[Vector2i]) -> Rect2:
	if cells.is_empty() or _map_canvas == null or not is_instance_valid(_map_canvas):
		return Rect2(Vector2(400, 300), Vector2(40, 40))
	var cs := int(_map_canvas.get_cell_size())
	var origin: Vector2i = _get_world_origin()
	var base: Vector2 = (_map_canvas as Control).global_position
	var min_v := Vector2(INF, INF)
	var max_v := Vector2(-INF, -INF)
	for c in cells:
		var view := c - origin
		var tl := base + Vector2(view) * float(cs)
		var br := tl + Vector2(cs, cs)
		min_v = Vector2(minf(min_v.x, tl.x), minf(min_v.y, tl.y))
		max_v = Vector2(maxf(max_v.x, br.x), maxf(max_v.y, br.y))
	return Rect2(min_v, max_v - min_v)

func _get_piece_canvas_rect(cells: Array[Vector2i]) -> Rect2:
	if cells.is_empty() or _map_canvas == null or not is_instance_valid(_map_canvas):
		return Rect2()
	var cs := int(_map_canvas.get_cell_size())
	var origin: Vector2i = _get_world_origin()
	var min_v := Vector2(INF, INF)
	var max_v := Vector2(-INF, -INF)
	for c in cells:
		var view := c - origin
		var tl := Vector2(view) * float(cs)
		var br := tl + Vector2(cs, cs)
		min_v = Vector2(minf(min_v.x, tl.x), minf(min_v.y, tl.y))
		max_v = Vector2(maxf(max_v.x, br.x), maxf(max_v.y, br.y))
	return Rect2(min_v, max_v - min_v)

func _global_to_layer(global_pos: Vector2) -> Vector2:
	if is_instance_valid(_anim_layer):
		return global_pos - _anim_layer.global_position
	return global_pos

func _get_bank_label_global_center() -> Vector2:
	if is_instance_valid(_bank_label):
		return _bank_label.global_position + _bank_label.size * 0.5
	return Vector2(400, 30)

func _get_player_tab_global_center(player_id: int) -> Vector2:
	if _player_panel != null and is_instance_valid(_player_panel):
		var grid = _player_panel.get("overview_grid")
		if grid is Control and is_instance_valid(grid):
			for node in (grid as Control).get_children():
				if not (node is Control) or not is_instance_valid(node):
					continue
				var card: Control = node
				if card.has_meta("player_id") and int(card.get_meta("player_id")) == player_id:
					var cash: Label = card.find_child("CashLabel", true, false)
					if cash != null and is_instance_valid(cash):
						return cash.global_position + cash.size * 0.5
					return card.global_position + card.size * 0.5
			var cards = (grid as Control).get_children()
			if player_id >= 0 and player_id < cards.size():
				var card2 = cards[player_id]
				if card2 is Control and is_instance_valid(card2):
					var cash2: Label = (card2 as Control).find_child("CashLabel", true, false)
					if cash2 != null and is_instance_valid(cash2):
						return cash2.global_position + cash2.size * 0.5
					return (card2 as Control).global_position + (card2 as Control).size * 0.5
	return Vector2(100, 200)

func _get_revenue_target_global_center(sale: Dictionary, owner_id: int) -> Vector2:
	var restaurant_id := str(sale.get("matched_restaurant", sale.get("winner_restaurant_id", ""))).strip_edges()
	if _player_panel != null and is_instance_valid(_player_panel):
		var grid = _player_panel.get("overview_grid")
		if grid is Control and is_instance_valid(grid):
			for node in (grid as Control).get_children():
				if not (node is Control) or not is_instance_valid(node):
					continue
				var card: Control = node
				if not card.has_meta("player_id") or int(card.get_meta("player_id")) != owner_id:
					continue
				if card.has_meta("restaurant_id"):
					var card_restaurant_id := str(card.get_meta("restaurant_id")).strip_edges()
					if not restaurant_id.is_empty() and not card_restaurant_id.is_empty() and card_restaurant_id != restaurant_id:
						continue
				var cash: Label = card.find_child("CashLabel", true, false)
				if cash != null and is_instance_valid(cash):
					return cash.global_position + cash.size * 0.5
				return card.global_position + card.size * 0.5
	return _get_player_tab_global_center(owner_id)

func _apply_cash_overrides() -> void:
	if _player_panel != null and is_instance_valid(_player_panel):
		if _player_panel.has_method("set_cash_overrides"):
			_player_panel.set_cash_overrides(_player_running_cash)
		else:
			_player_panel.cash_overrides = _player_running_cash.duplicate()

func _clear_cash_overrides() -> void:
	if _player_panel != null and is_instance_valid(_player_panel):
		if _player_panel.has_method("clear_cash_overrides"):
			_player_panel.clear_cash_overrides()
		else:
			_player_panel.cash_overrides = {}
	_player_running_cash.clear()

func _ensure_skin() -> void:
	if _skin != null:
		return
	var base_dir := ModulesBaseDirClass.get_base_dir()
	var mods: Array[String] = []
	if Globals != null and (Globals.enabled_modules_v2 is Array):
		mods = Array(Globals.enabled_modules_v2, TYPE_STRING, "", null)
	_skin = UiSkinCacheClass.get_skin_for_modules(base_dir, mods, 40)

func _load_coin_texture() -> void:
	_coin_tex = load(COIN_TEXTURE_PATH) as Texture2D
