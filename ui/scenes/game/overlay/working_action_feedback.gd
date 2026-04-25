# 工作时间行动地图反馈
# 监听 Working 阶段的即时行动事件，在地图画布上播放非阻塞动效。
class_name WorkingActionFeedbackController
extends RefCounted

const UiSkinCacheClass = preload("res://ui/visual/ui_skin_cache.gd")
const UiZClass = preload("res://ui/utils/ui_z.gd")
const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")
const ProductRegistryClass = preload("res://core/data/product_registry.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const ModulesBaseDirClass = preload("res://ui/utils/modules_base_dir.gd")

const TOKEN_FLY_SEC := 0.56
const TOKEN_EMIT_GAP_SEC := 0.12
const BURST_TOTAL_SEC := 0.62
const PULSE_SEC := 0.34
const MAX_TOKENS_PER_FEEDBACK := 5

var _scene = null
var _map_canvas = null
var _layer: Control = null
var _skin = null
var _speed: float = 1.0
var _eventbus_source: String = ""
var _pending_events: Array[Dictionary] = []
var _flush_scheduled: bool = false
var _active_tweens: Array[Tween] = []
var _handled_sequences: Dictionary = {}

func _init(scene, map_canvas) -> void:
	_scene = scene
	_map_canvas = map_canvas
	_eventbus_source = "WorkingActionFeedback:%s" % str(get_instance_id())

func initialize() -> void:
	if OS.has_feature("headless"):
		return
	EventBus.subscribe(EventBus.EventType.FOOD_PRODUCED, Callable(self, "_on_feedback_event"), 130, _eventbus_source)
	EventBus.subscribe(EventBus.EventType.DRINKS_PROCURED, Callable(self, "_on_feedback_event"), 130, _eventbus_source)
	EventBus.subscribe(EventBus.EventType.EMPLOYEE_RECRUITED, Callable(self, "_on_feedback_event"), 130, _eventbus_source)
	EventBus.subscribe(EventBus.EventType.EMPLOYEE_TRAINED, Callable(self, "_on_feedback_event"), 130, _eventbus_source)
	EventBus.subscribe(EventBus.EventType.COMMAND_EXECUTED, Callable(self, "_on_feedback_event"), 130, _eventbus_source)

func dispose() -> void:
	if not _eventbus_source.is_empty():
		EventBus.unsubscribe_all_from_source(_eventbus_source)
	_eventbus_source = ""
	_pending_events.clear()
	_flush_scheduled = false
	_handled_sequences.clear()
	_kill_tweens()
	if is_instance_valid(_layer):
		_layer.queue_free()
	_layer = null
	_scene = null
	_map_canvas = null
	_skin = null

func clear() -> void:
	_pending_events.clear()
	_flush_scheduled = false
	_kill_tweens()
	if is_instance_valid(_layer):
		for child in _layer.get_children():
			child.queue_free()

func _on_feedback_event(event: Dictionary) -> void:
	if OS.has_feature("headless"):
		return
	if not (event is Dictionary) or event.is_empty():
		return
	var seq := int(event.get("sequence", -1))
	if seq > 0:
		if _handled_sequences.has(seq):
			return
		_handled_sequences[seq] = true
		if _handled_sequences.size() > 256:
			_handled_sequences.clear()
	var type := str(event.get("type", "")).strip_edges()
	if type == EventBus.EventType.COMMAND_EXECUTED:
		var data_val = event.get("data", null)
		var data: Dictionary = data_val if (data_val is Dictionary) else {}
		if not data.has("price_modifier"):
			return
	_pending_events.append(event.duplicate(true))
	if _flush_scheduled:
		return
	_flush_scheduled = true
	call_deferred("_flush_pending_events")

func _flush_pending_events() -> void:
	_flush_scheduled = false
	if _pending_events.is_empty():
		return
	if _scene == null or not is_instance_valid(_scene):
		_pending_events.clear()
		return
	var tree = _scene.get_tree()
	if tree == null:
		_pending_events.clear()
		return
	await tree.process_frame
	if _scene == null or not is_instance_valid(_scene):
		_pending_events.clear()
		return
	var events := _pending_events.duplicate(true)
	_pending_events.clear()
	for event_val in events:
		if not (event_val is Dictionary):
			continue
		_play_event(event_val)

func _play_event(event: Dictionary) -> void:
	var state := _read_live_game_state()
	if state == null:
		return
	if str(state.phase) != DefsClass.PHASE_WORKING:
		return
	if not _ensure_layer():
		return
	_speed = maxf(float(Globals.animation_speed) if Globals != null else 1.0, 0.05)
	_ensure_skin(state)

	var data_val = event.get("data", null)
	var data: Dictionary = data_val if (data_val is Dictionary) else {}
	var type := str(event.get("type", "")).strip_edges()
	match type:
		EventBus.EventType.FOOD_PRODUCED:
			_play_food_produced(state, data)
		EventBus.EventType.DRINKS_PROCURED:
			_play_drinks_procured(state, data)
		EventBus.EventType.EMPLOYEE_RECRUITED:
			_play_employee_recruited(state, data)
		EventBus.EventType.EMPLOYEE_TRAINED:
			_play_employee_trained(state, data)
		EventBus.EventType.COMMAND_EXECUTED:
			_play_price_modifier(state, data)

func _play_food_produced(state: GameState, data: Dictionary) -> void:
	var player_id := int(data.get("player_id", -1))
	var food_type := _normalize_product_id(str(data.get("food_type", data.get("product", ""))).strip_edges())
	var amount := maxi(1, int(data.get("amount", 1)))
	var rect := _get_player_restaurant_rect(state, player_id)
	if rect.size == Vector2.ZERO:
		rect = _get_map_center_rect()
	_start_rect_pulse(rect, Color(0.94, 0.64, 0.24, 0.28))
	var product_name := _product_name(food_type)
	var label := "+%s" % (product_name if not product_name.is_empty() else food_type)
	if amount > 1:
		label += " x%d" % amount
	_start_action_burst(rect, label, Color(1.0, 0.84, 0.24, 1.0))

func _play_drinks_procured(state: GameState, data: Dictionary) -> void:
	var player_id := int(data.get("player_id", -1))
	var restaurant_id := str(data.get("restaurant_id", "")).strip_edges()
	var target_rect := _get_player_restaurant_rect(state, player_id, restaurant_id)
	if target_rect.size == Vector2.ZERO:
		target_rect = _get_player_restaurant_rect(state, player_id)
	if target_rect.size == Vector2.ZERO:
		target_rect = _get_map_center_rect()
	_start_rect_pulse(target_rect, Color(0.45, 0.82, 1.0, 0.24))

	var picked := _read_picked_sources(data.get("picked_sources", null))
	var procured: Dictionary = data.get("drinks_procured", {}) if (data.get("drinks_procured", null) is Dictionary) else {}
	var route := _read_vector2i_array(data.get("route", null))
	if picked.is_empty():
		var first_product := _first_product_id_from_count_dict(procured)
		var amount := int(procured.get(first_product, 1)) if not first_product.is_empty() else 1
		var drink_name := _product_name(first_product)
		var label := "+%s" % (drink_name if not drink_name.is_empty() else first_product)
		if amount > 1:
			label += " x%d" % amount
		_start_action_burst(target_rect, label, Color(0.42, 0.82, 1.0, 1.0))
		return

	var source_count_by_type := _count_sources_by_type(picked)
	var shown := 0
	for source in picked:
		if shown >= MAX_TOKENS_PER_FEEDBACK:
			break
		var product_id := _normalize_product_id(str(source.get("type", "")).strip_edges())
		var world_pos: Vector2i = source.get("world_pos", Vector2i(-1, -1))
		if product_id.is_empty() or world_pos == Vector2i(-1, -1):
			continue
		var per_source := 1
		var denom := maxi(1, int(source_count_by_type.get(product_id, 1)))
		if procured.has(product_id):
			per_source = maxi(1, int(floor(float(int(procured.get(product_id, 1))) / float(denom))))
		var source_rect := _world_cell_rect(world_pos)
		var points := _build_return_route_points(world_pos, route, target_rect)
		_start_product_token_flight(product_id, source_rect, target_rect, shown, per_source, points, float(shown) * TOKEN_EMIT_GAP_SEC, func():
			_start_rect_pulse(target_rect, Color(0.45, 0.82, 1.0, 0.16))
		)
		shown += 1

	var hidden_count := picked.size() - shown
	if hidden_count > 0:
		var label := "+%d 进货点" % hidden_count
		_start_action_burst(target_rect, label, Color(0.42, 0.82, 1.0, 1.0), 0.28)

func _play_employee_recruited(state: GameState, data: Dictionary) -> void:
	var player_id := int(data.get("player_id", -1))
	var employee_type := str(data.get("employee_type", "")).strip_edges()
	if employee_type.is_empty():
		return
	var rect := _get_player_restaurant_rect(state, player_id)
	if rect.size == Vector2.ZERO:
		rect = _get_map_center_rect()
	_start_rect_pulse(rect, Color(0.76, 0.72, 0.72, 0.24))
	var name := _employee_name(employee_type)
	var label := "招聘 %s" % (name if not name.is_empty() else employee_type)
	if bool(data.get("on_credit", false)):
		label += " 预支"
	_start_action_burst(rect, label, Color(0.92, 0.90, 0.86, 1.0))

func _play_employee_trained(state: GameState, data: Dictionary) -> void:
	var player_id := int(data.get("player_id", -1))
	var from_employee := str(data.get("from_employee", "")).strip_edges()
	var to_employee := str(data.get("to_employee", "")).strip_edges()
	if from_employee.is_empty() or to_employee.is_empty():
		return
	var rect := _get_player_restaurant_rect(state, player_id)
	if rect.size == Vector2.ZERO:
		rect = _get_map_center_rect()
	_start_rect_pulse(rect, Color(0.70, 0.66, 1.0, 0.24))
	var from_name := _employee_name(from_employee)
	var to_name := _employee_name(to_employee)
	var label := "%s -> %s" % [
		from_name if not from_name.is_empty() else from_employee,
		to_name if not to_name.is_empty() else to_employee,
	]
	var steps := maxi(1, int(data.get("steps", 1)))
	if steps > 1:
		label += " %d步" % steps
	if bool(data.get("from_pending", false)):
		label += " 清账"
	_start_action_burst(rect, label, Color(0.80, 0.76, 1.0, 1.0))

func _play_price_modifier(state: GameState, data: Dictionary) -> void:
	if not data.has("price_modifier"):
		return
	var player_id := int(data.get("player_id", -1))
	var action_id := str(data.get("action_id", "")).strip_edges()
	var modifier := int(data.get("price_modifier", 0))
	var rect := _get_player_restaurant_rect(state, player_id)
	if rect.size == Vector2.ZERO:
		rect = _get_map_center_rect()
	var label := ""
	var color := Color(1.0, 0.72, 0.36, 1.0)
	match action_id:
		"set_discount":
			label = "折扣 $%+d" % modifier
			color = Color(1.0, 0.52, 0.28, 1.0)
		"set_luxury_price":
			label = "奢侈 $%+d" % modifier
			color = Color(1.0, 0.86, 0.30, 1.0)
		_:
			label = "售价 $%+d" % modifier
	_start_rect_pulse(rect, Color(color.r, color.g, color.b, 0.22))
	_start_action_burst(rect, label, color)

func _start_action_burst(anchor_rect: Rect2, text: String, color: Color, delay_sec: float = 0.0) -> void:
	if not is_instance_valid(_layer):
		return
	var label_text := str(text).strip_edges()
	if label_text.is_empty():
		return
	var cell_size := maxf(_get_cell_size(), 1.0)
	var min_w := maxf(anchor_rect.size.x * 1.45, cell_size * 2.65)
	min_w = maxf(min_w, float(label_text.length()) * cell_size * 0.42)
	var marker_size := Vector2(min_w, maxf(anchor_rect.size.y * 0.95, cell_size * 1.18))
	var start_pos := anchor_rect.position + anchor_rect.size * 0.5 - marker_size * 0.5

	var marker := Label.new()
	marker.name = "WorkingActionFeedbackBurst"
	marker.text = label_text
	marker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	marker.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	marker.add_theme_font_size_override("font_size", maxi(16, int(cell_size * 0.45)))
	marker.add_theme_color_override("font_color", color)
	marker.add_theme_color_override("font_outline_color", Color(0.04, 0.05, 0.04, 0.95))
	marker.add_theme_constant_override("outline_size", maxi(2, int(round(cell_size * 0.07))))
	marker.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.70))
	marker.add_theme_constant_override("shadow_offset_x", 2)
	marker.add_theme_constant_override("shadow_offset_y", 2)
	marker.position = start_pos
	marker.size = marker_size
	marker.pivot_offset = marker.size * 0.5
	marker.scale = Vector2(0.45, 0.45)
	marker.rotation_degrees = -8.0
	marker.modulate.a = 0.0
	marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(marker)

	var tw := marker.create_tween().set_parallel(true)
	_active_tweens.append(tw)
	var d := maxf(0.0, delay_sec) / _speed
	var rise := maxf(18.0, cell_size * 0.56)
	tw.tween_property(marker, "modulate:a", 1.0, 0.08 / _speed).set_delay(d)
	tw.tween_property(marker, "scale", Vector2(1.30, 1.30), 0.14 / _speed).set_delay(d).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.tween_property(marker, "scale", Vector2(0.96, 0.96), 0.10 / _speed).set_delay(d + 0.14 / _speed).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(marker, "scale", Vector2(1.06, 1.06), 0.12 / _speed).set_delay(d + 0.24 / _speed).set_ease(Tween.EASE_OUT)
	tw.tween_property(marker, "rotation_degrees", 7.0, 0.14 / _speed).set_delay(d).set_ease(Tween.EASE_OUT)
	tw.tween_property(marker, "rotation_degrees", -3.0, 0.10 / _speed).set_delay(d + 0.14 / _speed).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(marker, "rotation_degrees", 0.0, 0.16 / _speed).set_delay(d + 0.24 / _speed).set_ease(Tween.EASE_OUT)
	tw.tween_property(marker, "position:y", marker.position.y - rise, BURST_TOTAL_SEC / _speed).set_delay(d).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(marker, "modulate:a", 0.0, 0.20 / _speed).set_delay(d + 0.42 / _speed)
	tw.chain().tween_callback(func():
		if is_instance_valid(marker):
			marker.queue_free()
		_active_tweens.erase(tw)
	)

func _start_rect_pulse(rect: Rect2, color: Color) -> void:
	if not is_instance_valid(_layer):
		return
	if rect.size == Vector2.ZERO:
		return
	var pulse := ColorRect.new()
	pulse.name = "WorkingActionFeedbackPulse"
	pulse.position = rect.position
	pulse.size = rect.size
	pulse.pivot_offset = rect.size * 0.5
	pulse.color = color
	pulse.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(pulse)
	var tw := pulse.create_tween().set_parallel(true)
	_active_tweens.append(tw)
	tw.tween_property(pulse, "scale", Vector2(1.10, 1.10), PULSE_SEC / _speed).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(pulse, "modulate:a", 0.0, PULSE_SEC / _speed).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(func():
		if is_instance_valid(pulse):
			pulse.queue_free()
		_active_tweens.erase(tw)
	)

func _start_product_token_flight(
	product_id: String,
	source_rect: Rect2,
	target_rect: Rect2,
	index: int,
	amount: int,
	route_points: Array[Vector2],
	delay_sec: float,
	on_landed: Callable = Callable()
) -> void:
	if not is_instance_valid(_layer):
		return
	var icon_size := maxf(18.0, _get_cell_size() * 0.66)
	var token := Control.new()
	token.name = "WorkingActionFeedbackProductToken"
	token.size = Vector2(icon_size, icon_size)
	token.custom_minimum_size = token.size
	token.pivot_offset = token.size * 0.5
	token.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var points := route_points.duplicate()
	if points.size() < 2:
		points = [
			source_rect.position + source_rect.size * 0.5,
			target_rect.position + target_rect.size * 0.5,
		]
	if points.size() >= 2 and index > 0:
		var offset := Vector2(cos(float(index) * 2.399), sin(float(index) * 2.399)) * minf(_get_cell_size() * 0.14, 8.0)
		points[0] = Vector2(points[0]) + offset
		points[points.size() - 1] = Vector2(points[points.size() - 1]) + offset * 0.4

	token.position = Vector2(points[0]) - token.size * 0.5
	token.scale = Vector2(0.78, 0.78)
	_layer.add_child(token)
	_add_product_visual(token, product_id, amount)

	var tw := token.create_tween()
	_active_tweens.append(tw)
	var delay := maxf(0.0, delay_sec) / _speed
	if delay > 0.0:
		tw.tween_interval(delay)
	var top_left_points: Array[Vector2] = []
	for p in points:
		top_left_points.append(Vector2(p) - token.size * 0.5)
	var total_dist := _polyline_length(top_left_points)
	if total_dist <= 0.01:
		total_dist = 1.0
	var dur := TOKEN_FLY_SEC / _speed
	for i in range(1, top_left_points.size()):
		var seg_dist := top_left_points[i - 1].distance_to(top_left_points[i])
		var seg_dur := maxf(0.04 / _speed, dur * seg_dist / total_dist)
		tw.tween_property(token, "position", top_left_points[i], seg_dur).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
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

func _add_product_visual(token: Control, product_id: String, amount: int) -> void:
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
	if amount <= 1:
		return
	var badge := Label.new()
	badge.name = "AmountBadge"
	badge.anchor_left = 0.42
	badge.anchor_right = 1.12
	badge.anchor_top = 0.62
	badge.anchor_bottom = 1.16
	badge.text = "+%d" % amount
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.add_theme_font_size_override("font_size", maxi(9, int(_get_cell_size() * 0.24)))
	badge.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	badge.add_theme_color_override("font_outline_color", Color(0.03, 0.04, 0.05, 0.96))
	badge.add_theme_constant_override("outline_size", 2)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	token.add_child(badge)

func _build_return_route_points(source_world_pos: Vector2i, route: Array[Vector2i], target_rect: Rect2) -> Array[Vector2]:
	var source_center := _world_cell_rect(source_world_pos).position + _world_cell_rect(source_world_pos).size * 0.5
	var target_center := target_rect.position + target_rect.size * 0.5
	if route.is_empty():
		return [source_center, target_center]
	var idx := route.find(source_world_pos)
	if idx < 0:
		return [source_center, target_center]
	var points: Array[Vector2] = []
	for i in range(idx, -1, -1):
		points.append(_world_cell_center(route[i]))
	if points.is_empty():
		return [source_center, target_center]
	points[0] = source_center
	points.append(target_center)
	return points

func _read_picked_sources(value) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not (value is Array):
		return out
	for item_val in Array(value):
		if not (item_val is Dictionary):
			continue
		var item: Dictionary = item_val
		var product_id := _normalize_product_id(str(item.get("type", "")).strip_edges())
		var wp := _read_vector2i(item.get("world_pos", null), Vector2i(-1, -1))
		if product_id.is_empty() or wp == Vector2i(-1, -1):
			continue
		out.append({
			"type": product_id,
			"world_pos": wp,
		})
	return out

func _count_sources_by_type(sources: Array[Dictionary]) -> Dictionary:
	var out := {}
	for source in sources:
		var product_id := str(source.get("type", "")).strip_edges()
		if product_id.is_empty():
			continue
		out[product_id] = int(out.get(product_id, 0)) + 1
	return out

func _first_product_id_from_count_dict(counts: Dictionary) -> String:
	for key_val in counts.keys():
		var product_id := _normalize_product_id(str(key_val).strip_edges())
		if not product_id.is_empty() and int(counts.get(key_val, 0)) > 0:
			return product_id
	return ""

func _get_player_restaurant_rect(state: GameState, player_id: int, preferred_restaurant_id: String = "") -> Rect2:
	if state == null or not (state.map is Dictionary):
		return Rect2()
	var restaurants_val = state.map.get("restaurants", null)
	if not (restaurants_val is Dictionary):
		return Rect2()
	var restaurants: Dictionary = restaurants_val
	var out := Rect2()
	var has_rect := false
	var preferred := str(preferred_restaurant_id).strip_edges()
	for rid_val in restaurants.keys():
		var rid := str(rid_val).strip_edges()
		var rest_val = restaurants.get(rid_val, null)
		if not (rest_val is Dictionary):
			continue
		var rest: Dictionary = rest_val
		if not preferred.is_empty():
			if rid != preferred:
				continue
		else:
			var owner := int(rest.get("owner", rest.get("owner_id", rest.get("player_id", -1))))
			if owner != player_id:
				continue
		var cells := _read_vector2i_array(rest.get("cells", null))
		if cells.is_empty():
			var ep := _read_vector2i(rest.get("entrance_pos", null), Vector2i(-1, -1))
			if ep != Vector2i(-1, -1):
				cells.append(ep)
		var rect := _cells_rect(cells)
		if rect.size == Vector2.ZERO:
			continue
		if has_rect:
			out = out.merge(rect)
		else:
			out = rect
			has_rect = true
	return out if has_rect else Rect2()

func _get_map_center_rect() -> Rect2:
	var cs := maxf(_get_cell_size(), 1.0)
	if _map_canvas is Control and is_instance_valid(_map_canvas):
		var c := (_map_canvas as Control)
		if c.size != Vector2.ZERO:
			return Rect2(c.size * 0.5 - Vector2(cs, cs), Vector2(cs * 2.0, cs * 2.0))
	return Rect2(Vector2(cs * 4.0, cs * 4.0), Vector2(cs * 2.0, cs * 2.0))

func _cells_rect(cells: Array[Vector2i]) -> Rect2:
	if cells.is_empty():
		return Rect2()
	var cs := maxf(_get_cell_size(), 1.0)
	var origin := _get_world_origin()
	var min_v := Vector2(INF, INF)
	var max_v := Vector2(-INF, -INF)
	for c in cells:
		var tl := Vector2(c - origin) * cs
		var br := tl + Vector2(cs, cs)
		min_v = Vector2(minf(min_v.x, tl.x), minf(min_v.y, tl.y))
		max_v = Vector2(maxf(max_v.x, br.x), maxf(max_v.y, br.y))
	return Rect2(min_v, max_v - min_v)

func _world_cell_rect(world_pos: Vector2i) -> Rect2:
	var cs := maxf(_get_cell_size(), 1.0)
	var view_pos := world_pos - _get_world_origin()
	return Rect2(Vector2(view_pos) * cs, Vector2(cs, cs))

func _world_cell_center(world_pos: Vector2i) -> Vector2:
	var rect := _world_cell_rect(world_pos)
	return rect.position + rect.size * 0.5

func _read_vector2i_array(value) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if not (value is Array):
		return out
	for item in Array(value):
		var v := _read_vector2i(item, Vector2i(-1, -1))
		if v != Vector2i(-1, -1):
			out.append(v)
	return out

func _read_vector2i(value, fallback: Vector2i) -> Vector2i:
	if value is Vector2i:
		return Vector2i(value)
	if value is Vector2:
		var vv: Vector2 = value
		return Vector2i(int(vv.x), int(vv.y))
	if value is Array:
		var arr: Array = value
		if arr.size() == 2:
			return Vector2i(int(arr[0]), int(arr[1]))
	if value is Dictionary:
		var d: Dictionary = value
		if d.has("x") and d.has("y"):
			return Vector2i(int(d.get("x", 0)), int(d.get("y", 0)))
	return fallback

func _polyline_length(points: Array[Vector2]) -> float:
	var total := 0.0
	for i in range(1, points.size()):
		total += points[i - 1].distance_to(points[i])
	return total

func _ensure_layer() -> bool:
	if _map_canvas == null or not is_instance_valid(_map_canvas):
		return false
	if not (_map_canvas is Control):
		return false
	if is_instance_valid(_layer) and _layer.get_parent() == _map_canvas:
		return true
	_layer = Control.new()
	_layer.name = "WorkingActionFeedbackLayer"
	_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_layer.position = Vector2.ZERO
	_layer.size = (_map_canvas as Control).size
	_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiZClass.apply_absolute(_layer, UiZClass.MAP_OVERLAY)
	(_map_canvas as Control).add_child(_layer)
	return true

func _ensure_skin(state: GameState) -> void:
	if _skin != null:
		return
	var base_dir := ModulesBaseDirClass.get_base_dir()
	var mods: Array[String] = []
	if state != null and (state.modules is Array):
		mods = Array(state.modules, TYPE_STRING, "", null)
	elif Globals != null and (Globals.enabled_modules_v2 is Array):
		mods = Array(Globals.enabled_modules_v2, TYPE_STRING, "", null)
	_skin = UiSkinCacheClass.get_skin_for_modules(base_dir, mods, 40)

func _get_product_texture(product_id: String) -> Texture2D:
	if _skin == null:
		return null
	var pid := _normalize_product_id(product_id)
	if pid.is_empty():
		return null
	return _skin.get_product_icon_texture(pid)

func _normalize_product_id(product_id: String) -> String:
	var pid := str(product_id).strip_edges()
	if pid == "cola":
		pid = "soda"
	return pid

func _product_name(product_id: String) -> String:
	var pid := _normalize_product_id(product_id)
	if pid.is_empty():
		return ""
	if ProductRegistryClass.is_loaded():
		var def_val = ProductRegistryClass.get_def(pid)
		if def_val != null and def_val is ProductDef:
			var name := str((def_val as ProductDef).name).strip_edges()
			if not name.is_empty():
				return name
	return pid

func _employee_name(employee_id: String) -> String:
	var eid := str(employee_id).strip_edges()
	if eid.is_empty():
		return ""
	if EmployeeRegistryClass.is_loaded():
		var def_val = EmployeeRegistryClass.get_def(eid)
		if def_val != null and def_val is EmployeeDef:
			var name := str((def_val as EmployeeDef).name).strip_edges()
			if not name.is_empty():
				return name
	return eid

func _read_live_game_state() -> GameState:
	if _scene == null or not is_instance_valid(_scene):
		return null
	if not _scene.has_method("get"):
		return null
	var engine_val = _scene.get("game_engine")
	if engine_val == null or not engine_val.has_method("get_state"):
		return null
	var state_val = engine_val.get_state()
	return state_val if state_val is GameState else null

func _get_world_origin() -> Vector2i:
	if _map_canvas != null and is_instance_valid(_map_canvas) and _map_canvas.has_method("get_world_origin"):
		var val = _map_canvas.call("get_world_origin")
		if val is Vector2i:
			return Vector2i(val)
	return Vector2i.ZERO

func _get_cell_size() -> float:
	if _map_canvas != null and is_instance_valid(_map_canvas) and _map_canvas.has_method("get_cell_size"):
		return maxf(1.0, float(_map_canvas.call("get_cell_size")))
	return 40.0

func _kill_tweens() -> void:
	for tween in _active_tweens:
		if is_instance_valid(tween):
			tween.kill()
	_active_tweens.clear()
