# 营销结算动画控制器
# 自动逐个展示广告牌生效、房屋需求增加和广告持续时间变化。
class_name MarketingAnimationController
extends RefCounted

signal settlement_completed()

const OverlayUtilsClass = preload("res://ui/scenes/game/overlay/utils.gd")
const MapUtilsClass = preload("res://core/map/map_utils.gd")
const UiSkinCacheClass = preload("res://ui/visual/ui_skin_cache.gd")
const ModulesBaseDirClass = preload("res://ui/utils/modules_base_dir.gd")
const UiZClass = preload("res://ui/utils/ui_z.gd")
const UiStylesClass = preload("res://ui/utils/ui_styles.gd")
const MarketingAnimationOrdersBuilderClass = preload("res://ui/scenes/game/marketing/orders_builder.gd")
const DinnertimeAnimationMapHelpersClass = preload("res://ui/scenes/game/dinnertime/map_helpers.gd")
const DinnertimeAnimationPositionHelpersClass = preload("res://ui/scenes/game/dinnertime/position_helpers.gd")

const TOKEN_MAX_PER_HOUSE_EVENT := 3
const BOARD_PULSE_SEC := 0.28
const TOKEN_FLY_SEC := 0.42
const HOUSE_PULSE_SEC := 0.20
const ORDER_GAP_SEC := 0.14
const DURATION_HOLD_SEC := 0.36

enum State { IDLE, PLAYING, DONE }

var _state: int = State.IDLE
var _orders: Array[Dictionary] = []
var _current_idx: int = 0
var _scene: Node = null
var _map_canvas = null
var _game_state: GameState = null
var _anim_layer: Control = null
var _map_anim_layer: Control = null
var _control_bar: Control = null
var _skin = null
var _speed: float = 1.0
var _active_tweens: Array[Tween] = []

func start(
	marketing_data: Dictionary,
	state: GameState,
	scene: Node,
	map_canvas,
	_player_panel = null,
	_milestone_toast_cb: Callable = Callable()
) -> void:
	_game_state = state
	_scene = scene
	_map_canvas = map_canvas
	_speed = maxf(float(Globals.animation_speed) if Globals != null else 1.0, 0.05)
	_orders = MarketingAnimationOrdersBuilderClass.build_orders_from_settlement(marketing_data)
	_current_idx = 0
	_ensure_skin()
	_create_anim_layer()
	_create_map_anim_layer()
	_create_control_bar()
	_state = State.PLAYING
	_update_control_bar()

	if _orders.is_empty():
		_finish()
		return
	_play_sequence()

func skip_all() -> void:
	_kill_all_tweens()
	_finish()

func dispose() -> void:
	_kill_all_tweens()
	if is_instance_valid(_control_bar):
		_control_bar.queue_free()
	_control_bar = null
	if is_instance_valid(_anim_layer):
		_anim_layer.queue_free()
	_anim_layer = null
	if is_instance_valid(_map_anim_layer):
		_map_anim_layer.queue_free()
	_map_anim_layer = null
	_scene = null
	_map_canvas = null
	_game_state = null
	_skin = null
	_orders.clear()

func _play_sequence() -> void:
	if _scene == null or not is_instance_valid(_scene):
		_finish()
		return
	await _scene.get_tree().process_frame
	while _state == State.PLAYING and _current_idx < _orders.size():
		var order: Dictionary = _orders[_current_idx]
		_current_idx += 1
		_update_control_bar()
		await _play_order(order)
		await _wait(ORDER_GAP_SEC)
	_finish()

func _play_order(order: Dictionary) -> void:
	if _state != State.PLAYING:
		return
	var board_rect := _compute_marketing_rect(order)
	await _pulse_board(order, board_rect)
	await _play_campaign_range_effect(order, board_rect)

	var house_events_val = order.get("house_events", [])
	var house_events: Array = house_events_val if house_events_val is Array else []
	for evt_val in house_events:
		if _state != State.PLAYING:
			return
		if not (evt_val is Dictionary):
			continue
		await _play_house_demand_event(order, evt_val, board_rect)

	await _play_duration_event(order, board_rect)

func _pulse_board(order: Dictionary, board_rect: Rect2) -> void:
	if not is_instance_valid(_map_anim_layer):
		return
	var rect := board_rect
	if rect.size == Vector2.ZERO:
		rect = Rect2(Vector2.ZERO, Vector2(maxf(_get_cell_size(), 1.0), maxf(_get_cell_size(), 1.0)))

	var pulse := ColorRect.new()
	pulse.name = "MarketingBoardPulse"
	pulse.position = rect.position
	pulse.size = rect.size
	pulse.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pulse.color = _color_for_marketing_type(str(order.get("type", "")), 0.34)
	pulse.pivot_offset = rect.size * 0.5
	_map_anim_layer.add_child(pulse)

	var tw := pulse.create_tween().set_parallel(true)
	_active_tweens.append(tw)
	tw.tween_property(pulse, "scale", Vector2(1.08, 1.08), BOARD_PULSE_SEC / _speed).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(pulse, "modulate:a", 0.0, BOARD_PULSE_SEC / _speed).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(func():
		if is_instance_valid(pulse):
			pulse.queue_free()
		_active_tweens.erase(tw)
	)
	await tw.finished

func _play_campaign_range_effect(order: Dictionary, board_rect: Rect2) -> void:
	if not is_instance_valid(_map_anim_layer):
		return
	var unique_houses := _unique_house_ids_from_order(order)
	if unique_houses.is_empty():
		await _wait(0.10)
		return

	var color := _color_for_marketing_type(str(order.get("type", "")), 0.24)
	var nodes: Array[Control] = []
	for house_id in unique_houses:
		var rect := _compute_house_rect(str(house_id))
		if rect.size == Vector2.ZERO:
			continue
		var h := ColorRect.new()
		h.name = "MarketingHouseRangePulse"
		h.position = rect.position
		h.size = rect.size
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.color = color
		h.modulate.a = 0.0
		_map_anim_layer.add_child(h)
		nodes.append(h)

	var sweep := _create_campaign_sweep(order, board_rect)
	var tw := _map_anim_layer.create_tween().set_parallel(true)
	_active_tweens.append(tw)
	for n in nodes:
		tw.tween_property(n, "modulate:a", 1.0, 0.16 / _speed)
		tw.tween_property(n, "modulate:a", 0.0, 0.28 / _speed).set_delay(0.16 / _speed)
	if is_instance_valid(sweep):
		tw.tween_property(sweep, "modulate:a", 0.0, 0.44 / _speed).set_delay(0.05 / _speed)
	tw.chain().tween_callback(func():
		for n2 in nodes:
			if is_instance_valid(n2):
				n2.queue_free()
		if is_instance_valid(sweep):
			sweep.queue_free()
		_active_tweens.erase(tw)
	)
	await tw.finished

func _play_house_demand_event(order: Dictionary, event: Dictionary, board_rect: Rect2) -> void:
	var house_id := str(event.get("house_id", "")).strip_edges()
	if house_id.is_empty():
		return
	var house_rect := _compute_house_rect(house_id)
	if house_rect.size == Vector2.ZERO:
		return

	var amount_added := int(event.get("amount_added", 0))
	if amount_added <= 0:
		await _show_capped_marker(house_rect)
		return

	var count := mini(amount_added, TOKEN_MAX_PER_HOUSE_EVENT)
	for i in range(count):
		await _fly_product_token(str(event.get("product", order.get("product", ""))), board_rect, house_rect, i, count)
	await _pulse_house(house_rect)

func _play_duration_event(order: Dictionary, board_rect: Rect2) -> void:
	var before_duration := int(order.get("duration_before", 0))
	var after_duration := int(order.get("duration_after", 0))
	var expired := bool(order.get("expired", false))
	if before_duration == 0 and after_duration == 0 and not expired:
		return
	if not is_instance_valid(_map_anim_layer):
		return

	var label := Label.new()
	label.name = "MarketingDurationLabel"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", maxi(12, int(_get_cell_size() * 0.34)))
	label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.text = "失效" if expired else "%d > %d" % [before_duration, after_duration]
	label.position = board_rect.position
	label.size = board_rect.size
	label.modulate.a = 0.0
	_map_anim_layer.add_child(label)

	var bg := ColorRect.new()
	bg.name = "MarketingDurationPulse"
	bg.position = board_rect.position
	bg.size = board_rect.size
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.color = Color(0.78, 0.18, 0.16, 0.34) if expired else Color(0.10, 0.18, 0.22, 0.30)
	_map_anim_layer.add_child(bg)
	_map_anim_layer.move_child(bg, max(0, label.get_index() - 1))

	var tw := _map_anim_layer.create_tween().set_parallel(true)
	_active_tweens.append(tw)
	tw.tween_property(label, "modulate:a", 1.0, 0.12 / _speed)
	tw.tween_property(bg, "modulate:a", 1.0, 0.12 / _speed)
	tw.tween_property(label, "modulate:a", 0.0, 0.18 / _speed).set_delay(DURATION_HOLD_SEC / _speed)
	tw.tween_property(bg, "modulate:a", 0.0, 0.18 / _speed).set_delay(DURATION_HOLD_SEC / _speed)
	tw.chain().tween_callback(func():
		if is_instance_valid(label):
			label.queue_free()
		if is_instance_valid(bg):
			bg.queue_free()
		_active_tweens.erase(tw)
	)
	await tw.finished

func _fly_product_token(product_id: String, board_rect: Rect2, house_rect: Rect2, index: int, total: int) -> void:
	if not is_instance_valid(_map_anim_layer):
		return
	var icon_size := maxf(18.0, _get_cell_size() * 0.68)
	var token := Control.new()
	token.name = "MarketingDemandToken"
	token.size = Vector2(icon_size, icon_size)
	token.custom_minimum_size = token.size
	token.pivot_offset = token.size * 0.5
	token.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var from_pos := board_rect.position + board_rect.size * 0.5 - token.size * 0.5
	var to_pos := house_rect.position + house_rect.size * 0.5 - token.size * 0.5
	if total > 1:
		var angle := TAU * float(index) / float(total)
		to_pos += Vector2(cos(angle), sin(angle)) * minf(_get_cell_size() * 0.18, 12.0)
	token.position = from_pos
	token.scale = Vector2(0.75, 0.75)
	_map_anim_layer.add_child(token)

	var tex := _get_product_texture(product_id)
	if tex != null:
		var icon := TextureRect.new()
		icon.set_anchors_preset(Control.PRESET_FULL_RECT)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture = tex
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		token.add_child(icon)
	else:
		var fallback := Label.new()
		fallback.set_anchors_preset(Control.PRESET_FULL_RECT)
		fallback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		fallback.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		fallback.text = product_id.left(2).to_upper()
		fallback.add_theme_font_size_override("font_size", 12)
		token.add_child(fallback)

	var tw := token.create_tween().set_parallel(true)
	_active_tweens.append(tw)
	var dur := TOKEN_FLY_SEC / _speed
	tw.tween_property(token, "position", to_pos, dur).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(token, "scale", Vector2(1.05, 1.05), dur * 0.65)
	tw.tween_property(token, "modulate:a", 0.0, dur * 0.28).set_delay(dur * 0.72)
	tw.chain().tween_callback(func():
		if is_instance_valid(token):
			token.queue_free()
		_active_tweens.erase(tw)
	)
	await tw.finished

func _pulse_house(house_rect: Rect2) -> void:
	if not is_instance_valid(_map_anim_layer):
		return
	var pulse := ColorRect.new()
	pulse.name = "MarketingHousePulse"
	pulse.position = house_rect.position
	pulse.size = house_rect.size
	pulse.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pulse.color = Color(1.0, 0.80, 0.20, 0.28)
	_map_anim_layer.add_child(pulse)
	var tw := pulse.create_tween().set_parallel(true)
	_active_tweens.append(tw)
	tw.tween_property(pulse, "modulate:a", 0.0, HOUSE_PULSE_SEC / _speed)
	tw.chain().tween_callback(func():
		if is_instance_valid(pulse):
			pulse.queue_free()
		_active_tweens.erase(tw)
	)
	await tw.finished

func _show_capped_marker(house_rect: Rect2) -> void:
	if not is_instance_valid(_map_anim_layer):
		return
	var marker := Label.new()
	marker.name = "MarketingCappedMarker"
	marker.text = "已满"
	marker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	marker.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	marker.add_theme_font_size_override("font_size", maxi(10, int(_get_cell_size() * 0.28)))
	marker.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	marker.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	marker.add_theme_constant_override("shadow_offset_x", 1)
	marker.add_theme_constant_override("shadow_offset_y", 1)
	marker.position = house_rect.position
	marker.size = house_rect.size
	marker.modulate.a = 0.0
	marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map_anim_layer.add_child(marker)
	var tw := marker.create_tween().set_parallel(true)
	_active_tweens.append(tw)
	tw.tween_property(marker, "modulate:a", 1.0, 0.10 / _speed)
	tw.tween_property(marker, "position:y", marker.position.y - maxf(12.0, _get_cell_size() * 0.35), 0.34 / _speed)
	tw.tween_property(marker, "modulate:a", 0.0, 0.18 / _speed).set_delay(0.18 / _speed)
	tw.chain().tween_callback(func():
		if is_instance_valid(marker):
			marker.queue_free()
		_active_tweens.erase(tw)
	)
	await tw.finished

func _create_campaign_sweep(order: Dictionary, board_rect: Rect2) -> Control:
	if not is_instance_valid(_map_anim_layer):
		return null
	var sweep := ColorRect.new()
	sweep.name = "MarketingCampaignSweep"
	sweep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sweep.color = _color_for_marketing_type(str(order.get("type", "")), 0.34)
	var marketing_type := str(order.get("type", ""))
	if marketing_type == "radio":
		var s := maxf(board_rect.size.x, board_rect.size.y) * 2.5
		sweep.position = board_rect.position + board_rect.size * 0.5 - Vector2(s, s) * 0.5
		sweep.size = Vector2(s, s)
		sweep.pivot_offset = sweep.size * 0.5
		sweep.scale = Vector2(0.25, 0.25)
	elif marketing_type == "airplane":
		sweep.position = board_rect.position
		sweep.size = board_rect.size
		sweep.scale = Vector2(0.25, 1.0) if board_rect.size.x >= board_rect.size.y else Vector2(1.0, 0.25)
	else:
		sweep.position = board_rect.position
		sweep.size = board_rect.size
		sweep.pivot_offset = sweep.size * 0.5
		sweep.scale = Vector2(0.75, 0.75)
	_map_anim_layer.add_child(sweep)

	var tw := sweep.create_tween().set_parallel(true)
	_active_tweens.append(tw)
	if marketing_type == "radio":
		tw.tween_property(sweep, "scale", Vector2(1.0, 1.0), 0.38 / _speed).set_ease(Tween.EASE_OUT)
	elif marketing_type == "airplane":
		tw.tween_property(sweep, "scale", Vector2.ONE, 0.34 / _speed).set_ease(Tween.EASE_OUT)
	else:
		tw.tween_property(sweep, "scale", Vector2(1.12, 1.12), 0.34 / _speed).set_ease(Tween.EASE_OUT)
	tw.chain().tween_callback(func():
		_active_tweens.erase(tw)
	)
	return sweep

func _compute_marketing_rect(order: Dictionary) -> Rect2:
	var world_pos := _read_vector2i(order.get("world_pos", [0, 0]), Vector2i.ZERO)
	var size := _read_vector2i(order.get("footprint_size", [1, 1]), Vector2i.ONE)
	if size.x <= 0 or size.y <= 0:
		size = Vector2i.ONE
	var rotation := int(order.get("rotation", 0))
	if rotation == 90 or rotation == 270:
		size = Vector2i(size.y, size.x)
	var view_pos := world_pos - _get_world_origin()
	var cs := maxf(_get_cell_size(), 1.0)
	return Rect2(Vector2(view_pos) * cs, Vector2(size) * cs)

func _compute_house_rect(house_id: String) -> Rect2:
	var cell_size := maxf(_get_cell_size(), 1.0)
	var scanned := DinnertimeAnimationMapHelpersClass.compute_house_rects_from_map_cells(_game_state, _get_world_origin(), house_id, cell_size)
	if not scanned.is_empty():
		var structure_rect: Rect2 = scanned.get("structure_rect", Rect2())
		var house_rect: Rect2 = scanned.get("house_rect", structure_rect)
		if bool(scanned.get("has_garden", false)) and structure_rect.size != Vector2.ZERO:
			return structure_rect
		return house_rect

	var cells := OverlayUtilsClass.get_house_footprint_cells(_game_state, house_id)
	if not cells.is_empty():
		return DinnertimeAnimationPositionHelpersClass.get_piece_canvas_rect(_map_canvas, cells, _get_world_origin())
	var anchor := OverlayUtilsClass.get_house_anchor_world_pos(_game_state, house_id)
	if anchor != Vector2i(-1, -1):
		var house_mask := [[1, 1], [1, 1]]
		var footprint: Array[Vector2i] = MapUtilsClass.get_footprint_cells(house_mask, Vector2i.ZERO, anchor, 0)
		return DinnertimeAnimationPositionHelpersClass.get_piece_canvas_rect(_map_canvas, footprint, _get_world_origin())
	return Rect2()

func _unique_house_ids_from_order(order: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var seen: Dictionary = {}
	var house_events_val = order.get("house_events", [])
	if house_events_val is Array:
		for evt_val in house_events_val:
			if not (evt_val is Dictionary):
				continue
			var evt: Dictionary = evt_val
			var hid := str(evt.get("house_id", "")).strip_edges()
			if hid.is_empty() or seen.has(hid):
				continue
			seen[hid] = true
			out.append(hid)
	if not out.is_empty():
		return out
	var affected_val = order.get("affected_houses", [])
	if affected_val is Array:
		for h_val in affected_val:
			var hid2 := str(h_val).strip_edges()
			if hid2.is_empty() or seen.has(hid2):
				continue
			seen[hid2] = true
			out.append(hid2)
	return out

func _create_anim_layer() -> void:
	if _scene == null:
		return
	_anim_layer = Control.new()
	_anim_layer.name = "MarketingAnimLayer"
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
	_map_anim_layer.name = "MarketingMapAnimLayer"
	_map_anim_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_map_anim_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiZClass.apply_absolute(_map_anim_layer, UiZClass.DINNERTIME_OVERLAY)
	(_map_canvas as Control).add_child(_map_anim_layer)

func _create_control_bar() -> void:
	if _scene == null:
		return
	_control_bar = PanelContainer.new()
	_control_bar.name = "MarketingControlBar"
	_control_bar.anchor_left = 0.5
	_control_bar.anchor_right = 0.5
	_control_bar.anchor_top = 1.0
	_control_bar.anchor_bottom = 1.0
	_control_bar.offset_left = -210
	_control_bar.offset_right = 210
	_control_bar.offset_top = -56
	_control_bar.offset_bottom = -8
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.12, 0.12, 0.90)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(8)
	_control_bar.add_theme_stylebox_override("panel", style)

	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 12)
	_control_bar.add_child(hbox)

	var progress := Label.new()
	progress.name = "ProgressLabel"
	progress.add_theme_font_size_override("font_size", 14)
	progress.add_theme_color_override("font_color", Color(0.92, 0.95, 0.88, 1))
	hbox.add_child(progress)

	var skip_btn := Button.new()
	skip_btn.name = "SkipBtn"
	skip_btn.text = "跳过全部"
	skip_btn.custom_minimum_size = Vector2(88, 32)
	UiStylesClass.apply_button_secondary(skip_btn)
	skip_btn.pressed.connect(skip_all)
	hbox.add_child(skip_btn)

	UiZClass.apply_absolute(_control_bar, UiZClass.DINNERTIME_CONTROL_BAR)
	_scene.add_child(_control_bar)

func _update_control_bar() -> void:
	if not is_instance_valid(_control_bar):
		return
	var lbl: Label = _control_bar.find_child("ProgressLabel", true, false)
	if lbl != null:
		lbl.text = "营销结算 (%d/%d)" % [mini(_current_idx, _orders.size()), _orders.size()]

func _finish() -> void:
	if _state == State.DONE:
		return
	_state = State.DONE
	_kill_all_tweens()
	if is_instance_valid(_control_bar):
		_control_bar.queue_free()
	_control_bar = null
	if is_instance_valid(_anim_layer):
		for child in _anim_layer.get_children():
			child.queue_free()
	if is_instance_valid(_map_anim_layer):
		for child2 in _map_anim_layer.get_children():
			child2.queue_free()
	settlement_completed.emit()

func _kill_all_tweens() -> void:
	for tween in _active_tweens:
		if is_instance_valid(tween):
			tween.kill()
	_active_tweens.clear()

func _ensure_skin() -> void:
	if _skin != null:
		return
	var base_dir := ModulesBaseDirClass.get_base_dir()
	var mods: Array[String] = []
	if Globals != null and (Globals.enabled_modules_v2 is Array):
		mods = Array(Globals.enabled_modules_v2, TYPE_STRING, "", null)
	_skin = UiSkinCacheClass.get_skin_for_modules(base_dir, mods, 40)

func _get_product_texture(product_id: String) -> Texture2D:
	if _skin == null:
		return null
	var pid := str(product_id).strip_edges()
	if pid == "cola":
		pid = "soda"
	if pid.is_empty():
		return null
	return _skin.get_product_icon_texture(pid)

func _get_world_origin() -> Vector2i:
	return DinnertimeAnimationPositionHelpersClass.get_world_origin(_map_canvas)

func _get_cell_size() -> float:
	return DinnertimeAnimationPositionHelpersClass.get_cell_size(_map_canvas)

func _wait(seconds: float) -> void:
	if _scene == null or not is_instance_valid(_scene):
		return
	var tree := _scene.get_tree()
	if tree == null:
		return
	await tree.create_timer(maxf(0.01, float(seconds) / _speed)).timeout

func _read_vector2i(value, fallback: Vector2i) -> Vector2i:
	if value is Vector2i:
		return Vector2i(value)
	if value is Vector2:
		var v: Vector2 = value
		return Vector2i(int(v.x), int(v.y))
	if value is Array:
		var arr: Array = value
		if arr.size() == 2:
			return Vector2i(int(arr[0]), int(arr[1]))
	return fallback

func _color_for_marketing_type(marketing_type: String, alpha: float) -> Color:
	match marketing_type:
		"radio":
			return Color(0.32, 0.62, 1.0, alpha)
		"airplane":
			return Color(0.88, 0.88, 1.0, alpha)
		"mailbox":
			return Color(0.32, 0.78, 0.50, alpha)
		_:
			return Color(1.0, 0.76, 0.22, alpha)
