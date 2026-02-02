# 联机大厅（M5）：Connect/Rooms/Create/Room 页面导航 + 公开房间列表 + 配置自动同步 + 模块选择复用
extends Control

const RoomConfigEditorClass = preload("res://ui/components/room_config_editor/room_config_editor.gd")
const UiStylesClass = preload("res://ui/utils/ui_styles.gd")
const PasswordDialogClass = preload("res://ui/dialogs/password_dialog.gd")
const InfoDialogClass = preload("res://ui/dialogs/info_dialog.gd")
const RoomListControllerClass = preload("res://ui/scenes/online/online_lobby_room_list_controller.gd")
const RoomStateRendererClass = preload("res://ui/scenes/online/online_lobby_room_state_renderer.gd")

const _COLOR_NAME_HINTS: Array[String] = ["红", "蓝", "绿", "黄", "紫"]

@onready var panel: PanelContainer = $Center/Panel
@onready var back_button: Button = $Center/Panel/Margin/Root/TopBar/BackButton
@onready var top_title_label: Label = $Center/Panel/Margin/Root/TopBar/Title
@onready var pages: VBoxContainer = $Center/Panel/Margin/Root/Tabs
@onready var page_connect: Control = $Center/Panel/Margin/Root/Tabs/ConnectTab
@onready var page_rooms: Control = $Center/Panel/Margin/Root/Tabs/RoomsTab
@onready var page_join_by_code: Control = $Center/Panel/Margin/Root/Tabs/JoinByCodeTab
@onready var page_create: Control = $Center/Panel/Margin/Root/Tabs/CreateTab
@onready var page_room: Control = $Center/Panel/Margin/Root/Tabs/RoomTab

@onready var server_url_edit: LineEdit = $Center/Panel/Margin/Root/Tabs/ConnectTab/ServerRow/ServerUrlEdit
@onready var player_name_edit: LineEdit = $Center/Panel/Margin/Root/Tabs/ConnectTab/ProfileRow/PlayerNameEdit
@onready var connect_button: Button = $Center/Panel/Margin/Root/Tabs/ConnectTab/ButtonsRow/ConnectButton
@onready var disconnect_button: Button = $Center/Panel/Margin/Root/Tabs/ConnectTab/ButtonsRow/DisconnectButton
@onready var connect_status_label: Label = $Center/Panel/Margin/Root/Tabs/ConnectTab/ConnectStatus

@onready var open_create_button: Button = $Center/Panel/Margin/Root/Tabs/RoomsTab/RoomsHeader/OpenCreateButton
@onready var open_join_by_code_button: Button = $Center/Panel/Margin/Root/Tabs/RoomsTab/RoomsHeader/OpenJoinByCodeButton
@onready var refresh_rooms_button: Button = $Center/Panel/Margin/Root/Tabs/RoomsTab/RoomsHeader/RefreshRoomsButton
@onready var rooms_list_container: VBoxContainer = $Center/Panel/Margin/Root/Tabs/RoomsTab/RoomsScroll/RoomsList
@onready var rooms_status_label: Label = $Center/Panel/Margin/Root/Tabs/RoomsTab/RoomsStatus

@onready var join_by_code_back_button: Button = $Center/Panel/Margin/Root/Tabs/JoinByCodeTab/JoinHeaderRow/BackToRoomsButton
@onready var join_by_code_room_code_edit: LineEdit = $Center/Panel/Margin/Root/Tabs/JoinByCodeTab/RoomCodeRow/RoomCodeEdit
@onready var join_by_code_password_edit: LineEdit = $Center/Panel/Margin/Root/Tabs/JoinByCodeTab/PasswordRow/RoomPasswordEdit
@onready var join_by_code_submit_button: Button = $Center/Panel/Margin/Root/Tabs/JoinByCodeTab/JoinRoomButton
@onready var join_by_code_status_label: Label = $Center/Panel/Margin/Root/Tabs/JoinByCodeTab/JoinStatus

@onready var back_to_rooms_button: Button = $Center/Panel/Margin/Root/Tabs/CreateTab/CreateHeaderRow/BackToRoomsButton
@onready var create_password_edit: LineEdit = $Center/Panel/Margin/Root/Tabs/CreateTab/CreatePasswordRow/CreateRoomPasswordEdit
@onready var create_players_spin: SpinBox = $Center/Panel/Margin/Root/Tabs/CreateTab/CreatePlayersRow/CreatePlayersSpin
@onready var create_room_button: Button = $Center/Panel/Margin/Root/Tabs/CreateTab/CreateRoomButton
@onready var create_status_label: Label = $Center/Panel/Margin/Root/Tabs/CreateTab/CreateStatus

@onready var room_code_label: Label = $Center/Panel/Margin/Root/Tabs/RoomTab/RoomHeader/RoomCodeLabel
@onready var copy_room_code_button: Button = $Center/Panel/Margin/Root/Tabs/RoomTab/RoomHeader/CopyRoomCodeButton
@onready var my_color_option: OptionButton = $Center/Panel/Margin/Root/Tabs/RoomTab/RoomBody/LeftColumn/MyColorRow/MyColorOption
@onready var players_list_container: VBoxContainer = $Center/Panel/Margin/Root/Tabs/RoomTab/RoomBody/LeftColumn/PlayersList
@onready var spectators_list_container: VBoxContainer = $Center/Panel/Margin/Root/Tabs/RoomTab/RoomBody/LeftColumn/SpectatorsList
@onready var config_sync_status_label: Label = $Center/Panel/Margin/Root/Tabs/RoomTab/RoomBody/RightColumn/ConfigSyncStatus
@onready var room_config_container: VBoxContainer = $Center/Panel/Margin/Root/Tabs/RoomTab/RoomBody/RightColumn/RoomConfigContainer
@onready var leave_room_button: Button = $Center/Panel/Margin/Root/Tabs/RoomTab/RoomActionsRow/LeaveRoomButton
@onready var start_game_button: Button = $Center/Panel/Margin/Root/Tabs/RoomTab/RoomActionsRow/StartGameButton
@onready var room_status_label: Label = $Center/Panel/Margin/Root/Tabs/RoomTab/RoomStatus

@onready var config_debounce_timer: Timer = $ConfigDebounceTimer

enum LobbyPage { CONNECT, ROOMS, JOIN_BY_CODE, CREATE, ROOM }
var _current_page: int = LobbyPage.CONNECT

var _room_config_editor = null
var _room_list_controller = null
var _room_state_renderer = null

var _config_sync_state: String = "synced" # synced/dirty/syncing/error
var _config_sync_message: String = ""
var _pending_config_patch: Dictionary = {}
var _start_game_request_id: String = ""
var _start_game_flow_in_progress: bool = false

var _password_dialog = null
var _password_dialog_room_code: String = ""
var _info_dialog = null
var _suppress_profile_signals: bool = false

func _ready() -> void:
	UiStylesClass.apply_dialog_surface(panel)
	UiStylesClass.apply_button_secondary(back_button)
	UiStylesClass.apply_button_primary(connect_button)
	UiStylesClass.apply_button_secondary(disconnect_button)
	UiStylesClass.apply_button_primary(open_create_button)
	UiStylesClass.apply_button_secondary(open_join_by_code_button)
	UiStylesClass.apply_button_secondary(refresh_rooms_button)
	UiStylesClass.apply_button_secondary(join_by_code_back_button)
	UiStylesClass.apply_button_primary(join_by_code_submit_button)
	UiStylesClass.apply_button_secondary(back_to_rooms_button)
	UiStylesClass.apply_button_primary(create_room_button)
	UiStylesClass.apply_button_secondary(copy_room_code_button)
	UiStylesClass.apply_button_secondary(leave_room_button)
	UiStylesClass.apply_button_primary(start_game_button)

	_bind_net_signals()
	_ensure_editors()
	_ensure_password_dialog()
	_ensure_info_dialog()
	_ensure_room_renderers()
	_setup_my_color_selector()
	_apply_defaults()
	_refresh_ui()

func _setup_my_color_selector() -> void:
	if my_color_option == null or not is_instance_valid(my_color_option):
		return
	if my_color_option.item_selected.is_connected(_on_my_color_option_selected):
		return
	my_color_option.clear()
	var palette_size := 0
	if Globals != null and (Globals.PLAYER_COLOR_PALETTE is Array):
		palette_size = Array(Globals.PLAYER_COLOR_PALETTE).size()
	if palette_size <= 0:
		palette_size = _COLOR_NAME_HINTS.size()
	for i in range(palette_size):
		var label := _COLOR_NAME_HINTS[i] if i < _COLOR_NAME_HINTS.size() else ("颜色 %d" % i)
		my_color_option.add_item(label, i)
		my_color_option.set_item_metadata(i, i)
	my_color_option.item_selected.connect(_on_my_color_option_selected)

func _ensure_editors() -> void:
	if _room_config_editor == null or not is_instance_valid(_room_config_editor):
		_room_config_editor = RoomConfigEditorClass.new()
		room_config_container.add_child(_room_config_editor)
		_room_config_editor.changed.connect(_on_room_config_changed)
		_room_config_editor.validation_failed.connect(func(msg: String) -> void:
			_set_config_sync_state("error", msg)
		)

func _ensure_room_renderers() -> void:
	if _room_list_controller == null or not is_instance_valid(_room_list_controller):
		_room_list_controller = RoomListControllerClass.new()
		_room_list_controller.setup(self)
	if _room_state_renderer == null or not is_instance_valid(_room_state_renderer):
		_room_state_renderer = RoomStateRendererClass.new()
		_room_state_renderer.setup(self)

func _ensure_password_dialog() -> void:
	if _password_dialog != null and is_instance_valid(_password_dialog):
		return
	_password_dialog = PasswordDialogClass.new()
	add_child(_password_dialog)
	if _password_dialog.has_signal("submitted") and not _password_dialog.submitted.is_connected(_on_password_dialog_submitted):
		_password_dialog.submitted.connect(_on_password_dialog_submitted)

func _ensure_info_dialog() -> void:
	if _info_dialog != null and is_instance_valid(_info_dialog):
		return
	_info_dialog = InfoDialogClass.new()
	add_child(_info_dialog)

func _show_error_dialog(title_text: String, message: String) -> void:
	if OS.has_feature("headless"):
		return
	_ensure_info_dialog()
	if _info_dialog == null or not is_instance_valid(_info_dialog):
		return
	if _info_dialog.has_method("show_info"):
		_info_dialog.call("show_info", title_text, message, Vector2i(520, 320), "确定")

func _apply_defaults() -> void:
	_set_connect_status("")
	_set_rooms_status("")
	_set_join_by_code_status("")
	_set_create_status("")
	_set_room_status("")

	if NetContext != null and not str(NetContext.server_url).is_empty():
		server_url_edit.text = str(NetContext.server_url)
	else:
		server_url_edit.text = "ws://127.0.0.1:7000"

	var profile_name := "玩家"
	var profile_color_index := 0
	if NetContext != null and NetContext.player_profile is Dictionary and not Dictionary(NetContext.player_profile).is_empty():
		var p: Dictionary = Dictionary(NetContext.player_profile)
		profile_name = str(p.get("name", "玩家"))
		profile_color_index = int(p.get("color_index", 0))
	elif Globals != null:
		if Globals.player_names is Array and not Globals.player_names.is_empty():
			profile_name = str(Globals.player_names[0])
		if Globals.player_color_indices is Array and not Globals.player_color_indices.is_empty():
			profile_color_index = int(Globals.player_color_indices[0])

	player_name_edit.text = profile_name
	_write_local_player_profile(profile_name, profile_color_index)
	_apply_my_color_option_selection(profile_color_index)

	_set_config_sync_state("synced", "")

	if create_players_spin != null and is_instance_valid(create_players_spin):
		create_players_spin.min_value = float(Globals.MIN_PLAYERS)
		create_players_spin.max_value = float(Globals.MAX_PLAYERS)
		create_players_spin.value = float(clampi(int(Globals.player_count), Globals.MIN_PLAYERS, Globals.MAX_PLAYERS))

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

func _show_page(page: int, request_rooms_on_entry: bool = true) -> void:
	var prev := _current_page
	_current_page = page

	if is_instance_valid(page_connect):
		page_connect.visible = page == LobbyPage.CONNECT
	if is_instance_valid(page_rooms):
		page_rooms.visible = page == LobbyPage.ROOMS
	if is_instance_valid(page_join_by_code):
		page_join_by_code.visible = page == LobbyPage.JOIN_BY_CODE
	if is_instance_valid(page_create):
		page_create.visible = page == LobbyPage.CREATE
	if is_instance_valid(page_room):
		page_room.visible = page == LobbyPage.ROOM

	_update_top_title()

	if request_rooms_on_entry and page == LobbyPage.ROOMS and page != prev:
		if NetClient != null and NetClient.is_online_client_connected():
			NetClient.request_list_rooms()

func _sync_page_from_state() -> void:
	var connected := NetClient != null and NetClient.is_online_client_connected()
	var in_room := not _get_current_room_code().is_empty()

	if not connected:
		_show_page(LobbyPage.CONNECT, false)
		return

	if in_room:
		_show_page(LobbyPage.ROOM, false)
		return

	if _current_page == LobbyPage.JOIN_BY_CODE:
		_show_page(LobbyPage.JOIN_BY_CODE, false)
		return

	if _current_page == LobbyPage.CREATE:
		_show_page(LobbyPage.CREATE, false)
		return

	_show_page(LobbyPage.ROOMS, true)

func _update_top_title() -> void:
	if top_title_label == null or not is_instance_valid(top_title_label):
		return
	match _current_page:
		LobbyPage.CONNECT:
			top_title_label.text = "连接服务器"
		LobbyPage.ROOMS:
			top_title_label.text = "房间列表"
		LobbyPage.JOIN_BY_CODE:
			top_title_label.text = "房间码加入"
		LobbyPage.CREATE:
			top_title_label.text = "创建房间"
		LobbyPage.ROOM:
			top_title_label.text = "房间内"

func _refresh_ui() -> void:
	_ensure_room_renderers()
	var connected := NetClient != null and NetClient.is_online_client_connected()
	connect_button.disabled = connected
	disconnect_button.disabled = not connected
	open_create_button.disabled = not connected
	open_join_by_code_button.disabled = not connected
	refresh_rooms_button.disabled = not connected
	join_by_code_back_button.disabled = not connected
	join_by_code_submit_button.disabled = not connected
	back_to_rooms_button.disabled = not connected
	create_room_button.disabled = not connected
	leave_room_button.disabled = not connected
	if not connected:
		if connect_status_label.text.strip_edges().is_empty():
			_set_connect_status("未连接：请先连接服务器。")

	if _room_list_controller != null and is_instance_valid(_room_list_controller):
		_room_list_controller.render_room_list(NetContext.room_list if NetContext != null else [])
	if _room_state_renderer != null and is_instance_valid(_room_state_renderer):
		_room_state_renderer.render_room_state(NetContext.room_state if NetContext != null else {})
	_sync_page_from_state()

func _join_room_from_list(room_code: String, password_required: bool) -> void:
	if NetClient == null or not NetClient.is_online_client_connected():
		_show_error_dialog("未连接到服务器", "请先连接服务器。")
		_set_rooms_status("")
		return
	var code := str(room_code).strip_edges().to_upper()
	if code.is_empty():
		return
	if password_required:
		_prompt_password_and_join(code)
		return
	NetClient.request_join_room(code, "")
	_set_rooms_status("")

func _prompt_password_and_join(room_code: String) -> void:
	_ensure_password_dialog()
	_password_dialog_room_code = room_code
	if _password_dialog != null and is_instance_valid(_password_dialog) and _password_dialog.has_method("open_for_room"):
		_password_dialog.call_deferred("open_for_room", room_code, "加入/观战")

func _on_password_dialog_submitted(password: String) -> void:
	if NetClient == null or not NetClient.is_online_client_connected():
		return
	var code := str(_password_dialog_room_code).strip_edges().to_upper()
	if code.is_empty():
		return
	NetClient.request_join_room(code, str(password))
	_set_rooms_status("")

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

func _set_connect_status(text: String) -> void:
	connect_status_label.text = str(text).strip_edges()

func _set_rooms_status(text: String) -> void:
	rooms_status_label.text = str(text).strip_edges()

func _set_join_by_code_status(text: String) -> void:
	join_by_code_status_label.text = str(text).strip_edges()

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

func _on_net_connected() -> void:
	_set_connect_status("已连接")
	_set_rooms_status("")
	_set_join_by_code_status("")
	_set_create_status("")
	_set_room_status("")
	_refresh_ui()
	_show_page(LobbyPage.ROOMS, true)

func _on_net_disconnected(reason: String) -> void:
	var r := str(reason).strip_edges()
	if r == "connection_failed":
		var project_path := ProjectSettings.globalize_path("res://")
		var cmd := "godot --headless --path \"%s\" --scene res://server/dedicated_server.tscn -- --port=7000" % project_path
		_set_connect_status("连接失败：无法连接到服务器（请先启动 dedicated server）")
		_show_error_dialog("连接失败", "无法连接到服务器。\n\n若你尚未启动 Dedicated Server，可在项目根目录运行：\n%s" % cmd)
	else:
		_set_connect_status("已断开：%s" % reason)
	_set_rooms_status("")
	_set_join_by_code_status("")
	_set_create_status("")
	_set_room_status("")
	_set_config_sync_state("synced", "")
	_start_game_request_id = ""
	_start_game_flow_in_progress = false
	if SceneManager != null and SceneManager.has_method("hide_loading"):
		SceneManager.hide_loading()
	_refresh_ui()
	_show_page(LobbyPage.CONNECT, false)

func _on_room_list_updated(_rooms: Array) -> void:
	_refresh_ui()

func _on_room_state_updated(_room_state: Dictionary) -> void:
	_refresh_ui()
	if OS.has_feature("headless"):
		return
	var room_state: Dictionary = NetContext.room_state if NetContext != null else {}
	if str(room_state.get("status", "")).strip_edges() != "InGame":
		return
	if SceneManager != null and SceneManager.has_method("is_loading_visible") and SceneManager.is_loading_visible():
		return
	if SceneManager != null and SceneManager.has_method("show_loading"):
		SceneManager.show_loading("正在进入联机对局...")

func _on_request_rejected(request_id: String, code: String, message: String) -> void:
	if str(code).begins_with("update_config"):
		_set_config_sync_state("error", str(message))
		_refresh_ui()
		# StartGame 预同步失败：停止 loading 并解锁按钮
		if _start_game_flow_in_progress and _start_game_request_id.is_empty():
			_start_game_flow_in_progress = false
			if SceneManager != null and SceneManager.has_method("hide_loading"):
				SceneManager.hide_loading()

	if not _start_game_request_id.is_empty() and str(request_id) == _start_game_request_id:
		_start_game_request_id = ""
		_start_game_flow_in_progress = false
		if SceneManager != null and SceneManager.has_method("hide_loading"):
			SceneManager.hide_loading()

	if OS.has_feature("headless"):
		return

	var title := "请求失败"
	var body := ""
	var c := str(code).strip_edges()
	var m := str(message).strip_edges()

	match c:
		"protocol_version_mismatch":
			title = "协议版本不匹配"
			body = "客户端与服务器版本不一致，请更新后重试。"
		"missing_client_hello":
			title = "连接未完成"
			body = "请先连接服务器后再重试。"
		"invalid_player_count":
			title = "创建房间失败"
			body = "玩家人数不合法。"
		"invalid_params":
			title = "请求参数错误"
			body = m
		"create_room_failed":
			title = "创建房间失败"
			body = m
		"join_room_failed":
			title = "加入房间失败"
			match m:
				"Missing room_code":
					body = "请填写房间码。"
				"Room not found":
					body = "房间不存在或已解散。"
				"Invalid room_password":
					body = "房间密码错误，请重试。"
				"Room is full":
					body = "房间已满。"
				_:
					body = m
		"leave_room_failed":
			title = "离开房间失败"
			body = m
		"start_game_failed":
			title = "开始游戏失败"
			body = m
		"update_config_failed":
			title = "配置同步失败"
			body = m
		"not_in_room":
			title = "操作失败"
			body = "你当前不在房间内。"
		"not_in_game":
			title = "操作失败"
			body = "房间不在对局中。"
		"not_host":
			title = "操作失败"
			body = "仅房主可以执行该操作。"
		"spectator_readonly":
			title = "只读模式"
			body = "旁观者无法执行该操作。"
		"forfeited_readonly":
			title = "只读模式"
			body = "你已弃权，当前为只读旁观模式。"
		_:
			title = "请求失败"
			if not m.is_empty():
				body = m
			else:
				body = "%s" % c

	if body.is_empty():
		body = "请求失败，请稍后重试。"
	if not request_id.is_empty():
		body = "%s\n\n（请求号：%s）" % [body, request_id]

	_show_error_dialog(title, body)

func _on_game_started(_payload: Dictionary) -> void:
	_start_game_request_id = ""
	_start_game_flow_in_progress = false
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
	NetClient.request_update_room_config(_pending_config_patch)
	_set_room_status("")

func _room_config_matches_patch(cfg: Dictionary, patch: Dictionary) -> bool:
	if cfg == null or patch == null:
		return false
	for k in patch.keys():
		if cfg.get(k, null) != patch.get(k, null):
			return false
	return true

func _await_config_sync(timeout_sec: float = 5.0) -> bool:
	var deadline_ms := int(Time.get_ticks_msec() + int(round(timeout_sec * 1000.0)))
	while Time.get_ticks_msec() < deadline_ms:
		if _config_sync_state == "synced":
			return true
		if _config_sync_state == "error":
			return false
		await get_tree().process_frame
	return false

func _apply_my_color_option_selection(color_index: int) -> void:
	if my_color_option == null or not is_instance_valid(my_color_option):
		return
	if my_color_option.item_count <= 0:
		return
	var idx := clampi(int(color_index), 0, my_color_option.item_count - 1)
	_suppress_profile_signals = true
	my_color_option.select(idx)
	_suppress_profile_signals = false

func _write_local_player_profile(name: String, color_index: int) -> void:
	if NetContext == null:
		return
	var p: Dictionary = {}
	if NetContext.player_profile is Dictionary:
		p = Dictionary(NetContext.player_profile)
	p["name"] = str(name).strip_edges()
	p["color_index"] = int(color_index)
	NetContext.player_profile = p

func _on_my_color_option_selected(index: int) -> void:
	if _suppress_profile_signals:
		return
	if my_color_option == null or not is_instance_valid(my_color_option):
		return
	var meta_val = my_color_option.get_item_metadata(index)
	var palette_index := int(meta_val)
	_write_local_player_profile(str(player_name_edit.text), palette_index)
	if NetClient == null or not NetClient.is_online_client_connected():
		return
	# 仅在进入房间后允许选择餐厅/颜色（联机大厅设计：避免入局前选择造成困惑/冲突）
	if _get_current_room_code().is_empty():
		return
	if NetClient.has_method("request_update_player_profile"):
		NetClient.request_update_player_profile(NetContext.player_profile)

func _on_back_pressed() -> void:
	if NetClient != null:
		NetClient.shutdown()
	if SceneManager != null and SceneManager.has_method("go_back") and SceneManager.go_back():
		return
	if SceneManager != null and SceneManager.has_method("goto_main_menu"):
		SceneManager.goto_main_menu()

func _on_connect_pressed() -> void:
	_write_local_player_profile(str(player_name_edit.text), int(NetContext.player_profile.get("color_index", 0)) if (NetContext != null and NetContext.player_profile is Dictionary) else 0)
	var url := str(server_url_edit.text).strip_edges()
	var r: Result = NetClient.connect_to_server(url)
	if not r.ok:
		_set_connect_status("连接失败：%s" % r.error)
	_refresh_ui()

func _on_disconnect_pressed() -> void:
	if NetClient != null:
		NetClient.shutdown()
	_refresh_ui()

func _on_open_create_pressed() -> void:
	if NetClient == null or not NetClient.is_online_client_connected():
		_show_error_dialog("未连接到服务器", "请先连接服务器。")
		_set_rooms_status("")
		return
	_set_create_status("")
	_show_page(LobbyPage.CREATE, false)

func _on_open_join_by_code_pressed() -> void:
	if NetClient == null or not NetClient.is_online_client_connected():
		_show_error_dialog("未连接到服务器", "请先连接服务器。")
		_set_rooms_status("")
		return
	_set_join_by_code_status("")
	_show_page(LobbyPage.JOIN_BY_CODE, false)
	if join_by_code_room_code_edit != null and is_instance_valid(join_by_code_room_code_edit):
		join_by_code_room_code_edit.grab_focus()

func _on_back_from_join_pressed() -> void:
	_set_join_by_code_status("")
	_show_page(LobbyPage.ROOMS, true)

func _on_back_to_rooms_pressed() -> void:
	_set_create_status("")
	_show_page(LobbyPage.ROOMS, true)

func _on_refresh_rooms_pressed() -> void:
	if NetClient == null or not NetClient.is_online_client_connected():
		_show_error_dialog("未连接到服务器", "请先连接服务器。")
		_set_rooms_status("")
		return
	NetClient.request_list_rooms()
	_set_rooms_status("")

func _on_join_by_code_submit_pressed() -> void:
	if NetClient == null or not NetClient.is_online_client_connected():
		_show_error_dialog("未连接到服务器", "请先连接服务器。")
		_set_join_by_code_status("")
		return
	var room_code := str(join_by_code_room_code_edit.text).strip_edges().to_upper()
	var room_password := str(join_by_code_password_edit.text)
	NetClient.request_join_room(room_code, room_password)
	_set_join_by_code_status("")

func _on_create_room_pressed() -> void:
	if NetClient == null or not NetClient.is_online_client_connected():
		_show_error_dialog("未连接到服务器", "请先连接服务器。")
		_set_create_status("")
		return
	if create_players_spin == null or not is_instance_valid(create_players_spin):
		_show_error_dialog("创建房间失败", "人数输入缺失。")
		_set_create_status("")
		return
	var desired := clampi(int(create_players_spin.value), Globals.MIN_PLAYERS, Globals.MAX_PLAYERS)

	var room_password := str(create_password_edit.text)
	NetClient.request_create_room(desired, room_password, {})
	_set_create_status("")

func _on_leave_room_pressed() -> void:
	if NetClient == null or not NetClient.is_online_client_connected():
		_show_error_dialog("未连接到服务器", "请先连接服务器。")
		_set_room_status("")
		return
	config_debounce_timer.stop()
	_pending_config_patch = {}
	_set_config_sync_state("synced", "")
	_start_game_request_id = ""
	_start_game_flow_in_progress = false
	NetClient.request_leave_room()
	_set_room_status("")

func _on_start_game_pressed() -> void:
	if NetClient == null or not NetClient.is_online_client_connected():
		_show_error_dialog("未连接到服务器", "请先连接服务器。")
		_set_room_status("")
		return
	var room_state: Dictionary = NetContext.room_state if NetContext != null else {}
	if not _is_host(room_state):
		_show_error_dialog("无法开始游戏", "仅房主可开始游戏。")
		_set_room_status("")
		return
	if _start_game_flow_in_progress:
		return
	if _room_config_editor == null or not is_instance_valid(_room_config_editor):
		_show_error_dialog("无法开始游戏", "房间配置编辑器缺失。")
		_set_room_status("")
		return

	var vr: Result = _room_config_editor.validate()
	if not vr.ok:
		_set_config_sync_state("error", vr.error)
		_show_error_dialog("无法开始游戏", vr.error)
		_set_room_status("")
		return

	_start_game_flow_in_progress = true
	_refresh_ui()

	if not OS.has_feature("headless"):
		if SceneManager != null and SceneManager.has_method("show_loading"):
			SceneManager.show_loading("正在开始游戏...")
			await get_tree().process_frame

	# StartGame：进入 loading 后主动触发一次同步（避免“光标仍在输入框中导致未同步”）。
	config_debounce_timer.stop()
	var patch: Dictionary = _room_config_editor.get_config_patch()
	var cfg: Dictionary = Dictionary(room_state.get("config", {}))

	if _room_config_matches_patch(cfg, patch):
		_pending_config_patch = {}
		_set_config_sync_state("synced", "")
	else:
		_pending_config_patch = patch
		_set_config_sync_state("syncing", "")
		NetClient.request_update_room_config(patch)
		var synced := await _await_config_sync(5.0)
		if not synced:
			if _config_sync_state != "error":
				_set_config_sync_state("error", "配置同步超时")
			_start_game_flow_in_progress = false
			_refresh_ui()
			if SceneManager != null and SceneManager.has_method("hide_loading"):
				SceneManager.hide_loading()
			_set_room_status("")
			return

	_start_game_request_id = NetClient.request_start_game()
	_set_room_status("")

func _on_copy_room_code_pressed() -> void:
	var code := _get_current_room_code()
	if code.is_empty():
		return
	DisplayServer.clipboard_set(code)
	_set_room_status("已复制房间码：%s" % code)
