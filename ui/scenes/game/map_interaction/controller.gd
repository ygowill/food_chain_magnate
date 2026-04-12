# Game scene：地图交互控制器
# 负责：map_canvas 选点/hover、营销预览、餐厅/房屋放置选点与预览/高亮
class_name GameMapInteractionController
extends RefCounted

signal mode_changed(mode: String, payload: Dictionary)
signal procure_drinks_source_selected(world_pos: Vector2i)
signal procure_drinks_start_restaurant_selected(restaurant_id: String)
signal procure_drinks_start_restaurant_hovered(restaurant_id: String)

const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")
const ProductRegistryClass = preload("res://core/data/product_registry.gd")
const MarketingModeClass = preload("res://ui/scenes/game/map_interaction/marketing_mode.gd")
const PlacementModeClass = preload("res://ui/scenes/game/map_interaction/placement_mode.gd")
const DistanceToolControllerClass = preload("res://ui/scenes/game/map_interaction/distance_tool_controller.gd")
const CellsClass = preload("res://core/map/map_runtime/cells.gd")
const StructuresClass = preload("res://core/map/map_runtime/structures.gd")
const MapUtilsClass = preload("res://core/map/map_utils.gd")
const HouseNumberManagerClass = preload("res://core/map/house_number_manager.gd")

const ROUND_STATE_OPENING_SOON_RESTAURANTS_KEY := "opening_soon_restaurants"
const MAP_TOOLTIP_KEY_HOUSE := "map_hover_house"
const MAP_TOOLTIP_KEY_RESTAURANT := "map_hover_restaurant"
const MAP_TOOLTIP_KEY_DRINK_SOURCE := "map_hover_drink_source"

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
var _suspended_mode_for_distance_tool: String = ""
var _suspended_payload_for_distance_tool: Dictionary = {}
var _restaurant_valid_anchors: Dictionary = {} # Vector2i -> true
var _house_valid_anchors: Dictionary = {} # Vector2i -> true
var _piece_valid_anchors: Dictionary = {} # Vector2i -> true
var _marketing_valid_anchors: Dictionary = {} # Vector2i -> true
var _marketing_outside_to_anchor: Dictionary = {} # outside_world_pos(Vector2i) -> {anchor: Vector2i, axis: String, attach: String} (outside marketing)
var _procure_drinks_hover_restaurant_id: String = ""
var _map_hover_tooltip_key: String = ""
var _map_hover_tooltip_title: String = ""
var _map_hover_tooltip_content: String = ""

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
	_clear_suspended_distance_tool_state()
	_procure_drinks_hover_restaurant_id = ""
	_hide_map_hover_tooltip()

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
	if str(mode) != "distance_tool":
		_clear_suspended_distance_tool_state()
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
	_clear_suspended_distance_tool_state()
	_reset_procure_drinks_restaurant_hover()
	_hide_map_hover_tooltip()
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

func can_suspend_current_mode_for_distance_tool() -> bool:
	if _mode != "restaurant_placement":
		return false
	if not is_instance_valid(restaurant_placement_overlay) or not restaurant_placement_overlay.visible:
		return false
	return true

func suspend_current_mode_for_distance_tool() -> bool:
	if not can_suspend_current_mode_for_distance_tool():
		return false
	_suspended_mode_for_distance_tool = _mode
	_suspended_payload_for_distance_tool = _payload.duplicate(true)
	if _placement_mode != null and _placement_mode.has_method("on_restaurant_preview_cleared"):
		_placement_mode.on_restaurant_preview_cleared()
	begin_selection("distance_tool")
	return true

func resume_suspended_mode_from_distance_tool() -> bool:
	if _suspended_mode_for_distance_tool.is_empty():
		return false
	var restore_mode := _suspended_mode_for_distance_tool
	var restore_payload := _suspended_payload_for_distance_tool.duplicate(true)
	_clear_suspended_distance_tool_state()
	begin_selection(restore_mode, restore_payload)
	_restore_mode_after_distance_tool(restore_mode)
	return true

func _clear_suspended_distance_tool_state() -> void:
	_suspended_mode_for_distance_tool = ""
	_suspended_payload_for_distance_tool.clear()

func _restore_mode_after_distance_tool(mode: String) -> void:
	match str(mode).strip_edges():
		"restaurant_placement":
			_restore_restaurant_placement_after_distance_tool()

func _restore_restaurant_placement_after_distance_tool() -> void:
	if not is_instance_valid(restaurant_placement_overlay) or not restaurant_placement_overlay.visible:
		return

	var overlay_mode := "place_restaurant"
	if restaurant_placement_overlay.has_method("get_mode"):
		overlay_mode = str(restaurant_placement_overlay.get_mode()).strip_edges()

	var rotation := 0
	if restaurant_placement_overlay.has_method("get_selected_rotation"):
		rotation = int(restaurant_placement_overlay.get_selected_rotation())

	var restaurant_id := ""
	if restaurant_placement_overlay.has_method("get_selected_restaurant"):
		restaurant_id = str(restaurant_placement_overlay.get_selected_restaurant()).strip_edges()

	on_restaurant_highlight_requested(overlay_mode, rotation, restaurant_id)

	if restaurant_placement_overlay.has_method("get_selected_position"):
		var pos_val = restaurant_placement_overlay.get_selected_position()
		if pos_val is Vector2i:
			var pos := Vector2i(pos_val)
			if pos != Vector2i(-1, -1):
				on_restaurant_preview_requested(overlay_mode, pos, rotation, restaurant_id)
				return

	on_restaurant_preview_cleared()

func _ensure_module_modes_loaded() -> void:
	if _module_modes_loaded:
		return
	if _scene == null or _scene.game_engine == null:
		return

	var engine_val = _scene.game_engine
	if not (engine_val is GameEngine):
		return
	var engine: GameEngine = engine_val
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
	_sync_map_hover_tooltip(world_pos)
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

func _sync_map_hover_tooltip(world_pos: Vector2i) -> void:
	if not _can_show_map_hover_tooltip():
		_hide_map_hover_tooltip()
		return
	var mgr = _get_help_tooltip_manager()
	if mgr == null or not is_instance_valid(mgr):
		_map_hover_tooltip_key = ""
		_map_hover_tooltip_title = ""
		_map_hover_tooltip_content = ""
		return
	if world_pos == Vector2i(-1, -1):
		_hide_map_hover_tooltip(mgr)
		return

	var tip := _build_map_hover_tooltip(world_pos)
	if tip.is_empty():
		_hide_map_hover_tooltip(mgr)
		return

	var key := str(tip.get("key", "")).strip_edges()
	var title := str(tip.get("title", "")).strip_edges()
	var content := str(tip.get("content", "")).strip_edges()
	if key.is_empty() or title.is_empty() or content.is_empty():
		_hide_map_hover_tooltip(mgr)
		return

	var changed := (key != _map_hover_tooltip_key or title != _map_hover_tooltip_title or content != _map_hover_tooltip_content)
	if changed:
		if mgr.has_method("add_help_entry"):
			mgr.call("add_help_entry", key, title, content)
		_map_hover_tooltip_key = key
		_map_hover_tooltip_title = title
		_map_hover_tooltip_content = content

	var pos := _resolve_map_hover_tooltip_position(world_pos)
	if mgr.has_method("show_immediate"):
		mgr.call("show_immediate", key, pos)
	elif mgr.has_method("request_tooltip"):
		if changed:
			mgr.call("request_tooltip", key, pos)

func _hide_map_hover_tooltip(manager = null) -> void:
	var mgr = manager
	if mgr == null:
		mgr = _get_help_tooltip_manager()
	if mgr != null and is_instance_valid(mgr):
		if mgr.has_method("hide_tooltip"):
			mgr.call("hide_tooltip")
	_map_hover_tooltip_key = ""
	_map_hover_tooltip_title = ""
	_map_hover_tooltip_content = ""

func _can_show_map_hover_tooltip() -> bool:
	if Globals == null:
		return true
	return bool(Globals.show_hints)

func _get_help_tooltip_manager():
	if _overlay_controller == null or not is_instance_valid(_overlay_controller):
		return null
	if _overlay_controller.has_method("get_help_tooltip_manager"):
		return _overlay_controller.call("get_help_tooltip_manager")
	return null

func _resolve_map_hover_tooltip_position(world_pos: Vector2i) -> Vector2:
	if _map_canvas != null and is_instance_valid(_map_canvas):
		if _map_canvas.has_method("get_viewport"):
			var viewport = _map_canvas.get_viewport()
			if viewport != null and is_instance_valid(viewport):
				return viewport.get_mouse_position()
		if _map_canvas is Control:
			var world_origin := Vector2i.ZERO
			if _map_canvas.has_method("get_world_origin"):
				var wo = _map_canvas.call("get_world_origin")
				if wo is Vector2i:
					world_origin = Vector2i(wo)
			var cell_size := 40
			if _map_canvas.has_method("get_cell_size"):
				var cs = _map_canvas.call("get_cell_size")
				if cs is int:
					cell_size = int(cs)
			var view_pos := world_pos - world_origin
			var local_pos := Vector2((float(view_pos.x) + 0.5) * float(cell_size), (float(view_pos.y) + 0.5) * float(cell_size))
			return (_map_canvas as Control).get_global_position() + local_pos
	return Vector2.ZERO

func _build_map_hover_tooltip(world_pos: Vector2i) -> Dictionary:
	var state := _get_current_state()
	if state == null:
		return {}
	var cell := _get_cell_world(state, world_pos)
	if cell.is_empty():
		return {}

	var house_id := _resolve_house_id(state, world_pos, cell)
	if not house_id.is_empty():
		return _build_house_tooltip_data(state, house_id)

	var restaurant_info := _resolve_restaurant_info(state, world_pos, cell)
	if not restaurant_info.is_empty():
		return _build_restaurant_tooltip_data(state, restaurant_info)

	var drink_source_val = cell.get("drink_source", null)
	if drink_source_val is Dictionary:
		var drink_source: Dictionary = drink_source_val
		if not drink_source.is_empty():
			return _build_drink_source_tooltip_data(state, world_pos, drink_source)
	return {}

func _get_current_state() -> GameState:
	if _scene == null or _scene.game_engine == null:
		return null
	if not _scene.game_engine.has_method("get_state"):
		return null
	var s = _scene.game_engine.get_state()
	if s is GameState:
		return s
	return null

func _get_cell_world(state: GameState, world_pos: Vector2i) -> Dictionary:
	if _map_canvas != null and is_instance_valid(_map_canvas) and _map_canvas.has_method("_get_cell_world"):
		var cell_val = _map_canvas.call("_get_cell_world", world_pos)
		if cell_val is Dictionary:
			return cell_val

	if state == null or not (state.map is Dictionary):
		return {}
	var map_data: Dictionary = state.map
	var map_origin: Vector2i = map_data.get("map_origin", Vector2i.ZERO)
	var idx := world_pos + map_origin
	var grid_size: Vector2i = map_data.get("grid_size", Vector2i.ZERO)
	if grid_size != Vector2i.ZERO and MapUtilsClass.is_valid_pos(idx, grid_size):
		var cells_val = map_data.get("cells", null)
		if cells_val is Array:
			var cells: Array = cells_val
			if idx.y >= 0 and idx.y < cells.size():
				var row_val = cells[idx.y]
				if row_val is Array:
					var row: Array = row_val
					if idx.x >= 0 and idx.x < row.size():
						var cell_val2 = row[idx.x]
						if cell_val2 is Dictionary:
							return cell_val2

	var external_cells_val = map_data.get("external_cells", null)
	if external_cells_val is Dictionary:
		var external_cells: Dictionary = external_cells_val
		var key := "%d,%d" % [world_pos.x, world_pos.y]
		var ext_val = external_cells.get(key, null)
		if ext_val is Dictionary:
			return ext_val

	return {}

func _resolve_house_id(state: GameState, world_pos: Vector2i, cell: Dictionary) -> String:
	var structure_val = cell.get("structure", null)
	if structure_val is Dictionary:
		var structure: Dictionary = structure_val
		var hid := str(structure.get("house_id", "")).strip_edges()
		if not hid.is_empty():
			return hid

	if state == null or not (state.map is Dictionary):
		return ""
	var houses_val = state.map.get("houses", null)
	if not (houses_val is Dictionary):
		return ""
	var houses: Dictionary = houses_val
	for hid_val in houses.keys():
		var house_id := str(hid_val).strip_edges()
		if house_id.is_empty():
			continue
		var house_val = houses.get(hid_val, null)
		if not (house_val is Dictionary):
			continue
		var house: Dictionary = house_val
		var cells_val = house.get("cells", null)
		if not (cells_val is Array):
			continue
		for c in cells_val:
			if c is Vector2i and Vector2i(c) == world_pos:
				return house_id
	return ""

func _build_house_tooltip_data(state: GameState, house_id: String) -> Dictionary:
	if state == null or not (state.map is Dictionary):
		return {}
	var houses_val = state.map.get("houses", null)
	if not (houses_val is Dictionary):
		return {}
	var houses: Dictionary = houses_val
	var house_val = houses.get(house_id, null)
	if not (house_val is Dictionary):
		return {}
	var house: Dictionary = house_val

	var house_number := HouseNumberManagerClass.format_display_label(house.get("house_number", null), house_id, "?")
	var has_garden := bool(house.get("has_garden", false))
	var demands: Array = []
	var demands_val = house.get("demands", null)
	if demands_val is Array:
		demands = demands_val
	var demand_cap_label := _get_house_demand_cap_label(state, house, has_garden)
	var owner_label := _format_owner_label(_coerce_int(house.get("owner", -1), -1), state)
	var source_label := "印刷建筑" if bool(house.get("printed", false)) else "放置建筑"

	var lines: Array[String] = []
	lines.append("编号：%s" % house_number)
	lines.append("来源：%s" % source_label)
	lines.append("归属：%s" % owner_label)
	lines.append("花园：%s" % ("有" if has_garden else "无"))
	lines.append("需求：%d/%s" % [demands.size(), demand_cap_label])
	lines.append("当前需求：%s" % _format_demands_summary(demands))

	return {
		"key": MAP_TOOLTIP_KEY_HOUSE,
		"title": "房屋 %s" % house_number,
		"content": "\n".join(lines),
	}

func _get_house_demand_cap_label(state: GameState, house: Dictionary, has_garden: bool) -> String:
	if bool(house.get("no_demand_cap", false)):
		return "无限"
	if state == null or not (state.rules is Dictionary):
		return "?"
	var rules: Dictionary = state.rules
	var key := "demand_cap_with_garden" if has_garden else "demand_cap_normal"
	var cap := _coerce_int(rules.get(key, null), -1)
	if cap < 0:
		return "?"
	return str(cap)

func _format_demands_summary(demands: Array) -> String:
	if demands.is_empty():
		return "无"
	var counts: Dictionary = {}
	for d_val in demands:
		if not (d_val is Dictionary):
			continue
		var d: Dictionary = d_val
		var pid := str(d.get("product", "")).strip_edges()
		if pid.is_empty():
			pid = "unknown"
		counts[pid] = int(counts.get(pid, 0)) + 1
	if counts.is_empty():
		return "无"
	var ids: Array[String] = []
	for k in counts.keys():
		ids.append(str(k))
	ids.sort()
	var parts: Array[String] = []
	for pid in ids:
		var c := int(counts.get(pid, 0))
		parts.append("%s x%d" % [_get_product_display_name(pid), c])
	return "、".join(parts)

func _resolve_restaurant_info(state: GameState, world_pos: Vector2i, cell: Dictionary) -> Dictionary:
	var structure_val = cell.get("structure", null)
	if not (structure_val is Dictionary):
		return {}
	var structure: Dictionary = structure_val
	if str(structure.get("piece_id", "")) != "restaurant":
		return {}

	var anchor := world_pos
	var anchor_val = structure.get("parent_anchor", null)
	if anchor_val is Vector2i:
		anchor = anchor_val

	var restaurant_id := str(structure.get("restaurant_id", "")).strip_edges()
	if restaurant_id.is_empty():
		restaurant_id = _find_restaurant_id_by_anchor(state, anchor)

	var owner := _coerce_int(structure.get("owner", -1), -1)
	var opening_soon := bool(structure.get("opening_soon", false))
	var restaurant_data := {}

	if not restaurant_id.is_empty():
		var read := _get_restaurant_data_with_status(state, restaurant_id)
		if not read.is_empty():
			var data_val = read.get("data", null)
			if data_val is Dictionary:
				restaurant_data = data_val
			opening_soon = opening_soon or bool(read.get("opening_soon", false))
			if owner < 0:
				owner = _coerce_int((restaurant_data as Dictionary).get("owner", -1), -1)

	return {
		"restaurant_id": restaurant_id,
		"anchor": anchor,
		"owner": owner,
		"opening_soon": opening_soon,
		"data": restaurant_data,
	}

func _build_restaurant_tooltip_data(state: GameState, info: Dictionary) -> Dictionary:
	var restaurant_id := str(info.get("restaurant_id", "")).strip_edges()
	var owner := _coerce_int(info.get("owner", -1), -1)
	var opening_soon := bool(info.get("opening_soon", false))
	var anchor := Vector2i(-1, -1)
	var anchor_val = info.get("anchor", null)
	if anchor_val is Vector2i:
		anchor = anchor_val

	var restaurant_data: Dictionary = {}
	var data_val = info.get("data", null)
	if data_val is Dictionary:
		restaurant_data = data_val

	var entrance_text := "未知"
	var entrance_val = restaurant_data.get("entrance_pos", null)
	if entrance_val is Vector2i:
		var ep: Vector2i = entrance_val
		entrance_text = "(%d,%d)" % [ep.x, ep.y]
	elif anchor != Vector2i(-1, -1):
		entrance_text = "(%d,%d)" % [anchor.x, anchor.y]

	var cells_count := 0
	var cells_val = restaurant_data.get("cells", null)
	if cells_val is Array:
		cells_count = (cells_val as Array).size()

	var index_in_owner := _get_owner_restaurant_index(state, owner, restaurant_id, anchor)

	var lines: Array[String] = []
	lines.append("归属：%s" % _format_owner_label(owner, state))
	if index_in_owner > 0:
		lines.append("该玩家第 %d 家餐厅" % index_in_owner)
	if not restaurant_id.is_empty():
		lines.append("餐厅ID：%s" % restaurant_id)
	lines.append("入口：%s" % entrance_text)
	if cells_count > 0:
		lines.append("占地：%d 格" % cells_count)
	lines.append("状态：%s" % ("筹备中（本回合末开业）" if opening_soon else "营业中"))

	var title := "餐厅"
	if index_in_owner > 0:
		title = "餐厅（第 %d 家）" % index_in_owner

	return {
		"key": MAP_TOOLTIP_KEY_RESTAURANT,
		"title": title,
		"content": "\n".join(lines),
	}

func _find_restaurant_id_by_anchor(state: GameState, anchor: Vector2i) -> String:
	if state == null or not (state.map is Dictionary):
		return ""
	var restaurants_val = state.map.get("restaurants", null)
	if restaurants_val is Dictionary:
		var restaurants: Dictionary = restaurants_val
		for rid_val in restaurants.keys():
			var rid := str(rid_val).strip_edges()
			if rid.is_empty():
				continue
			var rest_val = restaurants.get(rid_val, null)
			if not (rest_val is Dictionary):
				continue
			var rest: Dictionary = rest_val
			var ap = rest.get("anchor_pos", null)
			if ap is Vector2i and Vector2i(ap) == anchor:
				return rid

	for p_val in _get_opening_soon_restaurants(state):
		if not (p_val is Dictionary):
			continue
		var p: Dictionary = p_val
		var rid2 := str(p.get("restaurant_id", "")).strip_edges()
		if rid2.is_empty():
			continue
		var ap2 = p.get("anchor_pos", null)
		if ap2 is Vector2i and Vector2i(ap2) == anchor:
			return rid2
	return ""

func _get_restaurant_data_with_status(state: GameState, restaurant_id: String) -> Dictionary:
	if state == null or not (state.map is Dictionary):
		return {}
	var restaurants_val = state.map.get("restaurants", null)
	if restaurants_val is Dictionary:
		var restaurants: Dictionary = restaurants_val
		var rest_val = restaurants.get(restaurant_id, null)
		if rest_val is Dictionary:
			return {"data": rest_val, "opening_soon": false}

	for p_val in _get_opening_soon_restaurants(state):
		if not (p_val is Dictionary):
			continue
		var p: Dictionary = p_val
		var rid := str(p.get("restaurant_id", "")).strip_edges()
		if rid == restaurant_id:
			return {"data": p, "opening_soon": true}
	return {}

func _get_opening_soon_restaurants(state: GameState) -> Array:
	if state == null or not (state.round_state is Dictionary):
		return []
	var val = state.round_state.get(ROUND_STATE_OPENING_SOON_RESTAURANTS_KEY, null)
	if val is Array:
		return val
	return []

func _get_owner_restaurant_index(state: GameState, owner: int, restaurant_id: String, anchor: Vector2i) -> int:
	if owner < 0:
		return -1
	var ids: Array[String] = []
	var id_by_anchor: Dictionary = {}

	if state != null and (state.map is Dictionary):
		var restaurants_val = state.map.get("restaurants", null)
		if restaurants_val is Dictionary:
			var restaurants: Dictionary = restaurants_val
			for rid_val in restaurants.keys():
				var rid := str(rid_val).strip_edges()
				if rid.is_empty():
					continue
				var rest_val = restaurants.get(rid_val, null)
				if not (rest_val is Dictionary):
					continue
				var rest: Dictionary = rest_val
				if _coerce_int(rest.get("owner", -1), -1) != owner:
					continue
				if not ids.has(rid):
					ids.append(rid)
				var ap = rest.get("anchor_pos", null)
				if ap is Vector2i:
					id_by_anchor[Vector2i(ap)] = rid

	for p_val in _get_opening_soon_restaurants(state):
		if not (p_val is Dictionary):
			continue
		var p: Dictionary = p_val
		if _coerce_int(p.get("owner", -1), -1) != owner:
			continue
		var rid2 := str(p.get("restaurant_id", "")).strip_edges()
		if rid2.is_empty():
			continue
		if not ids.has(rid2):
			ids.append(rid2)
		var ap2 = p.get("anchor_pos", null)
		if ap2 is Vector2i:
			id_by_anchor[Vector2i(ap2)] = rid2

	ids.sort()
	if ids.is_empty():
		return -1

	var target_id := str(restaurant_id).strip_edges()
	if target_id.is_empty() and anchor != Vector2i(-1, -1):
		target_id = str(id_by_anchor.get(anchor, "")).strip_edges()
	if target_id.is_empty():
		return -1

	var idx := ids.find(target_id)
	if idx < 0:
		return -1
	return idx + 1

func _build_drink_source_tooltip_data(state: GameState, world_pos: Vector2i, drink_source: Dictionary) -> Dictionary:
	var source_type := str(drink_source.get("type", "")).strip_edges()
	if source_type.is_empty():
		source_type = "unknown"
	var product_name := _get_product_display_name(source_type)
	var tile_id := _find_drink_source_tile_id(state, world_pos, source_type)

	var lines: Array[String] = []
	if product_name == source_type:
		lines.append("饮料类型：%s" % source_type)
	else:
		lines.append("饮料类型：%s（%s）" % [product_name, source_type])
	lines.append("位置：(%d,%d)" % [world_pos.x, world_pos.y])
	if not tile_id.is_empty():
		lines.append("来源板块：%s" % tile_id)
	lines.append("可用于采购饮料动作")

	return {
		"key": MAP_TOOLTIP_KEY_DRINK_SOURCE,
		"title": "饮料进货点",
		"content": "\n".join(lines),
	}

func _find_drink_source_tile_id(state: GameState, world_pos: Vector2i, source_type: String) -> String:
	if state == null or not (state.map is Dictionary):
		return ""
	var sources_val = state.map.get("drink_sources", null)
	if not (sources_val is Array):
		return ""
	for s_val in sources_val:
		if not (s_val is Dictionary):
			continue
		var s: Dictionary = s_val
		var wp = s.get("world_pos", null)
		if not (wp is Vector2i) or Vector2i(wp) != world_pos:
			continue
		var t := str(s.get("type", "")).strip_edges()
		if source_type.is_empty() or t == source_type:
			return str(s.get("tile_id", "")).strip_edges()
	return ""

func _format_owner_label(owner: int, state: GameState) -> String:
	if owner < 0:
		return "地图中立"
	var default_name := "玩家%d" % (owner + 1)
	var display_name := default_name
	if Globals != null:
		var names_val = Globals.player_names
		if names_val is Array:
			var names: Array = names_val
			if owner >= 0 and owner < names.size():
				var n := str(names[owner]).strip_edges()
				if not n.is_empty():
					display_name = n
	if display_name == default_name and state != null and state.players is Array:
		var players: Array = state.players
		if owner >= 0 and owner < players.size():
			var p_val = players[owner]
			if p_val is Dictionary:
				var p: Dictionary = p_val
				var n2 := str(p.get("name", "")).strip_edges()
				if not n2.is_empty():
					display_name = n2
	if display_name == default_name:
		return default_name
	return "%s（%s）" % [default_name, display_name]

func _get_product_display_name(product_id: String) -> String:
	var pid := str(product_id).strip_edges()
	if pid.is_empty():
		return "未知"
	if ProductRegistryClass.is_loaded():
		var def_val = ProductRegistryClass.get_def(pid)
		if def_val != null and def_val is ProductDef:
			var name := str((def_val as ProductDef).name).strip_edges()
			if not name.is_empty():
				return name
	return pid

func _format_house_number(value) -> String:
	return HouseNumberManagerClass.format_display_number(value, "?")

func _coerce_int(value, fallback: int = 0) -> int:
	if value is int:
		return int(value)
	if value is float:
		var f: float = float(value)
		if f == floor(f):
			return int(f)
	return fallback
