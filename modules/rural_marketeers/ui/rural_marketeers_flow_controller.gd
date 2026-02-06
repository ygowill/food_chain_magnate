extends RefCounted

const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const ProductRegistryClass = preload("res://core/data/product_registry.gd")

const GiantBillboardOverlayClass = preload("res://modules/rural_marketeers/ui/components/giant_billboard/giant_billboard_overlay.gd")
const OfframpPlacementOverlayClass = preload("res://modules/rural_marketeers/ui/components/offramp/offramp_placement_overlay.gd")

const MODE_ID_OFFRAMP := "rural_marketeers_offramp"
const OFFRAMP_PENDING_KEY := "rural_marketeers_offramp_pending"
const RURAL_HOUSE_ID := "rural_area"

var _scene = null
var _map_controller = null
var _overlay_controller = null
var _execute_command: Callable = Callable()
var _hide_all: Callable = Callable()

var _billboard_overlay: Control = null
var _offramp_overlay: Control = null

var _offramp_pending_active: bool = false
var _offramp_pending_player_id: int = -1

func _init(scene, map_controller, overlay_controller, execute_command: Callable, hide_all: Callable) -> void:
	_scene = scene
	_map_controller = map_controller
	_overlay_controller = overlay_controller
	_execute_command = execute_command
	_hide_all = hide_all

func hide() -> void:
	if is_instance_valid(_billboard_overlay):
		_billboard_overlay.visible = false
	if is_instance_valid(_offramp_overlay):
		_offramp_overlay.visible = false
	_set_map_mode_overlay(null)
	_clear_offramp_map_mode_if_active()

func get_context_overlay():
	if is_instance_valid(_billboard_overlay) and _billboard_overlay.visible:
		return _billboard_overlay
	if is_instance_valid(_offramp_overlay) and _offramp_overlay.visible:
		return _offramp_overlay
	return null

func try_handle_action_request(action_id: String, params: Dictionary) -> bool:
	var aid := str(action_id).strip_edges()
	if aid != "place_giant_billboard":
		return false
	if _scene == null or _scene.game_engine == null:
		return false
	var state: GameState = _scene.game_engine.get_state()
	if state == null:
		return false
	_show_giant_billboard_overlay(state, params if params != null else {})
	return true

func sync(state: GameState, force_full_refresh: bool = false) -> void:
	_sync_billboard_overlay_lifecycle(state)
	_sync_offramp_flow(state, force_full_refresh)

func _sync_billboard_overlay_lifecycle(state: GameState) -> void:
	if not is_instance_valid(_billboard_overlay) or not _billboard_overlay.visible:
		return
	if state == null:
		_billboard_overlay.visible = false
		return
	if str(state.phase) != DefsClass.PHASE_WORKING or str(state.sub_phase) != DefsClass.SUB_PHASE_MARKETING:
		_billboard_overlay.visible = false
		return

	var current_player_id := int(state.get_current_player_id())
	if NetContext != null and NetContext.mode == NetContext.Mode.ONLINE_CLIENT:
		var local_id := int(NetContext.local_player_id)
		if local_id >= 0 and current_player_id != local_id:
			_billboard_overlay.visible = false

func _sync_offramp_flow(state: GameState, force_full_refresh: bool = false) -> void:
	if state == null:
		_reset_offramp_flow()
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
		_reset_offramp_flow()
		return

	var actor_id := current_player_id
	if is_online and local_player_id >= 0:
		actor_id = local_player_id

	var pending := _is_offramp_pending_for_player(state, actor_id)
	if not pending:
		_reset_offramp_flow()
		return

	var is_new_pending := (not _offramp_pending_active) or (_offramp_pending_player_id != actor_id)
	if is_new_pending:
		_offramp_pending_active = true
		_offramp_pending_player_id = actor_id
		if _overlay_controller != null and _overlay_controller.has_method("show_toast"):
			_overlay_controller.show_toast("里程碑奖励：高速公路出口（请立即放置）")

	# Only actionable in Working/Marketing (executor restricts); keep UI quiet otherwise.
	if str(state.phase) != DefsClass.PHASE_WORKING or str(state.sub_phase) != DefsClass.SUB_PHASE_MARKETING:
		return

	_show_offramp_overlay(state, force_full_refresh)

func _reset_offramp_flow() -> void:
	if is_instance_valid(_offramp_overlay):
		_offramp_overlay.visible = false
	_set_map_mode_overlay(null)
	_clear_offramp_map_mode_if_active()
	_offramp_pending_active = false
	_offramp_pending_player_id = -1

func _is_offramp_pending_for_player(state: GameState, player_id: int) -> bool:
	if state == null or not (state.round_state is Dictionary):
		return false
	var rs: Dictionary = state.round_state
	var pending_val = rs.get(OFFRAMP_PENDING_KEY, null)
	if not (pending_val is Dictionary):
		return false
	var pending: Dictionary = pending_val
	var flag = pending.get(player_id, null)
	if flag == null and pending.has(str(player_id)):
		flag = pending.get(str(player_id), null)
	return bool(flag)

func _show_offramp_overlay(state: GameState, force_full_refresh: bool = false) -> void:
	if _scene == null:
		return
	if _map_controller == null:
		return

	var already_visible := false
	if is_instance_valid(_offramp_overlay):
		already_visible = bool(_offramp_overlay.visible)
	if not already_visible and _hide_all.is_valid():
		_hide_all.call()

	if _offramp_overlay == null:
		_offramp_overlay = OfframpPlacementOverlayClass.new()
		if is_instance_valid(_offramp_overlay):
			if _offramp_overlay.has_signal("placement_confirmed"):
				_offramp_overlay.placement_confirmed.connect(_on_offramp_placement_confirmed)
			_scene.add_child(_offramp_overlay)
			_set_map_mode_overlay(_offramp_overlay)

	if not is_instance_valid(_offramp_overlay):
		return

	_offramp_overlay.visible = true
	_set_map_mode_overlay(_offramp_overlay)

	var need_begin := (not _map_controller.has_method("get_mode")) or str(_map_controller.get_mode()) != MODE_ID_OFFRAMP
	if need_begin or force_full_refresh:
		_map_controller.begin_selection(MODE_ID_OFFRAMP)
		if force_full_refresh and _offramp_overlay.has_method("clear_target"):
			_offramp_overlay.clear_target()

func _on_offramp_placement_confirmed(connect_pos: Vector2i) -> void:
	if _scene == null or _scene.game_engine == null:
		return
	if not _execute_command.is_valid():
		return
	if connect_pos == Vector2i(-1, -1):
		return

	var state: GameState = _scene.game_engine.get_state()
	if state == null:
		return

	var current_player_id := int(state.get_current_player_id())
	var actor_id := current_player_id
	if NetContext != null and NetContext.mode == NetContext.Mode.ONLINE_CLIENT and int(NetContext.local_player_id) >= 0:
		actor_id = int(NetContext.local_player_id)

	var params := {
		"position": [connect_pos.x, connect_pos.y],
	}
	var result: Result = _execute_command.call(Command.create("place_highway_offramp", actor_id, params))
	if result.ok:
		if is_instance_valid(_offramp_overlay):
			_offramp_overlay.visible = false
		_set_map_mode_overlay(null)
		_clear_offramp_map_mode_if_active()
		if _overlay_controller != null:
			_overlay_controller.hide_all_overlays()
	else:
		if is_instance_valid(_offramp_overlay) and _offramp_overlay.has_method("set_validation"):
			_offramp_overlay.set_validation(false, result.error)

func _show_giant_billboard_overlay(state: GameState, params: Dictionary) -> void:
	if _scene == null:
		return

	if str(state.phase) != DefsClass.PHASE_WORKING or str(state.sub_phase) != DefsClass.SUB_PHASE_MARKETING:
		if _overlay_controller != null and _overlay_controller.has_method("show_toast"):
			_overlay_controller.show_toast("当前不在 Working/Marketing，无法使用乡村营销员")
		return

	if not (state.map is Dictionary):
		return
	var houses_val = state.map.get("houses", null)
	if not (houses_val is Dictionary):
		return
	var houses: Dictionary = houses_val
	var rural_val = houses.get(RURAL_HOUSE_ID, null)
	if not (rural_val is Dictionary):
		return
	var rural: Dictionary = rural_val
	var boards_val = rural.get("giant_billboards", null)
	var boards: Dictionary = boards_val if boards_val is Dictionary else {}

	var available_sides: Array[String] = []
	for side in ["N", "E", "S", "W"]:
		if not boards.has(side):
			available_sides.append(side)
	if available_sides.is_empty():
		if _overlay_controller != null and _overlay_controller.has_method("show_toast"):
			_overlay_controller.show_toast("所有乡村巨型广告牌位置已被占用")
		return

	var available_products: Array[String] = []
	if ProductRegistryClass.is_loaded():
		for pid in ProductRegistryClass.get_all_ids():
			var def_val = ProductRegistryClass.get_def(pid)
			if not (def_val is ProductDef):
				continue
			var def: ProductDef = def_val
			if def.has_tag("no_marketing"):
				continue
			if not (def.has_tag("food") or def.has_tag("drink")):
				continue
			available_products.append(pid)

	if available_products.is_empty():
		if _overlay_controller != null and _overlay_controller.has_method("show_toast"):
			_overlay_controller.show_toast("没有可用于乡村广告牌的产品（food/drink）")
		return

	if _hide_all.is_valid():
		_hide_all.call()

	if _billboard_overlay == null:
		_billboard_overlay = GiantBillboardOverlayClass.new()
		if is_instance_valid(_billboard_overlay):
			if _billboard_overlay.has_signal("placement_confirmed"):
				_billboard_overlay.placement_confirmed.connect(_on_billboard_placement_confirmed)
			_scene.add_child(_billboard_overlay)

	if not is_instance_valid(_billboard_overlay):
		return

	if _billboard_overlay.has_method("set_available_sides"):
		_billboard_overlay.set_available_sides(available_sides)
	if _billboard_overlay.has_method("set_available_products"):
		_billboard_overlay.set_available_products(available_products)

	# Optional prefill (debug / future UI integrations).
	var pre_side := str(params.get("side", "")).strip_edges()
	if not pre_side.is_empty() and available_sides.has(pre_side) and _billboard_overlay.has_method("set_selected_side"):
		_billboard_overlay.set_selected_side(pre_side)
	var pre_product := str(params.get("product", "")).strip_edges()
	if not pre_product.is_empty() and available_products.has(pre_product) and _billboard_overlay.has_method("set_selected_product"):
		_billboard_overlay.set_selected_product(pre_product)

	if _billboard_overlay.has_method("set_validation"):
		_billboard_overlay.set_validation(true, "")

	_billboard_overlay.visible = true
	if _overlay_controller != null and _overlay_controller.has_method("show_toast"):
		_overlay_controller.show_toast("请选择巨型广告牌的方向与产品")

func _on_billboard_placement_confirmed(side: String, product: String) -> void:
	if _scene == null or _scene.game_engine == null:
		return
	if not _execute_command.is_valid():
		return

	var state: GameState = _scene.game_engine.get_state()
	if state == null:
		return

	var current_player_id := int(state.get_current_player_id())
	var actor_id := current_player_id
	if NetContext != null and NetContext.mode == NetContext.Mode.ONLINE_CLIENT and int(NetContext.local_player_id) >= 0:
		actor_id = int(NetContext.local_player_id)

	var params := {
		"side": str(side).strip_edges(),
		"product": str(product).strip_edges(),
	}
	var result: Result = _execute_command.call(Command.create("place_giant_billboard", actor_id, params))
	if result.ok:
		if is_instance_valid(_billboard_overlay):
			_billboard_overlay.visible = false
		if _overlay_controller != null:
			_overlay_controller.hide_all_overlays()
	else:
		if is_instance_valid(_billboard_overlay) and _billboard_overlay.has_method("set_validation"):
			_billboard_overlay.set_validation(false, result.error)

func _set_map_mode_overlay(overlay: Node) -> void:
	if _map_controller == null:
		return
	if _map_controller.has_method("set_custom_mode_overlay"):
		_map_controller.set_custom_mode_overlay(MODE_ID_OFFRAMP, overlay)

func _clear_offramp_map_mode_if_active() -> void:
	if _map_controller == null or not _map_controller.has_method("get_mode"):
		return
	if str(_map_controller.get_mode()) == MODE_ID_OFFRAMP:
		_map_controller.clear_selection()
