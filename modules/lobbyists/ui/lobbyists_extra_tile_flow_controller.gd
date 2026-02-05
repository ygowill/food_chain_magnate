extends RefCounted

const LobbyistsExtraTileOverlayScene = preload("res://modules/lobbyists/ui/components/lobbyists_extra_tile/lobbyists_extra_tile_overlay.tscn")
const ChoiceDialogScene = preload("res://ui/dialogs/choice_dialog.tscn")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")

const EXTRA_TILE_PENDING_KEY := "lobbyists_extra_tile_pending"
const MODE_ID := "lobbyists_extra_tile"

var _scene = null
var _map_controller = null
var _overlay_controller = null
var _execute_command: Callable = Callable()
var _hide_all: Callable = Callable()

var _overlay: Control = null
var _choice_dialog: Control = null

var _pending_active: bool = false
var _pending_player_id: int = -1
var _choice: String = "" # "" | "use"

func _init(scene, map_controller, overlay_controller, execute_command: Callable, hide_all: Callable) -> void:
	_scene = scene
	_map_controller = map_controller
	_overlay_controller = overlay_controller
	_execute_command = execute_command
	_hide_all = hide_all

func hide() -> void:
	_hide_choice_dialog()
	if is_instance_valid(_overlay):
		_overlay.visible = false
	_clear_action_panel_context()

func get_context_overlay():
	if is_instance_valid(_overlay) and _overlay.visible:
		return _overlay
	return null

func sync(state: GameState, force_full_refresh: bool = false) -> void:
	# Lobbyists milestone：首个使用说客 -> 立即二选一（使用扩边 / 放弃）
	if state == null:
		_reset_flow()
		return

	var is_online := false
	var local_player_id := -1
	if NetContext != null and NetContext.mode == NetContext.Mode.ONLINE_CLIENT:
		is_online = true
		local_player_id = int(NetContext.local_player_id)

	var current_player_id := int(state.get_current_player_id())
	var is_local_turn := (not is_online) or (local_player_id >= 0 and current_player_id == local_player_id)
	if not is_local_turn:
		_reset_flow()
		return

	var actor_id := current_player_id
	if is_online and local_player_id >= 0:
		actor_id = local_player_id

	var pending := _is_pending_for_player(state, actor_id)
	if not pending:
		_reset_flow()
		return

	var is_new_pending := (not _pending_active) or (_pending_player_id != actor_id)
	if is_new_pending:
		_pending_active = true
		_pending_player_id = actor_id
		_choice = ""
		_hide_choice_dialog()
		_clear_overlay_target()
		if _overlay_controller != null and _overlay_controller.has_method("show_toast"):
			_overlay_controller.show_toast("里程碑奖励：扩边（请立即二选一：使用/放弃）")

	# 只能在 Working/Lobbyists 执行 place/skip（动作执行器限制），因此 UI 也仅在此时激活。
	if str(state.phase) != DefsClass.PHASE_WORKING or str(state.sub_phase) != "Lobbyists":
		return

	# choice 已确定为 use：确保 overlay 存在并保持同步
	if _choice == "use":
		_show_overlay(state, force_full_refresh)
		return

	# 尚未做出选择：弹出二选一窗口（无取消）
	_show_choice_dialog(state, actor_id)

func _reset_flow() -> void:
	_hide_choice_dialog()
	if is_instance_valid(_overlay):
		_overlay.visible = false
	_clear_action_panel_context()
	_set_map_mode_overlay(null)
	if _map_controller != null and _map_controller.has_method("get_mode") and str(_map_controller.get_mode()) == MODE_ID:
		_map_controller.clear_selection()
	_pending_active = false
	_pending_player_id = -1
	_choice = ""

func _is_pending_for_player(state: GameState, player_id: int) -> bool:
	if state == null or not (state.round_state is Dictionary):
		return false
	var rs: Dictionary = state.round_state
	var pending_val = rs.get(EXTRA_TILE_PENDING_KEY, null)
	if not (pending_val is Dictionary):
		return false
	var pending: Dictionary = pending_val
	var flag = pending.get(player_id, null)
	if flag == null and pending.has(str(player_id)):
		flag = pending.get(str(player_id), null)
	return bool(flag)

func _show_choice_dialog(state: GameState, actor_id: int) -> void:
	if _scene == null:
		return
	if is_instance_valid(_choice_dialog) and (_choice_dialog as Control).visible:
		return

	if _choice_dialog == null:
		_choice_dialog = ChoiceDialogScene.instantiate()
		if is_instance_valid(_choice_dialog):
			_scene.add_child(_choice_dialog)
			if _choice_dialog is Control:
				(_choice_dialog as Control).z_index = 950
			if _choice_dialog.has_signal("option_selected"):
				_choice_dialog.option_selected.connect(_on_choice_selected)
			if _choice_dialog.has_signal("cancelled"):
				_choice_dialog.cancelled.connect(_on_choice_cancelled)

	if not is_instance_valid(_choice_dialog):
		return

	var who := "玩家%d" % (actor_id + 1)
	if Globals != null and Globals.has_method("get_player_name"):
		who = str(Globals.get_player_name(actor_id))

	var title := "里程碑奖励：扩边"
	var message := "%s 获得“首个使用说客”里程碑奖励：\n是否立即使用扩边放置一块地图板块？" % who
	var options: Array[Dictionary] = [
		{"id": "use", "text": "使用"},
		{"id": "skip", "text": "放弃"},
	]
	if _choice_dialog.has_method("setup"):
		_choice_dialog.setup(title, message, options, "")
	if _choice_dialog.has_method("open"):
		_choice_dialog.open()

func _hide_choice_dialog() -> void:
	if not is_instance_valid(_choice_dialog):
		return
	if _choice_dialog.has_method("close"):
		_choice_dialog.close()
	elif _choice_dialog is Control:
		(_choice_dialog as Control).visible = false

func _on_choice_selected(option_id: String) -> void:
	var opt := str(option_id).strip_edges()
	if opt == "use":
		_choice = "use"
		if _scene != null and _scene.game_engine != null:
			var state: GameState = _scene.game_engine.get_state()
			if state != null:
				_show_overlay(state, true)
		return

	if opt == "skip":
		var actor_id := _pending_player_id
		_execute_skip(actor_id)
		return

func _on_choice_cancelled() -> void:
	# 本对话框用于“必须当场二选一”，cancel 被隐藏；这里保留兼容处理。
	var actor_id := _pending_player_id
	_execute_skip(actor_id)

func _show_overlay(state: GameState, force_full_refresh: bool = false) -> void:
	if _scene == null or _scene.game_engine == null:
		return
	if _map_controller == null:
		return
	var already_visible := false
	if is_instance_valid(_overlay):
		already_visible = bool(_overlay.visible)
	if not already_visible and _hide_all.is_valid():
		_hide_all.call()

	if _overlay == null:
		_overlay = LobbyistsExtraTileOverlayScene.instantiate()
		if is_instance_valid(_overlay):
			if _overlay.has_signal("placement_confirmed"):
				_overlay.placement_confirmed.connect(_on_overlay_placement_confirmed)
			if _overlay.has_signal("skip_requested"):
				_overlay.skip_requested.connect(_on_overlay_skip_requested)
			if _overlay.has_signal("highlight_requested") and _map_controller != null:
				# NOTE: Callable.bind() appends args after signal args; keep mode_id first.
				_overlay.highlight_requested.connect(_on_overlay_highlight_requested)
			_scene.add_child(_overlay)
			_set_map_mode_overlay(_overlay)

	if not is_instance_valid(_overlay):
		return

	_overlay.visible = true
	if (not already_visible or force_full_refresh) and _overlay.has_method("show_picker"):
		_overlay.show_picker()

	_bind_action_panel_context(_overlay)

	# 进入地图选点模式：高亮有效的扩边边缘格
	if not _map_controller.has_method("get_mode") or str(_map_controller.get_mode()) != MODE_ID or force_full_refresh:
		_map_controller.begin_selection(MODE_ID)
	_sync_overlay_tiles(state)

	if force_full_refresh and _overlay.has_method("clear_target"):
		_overlay.clear_target()

func _on_overlay_highlight_requested(tile_id: String, rotation: int) -> void:
	if _map_controller == null:
		return
	if _map_controller.has_method("notify_custom_mode_highlight"):
		_map_controller.notify_custom_mode_highlight(MODE_ID, tile_id, rotation)

func _sync_overlay_tiles(state: GameState) -> void:
	if state == null:
		return
	if not is_instance_valid(_overlay):
		return

	var remaining: Array[String] = []
	if state.map is Dictionary and state.map.has("tile_supply_remaining") and (state.map["tile_supply_remaining"] is Array):
		for v in Array(state.map["tile_supply_remaining"]):
			var s := str(v).strip_edges()
			if not s.is_empty():
				remaining.append(s)
	remaining.sort()

	if _overlay.has_method("set_available_tiles"):
		_overlay.set_available_tiles(remaining)

func _execute_skip(actor_id: int) -> void:
	if actor_id < 0:
		return
	if _scene == null or _scene.game_engine == null:
		return
	if not _execute_command.is_valid():
		return

	var cmd := Command.create("skip_lobbyists_extra_map_tile", actor_id, {})
	var result: Result = _execute_command.call(cmd)
	if result.ok:
		_choice = ""
		_hide_choice_dialog()
		if is_instance_valid(_overlay):
			_overlay.visible = false
		_clear_action_panel_context()
		_set_map_mode_overlay(null)
		if _map_controller != null:
			_map_controller.clear_selection()
	else:
		if _overlay_controller != null and _overlay_controller.has_method("show_toast"):
			_overlay_controller.show_toast("放弃扩边失败：%s" % str(result.error))

func _on_overlay_skip_requested() -> void:
	var actor_id := _pending_player_id
	_execute_skip(actor_id)

func _on_overlay_placement_confirmed(attach_board_pos: Vector2i, side: String, rotation: int, tile_id: String) -> void:
	if _scene == null or _scene.game_engine == null:
		return
	if not _execute_command.is_valid():
		return
	if tile_id.is_empty() or side.is_empty():
		return

	var state: GameState = _scene.game_engine.get_state()
	if state == null:
		return

	var current_player_id := int(state.get_current_player_id())
	var actor_id := current_player_id
	if NetContext != null and NetContext.mode == NetContext.Mode.ONLINE_CLIENT and int(NetContext.local_player_id) >= 0:
		actor_id = int(NetContext.local_player_id)

	var params := {
		"tile_id": tile_id,
		"attach_to_tile_board_pos": [attach_board_pos.x, attach_board_pos.y],
		"side": side,
		"rotation": int(rotation),
	}
	var result: Result = _execute_command.call(Command.create("place_lobbyists_extra_map_tile", actor_id, params))
	if result.ok:
		_choice = ""
		_hide_choice_dialog()
		if is_instance_valid(_overlay):
			_overlay.visible = false
		_clear_action_panel_context()
		_set_map_mode_overlay(null)
		if _map_controller != null:
			_map_controller.clear_selection()
		if _overlay_controller != null:
			_overlay_controller.hide_all_overlays()
	else:
		if is_instance_valid(_overlay) and _overlay.has_method("set_validation"):
			_overlay.set_validation(false, result.error)

func _bind_action_panel_context(overlay: Node) -> void:
	if _scene == null:
		return
	var ap = _scene.get("action_panel")
	if ap == null or not is_instance_valid(ap):
		return
	if ap.has_method("bind_context_overlay"):
		ap.call("bind_context_overlay", overlay)

func _clear_action_panel_context() -> void:
	if _scene == null:
		return
	var ap = _scene.get("action_panel")
	if ap == null or not is_instance_valid(ap):
		return
	if ap.has_method("clear_context_overlay"):
		ap.call("clear_context_overlay")

func _set_map_mode_overlay(overlay: Node) -> void:
	if _map_controller == null:
		return
	if _map_controller.has_method("set_custom_mode_overlay"):
		_map_controller.set_custom_mode_overlay(MODE_ID, overlay)

func _clear_overlay_target() -> void:
	if not is_instance_valid(_overlay):
		return
	if _overlay.has_method("clear_target"):
		_overlay.clear_target()
