# 晚餐结算动画：控制条 UI 辅助
class_name DinnertimeAnimationControlBarHelpers
extends RefCounted

const UiStylesClass = preload("res://ui/utils/ui_styles.gd")

static func build_control_bar(on_next: Callable, on_skip: Callable) -> PanelContainer:
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
	if on_next.is_valid():
		next_btn.pressed.connect(on_next)
	hbox.add_child(next_btn)

	var skip_btn := Button.new()
	skip_btn.name = "SkipBtn"
	skip_btn.text = "跳过全部"
	skip_btn.custom_minimum_size = Vector2(80, 32)
	UiStylesClass.apply_button_secondary(skip_btn)
	if on_skip.is_valid():
		skip_btn.pressed.connect(on_skip)
	hbox.add_child(skip_btn)

	return bar

static func update_control_bar(control_bar: Control, current_idx: int, total_orders: int, previewing: bool, post_income_playing: bool, post_income_done: bool) -> void:
	if not is_instance_valid(control_bar):
		return
	var lbl: Label = control_bar.find_child("ProgressLabel", true, false)
	if lbl != null:
		lbl.text = "晚餐结算 (%d/%d)" % [current_idx, total_orders]
	var btn: Button = control_bar.find_child("NextBtn", true, false)
	if btn == null:
		return

	if post_income_playing:
		btn.text = "播放中..."
		btn.disabled = true
	elif current_idx >= total_orders and not previewing and post_income_done:
		btn.text = "确认结算"
		btn.disabled = false
	elif previewing:
		btn.text = "下一笔"
		btn.disabled = false
	else:
		btn.text = "播放中..."
		btn.disabled = true
