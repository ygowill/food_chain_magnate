# 联机大厅（M1）：连接服务器、创建/加入房间、显示 RoomState
extends Control

@onready var server_url_edit: LineEdit = $Root/ConnectionSection/ServerRow/ServerUrlEdit
@onready var player_name_edit: LineEdit = $Root/ConnectionSection/ProfileRow/PlayerNameEdit
@onready var color_index_spin: SpinBox = $Root/ConnectionSection/ProfileRow/ColorIndexSpin
@onready var connect_button: Button = $Root/ConnectionSection/ButtonsRow/ConnectButton
@onready var disconnect_button: Button = $Root/ConnectionSection/ButtonsRow/DisconnectButton

@onready var create_player_count_spin: SpinBox = $Root/RoomSection/CreateRoom/PlayerCountRow/PlayerCountSpin
@onready var create_password_edit: LineEdit = $Root/RoomSection/CreateRoom/PasswordRow/RoomPasswordEdit
@onready var create_room_button: Button = $Root/RoomSection/CreateRoom/CreateRoomButton

@onready var join_room_code_edit: LineEdit = $Root/RoomSection/JoinRoom/RoomCodeRow/RoomCodeEdit
@onready var join_password_edit: LineEdit = $Root/RoomSection/JoinRoom/PasswordRow/RoomPasswordEdit
@onready var join_room_button: Button = $Root/RoomSection/JoinRoom/JoinRoomButton

@onready var leave_room_button: Button = $Root/RoomActionsRow/LeaveRoomButton
@onready var status_output: RichTextLabel = $Root/StatusOutput

func _ready() -> void:
	_bind_net_signals()
	_apply_defaults()
	_refresh_ui()

func _on_back_pressed() -> void:
	if NetClient != null:
		NetClient.shutdown()
	if SceneManager != null and SceneManager.has_method("go_back") and SceneManager.go_back():
		return
	if SceneManager != null and SceneManager.has_method("goto_main_menu"):
		SceneManager.goto_main_menu()

func _on_connect_pressed() -> void:
	if NetContext != null:
		NetContext.player_profile = {
			"name": str(player_name_edit.text).strip_edges(),
			"color_index": int(color_index_spin.value),
		}
	var url := str(server_url_edit.text).strip_edges()
	var r: Result = NetClient.connect_to_server(url)
	if not r.ok:
		_set_status("连接失败：%s" % r.error)
	_refresh_ui()

func _on_disconnect_pressed() -> void:
	if NetClient != null:
		NetClient.shutdown()
	_refresh_ui()

func _on_create_room_pressed() -> void:
	if NetClient == null or not NetClient.is_online_client_connected():
		_set_status("未连接到服务器")
		return
	var desired_player_count := int(create_player_count_spin.value)
	var room_password := str(create_password_edit.text)
	var request_id := NetClient.request_create_room(desired_player_count, room_password)
	_set_status("CreateRoom 已发送 request_id=%s" % request_id)

func _on_join_room_pressed() -> void:
	if NetClient == null or not NetClient.is_online_client_connected():
		_set_status("未连接到服务器")
		return
	var room_code := str(join_room_code_edit.text).strip_edges().to_upper()
	var room_password := str(join_password_edit.text)
	var request_id := NetClient.request_join_room(room_code, room_password)
	_set_status("JoinRoom 已发送 request_id=%s" % request_id)

func _on_leave_room_pressed() -> void:
	if NetClient == null or not NetClient.is_online_client_connected():
		_set_status("未连接到服务器")
		return
	var request_id := NetClient.request_leave_room()
	_set_status("LeaveRoom 已发送 request_id=%s" % request_id)

func _bind_net_signals() -> void:
	if NetClient == null:
		return
	if not NetClient.connected.is_connected(_on_net_connected):
		NetClient.connected.connect(_on_net_connected)
	if not NetClient.disconnected.is_connected(_on_net_disconnected):
		NetClient.disconnected.connect(_on_net_disconnected)
	if not NetClient.room_state_updated.is_connected(_on_room_state_updated):
		NetClient.room_state_updated.connect(_on_room_state_updated)
	if not NetClient.request_rejected.is_connected(_on_request_rejected):
		NetClient.request_rejected.connect(_on_request_rejected)

func _apply_defaults() -> void:
	if NetContext != null and not str(NetContext.server_url).is_empty():
		server_url_edit.text = str(NetContext.server_url)
	else:
		server_url_edit.text = "ws://127.0.0.1:7000"

	if NetContext != null and NetContext.player_profile is Dictionary and not Dictionary(NetContext.player_profile).is_empty():
		var p: Dictionary = Dictionary(NetContext.player_profile)
		player_name_edit.text = str(p.get("name", "玩家"))
		color_index_spin.value = int(p.get("color_index", 0))
	elif Globals != null:
		if Globals.player_names is Array and not Globals.player_names.is_empty():
			player_name_edit.text = str(Globals.player_names[0])
		if Globals.player_color_indices is Array and not Globals.player_color_indices.is_empty():
			color_index_spin.value = int(Globals.player_color_indices[0])

	create_player_count_spin.min_value = Globals.MIN_PLAYERS
	create_player_count_spin.max_value = Globals.MAX_PLAYERS
	create_player_count_spin.value = clampi(int(Globals.player_count), Globals.MIN_PLAYERS, Globals.MAX_PLAYERS)

func _refresh_ui() -> void:
	var connected := NetClient != null and NetClient.is_online_client_connected()
	connect_button.disabled = connected
	disconnect_button.disabled = not connected
	create_room_button.disabled = not connected
	join_room_button.disabled = not connected
	leave_room_button.disabled = not connected

	_render_room_state(NetContext.room_state if NetContext != null else {})

func _render_room_state(room_state: Dictionary) -> void:
	var s := ""
	var connected := NetClient != null and NetClient.is_online_client_connected()
	s += "连接状态：%s\n" % ("已连接" if connected else "未连接")

	var code := str(room_state.get("room_code", ""))
	if code.is_empty():
		s += "房间：-\n"
	else:
		s += "房间：%s\n" % code
		s += "房主 peer_id：%s\n" % str(room_state.get("host_peer_id", ""))
		var players: Array = Array(room_state.get("players", []))
		s += "玩家列表（%d）：\n" % players.size()
		for p in players:
			if p is Dictionary:
				var pd := Dictionary(p)
				s += "- seat=%d peer=%d name=%s color=%d\n" % [
					int(pd.get("seat_index", -1)),
					int(pd.get("peer_id", -1)),
					str(pd.get("name", "")),
					int(pd.get("color_index", 0)),
				]

	_set_status(s.strip_edges())

func _set_status(text: String) -> void:
	if status_output == null or not is_instance_valid(status_output):
		return
	status_output.text = text + "\n"

func _on_net_connected() -> void:
	_refresh_ui()

func _on_net_disconnected(_reason: String) -> void:
	_refresh_ui()

func _on_room_state_updated(_room_state: Dictionary) -> void:
	_refresh_ui()

func _on_request_rejected(request_id: String, code: String, message: String) -> void:
	_set_status("RequestRejected request_id=%s code=%s message=%s" % [request_id, code, message])
	_refresh_ui()
