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

const TOKEN_FLY_SEC := 1.45
const TOKEN_EMIT_GAP_SEC := 0.24
const BURST_TOTAL_SEC := 1.80
const PULSE_SEC := 0.90
const PLACEMENT_FLASH_SEC := 1.55
const MOVE_GHOST_SEC := 1.05
const MAX_TOKENS_PER_FEEDBACK := 5
const MAX_DRAWN_BURSTS := 8
const MAX_EFFECT_NODES := 18
const MAX_BURST_WIDTH_PX := 360.0

class BurstDrawLayer:
	extends Control

	const MAX_BURSTS := 8
	const DEFAULT_DURATION_SEC := 1.80

	var _bursts: Array[Dictionary] = []
	var _clock: float = 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_process(false)

	func add_burst(text: String, center: Vector2, width: float, font_size: int, color: Color, delay_sec: float, duration_sec: float, rise_px: float) -> void:
		var label_text := str(text).strip_edges()
		if label_text.is_empty():
			return
		_bursts.append({
			"text": label_text,
			"center": center,
			"width": maxf(1.0, float(width)),
			"font_size": maxi(10, int(font_size)),
			"color": color,
			"delay": maxf(0.0, float(delay_sec)),
			"duration": maxf(0.08, float(duration_sec)),
			"rise": maxf(0.0, float(rise_px)),
			"start": _clock,
		})
		while _bursts.size() > MAX_BURSTS:
			_bursts.pop_front()
		set_process(true)
		queue_redraw()

	func clear_bursts() -> void:
		_bursts.clear()
		set_process(false)
		queue_redraw()

	func active_count() -> int:
		return _bursts.size()

	func _process(delta: float) -> void:
		_clock += maxf(0.0, float(delta))
		for i in range(_bursts.size() - 1, -1, -1):
			var item: Dictionary = _bursts[i]
			var age := _clock - float(item.get("start", 0.0))
			var done_at := float(item.get("delay", 0.0)) + float(item.get("duration", DEFAULT_DURATION_SEC))
			if age >= done_at:
				_bursts.remove_at(i)
		if _bursts.is_empty():
			set_process(false)
		queue_redraw()

	func _draw() -> void:
		if _bursts.is_empty():
			return
		var font: Font = ThemeDB.fallback_font
		for item in _bursts:
			_draw_burst(font, item)

	func _draw_burst(font: Font, item: Dictionary) -> void:
		if font == null:
			return
		var age := _clock - float(item.get("start", 0.0)) - float(item.get("delay", 0.0))
		if age < 0.0:
			return
		var duration := maxf(0.08, float(item.get("duration", DEFAULT_DURATION_SEC)))
		var t := clampf(age / duration, 0.0, 1.0)
		var alpha := _burst_alpha(t)
		if alpha <= 0.001:
			return
		var scale := _burst_scale(t)
		var font_size := maxi(10, int(round(float(item.get("font_size", 16)) * scale)))
		var width := maxf(1.0, float(item.get("width", 120.0)))
		var center: Vector2 = item.get("center", Vector2.ZERO)
		var eased_rise := 1.0 - pow(1.0 - t, 3.0)
		center.y -= float(item.get("rise", 0.0)) * eased_rise
		var baseline := Vector2(center.x - width * 0.5, center.y + float(font_size) * 0.35)
		var color: Color = item.get("color", Color(1, 1, 1, 1))
		color.a *= alpha
		var shadow := Color(0, 0, 0, 0.62 * alpha)
		var outline := Color(0.04, 0.05, 0.04, 0.92 * alpha)
		var outline_px := maxf(1.0, float(font_size) * 0.10)
		draw_string(font, baseline + Vector2(outline_px + 1.0, outline_px + 1.0), str(item.get("text", "")), HORIZONTAL_ALIGNMENT_CENTER, width, font_size, shadow)
		draw_string(font, baseline + Vector2(-outline_px, 0.0), str(item.get("text", "")), HORIZONTAL_ALIGNMENT_CENTER, width, font_size, outline)
		draw_string(font, baseline + Vector2(outline_px, 0.0), str(item.get("text", "")), HORIZONTAL_ALIGNMENT_CENTER, width, font_size, outline)
		draw_string(font, baseline + Vector2(0.0, -outline_px), str(item.get("text", "")), HORIZONTAL_ALIGNMENT_CENTER, width, font_size, outline)
		draw_string(font, baseline + Vector2(0.0, outline_px), str(item.get("text", "")), HORIZONTAL_ALIGNMENT_CENTER, width, font_size, outline)
		draw_string(font, baseline, str(item.get("text", "")), HORIZONTAL_ALIGNMENT_CENTER, width, font_size, color)

	func _burst_alpha(t: float) -> float:
		if t <= 0.06:
			return clampf(t / 0.06, 0.0, 1.0)
		if t >= 0.82:
			return clampf((1.0 - t) / 0.18, 0.0, 1.0)
		return 1.0

	func _burst_scale(t: float) -> float:
		if t <= 0.08:
			return lerpf(0.80, 1.18, t / 0.08)
		if t <= 0.18:
			return lerpf(1.18, 0.98, (t - 0.08) / 0.10)
		if t <= 0.30:
			return lerpf(0.98, 1.04, (t - 0.18) / 0.12)
		return 1.0

var _scene = null
var _map_canvas = null
var _layer: Control = null
var _burst_layer: BurstDrawLayer = null
var _skin = null
var _speed: float = 1.0
var _eventbus_source: String = ""
var _pending_events: Array[Dictionary] = []
var _flush_scheduled: bool = false
var _active_tweens: Array[Tween] = []
var _active_effect_nodes: Array[Node] = []
var _handled_sequences: Dictionary = {}
var _last_seen_sequence: int = 0
var _initialized: bool = false

func _init(scene, map_canvas) -> void:
	_scene = scene
	_map_canvas = map_canvas
	_eventbus_source = "WorkingActionFeedback:%s" % str(get_instance_id())

func initialize() -> void:
	if OS.has_feature("headless"):
		return
	if _initialized:
		return
	_initialized = true
	EventBus.subscribe(EventBus.EventType.FOOD_PRODUCED, Callable(self, "_on_feedback_event"), 130, _eventbus_source)
	EventBus.subscribe(EventBus.EventType.DRINKS_PROCURED, Callable(self, "_on_feedback_event"), 130, _eventbus_source)
	EventBus.subscribe(EventBus.EventType.EMPLOYEE_RECRUITED, Callable(self, "_on_feedback_event"), 130, _eventbus_source)
	EventBus.subscribe(EventBus.EventType.EMPLOYEE_TRAINED, Callable(self, "_on_feedback_event"), 130, _eventbus_source)
	EventBus.subscribe(EventBus.EventType.HOUSE_PLACED, Callable(self, "_on_feedback_event"), 130, _eventbus_source)
	EventBus.subscribe(EventBus.EventType.GARDEN_ADDED, Callable(self, "_on_feedback_event"), 130, _eventbus_source)
	EventBus.subscribe(EventBus.EventType.RESTAURANT_PLACED, Callable(self, "_on_feedback_event"), 130, _eventbus_source)
	EventBus.subscribe(EventBus.EventType.RESTAURANT_MOVED, Callable(self, "_on_feedback_event"), 130, _eventbus_source)
	EventBus.subscribe(EventBus.EventType.COMMAND_EXECUTED, Callable(self, "_on_feedback_event"), 130, _eventbus_source)

func dispose() -> void:
	if not _eventbus_source.is_empty():
		EventBus.unsubscribe_all_from_source(_eventbus_source)
	_eventbus_source = ""
	_pending_events.clear()
	_flush_scheduled = false
	_handled_sequences.clear()
	_last_seen_sequence = 0
	_initialized = false
	_kill_tweens()
	_active_effect_nodes.clear()
	if is_instance_valid(_layer):
		_layer.queue_free()
	_layer = null
	_burst_layer = null
	_scene = null
	_map_canvas = null
	_skin = null

func clear() -> void:
	# hide_all_overlays() 也会在命令成功后的 UI 同步中被调用。
	# 工作行动反馈是非阻塞即时反馈，不能被通用选点/面板清理打断；节点会按各自动画自行释放。
	pass

func _on_feedback_event(event: Dictionary) -> void:
	if OS.has_feature("headless"):
		return
	if not (event is Dictionary) or event.is_empty():
		return
	var seq := int(event.get("sequence", -1))
	if not _accept_event_sequence(seq):
		return
	var type := str(event.get("type", "")).strip_edges()
	if type == EventBus.EventType.COMMAND_EXECUTED:
		var data_val = event.get("data", null)
		var data: Dictionary = data_val if (data_val is Dictionary) else {}
		if not data.has("price_modifier"):
			return
	var event_copy := event.duplicate(true)
	var command_phase := _read_event_command_phase(event_copy)
	if not command_phase.is_empty():
		event_copy["__feedback_phase"] = str(command_phase.get("phase", ""))
		event_copy["__feedback_sub_phase"] = str(command_phase.get("sub_phase", ""))
		_pending_events.append(event_copy)
		if _flush_scheduled:
			return
		_flush_scheduled = true
		call_deferred("_flush_pending_events")
		return
	var state := _read_live_game_state()
	if state != null:
		event_copy["__feedback_phase"] = str(state.phase)
		event_copy["__feedback_sub_phase"] = str(state.sub_phase)
	_pending_events.append(event_copy)
	if _flush_scheduled:
		return
	_flush_scheduled = true
	call_deferred("_flush_pending_events")

func _accept_event_sequence(seq: int) -> bool:
	if seq <= 0:
		return true
	# 回退/截断历史会重建 EventBus.history 并把事件序号从 1 重新开始。
	# 旧去重表如果不清空，会把新分支上的即时反馈误判为已播放。
	if _last_seen_sequence > 0 and seq <= _last_seen_sequence:
		_handled_sequences.clear()
	_last_seen_sequence = seq
	if _handled_sequences.has(seq):
		return false
	_handled_sequences[seq] = true
	if _handled_sequences.size() > 256:
		_handled_sequences.clear()
		_handled_sequences[seq] = true
	return true

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
	var data_val = event.get("data", null)
	var data: Dictionary = data_val if (data_val is Dictionary) else {}
	var type := str(event.get("type", "")).strip_edges()
	var phase_name := str(event.get("__feedback_phase", "")).strip_edges()
	if phase_name.is_empty():
		phase_name = str(state.phase)
	if not _is_feedback_phase_allowed(type, phase_name):
		return
	if not _ensure_layer():
		return
	_speed = maxf(float(Globals.animation_speed) if Globals != null else 1.0, 0.05)
	_ensure_skin(state)

	match type:
		EventBus.EventType.FOOD_PRODUCED:
			_play_food_produced(state, data)
		EventBus.EventType.DRINKS_PROCURED:
			_play_drinks_procured(state, data)
		EventBus.EventType.EMPLOYEE_RECRUITED:
			_play_employee_recruited(state, data)
		EventBus.EventType.EMPLOYEE_TRAINED:
			_play_employee_trained(state, data)
		EventBus.EventType.HOUSE_PLACED:
			_play_house_placed(state, data)
		EventBus.EventType.GARDEN_ADDED:
			_play_garden_added(state, data)
		EventBus.EventType.RESTAURANT_PLACED:
			_play_restaurant_placed(state, data)
		EventBus.EventType.RESTAURANT_MOVED:
			_play_restaurant_moved(state, data)
		EventBus.EventType.COMMAND_EXECUTED:
			_play_price_modifier(state, data)

func _is_feedback_phase_allowed(event_type: String, phase_name: String) -> bool:
	if phase_name == DefsClass.PHASE_WORKING:
		return true
	return phase_name == DefsClass.PHASE_SETUP and event_type == EventBus.EventType.RESTAURANT_PLACED

func _play_food_produced(state: GameState, data: Dictionary) -> void:
	var player_id := int(data.get("player_id", -1))
	var food_type := _normalize_product_id(str(data.get("food_type", data.get("product", ""))).strip_edges())
	var amount := maxi(1, int(data.get("amount", 1)))
	var rect := _get_player_restaurant_rect(state, player_id, str(data.get("restaurant_id", "")).strip_edges())
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
	var rect := _get_player_restaurant_rect(state, player_id, str(data.get("restaurant_id", "")).strip_edges())
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
	var rect := _get_player_restaurant_rect(state, player_id, str(data.get("restaurant_id", "")).strip_edges())
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
	var rect := _get_player_restaurant_rect(state, player_id, str(data.get("restaurant_id", "")).strip_edges())
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

func _play_house_placed(state: GameState, data: Dictionary) -> void:
	var house_id := str(data.get("house_id", "")).strip_edges()
	var rect := _get_house_rect(state, house_id)
	if rect.size == Vector2.ZERO:
		rect = _rect_from_event_position(data)
	if rect.size == Vector2.ZERO:
		rect = _get_map_center_rect()
	var house_number := str(data.get("house_number", "")).strip_edges()
	var label := "新房屋"
	if not house_number.is_empty():
		label += " #%s" % house_number
	_start_placement_feedback(rect, label, Color(0.52, 0.95, 0.58, 1.0))

func _play_garden_added(state: GameState, data: Dictionary) -> void:
	var house_id := str(data.get("house_id", "")).strip_edges()
	var rect := _get_house_rect(state, house_id)
	if rect.size == Vector2.ZERO:
		rect = _rect_from_event_position(data)
	if rect.size == Vector2.ZERO:
		rect = _get_map_center_rect()
	_start_placement_feedback(rect, "加建花园", Color(0.36, 0.86, 0.48, 1.0))

func _play_restaurant_placed(state: GameState, data: Dictionary) -> void:
	var restaurant_id := str(data.get("restaurant_id", "")).strip_edges()
	var rect := _get_restaurant_rect(state, restaurant_id)
	if rect.size == Vector2.ZERO:
		rect = _rect_from_event_position(data)
	if rect.size == Vector2.ZERO:
		rect = _get_map_center_rect()
	var label := "新餐厅"
	if bool(data.get("opening_soon", false)):
		label = "即将开业"
	_start_placement_feedback(rect, label, Color(1.0, 0.68, 0.32, 1.0))

func _play_restaurant_moved(state: GameState, data: Dictionary) -> void:
	var restaurant_id := str(data.get("restaurant_id", "")).strip_edges()
	var to_rect := _rect_from_event_cells(data, "to_cells")
	if to_rect.size == Vector2.ZERO:
		to_rect = _get_restaurant_rect(state, restaurant_id)
	if to_rect.size == Vector2.ZERO:
		to_rect = _rect_from_event_position_key(data, "to_position")
	if to_rect.size == Vector2.ZERO:
		to_rect = _rect_from_event_position(data)
	if to_rect.size == Vector2.ZERO:
		to_rect = _get_map_center_rect()

	var from_rect := _rect_from_event_cells(data, "from_cells")
	if from_rect.size == Vector2.ZERO:
		from_rect = _rect_from_event_position_key(data, "from_position")
	if from_rect.size != Vector2.ZERO and from_rect.position.distance_to(to_rect.position) > 1.0:
		_start_move_ghost(from_rect, to_rect, Color(1.0, 0.58, 0.30, 1.0))
	_start_placement_feedback(to_rect, "移动餐厅", Color(0.98, 0.58, 0.36, 1.0))

func _start_action_burst(anchor_rect: Rect2, text: String, color: Color, delay_sec: float = 0.0) -> void:
	if not is_instance_valid(_layer):
		return
	if not _ensure_burst_layer():
		return
	var label_text := str(text).strip_edges()
	if label_text.is_empty():
		return
	var cell_size := maxf(_get_cell_size(), 1.0)
	var font_size := clampi(int(round(cell_size * 0.45)), 14, 24)
	var text_w := ThemeDB.fallback_font.get_string_size(label_text, HORIZONTAL_ALIGNMENT_CENTER, -1.0, font_size).x if ThemeDB.fallback_font != null else float(label_text.length()) * float(font_size)
	var burst_w := maxf(cell_size * 2.65, text_w + cell_size * 0.75)
	burst_w = minf(burst_w, maxf(MAX_BURST_WIDTH_PX, cell_size * 6.5))
	var rise := maxf(18.0, cell_size * 0.56)
	_burst_layer.add_burst(label_text, anchor_rect.position + anchor_rect.size * 0.5, burst_w, font_size, color, maxf(0.0, delay_sec) / _speed, BURST_TOTAL_SEC / _speed, rise)
	_burst_layer.move_to_front()

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
	_track_effect_node(pulse)
	var tw := pulse.create_tween().set_parallel(true)
	_active_tweens.append(tw)
	tw.tween_property(pulse, "scale", Vector2(1.10, 1.10), PULSE_SEC / _speed).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(pulse, "modulate:a", 0.0, PULSE_SEC / _speed).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(func():
		_finish_effect_node(pulse, tw)
	)

func _start_placement_feedback(rect: Rect2, label: String, color: Color) -> void:
	_start_rect_pulse(rect, Color(color.r, color.g, color.b, 0.24))
	_start_placement_flash(rect, Color(color.r, color.g, color.b, 0.30))
	_start_action_burst(rect, label, color, 0.10)

func _start_placement_flash(rect: Rect2, color: Color) -> void:
	if not is_instance_valid(_layer):
		return
	if rect.size == Vector2.ZERO:
		return
	var flash := ColorRect.new()
	flash.name = "WorkingActionFeedbackPlacementFlash"
	flash.position = rect.position
	flash.size = rect.size
	flash.pivot_offset = rect.size * 0.5
	flash.color = color
	flash.scale = Vector2(1.24, 1.24)
	flash.modulate.a = 0.0
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(flash)
	_track_effect_node(flash)
	var tw := flash.create_tween().set_parallel(true)
	_active_tweens.append(tw)
	tw.tween_property(flash, "modulate:a", 1.0, 0.16 / _speed).set_ease(Tween.EASE_OUT)
	tw.tween_property(flash, "scale", Vector2(1.0, 1.0), 0.36 / _speed).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.tween_property(flash, "modulate:a", 0.0, 0.62 / _speed).set_delay(maxf(0.0, PLACEMENT_FLASH_SEC - 0.62) / _speed).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(func():
		_finish_effect_node(flash, tw)
	)

func _start_move_ghost(from_rect: Rect2, to_rect: Rect2, color: Color) -> void:
	if not is_instance_valid(_layer):
		return
	if from_rect.size == Vector2.ZERO or to_rect.size == Vector2.ZERO:
		return
	var ghost := ColorRect.new()
	ghost.name = "WorkingActionFeedbackMoveGhost"
	ghost.position = from_rect.position
	ghost.size = to_rect.size
	ghost.pivot_offset = ghost.size * 0.5
	ghost.color = Color(color.r, color.g, color.b, 0.28)
	ghost.modulate.a = 0.0
	ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(ghost)
	_track_effect_node(ghost)

	var tw := ghost.create_tween().set_parallel(true)
	_active_tweens.append(tw)
	tw.tween_property(ghost, "modulate:a", 1.0, 0.16 / _speed).set_ease(Tween.EASE_OUT)
	tw.tween_property(ghost, "position", to_rect.position, MOVE_GHOST_SEC / _speed).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(ghost, "scale", Vector2(1.10, 1.10), 0.18 / _speed).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.tween_property(ghost, "scale", Vector2(1.0, 1.0), 0.24 / _speed).set_delay(0.18 / _speed).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(ghost, "modulate:a", 0.0, 0.28 / _speed).set_delay(maxf(0.0, MOVE_GHOST_SEC - 0.28) / _speed).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(func():
		_finish_effect_node(ghost, tw)
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
	var icon_size := maxf(26.0, _get_cell_size() * 0.92)
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
	token.scale = Vector2(0.64, 0.64)
	token.rotation_degrees = -5.0 if index % 2 == 0 else 5.0
	_layer.add_child(token)
	_track_effect_node(token)
	_add_product_visual(token, product_id, amount)

	var tw := token.create_tween()
	_active_tweens.append(tw)
	var delay := maxf(0.0, delay_sec) / _speed
	if delay > 0.0:
		tw.tween_interval(delay)
	tw.tween_property(token, "scale", Vector2(1.10, 1.10), 0.14 / _speed).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.parallel().tween_property(token, "rotation_degrees", 0.0, 0.14 / _speed).set_ease(Tween.EASE_OUT)
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
		var swing := 7.0 if i % 2 == 0 else -7.0
		tw.parallel().tween_property(token, "rotation_degrees", swing, seg_dur).set_ease(Tween.EASE_IN_OUT)
	tw.tween_callback(func():
		if on_landed.is_valid():
			on_landed.call()
	)
	tw.tween_property(token, "scale", Vector2(1.10, 1.10), 0.06 / _speed)
	tw.parallel().tween_property(token, "modulate:a", 0.0, 0.16 / _speed)
	tw.tween_callback(func():
		_finish_effect_node(token, tw)
	)

func _add_product_visual(token: Control, product_id: String, amount: int) -> void:
	var bg := Panel.new()
	bg.name = "TokenBackplate"
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.10, 0.13, 0.72)
	var radius := maxi(6, int(round(token.size.x * 0.28)))
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.80, 0.95, 1.0, 0.82)
	bg.add_theme_stylebox_override("panel", style)
	token.add_child(bg)

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
	var preferred := str(preferred_restaurant_id).strip_edges()
	var candidate_ids := _get_feedback_restaurant_ids(state, player_id, preferred, restaurants)
	for rid in candidate_ids:
		var rest_val = restaurants.get(rid, null)
		if not (rest_val is Dictionary):
			continue
		var rest: Dictionary = rest_val
		var cells := _read_vector2i_array(rest.get("cells", null))
		if cells.is_empty():
			var ep := _read_vector2i(rest.get("entrance_pos", null), Vector2i(-1, -1))
			if ep != Vector2i(-1, -1):
				cells.append(ep)
		var rect := _cells_rect(cells)
		if rect.size != Vector2.ZERO:
			return rect
	return Rect2()

func _get_feedback_restaurant_ids(state: GameState, player_id: int, preferred_restaurant_id: String, restaurants: Dictionary) -> Array[String]:
	var preferred := str(preferred_restaurant_id).strip_edges()
	if not preferred.is_empty():
		var preferred_only: Array[String] = []
		preferred_only.append(preferred)
		return preferred_only
	var out: Array[String] = []
	if player_id >= 0 and player_id < state.players.size():
		var player_val = state.players[player_id]
		if player_val is Dictionary:
			var player: Dictionary = player_val
			var list_val = player.get("restaurants", null)
			if list_val is Array:
				for rid_val in Array(list_val):
					var rid := str(rid_val).strip_edges()
					if not rid.is_empty() and restaurants.has(rid):
						out.append(rid)
	if not out.is_empty():
		return out
	for rid_val in restaurants.keys():
		var rid := str(rid_val).strip_edges()
		if rid.is_empty():
			continue
		var rest_val = restaurants.get(rid_val, null)
		if not (rest_val is Dictionary):
			continue
		var rest: Dictionary = rest_val
		var owner := int(rest.get("owner", rest.get("owner_id", rest.get("player_id", -1))))
		if owner == player_id:
			out.append(rid)
	out.sort()
	return out

func _get_house_rect(state: GameState, house_id: String) -> Rect2:
	if state == null or not (state.map is Dictionary):
		return Rect2()
	var houses_val = state.map.get("houses", null)
	if not (houses_val is Dictionary):
		return Rect2()
	var houses: Dictionary = houses_val
	if not houses.has(house_id):
		return Rect2()
	var house_val = houses.get(house_id, null)
	if not (house_val is Dictionary):
		return Rect2()
	var house: Dictionary = house_val
	var cells := _read_vector2i_array(house.get("cells", null))
	if cells.is_empty():
		var anchor := _read_vector2i(house.get("anchor_pos", null), Vector2i(-1, -1))
		if anchor != Vector2i(-1, -1):
			cells.append(anchor)
	return _cells_rect(cells)

func _get_restaurant_rect(state: GameState, restaurant_id: String) -> Rect2:
	if state == null or not (state.map is Dictionary):
		return Rect2()
	var rid := str(restaurant_id).strip_edges()
	if rid.is_empty():
		return Rect2()
	var restaurants_val = state.map.get("restaurants", null)
	if restaurants_val is Dictionary:
		var restaurants: Dictionary = restaurants_val
		if restaurants.has(rid):
			var rest_val = restaurants.get(rid, null)
			if rest_val is Dictionary:
				var rest: Dictionary = rest_val
				var cells := _read_vector2i_array(rest.get("cells", null))
				if cells.is_empty():
					var anchor := _read_vector2i(rest.get("anchor_pos", null), Vector2i(-1, -1))
					if anchor != Vector2i(-1, -1):
						cells.append(anchor)
				var rect := _cells_rect(cells)
				if rect.size != Vector2.ZERO:
					return rect
	var pending_cells := _get_opening_soon_restaurant_cells(state, rid)
	if not pending_cells.is_empty():
		return _cells_rect(pending_cells)
	return Rect2()

func _get_opening_soon_restaurant_cells(state: GameState, restaurant_id: String) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if state == null or not (state.round_state is Dictionary):
		return out
	var pending_val = state.round_state.get("opening_soon_restaurants", null)
	if not (pending_val is Array):
		return out
	for item_val in Array(pending_val):
		if not (item_val is Dictionary):
			continue
		var item: Dictionary = item_val
		if str(item.get("restaurant_id", "")).strip_edges() != restaurant_id:
			continue
		out = _read_vector2i_array(item.get("cells", null))
		if out.is_empty():
			var anchor := _read_vector2i(item.get("anchor_pos", null), Vector2i(-1, -1))
			if anchor != Vector2i(-1, -1):
				out.append(anchor)
		return out
	return out

func _rect_from_event_position(data: Dictionary) -> Rect2:
	return _rect_from_event_position_key(data, "position")

func _rect_from_event_position_key(data: Dictionary, key: String) -> Rect2:
	var pos := _read_vector2i(data.get(key, null), Vector2i(-1, -1))
	if pos == Vector2i(-1, -1):
		return Rect2()
	return _world_cell_rect(pos)

func _rect_from_event_cells(data: Dictionary, key: String) -> Rect2:
	return _cells_rect(_read_vector2i_array(data.get(key, null)))

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
		_layer.size = (_map_canvas as Control).size
		if is_instance_valid(_burst_layer):
			_burst_layer.size = _layer.size
		return true
	_layer = Control.new()
	_layer.name = "WorkingActionFeedbackLayer"
	_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_layer.position = Vector2.ZERO
	_layer.size = (_map_canvas as Control).size
	_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiZClass.apply_absolute(_layer, UiZClass.MAP_OVERLAY)
	(_map_canvas as Control).add_child(_layer)
	_burst_layer = null
	return true

func _ensure_burst_layer() -> bool:
	if not is_instance_valid(_layer):
		return false
	if is_instance_valid(_burst_layer) and _burst_layer.get_parent() == _layer:
		_burst_layer.size = _layer.size
		return true
	_burst_layer = BurstDrawLayer.new()
	_burst_layer.name = "WorkingActionFeedbackBurst"
	_burst_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_burst_layer.position = Vector2.ZERO
	_burst_layer.size = _layer.size
	_burst_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(_burst_layer)
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
	var engine_val = _read_live_game_engine()
	if engine_val == null or not engine_val.has_method("get_state"):
		return null
	var state_val = engine_val.get_state()
	return state_val if state_val is GameState else null

func _read_live_game_engine():
	if _scene == null or not is_instance_valid(_scene):
		return null
	if not _scene.has_method("get"):
		return null
	var engine_val = _scene.get("game_engine")
	return engine_val

func _read_event_command_phase(event: Dictionary) -> Dictionary:
	var data_val = event.get("data", null)
	if not (data_val is Dictionary):
		return {}
	var data: Dictionary = data_val
	if not data.has("command_index"):
		return {}
	var command_index := int(data.get("command_index", -1))
	if command_index < 0:
		return {}
	var engine_val = _read_live_game_engine()
	if engine_val == null or not engine_val.has_method("get"):
		return {}
	var history_val = engine_val.get("command_history")
	if not (history_val is Array):
		return {}
	var history: Array = history_val
	if command_index >= history.size():
		return {}
	var command_val = history[command_index]
	if command_val is Command:
		var command: Command = command_val
		return {
			"phase": str(command.phase),
			"sub_phase": str(command.sub_phase),
		}
	if command_val is Dictionary:
		var command_dict: Dictionary = command_val
		return {
			"phase": str(command_dict.get("phase", "")),
			"sub_phase": str(command_dict.get("sub_phase", "")),
		}
	return {}

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

func _track_effect_node(node: Node) -> void:
	_cleanup_effect_nodes()
	if not is_instance_valid(node):
		return
	_active_effect_nodes.append(node)
	while _active_effect_nodes.size() > MAX_EFFECT_NODES:
		var old_node: Node = _active_effect_nodes.pop_front()
		if is_instance_valid(old_node):
			old_node.queue_free()

func _finish_effect_node(node: Node, tween: Tween) -> void:
	if is_instance_valid(node):
		node.queue_free()
	_active_effect_nodes.erase(node)
	_active_tweens.erase(tween)

func _cleanup_effect_nodes() -> void:
	for i in range(_active_effect_nodes.size() - 1, -1, -1):
		if not is_instance_valid(_active_effect_nodes[i]):
			_active_effect_nodes.remove_at(i)
	for i in range(_active_tweens.size() - 1, -1, -1):
		if not is_instance_valid(_active_tweens[i]):
			_active_tweens.remove_at(i)

func get_debug_active_burst_count() -> int:
	if is_instance_valid(_burst_layer):
		return _burst_layer.active_count()
	return 0

func get_debug_effect_node_count() -> int:
	_cleanup_effect_nodes()
	return _active_effect_nodes.size()

func _kill_tweens() -> void:
	for tween in _active_tweens:
		if is_instance_valid(tween):
			tween.kill()
	_active_tweens.clear()
	for node in _active_effect_nodes:
		if is_instance_valid(node):
			node.queue_free()
	_active_effect_nodes.clear()
	if is_instance_valid(_burst_layer):
		_burst_layer.clear_bursts()
