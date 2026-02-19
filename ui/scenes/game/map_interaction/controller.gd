# Game scene：地图交互控制器
# 负责：map_canvas 选点/hover、营销预览、餐厅/房屋放置选点与预览/高亮
class_name GameMapInteractionController
extends RefCounted

signal mode_changed(mode: String, payload: Dictionary)
signal procure_drinks_source_selected(world_pos: Vector2i)
signal procure_drinks_start_restaurant_selected(restaurant_id: String)
signal procure_drinks_start_restaurant_hovered(restaurant_id: String)

const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")
const MarketingModeClass = preload("res://ui/scenes/game/map_interaction/marketing_mode.gd")
const PlacementModeClass = preload("res://ui/scenes/game/map_interaction/placement_mode.gd")
const DistanceToolControllerClass = preload("res://ui/scenes/game/map_interaction/distance_tool_controller.gd")
const CellsClass = preload("res://core/map/map_runtime/cells.gd")
const StructuresClass = preload("res://core/map/map_runtime/structures.gd")
const MapUtilsClass = preload("res://core/map/map_utils.gd")

var _scene = null
var _map_canvas = null
var _overlay_controller = null
var _marketing_mode = null
var _placement_mode = null
var _distance_tool_controller = null
var _module_modes_loaded: bool = false
var _custom_mode_handlers: Dictionary = {} # mode_id -> handler (RefCounted)
var _custom_mode_overlays: Dictionary = {} # mode_id -> overlay (Node)

var _mode: String = ""
var _payload: Dictionary = {}
var _restaurant_valid_anchors: Dictionary = {} # Vector2i -> true
var _house_valid_anchors: Dictionary = {} # Vector2i -> true
var _piece_valid_anchors: Dictionary = {} # Vector2i -> true
var _marketing_valid_anchors: Dictionary = {} # Vector2i -> true
var _marketing_outside_to_anchor: Dictionary = {} # outside_world_pos(Vector2i) -> {anchor: Vector2i, axis: String, attach: String} (outside marketing)
var _procure_drinks_hover_restaurant_id: String = ""

var marketing_panel = null
var restaurant_placement_overlay = null
var house_placement_overlay = null
var piece_placement_overlay = null

func _init(scene, map_canvas, overlay_controller) -> void:
	_scene = scene
	_map_canvas = map_canvas
	_overlay_controller = overlay_controller
	_marketing_mode = MarketingModeClass.new(self)
	_placement_mode = PlacementModeClass.new(self)
	_distance_tool_controller = DistanceToolControllerClass.new(self, _map_canvas, _overlay_controller)

func connect_signals() -> void:
	if not is_instance_valid(_map_canvas):
		return
	if _map_canvas.has_signal("cell_selected") and not _map_canvas.cell_selected.is_connected(_on_map_cell_selected):
		_map_canvas.cell_selected.connect(_on_map_cell_selected)
	if _map_canvas.has_signal("cell_hovered") and not _map_canvas.cell_hovered.is_connected(_on_map_cell_hovered):
		_map_canvas.cell_hovered.connect(_on_map_cell_hovered)

func dispose() -> void:
	clear_selection()
	_reset_custom_modes()
	_custom_mode_handlers.clear()
	_custom_mode_overlays.clear()
	_module_modes_loaded = false
	_restaurant_valid_anchors.clear()
	_house_valid_anchors.clear()
	_piece_valid_anchors.clear()
	_marketing_valid_anchors.clear()
	_marketing_outside_to_anchor.clear()
	_payload.clear()
	_mode = ""
	_procure_drinks_hover_restaurant_id = ""

	if _marketing_mode != null and _marketing_mode.has_method("dispose"):
		_marketing_mode.dispose()
	if _placement_mode != null and _placement_mode.has_method("dispose"):
		_placement_mode.dispose()
	_marketing_mode = null
	_placement_mode = null
	if _distance_tool_controller != null and _distance_tool_controller.has_method("dispose"):
		_distance_tool_controller.dispose()
	_distance_tool_controller = null

	marketing_panel = null
	restaurant_placement_overlay = null
	house_placement_overlay = null
	piece_placement_overlay = null
	_overlay_controller = null
	_map_canvas = null
	_scene = null

func set_marketing_panel(panel) -> void:
	marketing_panel = panel

func _call_marketing_panel_method(method: String, args: Array = []) -> bool:
	if marketing_panel == null or not is_instance_valid(marketing_panel):
		return false
	if not (marketing_panel is CanvasItem) or not (marketing_panel as CanvasItem).visible:
		return false
	var m := StringName(method)
	if not marketing_panel.has_method(m):
		return false
	marketing_panel.callv(m, args)
	return true

func set_restaurant_placement_overlay(overlay) -> void:
	restaurant_placement_overlay = overlay

func set_house_placement_overlay(overlay) -> void:
	house_placement_overlay = overlay

func set_piece_placement_overlay(overlay) -> void:
	piece_placement_overlay = overlay

func set_custom_mode_overlay(mode_id: String, overlay: Node) -> void:
	var key := str(mode_id).strip_edges()
	if key.is_empty():
		return
	if overlay == null or not is_instance_valid(overlay):
		_custom_mode_overlays.erase(key)
	else:
		_custom_mode_overlays[key] = overlay

func get_custom_mode_overlay(mode_id: String):
	var key := str(mode_id).strip_edges()
	if key.is_empty():
		return null
	return _custom_mode_overlays.get(key, null)

func notify_custom_mode_highlight(mode_id: String, tile_id: String, rotation: int) -> void:
	_ensure_module_modes_loaded()
	var key := str(mode_id).strip_edges()
	if key.is_empty():
		return
	var handler = _custom_mode_handlers.get(key, null)
	if handler != null and is_instance_valid(handler) and handler.has_method("on_highlight_requested"):
		handler.call("on_highlight_requested", tile_id, rotation)

func begin_selection(mode: String, payload: Dictionary = {}) -> void:
	_mode = mode
	_payload = payload.duplicate(true)
	_reset_procure_drinks_restaurant_hover()
	_ensure_module_modes_loaded()
	_restaurant_valid_anchors.clear()
	_house_valid_anchors.clear()
	_piece_valid_anchors.clear()
	_marketing_valid_anchors.clear()
	_marketing_outside_to_anchor.clear()
	if is_instance_valid(_map_canvas) and _map_canvas.has_method("clear_cell_highlights"):
		_map_canvas.call("clear_cell_highlights")
	if is_instance_valid(_map_canvas) and _map_canvas.has_method("clear_move_restaurant_selected_restaurant"):
		_map_canvas.call("clear_move_restaurant_selected_restaurant")
	if _distance_tool_controller != null and _distance_tool_controller.has_method("clear_points_overlay"):
		_distance_tool_controller.clear_points_overlay()
	_reset_custom_modes()

	# 动态控制“地图外围 UI-only 空圈”：仅在需要放置/显示外围 piece 时开启（issue_tracker #64）。
	_update_map_outside_margin_for_mode()

	_emit_mode_changed()
	if _mode == "procure_drinks":
		_sync_procure_drinks_highlights()

func clear_selection() -> void:
	var old_mode := _mode
	_mode = ""
	_payload.clear()
	_reset_procure_drinks_restaurant_hover()
	if is_instance_valid(_map_canvas) and _map_canvas.has_method("clear_structure_preview"):
		_map_canvas.call("clear_structure_preview")
	if is_instance_valid(_map_canvas) and _map_canvas.has_method("clear_cell_highlights"):
		_map_canvas.call("clear_cell_highlights")
	if is_instance_valid(_map_canvas) and _map_canvas.has_method("clear_move_restaurant_selected_restaurant"):
		_map_canvas.call("clear_move_restaurant_selected_restaurant")
	if _distance_tool_controller != null and _distance_tool_controller.has_method("clear_points_overlay"):
		_distance_tool_controller.clear_points_overlay()
	_reset_custom_modes()

	# 退出任何选点模式后，如果不再需要外围空圈则恢复（issue_tracker #64）。
	_update_map_outside_margin_for_mode()

	_restaurant_valid_anchors.clear()
	_house_valid_anchors.clear()
	_piece_valid_anchors.clear()
	_marketing_valid_anchors.clear()
	_marketing_outside_to_anchor.clear()
	if old_mode == "distance_tool":
		if _distance_tool_controller != null and _distance_tool_controller.has_method("on_mode_cleared"):
			_distance_tool_controller.on_mode_cleared()
	_emit_mode_changed()

func get_mode() -> String:
	return _mode

func _ensure_module_modes_loaded() -> void:
	if _module_modes_loaded:
		return
	if _scene == null or _scene.game_engine == null:
		return

	var engine: GameEngine = _scene.game_engine
	var manifests: Dictionary = engine.module_manifests_v2
	var plan: Array[String] = engine.get_module_plan_v2() if engine.has_method("get_module_plan_v2") else []

	for mid in plan:
		var manifest_val = manifests.get(mid, null)
		if not (manifest_val is ModuleManifest):
			continue
		var manifest: ModuleManifest = manifest_val
		var provides: Dictionary = manifest.provides
		var ui_val = provides.get("ui", null)
		if not (ui_val is Dictionary):
			continue
		var ui: Dictionary = ui_val
		var modes_val = ui.get("map_interaction_modes", null)
		if not (modes_val is Array):
			continue

		for mv in Array(modes_val):
			if not (mv is Dictionary):
				continue
			var d: Dictionary = mv
			var mode_id := str(d.get("id", d.get("mode", ""))).strip_edges()
			if mode_id.is_empty() or _custom_mode_handlers.has(mode_id):
				continue
			var script_path := str(d.get("script", "")).strip_edges()
			if script_path.is_empty():
				continue
			var res = load(script_path)
			if not (res is Script):
				continue
			var handler = (res as Script).new(self)
			if handler == null:
				continue
			_custom_mode_handlers[mode_id] = handler

	_module_modes_loaded = true

func _reset_custom_modes() -> void:
	for h in _custom_mode_handlers.values():
		if h != null and is_instance_valid(h) and h.has_method("reset"):
			h.call("reset")

func _emit_mode_changed() -> void:
	mode_changed.emit(_mode, _payload.duplicate(true))

func toggle_distance_tool() -> void:
	if _distance_tool_controller != null and _distance_tool_controller.has_method("toggle_distance_tool"):
		_distance_tool_controller.toggle_distance_tool()

func try_select_procure_drinks_start_restaurant_by_index(index: int) -> bool:
	var idx := int(index)
	if idx <= 0:
		return false
	if _mode != "procure_drinks":
		return false
	var emp_type := str(_payload.get("employee_type", "")).strip_edges()
	if emp_type.is_empty() or emp_type == "errand_boy":
		return false
	if _scene == null or _scene.game_engine == null:
		return false
	var state: GameState = _scene.game_engine.get_state()
	if state == null:
		return false
	var restaurants_val = state.map.get("restaurants", null)
	if not (restaurants_val is Dictionary):
		return false
	var restaurants: Dictionary = restaurants_val

	var player_id := state.get_current_player_id()
	var ids: Array[String] = []
	for rid_val in restaurants.keys():
		if not (rid_val is String):
			continue
		var rid := str(rid_val)
		var rest_val = restaurants.get(rid, null)
		if not (rest_val is Dictionary):
			continue
		var rest: Dictionary = rest_val
		if int(rest.get("owner", -1)) != player_id:
			continue
		ids.append(rid)
	ids.sort()
	if idx > ids.size():
		return false

	var pick := str(ids[idx - 1]).strip_edges()
	if pick.is_empty():
		return false
	procure_drinks_start_restaurant_selected.emit(pick)
	return true

func _on_map_cell_selected(world_pos: Vector2i) -> void:
	if world_pos == Vector2i(-1, -1):
		return

	match _mode:
		"procure_drinks":
			var emp_type := str(_payload.get("employee_type", ""))
			if _scene == null or _scene.game_engine == null:
				# 兼容：在没有 scene/engine 的最小测试中，air procure 仍然允许选点（不依赖 state）。
				if _is_air_procure_employee(emp_type):
					procure_drinks_source_selected.emit(world_pos)
				return
			var state: GameState = _scene.game_engine.get_state()
			if state == null:
				return

			# 点击餐厅：在多餐厅时用于选择“起点餐厅”；只响应当前玩家的餐厅。
			if emp_type != "errand_boy":
				var rest_id := _resolve_procure_drinks_owned_restaurant_id_at(state, world_pos)
				if not rest_id.is_empty():
					procure_drinks_start_restaurant_selected.emit(rest_id)
					return

			if _is_air_procure_employee(emp_type):
				procure_drinks_source_selected.emit(world_pos)
				return
			var sources_val = state.map.get("drink_sources", null)
			if not (sources_val is Array):
				return
			var sources: Array = sources_val
			for s_val in sources:
				if not (s_val is Dictionary):
					continue
				var s: Dictionary = s_val
				var wp = s.get("world_pos", null)
				if wp is Vector2i and Vector2i(wp) == world_pos:
					procure_drinks_source_selected.emit(world_pos)
					return
		"marketing":
			if _marketing_mode != null:
				_marketing_mode.on_cell_selected(world_pos)
		"restaurant_placement":
			# 仅允许点击“高亮的合法格”
			if _restaurant_valid_anchors.is_empty() or not _restaurant_valid_anchors.has(world_pos):
				if is_instance_valid(restaurant_placement_overlay) and restaurant_placement_overlay.visible and restaurant_placement_overlay.has_method("set_validation"):
					restaurant_placement_overlay.set_validation(false, "请选择高亮的可放置格")
				return
			if is_instance_valid(restaurant_placement_overlay) and restaurant_placement_overlay.visible and restaurant_placement_overlay.has_method("set_selected_position"):
				restaurant_placement_overlay.set_selected_position(world_pos)
				_maybe_auto_confirm_placement(restaurant_placement_overlay)
		"house_placement":
			var action_id := str(_payload.get("action_id", ""))
			if action_id == "place_house":
				if _house_valid_anchors.is_empty() or not _house_valid_anchors.has(world_pos):
					return
			if is_instance_valid(house_placement_overlay) and house_placement_overlay.visible and house_placement_overlay.has_method("set_selected_position"):
				house_placement_overlay.set_selected_position(world_pos)
				_maybe_auto_confirm_placement(house_placement_overlay)
		"piece_placement":
			# 仅允许点击“高亮的合法格”
			if _piece_valid_anchors.is_empty() or not _piece_valid_anchors.has(world_pos):
				if is_instance_valid(piece_placement_overlay) and piece_placement_overlay.visible and piece_placement_overlay.has_method("set_validation"):
					piece_placement_overlay.set_validation(false, "请选择高亮的可放置格")
				return
			if is_instance_valid(piece_placement_overlay) and piece_placement_overlay.visible and piece_placement_overlay.has_method("set_selected_position"):
				piece_placement_overlay.set_selected_position(world_pos)
				_maybe_auto_confirm_placement(piece_placement_overlay)
		"distance_tool":
			if _distance_tool_controller != null and _distance_tool_controller.has_method("on_cell_selected"):
				_distance_tool_controller.on_cell_selected(world_pos)
		_:
			var handler = _custom_mode_handlers.get(_mode, null)
			if handler != null and is_instance_valid(handler) and handler.has_method("on_cell_selected"):
				handler.call("on_cell_selected", world_pos)

func _update_map_outside_margin_for_mode() -> void:
	if not is_instance_valid(_map_canvas):
		return
	if not _map_canvas.has_method("set_ui_outside_margin_override"):
		return

	_ensure_module_modes_loaded()

	var requested := 0
	if _mode == "marketing":
		var mt := str(_payload.get("marketing_type", "")).strip_edges()
		if mt == "airplane":
			requested = 2
	var handler = _custom_mode_handlers.get(_mode, null)
	if handler != null and is_instance_valid(handler) and handler.has_method("get_outside_margin_override"):
		requested = int(handler.call("get_outside_margin_override"))

	var changed := bool(_map_canvas.call("set_ui_outside_margin_override", requested))
	if changed:
		_request_map_view_fit()

func _request_map_view_fit() -> void:
	# MapCanvas 位于 MapView(Content/Canvas) 之下：向上查找带有 fit_to_view() 的父节点并触发。
	if not is_instance_valid(_map_canvas):
		return
	var state: GameState = null
	if _scene != null and _scene.game_engine != null:
		state = _scene.game_engine.get_state()
	var n: Node = _map_canvas.get_parent()
	while is_instance_valid(n):
		# 优先走 MapView.set_game_state：可同步 MapView 的 auto-fit 缓存，避免后续 _update_ui 时重复触发 auto-fit。
		if state != null and n.has_method("set_game_state"):
			n.call_deferred("set_game_state", state)
			return
		if n.has_method("fit_to_view"):
			n.call_deferred("fit_to_view")
			return
		n = n.get_parent()

func _sync_procure_drinks_highlights() -> void:
	if not is_instance_valid(_map_canvas):
		return
	var emp_type := str(_payload.get("employee_type", ""))
	if _is_air_procure_employee(emp_type):
		if _map_canvas.has_method("clear_cell_highlights"):
			_map_canvas.call("clear_cell_highlights")
		return
	if _scene == null or _scene.game_engine == null:
		return
	var state: GameState = _scene.game_engine.get_state()
	if state == null:
		return

	var sources_val = state.map.get("drink_sources", null)
	if not (sources_val is Array):
		return
	var sources: Array = sources_val

	var cells: Array[Vector2i] = []
	for s_val in sources:
		if not (s_val is Dictionary):
			continue
		var s: Dictionary = s_val
		var wp = s.get("world_pos", null)
		if wp is Vector2i:
			cells.append(Vector2i(wp))

	if _map_canvas.has_method("set_cell_highlights"):
		_map_canvas.call("set_cell_highlights", cells)

func _sync_procure_drinks_hovered_restaurant(world_pos: Vector2i) -> void:
	var rid := ""
	if world_pos != Vector2i(-1, -1):
		var emp_type := str(_payload.get("employee_type", "")).strip_edges()
		if not emp_type.is_empty() and emp_type != "errand_boy":
			if _scene != null and _scene.game_engine != null:
				var state: GameState = _scene.game_engine.get_state()
				if state != null:
					rid = _resolve_procure_drinks_owned_restaurant_id_at(state, world_pos)
	_set_procure_drinks_hover_restaurant_id(rid)

func _set_procure_drinks_hover_restaurant_id(restaurant_id: String) -> void:
	var next := str(restaurant_id).strip_edges()
	if _procure_drinks_hover_restaurant_id == next:
		return
	_procure_drinks_hover_restaurant_id = next
	procure_drinks_start_restaurant_hovered.emit(_procure_drinks_hover_restaurant_id)

func _reset_procure_drinks_restaurant_hover() -> void:
	_set_procure_drinks_hover_restaurant_id("")

func _resolve_procure_drinks_owned_restaurant_id_at(state: GameState, world_pos: Vector2i) -> String:
	if state == null:
		return ""
	if not (state.map is Dictionary):
		return ""
	var restaurants_val = state.map.get("restaurants", null)
	if not (restaurants_val is Dictionary):
		return ""
	var restaurants: Dictionary = restaurants_val
	var player_id := state.get_current_player_id()

	# entrance_pos -> rest_id（仅限当前玩家的餐厅）
	var id_by_entrance: Dictionary = {}
	for rid_val in restaurants.keys():
		if not (rid_val is String):
			continue
		var rid := str(rid_val)
		var rest_val = restaurants.get(rid, null)
		if not (rest_val is Dictionary):
			continue
		var rest: Dictionary = rest_val
		if int(rest.get("owner", -1)) != player_id:
			continue
		var ep = rest.get("entrance_pos", null)
		if ep is Vector2i:
			id_by_entrance[Vector2i(ep)] = rid

	# 优先用 MapCanvas 的 structure 索引：允许点击餐厅占地任意格（不仅是入口格）
	if is_instance_valid(_map_canvas):
		var structures_val = _map_canvas.get("_structures_by_anchor")
		if structures_val is Dictionary:
			var structures: Dictionary = structures_val
			var origin := Vector2i.ZERO
			if _map_canvas.has_method("get_world_origin"):
				var wo = _map_canvas.call("get_world_origin")
				if wo is Vector2i:
					origin = Vector2i(wo)
			var view_pos := world_pos - origin

			for anchor_val in structures.keys():
				if not (anchor_val is Vector2i):
					continue
				var anchor: Vector2i = anchor_val
				var info_val = structures.get(anchor, null)
				if not (info_val is Dictionary):
					continue
				var info: Dictionary = info_val
				if str(info.get("piece_id", "")) != "restaurant":
					continue
				if int(info.get("owner", -1)) != player_id:
					continue
				var min_pos_val = info.get("min", null)
				var max_pos_val = info.get("max", null)
				if not (min_pos_val is Vector2i) or not (max_pos_val is Vector2i):
					continue
				var min_pos: Vector2i = min_pos_val
				var max_pos: Vector2i = max_pos_val
				if view_pos.x < min_pos.x or view_pos.x > max_pos.x or view_pos.y < min_pos.y or view_pos.y > max_pos.y:
					continue
				var found = id_by_entrance.get(anchor, "")
				if found is String and not str(found).is_empty():
					return str(found)

	var direct = id_by_entrance.get(world_pos, "")
	if direct is String:
		return str(direct)
	return ""

func _is_air_procure_employee(employee_type: String) -> bool:
	if employee_type.is_empty():
		return false
	if EmployeeRegistryClass.is_loaded():
		var def_val = EmployeeRegistryClass.get_def(employee_type)
		if def_val != null and (def_val is EmployeeDef):
			var def: EmployeeDef = def_val
			return str(def.range_type) == "air"
	return employee_type == "zeppelin_pilot"

func _should_auto_confirm_placement() -> bool:
	# confirm_actions=false：进入“快速模式”，点击合法目标即可直接执行（不需要右侧确认按钮）
	if Globals == null:
		return false
	return not bool(Globals.confirm_actions)

func _maybe_auto_confirm_placement(overlay: Node) -> void:
	if not _should_auto_confirm_placement():
		return
	if overlay == null or not is_instance_valid(overlay):
		return
	if not overlay.has_method("can_confirm"):
		return
	if not bool(overlay.call("can_confirm")):
		return
	if not overlay.has_method("request_confirm"):
		return
	overlay.call_deferred("request_confirm")

# Distance tool helpers moved to `game_map_interaction_distance_tool_controller.gd`.

func _on_map_cell_hovered(world_pos: Vector2i) -> void:
	_ensure_module_modes_loaded()
	var handler = _custom_mode_handlers.get(_mode, null)
	if handler != null and is_instance_valid(handler) and handler.has_method("on_cell_hovered"):
		handler.call("on_cell_hovered", world_pos)
		return
	if _mode == "procure_drinks":
		_sync_procure_drinks_hovered_restaurant(world_pos)
		return
	if _mode == "marketing":
		if _marketing_mode != null:
			_marketing_mode.on_cell_hovered(world_pos)

func on_marketing_map_selection_requested(marketing_type: String, employee_type: String = "", board_number: int = 0, rotation: int = 0) -> void:
	begin_selection("marketing", {
		"marketing_type": marketing_type,
		"employee_type": employee_type,
		"board_number": board_number,
		"rotation": rotation,
	})
	if _overlay_controller != null:
		_overlay_controller.hide_marketing_range_overlay()
	_sync_marketing_highlights()

func _sync_marketing_highlights() -> void:
	if _marketing_mode != null:
		_marketing_mode.sync_highlights()

func on_restaurant_preview_cleared() -> void:
	if _placement_mode != null:
		_placement_mode.on_restaurant_preview_cleared()

func on_restaurant_highlight_requested(mode: String, rotation: int, restaurant_id: String) -> void:
	if _placement_mode != null:
		_placement_mode.on_restaurant_highlight_requested(mode, rotation, restaurant_id)

func on_house_highlight_requested(action_id: String, rotation: int) -> void:
	if _placement_mode != null:
		_placement_mode.on_house_highlight_requested(action_id, rotation)

func on_house_preview_cleared() -> void:
	if _placement_mode != null:
		_placement_mode.on_house_preview_cleared()

func on_restaurant_preview_requested(mode: String, position: Vector2i, rotation: int, restaurant_id: String) -> void:
	if _placement_mode != null:
		_placement_mode.on_restaurant_preview_requested(mode, position, rotation, restaurant_id)

func on_house_preview_requested(action_id: String, position: Vector2i, rotation: int) -> void:
	if _placement_mode != null:
		_placement_mode.on_house_preview_requested(action_id, position, rotation)

func on_piece_highlight_requested(action_id: String, rotation: int, piece_id: String) -> void:
	if _placement_mode != null:
		_placement_mode.on_piece_highlight_requested(action_id, rotation, piece_id)

func on_piece_preview_cleared() -> void:
	if _placement_mode != null:
		_placement_mode.on_piece_preview_cleared()

func on_piece_preview_requested(action_id: String, position: Vector2i, rotation: int, piece_id: String) -> void:
	if _placement_mode != null:
		_placement_mode.on_piece_preview_requested(action_id, position, rotation, piece_id)
