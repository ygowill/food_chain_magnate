# OnlineLobby：RoomTab 渲染（玩家/旁观者列表 + 配置同步 UI + StartGame 可用性）
extends RefCounted

const UiStylesClass = preload("res://ui/utils/ui_styles.gd")
const LobbyViewModelClass = preload("res://ui/scenes/online/online_lobby_view_model.gd")

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

	# 玩家/旁观者列表
	for child in _lobby.players_list_container.get_children():
		child.queue_free()
	for child2 in _lobby.spectators_list_container.get_children():
		child2.queue_free()

	# Room 配置：host 自动同步 / 非 host 只读
	var cfg: Dictionary = LobbyViewModelClass.get_room_config(room_state)
	var desired_player_count := int(cfg.get("desired_player_count", 0))

	var host_peer_id := LobbyViewModelClass.get_host_peer_id(room_state)
	var player_by_seat: Dictionary = {}
	var players: Array = LobbyViewModelClass.get_players(room_state)
	for p_val in players:
		if not (p_val is Dictionary):
			continue
		var p: Dictionary = Dictionary(p_val)
		var seat := int(p.get("seat_index", -1))
		if seat < 0:
			continue
		player_by_seat[seat] = p

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

			var tags: Array[String] = []
			if peer_id > 0 and peer_id == host_peer_id:
				tags.append("房主")
			if not connected_flag:
				tags.append("掉线")
			if forfeited:
				tags.append("弃权")

			var item := _build_room_member_item(
				"玩家 %d：%s" % [seat_index + 1, name],
				_color_from_palette_index(palette_index),
				tags,
				not connected_flag
			)
			_lobby.players_list_container.add_child(item)
		else:
			var empty_item := _build_room_member_item(
				"玩家 %d：空位" % (seat_index + 1),
				Color(0.35, 0.35, 0.4, 0.8),
				[],
				true
			)
			_lobby.players_list_container.add_child(empty_item)

	var spectators: Array = LobbyViewModelClass.get_spectators(room_state)
	if spectators.is_empty():
		var none := Label.new()
		none.text = "暂无旁观者"
		UiStylesClass.apply_label_hint_dark(none)
		_lobby.spectators_list_container.add_child(none)
	else:
		for s_val in spectators:
			if not (s_val is Dictionary):
				continue
			var s: Dictionary = Dictionary(s_val)
			var s_name := str(s.get("name", "")).strip_edges()
			if s_name.is_empty():
				s_name = "旁观者"
			var s_palette_index := int(s.get("color_index", 0))
			var s_item := _build_room_member_item(
				s_name,
				_color_from_palette_index(s_palette_index),
				["旁观"],
				false
			)
			_lobby.spectators_list_container.add_child(s_item)

	# 我的餐厅/颜色选择（进入房间后才允许）
	if _lobby.my_color_option != null and is_instance_valid(_lobby.my_color_option):
		var local_player_entry: Dictionary = {}
		for p_val2 in players:
			if not (p_val2 is Dictionary):
				continue
			var p2: Dictionary = Dictionary(p_val2)
			if int(p2.get("peer_id", 0)) == local_peer_id:
				local_player_entry = p2
				break
		var can_edit_color := (not code.is_empty()) and (LobbyViewModelClass.get_room_status(room_state) == "Lobby") and (not local_player_entry.is_empty())
		_lobby.my_color_option.disabled = not can_edit_color
		if not local_player_entry.is_empty():
			var local_color_index := int(local_player_entry.get("color_index", 0))
			_lobby._write_local_player_profile(str(local_player_entry.get("name", _lobby.player_name_edit.text)), local_color_index)
			_lobby._apply_my_color_option_selection(local_color_index)

	var in_room: bool = not code.is_empty()
	var is_host: bool = in_room and LobbyViewModelClass.is_host(room_state, local_peer_id)
	if _lobby._room_config_sync_controller != null and is_instance_valid(_lobby._room_config_sync_controller):
		_lobby._room_config_sync_controller.sync_editor_from_room_state(room_state, is_host, _lobby._room_config_editor)

	# StartGame 按钮
	var config_error := false
	if _lobby._room_config_sync_controller != null and is_instance_valid(_lobby._room_config_sync_controller):
		config_error = bool(_lobby._room_config_sync_controller.is_error())
	_lobby.start_game_button.disabled = (not connected) or (not LobbyViewModelClass.can_start_game(room_state, local_peer_id)) or _lobby._start_game_flow_in_progress or config_error

	if in_room and _lobby._current_page != _lobby.LobbyPage.ROOM:
		_lobby._show_page(_lobby.LobbyPage.ROOM, false)

func _color_from_palette_index(palette_index: int) -> Color:
	if Globals == null:
		return Color.WHITE
	if not (Globals.PLAYER_COLOR_PALETTE is Array) or Array(Globals.PLAYER_COLOR_PALETTE).is_empty():
		return Color.WHITE
	var palette: Array = Array(Globals.PLAYER_COLOR_PALETTE)
	var idx := clampi(int(palette_index), 0, palette.size() - 1)
	var c_val = palette[idx]
	if c_val is Color:
		return c_val
	return Color.WHITE

func _build_room_member_item(primary_text: String, accent_color: Color, tags: Array[String], muted: bool) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(0, 34)

	var style := StyleBoxFlat.new()
	style.set_corner_radius_all(6)
	if muted:
		style.bg_color = Color(0.92, 0.88, 0.78, 0.35)
		style.border_color = Color(0.25, 0.25, 0.3, 0.5)
	else:
		style.bg_color = Color(0.92, 0.88, 0.78, 0.6)
		style.border_color = Color(0.25, 0.25, 0.3, 0.7)
	style.set_border_width_all(1)
	panel.add_theme_stylebox_override("panel", style)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	panel.add_child(row)

	var color_rect := ColorRect.new()
	color_rect.custom_minimum_size = Vector2(8, 0)
	color_rect.size_flags_vertical = Control.SIZE_EXPAND_FILL
	color_rect.color = accent_color
	color_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(color_rect)

	var name_label := Label.new()
	name_label.text = str(primary_text)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiStylesClass.apply_label_dark(name_label)
	row.add_child(name_label)

	if not tags.is_empty():
		var tag_label := Label.new()
		tag_label.text = " ".join(tags)
		UiStylesClass.apply_label_hint_dark(tag_label)
		tag_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		tag_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(tag_label)

	return panel
