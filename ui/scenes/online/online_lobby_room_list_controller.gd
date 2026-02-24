# OnlineLobby：房间列表渲染（卡片式 RoomCard）
extends RefCounted

const UiStylesClass = preload("res://ui/utils/ui_styles.gd")

var _lobby = null
var _rooms_list_container: VBoxContainer = null

func setup(lobby) -> void:
	_lobby = lobby
	if _lobby != null and is_instance_valid(_lobby):
		_rooms_list_container = _lobby.rooms_list_container

func render_room_list(rooms: Array) -> void:
	if _lobby == null or not is_instance_valid(_lobby):
		return
	if _rooms_list_container == null or not is_instance_valid(_rooms_list_container):
		return

	for child in _rooms_list_container.get_children():
		child.queue_free()

	if rooms.is_empty():
		var hint := Label.new()
		hint.text = "暂无房间"
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		UiStylesClass.apply_label_hint_dark(hint)
		_rooms_list_container.add_child(hint)
		return

	var current_code: String = _lobby._get_current_room_code()

	for room_val in rooms:
		if not (room_val is Dictionary):
			continue
		var room: Dictionary = Dictionary(room_val)

		var code := str(room.get("room_code", "")).strip_edges().to_upper()
		if code.is_empty():
			continue
		var status := str(room.get("status", "")).strip_edges()
		var desired := int(room.get("desired_player_count", 0))
		var player_count := int(room.get("player_count", 0))
		var password_required := bool(room.get("password_required", false))
		var allow_spectators := bool(room.get("allow_spectators", true))
		var host_name := str(room.get("host_name", "")).strip_edges()

		var card := _build_room_card(code, status, desired, player_count, password_required, allow_spectators, host_name, current_code)
		_rooms_list_container.add_child(card)

func _build_room_card(code: String, status: String, desired: int, player_count: int, password_required: bool, allow_spectators: bool, host_name: String, current_code: String) -> Control:
	# 卡片外壳
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(0, 72)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.95, 0.91, 0.83, 0.55)
	style.border_color = Color(0.17, 0.13, 0.09, 0.15)
	style.set_border_width_all(1)
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_right = 10
	style.corner_radius_bottom_left = 10
	style.content_margin_left = 12
	style.content_margin_top = 10
	style.content_margin_right = 12
	style.content_margin_bottom = 10
	card.add_theme_stylebox_override("panel", style)

	var main_row := HBoxContainer.new()
	main_row.add_theme_constant_override("separation", 12)
	card.add_child(main_row)

	# ── 状态指示区 ──
	var status_vbox := VBoxContainer.new()
	status_vbox.custom_minimum_size = Vector2(40, 0)
	status_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	main_row.add_child(status_vbox)

	var is_lobby := status == "Lobby"
	var dot_color := Color(0.28, 0.55, 0.22) if is_lobby else Color(0.85, 0.55, 0.15)

	var dot := ColorRect.new()
	dot.custom_minimum_size = Vector2(12, 12)
	dot.color = dot_color
	dot.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status_vbox.add_child(dot)

	var status_text := Label.new()
	status_text.text = "等待中" if is_lobby else "对局中"
	status_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_text.add_theme_font_size_override("font_size", 11)
	UiStylesClass.apply_label_hint_dark(status_text)
	status_vbox.add_child(status_text)

	# ── 信息区 ──
	var info_vbox := VBoxContainer.new()
	info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_vbox.add_theme_constant_override("separation", 4)
	main_row.add_child(info_vbox)

	# 顶行：房间码 + 密码标记 + 房主名
	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 8)
	info_vbox.add_child(top_row)

	var code_label := Label.new()
	code_label.text = code
	code_label.add_theme_font_size_override("font_size", 16)
	UiStylesClass.apply_label_dark(code_label)
	top_row.add_child(code_label)

	if password_required:
		var pw_tag := Label.new()
		pw_tag.text = "(密码)"
		pw_tag.add_theme_font_size_override("font_size", 12)
		UiStylesClass.apply_label_hint_dark(pw_tag)
		top_row.add_child(pw_tag)

	var host_label := Label.new()
	host_label.text = host_name if not host_name.is_empty() else "-"
	host_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	host_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	UiStylesClass.apply_label_hint_dark(host_label)
	top_row.add_child(host_label)

	# 底行：进度条 + 人数
	var bottom_row := HBoxContainer.new()
	bottom_row.add_theme_constant_override("separation", 8)
	bottom_row.alignment = BoxContainer.ALIGNMENT_BEGIN
	info_vbox.add_child(bottom_row)

	var progress_bar := _build_player_count_bar(player_count, desired)
	bottom_row.add_child(progress_bar)

	var count_label := Label.new()
	count_label.text = "%d/%d 玩家" % [player_count, desired]
	count_label.add_theme_font_size_override("font_size", 12)
	UiStylesClass.apply_label_hint_dark(count_label)
	bottom_row.add_child(count_label)

	# ── 操作区 ──
	var action_vbox := VBoxContainer.new()
	action_vbox.custom_minimum_size = Vector2(100, 0)
	action_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	action_vbox.add_theme_constant_override("separation", 4)
	main_row.add_child(action_vbox)

	if code == current_code:
		var enter_btn := Button.new()
		enter_btn.text = "进入"
		UiStylesClass.apply_button_secondary(enter_btn)
		enter_btn.pressed.connect(func() -> void:
			_lobby._show_page(_lobby.LobbyPage.ROOM, false)
		)
		action_vbox.add_child(enter_btn)
	else:
		var can_join := is_lobby and desired > 0 and player_count < desired
		var can_spectate := status == "InGame" and allow_spectators

		var join_btn := Button.new()
		join_btn.text = "加入"
		join_btn.disabled = not can_join
		UiStylesClass.apply_button_primary(join_btn)
		join_btn.pressed.connect(func() -> void:
			_lobby._join_room_from_list(code, password_required, false)
		)
		action_vbox.add_child(join_btn)

		if can_spectate:
			var spectate_btn := Button.new()
			spectate_btn.text = "观战"
			UiStylesClass.apply_button_secondary(spectate_btn)
			spectate_btn.pressed.connect(func() -> void:
				_lobby._join_room_from_list(code, password_required, true)
			)
			action_vbox.add_child(spectate_btn)

	return card

func _build_player_count_bar(current: int, total: int) -> Control:
	# 双层 PanelContainer 进度条：80x6px
	var outer := PanelContainer.new()
	outer.custom_minimum_size = Vector2(80, 6)
	var outer_style := StyleBoxFlat.new()
	outer_style.bg_color = Color(0.85, 0.82, 0.75, 0.6)
	outer_style.set_border_width_all(0)
	outer_style.corner_radius_top_left = 3
	outer_style.corner_radius_top_right = 3
	outer_style.corner_radius_bottom_right = 3
	outer_style.corner_radius_bottom_left = 3
	outer_style.content_margin_left = 0
	outer_style.content_margin_top = 0
	outer_style.content_margin_right = 0
	outer_style.content_margin_bottom = 0
	outer.add_theme_stylebox_override("panel", outer_style)

	var ratio := 0.0
	if total > 0:
		ratio = clampf(float(current) / float(total), 0.0, 1.0)

	var fill := ColorRect.new()
	fill.custom_minimum_size = Vector2(int(80.0 * ratio), 6)
	fill.color = Color(0.73, 0.23, 0.18, 0.85)
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outer.add_child(fill)

	return outer
