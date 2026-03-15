# 晚餐结算动画：后置收入员工卡片展示
class_name DinnertimeAnimationPostIncomeCard
extends RefCounted

const EmployeeCardClass = preload("res://ui/components/employee_card/employee_card.gd")
const IncomeUtilsClass = preload("res://ui/scenes/game/dinnertime/income_utils.gd")

static func create(anim_layer: Control, scene: Node, map_canvas, event: Dictionary, card_scale: float, speed: float, active_tweens: Array) -> Control:
	if not is_instance_valid(anim_layer):
		return null
	if not bool(event.get("show_card", false)):
		return null

	var employee_id := str(event.get("employee_id", "")).strip_edges()
	if employee_id.is_empty():
		return null
	var player_id := int(event.get("player_id", -1))

	var holder := PanelContainer.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.08, 0.07, 0.06, 0.90)
	panel_style.set_corner_radius_all(8)
	panel_style.set_content_margin_all(6)
	panel_style.border_width_left = 1
	panel_style.border_width_top = 1
	panel_style.border_width_right = 1
	panel_style.border_width_bottom = 1
	panel_style.border_color = Color(0.95, 0.86, 0.62, 0.85)
	holder.add_theme_stylebox_override("panel", panel_style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	holder.add_child(vbox)

	var title := Label.new()
	title.text = "%s - %s" % [_get_player_name(player_id), IncomeUtilsClass.get_employee_card_name(employee_id)]
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", Color(1, 0.95, 0.82, 1))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var card := EmployeeCardClass.new()
	card.variant = EmployeeCardClass.CardVariant.COMPACT
	card.draggable = false
	card.show_salary_indicator = false
	card.multiline_name = false
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.set_display_scale(card_scale)
	card.setup({
		"id": employee_id,
		"name": IncomeUtilsClass.get_employee_card_name(employee_id),
		"role": "special",
		"description": "",
		"salary": false,
		"range": {"type": "none", "value": 0},
		"train_to": [],
	})
	vbox.add_child(card)

	anim_layer.add_child(holder)
	var card_size := holder.get_combined_minimum_size()
	if card_size == Vector2.ZERO:
		card_size = Vector2(126, 106)
	holder.custom_minimum_size = card_size
	holder.size = card_size
	holder.position = _global_to_layer(anim_layer, _get_card_global_pos(scene, map_canvas, card_size))
	holder.modulate.a = 0.0
	var fade := holder.create_tween()
	active_tweens.append(fade)
	fade.tween_property(holder, "modulate:a", 1.0, 0.12 / maxf(speed, 0.01))
	fade.tween_callback(func():
		active_tweens.erase(fade)
	)
	return holder

static func remove(card: Control) -> void:
	if is_instance_valid(card):
		card.queue_free()

static func _global_to_layer(anim_layer: Control, global_pos: Vector2) -> Vector2:
	if is_instance_valid(anim_layer):
		return global_pos - anim_layer.global_position
	return global_pos

static func _get_card_global_pos(scene: Node, map_canvas, card_size: Vector2) -> Vector2:
	var base := Vector2(16, 56)
	var turn_order = _resolve_turn_order_display_control(scene)
	if is_instance_valid(turn_order):
		var rect := Rect2(turn_order.global_position, turn_order.size)
		base = Vector2(
			rect.position.x - card_size.x - 14.0,
			rect.position.y + maxf(0.0, (rect.size.y - card_size.y) * 0.5)
		)
	elif map_canvas != null and is_instance_valid(map_canvas) and map_canvas is Control:
		base = (map_canvas as Control).global_position + Vector2(12, 12)
	base.x = maxf(8.0, base.x)
	base.y = maxf(8.0, base.y)
	return base

static func _resolve_turn_order_display_control(scene: Node) -> Control:
	if scene == null or not is_instance_valid(scene):
		return null
	var direct = scene.get("turn_order_display")
	if direct is Control and is_instance_valid(direct):
		return direct
	if scene.has_node("UIRoot/MainContent/CenterSplit/GameArea/TurnOrderOverlay/TurnOrderDisplay"):
		var node := scene.get_node("UIRoot/MainContent/CenterSplit/GameArea/TurnOrderOverlay/TurnOrderDisplay")
		if node is Control and is_instance_valid(node):
			return node
	return null

static func _get_player_name(player_id: int) -> String:
	if player_id < 0:
		return "玩家?"
	if Globals != null and Globals.has_method("get_player_name"):
		return str(Globals.get_player_name(player_id))
	return "玩家 %d" % (player_id + 1)
