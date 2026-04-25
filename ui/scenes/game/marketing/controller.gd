# 营销结算动画控制器
# 自动逐个展示广告牌生效和房屋需求增加。
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
const RADIO_WAVE_PERIOD_SEC := 2.35
const AIRPLANE_FLY_SEC := 2.85
const AIRPLANE_DROP_TOKEN_SEC := 0.46
const AIRPLANE_DROP_START_RATIO := 0.18
const AIRPLANE_DROP_END_RATIO := 0.76

class RadioWaveLoopNode:
	extends Control

	var wave_color: Color = Color(0.32, 0.62, 1.0, 0.55)
	var center: Vector2 = Vector2.ZERO
	var min_radius: float = 12.0
	var max_radius: float = 120.0
	var wave_period: float = 1.05
	var wave_count: int = 4
	var line_width: float = 3.0
	var _elapsed: float = 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_process(true)

	func _process(delta: float) -> void:
		_elapsed += delta
		queue_redraw()

	func _draw() -> void:
		if max_radius <= min_radius:
			return
		var period := maxf(0.05, wave_period)
		var count := maxi(1, wave_count)
		for i in range(count):
			var phase := fposmod((_elapsed / period) - (float(i) / float(count)), 1.0)
			var eased := 1.0 - pow(1.0 - phase, 2.0)
			var radius := lerpf(min_radius, max_radius, eased)
			var c := wave_color
			c.a *= clampf((1.0 - phase) * 1.15, 0.0, 1.0)
			if c.a <= 0.01:
				continue
			draw_arc(center, radius, 0.0, TAU, 96, c, line_width, true)

class AirplaneBoardFlightNode:
	extends Control

	var marketing_texture: Texture2D = null
	var product_texture: Texture2D = null
	var board_number: int = 0
	var remaining_text: String = ""
	var cell_size: float = 40.0
	var rotate_marketing_texture: bool = false

	func _draw() -> void:
		var rect := Rect2(Vector2.ZERO, size)
		draw_rect(rect, Color("#98a295"), true)
		var icon_pad := maxf(2.0, cell_size * 0.08)
		var icon_rect := rect.grow(-icon_pad)
		if marketing_texture != null:
			if rotate_marketing_texture:
				var center_pos := icon_rect.position + icon_rect.size * 0.5
				var draw_size := Vector2(icon_rect.size.y, icon_rect.size.x)
				draw_set_transform(center_pos, deg_to_rad(90.0), Vector2.ONE)
				_draw_texture_fit(marketing_texture, Rect2(-draw_size * 0.5, draw_size), Color(1, 1, 1, 0.45))
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			else:
				_draw_texture_fit(marketing_texture, icon_rect, Color(1, 1, 1, 0.45))
		_draw_board_badge()
		_draw_product()

	func _draw_product() -> void:
		if product_texture == null:
			return
		var pad := maxf(2.0, cell_size * 0.12)
		var avail := size - Vector2(pad * 2.0, pad * 2.0)
		var s := minf(avail.x, avail.y) * 0.85
		if s <= 1.0:
			return
		var product_rect := Rect2((size - Vector2(s, s)) * 0.5, Vector2(s, s))
		_draw_texture_fit(product_texture, product_rect, Color(1, 1, 1, 0.95))
		if remaining_text.is_empty():
			return
		var font: Font = ThemeDB.fallback_font
		var font_size := maxi(10, int(round(minf(product_rect.size.x, product_rect.size.y) * 0.55)))
		if remaining_text.length() >= 2:
			font_size = int(round(float(font_size) * 0.85))
		if remaining_text.length() >= 3:
			font_size = int(round(float(font_size) * 0.75))
		font_size = maxi(10, font_size)
		var baseline := Vector2(product_rect.position.x, product_rect.position.y + product_rect.size.y * 0.5 + float(font_size) * 0.35)
		draw_string(font, baseline + Vector2(1, 1), remaining_text, HORIZONTAL_ALIGNMENT_CENTER, product_rect.size.x, font_size, Color(0, 0, 0, 0.85))
		draw_string(font, baseline, remaining_text, HORIZONTAL_ALIGNMENT_CENTER, product_rect.size.x, font_size, Color(1, 1, 1, 1))

	func _draw_board_badge() -> void:
		if board_number <= 0:
			return
		var badge_size := maxf(14.0, cell_size * 0.42)
		var margin := maxf(2.0, cell_size * 0.06)
		var badge_rect := Rect2(Vector2(size.x - badge_size - margin, margin), Vector2(badge_size, badge_size))
		draw_rect(badge_rect, Color(0.05, 0.06, 0.06, 0.72), true)
		var font: Font = ThemeDB.fallback_font
		var font_size := maxi(9, int(round(badge_size * 0.58)))
		var text := str(board_number)
		var baseline := Vector2(badge_rect.position.x, badge_rect.position.y + badge_rect.size.y * 0.5 + float(font_size) * 0.35)
		draw_string(font, baseline, text, HORIZONTAL_ALIGNMENT_CENTER, badge_rect.size.x, font_size, Color(1, 1, 1, 1))

	func _draw_texture_fit(texture: Texture2D, rect: Rect2, modulate: Color) -> void:
		var fit_rect := _texture_fit_rect(texture, rect)
		draw_texture_rect(texture, fit_rect, false, modulate)

	func _texture_fit_rect(texture: Texture2D, rect: Rect2) -> Rect2:
		if texture == null:
			return rect
		var tex_size := texture.get_size()
		if tex_size.x <= 0.0 or tex_size.y <= 0.0 or rect.size.x <= 0.0 or rect.size.y <= 0.0:
			return rect
		var scale := minf(rect.size.x / tex_size.x, rect.size.y / tex_size.y)
		var draw_size := tex_size * scale
		return Rect2(rect.position + (rect.size - draw_size) * 0.5, draw_size)

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
var _hidden_demand_counts_by_house: Dictionary = {}

static func build_initial_hidden_demand_counts(orders: Array) -> Dictionary:
	var hidden := {}
	for order_val in orders:
		if not (order_val is Dictionary):
			continue
		var order: Dictionary = order_val
		var fallback_product := str(order.get("product", "")).strip_edges()
		var house_events_val = order.get("house_events", [])
		if not (house_events_val is Array):
			continue
		for evt_val in house_events_val:
			if not (evt_val is Dictionary):
				continue
			var evt: Dictionary = evt_val
			var amount_added := int(evt.get("amount_added", 0))
			if amount_added <= 0:
				continue
			var house_id := str(evt.get("house_id", "")).strip_edges()
			if house_id.is_empty():
				continue
			var product_id := str(evt.get("product", fallback_product)).strip_edges()
			if product_id.is_empty():
				continue
			var house_counts: Dictionary = hidden.get(house_id, {})
			house_counts[product_id] = int(house_counts.get(product_id, 0)) + amount_added
			hidden[house_id] = house_counts
	return hidden

static func reveal_hidden_demand_counts_for_event(hidden_counts: Dictionary, event: Dictionary, fallback_product: String = "") -> Dictionary:
	var house_id := str(event.get("house_id", "")).strip_edges()
	if house_id.is_empty():
		return hidden_counts
	var product_id := str(event.get("product", fallback_product)).strip_edges()
	if product_id.is_empty():
		return hidden_counts
	var amount_added := int(event.get("amount_added", 0))
	if amount_added <= 0:
		return hidden_counts
	var house_counts_val = hidden_counts.get(house_id, null)
	if not (house_counts_val is Dictionary):
		return hidden_counts
	var house_counts: Dictionary = house_counts_val
	var remaining := maxi(0, int(house_counts.get(product_id, 0)) - amount_added)
	if remaining <= 0:
		house_counts.erase(product_id)
	else:
		house_counts[product_id] = remaining
	if house_counts.is_empty():
		hidden_counts.erase(house_id)
	else:
		hidden_counts[house_id] = house_counts
	return hidden_counts

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
	_apply_initial_demand_mask()
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
	_clear_demand_mask()
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
	var unique_houses := _unique_house_ids_from_order(order)
	var loop_effect := _start_campaign_loop_effect(order, board_rect, unique_houses)
	if str(order.get("type", "")) == "airplane":
		await _play_airplane_order(order, board_rect, unique_houses, loop_effect)
		return
	await _pulse_board(order, board_rect)
	await _play_campaign_range_effect(order, board_rect, unique_houses)

	var house_events_val = order.get("house_events", [])
	var house_events: Array = house_events_val if house_events_val is Array else []
	for evt_val in house_events:
		if _state != State.PLAYING:
			_stop_campaign_loop_effect(loop_effect)
			return
		if not (evt_val is Dictionary):
			continue
		await _play_house_demand_event(order, evt_val, board_rect)

	_stop_campaign_loop_effect(loop_effect)

func _play_airplane_order(order: Dictionary, board_rect: Rect2, unique_houses: Array[String], loop_effect: Control) -> void:
	await _pulse_board(order, board_rect)
	var flight := _create_airplane_flight_effect(order, board_rect)
	var house_events_val = order.get("house_events", [])
	var house_events: Array = house_events_val if house_events_val is Array else []
	var drop_tail_sec := _schedule_airplane_house_drops(order, house_events, flight)
	await _play_campaign_house_range_pulse(order, unique_houses)
	await _await_campaign_effect(flight)
	if drop_tail_sec > AIRPLANE_FLY_SEC:
		await _wait(drop_tail_sec - AIRPLANE_FLY_SEC)
	_stop_campaign_loop_effect(loop_effect)

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

func _play_campaign_house_range_pulse(order: Dictionary, unique_houses: Array[String]) -> void:
	if not is_instance_valid(_map_anim_layer):
		return
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

	var tw := _map_anim_layer.create_tween().set_parallel(true)
	_active_tweens.append(tw)
	for n in nodes:
		tw.tween_property(n, "modulate:a", 1.0, 0.16 / _speed)
		tw.tween_property(n, "modulate:a", 0.0, 0.28 / _speed).set_delay(0.16 / _speed)
	tw.chain().tween_callback(func():
		for n2 in nodes:
			if is_instance_valid(n2):
				n2.queue_free()
		_active_tweens.erase(tw)
	)
	await tw.finished

func _play_campaign_range_effect(order: Dictionary, board_rect: Rect2, unique_houses: Array[String]) -> void:
	if not is_instance_valid(_map_anim_layer):
		return
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

	var effect := _create_campaign_effect(order, board_rect, unique_houses)
	var sweep: Control = effect.get("node", null)
	var effect_tweens: Array = effect.get("tweens", [])
	var custom_effect := bool(effect.get("custom", false))
	var tw := _map_anim_layer.create_tween().set_parallel(true)
	_active_tweens.append(tw)
	for n in nodes:
		tw.tween_property(n, "modulate:a", 1.0, 0.16 / _speed)
		tw.tween_property(n, "modulate:a", 0.0, 0.28 / _speed).set_delay(0.16 / _speed)
	if is_instance_valid(sweep) and not custom_effect:
		tw.tween_property(sweep, "modulate:a", 0.0, 0.44 / _speed).set_delay(0.05 / _speed)
	tw.chain().tween_callback(func():
		for n2 in nodes:
			if is_instance_valid(n2):
				n2.queue_free()
		if is_instance_valid(sweep) and not custom_effect:
			sweep.queue_free()
		_active_tweens.erase(tw)
	)
	await tw.finished
	for effect_tw_val in effect_tweens:
		if effect_tw_val is Tween:
			var effect_tw: Tween = effect_tw_val
			if is_instance_valid(effect_tw) and effect_tw.is_running():
				await effect_tw.finished
	if is_instance_valid(sweep):
		sweep.queue_free()

func _await_campaign_effect(effect: Dictionary) -> void:
	var node: Control = effect.get("node", null)
	var effect_tweens: Array = effect.get("tweens", [])
	for effect_tw_val in effect_tweens:
		if effect_tw_val is Tween:
			var effect_tw: Tween = effect_tw_val
			if is_instance_valid(effect_tw) and effect_tw.is_running():
				await effect_tw.finished
	if is_instance_valid(node):
		node.queue_free()

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

	var product_id := str(event.get("product", order.get("product", "")))
	var count := mini(amount_added, TOKEN_MAX_PER_HOUSE_EVENT)
	for i in range(count):
		await _fly_product_token(product_id, board_rect, house_rect, i, count)
		_reveal_house_demand_amount(order, event, 1)
	var unshown_count := amount_added - count
	if unshown_count > 0:
		_reveal_house_demand_amount(order, event, unshown_count)
	await _pulse_house(house_rect)

func _schedule_airplane_house_drops(order: Dictionary, house_events: Array, flight: Dictionary) -> float:
	if _scene == null or not is_instance_valid(_scene):
		return 0.0
	var tree := _scene.get_tree()
	if tree == null:
		return 0.0
	var events: Array[Dictionary] = []
	for evt_val in house_events:
		if evt_val is Dictionary:
			events.append(evt_val)
	if events.is_empty():
		return 0.0
	var denom := maxf(1.0, float(events.size() - 1))
	var max_delay_sec := 0.0
	for i in range(events.size()):
		var t := 0.5
		if events.size() > 1:
			t = float(i) / denom
		var ratio := _airplane_drop_ratio_for_event(events[i], flight)
		if ratio < 0.0:
			ratio = lerpf(AIRPLANE_DROP_START_RATIO, AIRPLANE_DROP_END_RATIO, t)
		var delay_sec := maxf(0.0, AIRPLANE_FLY_SEC * ratio)
		max_delay_sec = maxf(max_delay_sec, delay_sec)
		var event_for_timer: Dictionary = events[i]
		var timer := tree.create_timer(maxf(0.01, delay_sec / _speed))
		timer.timeout.connect(_on_airplane_house_drop_timeout.bind(order, event_for_timer, flight))
	return max_delay_sec + AIRPLANE_DROP_TOKEN_SEC + HOUSE_PULSE_SEC

func _airplane_drop_ratio_for_event(event: Dictionary, flight: Dictionary) -> float:
	var start_val = flight.get("start_center", null)
	var end_val = flight.get("end_center", null)
	if not (start_val is Vector2) or not (end_val is Vector2):
		return -1.0
	var start_center: Vector2 = start_val
	var end_center: Vector2 = end_val
	var travel := end_center - start_center
	var travel_len_sq := travel.length_squared()
	if travel_len_sq <= 0.01:
		return -1.0
	var house_id := str(event.get("house_id", "")).strip_edges()
	if house_id.is_empty():
		return -1.0
	var house_rect := _compute_house_rect(house_id)
	if house_rect.size == Vector2.ZERO:
		return -1.0
	var house_center := house_rect.position + house_rect.size * 0.5
	var raw_ratio := (house_center - start_center).dot(travel) / travel_len_sq
	return clampf(raw_ratio, AIRPLANE_DROP_START_RATIO, AIRPLANE_DROP_END_RATIO)

func _on_airplane_house_drop_timeout(order: Dictionary, event: Dictionary, flight: Dictionary) -> void:
	if _state != State.PLAYING:
		return
	_start_airplane_house_drop_event(order, event, flight)

func _start_airplane_house_drop_event(order: Dictionary, event: Dictionary, flight: Dictionary) -> void:
	var house_id := str(event.get("house_id", "")).strip_edges()
	if house_id.is_empty():
		return
	var house_rect := _compute_house_rect(house_id)
	if house_rect.size == Vector2.ZERO:
		return
	var amount_added := int(event.get("amount_added", 0))
	if amount_added <= 0:
		_show_capped_marker(house_rect)
		return
	var source: Control = flight.get("board", null)
	if not is_instance_valid(source):
		return
	var product_id := str(event.get("product", order.get("product", "")))
	var count := mini(amount_added, TOKEN_MAX_PER_HOUSE_EVENT)
	var unshown_count := amount_added - count
	for i in range(count):
		var reveal_amount := 1
		if i == count - 1:
			reveal_amount += unshown_count
		var reveal_for_token := reveal_amount
		_drop_product_token_from_airplane(
			product_id,
			source,
			house_rect,
			i,
			count,
			func():
				_reveal_house_demand_amount(order, event, reveal_for_token)
				_start_house_pulse(house_rect)
		)

func _drop_product_token_from_airplane(
	product_id: String,
	source: Control,
	house_rect: Rect2,
	index: int,
	total: int,
	on_landed: Callable
) -> void:
	if not is_instance_valid(_map_anim_layer) or not is_instance_valid(source):
		return
	var icon_size := maxf(18.0, _get_cell_size() * 0.68)
	var token := Control.new()
	token.name = "MarketingAirplaneDemandDrop"
	token.size = Vector2(icon_size, icon_size)
	token.custom_minimum_size = token.size
	token.pivot_offset = token.size * 0.5
	token.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var from_pos := source.position + source.size * 0.5 - token.size * 0.5
	var to_pos := house_rect.position + house_rect.size * 0.5 - token.size * 0.5
	if total > 1:
		var angle := TAU * float(index) / float(total)
		to_pos += Vector2(cos(angle), sin(angle)) * minf(_get_cell_size() * 0.18, 12.0)
	token.position = from_pos
	token.scale = Vector2(0.90, 0.90)
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

	var tw := token.create_tween()
	_active_tweens.append(tw)
	var dur := AIRPLANE_DROP_TOKEN_SEC / _speed
	var arc_pos := Vector2((from_pos.x + to_pos.x) * 0.5, minf(from_pos.y, to_pos.y) - maxf(10.0, _get_cell_size() * 0.32))
	tw.tween_property(token, "position", arc_pos, dur * 0.42).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(token, "position", to_pos, dur * 0.58).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.tween_callback(func():
		if on_landed.is_valid():
			on_landed.call()
	)
	tw.tween_property(token, "scale", Vector2(1.10, 1.10), 0.06 / _speed)
	tw.parallel().tween_property(token, "modulate:a", 0.0, 0.16 / _speed)
	tw.tween_callback(func():
		if is_instance_valid(token):
			token.queue_free()
		_active_tweens.erase(tw)
	)

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
	_start_house_pulse(house_rect)
	await _wait(HOUSE_PULSE_SEC)

func _start_house_pulse(house_rect: Rect2) -> void:
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

func _start_campaign_loop_effect(order: Dictionary, board_rect: Rect2, unique_houses: Array[String]) -> Control:
	var marketing_type := str(order.get("type", ""))
	match marketing_type:
		"radio":
			return _create_radio_wave_loop_effect(board_rect, unique_houses)
		_:
			return null

func _stop_campaign_loop_effect(effect: Control) -> void:
	if is_instance_valid(effect):
		effect.queue_free()

func _create_campaign_effect(order: Dictionary, board_rect: Rect2, _unique_houses: Array[String]) -> Dictionary:
	var marketing_type := str(order.get("type", ""))
	match marketing_type:
		"radio":
			return {
				"node": null,
				"tweens": [],
				"custom": true,
			}
		"airplane":
			return _create_airplane_flight_effect(order, board_rect)
		_:
			return {
				"node": _create_campaign_sweep(order, board_rect),
				"tweens": [],
				"custom": false,
			}

func _create_radio_wave_loop_effect(board_rect: Rect2, unique_houses: Array[String]) -> Control:
	if not is_instance_valid(_map_anim_layer):
		return null
	var bounds := board_rect
	for house_id in unique_houses:
		var house_rect := _compute_house_rect(str(house_id))
		if house_rect.size == Vector2.ZERO:
			continue
		bounds = bounds.merge(house_rect)
	var center := board_rect.position + board_rect.size * 0.5
	var max_distance := 0.0
	for corner in [
		bounds.position,
		bounds.position + Vector2(bounds.size.x, 0.0),
		bounds.position + Vector2(0.0, bounds.size.y),
		bounds.position + bounds.size,
	]:
		max_distance = maxf(max_distance, center.distance_to(corner))
	var wave := RadioWaveLoopNode.new()
	wave.name = "MarketingRadioWaveLoop"
	wave.set_anchors_preset(Control.PRESET_FULL_RECT)
	wave.position = Vector2.ZERO
	wave.size = _map_anim_layer.size
	if wave.size == Vector2.ZERO and _map_canvas is Control:
		wave.size = (_map_canvas as Control).size
	wave.center = center
	wave.min_radius = maxf(_get_cell_size() * 0.35, 8.0)
	wave.max_radius = maxf(max_distance * 1.08, _get_cell_size() * 3.2)
	wave.wave_period = RADIO_WAVE_PERIOD_SEC / _speed
	wave.wave_count = 3
	wave.wave_color = _color_for_marketing_type("radio", 0.54)
	wave.line_width = maxf(2.0, _get_cell_size() * 0.07)
	_map_anim_layer.add_child(wave)
	return wave

func _create_airplane_flight_effect(order: Dictionary, board_rect: Rect2) -> Dictionary:
	if not is_instance_valid(_map_anim_layer):
		return {}
	var path := _compute_airplane_flight_path(order, board_rect)
	var start_center: Vector2 = path.get("start", board_rect.position + board_rect.size * 0.5)
	var end_center: Vector2 = path.get("end", board_rect.position + board_rect.size * 0.5)
	var axis := str(path.get("axis", "row"))
	var dir: Vector2 = end_center - start_center
	var cs := maxf(_get_cell_size(), 1.0)
	var board_size := _compute_airplane_board_flight_size(order, board_rect)
	if dir.length() > 0.01:
		var dir_norm := dir.normalized()
		var travel_pad := maxf(cs, maxf(board_size.x, board_size.y) * 0.65)
		start_center -= dir_norm * travel_pad
		end_center += dir_norm * travel_pad
		dir = end_center - start_center

	var parent := Control.new()
	parent.name = "MarketingAirplaneBoardFlightEffect"
	parent.position = Vector2.ZERO
	parent.size = _map_anim_layer.size
	parent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map_anim_layer.add_child(parent)

	var trail := ColorRect.new()
	trail.name = "MarketingAirplaneTrail"
	trail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	trail.color = _color_for_marketing_type("airplane", 0.20)
	trail.modulate.a = 0.0
	if axis == "col":
		var y0 := minf(start_center.y, end_center.y)
		var y1 := maxf(start_center.y, end_center.y)
		trail.position = Vector2(start_center.x - cs * 0.30, y0)
		trail.size = Vector2(cs * 0.60, y1 - y0)
	else:
		var x0 := minf(start_center.x, end_center.x)
		var x1 := maxf(start_center.x, end_center.x)
		trail.position = Vector2(x0, start_center.y - cs * 0.30)
		trail.size = Vector2(x1 - x0, cs * 0.60)
	parent.add_child(trail)

	var board: Control = _create_airplane_board_flight_visual(order, board_size)
	board.position = start_center - board_size * 0.5
	board.modulate.a = 0.0
	parent.add_child(board)

	var tw := parent.create_tween().set_parallel(true)
	_active_tweens.append(tw)
	tw.tween_property(trail, "modulate:a", 1.0, 0.10 / _speed)
	tw.tween_property(trail, "modulate:a", 0.0, 0.36 / _speed).set_delay((AIRPLANE_FLY_SEC * 0.72) / _speed)
	tw.tween_property(board, "modulate:a", 1.0, 0.12 / _speed)
	tw.tween_property(board, "position", end_center - board_size * 0.5, AIRPLANE_FLY_SEC / _speed).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	tw.tween_property(board, "modulate:a", 0.0, 0.24 / _speed).set_delay((AIRPLANE_FLY_SEC * 0.90) / _speed)
	tw.chain().tween_callback(func():
		_active_tweens.erase(tw)
	)
	return {
		"node": parent,
		"tweens": [tw],
		"board": board,
		"start_center": start_center,
		"end_center": end_center,
		"custom": true,
	}

func _compute_airplane_board_flight_size(order: Dictionary, board_rect: Rect2) -> Vector2:
	var cs := maxf(_get_cell_size(), 1.0)
	var base_size := _read_vector2i(order.get("footprint_size", [1, 1]), Vector2i.ONE)
	if base_size.x <= 0 or base_size.y <= 0:
		base_size = Vector2i.ONE
	var thickness := 2
	var length := 1
	if base_size.x == 2 and base_size.y != 2:
		length = base_size.y
	elif base_size.y == 2 and base_size.x != 2:
		length = base_size.x
	else:
		thickness = mini(base_size.x, base_size.y)
		length = maxi(base_size.x, base_size.y)
	var axis := str(order.get("axis", "")).strip_edges()
	if axis == "row":
		return Vector2(maxi(1, thickness) * cs, maxi(1, length) * cs)
	if axis == "col":
		return Vector2(maxi(1, length) * cs, maxi(1, thickness) * cs)
	if board_rect.size != Vector2.ZERO:
		return board_rect.size
	return Vector2(maxi(1, base_size.x) * cs, maxi(1, base_size.y) * cs)

func _create_airplane_board_flight_visual(order: Dictionary, board_size: Vector2) -> Control:
	var board := AirplaneBoardFlightNode.new()
	board.name = "MarketingAirplaneBoard"
	board.size = board_size
	board.custom_minimum_size = board_size
	board.pivot_offset = board_size * 0.5
	board.cell_size = maxf(_get_cell_size(), 1.0)
	board.board_number = int(order.get("board_number", 0))
	board.remaining_text = _read_duration_label(order)
	board.rotate_marketing_texture = board_size.y > board_size.x
	if _skin != null:
		board.marketing_texture = _skin.get_marketing_texture("airplane")
	board.product_texture = _get_product_texture(str(order.get("product", "")))
	board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return board

func _read_duration_label(order: Dictionary) -> String:
	var rd := int(order.get("duration_after", order.get("duration_before", 0)))
	if rd == -1:
		return "无限"
	if rd > 0:
		return str(rd)
	return ""

func _compute_airplane_flight_path(order: Dictionary, board_rect: Rect2) -> Dictionary:
	var axis := str(order.get("axis", "")).strip_edges()
	if axis != "row" and axis != "col":
		axis = "row" if board_rect.size.x >= board_rect.size.y else "col"
	var world_pos := _read_vector2i(order.get("world_pos", [0, 0]), Vector2i.ZERO)
	var minp := _get_map_world_min()
	var maxp := _get_map_world_max()
	var start_world := world_pos
	var end_world := world_pos
	if axis == "col":
		var x := clampi(world_pos.x, minp.x, maxp.x)
		var from_bottom := world_pos.y > int(floor(float(minp.y + maxp.y) * 0.5))
		start_world = Vector2i(x, maxp.y if from_bottom else minp.y)
		end_world = Vector2i(x, minp.y if from_bottom else maxp.y)
	else:
		var y := clampi(world_pos.y, minp.y, maxp.y)
		var from_right := world_pos.x > int(floor(float(minp.x + maxp.x) * 0.5))
		start_world = Vector2i(maxp.x if from_right else minp.x, y)
		end_world = Vector2i(minp.x if from_right else maxp.x, y)
	return {
		"axis": axis,
		"start": _world_cell_center(start_world),
		"end": _world_cell_center(end_world),
	}

func _world_cell_center(world_pos: Vector2i) -> Vector2:
	var view_pos := world_pos - _get_world_origin()
	var cs := maxf(_get_cell_size(), 1.0)
	return Vector2(view_pos) * cs + Vector2(cs, cs) * 0.5

func _get_map_world_min() -> Vector2i:
	if _game_state == null or not (_game_state.map is Dictionary):
		return Vector2i.ZERO
	var origin: Vector2i = _game_state.map.get("map_origin", Vector2i.ZERO)
	return -origin

func _get_map_world_max() -> Vector2i:
	if _game_state == null or not (_game_state.map is Dictionary):
		return Vector2i.ZERO
	var grid_size: Vector2i = _game_state.map.get("grid_size", Vector2i.ZERO)
	var origin: Vector2i = _game_state.map.get("map_origin", Vector2i.ZERO)
	if grid_size.x <= 0 or grid_size.y <= 0:
		return Vector2i.ZERO
	return Vector2i(grid_size.x - origin.x - 1, grid_size.y - origin.y - 1)

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

func _apply_initial_demand_mask() -> void:
	_hidden_demand_counts_by_house = build_initial_hidden_demand_counts(_orders)
	_sync_demand_mask_to_canvas()

func _reveal_house_demand_event(order: Dictionary, event: Dictionary) -> void:
	_reveal_house_demand_amount(order, event, int(event.get("amount_added", 0)))

func _reveal_house_demand_amount(order: Dictionary, event: Dictionary, amount: int) -> void:
	if _hidden_demand_counts_by_house.is_empty():
		return
	if amount <= 0:
		return
	var reveal_event := event.duplicate(true)
	reveal_event["amount_added"] = amount
	_hidden_demand_counts_by_house = reveal_hidden_demand_counts_for_event(
		_hidden_demand_counts_by_house,
		reveal_event,
		str(order.get("product", "")).strip_edges()
	)
	_sync_demand_mask_to_canvas()

func _sync_demand_mask_to_canvas() -> void:
	if _map_canvas == null or not is_instance_valid(_map_canvas):
		return
	if not _map_canvas.has_method("set_hidden_demand_counts_by_house"):
		return
	_map_canvas.call("set_hidden_demand_counts_by_house", _hidden_demand_counts_by_house)

func _clear_demand_mask() -> void:
	_hidden_demand_counts_by_house.clear()
	if _map_canvas == null or not is_instance_valid(_map_canvas):
		return
	if _map_canvas.has_method("clear_hidden_demand_counts_by_house"):
		_map_canvas.call("clear_hidden_demand_counts_by_house")

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
	_clear_demand_mask()
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
