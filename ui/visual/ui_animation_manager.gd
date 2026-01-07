# UI动画管理器
# 提供卡牌移动、销售流程、翻面等动画效果
class_name UIAnimationManager
extends Node

signal animation_started(anim_id: String)
signal animation_completed(anim_id: String)
signal all_animations_completed()

var _active_animations: Dictionary = {}  # anim_id -> Tween
var _animation_speed: float = 1.0
var _anim_id_counter: int = 0

# 预设动画时长（秒）
const DURATION_CARD_MOVE := 0.3
const DURATION_CARD_FLIP := 0.25
const DURATION_FADE := 0.2
const DURATION_SCALE := 0.2
const DURATION_SLIDE := 0.35
const DURATION_SHAKE := 0.4
const DURATION_PULSE := 0.5

func _ready() -> void:
	pass

func set_animation_speed(speed: float) -> void:
	_animation_speed = clampf(speed, 0.1, 3.0)

func get_animation_speed() -> float:
	return _animation_speed

# === 卡牌移动动画 ===
func animate_card_move(card: Control, target_pos: Vector2, callback: Callable = Callable()) -> String:
	var anim_id := _generate_id()
	var duration := DURATION_CARD_MOVE / _animation_speed

	var tween := create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_QUAD)

	# 移动
	tween.tween_property(card, "position", target_pos, duration)

	_register_animation(anim_id, tween, callback)
	return anim_id

func animate_card_move_with_arc(card: Control, target_pos: Vector2, arc_height: float = 50.0, callback: Callable = Callable()) -> String:
	var anim_id := _generate_id()
	var duration := DURATION_CARD_MOVE / _animation_speed
	var start_pos := card.position

	var tween := create_tween()
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.set_trans(Tween.TRANS_SINE)

	# 使用自定义方法实现弧形移动
	tween.tween_method(
		func(t: float):
			var linear_pos := start_pos.lerp(target_pos, t)
			var arc_offset := sin(t * PI) * arc_height
			card.position = linear_pos + Vector2(0, -arc_offset),
		0.0, 1.0, duration
	)

	_register_animation(anim_id, tween, callback)
	return anim_id

# === 卡牌翻转动画 ===
func animate_card_flip(card: Control, callback: Callable = Callable()) -> String:
	var anim_id := _generate_id()
	var duration := DURATION_CARD_FLIP / _animation_speed
	var half_duration := duration / 2

	var tween := create_tween()

	# 缩小到0（X轴）
	tween.tween_property(card, "scale:x", 0.0, half_duration)
	# 恢复
	tween.tween_property(card, "scale:x", 1.0, half_duration)

	_register_animation(anim_id, tween, callback)
	return anim_id

# === 淡入淡出动画 ===
func animate_fade_in(node: CanvasItem, callback: Callable = Callable()) -> String:
	var anim_id := _generate_id()
	var duration := DURATION_FADE / _animation_speed

	node.modulate.a = 0.0

	var tween := create_tween()
	tween.tween_property(node, "modulate:a", 1.0, duration)

	_register_animation(anim_id, tween, callback)
	return anim_id

func animate_fade_out(node: CanvasItem, callback: Callable = Callable()) -> String:
	var anim_id := _generate_id()
	var duration := DURATION_FADE / _animation_speed

	var tween := create_tween()
	tween.tween_property(node, "modulate:a", 0.0, duration)

	_register_animation(anim_id, tween, callback)
	return anim_id

# === 缩放动画 ===
func animate_scale_pop(node: Control, target_scale: float = 1.2, callback: Callable = Callable()) -> String:
	var anim_id := _generate_id()
	var duration := DURATION_SCALE / _animation_speed
	var original_scale := node.scale

	var tween := create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_BACK)

	# 放大
	tween.tween_property(node, "scale", Vector2.ONE * target_scale, duration * 0.4)
	# 恢复
	tween.tween_property(node, "scale", original_scale, duration * 0.6)

	_register_animation(anim_id, tween, callback)
	return anim_id

func animate_scale_bounce(node: Control, callback: Callable = Callable()) -> String:
	var anim_id := _generate_id()
	var duration := DURATION_SCALE / _animation_speed
	var original_scale := node.scale

	var tween := create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_ELASTIC)

	tween.tween_property(node, "scale", original_scale * 1.1, duration * 0.3)
	tween.tween_property(node, "scale", original_scale, duration * 0.7)

	_register_animation(anim_id, tween, callback)
	return anim_id

# === 滑入滑出动画 ===
func animate_slide_in(node: Control, from_direction: String = "right", callback: Callable = Callable()) -> String:
	var anim_id := _generate_id()
	var duration := DURATION_SLIDE / _animation_speed
	var target_pos := node.position
	var start_offset := Vector2.ZERO

	match from_direction:
		"left":
			start_offset = Vector2(-node.size.x - 50, 0)
		"right":
			start_offset = Vector2(node.size.x + 50, 0)
		"top":
			start_offset = Vector2(0, -node.size.y - 50)
		"bottom":
			start_offset = Vector2(0, node.size.y + 50)

	node.position = target_pos + start_offset

	var tween := create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_BACK)
	tween.tween_property(node, "position", target_pos, duration)

	_register_animation(anim_id, tween, callback)
	return anim_id

func animate_slide_out(node: Control, to_direction: String = "right", callback: Callable = Callable()) -> String:
	var anim_id := _generate_id()
	var duration := DURATION_SLIDE / _animation_speed
	var start_pos := node.position
	var end_offset := Vector2.ZERO

	match to_direction:
		"left":
			end_offset = Vector2(-node.size.x - 50, 0)
		"right":
			end_offset = Vector2(node.size.x + 50, 0)
		"top":
			end_offset = Vector2(0, -node.size.y - 50)
		"bottom":
			end_offset = Vector2(0, node.size.y + 50)

	var tween := create_tween()
	tween.set_ease(Tween.EASE_IN)
	tween.set_trans(Tween.TRANS_BACK)
	tween.tween_property(node, "position", start_pos + end_offset, duration)

	_register_animation(anim_id, tween, callback)
	return anim_id

# === 震动动画 ===
func animate_shake(node: Control, intensity: float = 5.0, callback: Callable = Callable()) -> String:
	var anim_id := _generate_id()
	var duration := DURATION_SHAKE / _animation_speed
	var original_pos := node.position

	var tween := create_tween()

	var shake_count := 6
	var shake_duration := duration / shake_count

	for i in range(shake_count):
		var offset := Vector2(
			randf_range(-intensity, intensity),
			randf_range(-intensity, intensity)
		) * (1.0 - float(i) / shake_count)
		tween.tween_property(node, "position", original_pos + offset, shake_duration)

	tween.tween_property(node, "position", original_pos, shake_duration * 0.5)

	_register_animation(anim_id, tween, callback)
	return anim_id

# === 脉冲高亮动画 ===
func animate_pulse(node: CanvasItem, pulse_color: Color = Color(1.2, 1.2, 1.2, 1), callback: Callable = Callable()) -> String:
	var anim_id := _generate_id()
	var duration := DURATION_PULSE / _animation_speed
	var original_modulate := node.modulate

	var tween := create_tween()
	tween.set_loops(2)

	tween.tween_property(node, "modulate", pulse_color, duration * 0.25)
	tween.tween_property(node, "modulate", original_modulate, duration * 0.25)

	tween.finished.connect(func():
		node.modulate = original_modulate
	)

	_register_animation(anim_id, tween, callback)
	return anim_id

# === 序列动画 ===
func create_sequence() -> AnimationSequence:
	return AnimationSequence.new(self)

# === 内部方法 ===
func _generate_id() -> String:
	_anim_id_counter += 1
	return "anim_%d_%d" % [Time.get_ticks_msec(), _anim_id_counter]

func _register_animation(anim_id: String, tween: Tween, callback: Callable) -> void:
	_active_animations[anim_id] = tween
	animation_started.emit(anim_id)

	tween.finished.connect(func():
		_active_animations.erase(anim_id)
		if callback.is_valid():
			callback.call()
		animation_completed.emit(anim_id)

		if _active_animations.is_empty():
			all_animations_completed.emit()
	)

func is_animating() -> bool:
	return not _active_animations.is_empty()

func cancel_all() -> void:
	for anim_id in _active_animations.keys():
		var tween: Tween = _active_animations[anim_id]
		if is_instance_valid(tween):
			tween.kill()
	_active_animations.clear()


# === 序列动画类 ===
class AnimationSequence:
	var _manager: UIAnimationManager
	var _steps: Array[Dictionary] = []

	func _init(manager: UIAnimationManager) -> void:
		_manager = manager

	func add_move(card: Control, target_pos: Vector2) -> AnimationSequence:
		_steps.append({"type": "move", "card": card, "target": target_pos})
		return self

	func add_fade_in(node: CanvasItem) -> AnimationSequence:
		_steps.append({"type": "fade_in", "node": node})
		return self

	func add_fade_out(node: CanvasItem) -> AnimationSequence:
		_steps.append({"type": "fade_out", "node": node})
		return self

	func add_delay(seconds: float) -> AnimationSequence:
		_steps.append({"type": "delay", "duration": seconds})
		return self

	func add_callback(callback: Callable) -> AnimationSequence:
		_steps.append({"type": "callback", "callback": callback})
		return self

	func play(on_complete: Callable = Callable()) -> void:
		_play_step(0, on_complete)

	func _play_step(index: int, on_complete: Callable) -> void:
		if index >= _steps.size():
			if on_complete.is_valid():
				on_complete.call()
			return

		var step: Dictionary = _steps[index]
		var next_callback := func(): _play_step(index + 1, on_complete)

		match step.type:
			"move":
				_manager.animate_card_move(step.card, step.target, next_callback)
			"fade_in":
				_manager.animate_fade_in(step.node, next_callback)
			"fade_out":
				_manager.animate_fade_out(step.node, next_callback)
			"delay":
				_manager.get_tree().create_timer(step.duration).timeout.connect(next_callback)
			"callback":
				if step.callback.is_valid():
					step.callback.call()
				next_callback.call()
			_:
				next_callback.call()
