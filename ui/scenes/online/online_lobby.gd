# 联机大厅（M5）：Connect/Rooms/Create/Room 分页 + 公开房间列表 + 配置自动同步 + 模块选择复用
extends Control

const RoomConfigEditorClass = preload("res://ui/components/room_config_editor/room_config_editor.gd")
const UiStylesClass = preload("res://ui/utils/ui_styles.gd")
const PasswordDialogClass = preload("res://ui/dialogs/password_dialog.gd")

@onready var panel: PanelContainer = $Center/Panel
@onready var tabs: TabContainer = $Center/Panel/Margin/Root/Tabs

@onready var server_url_edit: LineEdit = $Center/Panel/Margin/Root/Tabs/ConnectTab/ServerRow/ServerUrlEdit
@onready var player_name_edit: LineEdit = $Center/Panel/Margin/Root/Tabs/ConnectTab/ProfileRow/PlayerNameEdit
@onready var color_index_spin: SpinBox = $Center/Panel/Margin/Root/Tabs/ConnectTab/ProfileRow/ColorIndexSpin
@onready var connect_button: Button = $Center/Panel/Margin/Root/Tabs/ConnectTab/ButtonsRow/ConnectButton
@onready var disconnect_button: Button = $Center/Panel/Margin/Root/Tabs/ConnectTab/ButtonsRow/DisconnectButton
@onready var connect_status_label: Label = $Center/Panel/Margin/Root/Tabs/ConnectTab/ConnectStatus

@onready var refresh_rooms_button: Button = $Center/Panel/Margin/Root/Tabs/RoomsTab/RoomsHeader/RefreshRoomsButton
@onready var rooms_list_container: VBoxContainer = $Center/Panel/Margin/Root/Tabs/RoomsTab/RoomsScroll/RoomsList
@onready var join_by_code_room_code_edit: LineEdit = $Center/Panel/Margin/Root/Tabs/RoomsTab/JoinByCode/RoomCodeRow/RoomCodeEdit
@onready var join_by_code_password_edit: LineEdit = $Center/Panel/Margin/Root/Tabs/RoomsTab/JoinByCode/PasswordRow/RoomPasswordEdit
@onready var join_by_code_button: Button = $Center/Panel/Margin/Root/Tabs/RoomsTab/JoinByCode/JoinRoomButton
@onready var rooms_status_label: Label = $Center/Panel/Margin/Root/Tabs/RoomsTab/RoomsStatus

@onready var create_password_edit: LineEdit = $Center/Panel/Margin/Root/Tabs/CreateTab/CreatePasswordRow/CreateRoomPasswordEdit
@onready var create_config_container: VBoxContainer = $Center/Panel/Margin/Root/Tabs/CreateTab/CreateConfigContainer
@onready var create_room_button: Button = $Center/Panel/Margin/Root/Tabs/CreateTab/CreateRoomButton
@onready var create_status_label: Label = $Center/Panel/Margin/Root/Tabs/CreateTab/CreateStatus

@onready var room_code_label: Label = $Center/Panel/Margin/Root/Tabs/RoomTab/RoomHeader/RoomCodeLabel
@onready var copy_room_code_button: Button = $Center/Panel/Margin/Root/Tabs/RoomTab/RoomHeader/CopyRoomCodeButton
@onready var players_list_container: VBoxContainer = $Center/Panel/Margin/Root/Tabs/RoomTab/RoomBody/LeftColumn/PlayersList
@onready var spectators_list_container: VBoxContainer = $Center/Panel/Margin/Root/Tabs/RoomTab/RoomBody/LeftColumn/SpectatorsList
@onready var config_sync_status_label: Label = $Center/Panel/Margin/Root/Tabs/RoomTab/RoomBody/RightColumn/ConfigSyncStatus
@onready var room_config_container: VBoxContainer = $Center/Panel/Margin/Root/Tabs/RoomTab/RoomBody/RightColumn/RoomConfigContainer
@onready var leave_room_button: Button = $Center/Panel/Margin/Root/Tabs/RoomTab/RoomActionsRow/LeaveRoomButton
@onready var start_game_button: Button = $Center/Panel/Margin/Root/Tabs/RoomTab/RoomActionsRow/StartGameButton
@onready var room_status_label: Label = $Center/Panel/Margin/Root/Tabs/RoomTab/RoomStatus

@onready var config_debounce_timer: Timer = $ConfigDebounceTimer

var _tab_connect: int = 0
var _tab_rooms: int = 0
var _tab_create: int = 0
var _tab_room: int = 0

var _create_config_editor = null
var _room_config_editor = null

var _config_sync_state: String = "synced" # synced/dirty/syncing/error
var _config_sync_message: String = ""
var _pending_config_patch: Dictionary = {}

var _password_dialog = null
var _password_dialog_room_code: String = ""

func _ready() -> void:
	UiStylesClass.apply_dialog_surface(panel)
	UiStylesClass.apply_button_secondary($Center/Panel/Margin/Root/TopBar/BackButton)
	UiStylesClass.apply_button_primary(connect_button)
	UiStylesClass.apply_button_secondary(disconnect_button)
	UiStylesClass.apply_button_secondary(refresh_rooms_button)
	UiStylesClass.apply_button_primary(join_by_code_button)
	UiStylesClass.apply_button_primary(create_room_button)
	UiStylesClass.apply_button_secondary(copy_room_code_button)
	UiStylesClass.apply_button_secondary(leave_room_button)
	UiStylesClass.apply_button_primary(start_game_button)

	_bind_net_signals()
	_setup_tabs()
	_ensure_editors()
	_apply_defaults()
	_refresh_ui()

func _setup_tabs() -> void:
	if tabs == null or not is_instance_valid(tabs):
		return
	_tab_connect = tabs.get_tab_idx_from_control(tabs.get_node("ConnectTab") as Control)
	_tab_rooms = tabs.get_tab_idx_from_control(tabs.get_node("RoomsTab") as Control)
	_tab_create = tabs.get_tab_idx_from_control(tabs.get_node("CreateTab") as Control)
	_tab_room = tabs.get_tab_idx_from_control(tabs.get_node("RoomTab") as Control)

	tabs.set_tab_title(_tab_connect, "连接")
	tabs.set_tab_title(_tab_rooms, "房间")
	tabs.set_tab_title(_tab_create, "创建")
	tabs.set_tab_title(_tab_room, "房间内")

	if not tabs.tab_changed.is_connected(_on_tab_changed):
		tabs.tab_changed.connect(_on_tab_changed)

func _ensure_editors() -> void:
	if _create_config_editor == null or not is_instance_valid(_create_config_editor):
		_create_config_editor = RoomConfigEditorClass.new()
		create_config_container.add_child(_create_config_editor)

	if _room_config_editor == null or not is_instance_valid(_room_config_editor):
		_room_config_editor = RoomConfigEditorClass.new()
		room_config_container.add_child(_room_config_editor)
		_room_config_editor.changed.connect(_on_room_config_changed)
		_room_config_editor.validation_failed.connect(func(msg: String) -> void:
			_set_config_sync_state("error", msg)
		)

func _ensure_password_dialog() -> void:
	if _password_dialog != null and is_instance_valid(_password_dialog):
		return
	_password_dialog = PasswordDialogClass.new()
	add_child(_password_dialog)
	if _password_dialog.has_signal("submitted") and not _password_dialog.submitted.is_connected(_on_password_dialog_submitted):
		_password_dialog.submitted.connect(_on_password_dialog_submitted)

func _apply_defaults() -> void:
	_set_connect_status("")
	_set_rooms_status("")
	_set_create_status("")
	_set_room_status("")

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

	_set_config_sync_state("synced", "")

	# Create 默认配置：复用本地 Globals（seed 由 server 在创建后生成并广播）
	var cfg := {
		"desired_player_count": clampi(int(Globals.player_count), Globals.MIN_PLAYERS, Globals.MAX_PLAYERS),
		"seed_mode": "random",
		"seed": 0,
		"allow_spectators": true,
		"enabled_modules_v2": Array(Globals.enabled_modules_v2, TYPE_STRING, "", null),
		"modules_v2_base_dir": str(Globals.modules_v2_base_dir),
	}
	if _create_config_editor != null and is_instance_valid(_create_config_editor):
		_create_config_editor.set_from_room_config(cfg)

func _bind_net_signals() -> void:
	if NetClient == null:
		return
	if not NetClient.connected.is_connected(_on_net_connected):
		NetClient.connected.connect(_on_net_connected)
	if not NetClient.disconnected.is_connected(_on_net_disconnected):
		NetClient.disconnected.connect(_on_net_disconnected)
	if not NetClient.room_state_updated.is_connected(_on_room_state_updated):
		NetClient.room_state_updated.connect(_on_room_state_updated)
	if not NetClient.room_list_updated.is_connected(_on_room_list_updated):
		NetClient.room_list_updated.connect(_on_room_list_updated)
	if not NetClient.request_rejected.is_connected(_on_request_rejected):
		NetClient.request_rejected.connect(_on_request_rejected)
	if not NetClient.game_started.is_connected(_on_game_started):
		NetClient.game_started.connect(_on_game_started)

func _refresh_ui() -> void:
	var connected := NetClient != null and NetClient.is_online_client_connected()
	connect_button.disabled = connected
	disconnect_button.disabled = not connected
	refresh_rooms_button.disabled = not connected
	join_by_code_button.disabled = not connected
	create_room_button.disabled = not connected
	leave_room_button.disabled = not connected

	var in_room := _get_current_room_code().is_empty() == false
	if tabs != null and is_instance_valid(tabs):
		tabs.set_tab_disabled(_tab_rooms, not connected)
		tabs.set_tab_disabled(_tab_create, not connected)
		tabs.set_tab_disabled(_tab_room, not (connected and in_room))

	_render_room_list(NetContext.room_list if NetContext != null else [])
	_render_room_state(NetContext.room_state if NetContext != null else {})

func _render_room_list(rooms: Array) -> void:
	if rooms_list_container == null or not is_instance_valid(rooms_list_container):
		return

	for child in rooms_list_container.get_children():
		child.queue_free()

	var connected := NetClient != null and NetClient.is_online_client_connected()
	if not connected:
		return

	var current_code := _get_current_room_code()

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
		rooms_list_container.add_child(row)

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
				_select_tab(_tab_room)
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
			_join_room_from_list(code, password_required)
		)
		row.add_child(join_btn)

		var spectate_btn := Button.new()
		spectate_btn.text = "观战"
		spectate_btn.disabled = not can_spectate
		UiStylesClass.apply_button_secondary(spectate_btn)
		spectate_btn.pressed.connect(func() -> void:
			_join_room_from_list(code, password_required)
		)
		row.add_child(spectate_btn)

func _join_room_from_list(room_code: String, password_required: bool) -> void:
	if NetClient == null or not NetClient.is_online_client_connected():
		_set_rooms_status("未连接到服务器")
		return
	var code := str(room_code).strip_edges().to_upper()
	if code.is_empty():
		return
	if password_required:
		_prompt_password_and_join(code)
		return
	var request_id := NetClient.request_join_room(code, "")
	_set_rooms_status("JoinRoom 已发送 request_id=%s" % request_id)

func _prompt_password_and_join(room_code: String) -> void:
	_ensure_password_dialog()
	_password_dialog_room_code = room_code
	if _password_dialog != null and is_instance_valid(_password_dialog) and _password_dialog.has_method("open_for_room"):
		_password_dialog.call("open_for_room", room_code, "加入/观战")

func _on_password_dialog_submitted(password: String) -> void:
	if NetClient == null or not NetClient.is_online_client_connected():
		return
	var code := str(_password_dialog_room_code).strip_edges().to_upper()
	if code.is_empty():
		return
	var request_id := NetClient.request_join_room(code, str(password))
	_set_rooms_status("JoinRoom 已发送 request_id=%s" % request_id)

func _render_room_state(room_state: Dictionary) -> void:
	var connected := NetClient != null and NetClient.is_online_client_connected()
	if not connected:
		room_code_label.text = "房间：-"
		return

	var code := str(room_state.get("room_code", "")).strip_edges()
	if code.is_empty():
		room_code_label.text = "房间：-"
	else:
		room_code_label.text = "房间：%s" % code

	# 玩家列表
	for child in players_list_container.get_children():
		child.queue_free()
	for child2 in spectators_list_container.get_children():
		child2.queue_free()

	var players: Array = Array(room_state.get("players", []))
	for p_val in players:
		if not (p_val is Dictionary):
			continue
		var p: Dictionary = Dictionary(p_val)
		var seat := int(p.get("seat_index", -1))
		var name := str(p.get("name", ""))
		var color := int(p.get("color_index", 0))
		var connected_flag := bool(p.get("connected", true))
		var forfeited := bool(p.get("forfeited", false))

		var line := Label.new()
		line.autowrap_mode = TextServer.AUTOWRAP_WORD
		line.text = "seat=%d  %s  color=%d  %s%s" % [
			seat,
			name,
			color,
			("在线" if connected_flag else "掉线"),
			("  (弃权)" if forfeited else ""),
		]
		players_list_container.add_child(line)

	var spectators: Array = Array(room_state.get("spectators", []))
	for s_val in spectators:
		if not (s_val is Dictionary):
			continue
		var s: Dictionary = Dictionary(s_val)
		var line2 := Label.new()
		line2.autowrap_mode = TextServer.AUTOWRAP_WORD
		line2.text = "%s" % str(s.get("name", ""))
		spectators_list_container.add_child(line2)

	# Room 配置：host 自动同步 / 非 host 只读
	var cfg: Dictionary = Dictionary(room_state.get("config", {}))
	var in_room := not code.is_empty()
	var is_host := in_room and _is_host(room_state)
	if not is_host and _config_sync_state != "synced":
		_set_config_sync_state("synced", "")
	if _room_config_editor != null and is_instance_valid(_room_config_editor):
		var editable := is_host and str(room_state.get("status", "")) == "Lobby"
		if not is_host or _config_sync_state == "synced" or _config_sync_state == "syncing":
			_room_config_editor.set_from_room_config(cfg)
			if is_host and _config_sync_state == "syncing":
				_pending_config_patch = {}
				_set_config_sync_state("synced", "")
		_room_config_editor.set_editable(editable)

	# StartGame 按钮
	start_game_button.disabled = not (connected and _can_start_game(room_state) and _config_sync_state == "synced")

	if in_room and tabs != null and is_instance_valid(tabs) and tabs.current_tab != _tab_room:
		_select_tab(_tab_room)

func _is_host(room_state: Dictionary) -> bool:
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

func _select_tab(idx: int) -> void:
	if tabs == null or not is_instance_valid(tabs):
		return
	tabs.current_tab = idx

func _set_connect_status(text: String) -> void:
	connect_status_label.text = str(text).strip_edges()

func _set_rooms_status(text: String) -> void:
	rooms_status_label.text = str(text).strip_edges()

func _set_create_status(text: String) -> void:
	create_status_label.text = str(text).strip_edges()

func _set_room_status(text: String) -> void:
	room_status_label.text = str(text).strip_edges()

func _set_config_sync_state(state: String, message: String) -> void:
	_config_sync_state = str(state)
	_config_sync_message = str(message).strip_edges()
	var s := ""
	match _config_sync_state:
		"synced":
			s = "配置：已同步"
		"dirty":
			s = "配置：待同步..."
		"syncing":
			s = "配置：同步中..."
		"error":
			s = "配置：错误 - %s" % _config_sync_message
		_:
			s = "配置：%s" % _config_sync_state
	config_sync_status_label.text = s

func _get_current_room_code() -> String:
	if NetContext == null:
		return ""
	return str(NetContext.room_state.get("room_code", "")).strip_edges().to_upper()

func _on_tab_changed(idx: int) -> void:
	if idx == _tab_rooms and NetClient != null and NetClient.is_online_client_connected():
		NetClient.request_list_rooms()

func _on_net_connected() -> void:
	_set_connect_status("已连接")
	_refresh_ui()
	if NetClient != null:
		NetClient.request_list_rooms()

func _on_net_disconnected(reason: String) -> void:
	_set_connect_status("已断开：%s" % reason)
	_set_rooms_status("")
	_set_create_status("")
	_set_room_status("")
	_set_config_sync_state("synced", "")
	_refresh_ui()

func _on_room_list_updated(_rooms: Array) -> void:
	_refresh_ui()

func _on_room_state_updated(_room_state: Dictionary) -> void:
	_refresh_ui()

func _on_request_rejected(request_id: String, code: String, message: String) -> void:
	var s := "RequestRejected request_id=%s code=%s message=%s" % [request_id, code, message]
	_set_room_status(s)
	if code.begins_with("create_room"):
		_set_create_status(s)
	elif code.begins_with("join_room") or code.begins_with("list_rooms"):
		_set_rooms_status(s)
	elif code.begins_with("update_config"):
		_set_config_sync_state("error", message)
	_refresh_ui()

func _on_game_started(_payload: Dictionary) -> void:
	if SceneManager != null and SceneManager.has_method("show_loading"):
		SceneManager.show_loading("正在进入联机对局...")
		await get_tree().process_frame
	SceneManager.goto_game()

func _on_room_config_changed() -> void:
	var room_state: Dictionary = NetContext.room_state if NetContext != null else {}
	if not _is_host(room_state):
		return
	if str(room_state.get("status", "")).strip_edges() != "Lobby":
		return
	if _room_config_editor == null or not is_instance_valid(_room_config_editor):
		return

	var vr: Result = _room_config_editor.validate()
	if not vr.ok:
		_set_config_sync_state("error", vr.error)
		return

	_pending_config_patch = _room_config_editor.get_config_patch()
	_set_config_sync_state("dirty", "")
	config_debounce_timer.start()

func _on_config_debounce_timeout() -> void:
	var room_state: Dictionary = NetContext.room_state if NetContext != null else {}
	if not _is_host(room_state):
		return
	if str(room_state.get("status", "")).strip_edges() != "Lobby":
		return
	if _pending_config_patch.is_empty():
		return
	if NetClient == null or not NetClient.is_online_client_connected():
		return

	_set_config_sync_state("syncing", "")
	var request_id := NetClient.request_update_room_config(_pending_config_patch)
	_set_room_status("UpdateRoomConfig 已发送 request_id=%s" % request_id)

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
		_set_connect_status("连接失败：%s" % r.error)
	_refresh_ui()

func _on_disconnect_pressed() -> void:
	if NetClient != null:
		NetClient.shutdown()
	_refresh_ui()

func _on_refresh_rooms_pressed() -> void:
	if NetClient == null or not NetClient.is_online_client_connected():
		_set_rooms_status("未连接到服务器")
		return
	var request_id := NetClient.request_list_rooms()
	_set_rooms_status("ListRooms 已发送 request_id=%s" % request_id)

func _on_join_by_code_pressed() -> void:
	if NetClient == null or not NetClient.is_online_client_connected():
		_set_rooms_status("未连接到服务器")
		return
	var room_code := str(join_by_code_room_code_edit.text).strip_edges().to_upper()
	var room_password := str(join_by_code_password_edit.text)
	var request_id := NetClient.request_join_room(room_code, room_password)
	_set_rooms_status("JoinRoom 已发送 request_id=%s" % request_id)

func _on_create_room_pressed() -> void:
	if NetClient == null or not NetClient.is_online_client_connected():
		_set_create_status("未连接到服务器")
		return
	if _create_config_editor == null or not is_instance_valid(_create_config_editor):
		_set_create_status("配置编辑器缺失")
		return

	var vr: Result = _create_config_editor.validate()
	if not vr.ok:
		_set_create_status("配置无效：%s" % vr.error)
		return

	var cfg: Dictionary = _create_config_editor.get_config_patch()
	var desired := int(cfg.get("desired_player_count", Globals.MIN_PLAYERS))
	cfg.erase("desired_player_count")

	var room_password := str(create_password_edit.text)
	var request_id := NetClient.request_create_room(desired, room_password, cfg)
	_set_create_status("CreateRoom 已发送 request_id=%s" % request_id)

func _on_leave_room_pressed() -> void:
	if NetClient == null or not NetClient.is_online_client_connected():
		_set_room_status("未连接到服务器")
		return
	config_debounce_timer.stop()
	_pending_config_patch = {}
	_set_config_sync_state("synced", "")
	var request_id := NetClient.request_leave_room()
	_set_room_status("LeaveRoom 已发送 request_id=%s" % request_id)

func _on_start_game_pressed() -> void:
	if NetClient == null or not NetClient.is_online_client_connected():
		_set_room_status("未连接到服务器")
		return
	var room_state: Dictionary = NetContext.room_state if NetContext != null else {}
	if not _is_host(room_state):
		_set_room_status("仅房主可开始游戏")
		return
	if _config_sync_state != "synced":
		_set_room_status("配置未同步，无法开始")
		return
	var request_id := NetClient.request_start_game()
	_set_room_status("StartGame 已发送 request_id=%s" % request_id)

func _on_copy_room_code_pressed() -> void:
	var code := _get_current_room_code()
	if code.is_empty():
		return
	DisplayServer.clipboard_set(code)
	_set_room_status("已复制房间码：%s" % code)
