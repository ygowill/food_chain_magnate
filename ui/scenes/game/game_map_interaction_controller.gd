# Game scene：地图交互控制器
# 负责：map_canvas 选点/hover、营销预览、餐厅/房屋放置选点与预览/高亮
class_name GameMapInteractionController
extends RefCounted

signal mode_changed(mode: String, payload: Dictionary)
signal procure_drinks_source_selected(world_pos: Vector2i)

const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")
const MarketingModeClass = preload("res://ui/scenes/game/game_map_interaction_marketing_mode.gd")
const PlacementModeClass = preload("res://ui/scenes/game/game_map_interaction_placement_mode.gd")
const CellsClass = preload("res://core/map/map_runtime/cells.gd")
const MapUtilsClass = preload("res://core/map/map_utils.gd")

var _scene = null
var _map_canvas = null
var _overlay_controller = null
var _marketing_mode = null
var _placement_mode = null

var _mode: String = ""
var _payload: Dictionary = {}
var _restaurant_valid_anchors: Dictionary = {} # Vector2i -> true
var _house_valid_anchors: Dictionary = {} # Vector2i -> true
var _piece_valid_anchors: Dictionary = {} # Vector2i -> true
var _marketing_valid_anchors: Dictionary = {} # Vector2i -> true
var _lobbyists_extra_tile_valid_anchors: Dictionary = {} # Vector2i -> true
var _marketing_outside_to_anchor: Dictionary = {} # outside_world_pos(Vector2i) -> {anchor: Vector2i, axis: String, attach: String} (airplane only)
var _distance_tool_from: Vector2i = Vector2i(-1, -1)

var marketing_panel = null
var restaurant_placement_overlay = null
var house_placement_overlay = null
var piece_placement_overlay = null
var lobbyists_extra_tile_overlay = null

const _DISTANCE_TOOL_POINTS_OVERLAY_ID := "distance_tool_points"
const _LOBBYISTS_EXTRA_TILE_PREVIEW_OVERLAY_ID := "lobbyists_extra_tile_preview"

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

func set_lobbyists_extra_tile_overlay(overlay) -> void:
	lobbyists_extra_tile_overlay = overlay

func begin_selection(mode: String, payload: Dictionary = {}) -> void:
	_mode = mode
	_payload = payload.duplicate(true)
	_restaurant_valid_anchors.clear()
	_house_valid_anchors.clear()
	_piece_valid_anchors.clear()
	_marketing_valid_anchors.clear()
	_lobbyists_extra_tile_valid_anchors.clear()
	_marketing_outside_to_anchor.clear()
	if is_instance_valid(_map_canvas) and _map_canvas.has_method("clear_cell_highlights"):
		_map_canvas.call("clear_cell_highlights")
	if is_instance_valid(_map_canvas) and _map_canvas.has_method("clear_move_restaurant_selected_restaurant"):
		_map_canvas.call("clear_move_restaurant_selected_restaurant")
	if is_instance_valid(_map_canvas) and _map_canvas.has_method("clear_piece_overlay"):
		_map_canvas.call("clear_piece_overlay", _DISTANCE_TOOL_POINTS_OVERLAY_ID)
		_map_canvas.call("clear_piece_overlay", _LOBBYISTS_EXTRA_TILE_PREVIEW_OVERLAY_ID)

	# 动态控制“地图外围 UI-only 空圈”：仅在需要放置/显示外围 piece 时开启（issue_tracker #64）。
	_update_map_outside_margin_for_mode()

	_emit_mode_changed()
	if _mode == "procure_drinks":
		_sync_procure_drinks_highlights()

func clear_selection() -> void:
	var old_mode := _mode
	_mode = ""
	_payload.clear()
	if is_instance_valid(_map_canvas) and _map_canvas.has_method("clear_structure_preview"):
		_map_canvas.call("clear_structure_preview")
	if is_instance_valid(_map_canvas) and _map_canvas.has_method("clear_cell_highlights"):
		_map_canvas.call("clear_cell_highlights")
	if is_instance_valid(_map_canvas) and _map_canvas.has_method("clear_move_restaurant_selected_restaurant"):
		_map_canvas.call("clear_move_restaurant_selected_restaurant")
	if is_instance_valid(_map_canvas) and _map_canvas.has_method("clear_piece_overlay"):
		_map_canvas.call("clear_piece_overlay", _DISTANCE_TOOL_POINTS_OVERLAY_ID)
		_map_canvas.call("clear_piece_overlay", _LOBBYISTS_EXTRA_TILE_PREVIEW_OVERLAY_ID)

	# 退出任何选点模式后，如果不再需要外围空圈则恢复（issue_tracker #64）。
	_update_map_outside_margin_for_mode()

	_restaurant_valid_anchors.clear()
	_house_valid_anchors.clear()
	_piece_valid_anchors.clear()
	_marketing_valid_anchors.clear()
	_lobbyists_extra_tile_valid_anchors.clear()
	_marketing_outside_to_anchor.clear()
	if old_mode == "distance_tool":
		_distance_tool_from = Vector2i(-1, -1)
		if _overlay_controller != null:
			_overlay_controller.hide_distance_overlay()
	_emit_mode_changed()

func get_mode() -> String:
	return _mode

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
	_distance_tool_from = Vector2i(-1, -1)
	if _overlay_controller != null:
		_overlay_controller.hide_distance_overlay()
	GameLog.info("Game", "距离工具已启用：点击起点，再点击终点")

func _on_map_cell_selected(world_pos: Vector2i) -> void:
	if world_pos == Vector2i(-1, -1):
		return

	match _mode:
		"procure_drinks":
			var emp_type := str(_payload.get("employee_type", ""))
			if _is_air_procure_employee(emp_type):
				procure_drinks_source_selected.emit(world_pos)
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
		"lobbyists_extra_tile":
			# 仅允许点击“高亮的合法边缘格”
			if _lobbyists_extra_tile_valid_anchors.is_empty() or not _lobbyists_extra_tile_valid_anchors.has(world_pos):
				if is_instance_valid(lobbyists_extra_tile_overlay) and lobbyists_extra_tile_overlay.visible and lobbyists_extra_tile_overlay.has_method("set_validation"):
					lobbyists_extra_tile_overlay.set_validation(false, "请选择高亮的可放置边缘格")
				return
			if _scene == null or _scene.game_engine == null:
				return
			var state2: GameState = _scene.game_engine.get_state()
			if state2 == null:
				return

			var tile_info: Dictionary = MapUtilsClass.world_to_tile(world_pos)
			var attach_board_pos: Vector2i = tile_info.get("board_pos", Vector2i.ZERO)
			var local_pos: Vector2i = tile_info.get("local_pos", Vector2i.ZERO)
			var side := _side_from_tile_local_pos(local_pos)
			if side.is_empty():
				if is_instance_valid(lobbyists_extra_tile_overlay) and lobbyists_extra_tile_overlay.visible and lobbyists_extra_tile_overlay.has_method("set_validation"):
					lobbyists_extra_tile_overlay.set_validation(false, "请点击板块边缘格（非角落）")
				return

			var tile_id := ""
			var rotation := 0
			if is_instance_valid(lobbyists_extra_tile_overlay):
				if lobbyists_extra_tile_overlay.has_method("get_selected_tile_id"):
					tile_id = str(lobbyists_extra_tile_overlay.get_selected_tile_id()).strip_edges()
				if lobbyists_extra_tile_overlay.has_method("get_selected_rotation"):
					rotation = int(lobbyists_extra_tile_overlay.get_selected_rotation())
			if tile_id.is_empty():
				if is_instance_valid(lobbyists_extra_tile_overlay) and lobbyists_extra_tile_overlay.visible and lobbyists_extra_tile_overlay.has_method("set_validation"):
					lobbyists_extra_tile_overlay.set_validation(false, "tile 未选择")
				return

			var actor := int(state2.get_current_player_id())
			if NetContext != null and NetContext.mode == NetContext.Mode.ONLINE_CLIENT and int(NetContext.local_player_id) >= 0:
				actor = int(NetContext.local_player_id)

			var cmd := Command.create("place_lobbyists_extra_map_tile", actor, {
				"tile_id": tile_id,
				"attach_to_tile_board_pos": [attach_board_pos.x, attach_board_pos.y],
				"side": side,
				"rotation": rotation,
			})
			cmd.phase = state2.phase
			cmd.sub_phase = state2.sub_phase

			var executor = _scene.game_engine.get_action_registry().get_executor("place_lobbyists_extra_map_tile")
			if executor != null:
				var vr: Result = executor.validate(state2, cmd)
				if not vr.ok:
					if is_instance_valid(lobbyists_extra_tile_overlay) and lobbyists_extra_tile_overlay.visible and lobbyists_extra_tile_overlay.has_method("set_validation"):
						lobbyists_extra_tile_overlay.set_validation(false, vr.error)
					return

			if is_instance_valid(lobbyists_extra_tile_overlay) and lobbyists_extra_tile_overlay.visible:
				if lobbyists_extra_tile_overlay.has_method("set_selected_target"):
					lobbyists_extra_tile_overlay.set_selected_target(attach_board_pos, side)
				if lobbyists_extra_tile_overlay.has_method("set_validation"):
					lobbyists_extra_tile_overlay.set_validation(true, "")
				_maybe_auto_confirm_placement(lobbyists_extra_tile_overlay)
		"distance_tool":
			if _overlay_controller == null:
				return

			if _scene == null or _scene.game_engine == null:
				return
			var state: GameState = _scene.game_engine.get_state()
			if state == null:
				return
			# 只允许点道路格（issue_tracker #59）。
			if not CellsClass.has_road_at_any(state, world_pos):
				return

			if _distance_tool_from == Vector2i(-1, -1):
				_distance_tool_from = world_pos
				_overlay_controller.hide_distance_overlay()
				_show_distance_tool_points_highlight([world_pos])
				GameLog.info("Game", "距离工具：起点=%s，请选择终点" % str(world_pos))
				return

			# 再次点击起点视为重置（仅影响“起点已选但尚未测距完成”的阶段）
			if world_pos == _distance_tool_from:
				_distance_tool_from = Vector2i(-1, -1)
				_overlay_controller.hide_distance_overlay()
				_clear_distance_tool_points_highlight()
				GameLog.info("Game", "距离工具：已清除起点，请重新选择起点")
				return

			var to_positions: Array[Vector2i] = []
			to_positions.append(world_pos)
			_overlay_controller.show_distance_overlay(_distance_tool_from, to_positions)
			# 每次只测一段：测完后清空起点；下一次点击任意道路格会重新开始（issue_tracker #59）。
			# 起点/终点高亮保持到下一次测距开始（issue_tracker #59：可见性增强）。
			_show_distance_tool_points_highlight([_distance_tool_from, world_pos])
			_distance_tool_from = Vector2i(-1, -1)
		_:
			pass

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
		"fill": Color(1, 0.9, 0.15, 0.12),
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

	var requested := 0
	if _mode == "marketing":
		var mt := str(_payload.get("marketing_type", "")).strip_edges()
		if mt == "airplane":
			requested = 2

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

func _on_map_cell_hovered(world_pos: Vector2i) -> void:
	if _mode == "lobbyists_extra_tile":
		_on_lobbyists_extra_tile_cell_hovered(world_pos)
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

func on_lobbyists_extra_tile_highlight_requested(tile_id: String, rotation: int) -> void:
	if _mode != "lobbyists_extra_tile":
		return
	if not is_instance_valid(_map_canvas):
		return
	if _scene == null or _scene.game_engine == null:
		return
	var state: GameState = _scene.game_engine.get_state()
	if state == null:
		return

	var tid := str(tile_id).strip_edges()
	if tid.is_empty():
		_lobbyists_extra_tile_valid_anchors.clear()
		if _map_canvas.has_method("clear_cell_highlights"):
			_map_canvas.call("clear_cell_highlights")
		if _map_canvas.has_method("clear_piece_overlay"):
			_map_canvas.call("clear_piece_overlay", _LOBBYISTS_EXTRA_TILE_PREVIEW_OVERLAY_ID)
		return

	var actor := int(state.get_current_player_id())
	if NetContext != null and NetContext.mode == NetContext.Mode.ONLINE_CLIENT and int(NetContext.local_player_id) >= 0:
		actor = int(NetContext.local_player_id)

	var executor = _scene.game_engine.get_action_registry().get_executor("place_lobbyists_extra_map_tile")
	if executor == null:
		_lobbyists_extra_tile_valid_anchors.clear()
		if _map_canvas.has_method("clear_cell_highlights"):
			_map_canvas.call("clear_cell_highlights")
		return

	var occupied := _get_occupied_tile_board_positions(state)

	var cells: Array[Vector2i] = []
	var anchor_set := {}
	for bp in occupied:
		var board_pos: Vector2i = bp
		for side in ["N", "E", "S", "W"]:
			var cmd := Command.create("place_lobbyists_extra_map_tile", actor, {
				"tile_id": tid,
				"attach_to_tile_board_pos": [board_pos.x, board_pos.y],
				"side": str(side),
				"rotation": _normalize_rotation(rotation),
			})
			cmd.phase = state.phase
			cmd.sub_phase = state.sub_phase
			var vr: Result = executor.validate(state, cmd)
			if not vr.ok:
				continue
			var edge_cells := _edge_cells_for_tile_side(board_pos, str(side))
			for c in edge_cells:
				if anchor_set.has(c):
					continue
				anchor_set[c] = true
				cells.append(c)

	_lobbyists_extra_tile_valid_anchors = anchor_set
	if _map_canvas.has_method("set_cell_highlights"):
		_map_canvas.call("set_cell_highlights", cells)

func _on_lobbyists_extra_tile_cell_hovered(world_pos: Vector2i) -> void:
	if not is_instance_valid(_map_canvas):
		return
	if not _map_canvas.has_method("is_cell_highlighted"):
		return
	if not bool(_map_canvas.call("is_cell_highlighted", world_pos)):
		if _map_canvas.has_method("clear_piece_overlay"):
			_map_canvas.call("clear_piece_overlay", _LOBBYISTS_EXTRA_TILE_PREVIEW_OVERLAY_ID)
		return

	var info: Dictionary = MapUtilsClass.world_to_tile(world_pos)
	var attach_board_pos: Vector2i = info.get("board_pos", Vector2i.ZERO)
	var local_pos: Vector2i = info.get("local_pos", Vector2i.ZERO)
	var side := _side_from_tile_local_pos(local_pos)
	if side.is_empty():
		if _map_canvas.has_method("clear_piece_overlay"):
			_map_canvas.call("clear_piece_overlay", _LOBBYISTS_EXTRA_TILE_PREVIEW_OVERLAY_ID)
		return

	var offset: Vector2i = MapUtilsClass.DIR_OFFSETS.get(side, Vector2i.ZERO)
	var new_board_pos: Vector2i = attach_board_pos + offset

	if not _map_canvas.has_method("set_piece_overlay"):
		return

	var region: Array[Vector2i] = []
	var tile_size := int(MapUtilsClass.TILE_SIZE)
	var origin: Vector2i = new_board_pos * tile_size
	for dy in range(tile_size):
		for dx in range(tile_size):
			region.append(origin + Vector2i(dx, dy))

	_map_canvas.call("set_piece_overlay", _LOBBYISTS_EXTRA_TILE_PREVIEW_OVERLAY_ID, region, {
		"fill": Color(0.2, 0.65, 1.0, 0.12),
		"border": Color(0.2, 0.65, 1.0, 0.9),
		"border_width": 3.0,
	})

func _get_occupied_tile_board_positions(state: GameState) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if state == null or not (state.map is Dictionary):
		return result

	var placements: Array = []
	if state.map.has("tile_placements") and (state.map["tile_placements"] is Array):
		placements.append_array(state.map["tile_placements"])
	if state.map.has("external_tile_placements") and (state.map["external_tile_placements"] is Array):
		placements.append_array(state.map["external_tile_placements"])

	var seen := {}
	for pv in placements:
		if not (pv is Dictionary):
			continue
		var p: Dictionary = pv
		var bp_val = p.get("board_pos", null)
		if not (bp_val is Vector2i):
			continue
		var bp: Vector2i = bp_val
		if seen.has(bp):
			continue
		seen[bp] = true
		result.append(bp)

	return result

func _edge_cells_for_tile_side(board_pos: Vector2i, side: String) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var tile_size := int(MapUtilsClass.TILE_SIZE)
	var max_idx := tile_size - 1
	var origin: Vector2i = board_pos * tile_size

	match str(side):
		"N":
			for lx in range(1, max_idx):
				cells.append(origin + Vector2i(lx, 0))
		"S":
			for lx in range(1, max_idx):
				cells.append(origin + Vector2i(lx, max_idx))
		"W":
			for ly in range(1, max_idx):
				cells.append(origin + Vector2i(0, ly))
		"E":
			for ly in range(1, max_idx):
				cells.append(origin + Vector2i(max_idx, ly))

	return cells

func _side_from_tile_local_pos(local_pos: Vector2i) -> String:
	var tile_size := int(MapUtilsClass.TILE_SIZE)
	var max_idx := tile_size - 1
	var on_n := local_pos.y == 0
	var on_s := local_pos.y == max_idx
	var on_w := local_pos.x == 0
	var on_e := local_pos.x == max_idx
	var count := int(on_n) + int(on_s) + int(on_w) + int(on_e)
	if count != 1:
		return ""
	if on_n:
		return "N"
	if on_s:
		return "S"
	if on_w:
		return "W"
	return "E"

func _normalize_rotation(rotation: int) -> int:
	var r := int(rotation) % 360
	if r < 0:
		r += 360
	if r != 0 and r != 90 and r != 180 and r != 270:
		r = 0
	return r
