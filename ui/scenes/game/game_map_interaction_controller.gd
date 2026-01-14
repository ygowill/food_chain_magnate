# Game scene：地图交互控制器
# 负责：map_canvas 选点/hover、营销预览、餐厅/房屋放置选点与预览/高亮
class_name GameMapInteractionController
extends RefCounted

signal mode_changed(mode: String, payload: Dictionary)
signal procure_drinks_source_selected(world_pos: Vector2i)

const PlacementValidatorClass = preload("res://core/map/placement_validator.gd")
const PieceDefClass = preload("res://core/map/piece_def.gd")
const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")
const MarketingTypeRegistryClass = preload("res://core/rules/marketing_type_registry.gd")
const MapRuntimeClass = preload("res://core/map/map_runtime.gd")
const RangeUtilsClass = preload("res://core/utils/range_utils.gd")
const ChoiceDialogScene = preload("res://ui/dialogs/choice_dialog.tscn")

var _scene = null
var _map_canvas = null
var _overlay_controller = null

var _mode: String = ""
var _payload: Dictionary = {}
var _restaurant_valid_anchors: Dictionary = {} # Vector2i -> true
var _house_valid_anchors: Dictionary = {} # Vector2i -> true
var _marketing_valid_anchors: Dictionary = {} # Vector2i -> true
var _distance_tool_from: Vector2i = Vector2i(-1, -1)
var _pending_airplane_corner_pos: Vector2i = Vector2i(-1, -1)

var marketing_panel = null
var restaurant_placement_overlay = null
var house_placement_overlay = null

func _init(scene, map_canvas, overlay_controller) -> void:
	_scene = scene
	_map_canvas = map_canvas
	_overlay_controller = overlay_controller

func connect_signals() -> void:
	if not is_instance_valid(_map_canvas):
		return
	if _map_canvas.has_signal("cell_selected") and not _map_canvas.cell_selected.is_connected(_on_map_cell_selected):
		_map_canvas.cell_selected.connect(_on_map_cell_selected)
	if _map_canvas.has_signal("cell_hovered") and not _map_canvas.cell_hovered.is_connected(_on_map_cell_hovered):
		_map_canvas.cell_hovered.connect(_on_map_cell_hovered)

func set_marketing_panel(panel) -> void:
	marketing_panel = panel

func set_restaurant_placement_overlay(overlay) -> void:
	restaurant_placement_overlay = overlay

func set_house_placement_overlay(overlay) -> void:
	house_placement_overlay = overlay

func begin_selection(mode: String, payload: Dictionary = {}) -> void:
	_mode = mode
	_payload = payload.duplicate(true)
	_restaurant_valid_anchors.clear()
	_house_valid_anchors.clear()
	_marketing_valid_anchors.clear()
	if is_instance_valid(_map_canvas) and _map_canvas.has_method("clear_cell_highlights"):
		_map_canvas.call("clear_cell_highlights")
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
	_restaurant_valid_anchors.clear()
	_house_valid_anchors.clear()
	_marketing_valid_anchors.clear()
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
			if not _marketing_valid_anchors.is_empty() and not _marketing_valid_anchors.has(world_pos):
				if is_instance_valid(marketing_panel) and marketing_panel.visible and marketing_panel.has_method("set_error"):
					marketing_panel.set_error("该位置不可放置，请选择绿色高亮的可放置格")
				return
			var mt := str(_payload.get("marketing_type", ""))
			if mt.is_empty():
				return

			if mt == "airplane":
				var axis := _infer_airplane_axis_for_pos(world_pos)
				if axis.is_empty():
					if _overlay_controller != null:
						_overlay_controller.hide_marketing_range_overlay()
					if is_instance_valid(marketing_panel) and marketing_panel.visible and marketing_panel.has_method("set_error"):
						marketing_panel.set_error("飞机必须放置在地图边缘")
					return

				if _is_airplane_corner(world_pos):
					_pending_airplane_corner_pos = world_pos
					_show_airplane_axis_dialog(Callable(self, "_on_airplane_axis_selected"), Callable(self, "_on_airplane_axis_cancelled"))
					return

				_payload["axis"] = axis
				_payload["selected_target"] = world_pos
				if is_instance_valid(marketing_panel) and marketing_panel.visible and marketing_panel.has_method("set_selected_target"):
					marketing_panel.set_selected_target(world_pos, axis)
				if _overlay_controller != null:
					_overlay_controller.preview_marketing_range(world_pos, 0, mt, {"axis": axis})
				return

			_payload.erase("axis")
			_payload.erase("selected_target")
			if is_instance_valid(marketing_panel) and marketing_panel.visible and marketing_panel.has_method("set_selected_target"):
				marketing_panel.set_selected_target(world_pos)
			if _overlay_controller != null:
				_overlay_controller.preview_marketing_range(world_pos, 0, mt)
		"restaurant_placement":
			# 仅允许点击“高亮的合法格”
			if _restaurant_valid_anchors.is_empty() or not _restaurant_valid_anchors.has(world_pos):
				if is_instance_valid(restaurant_placement_overlay) and restaurant_placement_overlay.visible and restaurant_placement_overlay.has_method("set_validation"):
					restaurant_placement_overlay.set_validation(false, "请选择绿色高亮的可放置格")
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
		"distance_tool":
			if _overlay_controller == null:
				return

			if _distance_tool_from == Vector2i(-1, -1):
				_distance_tool_from = world_pos
				_overlay_controller.hide_distance_overlay()
				GameLog.info("Game", "距离工具：起点=%s，请选择终点" % str(world_pos))
				return

			# 再次点击起点视为重置
			if world_pos == _distance_tool_from:
				_distance_tool_from = Vector2i(-1, -1)
				_overlay_controller.hide_distance_overlay()
				GameLog.info("Game", "距离工具：已清除起点，请重新选择起点")
				return

			var to_positions: Array[Vector2i] = []
			to_positions.append(world_pos)
			_overlay_controller.show_distance_overlay(_distance_tool_from, to_positions)
		_:
			pass

func _sync_procure_drinks_highlights() -> void:
	if not is_instance_valid(_map_canvas):
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
	if world_pos == Vector2i(-1, -1):
		if _overlay_controller != null:
			_overlay_controller.hide_marketing_range_overlay()
		return

	var mt := str(_payload.get("marketing_type", ""))
	if mt.is_empty():
		return

	if _overlay_controller != null:
		if mt == "airplane":
			var axis := _infer_airplane_axis_for_pos(world_pos)
			if axis.is_empty():
				_overlay_controller.hide_marketing_range_overlay()
				return
			if _is_airplane_corner(world_pos):
				var selected_pos_val = _payload.get("selected_target", null)
				if selected_pos_val is Vector2i and Vector2i(selected_pos_val) == world_pos:
					var chosen := str(_payload.get("axis", ""))
					if chosen == "row" or chosen == "col":
						axis = chosen
			_overlay_controller.preview_marketing_range(world_pos, 0, mt, {"axis": axis})
		else:
			_overlay_controller.preview_marketing_range(world_pos, 0, mt)

func on_marketing_map_selection_requested(marketing_type: String, employee_type: String = "") -> void:
	begin_selection("marketing", {
		"marketing_type": marketing_type,
		"employee_type": employee_type,
	})
	if _overlay_controller != null:
		_overlay_controller.hide_marketing_range_overlay()
	_sync_marketing_highlights()

func _sync_marketing_highlights() -> void:
	if not is_instance_valid(_map_canvas):
		return
	if _mode != "marketing":
		return

	_marketing_valid_anchors.clear()
	if _map_canvas.has_method("clear_cell_highlights"):
		_map_canvas.call("clear_cell_highlights")

	var mt := str(_payload.get("marketing_type", ""))
	var employee_type := str(_payload.get("employee_type", ""))
	if mt.is_empty() or employee_type.is_empty():
		return
	if not MarketingTypeRegistryClass.is_loaded() or not MarketingTypeRegistryClass.has_type(mt):
		return
	if not EmployeeRegistryClass.is_loaded():
		return
	var emp_def_val = EmployeeRegistryClass.get_def(employee_type)
	if emp_def_val == null or not (emp_def_val is EmployeeDef):
		return
	var emp_def: EmployeeDef = emp_def_val

	if _scene == null or _scene.game_engine == null:
		return
	var state: GameState = _scene.game_engine.get_state()
	if state == null:
		return
	if not (state.map is Dictionary):
		return
	if not state.map.has("grid_size") or not (state.map["grid_size"] is Vector2i):
		return
	var grid_size: Vector2i = state.map["grid_size"]
	if grid_size.x <= 0 or grid_size.y <= 0:
		return

	var actor: int = int(state.get_current_player_id())
	var restaurant_ids := MapRuntimeClass.get_player_restaurants(state, actor)

	var occupied_positions := {}
	if state.map.has("marketing_placements") and (state.map["marketing_placements"] is Dictionary):
		var placements: Dictionary = state.map["marketing_placements"]
		for k in placements.keys():
			var p_val = placements[k]
			if not (p_val is Dictionary):
				continue
			var p: Dictionary = p_val
			var pos_val = p.get("world_pos", null)
			if pos_val is Vector2i:
				occupied_positions[pos_val] = true

		var requires_edge := MarketingTypeRegistryClass.requires_edge(mt)
		var range_type := str(emp_def.range_type)
		var range_value := int(emp_def.range_value)
		var range_required := range_value >= 0 and not range_type.is_empty()
		var range_error := ""
		var has_any_road := false
		var empty_structure_cells_total := 0
		var base_candidates := 0
		var out_of_range_candidates := 0

		# 若员工存在距离限制：没有餐厅则必定无可放置格（提示原因，避免误解为 UI bug）
		if range_required and restaurant_ids.is_empty():
			if is_instance_valid(marketing_panel) and marketing_panel.visible and marketing_panel.has_method("set_error"):
				var rt := range_type
				var rv := range_value
				marketing_panel.set_error("没有可放置格：你还没有餐厅（距离限制：%s %d）" % [rt, rv])
			return

		var valid: Array[Vector2i] = []
		for y in range(grid_size.y):
			for x in range(grid_size.x):
				var world_pos := MapRuntimeClass.index_to_world(state, Vector2i(x, y))

				var cell := MapRuntimeClass.get_cell(state, world_pos)
				if cell.is_empty():
					continue

				# 统计：是否存在道路（用于“必须邻路”类营销的失败原因提示）
				if not requires_edge and not has_any_road:
					var rs_val = cell.get("road_segments", null)
					if rs_val is Array and not (rs_val as Array).is_empty():
						has_any_road = true

				var structure_val = cell.get("structure", null)
				if not (structure_val is Dictionary):
					continue
				if not (structure_val as Dictionary).is_empty():
					continue
				empty_structure_cells_total += 1

				if occupied_positions.has(world_pos):
					continue
				if requires_edge and not MapRuntimeClass.is_on_map_edge(state, world_pos):
					continue

				if not requires_edge:
					var blocked_val = cell.get("blocked", null)
					if not (blocked_val is bool) or bool(blocked_val):
						continue
				var road_segments_val = cell.get("road_segments", null)
				if not (road_segments_val is Array):
					continue
				if not (road_segments_val as Array).is_empty():
					continue
				var adjacent_roads_r := RangeUtilsClass.get_adjacent_road_cells(state, world_pos)
				if not adjacent_roads_r.ok:
					continue
					var adjacent_roads: Array = adjacent_roads_r.value
					if adjacent_roads.is_empty():
						continue

				# 统计：通过“结构/邻路/边缘”等基础约束的候选点数量
				base_candidates += 1

				# 距离校验（对齐 InitiateMarketingAction.validate）
				if range_required:
					if range_type == "road":
						var ok_r := RangeUtilsClass.is_within_road_range(state, actor, restaurant_ids, world_pos, range_value)
						if not ok_r.ok:
							if range_error.is_empty():
								range_error = str(ok_r.error)
							continue
						if not bool(ok_r.value):
							out_of_range_candidates += 1
							continue
					elif range_type == "air":
						var ok_r := RangeUtilsClass.is_within_air_range(state, actor, restaurant_ids, world_pos, range_value)
						if not ok_r.ok:
							if range_error.is_empty():
								range_error = str(ok_r.error)
							continue
						if not bool(ok_r.value):
							out_of_range_candidates += 1
							continue
					else:
						if range_error.is_empty():
							range_error = "未知的 range_type: %s" % range_type
						continue

				_marketing_valid_anchors[world_pos] = true
				valid.append(world_pos)

		if _map_canvas.has_method("set_cell_highlights"):
			_map_canvas.call("set_cell_highlights", valid)

		# 无可放置格：在面板中给出可理解的原因提示
		if valid.is_empty():
			var msg := ""
			if not range_error.is_empty():
				msg = "无法计算可放置范围：%s" % range_error
			elif empty_structure_cells_total <= 0:
				msg = "没有可放置格：地图上没有空地（所有格子都有建筑）"
			elif requires_edge:
				if base_candidates <= 0:
					msg = "没有可放置格：该营销必须放在地图边缘的空地"
				elif range_required and out_of_range_candidates >= base_candidates:
					msg = "没有可放置格：全部边缘候选点超出距离范围（%s %d）" % [range_type, range_value]
				else:
					msg = "没有可放置格：没有满足规则的边缘空地"
			else:
				if base_candidates <= 0:
					if not has_any_road:
						msg = "没有可放置格：地图上没有道路（该营销必须邻接道路的空地）"
					else:
						msg = "没有可放置格：没有邻接道路的空地（且不能占用道路/阻塞格/有建筑格）"
				elif range_required and out_of_range_candidates >= base_candidates:
					msg = "没有可放置格：全部候选点超出距离范围（%s %d）" % [range_type, range_value]
				else:
					msg = "没有可放置格：没有满足规则的空地"

			if not msg.is_empty():
				if is_instance_valid(marketing_panel) and marketing_panel.visible and marketing_panel.has_method("set_error"):
					marketing_panel.set_error(msg)

func _is_airplane_corner(world_pos: Vector2i) -> bool:
	if _scene == null or _scene.game_engine == null:
		return false
	var state: GameState = _scene.game_engine.get_state()
	if state == null:
		return false
	var minp := MapRuntimeClass.get_world_min(state)
	var maxp := MapRuntimeClass.get_world_max(state)
	var on_x_edge := world_pos.x == minp.x or world_pos.x == maxp.x
	var on_y_edge := world_pos.y == minp.y or world_pos.y == maxp.y
	return on_x_edge and on_y_edge

func _infer_airplane_axis_for_pos(world_pos: Vector2i) -> String:
	if _scene == null or _scene.game_engine == null:
		return ""
	var state: GameState = _scene.game_engine.get_state()
	if state == null:
		return ""
	var minp := MapRuntimeClass.get_world_min(state)
	var maxp := MapRuntimeClass.get_world_max(state)
	if world_pos.x == minp.x or world_pos.x == maxp.x:
		return "row"
	if world_pos.y == minp.y or world_pos.y == maxp.y:
		return "col"
	return ""

func _show_airplane_axis_dialog(on_selected: Callable, on_cancel: Callable = Callable()) -> void:
	if _scene == null:
		return
	if OS.has_feature("headless"):
		if on_selected.is_valid():
			on_selected.call("row")
		return

	if ChoiceDialogScene == null:
		return

	var dialog = ChoiceDialogScene.instantiate()
	if dialog == null:
		return

	var cleanup := func():
		if is_instance_valid(dialog):
			dialog.hide()
			dialog.queue_free()

	if dialog.has_signal("option_selected"):
		dialog.option_selected.connect(func(option_id: String):
			cleanup.call()
			if on_selected.is_valid():
				on_selected.call(str(option_id))
		)
	if dialog.has_signal("cancelled"):
		dialog.cancelled.connect(func():
			cleanup.call()
			if on_cancel.is_valid():
				on_cancel.call()
		)

	_scene.add_child(dialog)
	if dialog.has_method("setup"):
		dialog.setup(
			"选择飞行方向",
			"飞机位于角落：请选择横飞（整行）或竖飞（整列）",
			[
				{"id": "row", "text": "横飞（行）"},
				{"id": "col", "text": "竖飞（列）"},
			],
			"取消"
		)
	if dialog.has_method("show_dialog"):
		dialog.show_dialog()
	else:
		dialog.popup_centered()

func _on_airplane_axis_selected(axis: String) -> void:
	var pos := _pending_airplane_corner_pos
	_pending_airplane_corner_pos = Vector2i(-1, -1)
	if pos == Vector2i(-1, -1):
		return
	var mt := str(_payload.get("marketing_type", ""))
	if mt != "airplane":
		return
	if axis != "row" and axis != "col":
		return

	_payload["axis"] = axis
	_payload["selected_target"] = pos

	if is_instance_valid(marketing_panel) and marketing_panel.visible and marketing_panel.has_method("set_selected_target"):
		marketing_panel.set_selected_target(pos, axis)
	if _overlay_controller != null:
		_overlay_controller.preview_marketing_range(pos, 0, mt, {"axis": axis})

func _on_airplane_axis_cancelled() -> void:
	_pending_airplane_corner_pos = Vector2i(-1, -1)
	if is_instance_valid(marketing_panel) and marketing_panel.visible and marketing_panel.has_method("set_error"):
		marketing_panel.set_error("未选择飞行方向")

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
			var r: Result = PlacementValidatorClass.validate_restaurant_placement(
				ctx,
				world_anchor,
				rotation,
				piece_registry,
				actor,
				state.phase == "Setup",
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
	if not piece_registry.has("house") or not (piece_registry["house"] is PieceDef):
		piece_registry["house"] = PieceDefClass.create_house()

	var ctx := {
		"cells": state.map.cells,
		"grid_size": state.map.grid_size,
		"map_origin": map_origin,
		"houses": state.map.houses,
		"restaurants": state.map.restaurants,
		"drink_sources": state.map.get("drink_sources", []),
	}

	var anchors: Array[Vector2i] = []
	var anchor_set := {}
	for y in range(grid_size.y):
		for x in range(grid_size.x):
			var world_anchor: Vector2i = Vector2i(x, y) - map_origin
			var r: Result = PlacementValidatorClass.validate_house_placement(
				ctx,
				world_anchor,
				rotation,
				piece_registry,
				actor,
				{}
			)
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
	}

	var extra := {}
	if action_id == "move_restaurant" and not restaurant_id.is_empty():
		if state.map.restaurants.has(restaurant_id):
			var rest: Dictionary = state.map.restaurants[restaurant_id]
			if rest.has("cells") and (rest["cells"] is Array):
				extra["ignore_structure_cells"] = rest["cells"]

	var validate_r: Result = PlacementValidatorClass.validate_restaurant_placement(
		ctx,
		position,
		rotation,
		piece_registry,
		actor,
		state.phase == "Setup",
		extra
	)

	var valid := validate_r.ok
	var message := "" if valid else validate_r.error

	# 额外约束：与动作执行器一致的“回合/次数/数量”检查（避免只靠放置校验导致误导）
	# 这里用执行器 validate（包含员工/回合等规则），确保提示与真实执行一致
	var cmd_params := {"position": [position.x, position.y], "rotation": rotation}
	if action_id == "move_restaurant" and not restaurant_id.is_empty():
		cmd_params["restaurant_id"] = restaurant_id
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
	if not piece_registry.has("house") or not (piece_registry["house"] is PieceDef):
		piece_registry["house"] = PieceDefClass.create_house()
	var piece_def_val = piece_registry.get("house", null)
	var piece_def: PieceDef = piece_def_val if piece_def_val is PieceDef else PieceDefClass.create_house()
	var footprint_cells: Array[Vector2i] = piece_def.get_world_cells(position, rotation)

	var ctx := {
		"cells": state.map.cells,
		"grid_size": state.map.grid_size,
		"map_origin": state.map.get("map_origin", Vector2i.ZERO),
		"houses": state.map.houses,
		"restaurants": state.map.restaurants,
		"drink_sources": state.map.get("drink_sources", []),
	}

	var validate_r: Result = PlacementValidatorClass.validate_house_placement(
		ctx,
		position,
		rotation,
		piece_registry,
		actor,
		{}
	)
	var valid := validate_r.ok
	var message := "" if valid else validate_r.error

	var cmd := Command.create("place_house", actor, {"position": [position.x, position.y], "rotation": rotation})
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
			"piece_id": "house",
			"anchor": position,
			"rotation": rotation,
		})

	# HousePlacementOverlay 目前没有 validation UI（只做预览与确认）
