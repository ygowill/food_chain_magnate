# 晚餐结算动画：时间线与节奏辅助
class_name DinnertimeAnimationTimelineHelpers
extends RefCounted

static func compute_coin_flight_timing(speed: float, coin_count: int) -> Dictionary:
	var safe_speed := maxf(float(speed), 0.01)
	var count := maxi(0, int(coin_count))
	var dur_fly := 0.80 / safe_speed
	var coin_delay_step := 0.0
	if count > 1:
		var start_spread := dur_fly * 0.55
		coin_delay_step = start_spread / float(count - 1)
		coin_delay_step = clampf(coin_delay_step, 0.04 / safe_speed, 0.14 / safe_speed)
	var dur_fly_total := dur_fly + float(maxi(0, count - 1)) * coin_delay_step
	return {
		"dur_fly": dur_fly,
		"coin_delay_step": coin_delay_step,
		"dur_fly_total": dur_fly_total,
	}

static func schedule_sale_timeline(
	anim_layer: Control,
	active_tweens: Array[Tween],
	speed: float,
	dur_float: float,
	dur_fly_total: float,
	on_spawn_coins_cb: Callable,
	on_finished_cb: Callable
) -> void:
	if not is_instance_valid(anim_layer):
		return
	var safe_speed := maxf(float(speed), 0.01)
	var tween := anim_layer.create_tween()
	active_tweens.append(tween)
	tween.tween_interval(maxf(0.0, float(dur_float)))
	if on_spawn_coins_cb.is_valid():
		tween.tween_callback(func():
			on_spawn_coins_cb.call()
		)
	tween.tween_interval(maxf(0.0, float(dur_fly_total) + 0.3 / safe_speed))
	tween.finished.connect(func():
		active_tweens.erase(tween)
		if on_finished_cb.is_valid():
			on_finished_cb.call()
	)

static func schedule_post_income_event_timeline(
	anim_layer: Control,
	active_tweens: Array[Tween],
	speed: float,
	dur_fly_total: float,
	card_hold_sec: float,
	on_spawn_coins_cb: Callable,
	on_remove_card_cb: Callable,
	on_finished_cb: Callable
) -> void:
	if not is_instance_valid(anim_layer):
		return
	var safe_speed := maxf(float(speed), 0.01)
	var tween := anim_layer.create_tween()
	active_tweens.append(tween)
	tween.tween_interval(0.06 / safe_speed)
	if on_spawn_coins_cb.is_valid():
		tween.tween_callback(func():
			on_spawn_coins_cb.call()
		)
	tween.tween_interval(maxf(0.0, float(dur_fly_total) + float(card_hold_sec) / safe_speed))
	if on_remove_card_cb.is_valid():
		tween.tween_callback(func():
			on_remove_card_cb.call()
		)
	tween.tween_interval(0.06 / safe_speed)
	tween.finished.connect(func():
		active_tweens.erase(tween)
		if on_finished_cb.is_valid():
			on_finished_cb.call()
	)
