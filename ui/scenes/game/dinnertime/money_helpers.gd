# 晚餐结算动画：金币与金额滚动辅助
class_name DinnertimeAnimationMoneyHelpers
extends RefCounted

static func compute_coin_count(revenue: int, base_count: int, per_amount: int, max_count: int) -> int:
	var rev := int(revenue)
	if rev <= 0:
		return 0
	var step := maxi(1, int(per_amount))
	var count := int(ceil(float(rev) / float(step)))
	count = maxi(count, int(base_count))
	if int(max_count) > 0:
		count = mini(count, int(max_count))
	return count

static func spawn_flying_coins(
	anim_layer: Control,
	coin_tex: Texture2D,
	from: Vector2,
	to: Vector2,
	revenue: int,
	owner_id: int,
	dur: float,
	coin_delay_step: float,
	coin_count: int,
	coin_base_size: float,
	coin_size_scale: float,
	active_tweens: Array[Tween],
	on_numbers: Callable
) -> void:
	if not is_instance_valid(anim_layer):
		return
	if revenue <= 0:
		return
	var count := maxi(0, int(coin_count))
	if count <= 0:
		count = compute_coin_count(revenue, 0, 2, 0)
	var coin_size := float(coin_base_size) * float(coin_size_scale)
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
		anim_layer.add_child(coin_wrap)

		if coin_tex != null:
			var shadow := TextureRect.new()
			shadow.texture = coin_tex
			shadow.custom_minimum_size = Vector2(coin_size, coin_size)
			shadow.size = Vector2(coin_size, coin_size)
			shadow.position = Vector2(1, 1)
			shadow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			shadow.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			shadow.modulate = Color(0, 0, 0, 0.25)
			shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
			coin_wrap.add_child(shadow)

			var coin := TextureRect.new()
			coin.texture = coin_tex
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

		var tw := anim_layer.create_tween()
		active_tweens.append(tw)
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
			active_tweens.erase(tw)
		)

	var number_dur := maxf(0.01, float(dur) + float(maxi(0, count - 1)) * float(coin_delay_step))
	if on_numbers.is_valid():
		on_numbers.call(owner_id, revenue, number_dur)

static func animate_bank_decrease(bank_label: Label, active_tweens: Array[Tween], from_val: int, amount: int, dur: float) -> int:
	var to_val := int(from_val) - int(amount)
	if not is_instance_valid(bank_label):
		return to_val
	var d := maxf(0.01, float(dur))

	var tween := bank_label.create_tween()
	active_tweens.append(tween)
	tween.tween_method(func(v: float):
		if is_instance_valid(bank_label):
			bank_label.text = "$%d" % int(v)
	, float(from_val), float(to_val), d)
	tween.tween_callback(func():
		active_tweens.erase(tween)
	)
	return to_val

static func animate_bank_increase(bank_label: Label, active_tweens: Array[Tween], from_val: int, amount: int, dur: float) -> int:
	var to_val := int(from_val) + int(amount)
	if not is_instance_valid(bank_label):
		return to_val
	var d := maxf(0.01, float(dur))

	var tween := bank_label.create_tween()
	active_tweens.append(tween)
	tween.tween_method(func(v: float):
		if is_instance_valid(bank_label):
			bank_label.text = "$%d" % int(v)
	, float(from_val), float(to_val), d)
	tween.tween_callback(func():
		active_tweens.erase(tween)
	)
	return to_val

static func animate_player_income(
	anim_layer: Control,
	player_id: int,
	amount: int,
	dur: float,
	speed: float,
	active_tweens: Array[Tween],
	player_running_cash: Dictionary,
	apply_cash_overrides_cb: Callable,
	target_pos: Vector2
) -> void:
	if amount <= 0:
		return

	var from_val := int(player_running_cash.get(player_id, 0))
	player_running_cash[player_id] = from_val + amount
	var to_val = player_running_cash[player_id]

	if is_instance_valid(anim_layer):
		var d := maxf(0.01, float(dur))
		var tw := anim_layer.create_tween()
		active_tweens.append(tw)
		tw.tween_method(func(v: float):
			player_running_cash[player_id] = int(v)
			if apply_cash_overrides_cb.is_valid():
				apply_cash_overrides_cb.call()
		, float(from_val), float(to_val), d)
		tw.tween_callback(func():
			active_tweens.erase(tw)
		)

	if not is_instance_valid(anim_layer):
		return
	var lbl := Label.new()
	lbl.text = "+$%d" % amount
	lbl.add_theme_font_size_override("font_size", 16)
	lbl.add_theme_color_override("font_color", Color(0.2, 0.8, 0.2, 1))
	lbl.position = target_pos - Vector2(20, 10)
	anim_layer.add_child(lbl)
	var dur2 := 1.5 / maxf(speed, 0.01)
	var tween := anim_layer.create_tween().set_parallel(true)
	active_tweens.append(tween)
	tween.tween_property(lbl, "position:y", lbl.position.y - 40, dur2)
	tween.tween_property(lbl, "modulate:a", 0.0, dur2).set_delay(dur2 * 0.5)
	tween.chain().tween_callback(func():
		if is_instance_valid(lbl):
			lbl.queue_free()
		active_tweens.erase(tween)
	)
