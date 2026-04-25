# 晚餐结算动画控制器
# 在地图上逐笔播放结算动画，替代旧的模态面板
class_name DinnertimeAnimationController
extends RefCounted

signal settlement_completed()
signal flow_state_changed()

const OverlayUtilsClass = preload("res://ui/scenes/game/overlay/utils.gd")
const MapUtilsClass = preload("res://core/map/map_utils.gd")
const DinnertimeTimelineClass = preload("res://core/rules/dinnertime_timeline.gd")
const UiSkinCacheClass = preload("res://ui/visual/ui_skin_cache.gd")
const ModulesBaseDirClass = preload("res://ui/utils/modules_base_dir.gd")
const UiZClass = preload("res://ui/utils/ui_z.gd")
const DinnertimeAnimationOrdersBuilderClass = preload("res://ui/scenes/game/dinnertime/orders_builder.gd")
const DinnertimeAnimationIncomeUtilsClass = preload("res://ui/scenes/game/dinnertime/income_utils.gd")
const DinnertimeAnimationPostIncomeCardClass = preload("res://ui/scenes/game/dinnertime/post_income_card.gd")
const DinnertimeAnimationMapHelpersClass = preload("res://ui/scenes/game/dinnertime/map_helpers.gd")
const DinnertimeAnimationRouteHelpersClass = preload("res://ui/scenes/game/dinnertime/route_helpers.gd")
const DinnertimeAnimationMoneyHelpersClass = preload("res://ui/scenes/game/dinnertime/money_helpers.gd")
const DinnertimeAnimationControlBarHelpersClass = preload("res://ui/scenes/game/dinnertime/control_bar_helpers.gd")
const DinnertimeAnimationPositionHelpersClass = preload("res://ui/scenes/game/dinnertime/position_helpers.gd")
const DinnertimeAnimationLayoutHelpersClass = preload("res://ui/scenes/game/dinnertime/layout_helpers.gd")
const DinnertimeAnimationTimelineHelpersClass = preload("res://ui/scenes/game/dinnertime/timeline_helpers.gd")

const COIN_TEXTURE_PATH = "res://assets/images/coin_gold.svg"
const COIN_BASE_COUNT := 0
const COIN_PER_AMOUNT := 2
const COIN_MAX_COUNT := 0
const COIN_BASE_SIZE := 20.0
const COIN_SIZE_SCALE := 0.20
const DEMAND_TOKEN_ICON_SCALE := 0.90
const ROUTE_FLASH_ALPHA_MIN := 0.35
const ROUTE_FLASH_ALPHA_MAX := 0.95
const POST_INCOME_CARD_SCALE := 0.68
const POST_INCOME_CARD_HOLD_SEC := 0.20
const PREVIEW_FLOAT_BASE_SEC := 1.05
const BANK_INCREASE_BASE_SEC := 0.22

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
var _layout_monitor_running: bool = false
var _layout_start_wait_running: bool = false
var _dinnertime_distance_script = null
var _post_income_events: Array[Dictionary] = []
var _post_income_by_player: Dictionary = {}  # player_id -> int
var _post_income_started: bool = false
var _post_income_playing: bool = false
var _post_income_done: bool = false
var _post_income_card: Control = null
var _bank_break_panel = null
var _bankruptcy_events_by_sale_index: Dictionary = {}  # sale_index -> Array[Dictionary]
var _bankruptcy_events_by_post_income_key: Dictionary = {}  # key -> Array[Dictionary]
var _milestone_toast_cb: Callable = Callable()
var _milestone_events_by_sale_index: Dictionary = {}  # sale_index -> Array[Dictionary]
var _milestone_events_by_post_income_key: Dictionary = {}  # key -> Array[Dictionary]
var _milestone_events_end: Array[Dictionary] = []

# 外部 UI 引用（用于动画目标位置）
var _bank_label: Label = null
var _player_panel = null  # LeftPanel

func start(
	settlement_data: Dictionary,
	state: GameState,
	scene: Node,
	map_canvas,
	bank_label: Label,
	player_panel,
	bank_break_panel = null,
	milestone_toast_cb: Callable = Callable()
) -> void:
	_game_state = state
	_scene = scene
	_map_canvas = map_canvas
	_bank_label = bank_label
	_player_panel = player_panel
	_bank_break_panel = bank_break_panel
	_milestone_toast_cb = milestone_toast_cb
	_speed = float(Globals.animation_speed) if Globals != null else 1.0

	_orders = DinnertimeAnimationOrdersBuilderClass.build_orders_from_settlement(settlement_data)
	_current_idx = 0
	_post_income_events = DinnertimeAnimationIncomeUtilsClass.build_post_house_income_events(settlement_data, _game_state)
	_post_income_by_player = DinnertimeAnimationIncomeUtilsClass.sum_post_income_by_player(_post_income_events)
	_bankruptcy_events_by_sale_index = _build_bankruptcy_events_by_sale_index(settlement_data)
	_bankruptcy_events_by_post_income_key = _build_bankruptcy_events_by_post_income_key(settlement_data)
	_milestone_events_by_sale_index = _build_milestone_events_by_sale_index(settlement_data)
	_milestone_events_by_post_income_key = _build_milestone_events_by_post_income_key(settlement_data)
	_milestone_events_end = _build_end_milestone_events(settlement_data)
	_post_income_started = false
	_post_income_playing = false
	_post_income_done = _post_income_events.is_empty()

	# 计算结算前银行值（当前值 + 所有房屋订单收入总和 + 后置收入 - 破产注资）。
	var total_revenue := 0
	for o in _orders:
		if bool(o.get("is_skipped", false)):
			continue
		total_revenue += DinnertimeAnimationIncomeUtilsClass.get_order_income_amount(o)
	var total_post_income := DinnertimeAnimationIncomeUtilsClass.sum_income_dict(_post_income_by_player)
	var total_break_added := _sum_bankruptcy_reserve_added(settlement_data)
	_running_bank_value = int(state.bank.get("total", 0)) + total_revenue + total_post_income - total_break_added
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
				_player_running_cash[oid] -= DinnertimeAnimationIncomeUtilsClass.get_order_income_amount(o)
		for pid_val in _post_income_by_player.keys():
			if not (pid_val is int):
				continue
			var pid := int(pid_val)
			if pid < 0 or not _player_running_cash.has(pid):
				continue
			_player_running_cash[pid] -= int(_post_income_by_player.get(pid, 0))
	_apply_cash_overrides()

	_ensure_skin()
	_load_coin_texture()
	_create_anim_layer()
	_create_map_anim_layer()
	_state = State.PLAYING
	_started_preview = false
	_stop_layout_monitor()
	_stop_layout_start_wait()

	if _orders.is_empty() and _post_income_events.is_empty():
		_finish()
		return
	if _orders.is_empty():
		_preview_current()
		_started_preview = true
		return
	# 等待 MapView auto-fit/zoom 应用完毕（避免 token/highlight 因 cell_size 变化而错位/缩放异常）。
	_start_when_layout_stable()

func _start_when_layout_stable() -> void:
	if _layout_start_wait_running:
		return
	_layout_start_wait_running = true
	await DinnertimeAnimationLayoutHelpersClass.wait_until_layout_stable(
		_scene,
		_map_canvas,
		func() -> bool:
			return _state == State.PLAYING and _layout_start_wait_running,
		func() -> bool:
			return _started_preview,
		func() -> float:
			return _get_cell_size(),
		func() -> Vector2i:
			return _get_world_origin(),
		func() -> bool:
			return _is_structure_index_ready_for_orders(),
		func() -> void:
			_spawn_persistent_demand_tokens()
			_preview_current()
			_started_preview = true
			_start_layout_monitor(),
		4,
		40
	)
	_layout_start_wait_running = false

func _is_structure_index_ready_for_orders() -> bool:
	return DinnertimeAnimationLayoutHelpersClass.is_structure_index_ready_for_orders(_map_canvas, _orders)

func skip_all() -> void:
	_kill_all_tweens()
	_finish()

func advance() -> void:
	if _state != State.PLAYING or not _previewing or _post_income_playing:
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

func can_advance() -> bool:
	return _state == State.PLAYING and _previewing and not _post_income_playing

func is_playing_step() -> bool:
	return _state == State.PLAYING and (not _previewing or _post_income_playing)

func get_progress_text() -> String:
	return "晚餐结算 (%d/%d)" % [clampi(_current_idx, 0, _orders.size()), _orders.size()]

func dispose() -> void:
	_stop_layout_monitor()
	_stop_layout_start_wait()
	_kill_all_tweens()
	_remove_highlight()
	_house_tokens.clear()
	_clear_cash_overrides()
	_remove_post_income_card()
	_post_income_events.clear()
	_post_income_by_player.clear()
	_bankruptcy_events_by_sale_index.clear()
	_bankruptcy_events_by_post_income_key.clear()
	_milestone_events_by_sale_index.clear()
	_milestone_events_by_post_income_key.clear()
	_milestone_events_end.clear()
	_milestone_toast_cb = Callable()
	_post_income_started = false
	_post_income_playing = false
	_post_income_done = false
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
	_bank_break_panel = null

# === 内部方法 ===

func _create_anim_layer() -> void:
	if _scene == null:
		return
	_anim_layer = Control.new()
	_anim_layer.name = "DinnertimeAnimLayer"
	_anim_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_anim_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiZClass.apply_absolute(_anim_layer, UiZClass.DINNERTIME_OVERLAY)
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
	UiZClass.apply_absolute(_map_anim_layer, UiZClass.DINNERTIME_OVERLAY)
	(_map_canvas as Control).add_child(_map_anim_layer)

func _create_control_bar() -> void:
	# 晚餐结算推进入口已迁移到右侧动作面板；保留空实现兼容旧调用路径。
	return

func _update_control_bar() -> void:
	if is_instance_valid(_control_bar):
		DinnertimeAnimationControlBarHelpersClass.update_control_bar(
			_control_bar,
			_current_idx,
			_orders.size(),
			_previewing,
			_post_income_playing,
			_post_income_done
		)
	flow_state_changed.emit()

func _on_next_pressed() -> void:
	if _current_idx >= _orders.size() and not _previewing:
		return
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
		if not _post_income_started:
			_post_income_started = true
			if _post_income_done:
				_finish()
				return
			_play_post_house_income_sequence()
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
	return DinnertimeAnimationMapHelpersClass.compute_structure_rect_from_index(cell_size, info)

func _compute_house_rect_from_anchor(cell_size: float, anchor: Vector2i, rotation: int) -> Rect2:
	return DinnertimeAnimationMapHelpersClass.compute_house_rect_from_anchor(cell_size, anchor, rotation, _get_world_origin())

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
	_monitor_layout_during_playback()

func _stop_layout_monitor() -> void:
	_layout_monitor_running = false

func _stop_layout_start_wait() -> void:
	_layout_start_wait_running = false

func _monitor_layout_during_playback() -> void:
	await DinnertimeAnimationLayoutHelpersClass.monitor_layout_during_playback(
		_scene,
		_map_canvas,
		func() -> bool:
			return _layout_monitor_running,
		func() -> bool:
			return _state == State.PLAYING,
		func() -> float:
			return _get_cell_size(),
		func() -> Vector2i:
			return _get_world_origin(),
		func() -> void:
			_on_map_layout_changed()
	)
	_layout_monitor_running = false

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
	return DinnertimeAnimationMapHelpersClass.compute_house_rects_from_map_cells(_game_state, _get_world_origin(), house_id, cell_size)

func _create_demand_token_nodes(order: Dictionary, house_id: String, house_rect: Rect2, structure_rect: Rect2, has_garden: bool) -> Array[Control]:
	var state_seed := int(_game_state.seed) if _game_state != null else 0
	return DinnertimeAnimationMapHelpersClass.create_demand_token_nodes(
		_map_anim_layer,
		_skin,
		order,
		house_id,
		house_rect,
		structure_rect,
		has_garden,
		maxf(_get_cell_size(), 1.0),
		state_seed
	)

func _create_restaurant_demand_token_nodes(order: Dictionary, restaurant_rect: Rect2) -> Array[Control]:
	var state_seed := int(_game_state.seed) if _game_state != null else 0
	return DinnertimeAnimationMapHelpersClass.create_restaurant_demand_token_nodes(
		_map_anim_layer,
		_skin,
		order,
		restaurant_rect,
		maxf(_get_cell_size(), 1.0),
		state_seed
	)

func _compute_restaurant_rect_from_order(order: Dictionary) -> Rect2:
	var restaurant_id := str(order.get("matched_restaurant", order.get("winner_restaurant_id", ""))).strip_edges()
	if restaurant_id.is_empty():
		return Rect2()
	var cells := _get_restaurant_cells(restaurant_id)
	if cells.is_empty():
		return Rect2()
	return _get_piece_canvas_rect(cells)

func _get_restaurant_cells(restaurant_id: String) -> Array[Vector2i]:
	return DinnertimeAnimationMapHelpersClass.get_restaurant_cells(_game_state, restaurant_id)

func _start_route_highlight_for_order(order: Dictionary) -> void:
	_clear_route_highlight()
	if not is_instance_valid(_map_anim_layer):
		return

	var path := _compute_route_path_for_order(order)
	if path.is_empty():
		return

	var built: Dictionary = DinnertimeAnimationRouteHelpersClass.create_route_highlight(
		_map_anim_layer,
		path,
		maxf(_get_cell_size(), 1.0),
		_get_world_origin(),
		_speed,
		ROUTE_FLASH_ALPHA_MIN,
		ROUTE_FLASH_ALPHA_MAX
	)
	_route_highlight_nodes.clear()
	var nodes_val = built.get("nodes", null)
	if nodes_val is Array:
		for n in nodes_val:
			if n is Control:
				_route_highlight_nodes.append(n)
	var tween_val = built.get("tween", null)
	_route_highlight_tween = tween_val if tween_val is Tween else null

func _clear_route_highlight() -> void:
	DinnertimeAnimationRouteHelpersClass.clear_route_highlight(_route_highlight_nodes, _route_highlight_tween)
	_route_highlight_tween = null
	_route_highlight_nodes.clear()

func _compute_route_path_for_order(order: Dictionary) -> Array[Vector2i]:
	return DinnertimeAnimationRouteHelpersClass.compute_route_path_for_order(
		_game_state,
		order,
		_get_dinnertime_distance_script()
	)

func _get_dinnertime_distance_script():
	_dinnertime_distance_script = DinnertimeAnimationRouteHelpersClass.get_dinnertime_distance_script(_dinnertime_distance_script)
	return _dinnertime_distance_script

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
	return DinnertimeAnimationMapHelpersClass.get_structure_rotation_at(_game_state, world_anchor)

func _get_structure_piece_id_at(world_anchor: Vector2i) -> String:
	return DinnertimeAnimationMapHelpersClass.get_structure_piece_id_at(_game_state, world_anchor)

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
	DinnertimeAnimationMapHelpersClass.place_persistent_x_mark(_map_anim_layer, rect, cell_size)

func _play_sale_animation(sale: Dictionary) -> void:
	var owner_id := int(sale.get("winner_owner", -1))
	var revenue := DinnertimeAnimationIncomeUtilsClass.get_order_income_amount(sale)
	var house_id := str(sale.get("house_id", ""))
	_current_house_id = house_id
	_house_tokens.erase(house_id)

	if not is_instance_valid(_anim_layer):
		_preview_current()
		return

	var dur_float := PREVIEW_FLOAT_BASE_SEC / _speed
	var coin_count := _compute_coin_count(revenue)
	var fly_timing := DinnertimeAnimationTimelineHelpersClass.compute_coin_flight_timing(_speed, coin_count)
	var dur_fly := float(fly_timing.get("dur_fly", 0.56 / maxf(_speed, 0.01)))
	var coin_delay_step := float(fly_timing.get("coin_delay_step", 0.0))
	var dur_fly_total := float(fly_timing.get("dur_fly_total", dur_fly))

	# 步骤1: 预览 token 向上漂浮消失
	_float_away_preview_tokens(dur_float)

	# 步骤3: 钱币从银行飞向左侧玩家概览卡 + 数字变化
	var bank_pos := _global_to_layer(_get_bank_label_global_center())
	var target_pos := _global_to_layer(_get_revenue_target_global_center(sale, owner_id))

	# 先完成 token 漂浮，再开始金币与数字变化。
	DinnertimeAnimationTimelineHelpersClass.schedule_sale_timeline(
		_anim_layer,
		_active_tweens,
		_speed,
		dur_float,
		dur_fly_total,
		func() -> void:
			_spawn_flying_coins(bank_pos, target_pos, revenue, owner_id, dur_fly, coin_delay_step, coin_count),
		func() -> void:
			_on_sale_timeline_finished(sale)
	)

func _on_sale_timeline_finished(sale: Dictionary) -> void:
	_clear_route_highlight()
	await _play_sale_bankruptcy_events(sale)
	_play_sale_milestone_events(sale)
	_preview_current()

func _play_sale_bankruptcy_events(sale: Dictionary) -> void:
	var sale_index := int(sale.get("sale_index", -1))
	if sale_index < 0:
		return
	var events := _consume_sale_bankruptcy_events(sale_index)
	for event_val in events:
		if not (event_val is Dictionary):
			continue
		await _show_bankruptcy_panel_for_event(event_val)

func _consume_sale_bankruptcy_events(sale_index: int) -> Array:
	if not _bankruptcy_events_by_sale_index.has(sale_index):
		return []
	var list_val = _bankruptcy_events_by_sale_index.get(sale_index, [])
	_bankruptcy_events_by_sale_index.erase(sale_index)
	if not (list_val is Array):
		return []
	return (list_val as Array).duplicate(true)

func _show_bankruptcy_panel_for_event(event: Dictionary) -> void:
	if _state != State.PLAYING:
		return

	var kind := str(event.get("kind", "")).strip_edges()
	_apply_bankruptcy_event_bank_increase_if_needed(event, kind)
	if not is_instance_valid(_bank_break_panel):
		return
	var count := 1
	if kind == "second":
		count = 2
	elif kind == "first":
		count = 1
	elif int(event.get("broke_count", 0)) >= 2:
		count = 2

	var bank_before := int(event.get("bank_total_before", _running_bank_value))
	var bank_after := int(event.get("bank_total_after", _running_bank_value))
	if _bank_break_panel.has_method("set_bankruptcy_info"):
		_bank_break_panel.call("set_bankruptcy_info", count, bank_before, bank_after, event.duplicate(true))

	if _bank_break_panel.has_method("show_with_animation"):
		_bank_break_panel.call("show_with_animation")
	else:
		_bank_break_panel.visible = true

	while _state == State.PLAYING and is_instance_valid(_bank_break_panel) and bool(_bank_break_panel.visible):
		if _scene == null or not is_instance_valid(_scene):
			return
		await _scene.get_tree().process_frame

func _apply_bankruptcy_event_bank_increase_if_needed(event: Dictionary, kind: String) -> void:
	if kind != "first":
		return
	var reserve_added := int(event.get("reserve_added", 0))
	if reserve_added <= 0:
		var before_val = event.get("bank_total_before", null)
		var after_val = event.get("bank_total_after", null)
		if before_val is int and after_val is int:
			reserve_added = int(after_val) - int(before_val)
	if reserve_added <= 0:
		return
	_animate_bank_increase(reserve_added, BANK_INCREASE_BASE_SEC / maxf(_speed, 0.01))

func _play_post_house_income_sequence() -> void:
	if _post_income_done or _post_income_playing:
		if _post_income_done and not _post_income_playing:
			_finish()
		return
	if _post_income_events.is_empty():
		_post_income_done = true
		_post_income_playing = false
		_finish()
		return
	_post_income_playing = true
	_update_control_bar()
	_play_post_house_income_event(0)

func _play_post_house_income_event(index: int) -> void:
	if _state != State.PLAYING:
		_post_income_playing = false
		_post_income_done = true
		_remove_post_income_card()
		_update_control_bar()
		return
	if index < 0 or index >= _post_income_events.size():
		_post_income_playing = false
		_post_income_done = true
		_remove_post_income_card()
		_finish()
		return
	if not is_instance_valid(_anim_layer):
		_post_income_playing = false
		_post_income_done = true
		_remove_post_income_card()
		_finish()
		return

	var event: Dictionary = _post_income_events[index]
	var player_id := int(event.get("player_id", -1))
	var amount := int(event.get("amount", 0))
	if player_id < 0 or amount <= 0:
		_play_post_house_income_event(index + 1)
		return

	_create_post_income_employee_card(event)

	var coin_count := _compute_coin_count(amount)
	var fly_timing := DinnertimeAnimationTimelineHelpersClass.compute_coin_flight_timing(_speed, coin_count)
	var dur_fly := float(fly_timing.get("dur_fly", 0.56 / maxf(_speed, 0.01)))
	var coin_delay_step := float(fly_timing.get("coin_delay_step", 0.0))
	var dur_fly_total := float(fly_timing.get("dur_fly_total", dur_fly))

	var bank_pos := _global_to_layer(_get_bank_label_global_center())
	var target_pos := _global_to_layer(_get_player_tab_global_center(player_id))

	DinnertimeAnimationTimelineHelpersClass.schedule_post_income_event_timeline(
		_anim_layer,
		_active_tweens,
		_speed,
		dur_fly_total,
		POST_INCOME_CARD_HOLD_SEC,
		func() -> void:
			_spawn_flying_coins(bank_pos, target_pos, amount, player_id, dur_fly, coin_delay_step, coin_count),
		func() -> void:
			_remove_post_income_card(),
		func() -> void:
			_on_post_income_timeline_finished(event, index)
	)

func _on_post_income_timeline_finished(event: Dictionary, index: int) -> void:
	await _play_post_income_bankruptcy_events(event)
	_play_post_income_milestone_events(event)
	_play_post_house_income_event(index + 1)

func _play_post_income_bankruptcy_events(event: Dictionary) -> void:
	var player_id := int(event.get("player_id", -1))
	var kind := str(event.get("kind", "")).strip_edges()
	var amount := int(event.get("amount", 0))
	if player_id < 0 or kind.is_empty() or amount <= 0:
		return
	var events := _consume_post_income_bankruptcy_events(kind, player_id, amount)
	for event_val in events:
		if not (event_val is Dictionary):
			continue
		await _show_bankruptcy_panel_for_event(event_val)

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
	return DinnertimeAnimationMoneyHelpersClass.compute_coin_count(revenue, COIN_BASE_COUNT, COIN_PER_AMOUNT, COIN_MAX_COUNT)

func _spawn_flying_coins(from: Vector2, to: Vector2, revenue: int, owner_id: int, dur: float, coin_delay_step: float, coin_count: int) -> void:
	DinnertimeAnimationMoneyHelpersClass.spawn_flying_coins(
		_anim_layer,
		_coin_tex,
		from,
		to,
		revenue,
		owner_id,
		dur,
		coin_delay_step,
		coin_count,
		COIN_BASE_SIZE,
		COIN_SIZE_SCALE,
		_active_tweens,
		func(pid: int, amount: int, number_dur: float):
			_animate_bank_decrease(amount, number_dur)
			_animate_player_income(pid, amount, number_dur)
	)

func _animate_bank_decrease(amount: int, dur: float) -> void:
	_running_bank_value = DinnertimeAnimationMoneyHelpersClass.animate_bank_decrease(
		_bank_label,
		_active_tweens,
		_running_bank_value,
		amount,
		dur
	)

func _animate_bank_increase(amount: int, dur: float) -> void:
	_running_bank_value = DinnertimeAnimationMoneyHelpersClass.animate_bank_increase(
		_bank_label,
		_active_tweens,
		_running_bank_value,
		amount,
		dur
	)

func _animate_player_income(player_id: int, amount: int, dur: float) -> void:
	DinnertimeAnimationMoneyHelpersClass.animate_player_income(
		_anim_layer,
		player_id,
		amount,
		dur,
		_speed,
		_active_tweens,
		_player_running_cash,
		func():
			_apply_cash_overrides(),
		_global_to_layer(_get_player_tab_global_center(player_id))
	)

func _finish() -> void:
	if _state == State.DONE:
		return
	_emit_all_remaining_milestone_events()
	_state = State.DONE
	_stop_layout_monitor()
	_stop_layout_start_wait()
	_clear_cash_overrides()
	_remove_post_income_card()
	_post_income_playing = false
	_post_income_done = true
	_remove_highlight()
	if is_instance_valid(_control_bar):
		_control_bar.queue_free()
	_control_bar = null
	_clear_anim_layer()
	_clear_map_anim_layer()
	flow_state_changed.emit()
	settlement_completed.emit()

func _clear_anim_layer() -> void:
	_post_income_card = null
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
	_remove_post_income_card()
	_post_income_playing = false
	_clear_anim_layer()
	_clear_map_anim_layer()

func _world_to_screen(world_pos: Vector2i) -> Vector2:
	if world_pos == Vector2i(-1, -1) or _map_canvas == null or not is_instance_valid(_map_canvas):
		return Vector2(400, 300)
	var cs := int(DinnertimeAnimationPositionHelpersClass.get_cell_size(_map_canvas))
	var view = world_pos - _get_world_origin()
	var local_pos := Vector2(view) * float(cs) + Vector2(cs, cs) * 0.5
	return (_map_canvas as Control).global_position + local_pos

func _get_world_origin() -> Vector2i:
	return DinnertimeAnimationPositionHelpersClass.get_world_origin(_map_canvas)

func _get_cell_size() -> float:
	return DinnertimeAnimationPositionHelpersClass.get_cell_size(_map_canvas)

func _get_piece_screen_rect(cells: Array[Vector2i]) -> Rect2:
	return DinnertimeAnimationPositionHelpersClass.get_piece_screen_rect(_map_canvas, cells, _get_world_origin())

func _get_piece_canvas_rect(cells: Array[Vector2i]) -> Rect2:
	return DinnertimeAnimationPositionHelpersClass.get_piece_canvas_rect(_map_canvas, cells, _get_world_origin())

func _global_to_layer(global_pos: Vector2) -> Vector2:
	return DinnertimeAnimationPositionHelpersClass.global_to_layer(_anim_layer, global_pos)

func _get_bank_label_global_center() -> Vector2:
	return DinnertimeAnimationPositionHelpersClass.get_bank_label_global_center(_bank_label)

func _get_player_tab_global_center(player_id: int) -> Vector2:
	return DinnertimeAnimationPositionHelpersClass.get_player_tab_global_center(_player_panel, player_id)

func _get_revenue_target_global_center(sale: Dictionary, owner_id: int) -> Vector2:
	return DinnertimeAnimationPositionHelpersClass.get_revenue_target_global_center(_player_panel, sale, owner_id)

func _create_post_income_employee_card(event: Dictionary) -> void:
	_remove_post_income_card()
	_post_income_card = DinnertimeAnimationPostIncomeCardClass.create(
		_anim_layer,
		_scene,
		_map_canvas,
		event,
		POST_INCOME_CARD_SCALE,
		_speed,
		_active_tweens
	)

func _remove_post_income_card() -> void:
	if is_instance_valid(_post_income_card):
		DinnertimeAnimationPostIncomeCardClass.remove(_post_income_card)
	_post_income_card = null

func _build_bankruptcy_events_by_sale_index(settlement_data: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var events_val = settlement_data.get("bankruptcy_events", null)
	if not (events_val is Array):
		return out
	var events: Array = events_val
	for evt_val in events:
		if not (evt_val is Dictionary):
			continue
		var evt: Dictionary = evt_val
		if str(evt.get(DinnertimeTimelineClass.KEY_STAGE, "")).strip_edges() != DinnertimeTimelineClass.STAGE_SALE:
			continue
		var sale_index := int(evt.get(DinnertimeTimelineClass.KEY_SALE_INDEX, -1))
		if sale_index < 0:
			continue
		var bucket: Array = []
		if out.has(sale_index):
			var cur = out[sale_index]
			if cur is Array:
				bucket = cur
		bucket.append(evt.duplicate(true))
		out[sale_index] = bucket
	return out

func _build_bankruptcy_events_by_post_income_key(settlement_data: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var events_val = settlement_data.get("bankruptcy_events", null)
	if not (events_val is Array):
		return out
	var events: Array = events_val
	for evt_val in events:
		if not (evt_val is Dictionary):
			continue
		var evt: Dictionary = evt_val
		if str(evt.get(DinnertimeTimelineClass.KEY_STAGE, "")).strip_edges() != DinnertimeTimelineClass.STAGE_POST_INCOME:
			continue
		var kind := str(evt.get(DinnertimeTimelineClass.KEY_POST_INCOME_KIND, "")).strip_edges()
		var player_id := int(evt.get(DinnertimeTimelineClass.KEY_PLAYER_ID, -1))
		var amount := int(evt.get(DinnertimeTimelineClass.KEY_PAYMENT_AMOUNT, 0))
		if kind.is_empty() or player_id < 0 or amount <= 0:
			continue
		var key := _build_post_income_key(kind, player_id, amount)
		var bucket: Array = []
		if out.has(key):
			var cur = out[key]
			if cur is Array:
				bucket = cur
		bucket.append(evt.duplicate(true))
		out[key] = bucket
	return out

func _build_milestone_events_by_sale_index(settlement_data: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var events_val = settlement_data.get(DinnertimeTimelineClass.KEY_TIMELINE_EVENTS, null)
	if not (events_val is Array):
		return out
	var events: Array = events_val
	for evt_val in events:
		if not (evt_val is Dictionary):
			continue
		var evt: Dictionary = evt_val
		if str(evt.get(DinnertimeTimelineClass.KEY_KIND, "")).strip_edges() != DinnertimeTimelineClass.KIND_MILESTONE:
			continue
		if str(evt.get(DinnertimeTimelineClass.KEY_STAGE, "")).strip_edges() != DinnertimeTimelineClass.STAGE_SALE:
			continue
		var sale_index := int(evt.get(DinnertimeTimelineClass.KEY_SALE_INDEX, -1))
		var player_id := int(evt.get(DinnertimeTimelineClass.KEY_PLAYER_ID, -1))
		var milestone_id := str(evt.get(DinnertimeTimelineClass.KEY_MILESTONE_ID, "")).strip_edges()
		if sale_index < 0 or player_id < 0 or milestone_id.is_empty():
			continue

		var bucket: Array = []
		if out.has(sale_index):
			var cur = out[sale_index]
			if cur is Array:
				bucket = cur
		bucket.append({
			"player_id": player_id,
			"milestone_id": milestone_id,
		})
		out[sale_index] = bucket

	for k in out.keys():
		var arr_val = out.get(k, null)
		if not (arr_val is Array):
			continue
		var arr: Array = arr_val
		arr.sort_custom(func(a, b) -> bool:
			if not (a is Dictionary and b is Dictionary):
				return false
			var da: Dictionary = a
			var db: Dictionary = b
			var pa := int(da.get("player_id", -1))
			var pb := int(db.get("player_id", -1))
			if pa != pb:
				return pa < pb
			return str(da.get("milestone_id", "")) < str(db.get("milestone_id", ""))
		)
	return out

func _build_milestone_events_by_post_income_key(settlement_data: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var events_val = settlement_data.get(DinnertimeTimelineClass.KEY_TIMELINE_EVENTS, null)
	if not (events_val is Array):
		return out
	var events: Array = events_val
	for evt_val in events:
		if not (evt_val is Dictionary):
			continue
		var evt: Dictionary = evt_val
		if str(evt.get(DinnertimeTimelineClass.KEY_KIND, "")).strip_edges() != DinnertimeTimelineClass.KIND_MILESTONE:
			continue
		if str(evt.get(DinnertimeTimelineClass.KEY_STAGE, "")).strip_edges() != DinnertimeTimelineClass.STAGE_POST_INCOME:
			continue
		var kind := str(evt.get(DinnertimeTimelineClass.KEY_POST_INCOME_KIND, "")).strip_edges()
		var player_id := int(evt.get(DinnertimeTimelineClass.KEY_PLAYER_ID, -1))
		var amount := int(evt.get(DinnertimeTimelineClass.KEY_PAYMENT_AMOUNT, 0))
		var milestone_id := str(evt.get(DinnertimeTimelineClass.KEY_MILESTONE_ID, "")).strip_edges()
		if kind.is_empty() or player_id < 0 or amount <= 0 or milestone_id.is_empty():
			continue

		var key := _build_post_income_key(kind, player_id, amount)
		var bucket: Array = []
		if out.has(key):
			var cur = out[key]
			if cur is Array:
				bucket = cur
		bucket.append({
			"player_id": player_id,
			"milestone_id": milestone_id,
		})
		out[key] = bucket

	for k in out.keys():
		var arr_val = out.get(k, null)
		if not (arr_val is Array):
			continue
		var arr: Array = arr_val
		arr.sort_custom(func(a, b) -> bool:
			if not (a is Dictionary and b is Dictionary):
				return false
			var da: Dictionary = a
			var db: Dictionary = b
			var pa := int(da.get("player_id", -1))
			var pb := int(db.get("player_id", -1))
			if pa != pb:
				return pa < pb
			return str(da.get("milestone_id", "")) < str(db.get("milestone_id", ""))
		)
	return out

func _build_end_milestone_events(settlement_data: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var events_val = settlement_data.get(DinnertimeTimelineClass.KEY_TIMELINE_EVENTS, null)
	if not (events_val is Array):
		return out
	var events: Array = events_val
	for evt_val in events:
		if not (evt_val is Dictionary):
			continue
		var evt: Dictionary = evt_val
		if str(evt.get(DinnertimeTimelineClass.KEY_KIND, "")).strip_edges() != DinnertimeTimelineClass.KIND_MILESTONE:
			continue
		if str(evt.get(DinnertimeTimelineClass.KEY_STAGE, "")).strip_edges() != DinnertimeTimelineClass.STAGE_END:
			continue
		var player_id := int(evt.get(DinnertimeTimelineClass.KEY_PLAYER_ID, -1))
		var milestone_id := str(evt.get(DinnertimeTimelineClass.KEY_MILESTONE_ID, "")).strip_edges()
		if player_id < 0 or milestone_id.is_empty():
			continue
		out.append({
			"player_id": player_id,
			"milestone_id": milestone_id,
		})

	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var pa := int(a.get("player_id", -1))
		var pb := int(b.get("player_id", -1))
		if pa != pb:
			return pa < pb
		return str(a.get("milestone_id", "")) < str(b.get("milestone_id", ""))
	)
	return out

func _build_post_income_key(kind: String, player_id: int, amount: int) -> String:
	return "%s:%d:%d" % [kind.strip_edges(), int(player_id), int(amount)]

func _consume_post_income_bankruptcy_events(kind: String, player_id: int, amount: int) -> Array:
	var key := _build_post_income_key(kind, player_id, amount)
	if not _bankruptcy_events_by_post_income_key.has(key):
		return []
	var list_val = _bankruptcy_events_by_post_income_key.get(key, [])
	_bankruptcy_events_by_post_income_key.erase(key)
	if not (list_val is Array):
		return []
	return (list_val as Array).duplicate(true)

func _sum_bankruptcy_reserve_added(settlement_data: Dictionary) -> int:
	var total := 0
	var events_val = settlement_data.get("bankruptcy_events", null)
	if not (events_val is Array):
		return total
	var events: Array = events_val
	for evt_val in events:
		if not (evt_val is Dictionary):
			continue
		var evt: Dictionary = evt_val
		if str(evt.get("kind", "")).strip_edges() != "first":
			continue
		total += int(evt.get("reserve_added", 0))
	return total

func _play_sale_milestone_events(sale: Dictionary) -> void:
	var sale_index := int(sale.get("sale_index", -1))
	if sale_index < 0:
		return
	var events := _consume_sale_milestone_events(sale_index)
	_emit_milestone_events(events)

func _consume_sale_milestone_events(sale_index: int) -> Array:
	if not _milestone_events_by_sale_index.has(sale_index):
		return []
	var list_val = _milestone_events_by_sale_index.get(sale_index, [])
	_milestone_events_by_sale_index.erase(sale_index)
	if not (list_val is Array):
		return []
	return (list_val as Array).duplicate(true)

func _play_post_income_milestone_events(event: Dictionary) -> void:
	var player_id := int(event.get("player_id", -1))
	var kind := str(event.get("kind", "")).strip_edges()
	var amount := int(event.get("amount", 0))
	if player_id < 0 or kind.is_empty() or amount <= 0:
		return
	var events := _consume_post_income_milestone_events(kind, player_id, amount)
	_emit_milestone_events(events)

func _consume_post_income_milestone_events(kind: String, player_id: int, amount: int) -> Array:
	var key := _build_post_income_key(kind, player_id, amount)
	if not _milestone_events_by_post_income_key.has(key):
		return []
	var list_val = _milestone_events_by_post_income_key.get(key, [])
	_milestone_events_by_post_income_key.erase(key)
	if not (list_val is Array):
		return []
	return (list_val as Array).duplicate(true)

func _emit_milestone_events(events: Array) -> void:
	if not _milestone_toast_cb.is_valid():
		return
	for evt_val in events:
		if not (evt_val is Dictionary):
			continue
		var evt: Dictionary = evt_val
		var player_id := int(evt.get("player_id", -1))
		var milestone_id := str(evt.get("milestone_id", "")).strip_edges()
		if player_id < 0 or milestone_id.is_empty():
			continue
		_milestone_toast_cb.call(player_id, milestone_id)

func _emit_all_remaining_milestone_events() -> void:
	# sale
	var sale_keys: Array[int] = []
	for k in _milestone_events_by_sale_index.keys():
		if k is int:
			sale_keys.append(int(k))
	sale_keys.sort()
	for sale_index in sale_keys:
		var list_val = _milestone_events_by_sale_index.get(sale_index, [])
		if list_val is Array:
			_emit_milestone_events(list_val as Array)
	_milestone_events_by_sale_index.clear()

	# post_income
	var post_keys: Array[String] = []
	for k in _milestone_events_by_post_income_key.keys():
		if k is String:
			post_keys.append(str(k))
	post_keys.sort()
	for key in post_keys:
		var list_val = _milestone_events_by_post_income_key.get(key, [])
		if list_val is Array:
			_emit_milestone_events(list_val as Array)
	_milestone_events_by_post_income_key.clear()

	# end
	_emit_milestone_events(_milestone_events_end)
	_milestone_events_end.clear()

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
