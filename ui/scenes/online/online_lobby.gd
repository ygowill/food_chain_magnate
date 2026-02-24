# 联机大厅：ConnectPage / BrowsePage / RoomPage 三页导航 + CreateRoomDialog 弹窗 + 配置自动同步
extends Control

const RoomConfigEditorClass = preload("res://ui/components/room_config_editor/room_config_editor.gd")
const UiStylesClass = preload("res://ui/utils/ui_styles.gd")
const PasswordDialogClass = preload("res://ui/dialogs/password_dialog.gd")
const InfoDialogClass = preload("res://ui/dialogs/info_dialog.gd")
const CreateRoomDialogClass = preload("res://ui/dialogs/create_room_dialog.gd")
const AuthDialogClass = preload("res://ui/dialogs/auth_dialog.gd")
const RoomListControllerClass = preload("res://ui/scenes/online/online_lobby_room_list_controller.gd")
const RoomStateRendererClass = preload("res://ui/scenes/online/online_lobby_room_state_renderer.gd")
const RequestRejectionMapperClass = preload("res://ui/scenes/online/online_lobby_request_rejection_mapper.gd")
const LobbyViewModelClass = preload("res://ui/scenes/online/online_lobby_view_model.gd")
const RoomConfigSyncControllerClass = preload("res://ui/scenes/online/online_lobby_room_config_sync_controller.gd")
const MapSkinBuilderClass = preload("res://ui/visual/map_skin_builder.gd")
const GameSetupClass = preload("res://ui/scenes/setup/game_setup.gd")

const _LOGO_DISPLAY_NAMES: Dictionary = GameSetupClass.LOGO_DISPLAY_NAMES
const _DEFAULT_LOGO_COUNT := 6

@onready var wall_background: ColorRect = $WallBackground
@onready var vignette_overlay: ColorRect = $VignetteOverlay
@onready var panel: PanelContainer = $Center/Panel
@onready var inner_border: PanelContainer = $Center/Panel/OuterMargin/InnerBorder
@onready var back_button: Button = $Center/Panel/OuterMargin/InnerBorder/Margin/Root/TopBar/BackButton
@onready var top_title_label: Label = $Center/Panel/OuterMargin/InnerBorder/Margin/Root/TopBar/Title
@onready var account_status_label: Label = $Center/Panel/OuterMargin/InnerBorder/Margin/Root/TopBar/AccountBar/AccountStatusLabel
@onready var account_button: Button = $Center/Panel/OuterMargin/InnerBorder/Margin/Root/TopBar/AccountBar/AccountButton
@onready var pages: VBoxContainer = $Center/Panel/OuterMargin/InnerBorder/Margin/Root/Pages

# ── ConnectPage ──
@onready var page_connect: Control = $Center/Panel/OuterMargin/InnerBorder/Margin/Root/Pages/ConnectPage
@onready var mode_option: OptionButton = $Center/Panel/OuterMargin/InnerBorder/Margin/Root/Pages/ConnectPage/ModeRow/ModeOption
@onready var server_row: HBoxContainer = $Center/Panel/OuterMargin/InnerBorder/Margin/Root/Pages/ConnectPage/ServerRow
@onready var server_url_edit: LineEdit = $Center/Panel/OuterMargin/InnerBorder/Margin/Root/Pages/ConnectPage/ServerRow/ServerUrlEdit
@onready var backend_row: HBoxContainer = $Center/Panel/OuterMargin/InnerBorder/Margin/Root/Pages/ConnectPage/BackendRow
@onready var backend_url_edit: LineEdit = $Center/Panel/OuterMargin/InnerBorder/Margin/Root/Pages/ConnectPage/BackendRow/BackendUrlEdit
@onready var player_name_edit: LineEdit = $Center/Panel/OuterMargin/InnerBorder/Margin/Root/Pages/ConnectPage/ProfileRow/PlayerNameEdit
@onready var connect_button: Button = $Center/Panel/OuterMargin/InnerBorder/Margin/Root/Pages/ConnectPage/ButtonsRow/ConnectButton
@onready var disconnect_button: Button = $Center/Panel/OuterMargin/InnerBorder/Margin/Root/Pages/ConnectPage/ButtonsRow/DisconnectButton
@onready var connect_status_label: Label = $Center/Panel/OuterMargin/InnerBorder/Margin/Root/Pages/ConnectPage/ConnectStatus

# ── BrowsePage ──
@onready var page_browse: Control = $Center/Panel/OuterMargin/InnerBorder/Margin/Root/Pages/BrowsePage
@onready var open_create_button: Button = $Center/Panel/OuterMargin/InnerBorder/Margin/Root/Pages/BrowsePage/BrowseHeader/OpenCreateButton
@onready var refresh_rooms_button: Button = $Center/Panel/OuterMargin/InnerBorder/Margin/Root/Pages/BrowsePage/BrowseHeader/RefreshRoomsButton
@onready var quick_join_code_edit: LineEdit = $Center/Panel/OuterMargin/InnerBorder/Margin/Root/Pages/BrowsePage/QuickJoinBar/QuickJoinCodeEdit
@onready var quick_join_password_edit: LineEdit = $Center/Panel/OuterMargin/InnerBorder/Margin/Root/Pages/BrowsePage/QuickJoinBar/QuickJoinPasswordEdit
@onready var quick_join_button: Button = $Center/Panel/OuterMargin/InnerBorder/Margin/Root/Pages/BrowsePage/QuickJoinBar/QuickJoinButton
@onready var quick_spectate_button: Button = $Center/Panel/OuterMargin/InnerBorder/Margin/Root/Pages/BrowsePage/QuickJoinBar/QuickSpectateButton
@onready var rooms_scroll: ScrollContainer = $Center/Panel/OuterMargin/InnerBorder/Margin/Root/Pages/BrowsePage/RoomsScroll
@onready var rooms_list_container: VBoxContainer = $Center/Panel/OuterMargin/InnerBorder/Margin/Root/Pages/BrowsePage/RoomsScroll/RoomsList
@onready var browse_status_label: Label = $Center/Panel/OuterMargin/InnerBorder/Margin/Root/Pages/BrowsePage/BrowseStatus

# ── RoomPage ──
@onready var page_room: Control = $Center/Panel/OuterMargin/InnerBorder/Margin/Root/Pages/RoomPage
@onready var room_code_label: Label = $Center/Panel/OuterMargin/InnerBorder/Margin/Root/Pages/RoomPage/RoomHeader/RoomCodeLabel
@onready var copy_room_code_button: Button = $Center/Panel/OuterMargin/InnerBorder/Margin/Root/Pages/RoomPage/RoomHeader/CopyRoomCodeButton
@onready var config_sync_status_label: Label = $Center/Panel/OuterMargin/InnerBorder/Margin/Root/Pages/RoomPage/RoomHeader/ConfigSyncStatus
@onready var my_logo_row: HBoxContainer = $Center/Panel/OuterMargin/InnerBorder/Margin/Root/Pages/RoomPage/RoomBody/LeftColumn/MyColorRow
@onready var my_color_option: OptionButton = $Center/Panel/OuterMargin/InnerBorder/Margin/Root/Pages/RoomPage/RoomBody/LeftColumn/MyColorRow/MyColorOption
@onready var players_list_container: VBoxContainer = $Center/Panel/OuterMargin/InnerBorder/Margin/Root/Pages/RoomPage/RoomBody/LeftColumn/PlayersList
@onready var spectators_list_container: VBoxContainer = $Center/Panel/OuterMargin/InnerBorder/Margin/Root/Pages/RoomPage/RoomBody/LeftColumn/SpectatorsList
@onready var room_config_container: VBoxContainer = $Center/Panel/OuterMargin/InnerBorder/Margin/Root/Pages/RoomPage/RoomBody/RightColumn/RoomConfigContainer
@onready var leave_room_button: Button = $Center/Panel/OuterMargin/InnerBorder/Margin/Root/Pages/RoomPage/RoomActionsRow/LeaveRoomButton
@onready var start_game_button: Button = $Center/Panel/OuterMargin/InnerBorder/Margin/Root/Pages/RoomPage/RoomActionsRow/StartGameButton
@onready var room_status_label: Label = $Center/Panel/OuterMargin/InnerBorder/Margin/Root/Pages/RoomPage/RoomStatus

@onready var config_debounce_timer: Timer = $ConfigDebounceTimer

enum LobbyPage { CONNECT, BROWSE, ROOM }
var _current_page: int = LobbyPage.CONNECT

const CONNECTION_MODE_DIRECT := "direct"
const CONNECTION_MODE_PLATFORM := "platform"

var _room_config_editor = null
var _room_list_controller = null
var _room_state_renderer = null

var _room_config_sync_controller = null
var _start_game_request_id: String = ""
var _start_game_flow_in_progress: bool = false

var _password_dialog = null
var _password_dialog_room_code: String = ""
var _info_dialog = null
var _create_room_dialog = null
var _auth_dialog = null
var _suppress_profile_signals: bool = false
var _logo_icons_small: Array[Texture2D] = []
var _logo_piece_ids: Array[String] = []

var _selected_connection_mode: String = CONNECTION_MODE_DIRECT
var _platform_entered: bool = false
var _platform_busy: bool = false

func _ready() -> void:
	UiStylesClass.apply_tiled_texture(wall_background, UiStylesClass.WALL_TEXTURE_PATHS, 3.0, Color(0.93, 0.88, 0.75, 1.0))
	UiStylesClass.apply_vignette(vignette_overlay, 0.45, 0.5)
	UiStylesClass.apply_dialog_surface(panel)
	UiStylesClass.apply_poster_inner_border(inner_border)
	UiStylesClass.apply_button_secondary(back_button)
	UiStylesClass.apply_button_secondary(account_button)
	UiStylesClass.apply_button_primary(connect_button)
	UiStylesClass.apply_button_secondary(disconnect_button)
	UiStylesClass.apply_button_primary(open_create_button)
	UiStylesClass.apply_button_secondary(refresh_rooms_button)
	UiStylesClass.apply_button_primary(quick_join_button)
	UiStylesClass.apply_button_secondary(quick_spectate_button)
	UiStylesClass.apply_button_secondary(copy_room_code_button)
	UiStylesClass.apply_button_secondary(leave_room_button)
	UiStylesClass.apply_button_primary(start_game_button)
	_apply_visual_styles()

	_apply_password_mask_fallback()
	_bind_net_signals()
	_bind_platform_signals()
	_ensure_editors()
	_ensure_config_sync_controller()
	_ensure_password_dialog()
	_ensure_info_dialog()
	_ensure_create_room_dialog()
	_ensure_room_renderers()
	_setup_connection_mode_selector()
	_setup_account_ui()
	if my_logo_row != null and is_instance_valid(my_logo_row):
		my_logo_row.visible = false
	_apply_defaults()
	_refresh_ui()

func _apply_visual_styles() -> void:
	_apply_label_style_recursive(panel)
	UiStylesClass.apply_label_hint_dark(connect_status_label)
	UiStylesClass.apply_label_hint_dark(browse_status_label)
	UiStylesClass.apply_label_hint_dark(config_sync_status_label)
	UiStylesClass.apply_label_hint_dark(room_status_label)
	UiStylesClass.apply_label_hint_dark(account_status_label)
	UiStylesClass.apply_line_edit_field(server_url_edit)
	UiStylesClass.apply_line_edit_field(backend_url_edit)
	UiStylesClass.apply_line_edit_field(player_name_edit)
	UiStylesClass.apply_line_edit_field(quick_join_code_edit)
	UiStylesClass.apply_line_edit_field(quick_join_password_edit)
	UiStylesClass.apply_option_button_field(my_color_option)
	UiStylesClass.apply_option_button_field(mode_option)

func _apply_label_style_recursive(root: Node) -> void:
	if root == null:
		return
	if root is Label:
		UiStylesClass.apply_label_dark(root)
	for child in root.get_children():
		_apply_label_style_recursive(child)

func _apply_password_mask_fallback() -> void:
	_apply_password_mask_to(quick_join_password_edit)

func _apply_password_mask_to(edit: LineEdit) -> void:
	if edit == null or not is_instance_valid(edit):
		return
	if not edit.secret:
		return
	edit.secret_character = "*"

func _setup_my_logo_selector() -> void:
	if my_color_option == null or not is_instance_valid(my_color_option):
		return
	if my_color_option.item_selected.is_connected(_on_my_logo_option_selected):
		return
	_rebuild_my_logo_options()
	my_color_option.item_selected.connect(_on_my_logo_option_selected)

func _rebuild_my_logo_options() -> void:
	my_color_option.clear()
	_ensure_logo_icons_cache()

	my_color_option.add_item("随机")
	my_color_option.set_item_metadata(0, -1)

	var logo_count := _logo_piece_ids.size()
	if logo_count <= 0:
		logo_count = _get_default_logo_count()
		for i in range(logo_count):
			my_color_option.add_item("店铺 %d" % (i + 1))
			my_color_option.set_item_metadata(i + 1, i)
		return

	for i in range(logo_count):
		var piece_id := str(_logo_piece_ids[i]).strip_edges()
		var label := _get_logo_display_name(piece_id, i)
		var icon_tex: Texture2D = _logo_icons_small[i] if i < _logo_icons_small.size() else null
		if icon_tex != null:
			my_color_option.add_icon_item(icon_tex, label)
		else:
			my_color_option.add_item(label)
		my_color_option.set_item_metadata(i + 1, i)

func _ensure_logo_icons_cache() -> void:
	_logo_icons_small.clear()
	_logo_piece_ids.clear()

	var base_dir := str(Globals.modules_v2_base_dir) if Globals != null else ""
	if base_dir.is_empty():
		return
	var read: Result = MapSkinBuilderClass.build_for_modules(base_dir, ["base_pieces"], 40)
	if not read.ok:
		GameLog.warn("OnlineLobby", "加载餐厅 Logo 贴图失败: %s" % read.error)
		return
	var skin = read.value
	if skin == null or not skin.has_method("get_piece_texture") or not skin.has_method("get_restaurant_logo_piece_ids"):
		GameLog.warn("OnlineLobby", "加载餐厅 Logo 贴图失败：skin 类型错误")
		return
	var logo_ids_val = skin.get_restaurant_logo_piece_ids()
	if not (logo_ids_val is Array):
		return
	for piece_id_val in (logo_ids_val as Array):
		var piece_id := str(piece_id_val).strip_edges()
		if piece_id.is_empty():
			continue
		_logo_piece_ids.append(piece_id)
		var tex: Texture2D = skin.get_piece_texture(piece_id)
		_logo_icons_small.append(_scale_texture_square(tex, 20))

func _scale_texture_square(tex: Texture2D, size_px: int) -> Texture2D:
	if tex == null:
		return null
	var img := tex.get_image()
	if img == null:
		return tex
	img.resize(size_px, size_px, Image.INTERPOLATE_LANCZOS)
	return ImageTexture.create_from_image(img)

func _get_logo_display_name(piece_id: String, index: int) -> String:
	if _LOGO_DISPLAY_NAMES.has(piece_id):
		return str(_LOGO_DISPLAY_NAMES[piece_id])
	return "店铺 %d" % (index + 1)

func _get_default_logo_count() -> int:
	var fallback := _DEFAULT_LOGO_COUNT
	if Globals != null:
		fallback = int(Globals.DEFAULT_RESTAURANT_LOGO_COUNT)
	return maxi(1, fallback)

func _ensure_editors() -> void:
	if _room_config_editor == null or not is_instance_valid(_room_config_editor):
		_room_config_editor = RoomConfigEditorClass.new()
		room_config_container.add_child(_room_config_editor)
		_room_config_editor.changed.connect(_on_room_config_changed)
		_room_config_editor.validation_failed.connect(func(msg: String) -> void:
			_ensure_config_sync_controller()
			if _room_config_sync_controller != null and is_instance_valid(_room_config_sync_controller):
				_room_config_sync_controller.on_room_config_editor_validation_failed(msg)
		)

func _ensure_config_sync_controller() -> void:
	if _room_config_sync_controller == null or not is_instance_valid(_room_config_sync_controller):
		_room_config_sync_controller = RoomConfigSyncControllerClass.new()
		_room_config_sync_controller.setup(self, config_sync_status_label, config_debounce_timer)

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

func _ensure_create_room_dialog() -> void:
	if _create_room_dialog != null and is_instance_valid(_create_room_dialog):
		return
	_create_room_dialog = CreateRoomDialogClass.new()
	add_child(_create_room_dialog)
	if not _create_room_dialog.create_requested.is_connected(_on_create_room_dialog_confirmed):
		_create_room_dialog.create_requested.connect(_on_create_room_dialog_confirmed)

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
	_set_browse_status("")
	_set_room_status("")

	if NetContext != null and not str(NetContext.server_url).is_empty():
		server_url_edit.text = str(NetContext.server_url)
	else:
		server_url_edit.text = "ws://127.0.0.1:7000"

	if PlatformApi != null and backend_url_edit != null and is_instance_valid(backend_url_edit):
		var bu := str(PlatformApi.base_url).strip_edges()
		backend_url_edit.text = bu if not bu.is_empty() else "http://127.0.0.1:8000"

	var profile_name := "玩家"
	var profile_logo_id := -1
	if NetContext != null and NetContext.player_profile is Dictionary and not Dictionary(NetContext.player_profile).is_empty():
		var p: Dictionary = Dictionary(NetContext.player_profile)
		profile_name = str(p.get("name", "玩家"))
		profile_logo_id = int(p.get("restaurant_logo_id", -1))
	elif Globals != null:
		if Globals.player_names is Array and not Globals.player_names.is_empty():
			profile_name = str(Globals.player_names[0])
		if Globals.player_restaurant_logo_choices is Array and not Globals.player_restaurant_logo_choices.is_empty():
			profile_logo_id = int(Globals.player_restaurant_logo_choices[0])

	player_name_edit.text = profile_name
	_write_local_player_profile(profile_name, profile_logo_id)
	_apply_my_logo_option_selection(profile_logo_id)
	_ensure_config_sync_controller()
	if _room_config_sync_controller != null and is_instance_valid(_room_config_sync_controller):
		_room_config_sync_controller.reset()

	_apply_connection_mode_ui()
	_update_account_status()

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

func _bind_platform_signals() -> void:
	if PlatformSession == null:
		return
	if PlatformSession.has_signal("session_changed") and not PlatformSession.session_changed.is_connected(_on_platform_session_changed):
		PlatformSession.session_changed.connect(_on_platform_session_changed)

func _on_platform_session_changed() -> void:
	_update_account_status()
	_refresh_ui()

func _setup_account_ui() -> void:
	if account_button != null and is_instance_valid(account_button):
		if not account_button.pressed.is_connected(_on_account_pressed):
			account_button.pressed.connect(_on_account_pressed)
	if quick_spectate_button != null and is_instance_valid(quick_spectate_button):
		if not quick_spectate_button.pressed.is_connected(_on_quick_spectate_pressed):
			quick_spectate_button.pressed.connect(_on_quick_spectate_pressed)

func _update_account_status() -> void:
	if account_status_label == null or not is_instance_valid(account_status_label):
		return
	if PlatformSession == null:
		account_status_label.text = "账号：-"
		return
	if not PlatformSession.is_logged_in:
		account_status_label.text = "账号：未登录"
		return
	var uid := str(PlatformSession.user_id).strip_edges()
	var short_uid := uid.substr(0, 8) if uid.length() >= 8 else uid
	if PlatformSession.is_guest:
		account_status_label.text = "账号：游客 %s" % short_uid
	else:
		account_status_label.text = "账号：已登录 %s" % short_uid

func _ensure_auth_dialog() -> void:
	if _auth_dialog != null and is_instance_valid(_auth_dialog):
		return
	_auth_dialog = AuthDialogClass.new()
	add_child(_auth_dialog)
	if _auth_dialog.has_signal("auth_completed") and not _auth_dialog.auth_completed.is_connected(_on_auth_completed):
		_auth_dialog.auth_completed.connect(_on_auth_completed)

func _on_auth_completed(_result: Dictionary) -> void:
	_update_account_status()
	_refresh_ui()

func _on_account_pressed() -> void:
	if OS.has_feature("headless"):
		return
	_ensure_auth_dialog()
	if _auth_dialog == null or not is_instance_valid(_auth_dialog):
		return
	# Guest 默认走“绑定邮箱”升级；非 guest 则打开登录/注册（也可切换账号）。
	if PlatformSession != null and PlatformSession.is_logged_in and PlatformSession.is_guest and _auth_dialog.has_method("open_for_bind"):
		_auth_dialog.call("open_for_bind")
	else:
		_auth_dialog.call("open")

func _setup_connection_mode_selector() -> void:
	if mode_option == null or not is_instance_valid(mode_option):
		return
	if mode_option.item_count <= 0:
		mode_option.add_item("直连")
		mode_option.set_item_metadata(0, CONNECTION_MODE_DIRECT)
		mode_option.add_item("平台")
		mode_option.set_item_metadata(1, CONNECTION_MODE_PLATFORM)
	if not mode_option.item_selected.is_connected(_on_mode_selected):
		mode_option.item_selected.connect(_on_mode_selected)
	_apply_connection_mode_ui()

func _on_mode_selected(index: int) -> void:
	if mode_option == null or not is_instance_valid(mode_option):
		return
	var meta = mode_option.get_item_metadata(index)
	var mode := str(meta).strip_edges()
	if mode.is_empty():
		mode = CONNECTION_MODE_DIRECT if index == 0 else CONNECTION_MODE_PLATFORM
	if mode == _selected_connection_mode:
		return
	_selected_connection_mode = mode
	_platform_entered = false
	_set_connect_status("")
	_set_browse_status("")
	if NetContext != null:
		NetContext.connection_mode = _selected_connection_mode
	_apply_connection_mode_ui()
	_refresh_ui()

func _is_platform_mode_selected() -> bool:
	return _selected_connection_mode == CONNECTION_MODE_PLATFORM

func _apply_connection_mode_ui() -> void:
	var platform := _is_platform_mode_selected()
	if server_row != null and is_instance_valid(server_row):
		server_row.visible = not platform
	if backend_row != null and is_instance_valid(backend_row):
		backend_row.visible = platform
	if connect_button != null and is_instance_valid(connect_button):
		connect_button.text = "连接" if not platform else "进入"
	if refresh_rooms_button != null and is_instance_valid(refresh_rooms_button):
		refresh_rooms_button.visible = not platform
	if rooms_scroll != null and is_instance_valid(rooms_scroll):
		rooms_scroll.visible = not platform
	if quick_spectate_button != null and is_instance_valid(quick_spectate_button):
		quick_spectate_button.visible = platform

func _platform_set_base_url_from_ui() -> void:
	if PlatformApi == null:
		return
	if backend_url_edit == null or not is_instance_valid(backend_url_edit):
		return
	var base_url := str(backend_url_edit.text).strip_edges()
	if base_url.is_empty():
		return
	PlatformApi.base_url = base_url

func _platform_ensure_session() -> Result:
	if PlatformSession == null:
		return Result.failure("PlatformSession autoload missing")
	if PlatformApi == null:
		return Result.failure("PlatformApi autoload missing")
	_platform_set_base_url_from_ui()
	var res: Dictionary = await PlatformSession.auto_guest_login()
	if res.has("error"):
		return Result.failure(str(res.get("error", "platform login failed")))
	if not PlatformSession.is_logged_in:
		return Result.failure("platform login failed")
	return Result.success()

func _platform_enter() -> void:
	if _platform_busy:
		return
	_platform_busy = true
	_set_connect_status("正在登录平台...")
	_refresh_ui()
	var lr: Result = await _platform_ensure_session()
	_platform_busy = false
	if not lr.ok:
		_platform_entered = false
		_set_connect_status("平台登录失败：%s" % lr.error)
		_refresh_ui()
		return
	_platform_entered = true
	_update_account_status()
	_set_connect_status("平台已就绪：创建/加入房间将自动连接服务器。")
	_refresh_ui()
	_show_page(LobbyPage.BROWSE, false)

func _platform_create_room(desired_player_count: int, room_password: String, config_patch: Dictionary) -> void:
	if _platform_busy:
		return
	_platform_busy = true
	_set_browse_status("正在创建房间...")
	_refresh_ui()
	var lr: Result = await _platform_ensure_session()
	if not lr.ok:
		_platform_busy = false
		_set_browse_status("")
		_show_error_dialog("平台登录失败", lr.error)
		_refresh_ui()
		return
	_platform_entered = true

	var config: Dictionary = config_patch.duplicate(true)
	config["desired_player_count"] = int(desired_player_count)
	var config_json := JSON.stringify(config)

	var cr: Dictionary = await PlatformApi.create_room(PlatformSession.session_id, config_json, room_password)
	_platform_busy = false
	if cr.has("error"):
		_show_error_dialog("创建房间失败", str(cr.get("error", "")))
		_set_browse_status("")
		_refresh_ui()
		return
	var ok_val = cr.get("ok", null)
	if not (ok_val is Dictionary):
		_show_error_dialog("创建房间失败", "后端返回格式错误")
		_set_browse_status("")
		_refresh_ui()
		return
	var ok: Dictionary = Dictionary(ok_val)
	var ws_url := str(ok.get("ws_url", "")).strip_edges()
	var connect_token := str(ok.get("connect_token", "")).strip_edges()
	if ws_url.is_empty() or connect_token.is_empty():
		_show_error_dialog("创建房间失败", "后端返回缺少 ws_url/connect_token")
		_set_browse_status("")
		_refresh_ui()
		return

	_set_browse_status("创建成功，正在连接...")
	_platform_connect_to_ws(ws_url, connect_token)

func _platform_join_room(room_code: String, room_password: String, spectate: bool) -> void:
	if _platform_busy:
		return
	_platform_busy = true
	_set_browse_status("正在请求房间...")
	_refresh_ui()
	var lr: Result = await _platform_ensure_session()
	if not lr.ok:
		_platform_busy = false
		_set_browse_status("")
		_show_error_dialog("平台登录失败", lr.error)
		_refresh_ui()
		return
	_platform_entered = true

	var code := str(room_code).strip_edges().to_upper()
	var jr: Dictionary
	if spectate:
		jr = await PlatformApi.spectate_room(code, PlatformSession.session_id)
	else:
		jr = await PlatformApi.join_room(code, PlatformSession.session_id, str(room_password))
	_platform_busy = false

	if jr.has("error"):
		_show_error_dialog("加入房间失败", str(jr.get("error", "")))
		_set_browse_status("")
		_refresh_ui()
		return
	var ok_val = jr.get("ok", null)
	if not (ok_val is Dictionary):
		_show_error_dialog("加入房间失败", "后端返回格式错误")
		_set_browse_status("")
		_refresh_ui()
		return
	var ok: Dictionary = Dictionary(ok_val)
	var ws_url := str(ok.get("ws_url", "")).strip_edges()
	var connect_token := str(ok.get("connect_token", "")).strip_edges()
	if ws_url.is_empty() or connect_token.is_empty():
		_show_error_dialog("加入房间失败", "后端返回缺少 ws_url/connect_token")
		_set_browse_status("")
		_refresh_ui()
		return

	_set_browse_status("正在连接...")
	_platform_connect_to_ws(ws_url, connect_token)

func _platform_connect_to_ws(ws_url: String, connect_token: String) -> void:
	if NetClient == null:
		_show_error_dialog("连接失败", "NetClient autoload missing")
		return
	var url := _build_platform_connect_url(ws_url, connect_token)
	if url.is_empty():
		_show_error_dialog("连接失败", "无效的 ws_url")
		return
	_write_local_player_profile(
		str(player_name_edit.text),
		int(NetContext.player_profile.get("restaurant_logo_id", -1)) if (NetContext != null and NetContext.player_profile is Dictionary) else -1
	)
	var r: Result = NetClient.connect_to_server(url)
	if not r.ok:
		_set_connect_status("连接失败：%s" % r.error)
	_set_browse_status("")
	_refresh_ui()

func _build_platform_connect_url(ws_url: String, connect_token: String) -> String:
	var base := str(ws_url).strip_edges()
	if base.is_empty():
		return ""
	var sep := "?" if base.find("?") < 0 else "&"
	return base + sep + "connect_token=" + str(connect_token).uri_encode()

# ── 页面导航 ──

func _show_page(page: int, request_rooms_on_entry: bool = true) -> void:
	var prev := _current_page
	_current_page = page

	if is_instance_valid(page_connect):
		page_connect.visible = page == LobbyPage.CONNECT
	if is_instance_valid(page_browse):
		page_browse.visible = page == LobbyPage.BROWSE
	if is_instance_valid(page_room):
		page_room.visible = page == LobbyPage.ROOM

	# RoomPage 需要更大面板
	if page == LobbyPage.ROOM:
		panel.custom_minimum_size = Vector2(1200, 720)
	else:
		panel.custom_minimum_size = Vector2(980, 720)

	_update_top_title()

	if request_rooms_on_entry and page == LobbyPage.BROWSE and page != prev:
		if not _is_platform_mode_selected() and NetClient != null and NetClient.is_online_client_connected():
			NetClient.request_list_rooms()

func _sync_page_from_state() -> void:
	var ws_connected := NetClient != null and NetClient.is_online_client_connected()
	var platform_ready := _is_platform_mode_selected() and _platform_entered and PlatformSession != null and PlatformSession.is_logged_in
	var in_room := not _get_current_room_code().is_empty()

	if not ws_connected and not platform_ready:
		_show_page(LobbyPage.CONNECT, false)
		return
	if ws_connected and in_room:
		_show_page(LobbyPage.ROOM, false)
		return

	_show_page(LobbyPage.BROWSE, true)

func _update_top_title() -> void:
	if top_title_label == null or not is_instance_valid(top_title_label):
		return
	match _current_page:
		LobbyPage.CONNECT:
			top_title_label.text = "平台入口" if _is_platform_mode_selected() else "连接服务器"
		LobbyPage.BROWSE:
			top_title_label.text = "房间列表"
		LobbyPage.ROOM:
			top_title_label.text = "房间内"

func _refresh_ui() -> void:
	_ensure_room_renderers()
	var ws_connected := NetClient != null and NetClient.is_online_client_connected()
	var platform_ready := _is_platform_mode_selected() and _platform_entered and PlatformSession != null and PlatformSession.is_logged_in
	connect_button.disabled = _platform_busy or (ws_connected if not _is_platform_mode_selected() else platform_ready)
	disconnect_button.disabled = not ws_connected
	open_create_button.disabled = _platform_busy or (not ws_connected if not _is_platform_mode_selected() else not platform_ready)
	refresh_rooms_button.disabled = not ws_connected
	quick_join_button.disabled = _platform_busy or (not ws_connected if not _is_platform_mode_selected() else not platform_ready)
	if quick_spectate_button != null and is_instance_valid(quick_spectate_button):
		quick_spectate_button.disabled = _platform_busy or not platform_ready
	leave_room_button.disabled = not ws_connected
	if not ws_connected and not platform_ready:
		if connect_status_label.text.strip_edges().is_empty():
			_set_connect_status("未就绪：请选择连接方式并进入。")
	elif platform_ready and not ws_connected:
		if connect_status_label.text.strip_edges().is_empty():
			_set_connect_status("平台已就绪：创建/加入房间将自动连接服务器。")

	if _room_list_controller != null and is_instance_valid(_room_list_controller):
		_room_list_controller.render_room_list(NetContext.room_list if NetContext != null else [])
	if _room_state_renderer != null and is_instance_valid(_room_state_renderer):
		_room_state_renderer.render_room_state(NetContext.room_state if NetContext != null else {})
	_sync_page_from_state()

func _join_room_from_list(room_code: String, password_required: bool) -> void:
	var code := str(room_code).strip_edges().to_upper()
	if code.is_empty():
		return
	if password_required:
		_prompt_password_and_join(code)
		return
	if _is_platform_mode_selected():
		await _platform_join_room(code, "", false)
		return
	if NetClient == null or not NetClient.is_online_client_connected():
		_show_error_dialog("未连接到服务器", "请先连接服务器。")
		_set_browse_status("")
		return
	NetClient.request_join_room(code, "")
	_set_browse_status("")

func _prompt_password_and_join(room_code: String) -> void:
	_ensure_password_dialog()
	_password_dialog_room_code = room_code
	if _password_dialog != null and is_instance_valid(_password_dialog) and _password_dialog.has_method("open_for_room"):
		_password_dialog.call_deferred("open_for_room", room_code, "加入/观战")

func _on_password_dialog_submitted(password: String) -> void:
	var code := str(_password_dialog_room_code).strip_edges().to_upper()
	if code.is_empty():
		return
	if _is_platform_mode_selected():
		await _platform_join_room(code, str(password), false)
		return
	if NetClient == null or not NetClient.is_online_client_connected():
		return
	NetClient.request_join_room(code, str(password))
	_set_browse_status("")

# ── 状态文本 ──

func _set_connect_status(text: String) -> void:
	connect_status_label.text = str(text).strip_edges()

func _set_browse_status(text: String) -> void:
	browse_status_label.text = str(text).strip_edges()

func _set_room_status(text: String) -> void:
	room_status_label.text = str(text).strip_edges()

func _get_current_room_code() -> String:
	if NetContext == null:
		return ""
	return str(NetContext.room_state.get("room_code", "")).strip_edges().to_upper()

# ── 网络信号处理 ──

func _on_net_connected() -> void:
	_set_connect_status("已连接")
	_set_browse_status("")
	_set_room_status("")
	_refresh_ui()
	_show_page(LobbyPage.BROWSE, not _is_platform_mode_selected())

func _on_net_disconnected(reason: String) -> void:
	var r := str(reason).strip_edges()
	if r == "connection_failed":
		var project_path := ProjectSettings.globalize_path("res://")
		var cmd := "godot --headless --path \"%s\" --scene res://server/dedicated_server.tscn -- --port=7000" % project_path
		_set_connect_status("连接失败：无法连接到服务器（请先启动 dedicated server）")
		_show_error_dialog("连接失败", "无法连接到服务器。\n\n若你尚未启动 Dedicated Server，可在项目根目录运行：\n%s" % cmd)
	else:
		_set_connect_status("已断开：%s" % reason)
	_set_browse_status("")
	_set_room_status("")
	_ensure_config_sync_controller()
	if _room_config_sync_controller != null and is_instance_valid(_room_config_sync_controller):
		_room_config_sync_controller.reset()
	_start_game_request_id = ""
	_start_game_flow_in_progress = false
	if SceneManager != null and SceneManager.has_method("hide_loading"):
		SceneManager.hide_loading()
	_refresh_ui()

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
		_ensure_config_sync_controller()
		if _room_config_sync_controller != null and is_instance_valid(_room_config_sync_controller):
			_room_config_sync_controller.on_request_rejected(code, message)
		_refresh_ui()
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

	var c := str(code).strip_edges()
	var m := str(message).strip_edges()
	var mapped: Dictionary = RequestRejectionMapperClass.get_dialog_text(c, m)
	var title := str(mapped.get("title", "请求失败"))
	var body := str(mapped.get("body", ""))

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

# ── 配置同步 ──

func _on_room_config_changed() -> void:
	var room_state: Dictionary = NetContext.room_state if NetContext != null else {}
	_ensure_config_sync_controller()
	var is_host := LobbyViewModelClass.is_host(room_state, int(multiplayer.get_unique_id()))
	if _room_config_sync_controller != null and is_instance_valid(_room_config_sync_controller):
		_room_config_sync_controller.on_room_config_editor_changed(room_state, is_host, _room_config_editor)

func _on_config_debounce_timeout() -> void:
	var room_state: Dictionary = NetContext.room_state if NetContext != null else {}
	_ensure_config_sync_controller()
	var is_host := LobbyViewModelClass.is_host(room_state, int(multiplayer.get_unique_id()))
	if _room_config_sync_controller != null and is_instance_valid(_room_config_sync_controller):
		_room_config_sync_controller.on_debounce_timeout(room_state, is_host, NetClient)
	_set_room_status("")

# ── 餐厅 Logo 选择 ──

func _apply_my_logo_option_selection(logo_id: int) -> void:
	if my_color_option == null or not is_instance_valid(my_color_option):
		return
	if my_color_option.item_count <= 0:
		return
	var idx := 0
	for i in range(my_color_option.item_count):
		var meta_val = my_color_option.get_item_metadata(i)
		if int(meta_val) == int(logo_id):
			idx = i
			break
	_suppress_profile_signals = true
	my_color_option.select(idx)
	_suppress_profile_signals = false

func _write_local_player_profile(name: String, restaurant_logo_id: int) -> void:
	if NetContext == null:
		return
	var p: Dictionary = {}
	if NetContext.player_profile is Dictionary:
		p = Dictionary(NetContext.player_profile)
	p["name"] = str(name).strip_edges()
	if not p.has("color_index"):
		p["color_index"] = 0
	p["restaurant_logo_id"] = int(restaurant_logo_id)
	NetContext.player_profile = p

func _on_my_logo_option_selected(index: int) -> void:
	if _suppress_profile_signals:
		return
	if my_color_option == null or not is_instance_valid(my_color_option):
		return
	var meta_val = my_color_option.get_item_metadata(index)
	var logo_id := int(meta_val)
	_write_local_player_profile(str(player_name_edit.text), logo_id)
	if NetClient == null or not NetClient.is_online_client_connected():
		return
	if _get_current_room_code().is_empty():
		return
	if NetClient.has_method("request_update_player_profile"):
		NetClient.request_update_player_profile(NetContext.player_profile)

# ── 按钮回调 ──

func _on_back_pressed() -> void:
	if NetClient != null:
		NetClient.shutdown()
	if SceneManager != null and SceneManager.has_method("go_back") and SceneManager.go_back():
		return
	if SceneManager != null and SceneManager.has_method("goto_main_menu"):
		SceneManager.goto_main_menu()

func _on_connect_pressed() -> void:
	_write_local_player_profile(
		str(player_name_edit.text),
		int(NetContext.player_profile.get("restaurant_logo_id", -1)) if (NetContext != null and NetContext.player_profile is Dictionary) else -1
	)
	if _is_platform_mode_selected():
		await _platform_enter()
		return
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
	if not _is_platform_mode_selected() and (NetClient == null or not NetClient.is_online_client_connected()):
		_show_error_dialog("未连接到服务器", "请先连接服务器。")
		_set_browse_status("")
		return
	if _is_platform_mode_selected():
		if PlatformSession == null or not PlatformSession.is_logged_in:
			_show_error_dialog("平台未就绪", "请先进入平台（自动游客登录）。")
			_set_browse_status("")
			return
	_ensure_create_room_dialog()
	if _create_room_dialog != null and is_instance_valid(_create_room_dialog):
		_create_room_dialog.open_dialog()

func _on_create_room_dialog_confirmed(desired_player_count: int, room_password: String, config_patch: Dictionary) -> void:
	if _is_platform_mode_selected():
		await _platform_create_room(desired_player_count, room_password, config_patch)
		return
	if NetClient == null or not NetClient.is_online_client_connected():
		_show_error_dialog("未连接到服务器", "请先连接服务器。")
		return
	NetClient.request_create_room(desired_player_count, room_password, config_patch)
	_set_browse_status("")

func _on_refresh_rooms_pressed() -> void:
	if NetClient == null or not NetClient.is_online_client_connected():
		_show_error_dialog("未连接到服务器", "请先连接服务器。")
		_set_browse_status("")
		return
	NetClient.request_list_rooms()
	_set_browse_status("")

func _on_quick_join_pressed() -> void:
	var room_code := str(quick_join_code_edit.text).strip_edges().to_upper()
	if room_code.is_empty():
		_set_browse_status("请输入房间码。")
		return
	var room_password := str(quick_join_password_edit.text)
	if _is_platform_mode_selected():
		await _platform_join_room(room_code, room_password, false)
		return
	if NetClient == null or not NetClient.is_online_client_connected():
		_show_error_dialog("未连接到服务器", "请先连接服务器。")
		_set_browse_status("")
		return
	NetClient.request_join_room(room_code, room_password)
	_set_browse_status("")

func _on_quick_spectate_pressed() -> void:
	var room_code := str(quick_join_code_edit.text).strip_edges().to_upper()
	if room_code.is_empty():
		_set_browse_status("请输入房间码。")
		return
	await _platform_join_room(room_code, "", true)

func _on_leave_room_pressed() -> void:
	if NetClient == null or not NetClient.is_online_client_connected():
		_show_error_dialog("未连接到服务器", "请先连接服务器。")
		_set_room_status("")
		return
	_ensure_config_sync_controller()
	if _room_config_sync_controller != null and is_instance_valid(_room_config_sync_controller):
		_room_config_sync_controller.reset()
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
	var is_host := LobbyViewModelClass.is_host(room_state, int(multiplayer.get_unique_id()))
	if not is_host:
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
		_ensure_config_sync_controller()
		if _room_config_sync_controller != null and is_instance_valid(_room_config_sync_controller):
			_room_config_sync_controller.set_state("error", vr.error)
		_show_error_dialog("无法开始游戏", vr.error)
		_set_room_status("")
		return

	_start_game_flow_in_progress = true
	_refresh_ui()

	if not OS.has_feature("headless"):
		if SceneManager != null and SceneManager.has_method("show_loading"):
			SceneManager.show_loading("正在开始游戏...")
			await get_tree().process_frame

	_ensure_config_sync_controller()
	if _room_config_sync_controller != null and is_instance_valid(_room_config_sync_controller):
		var config_ok: bool = await _room_config_sync_controller.pre_sync_for_start_game(room_state, NetClient, _room_config_editor, 5.0)
		if not config_ok:
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
