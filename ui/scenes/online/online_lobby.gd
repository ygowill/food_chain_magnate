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

@onready var config_player_count_spin: SpinBox = $Root/RoomConfigSection/ConfigPlayerCountRow/ConfigPlayerCountSpin
@onready var seed_mode_option: OptionButton = $Root/RoomConfigSection/SeedModeRow/SeedModeOption
@onready var seed_value_spin: SpinBox = $Root/RoomConfigSection/SeedModeRow/SeedValueSpin
@onready var modules_base_dir_edit: LineEdit = $Root/RoomConfigSection/ModulesBaseDirRow/ModulesBaseDirEdit
@onready var enabled_modules_edit: TextEdit = $Root/RoomConfigSection/EnabledModulesRow/EnabledModulesEdit
@onready var update_config_button: Button = $Root/RoomConfigSection/UpdateConfigButton

@onready var leave_room_button: Button = $Root/RoomActionsRow/LeaveRoomButton
@onready var start_game_button: Button = $Root/RoomActionsRow/StartGameButton
@onready var status_output: RichTextLabel = $Root/StatusOutput

func _ready() -> void:
	_bind_net_signals()
	_apply_defaults()
	_setup_seed_mode_option()
	_bind_local_signals()
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
	var desired_player_count := int(config_player_count_spin.value)
	var room_password := str(create_password_edit.text)
	var seed_mode := _get_seed_mode_value()
	var enabled_modules := _parse_enabled_modules_text()
	var config := {
		"seed_mode": seed_mode,
		"seed": int(seed_value_spin.value),
		"enabled_modules_v2": enabled_modules,
		"modules_v2_base_dir": str(modules_base_dir_edit.text).strip_edges(),
	}
	var request_id := NetClient.request_create_room(desired_player_count, room_password, config)
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

func _on_start_game_pressed() -> void:
	if NetClient == null or not NetClient.is_online_client_connected():
		_set_status("未连接到服务器")
		return
	var room_state: Dictionary = NetContext.room_state if NetContext != null else {}
	if not _is_host(room_state):
		_set_status("仅房主可开始游戏")
		return
	var request_id := NetClient.request_start_game()
	_set_status("StartGame 已发送 request_id=%s" % request_id)

func _on_update_config_pressed() -> void:
	if NetClient == null or not NetClient.is_online_client_connected():
		_set_status("未连接到服务器")
		return
	var room_state: Dictionary = NetContext.room_state if NetContext != null else {}
	if str(room_state.get("room_code", "")).is_empty():
		_set_status("未在房间中")
		return
	if not _is_host(room_state):
		_set_status("仅房主可同步配置")
		return

	var seed_mode := _get_seed_mode_value()
	var enabled_modules := _parse_enabled_modules_text()
	var patch := {
		"desired_player_count": int(config_player_count_spin.value),
		"seed_mode": seed_mode,
		"seed": int(seed_value_spin.value),
		"enabled_modules_v2": enabled_modules,
		"modules_v2_base_dir": str(modules_base_dir_edit.text).strip_edges(),
	}
	var request_id := NetClient.request_update_room_config(patch)
	_set_status("UpdateRoomConfig 已发送 request_id=%s" % request_id)

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
	if not NetClient.game_started.is_connected(_on_game_started):
		NetClient.game_started.connect(_on_game_started)

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
	config_player_count_spin.min_value = Globals.MIN_PLAYERS
	config_player_count_spin.max_value = Globals.MAX_PLAYERS
	config_player_count_spin.value = clampi(int(Globals.player_count), Globals.MIN_PLAYERS, Globals.MAX_PLAYERS)

	seed_value_spin.value = maxi(0, int(Globals.random_seed))
	modules_base_dir_edit.text = str(Globals.modules_v2_base_dir)
	enabled_modules_edit.text = "\n".join(Array(Globals.enabled_modules_v2, TYPE_STRING, "", null)) + "\n"

func _setup_seed_mode_option() -> void:
	if seed_mode_option == null or not is_instance_valid(seed_mode_option):
		return
	seed_mode_option.clear()
	seed_mode_option.add_item("随机", 0)
	seed_mode_option.set_item_metadata(0, "random")
	seed_mode_option.add_item("固定", 1)
	seed_mode_option.set_item_metadata(1, "fixed")
	seed_mode_option.select(0)

func _bind_local_signals() -> void:
	if is_instance_valid(create_player_count_spin) and not create_player_count_spin.value_changed.is_connected(_on_create_player_count_changed):
		create_player_count_spin.value_changed.connect(_on_create_player_count_changed)
	if is_instance_valid(config_player_count_spin) and not config_player_count_spin.value_changed.is_connected(_on_config_player_count_changed):
		config_player_count_spin.value_changed.connect(_on_config_player_count_changed)
	if is_instance_valid(seed_mode_option) and not seed_mode_option.item_selected.is_connected(_on_seed_mode_changed):
		seed_mode_option.item_selected.connect(_on_seed_mode_changed)

func _on_create_player_count_changed(v: float) -> void:
	if not is_instance_valid(config_player_count_spin):
		return
	if int(config_player_count_spin.value) == int(v):
		return
	config_player_count_spin.value = v

func _on_config_player_count_changed(v: float) -> void:
	if not is_instance_valid(create_player_count_spin):
		return
	if int(create_player_count_spin.value) == int(v):
		return
	create_player_count_spin.value = v

func _on_seed_mode_changed(_index: int) -> void:
	_refresh_ui()

func _refresh_ui() -> void:
	var connected := NetClient != null and NetClient.is_online_client_connected()
	connect_button.disabled = connected
	disconnect_button.disabled = not connected
	create_room_button.disabled = not connected
	join_room_button.disabled = not connected
	leave_room_button.disabled = not connected

	var room_state: Dictionary = NetContext.room_state if NetContext != null else {}
	_sync_config_fields_from_room_state(room_state)
	_apply_config_editability(room_state, connected)
	_render_room_state(room_state)

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
		var cfg: Dictionary = Dictionary(room_state.get("config", {}))
		var desired := int(cfg.get("desired_player_count", 0))
		if desired > 0:
			s += "配置：player_count=%d\n" % desired
		var seed_mode := str(cfg.get("seed_mode", ""))
		var seed := int(cfg.get("seed", 0))
		if not seed_mode.is_empty():
			s += "配置：seed_mode=%s seed=%d\n" % [seed_mode, seed]
		var base_dir := str(cfg.get("modules_v2_base_dir", ""))
		if not base_dir.is_empty():
			s += "配置：modules_dir=%s\n" % base_dir
		var mods_val = cfg.get("enabled_modules_v2", null)
		if mods_val is Array:
			s += "配置：enabled_modules_v2=%d\n" % Array(mods_val).size()

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

func _sync_config_fields_from_room_state(room_state: Dictionary) -> void:
	if not (room_state is Dictionary):
		return
	if str(room_state.get("room_code", "")).is_empty():
		return
	var cfg_val = room_state.get("config", null)
	if not (cfg_val is Dictionary):
		return
	var cfg: Dictionary = Dictionary(cfg_val)

	if cfg.has("desired_player_count"):
		var v = cfg.get("desired_player_count", null)
		if v is int or v is float:
			var n := int(v)
			if is_instance_valid(config_player_count_spin):
				config_player_count_spin.value = n
			if is_instance_valid(create_player_count_spin):
				create_player_count_spin.value = n

	var seed_mode := str(cfg.get("seed_mode", "")).strip_edges()
	if seed_mode.is_empty():
		seed_mode = "random"
	var seed := int(cfg.get("seed", 0))
	if is_instance_valid(seed_value_spin):
		seed_value_spin.value = seed
	_select_seed_mode_value(seed_mode)

	var base_dir := str(cfg.get("modules_v2_base_dir", "")).strip_edges()
	if not base_dir.is_empty() and is_instance_valid(modules_base_dir_edit):
		modules_base_dir_edit.text = base_dir

	var mods_val = cfg.get("enabled_modules_v2", null)
	if mods_val is Array and is_instance_valid(enabled_modules_edit):
		var mods: Array[String] = []
		for it in Array(mods_val):
			var s := str(it).strip_edges()
			if s.is_empty():
				continue
			mods.append(s)
		enabled_modules_edit.text = "\n".join(mods) + "\n"

func _apply_config_editability(room_state: Dictionary, connected: bool) -> void:
	var in_room := str(room_state.get("room_code", "")).is_empty() == false
	var is_host := in_room and _is_host(room_state)
	if is_instance_valid(update_config_button):
		update_config_button.disabled = not (connected and in_room and is_host)

	var editable := connected and in_room and is_host
	if is_instance_valid(seed_mode_option):
		seed_mode_option.disabled = not editable
	if is_instance_valid(modules_base_dir_edit):
		modules_base_dir_edit.editable = editable
	if is_instance_valid(enabled_modules_edit):
		enabled_modules_edit.editable = editable
	if is_instance_valid(start_game_button):
		start_game_button.disabled = not (connected and _can_start_game(room_state))

func _is_host(room_state: Dictionary) -> bool:
	if not (room_state is Dictionary):
		return false
	var host_peer_id := int(room_state.get("host_peer_id", 0))
	if host_peer_id <= 0:
		return false
	return int(multiplayer.get_unique_id()) == host_peer_id

func _can_start_game(room_state: Dictionary) -> bool:
	if not _is_host(room_state):
		return false
	if str(room_state.get("status", "")).strip_edges() != "Lobby":
		return false
	var cfg: Dictionary = Dictionary(room_state.get("config", {}))
	var desired := int(cfg.get("desired_player_count", 0))
	if desired <= 0:
		return false
	var players: Array = Array(room_state.get("players", []))
	return players.size() == desired

func _get_seed_mode_value() -> String:
	if seed_mode_option == null or not is_instance_valid(seed_mode_option):
		return "random"
	var idx := seed_mode_option.selected
	var meta = seed_mode_option.get_item_metadata(idx)
	var v := str(meta).strip_edges()
	if v.is_empty():
		return "random"
	return v

func _select_seed_mode_value(value: String) -> void:
	if seed_mode_option == null or not is_instance_valid(seed_mode_option):
		return
	for i in range(seed_mode_option.item_count):
		var meta = seed_mode_option.get_item_metadata(i)
		if str(meta) == value:
			seed_mode_option.select(i)
			return

func _parse_enabled_modules_text() -> Array[String]:
	var out: Array[String] = []
	if enabled_modules_edit == null or not is_instance_valid(enabled_modules_edit):
		return out
	var text := str(enabled_modules_edit.text)
	for raw_line in text.split("\n"):
		var line := str(raw_line).strip_edges()
		if line.is_empty():
			continue
		out.append(line)
	return out

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

func _on_game_started(_payload: Dictionary) -> void:
	if SceneManager != null and SceneManager.has_method("show_loading"):
		SceneManager.show_loading("正在进入联机对局...")
		await get_tree().process_frame
	SceneManager.goto_game()
