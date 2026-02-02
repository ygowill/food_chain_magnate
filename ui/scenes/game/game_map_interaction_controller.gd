# Game scene：地图交互控制器
# 负责：map_canvas 选点/hover、营销预览、餐厅/房屋放置选点与预览/高亮
class_name GameMapInteractionController
extends RefCounted

signal mode_changed(mode: String, payload: Dictionary)
signal procure_drinks_source_selected(world_pos: Vector2i)

const PlacementClass = preload("res://core/map/placement_validator/placement.gd")
const RestaurantPlacementClass = preload("res://core/map/placement_validator/restaurant_placement.gd")
const PieceDefClass = preload("res://core/map/piece_def.gd")
const PieceRegistryClass = preload("res://core/map/piece_registry.gd")
const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")
const MarketingModeClass = preload("res://ui/scenes/game/game_map_interaction_marketing_mode.gd")
const CellsClass = preload("res://core/map/map_runtime/cells.gd")
const CoordsClass = preload("res://core/map/map_runtime/coords.gd")
const StructuresClass = preload("res://core/map/map_runtime/structures.gd")
const RangeUtilsClass = preload("res://core/utils/range_utils.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")

var _scene = null
var _map_canvas = null
var _overlay_controller = null
var _marketing_mode = null

var _mode: String = ""
var _payload: Dictionary = {}
var _restaurant_valid_anchors: Dictionary = {} # Vector2i -> true
var _house_valid_anchors: Dictionary = {} # Vector2i -> true
var _piece_valid_anchors: Dictionary = {} # Vector2i -> true
var _marketing_valid_anchors: Dictionary = {} # Vector2i -> true
var _marketing_outside_to_anchor: Dictionary = {} # outside_world_pos(Vector2i) -> {anchor: Vector2i, axis: String, attach: String} (airplane only)
var _distance_tool_from: Vector2i = Vector2i(-1, -1)

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

func begin_selection(mode: String, payload: Dictionary = {}) -> void:
	_mode = mode
	_payload = payload.duplicate(true)
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

	# 退出任何选点模式后，如果不再需要外围空圈则恢复（issue_tracker #64）。
	_update_map_outside_margin_for_mode()

	_restaurant_valid_anchors.clear()
	_house_valid_anchors.clear()
	_piece_valid_anchors.clear()
	_marketing_valid_anchors.clear()
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
	if _mode != "marketing":
		return
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
	if is_instance_valid(_map_canvas) and _map_canvas.has_method("clear_structure_preview"):
		_map_canvas.call("clear_structure_preview")
	if is_instance_valid(restaurant_placement_overlay) and restaurant_placement_overlay.has_method("set_validation"):
		restaurant_placement_overlay.set_validation(true, "")

func on_restaurant_highlight_requested(mode: String, rotation: int, restaurant_id: String) -> void:
	if _mode != "restaurant_placement":
		return
	if not (is_instance_valid(restaurant_placement_overlay) and restaurant_placement_overlay.visible):
		return
	if _scene == null:
		return
	var engine = _scene.game_engine
	if engine == null:
		return
	var state = engine.get_state()
	if state == null:
		return

	var actor: int = state.get_current_player_id()
	var action_id := "place_restaurant" if mode != "move_restaurant" else "move_restaurant"

	# move_restaurant：未选择餐厅前不高亮
	if action_id == "move_restaurant" and restaurant_id.is_empty():
		_restaurant_valid_anchors.clear()
		if is_instance_valid(_map_canvas) and _map_canvas.has_method("clear_cell_highlights"):
			_map_canvas.call("clear_cell_highlights")
		if is_instance_valid(_map_canvas) and _map_canvas.has_method("clear_move_restaurant_selected_restaurant"):
			_map_canvas.call("clear_move_restaurant_selected_restaurant")
		return

	# 非 move_restaurant：确保清理“被移动餐厅”的高亮
	if action_id != "move_restaurant":
		if is_instance_valid(_map_canvas) and _map_canvas.has_method("clear_move_restaurant_selected_restaurant"):
			_map_canvas.call("clear_move_restaurant_selected_restaurant")
	else:
		# move_restaurant：高亮当前选中餐厅（入口 anchor）
		var anchor_world := Vector2i(-1, -1)
		if not restaurant_id.is_empty() and (state.map is Dictionary) and state.map.has("restaurants") and (state.map["restaurants"] is Dictionary):
			var rests: Dictionary = state.map["restaurants"]
			if rests.has(restaurant_id):
				var rest_val = rests[restaurant_id]
				if rest_val is Dictionary:
					var rest: Dictionary = rest_val
					var ep_val = rest.get("entrance_pos", null)
					if ep_val is Vector2i:
						anchor_world = Vector2i(ep_val)
		if is_instance_valid(_map_canvas) and _map_canvas.has_method("set_move_restaurant_selected_restaurant"):
			_map_canvas.call("set_move_restaurant_selected_restaurant", anchor_world)

	if not (state.map is Dictionary):
		return
	if not state.map.has("grid_size") or not (state.map["grid_size"] is Vector2i):
		return
	var grid_size: Vector2i = state.map["grid_size"]
	var map_origin: Vector2i = Vector2i.ZERO
	var map_origin_val = state.map.get("map_origin", Vector2i.ZERO)
	if map_origin_val is Vector2i:
		map_origin = map_origin_val

	# 基于 PlacementValidator 扫描（结构合法性），不依赖 executor.validate 的全图遍历
	var piece_registry: Dictionary = engine.game_data.pieces if engine.game_data != null else {}
	if not piece_registry.has("restaurant") or not (piece_registry["restaurant"] is PieceDef):
		piece_registry["restaurant"] = PieceDefClass.create_restaurant()

	var ctx := {
		"cells": state.map.cells,
		"grid_size": state.map.grid_size,
		"map_origin": map_origin,
		"houses": state.map.houses,
		"restaurants": state.map.restaurants,
		"drink_sources": state.map.get("drink_sources", []),
	}

	var extra := {}
	if action_id == "move_restaurant" and not restaurant_id.is_empty():
		if state.map.restaurants.has(restaurant_id):
			var rest: Dictionary = state.map.restaurants[restaurant_id]
			if rest.has("cells") and (rest["cells"] is Array):
				extra["ignore_structure_cells"] = rest["cells"]

	var anchors: Array[Vector2i] = []
	var anchor_set := {}
	for y in range(grid_size.y):
		for x in range(grid_size.x):
			var world_anchor: Vector2i = Vector2i(x, y) - map_origin
			var r: Result = RestaurantPlacementClass.validate_restaurant_placement(
				ctx,
				world_anchor,
				rotation,
					piece_registry,
					actor,
					state.phase == DefsClass.PHASE_SETUP,
					extra
				)
			if not r.ok:
				continue
			if anchor_set.has(world_anchor):
				continue
			anchor_set[world_anchor] = true
			anchors.append(world_anchor)

	_restaurant_valid_anchors = anchor_set
	if is_instance_valid(_map_canvas) and _map_canvas.has_method("set_cell_highlights"):
		_map_canvas.call("set_cell_highlights", anchors)

func on_house_highlight_requested(action_id: String, rotation: int) -> void:
	if _mode != "house_placement":
		return
	if not (is_instance_valid(house_placement_overlay) and house_placement_overlay.visible):
		return
	if _scene == null:
		return
	var engine = _scene.game_engine
	if engine == null:
		return
	var state = engine.get_state()
	if state == null:
		return
	if action_id != "place_house":
		_house_valid_anchors.clear()
		if is_instance_valid(_map_canvas) and _map_canvas.has_method("clear_cell_highlights"):
			_map_canvas.call("clear_cell_highlights")
		return

	if not (state.map is Dictionary):
		return
	if not state.map.has("grid_size") or not (state.map["grid_size"] is Vector2i):
		return
	var grid_size: Vector2i = state.map["grid_size"]
	var map_origin: Vector2i = Vector2i.ZERO
	var map_origin_val = state.map.get("map_origin", Vector2i.ZERO)
	if map_origin_val is Vector2i:
		map_origin = map_origin_val

	var actor: int = state.get_current_player_id()
	var piece_registry: Dictionary = engine.game_data.pieces if engine.game_data != null else {}
	if not piece_registry.has("house_with_garden") or not (piece_registry["house_with_garden"] is PieceDef):
		piece_registry["house_with_garden"] = PieceDefClass.create_house_with_garden()

	var ctx := {
		"cells": state.map.cells,
		"grid_size": state.map.grid_size,
		"map_origin": map_origin,
		"houses": state.map.houses,
		"restaurants": state.map.restaurants,
		"drink_sources": state.map.get("drink_sources", []),
		"marketing_placements": state.map.get("marketing_placements", {}),
	}

	var anchors: Array[Vector2i] = []
	var anchor_set := {}
	for y in range(grid_size.y):
		for x in range(grid_size.x):
			var world_anchor: Vector2i = Vector2i(x, y) - map_origin
			var r: Result = PlacementClass.validate_placement(ctx, "house_with_garden", world_anchor, rotation, piece_registry, {})
			if not r.ok:
				continue
			if anchor_set.has(world_anchor):
				continue
			anchor_set[world_anchor] = true
			anchors.append(world_anchor)

	_house_valid_anchors = anchor_set
	if is_instance_valid(_map_canvas) and _map_canvas.has_method("set_cell_highlights"):
		_map_canvas.call("set_cell_highlights", anchors)

func on_house_preview_cleared() -> void:
	if is_instance_valid(_map_canvas) and _map_canvas.has_method("clear_structure_preview"):
		_map_canvas.call("clear_structure_preview")

func on_restaurant_preview_requested(mode: String, position: Vector2i, rotation: int, restaurant_id: String) -> void:
	if _scene == null:
		return
	var engine = _scene.game_engine
	if engine == null:
		return
	var state = engine.get_state()
	if state == null:
		return

	var actor: int = state.get_current_player_id()
	var action_id := "place_restaurant" if mode != "move_restaurant" else "move_restaurant"

	# footprint 预览：尽量不依赖校验成功
	var piece_registry: Dictionary = engine.game_data.pieces if engine.game_data != null else {}
	if not piece_registry.has("restaurant") or not (piece_registry["restaurant"] is PieceDef):
		piece_registry["restaurant"] = PieceDefClass.create_restaurant()
	var piece_def_val = piece_registry.get("restaurant", null)
	var piece_def: PieceDef = piece_def_val if piece_def_val is PieceDef else PieceDefClass.create_restaurant()
	var footprint_cells: Array[Vector2i] = piece_def.get_world_cells(position, rotation)

	# UI 校验：用核心 PlacementValidator + 与动作一致的 ignore_cells 语义
	var ctx := {
		"cells": state.map.cells,
		"grid_size": state.map.grid_size,
		"map_origin": state.map.get("map_origin", Vector2i.ZERO),
		"houses": state.map.houses,
		"restaurants": state.map.restaurants,
		"marketing_placements": state.map.get("marketing_placements", {}),
	}

	var extra := {}
	if action_id == "move_restaurant" and not restaurant_id.is_empty():
		if state.map.restaurants.has(restaurant_id):
			var rest: Dictionary = state.map.restaurants[restaurant_id]
			if rest.has("cells") and (rest["cells"] is Array):
				extra["ignore_structure_cells"] = rest["cells"]

	var validate_r: Result = RestaurantPlacementClass.validate_restaurant_placement(
		ctx,
		position,
		rotation,
			piece_registry,
			actor,
			state.phase == DefsClass.PHASE_SETUP,
			extra
		)

	var valid := validate_r.ok
	var message := "" if valid else validate_r.error

	# 额外约束：与动作执行器一致的“回合/次数/数量”检查（避免只靠放置校验导致误导）
	# 这里用执行器 validate（包含员工/回合等规则），确保提示与真实执行一致
	var cmd_params := {"position": [position.x, position.y], "rotation": rotation}
	if action_id == "move_restaurant" and not restaurant_id.is_empty():
		cmd_params["restaurant_id"] = restaurant_id
	if is_instance_valid(restaurant_placement_overlay) and restaurant_placement_overlay.has_method("get_selected_employee"):
		var employee_type := str(restaurant_placement_overlay.get_selected_employee()).strip_edges()
		if not employee_type.is_empty():
			cmd_params["employee_type"] = employee_type
	var cmd := Command.create(action_id, actor, cmd_params)
	cmd.phase = state.phase
	cmd.sub_phase = state.sub_phase
	var executor = engine.get_action_registry().get_executor(action_id)
	if executor != null:
		var ex_r: Result = executor.validate(state, cmd)
		if not ex_r.ok:
			valid = false
			message = ex_r.error

	if is_instance_valid(_map_canvas) and _map_canvas.has_method("set_structure_preview"):
		_map_canvas.call("set_structure_preview", footprint_cells, valid, {
			"piece_id": "restaurant",
			"anchor": position,
			"rotation": rotation,
			"owner": actor,
		})
	if is_instance_valid(restaurant_placement_overlay) and restaurant_placement_overlay.has_method("set_validation"):
		restaurant_placement_overlay.set_validation(valid, message)

func on_house_preview_requested(action_id: String, position: Vector2i, rotation: int) -> void:
	if _scene == null:
		return
	var engine = _scene.game_engine
	if engine == null:
		return
	var state = engine.get_state()
	if state == null:
		return

	var actor: int = state.get_current_player_id()

	var piece_registry: Dictionary = engine.game_data.pieces if engine.game_data != null else {}
	if not piece_registry.has("house_with_garden") or not (piece_registry["house_with_garden"] is PieceDef):
		piece_registry["house_with_garden"] = PieceDefClass.create_house_with_garden()
	var piece_def_val = piece_registry.get("house_with_garden", null)
	var piece_def: PieceDef = piece_def_val if piece_def_val is PieceDef else PieceDefClass.create_house_with_garden()
	var footprint_cells: Array[Vector2i] = piece_def.get_world_cells(position, rotation)

	var ctx := {
		"cells": state.map.cells,
		"grid_size": state.map.grid_size,
		"map_origin": state.map.get("map_origin", Vector2i.ZERO),
		"houses": state.map.houses,
		"restaurants": state.map.restaurants,
		"drink_sources": state.map.get("drink_sources", []),
		"marketing_placements": state.map.get("marketing_placements", {}),
	}

	var validate_r: Result = PlacementClass.validate_placement(ctx, "house_with_garden", position, rotation, piece_registry, {})
	var valid := validate_r.ok
	var message := "" if valid else validate_r.error

	var house_number := -1
	if is_instance_valid(house_placement_overlay) and house_placement_overlay.has_method("get_selected_house_number"):
		house_number = int(house_placement_overlay.get_selected_house_number())
	var cmd_params := {"position": [position.x, position.y], "rotation": rotation, "house_number": house_number}
	if is_instance_valid(house_placement_overlay) and house_placement_overlay.has_method("get_selected_employee"):
		var employee_type := str(house_placement_overlay.get_selected_employee()).strip_edges()
		if not employee_type.is_empty():
			cmd_params["employee_type"] = employee_type
	var cmd := Command.create("place_house", actor, cmd_params)
	cmd.phase = state.phase
	cmd.sub_phase = state.sub_phase
	var executor = engine.get_action_registry().get_executor("place_house")
	if executor != null:
		var ex_r: Result = executor.validate(state, cmd)
		if not ex_r.ok:
			valid = false
			message = ex_r.error

	if is_instance_valid(_map_canvas) and _map_canvas.has_method("set_structure_preview"):
		_map_canvas.call("set_structure_preview", footprint_cells, valid, {
			"piece_id": "house_with_garden",
			"anchor": position,
			"rotation": rotation,
		})

	# HousePlacementOverlay 目前没有 validation UI（只做预览与确认）

func on_piece_highlight_requested(action_id: String, rotation: int, piece_id: String) -> void:
	if _mode != "piece_placement":
		return
	if not (is_instance_valid(piece_placement_overlay) and piece_placement_overlay.visible):
		return
	if _scene == null:
		return
	var engine = _scene.game_engine
	if engine == null:
		return
	var state = engine.get_state()
	if state == null:
		return

	var aid := str(action_id).strip_edges()
	var pid := str(piece_id).strip_edges()
	if aid.is_empty() or pid.is_empty():
		_piece_valid_anchors.clear()
		if is_instance_valid(_map_canvas) and _map_canvas.has_method("clear_cell_highlights"):
			_map_canvas.call("clear_cell_highlights")
		return

	if not (state.map is Dictionary):
		return
	if not state.map.has("grid_size") or not (state.map["grid_size"] is Vector2i):
		return
	var grid_size: Vector2i = state.map["grid_size"]
	var map_origin: Vector2i = state.map.get("map_origin", Vector2i.ZERO)

	var actor: int = state.get_current_player_id()
	var executor = engine.get_action_registry().get_executor(aid)
	if executor == null:
		_piece_valid_anchors.clear()
		if is_instance_valid(_map_canvas) and _map_canvas.has_method("clear_cell_highlights"):
			_map_canvas.call("clear_cell_highlights")
		return

	var anchors: Array[Vector2i] = []
	var anchor_set := {}
	for y in range(grid_size.y):
		for x in range(grid_size.x):
			var world_anchor: Vector2i = Vector2i(x, y) - map_origin
			var cmd := Command.create(aid, actor, {
				"piece_id": pid,
				"anchor_pos": [world_anchor.x, world_anchor.y],
				"rotation": int(rotation),
			})
			cmd.phase = state.phase
			cmd.sub_phase = state.sub_phase
			var vr: Result = executor.validate(state, cmd)
			if not vr.ok:
				continue
			if anchor_set.has(world_anchor):
				continue
			anchor_set[world_anchor] = true
			anchors.append(world_anchor)

	_piece_valid_anchors = anchor_set
	if is_instance_valid(_map_canvas) and _map_canvas.has_method("set_cell_highlights"):
		_map_canvas.call("set_cell_highlights", anchors)

func on_piece_preview_cleared() -> void:
	if is_instance_valid(_map_canvas) and _map_canvas.has_method("clear_structure_preview"):
		_map_canvas.call("clear_structure_preview")
	if is_instance_valid(piece_placement_overlay) and piece_placement_overlay.has_method("set_validation"):
		piece_placement_overlay.set_validation(true, "")

func on_piece_preview_requested(action_id: String, position: Vector2i, rotation: int, piece_id: String) -> void:
	if _scene == null:
		return
	var engine = _scene.game_engine
	if engine == null:
		return
	var state = engine.get_state()
	if state == null:
		return

	var actor: int = state.get_current_player_id()
	var aid := str(action_id).strip_edges()
	var pid := str(piece_id).strip_edges()

	var footprint_cells: Array[Vector2i] = []
	var valid := true
	var message := ""

	if pid.is_empty():
		valid = false
		message = "piece_id 为空"
	elif not PieceRegistryClass.is_loaded():
		valid = false
		message = "PieceRegistry 未初始化"
	else:
		var piece_def_val = PieceRegistryClass.get_def(pid)
		if piece_def_val == null or not (piece_def_val is PieceDef):
			valid = false
			message = "未加载的 piece: %s" % pid
		else:
			var piece_def: PieceDef = piece_def_val
			footprint_cells = piece_def.get_world_cells(position, rotation)

	var cmd := Command.create(aid, actor, {
		"piece_id": pid,
		"anchor_pos": [position.x, position.y],
		"rotation": int(rotation),
	})
	cmd.phase = state.phase
	cmd.sub_phase = state.sub_phase
	var executor = engine.get_action_registry().get_executor(aid)
	if executor != null:
		var ex_r: Result = executor.validate(state, cmd)
		if not ex_r.ok:
			valid = false
			message = ex_r.error
	else:
		valid = false
		if message.is_empty():
			message = "无法找到执行器: %s" % aid

	if is_instance_valid(_map_canvas) and _map_canvas.has_method("set_structure_preview"):
		_map_canvas.call("set_structure_preview", footprint_cells, valid, {
			"piece_id": pid,
			"anchor": position,
			"rotation": int(rotation),
			"owner": actor,
		})
	if is_instance_valid(piece_placement_overlay) and piece_placement_overlay.has_method("set_validation"):
		piece_placement_overlay.set_validation(valid, message)
