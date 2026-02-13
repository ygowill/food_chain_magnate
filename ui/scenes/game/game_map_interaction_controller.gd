# Game scene：地图交互控制器
# 负责：map_canvas 选点/hover、营销预览、餐厅/房屋放置选点与预览/高亮
class_name GameMapInteractionController
extends RefCounted

signal mode_changed(mode: String, payload: Dictionary)
signal procure_drinks_source_selected(world_pos: Vector2i)
signal procure_drinks_start_restaurant_selected(restaurant_id: String)
signal procure_drinks_start_restaurant_hovered(restaurant_id: String)

const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")
const MarketingModeClass = preload("res://ui/scenes/game/game_map_interaction_marketing_mode.gd")
const PlacementModeClass = preload("res://ui/scenes/game/game_map_interaction_placement_mode.gd")
const CellsClass = preload("res://core/map/map_runtime/cells.gd")
const StructuresClass = preload("res://core/map/map_runtime/structures.gd")
const MapUtilsClass = preload("res://core/map/map_utils.gd")
const RoadGraphClass = preload("res://core/map/road_graph.gd")
const MapOverlayProviderRegistryClass = preload("res://core/rules/map_overlay_provider_registry.gd")

var _scene = null
var _map_canvas = null
var _overlay_controller = null
var _marketing_mode = null
var _placement_mode = null
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
var _distance_tool_from: Dictionary = {} # {kind: road|house|restaurant, id: String, pos: Vector2i, cells: Array[Vector2i]}
var _procure_drinks_hover_restaurant_id: String = ""

var marketing_panel = null
var restaurant_placement_overlay = null
var house_placement_overlay = null
var piece_placement_overlay = null

const _DISTANCE_TOOL_POINTS_OVERLAY_ID := "distance_tool_points"

func _init(scene, map_canvas, overlay_controller) -> void:
	_scene = scene
	_map_canvas = map_canvas
	_overlay_controller = overlay_controller
	_marketing_mode = MarketingModeClass.new(self)
	_placement_mode = PlacementModeClass.new(self)

func connect_signals() -> void:
	if not is_instance_valid(_map_canvas):
		return
	if _map_canvas.has_signal("cell_selected") and not _map_canvas.cell_selected.is_connected(_on_map_cell_selected):
		_map_canvas.cell_selected.connect(_on_map_cell_selected)
	if _map_canvas.has_signal("cell_hovered") and not _map_canvas.cell_hovered.is_connected(_on_map_cell_hovered):
		_map_canvas.cell_hovered.connect(_on_map_cell_hovered)

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
	if is_instance_valid(_map_canvas) and _map_canvas.has_method("clear_piece_overlay"):
		_map_canvas.call("clear_piece_overlay", _DISTANCE_TOOL_POINTS_OVERLAY_ID)
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
	if is_instance_valid(_map_canvas) and _map_canvas.has_method("clear_piece_overlay"):
		_map_canvas.call("clear_piece_overlay", _DISTANCE_TOOL_POINTS_OVERLAY_ID)
	_reset_custom_modes()

	# 退出任何选点模式后，如果不再需要外围空圈则恢复（issue_tracker #64）。
	_update_map_outside_margin_for_mode()

	_restaurant_valid_anchors.clear()
	_house_valid_anchors.clear()
	_piece_valid_anchors.clear()
	_marketing_valid_anchors.clear()
	_marketing_outside_to_anchor.clear()
	if old_mode == "distance_tool":
		_distance_tool_from.clear()
		if _overlay_controller != null:
			_overlay_controller.hide_distance_overlay()
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
	if _mode == "distance_tool":
		clear_selection()
		GameLog.info("Game", "距离工具已关闭")
		return

	if not _mode.is_empty():
		GameLog.warn("Game", "当前正在 %s 选点模式，无法启用距离工具" % _mode)
		return

	begin_selection("distance_tool")
	_distance_tool_from.clear()
	if _overlay_controller != null:
		_overlay_controller.hide_distance_overlay()
	GameLog.info("Game", "距离工具已启用：支持道路↔道路，或房屋+餐厅")

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
			if _overlay_controller == null:
				return

			if _scene == null or _scene.game_engine == null:
				return
			var state: GameState = _scene.game_engine.get_state()
			if state == null:
				return

			var pick := _resolve_distance_tool_pick(state, world_pos)
			if pick.is_empty():
				return

			if _distance_tool_from.is_empty():
				_distance_tool_from = pick.duplicate(true)
				_overlay_controller.hide_distance_overlay()
				_show_distance_tool_points_highlight(_distance_tool_pick_to_cells(pick))
				GameLog.info("Game", "距离工具：起点=%s，请选择终点" % _get_distance_tool_pick_label(pick))
				return

			if _is_same_distance_tool_pick(_distance_tool_from, pick):
				_distance_tool_from.clear()
				_overlay_controller.hide_distance_overlay()
				_clear_distance_tool_points_highlight()
				GameLog.info("Game", "距离工具：已清除起点，请重新选择起点")
				return

			var measure_read := _measure_distance_between_picks(state, _distance_tool_from, pick)
			if not measure_read.ok:
				# 非法组合时，将当前点击目标作为新的起点。
				_distance_tool_from = pick.duplicate(true)
				_overlay_controller.hide_distance_overlay()
				_show_distance_tool_points_highlight(_distance_tool_pick_to_cells(pick))
				GameLog.info("Game", "%s；已切换起点=%s" % [measure_read.error, _get_distance_tool_pick_label(pick)])
				return

			var measured: Dictionary = measure_read.value
			var measured_kind := str(measured.get("kind", "")).strip_edges()
			if measured_kind == "road_pair":
				var from_pos_val = measured.get("from_position", null)
				var to_pos_val = measured.get("to_position", null)
				if from_pos_val is Vector2i and to_pos_val is Vector2i:
					var to_positions: Array[Vector2i] = [Vector2i(to_pos_val)]
					_overlay_controller.show_distance_overlay(Vector2i(from_pos_val), to_positions)
			elif measured_kind == "house_restaurant_pair":
				if _overlay_controller.has_method("show_distance_overlay_pair"):
					var house_pos_val = measured.get("house_position", null)
					var restaurant_pos_val = measured.get("restaurant_position", null)
					var path_val = measured.get("path_points", null)
					var distance_val = measured.get("distance", -1)
					if house_pos_val is Vector2i and restaurant_pos_val is Vector2i and path_val is Array:
						var path_points: Array[Vector2i] = []
						for p in Array(path_val):
							if p is Vector2i:
								path_points.append(Vector2i(p))
						_overlay_controller.show_distance_overlay_pair(
							Vector2i(house_pos_val),
							Vector2i(restaurant_pos_val),
							path_points,
							int(distance_val)
						)

			var hl_val = measured.get("highlight_cells", null)
			if hl_val is Array:
				var hl: Array[Vector2i] = []
				for c in Array(hl_val):
					if c is Vector2i:
						hl.append(Vector2i(c))
				_show_distance_tool_points_highlight(hl)
			_distance_tool_from.clear()
		_:
			var handler = _custom_mode_handlers.get(_mode, null)
			if handler != null and is_instance_valid(handler) and handler.has_method("on_cell_selected"):
				handler.call("on_cell_selected", world_pos)

func _show_distance_tool_points_highlight(cells_in: Array[Vector2i]) -> void:
	if not is_instance_valid(_map_canvas):
		return
	if not _map_canvas.has_method("set_piece_overlay"):
		return
	# NOTE: set_piece_overlay expects Array[Vector2i]; passing an untyped Array via call() will error.
	var cells: Array[Vector2i] = []
	for v in cells_in:
		cells.append(v)
	if cells.is_empty():
		return
	_map_canvas.call("set_piece_overlay", _DISTANCE_TOOL_POINTS_OVERLAY_ID, cells, {
		"fill": Color(1, 0.9, 0.15, 0.2),
		"border": Color(1, 0.9, 0.15, 0.95),
		"border_width": 3.0,
	})

func _clear_distance_tool_points_highlight() -> void:
	if not is_instance_valid(_map_canvas):
		return
	if _map_canvas.has_method("clear_piece_overlay"):
		_map_canvas.call("clear_piece_overlay", _DISTANCE_TOOL_POINTS_OVERLAY_ID)

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

func _resolve_distance_tool_pick(state: GameState, world_pos: Vector2i) -> Dictionary:
	var house_pick := _find_house_at(state, world_pos)
	if not house_pick.is_empty():
		return house_pick

	var restaurant_pick := _find_restaurant_at(state, world_pos)
	if not restaurant_pick.is_empty():
		return restaurant_pick

	if CellsClass.has_road_at_any(state, world_pos):
		var road_cells: Array[Vector2i] = [world_pos]
		return {
			"kind": "road",
			"id": "",
			"pos": world_pos,
			"cells": road_cells,
		}
	return {}

func _is_same_distance_tool_pick(a: Dictionary, b: Dictionary) -> bool:
	var ka := str(a.get("kind", "")).strip_edges()
	var kb := str(b.get("kind", "")).strip_edges()
	if ka != kb:
		return false

	if ka == "road":
		var pa = a.get("pos", null)
		var pb = b.get("pos", null)
		return (pa is Vector2i) and (pb is Vector2i) and Vector2i(pa) == Vector2i(pb)

	var ida := str(a.get("id", "")).strip_edges()
	var idb := str(b.get("id", "")).strip_edges()
	if not ida.is_empty() and not idb.is_empty():
		return ida == idb
	return false

func _distance_tool_pick_to_cells(pick: Dictionary) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var cells_val = pick.get("cells", null)
	if cells_val is Array:
		for c in Array(cells_val):
			if c is Vector2i:
				var p := Vector2i(c)
				if not out.has(p):
					out.append(p)
	if out.is_empty():
		var pos_val = pick.get("pos", null)
		if pos_val is Vector2i:
			out.append(Vector2i(pos_val))
	return out

func _get_distance_tool_pick_label(pick: Dictionary) -> String:
	var kind := str(pick.get("kind", "")).strip_edges()
	var id := str(pick.get("id", "")).strip_edges()
	var pos_val = pick.get("pos", null)
	var pos := Vector2i(pos_val) if pos_val is Vector2i else Vector2i(-1, -1)
	match kind:
		"road":
			return "道路%s" % str(pos)
		"house":
			return "房屋%s" % (" #%s" % id if not id.is_empty() else "")
		"restaurant":
			return "餐厅%s" % (" %s" % id if not id.is_empty() else "")
		_:
			return str(pos)

func _find_house_at(state: GameState, world_pos: Vector2i) -> Dictionary:
	if state == null or not (state.map is Dictionary):
		return {}
	var houses_val = state.map.get("houses", null)
	if not (houses_val is Dictionary):
		return {}
	var houses: Dictionary = houses_val
	for hid_val in houses.keys():
		if not (hid_val is String):
			continue
		var hid := str(hid_val).strip_edges()
		if hid.is_empty():
			continue
		var house_val = houses.get(hid_val, null)
		if not (house_val is Dictionary):
			continue
		var house: Dictionary = house_val
		var cells := _extract_vector2i_cells_from_structure(house)
		if not cells.has(world_pos):
			continue
		return {
			"kind": "house",
			"id": hid,
			"pos": world_pos,
			"cells": cells,
			"structure": house.duplicate(true),
		}
	return {}

func _find_restaurant_at(state: GameState, world_pos: Vector2i) -> Dictionary:
	if state == null or not (state.map is Dictionary):
		return {}
	var restaurants_val = state.map.get("restaurants", null)
	if not (restaurants_val is Dictionary):
		return {}
	var restaurants: Dictionary = restaurants_val
	for rid_val in restaurants.keys():
		if not (rid_val is String):
			continue
		var rid := str(rid_val).strip_edges()
		if rid.is_empty():
			continue
		var rest_val = restaurants.get(rid_val, null)
		if not (rest_val is Dictionary):
			continue
		var rest: Dictionary = rest_val
		var cells := _extract_vector2i_cells_from_structure(rest)
		if not cells.has(world_pos):
			continue
		return {
			"kind": "restaurant",
			"id": rid,
			"pos": world_pos,
			"cells": cells,
			"structure": rest.duplicate(true),
		}
	return {}

func _extract_vector2i_cells_from_structure(structure: Dictionary) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var cells_val = structure.get("cells", null)
	if cells_val is Array:
		for p in Array(cells_val):
			if p is Vector2i:
				var pv := Vector2i(p)
				if not out.has(pv):
					out.append(pv)
			elif p is Array:
				var a: Array = p
				if a.size() == 2 and (a[0] is int or a[0] is float) and (a[1] is int or a[1] is float):
					var pv2 := Vector2i(int(a[0]), int(a[1]))
					if not out.has(pv2):
						out.append(pv2)
	if out.is_empty():
		var anchor_val = structure.get("anchor_pos", null)
		if anchor_val is Vector2i:
			out.append(Vector2i(anchor_val))
	return out

func _measure_distance_between_picks(state: GameState, from_pick: Dictionary, to_pick: Dictionary) -> Result:
	var from_kind := str(from_pick.get("kind", "")).strip_edges()
	var to_kind := str(to_pick.get("kind", "")).strip_edges()

	if from_kind == "road" and to_kind == "road":
		var from_pos_val = from_pick.get("pos", null)
		var to_pos_val = to_pick.get("pos", null)
		if not (from_pos_val is Vector2i) or not (to_pos_val is Vector2i):
			return Result.failure("距离工具：道路坐标无效")
		var highlight_cells: Array[Vector2i] = [Vector2i(from_pos_val), Vector2i(to_pos_val)]
		return Result.success({
			"kind": "road_pair",
			"from_position": Vector2i(from_pos_val),
			"to_position": Vector2i(to_pos_val),
			"highlight_cells": highlight_cells,
		})

	var house_pick: Dictionary = {}
	var restaurant_pick: Dictionary = {}
	if from_kind == "house" and to_kind == "restaurant":
		house_pick = from_pick
		restaurant_pick = to_pick
	elif from_kind == "restaurant" and to_kind == "house":
		house_pick = to_pick
		restaurant_pick = from_pick
	else:
		return Result.failure("距离工具：请选择两条道路格，或一间房屋+一间餐厅")

	var house_id := str(house_pick.get("id", "")).strip_edges()
	var restaurant_id := str(restaurant_pick.get("id", "")).strip_edges()
	if house_id.is_empty() or restaurant_id.is_empty():
		return Result.failure("距离工具：房屋或餐厅信息无效")

	var house_val = house_pick.get("structure", null)
	var rest_val = restaurant_pick.get("structure", null)
	if not (house_val is Dictionary) or not (rest_val is Dictionary):
		return Result.failure("距离工具：房屋或餐厅数据缺失")
	var house: Dictionary = house_val
	var rest: Dictionary = rest_val

	var hr_read := _measure_house_to_restaurant_distance(state, house_id, house, restaurant_id, rest)
	if not hr_read.ok:
		return hr_read
	var hr: Dictionary = hr_read.value

	var highlight_cells := _distance_tool_pick_to_cells(house_pick)
	for c in _distance_tool_pick_to_cells(restaurant_pick):
		if not highlight_cells.has(c):
			highlight_cells.append(c)

	var house_pos_val = house_pick.get("pos", null)
	var restaurant_pos_val = restaurant_pick.get("pos", null)
	if not (house_pos_val is Vector2i):
		house_pos_val = Vector2i.ZERO
	if not (restaurant_pos_val is Vector2i):
		restaurant_pos_val = Vector2i.ZERO

	return Result.success({
		"kind": "house_restaurant_pair",
		"house_position": Vector2i(house_pos_val),
		"restaurant_position": Vector2i(restaurant_pos_val),
		"path_points": Array(hr.get("path_points", [])),
		"distance": int(hr.get("distance", -1)),
		"highlight_cells": highlight_cells,
	})

func _measure_house_to_restaurant_distance(
	state: GameState,
	house_id: String,
	house: Dictionary,
	restaurant_id: String,
	rest: Dictionary
) -> Result:
	var road_graph = _build_road_graph_from_state(state)
	if road_graph == null or not is_instance_valid(road_graph):
		return Result.failure("距离工具：无法构建道路图")

	var house_cells := _extract_vector2i_cells_from_structure(house)
	if house_cells.is_empty():
		return Result.failure("距离工具：房屋缺少有效占地")
	var house_roads := _get_structure_adjacent_roads(state, house_cells)
	if house_roads.is_empty():
		return Result.success({
			"distance": -1,
			"path_points": [],
		})

	var entrance_read := StructuresClass.get_restaurant_entrance_points(state, restaurant_id, rest)
	if not entrance_read.ok:
		return Result.failure("距离工具：%s" % entrance_read.error)
	var entrance_points: Array[Vector2i] = []
	for p in Array(entrance_read.value):
		if p is Vector2i:
			entrance_points.append(Vector2i(p))
	if entrance_points.is_empty():
		return Result.failure("距离工具：餐厅入口无效: %s" % restaurant_id)
	var rest_roads := _get_structure_adjacent_roads(state, entrance_points)
	if rest_roads.is_empty():
		return Result.success({
			"distance": -1,
			"path_points": [],
		})

	var rest_entry_cost_by_road := _build_structure_to_road_boundary_cost(entrance_points, rest_roads)
	var house_entry_cost_by_road := _build_structure_to_road_boundary_cost(house_cells, house_roads)

	var best_distance := 2147483647
	var best_steps := 2147483647
	var best_path: Array[Vector2i] = []

	for s in rest_roads:
		for t in house_roads:
			var sp = road_graph.find_shortest_path(s, t)
			if not sp.ok or not (sp.value is Dictionary):
				continue
			var sp_val: Dictionary = sp.value
			var base_distance := int(sp_val.get("distance", -1))
			if base_distance < 0:
				continue
			var steps := int(sp_val.get("steps", 2147483647))
			var path_points: Array[Vector2i] = []
			var path_val = sp_val.get("path", null)
			if path_val is Array:
				for p2 in Array(path_val):
					if p2 is Vector2i:
						path_points.append(Vector2i(p2))
			if path_points.is_empty():
				path_points.append(Vector2i(s))
				if Vector2i(t) != Vector2i(s):
					path_points.append(Vector2i(t))

			var d := base_distance
			d += int(rest_entry_cost_by_road.get(s, 0))
			d += int(house_entry_cost_by_road.get(t, 0))
			if d < best_distance or (d == best_distance and steps < best_steps):
				best_distance = d
				best_steps = steps
				best_path = path_points

	if best_distance == 2147483647:
		return Result.success({
			"distance": -1,
			"path_points": [],
		})

	best_distance += _count_roadworks_penalty(state.map, best_path)
	return Result.success({
		"distance": best_distance,
		"path_points": best_path,
	})

func _build_road_graph_from_state(state: GameState):
	if state == null or not (state.map is Dictionary):
		return null
	var map_data: Dictionary = state.map
	var cells_val = map_data.get("cells", null)
	var grid_size_val = map_data.get("grid_size", null)
	var boundary_index_val = map_data.get("boundary_index", null)
	if not (cells_val is Array) or not (grid_size_val is Vector2i) or not (boundary_index_val is Dictionary):
		return null

	var origin := Vector2i.ZERO
	var origin_val = map_data.get("map_origin", Vector2i.ZERO)
	if origin_val is Vector2i:
		origin = origin_val

	var external_cells: Dictionary = {}
	var ext_val = map_data.get("external_cells", null)
	if ext_val is Dictionary:
		external_cells = ext_val

	var options: Dictionary = {}
	var connect_parallel := false
	var cpl_val = map_data.get("road_graph_connect_parallel_lanes", null)
	if cpl_val is bool:
		connect_parallel = bool(cpl_val)
	elif cpl_val is int:
		connect_parallel = int(cpl_val) != 0
	elif cpl_val is float:
		var f: float = float(cpl_val)
		if f == floor(f):
			connect_parallel = int(f) != 0
	if connect_parallel:
		options["connect_parallel_lanes"] = true

	return RoadGraphClass.build_from_cells_with_external(
		cells_val,
		Vector2i(grid_size_val),
		origin,
		external_cells,
		boundary_index_val,
		options
	)

func _get_structure_adjacent_roads(state: GameState, structure_cells: Array[Vector2i]) -> Array[Vector2i]:
	var set := {}
	for cell in structure_cells:
		if CellsClass.has_cell_any(state, cell) and CellsClass.has_road_at_any(state, cell):
			set[cell] = true
		for dir in MapUtilsClass.DIRECTIONS:
			var n := MapUtilsClass.get_neighbor_pos(cell, dir)
			if not CellsClass.has_cell_any(state, n):
				continue
			if CellsClass.has_road_at_any(state, n):
				set[n] = true

	var result: Array[Vector2i] = []
	for k in set.keys():
		if k is Vector2i:
			result.append(Vector2i(k))
	return result

func _build_structure_to_road_boundary_cost(
	structure_cells: Array[Vector2i],
	road_cells: Array[Vector2i]
) -> Dictionary:
	var out := {}
	for r in road_cells:
		var best := 2147483647
		for c in structure_cells:
			if c == r:
				best = 0
				break
			if not MapUtilsClass.are_adjacent(c, r):
				continue
			best = min(best, 1 if MapUtilsClass.crosses_tile_boundary(c, r) else 0)
		if best == 2147483647:
			best = 0
		out[r] = int(best)
	return out

func _count_roadworks_penalty(map_data: Dictionary, path_points: Array[Vector2i]) -> int:
	if map_data == null or map_data.is_empty() or path_points.is_empty():
		return 0
	var marker_positions: Array[Vector2i] = MapOverlayProviderRegistryClass.get_roadworks_marker_world_positions(map_data)
	if marker_positions.is_empty():
		return 0
	var marker_set := {}
	for p in marker_positions:
		if p is Vector2i:
			marker_set[p] = true
	var penalty := 0
	for i in range(1, path_points.size()):
		var p2: Vector2i = path_points[i]
		if marker_set.has(p2):
			penalty += 1
	return penalty

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
