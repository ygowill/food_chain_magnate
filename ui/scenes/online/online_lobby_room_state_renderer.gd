# OnlineLobby：RoomPage 渲染（SectionPanel + GameSetup 风格 PlayerCard + 旁观者 + 配置同步 + StartGame）
extends RefCounted

const UiStylesClass = preload("res://ui/utils/ui_styles.gd")
const LobbyViewModelClass = preload("res://ui/scenes/online/online_lobby_view_model.gd")

const PLAYER_COLORS: Array[Color] = [
	Color(0.73, 0.23, 0.18),
	Color(0.22, 0.45, 0.65),
	Color(0.28, 0.55, 0.22),
	Color(0.72, 0.58, 0.20),
	Color(0.55, 0.30, 0.58),
	Color(0.20, 0.55, 0.52),
]

var _lobby = null

func setup(lobby) -> void:
	_lobby = lobby

func render_room_state(room_state: Dictionary) -> void:
	if _lobby == null or not is_instance_valid(_lobby):
		return

	var connected := NetClient != null and NetClient.is_online_client_connected()
	if not connected:
		_lobby.room_code_label.text = "房间：-"
		return

	var local_peer_id := int(_lobby.multiplayer.get_unique_id())
	var code := LobbyViewModelClass.get_room_code(room_state)
	if code.is_empty():
		_lobby.room_code_label.text = "房间：-"
	else:
		_lobby.room_code_label.text = "房间：%s" % code

	# 清空玩家/旁观者列表
	for child in _lobby.players_list_container.get_children():
		child.queue_free()
	for child2 in _lobby.spectators_list_container.get_children():
		child2.queue_free()

	var cfg: Dictionary = LobbyViewModelClass.get_room_config(room_state)
	var desired_player_count := int(cfg.get("desired_player_count", 0))
	var in_room: bool = not code.is_empty()
	var is_host_room: bool = in_room and LobbyViewModelClass.is_host(room_state, local_peer_id)
	var is_lobby_status: bool = LobbyViewModelClass.get_room_status(room_state) == "Lobby"
	var is_resume_room: bool = LobbyViewModelClass.is_resume_archive_room(room_state)

	var host_peer_id := LobbyViewModelClass.get_host_peer_id(room_state)
	var host_seat_index := LobbyViewModelClass.get_host_seat_index(room_state)
	var player_by_seat: Dictionary = {}
	var players: Array = LobbyViewModelClass.get_players(room_state)
	var waiting_members: Array = LobbyViewModelClass.get_waiting_members(room_state)
	for p_val in players:
		if not (p_val is Dictionary):
			continue
		var p: Dictionary = Dictionary(p_val)
		var seat := int(p.get("seat_index", -1))
		if seat < 0:
			continue
		player_by_seat[seat] = p

	# ── 玩家卡片（SectionPanel 包裹） ──
	var players_panel := _build_section_panel()
	_lobby.players_list_container.add_child(players_panel)

	var players_vbox := VBoxContainer.new()
	players_vbox.add_theme_constant_override("separation", 6)
	players_panel.add_child(players_vbox)

	var players_header := Label.new()
	players_header.text = "房间玩家"
	players_header.add_theme_font_size_override("font_size", 16)
	UiStylesClass.apply_label_dark(players_header)
	players_vbox.add_child(players_header)

	if is_resume_room and is_lobby_status:
		var waiting_panel := _build_waiting_members_panel(waiting_members, desired_player_count, player_by_seat, is_host_room)
		if waiting_panel != null:
			players_vbox.add_child(waiting_panel)

	var seat_count := maxi(players.size(), desired_player_count)
	for seat_index in range(seat_count):
		if player_by_seat.has(seat_index):
			var p: Dictionary = Dictionary(player_by_seat.get(seat_index, {}))
			var name := str(p.get("name", "")).strip_edges()
			if name.is_empty():
				name = "玩家 %d" % (seat_index + 1)
			var palette_index := int(p.get("color_index", 0))
			var connected_flag := bool(p.get("connected", true))
			var forfeited := bool(p.get("forfeited", false))
			var peer_id := int(p.get("peer_id", 0))

			var tag := ""
			if seat_index == host_seat_index or (peer_id > 0 and peer_id == host_peer_id):
				tag = "房主"
			elif not connected_flag:
				tag = "掉线"
			elif forfeited:
				tag = "弃权"

			var player_color := PLAYER_COLORS[palette_index] if palette_index < PLAYER_COLORS.size() else PLAYER_COLORS[0]
			var restaurant_logo_id := int(p.get("restaurant_logo_id", -1))
			var can_edit_logo := is_host_room and is_lobby_status and not is_resume_room
			var show_unassign_button := is_resume_room and is_lobby_status and is_host_room
			var card := _build_player_card(
				seat_index,
				name,
				player_color,
				tag,
				false,
				restaurant_logo_id,
				can_edit_logo,
				players,
				desired_player_count,
				show_unassign_button,
				Callable(self, "_request_unassign_seat").bind(seat_index)
			)
			players_vbox.add_child(card)
		else:
			var card := _build_player_card(seat_index, "等待加入...", Color(0.5, 0.5, 0.55, 0.6), "空位", true, -1, false)
			players_vbox.add_child(card)

	# ── 旁观者（SectionPanel 包裹） ──
	var spectators_panel := _build_section_panel()
	_lobby.spectators_list_container.add_child(spectators_panel)

	var spectators_vbox := VBoxContainer.new()
	spectators_vbox.add_theme_constant_override("separation", 6)
	spectators_panel.add_child(spectators_vbox)

	var spectators_header := Label.new()
	spectators_header.text = "旁观者"
	spectators_header.add_theme_font_size_override("font_size", 16)
	UiStylesClass.apply_label_dark(spectators_header)
	spectators_vbox.add_child(spectators_header)

	var spectators: Array = LobbyViewModelClass.get_spectators(room_state)
	if spectators.is_empty():
		var none := Label.new()
		none.text = "暂无旁观者"
		UiStylesClass.apply_label_hint_dark(none)
		spectators_vbox.add_child(none)
	else:
		for s_val in spectators:
			if not (s_val is Dictionary):
				continue
			var s: Dictionary = Dictionary(s_val)
			var s_name := str(s.get("name", "")).strip_edges()
			if s_name.is_empty():
				s_name = "旁观者"
			var s_palette_index := int(s.get("color_index", 0))
			var s_color := PLAYER_COLORS[s_palette_index] if s_palette_index < PLAYER_COLORS.size() else PLAYER_COLORS[0]
			var s_item := _build_spectator_item(s_name, s_color)
			spectators_vbox.add_child(s_item)

	# ── 本地 profile 同步（房主分配 Logo 后回写到本地缓存） ──
	if _lobby.my_color_option != null and is_instance_valid(_lobby.my_color_option):
		var my_logo_row: Node = _lobby.my_color_option.get_parent()
		if my_logo_row != null and my_logo_row is CanvasItem:
			(my_logo_row as CanvasItem).visible = false
		_lobby.my_color_option.disabled = true
		var local_player_entry: Dictionary = {}
		for p_val2 in players:
			if not (p_val2 is Dictionary):
				continue
			var p2: Dictionary = Dictionary(p_val2)
			if int(p2.get("peer_id", 0)) == local_peer_id:
				local_player_entry = p2
				break
		if not local_player_entry.is_empty():
			var local_logo_id := int(local_player_entry.get("restaurant_logo_id", -1))
			_lobby._write_local_player_profile(str(local_player_entry.get("name", _lobby.player_name_edit.text)), local_logo_id)

	# ── 配置同步 ──
	var is_host: bool = is_host_room
	if _lobby._room_config_sync_controller != null and is_instance_valid(_lobby._room_config_sync_controller):
		_lobby._room_config_sync_controller.sync_editor_from_room_state(room_state, is_host, _lobby._room_config_editor)

	# ── StartGame 按钮 ──
	var config_error := false
	if _lobby._room_config_sync_controller != null and is_instance_valid(_lobby._room_config_sync_controller):
		config_error = bool(_lobby._room_config_sync_controller.is_error())
	_lobby.start_game_button.disabled = (not connected) or (not LobbyViewModelClass.can_start_game(room_state, local_peer_id)) or _lobby._start_game_flow_in_progress or config_error

	if in_room and _lobby._current_page != _lobby.LobbyPage.ROOM:
		_lobby._show_page(_lobby.LobbyPage.ROOM, false)

# ── 区块面板构建器 ──

func _build_section_panel(bg_color: Color = Color(0.95, 0.91, 0.83, 0.55)) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := StyleBoxFlat.new()
	style.bg_color = bg_color
	style.border_color = Color(0.17, 0.13, 0.09, 0.15)
	style.set_border_width_all(1)
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_right = 10
	style.corner_radius_bottom_left = 10
	style.content_margin_left = 16
	style.content_margin_top = 14
	style.content_margin_right = 16
	style.content_margin_bottom = 14
	panel.add_theme_stylebox_override("panel", style)
	return panel

# ── GameSetup 风格 PlayerCard（房主可分配 Logo） ──

func _build_player_card(
	seat_index: int,
	display_name: String,
	player_color: Color,
	tag: String,
	is_empty_seat: bool,
	restaurant_logo_id: int,
	can_edit_logo: bool,
	players: Array = [],
	desired_player_count: int = 0,
	show_unassign_button: bool = false,
	unassign_callback: Callable = Callable()
) -> Control:
	var card_panel := PanelContainer.new()
	card_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var card_style := StyleBoxFlat.new()
	if is_empty_seat:
		card_style.bg_color = Color(0.92, 0.88, 0.78, 0.35)
		card_style.border_color = Color(0.25, 0.25, 0.3, 0.5)
	else:
		card_style.bg_color = Color(0.95, 0.90, 0.80, 0.5)
		card_style.border_color = Color(0.17, 0.13, 0.09, 0.12)
	card_style.set_border_width_all(1)
	card_style.corner_radius_top_left = 6
	card_style.corner_radius_top_right = 6
	card_style.corner_radius_bottom_right = 6
	card_style.corner_radius_bottom_left = 6
	card_style.content_margin_left = 0
	card_style.content_margin_top = 0
	card_style.content_margin_right = 0
	card_style.content_margin_bottom = 0
	card_panel.add_theme_stylebox_override("panel", card_style)
	card_panel.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	card_panel.add_child(row)

	# 色条 (4px)
	var color_bar := ColorRect.new()
	color_bar.custom_minimum_size = Vector2(4, 0)
	color_bar.size_flags_vertical = Control.SIZE_EXPAND_FILL
	color_bar.color = player_color
	color_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(color_bar)

	# 内容行
	var content_margin := MarginContainer.new()
	content_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_margin.add_theme_constant_override("margin_left", 10)
	content_margin.add_theme_constant_override("margin_top", 6)
	content_margin.add_theme_constant_override("margin_right", 10)
	content_margin.add_theme_constant_override("margin_bottom", 6)
	row.add_child(content_margin)

	var content_row := HBoxContainer.new()
	content_row.add_theme_constant_override("separation", 8)
	content_row.alignment = BoxContainer.ALIGNMENT_BEGIN
	content_margin.add_child(content_row)

	# 编号
	var number_label := Label.new()
	number_label.text = "P%d" % (seat_index + 1)
	number_label.custom_minimum_size = Vector2(32, 0)
	UiStylesClass.apply_label_dark(number_label)
	content_row.add_child(number_label)

	# 名称
	var name_label := Label.new()
	name_label.text = display_name
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if is_empty_seat:
		UiStylesClass.apply_label_hint_dark(name_label)
	else:
		UiStylesClass.apply_label_dark(name_label)
	content_row.add_child(name_label)

	if not is_empty_seat:
		if can_edit_logo:
			var logo_option := _build_logo_option_button(restaurant_logo_id)
			logo_option.item_selected.connect(func(index: int) -> void:
				if NetClient == null or not NetClient.is_online_client_connected():
					return
				if not NetClient.has_method("request_update_room_config"):
					return
				var meta_val = logo_option.get_item_metadata(index)
				var choices_patch := _build_logo_choices_patch(players, desired_player_count, seat_index, int(meta_val))
				NetClient.request_update_room_config({"restaurant_logo_choices_by_player": choices_patch})
			)
			UiStylesClass.apply_option_button_field(logo_option)
			content_row.add_child(logo_option)
		else:
			var logo_label := Label.new()
			logo_label.text = "Logo：%s" % _get_logo_display_text(restaurant_logo_id)
			logo_label.custom_minimum_size = Vector2(170, 0)
			logo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			UiStylesClass.apply_label_hint_dark(logo_label)
			content_row.add_child(logo_label)

	# 状态标签
	if not tag.is_empty():
		var tag_label := Label.new()
		tag_label.text = tag
		tag_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		tag_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		UiStylesClass.apply_label_hint_dark(tag_label)
		content_row.add_child(tag_label)

	if not is_empty_seat and show_unassign_button and unassign_callback.is_valid():
		var unassign_button := Button.new()
		unassign_button.text = "移回待分配"
		UiStylesClass.apply_button_secondary(unassign_button)
		unassign_button.pressed.connect(func() -> void:
			unassign_callback.call()
		)
		content_row.add_child(unassign_button)

	return card_panel

func _build_waiting_members_panel(waiting_members: Array, desired_player_count: int, player_by_seat: Dictionary, is_host_room: bool) -> Control:
	var panel := _build_section_panel(Color(0.93, 0.89, 0.80, 0.45))
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 6)
	panel.add_child(root)

	var header := Label.new()
	header.text = "待分配成员"
	header.add_theme_font_size_override("font_size", 15)
	UiStylesClass.apply_label_dark(header)
	root.add_child(header)

	var available_seats: Array[int] = []
	for seat_index in range(desired_player_count):
		if not player_by_seat.has(seat_index):
			available_seats.append(seat_index)

	if waiting_members.is_empty():
		var none := Label.new()
		none.text = "当前没有待分配成员"
		UiStylesClass.apply_label_hint_dark(none)
		root.add_child(none)
		return panel

	for member_val in waiting_members:
		if not (member_val is Dictionary):
			continue
		var member: Dictionary = Dictionary(member_val)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		root.add_child(row)

		var role_label := ""
		if str(member.get("role", "")).strip_edges() == "host":
			role_label = "房主"
		elif not bool(member.get("connected", false)):
			role_label = "未连接"

		var name_label := Label.new()
		var display_name := str(member.get("name", "")).strip_edges()
		if display_name.is_empty():
			display_name = "待分配玩家"
		if not role_label.is_empty():
			display_name += "（%s）" % role_label
		name_label.text = display_name
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		UiStylesClass.apply_label_dark(name_label)
		row.add_child(name_label)

		if not is_host_room:
			continue
		if available_seats.is_empty():
			var full_label := Label.new()
			full_label.text = "座位已满"
			UiStylesClass.apply_label_hint_dark(full_label)
			row.add_child(full_label)
			continue
		for seat_index2 in available_seats:
			var btn := Button.new()
			btn.text = "P%d" % (seat_index2 + 1)
			UiStylesClass.apply_button_secondary(btn)
			var user_id := str(member.get("user_id", "")).strip_edges()
			btn.disabled = user_id.is_empty()
			btn.pressed.connect(Callable(self, "_request_assign_waiting_member").bind(user_id, seat_index2))
			row.add_child(btn)

	return panel

func _request_assign_waiting_member(user_id: String, seat_index: int) -> void:
	if NetClient == null or not NetClient.is_online_client_connected():
		return
	if not NetClient.has_method("request_assign_room_seat"):
		return
	NetClient.request_assign_room_seat(user_id, seat_index)

func _request_unassign_seat(seat_index: int) -> void:
	if NetClient == null or not NetClient.is_online_client_connected():
		return
	if not NetClient.has_method("request_unassign_room_seat"):
		return
	NetClient.request_unassign_room_seat(seat_index)

func _build_logo_choices_patch(players: Array, desired_player_count: int, seat_index: int, logo_id: int) -> Array[int]:
	var total := maxi(0, desired_player_count)
	for p_val in players:
		if not (p_val is Dictionary):
			continue
		var seat := int(Dictionary(p_val).get("seat_index", -1))
		if seat >= 0:
			total = maxi(total, seat + 1)
	total = maxi(total, seat_index + 1)

	var out: Array[int] = []
	for _i in range(total):
		out.append(-1)
	for p_val2 in players:
		if not (p_val2 is Dictionary):
			continue
		var p: Dictionary = Dictionary(p_val2)
		var seat2 := int(p.get("seat_index", -1))
		if seat2 < 0 or seat2 >= out.size():
			continue
		out[seat2] = int(p.get("restaurant_logo_id", -1))
	if seat_index >= 0 and seat_index < out.size():
		out[seat_index] = int(logo_id)
	return out

func _build_logo_option_button(selected_logo_id: int) -> OptionButton:
	var opt := OptionButton.new()
	opt.custom_minimum_size = Vector2(220, 0)
	opt.size_flags_horizontal = Control.SIZE_SHRINK_END
	opt.add_item("随机")
	opt.set_item_metadata(0, -1)

	if _lobby != null and _lobby.has_method("_ensure_logo_icons_cache"):
		_lobby._ensure_logo_icons_cache()

	var piece_ids: Array = Array(_lobby._logo_piece_ids) if _lobby != null else []
	var logo_icons: Array = Array(_lobby._logo_icons_small) if _lobby != null else []
	var logo_count := piece_ids.size()
	if logo_count <= 0 and _lobby != null and _lobby.has_method("_get_default_logo_count"):
		logo_count = int(_lobby._get_default_logo_count())
	logo_count = maxi(1, logo_count)

	for i in range(logo_count):
		var piece_id := str(piece_ids[i]).strip_edges() if i < piece_ids.size() else ""
		var display_name := _get_logo_display_name(piece_id, i)
		var icon_tex: Texture2D = logo_icons[i] if i < logo_icons.size() else null
		if icon_tex != null:
			opt.add_icon_item(icon_tex, display_name)
		else:
			opt.add_item(display_name)
		opt.set_item_metadata(i + 1, i)

	var selected_index := 0
	for i in range(opt.item_count):
		if int(opt.get_item_metadata(i)) == int(selected_logo_id):
			selected_index = i
			break
	opt.select(selected_index)
	return opt

func _get_logo_display_text(restaurant_logo_id: int) -> String:
	if restaurant_logo_id < 0:
		return "随机"
	if _lobby != null and _lobby.has_method("_ensure_logo_icons_cache"):
		_lobby._ensure_logo_icons_cache()
	var piece_id := ""
	if _lobby != null:
		var piece_ids: Array = Array(_lobby._logo_piece_ids)
		if restaurant_logo_id >= 0 and restaurant_logo_id < piece_ids.size():
			piece_id = str(piece_ids[restaurant_logo_id]).strip_edges()
	return _get_logo_display_name(piece_id, restaurant_logo_id)

func _get_logo_display_name(piece_id: String, index: int) -> String:
	if _lobby != null and _lobby.has_method("_get_logo_display_name"):
		return str(_lobby._get_logo_display_name(piece_id, index))
	return "店铺 %d" % (index + 1)

# ── 旁观者条目 ──

func _build_spectator_item(display_name: String, accent_color: Color) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var color_rect := ColorRect.new()
	color_rect.custom_minimum_size = Vector2(8, 8)
	color_rect.color = accent_color
	color_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(color_rect)

	var label := Label.new()
	label.text = display_name
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiStylesClass.apply_label_hint_dark(label)
	row.add_child(label)

	return row
