extends RefCounted

const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const CoffeeShopPlacementOverlayClass = preload("res://modules/coffee/ui/components/coffee_shop/coffee_shop_placement_overlay.gd")

const MODE_ID := "coffee_shop_placement"

const ACTION_TRAIN := "place_or_move_coffee_shop"
const ACTION_CLEANUP := "resolve_first_coffee_sold_bonus_coffee_shop"

const CLEANUP_TASK_KIND := "coffee_first_coffee_sold_bonus_coffee_shop"
const TRIGGER_TO_EMPLOYEES: Array[String] = ["barista", "lead_barista"]

var _scene = null
var _map_controller = null
var _overlay_controller = null
var _execute_command: Callable = Callable()
var _hide_all: Callable = Callable()

var _overlay: Control = null

var _train_total_seen: Dictionary = {} # player_id(int) -> total_triggers(int)
var _cleanup_pending_active: bool = false
var _cleanup_pending_player_id: int = -1

func _init(scene, map_controller, overlay_controller, execute_command: Callable, hide_all: Callable) -> void:
	_scene = scene
	_map_controller = map_controller
	_overlay_controller = overlay_controller
	_execute_command = execute_command
	_hide_all = hide_all

func hide() -> void:
	_hide_overlay()

func get_context_overlay():
	if is_instance_valid(_overlay) and _overlay.visible:
		return _overlay
	return null

func try_handle_action_request(action_id: String, _params: Dictionary) -> bool:
	var aid := str(action_id).strip_edges()
	if aid != ACTION_TRAIN and aid != ACTION_CLEANUP:
		return false
	if _scene == null or _scene.game_engine == null:
		return false
	var state: GameState = _scene.game_engine.get_state()
	if state == null:
		return false

	var actor_id := _get_actor_id_for_state(state)
	if actor_id < 0:
		return false

	_show_overlay_for_action(state, actor_id, aid, true)
	return true

func sync(state: GameState, force_full_refresh: bool = false) -> void:
	if state == null:
		_reset_flow()
		return

	# Only drive the flow for the local player on their own turn (avoid accidental remote actions online).
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

	# Cleanup pending task: first coffee sold milestone bonus coffee shop (mandatory)
	var cleanup_pending := _is_cleanup_bonus_pending_for_player(state, actor_id)
	if cleanup_pending and str(state.phase) == DefsClass.PHASE_CLEANUP:
		var is_new_pending := (not _cleanup_pending_active) or (_cleanup_pending_player_id != actor_id)
		if is_new_pending:
			_cleanup_pending_active = true
			_cleanup_pending_player_id = actor_id
			if _overlay_controller != null and _overlay_controller.has_method("show_toast"):
				_overlay_controller.show_toast("里程碑奖励：首杯咖啡（请放置/移动额外咖啡店）")

		_show_overlay_for_action(state, actor_id, ACTION_CLEANUP, force_full_refresh or is_new_pending)
		return

	_cleanup_pending_active = false
	_cleanup_pending_player_id = -1

	# Train triggers: placing/moving coffee shop after training baristas
	var is_train_phase := (str(state.phase) == DefsClass.PHASE_WORKING and str(state.sub_phase) == DefsClass.SUB_PHASE_TRAIN)
	if is_train_phase:
		var total_triggers := _count_train_triggers(state.round_state, actor_id)
		var used_triggers := _get_used_train_triggers(state.round_state, actor_id)
		var remaining := maxi(0, total_triggers - used_triggers)

		var last_seen := int(_train_total_seen.get(actor_id, 0))
		_train_total_seen[actor_id] = total_triggers
		var is_new_trigger := total_triggers > last_seen

		if remaining > 0 and is_new_trigger:
			if _overlay_controller != null and _overlay_controller.has_method("show_toast"):
				_overlay_controller.show_toast("培训触发：可以立即放置/移动咖啡店")
			_show_overlay_for_action(state, actor_id, ACTION_TRAIN, true)
			return

		# Keep the overlay synced if it's already open.
		if _is_overlay_open_for_action(ACTION_TRAIN):
			if remaining <= 0:
				_hide_overlay()
				return
			_sync_overlay_from_state(state, actor_id, ACTION_TRAIN, force_full_refresh)
			return
	else:
		# Leaving Train: close train overlay if still open.
		if _is_overlay_open_for_action(ACTION_TRAIN):
			_hide_overlay()
			return

	# Leaving Cleanup: close cleanup overlay if still open.
	if _is_overlay_open_for_action(ACTION_CLEANUP):
		_hide_overlay()

func _reset_flow() -> void:
	_hide_overlay()
	_cleanup_pending_active = false
	_cleanup_pending_player_id = -1

func _show_overlay_for_action(state: GameState, actor_id: int, action_id: String, force_full_refresh: bool = false) -> void:
	if _scene == null or _map_controller == null:
		return

	var already_visible := is_instance_valid(_overlay) and _overlay.visible
	if not already_visible and _hide_all.is_valid():
		_hide_all.call()

	if _overlay == null:
		_overlay = CoffeeShopPlacementOverlayClass.new()
		if is_instance_valid(_overlay):
			if _overlay.has_signal("placement_confirmed"):
				_overlay.placement_confirmed.connect(_on_overlay_placement_confirmed)
			if _overlay.has_signal("highlight_refresh_requested"):
				_overlay.highlight_refresh_requested.connect(_on_highlight_refresh_requested)
			if _overlay.has_signal("ui_state_changed"):
				_overlay.ui_state_changed.connect(_on_overlay_ui_state_changed)
			_scene.add_child(_overlay)
			if _overlay is Control:
				(_overlay as Control).z_index = 920

	if not is_instance_valid(_overlay):
		return

	_overlay.visible = true
	_set_map_mode_overlay(_overlay)
	_bind_action_panel_context(_overlay)

	_sync_overlay_from_state(state, actor_id, action_id, true)

	var need_begin: bool = (not _map_controller.has_method("get_mode")) or str(_map_controller.get_mode()) != MODE_ID
	if need_begin or force_full_refresh:
		_map_controller.begin_selection(MODE_ID, {"action_id": str(action_id).strip_edges()})
		if force_full_refresh and _overlay.has_method("clear_target"):
			_overlay.clear_target()

func _sync_overlay_from_state(state: GameState, actor_id: int, action_id: String, force_full_refresh: bool = false) -> void:
	if not is_instance_valid(_overlay):
		return
	if state == null:
		return

	var tokens_remaining := _get_tokens_remaining(state, actor_id)
	var mode := "place" if tokens_remaining > 0 else "move"
	var triggers_remaining := 0
	if str(action_id).strip_edges() == ACTION_TRAIN:
		var total_triggers := _count_train_triggers(state.round_state, actor_id)
		var used_triggers := _get_used_train_triggers(state.round_state, actor_id)
		triggers_remaining = maxi(0, total_triggers - used_triggers)

	var shops: Array[Dictionary] = []
	if mode == "move":
		shops = _get_owned_shops(state, actor_id)

	if _overlay.has_method("setup_for_action"):
		_overlay.call("setup_for_action", str(action_id).strip_edges(), mode, tokens_remaining, triggers_remaining, shops)

	if force_full_refresh and _overlay.has_method("set_validation"):
		_overlay.call("set_validation", true, "")

func _on_highlight_refresh_requested() -> void:
	if _map_controller == null or not _map_controller.has_method("get_mode"):
		return
	if str(_map_controller.get_mode()) != MODE_ID:
		return
	if not is_instance_valid(_overlay) or not _overlay.visible:
		return
	var aid := ACTION_TRAIN
	if _overlay.has_method("get_action_id"):
		aid = str(_overlay.call("get_action_id")).strip_edges()
	_map_controller.begin_selection(MODE_ID, {"action_id": aid})

func _on_overlay_placement_confirmed(action_id: String, mode: String, position: Vector2i, from_shop_id: String) -> void:
	if _scene == null or _scene.game_engine == null:
		return
	if not _execute_command.is_valid():
		return
	if position == Vector2i(-1, -1):
		return

	var state: GameState = _scene.game_engine.get_state()
	if state == null:
		return

	var actor_id := _get_actor_id_for_state(state)
	if actor_id < 0:
		return

	var aid := str(action_id).strip_edges()
	if aid.is_empty():
		return

	var params := {
		"mode": str(mode).strip_edges(),
		"position": [position.x, position.y],
	}
	if str(mode).strip_edges() == "move":
		params["from_shop_id"] = str(from_shop_id).strip_edges()

	var result: Result = _execute_command.call(Command.create(aid, actor_id, params))
	if not result.ok:
		if is_instance_valid(_overlay) and _overlay.has_method("set_validation"):
			_overlay.call("set_validation", false, result.error)
		return

	# Refresh after state mutation.
	state = _scene.game_engine.get_state()
	if state == null:
		_hide_overlay()
		return

	if aid == ACTION_TRAIN:
		var total_triggers := _count_train_triggers(state.round_state, actor_id)
		var used_triggers := _get_used_train_triggers(state.round_state, actor_id)
		var remaining := maxi(0, total_triggers - used_triggers)
		_train_total_seen[actor_id] = total_triggers

		if remaining > 0:
			_sync_overlay_from_state(state, actor_id, ACTION_TRAIN, true)
			_map_controller.begin_selection(MODE_ID, {"action_id": ACTION_TRAIN})
			if _overlay_controller != null and _overlay_controller.has_method("show_toast"):
				_overlay_controller.show_toast("仍有 %d 次咖啡店放置/移动窗口" % remaining)
			return

	_hide_overlay()
	if _overlay_controller != null:
		_overlay_controller.hide_all_overlays()

func _on_overlay_ui_state_changed() -> void:
	# Allow "关闭" to exit the flow cleanly: clear map selection/highlights and context.
	if not is_instance_valid(_overlay):
		return
	if _overlay.visible:
		return
	_hide_overlay()

func _hide_overlay() -> void:
	if is_instance_valid(_overlay):
		_overlay.visible = false
	_clear_action_panel_context()
	_set_map_mode_overlay(null)
	if _map_controller != null and _map_controller.has_method("get_mode") and str(_map_controller.get_mode()) == MODE_ID:
		_map_controller.clear_selection()

func _is_overlay_open_for_action(action_id: String) -> bool:
	if not is_instance_valid(_overlay) or not _overlay.visible:
		return false
	if not _overlay.has_method("get_action_id"):
		return false
	return str(_overlay.call("get_action_id")).strip_edges() == str(action_id).strip_edges()

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

func _get_actor_id_for_state(state: GameState) -> int:
	if state == null:
		return -1
	var actor_id := int(state.get_current_player_id())
	if NetContext != null and NetContext.mode == NetContext.Mode.ONLINE_CLIENT and int(NetContext.local_player_id) >= 0:
		actor_id = int(NetContext.local_player_id)
	return actor_id

func _get_tokens_remaining(state: GameState, player_id: int) -> int:
	if state == null or not (state.players is Array):
		return 0
	if player_id < 0 or player_id >= state.players.size():
		return 0
	var p_val = state.players[player_id]
	if not (p_val is Dictionary):
		return 0
	var p: Dictionary = p_val
	var v = p.get("coffee_shop_tokens_remaining", 0)
	if v is int:
		return int(v)
	if v is float:
		var f: float = float(v)
		if f == floor(f):
			return int(f)
	return 0

func _get_owned_shops(state: GameState, player_id: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if state == null or not (state.map is Dictionary):
		return out
	var shops_val = state.map.get("coffee_shops", null)
	if not (shops_val is Dictionary):
		return out
	var shops: Dictionary = shops_val
	for sid_val in shops.keys():
		var shop_val = shops[sid_val]
		if not (shop_val is Dictionary):
			continue
		var shop: Dictionary = shop_val
		if int(shop.get("owner", -1)) != player_id:
			continue
		var sid := str(shop.get("shop_id", sid_val)).strip_edges()
		if sid.is_empty():
			continue
		var pos_val = shop.get("anchor_pos", null)
		var pos: Vector2i = pos_val if pos_val is Vector2i else Vector2i(-1, -1)
		out.append({"shop_id": sid, "anchor_pos": pos})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("shop_id", "")) < str(b.get("shop_id", ""))
	)
	return out

func _count_train_triggers(round_state: Variant, player_id: int) -> int:
	if not (round_state is Dictionary):
		return 0
	var rs: Dictionary = round_state
	var te_val = rs.get("train_events", null)
	if not (te_val is Array):
		return 0
	var train_events: Array = te_val
	var total := 0
	for ev_val in train_events:
		if not (ev_val is Dictionary):
			continue
		var ev: Dictionary = ev_val
		if int(ev.get("player_id", -1)) != player_id:
			continue
		var to_id := str(ev.get("to_employee", "")).strip_edges()
		if TRIGGER_TO_EMPLOYEES.has(to_id):
			total += 1
	return total

func _get_used_train_triggers(round_state: Variant, player_id: int) -> int:
	if not (round_state is Dictionary):
		return 0
	var rs: Dictionary = round_state
	var used_val = rs.get("coffee_shop_triggers_used", null)
	if not (used_val is Dictionary):
		return 0
	var used: Dictionary = used_val
	if used.has(player_id) and used[player_id] is int:
		return int(used[player_id])
	if used.has(str(player_id)) and used[str(player_id)] is int:
		return int(used[str(player_id)])
	return 0

func _is_cleanup_bonus_pending_for_player(state: GameState, player_id: int) -> bool:
	if state == null or not (state.round_state is Dictionary):
		return false
	var rs: Dictionary = state.round_state
	var ppa_val = rs.get("pending_phase_actions", null)
	if not (ppa_val is Dictionary):
		return false
	var ppa: Dictionary = ppa_val
	var list_val = ppa.get(DefsClass.PHASE_CLEANUP, null)
	if not (list_val is Array):
		return false
	var list: Array = list_val
	if list.is_empty():
		return false
	var first = list[0]
	if not (first is Dictionary):
		return false
	var task: Dictionary = first
	if str(task.get("kind", "")).strip_edges() != CLEANUP_TASK_KIND:
		return false
	return int(task.get("player_id", -1)) == player_id
