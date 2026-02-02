# OnlineLobby：房间列表渲染与加入入口（从 online_lobby.gd 拆出以降低文件体积）
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

	var connected := NetClient != null and NetClient.is_online_client_connected()
	if not connected:
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

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		_rooms_list_container.add_child(row)

		var code_label := Label.new()
		code_label.text = code
		code_label.custom_minimum_size = Vector2(90, 0)
		row.add_child(code_label)

		var status_label := Label.new()
		status_label.text = status
		status_label.custom_minimum_size = Vector2(60, 0)
		row.add_child(status_label)

		var count_label := Label.new()
		count_label.text = "%d/%d" % [player_count, desired]
		count_label.custom_minimum_size = Vector2(60, 0)
		row.add_child(count_label)

		var lock_label := Label.new()
		lock_label.text = "🔒" if password_required else ""
		lock_label.custom_minimum_size = Vector2(24, 0)
		row.add_child(lock_label)

		var host_name := str(room.get("host_name", "")).strip_edges()
		var host_label := Label.new()
		host_label.text = host_name
		host_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(host_label)

		if code == current_code:
			var enter_btn := Button.new()
			enter_btn.text = "进入"
			UiStylesClass.apply_button_secondary(enter_btn)
			enter_btn.pressed.connect(func() -> void:
				_lobby._show_page(_lobby.LobbyPage.ROOM, false)
			)
			row.add_child(enter_btn)
			continue

		var can_join := status == "Lobby" and desired > 0 and player_count < desired
		var can_spectate := status == "InGame" and allow_spectators

		var join_btn := Button.new()
		join_btn.text = "加入"
		join_btn.disabled = not can_join
		UiStylesClass.apply_button_primary(join_btn)
		join_btn.pressed.connect(func() -> void:
			_lobby._join_room_from_list(code, password_required)
		)
		row.add_child(join_btn)

		var spectate_btn := Button.new()
		spectate_btn.text = "观战"
		spectate_btn.disabled = not can_spectate
		UiStylesClass.apply_button_secondary(spectate_btn)
		spectate_btn.pressed.connect(func() -> void:
			_lobby._join_room_from_list(code, password_required)
		)
		row.add_child(spectate_btn)
