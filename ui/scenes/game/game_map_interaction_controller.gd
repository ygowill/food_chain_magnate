# Game scene：地图交互控制器
# 负责：map_canvas 选点/hover、营销预览、餐厅/房屋放置选点与预览/高亮
class_name GameMapInteractionController
extends RefCounted

signal mode_changed(mode: String, payload: Dictionary)
signal procure_drinks_source_selected(world_pos: Vector2i)

const PlacementClass = preload("res://core/map/placement_validator/placement.gd")
const RestaurantPlacementClass = preload("res://core/map/placement_validator/restaurant_placement.gd")
const PieceDefClass = preload("res://core/map/piece_def.gd")
const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")
const MarketingRegistryClass = preload("res://core/data/marketing_registry.gd")
const MarketingTypeRegistryClass = preload("res://core/rules/marketing_type_registry.gd")
const CellsClass = preload("res://core/map/map_runtime/cells.gd")
const CoordsClass = preload("res://core/map/map_runtime/coords.gd")
const StructuresClass = preload("res://core/map/map_runtime/structures.gd")
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

func begin_selection(mode: String, payload: Dictionary = {}) -> void:
	_mode = mode
	_payload = payload.duplicate(true)
	_restaurant_valid_anchors.clear()
	_house_valid_anchors.clear()
	_marketing_valid_anchors.clear()
	if is_instance_valid(_map_canvas) and _map_canvas.has_method("clear_cell_highlights"):
		_map_canvas.call("clear_cell_highlights")
	if is_instance_valid(_map_canvas) and _map_canvas.has_method("clear_move_restaurant_selected_restaurant"):
		_map_canvas.call("clear_move_restaurant_selected_restaurant")
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
			if not _marketing_valid_anchors.has(world_pos):
				_call_marketing_panel_method("set_error", ["该位置不可放置，请选择绿色高亮的可放置格"])
				return
			var mt := str(_payload.get("marketing_type", ""))
			if mt.is_empty():
				return

			if mt == "airplane":
				var axis := _infer_airplane_axis_for_pos(world_pos)
				if axis.is_empty():
					if _overlay_controller != null:
						_overlay_controller.hide_marketing_range_overlay()
					_call_marketing_panel_method("set_error", ["飞机必须有一条边完全贴地图边缘"])
					return

				if _is_airplane_corner(world_pos):
					_pending_airplane_corner_pos = world_pos
					_show_airplane_axis_dialog(Callable(self, "_on_airplane_axis_selected"), Callable(self, "_on_airplane_axis_cancelled"))
					return

				_payload["axis"] = axis
				_payload["selected_target"] = world_pos
				_call_marketing_panel_method("set_selected_target", [world_pos, axis])
				if _overlay_controller != null:
					_overlay_controller.preview_marketing_range(world_pos, 0, mt, {"axis": axis})
				return

			_payload.erase("axis")
			_payload.erase("selected_target")
			_call_marketing_panel_method("set_selected_target", [world_pos])
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
	if world_pos == Vector2i(-1, -1):
		if _overlay_controller != null:
			_overlay_controller.hide_marketing_range_overlay()
		if is_instance_valid(_map_canvas) and _map_canvas.has_method("clear_structure_preview"):
			_map_canvas.call("clear_structure_preview")
		return

	var mt := str(_payload.get("marketing_type", ""))
	if mt.is_empty():
		if is_instance_valid(_map_canvas) and _map_canvas.has_method("clear_structure_preview"):
			_map_canvas.call("clear_structure_preview")
		return

	if not _marketing_valid_anchors.has(world_pos):
		if _overlay_controller != null:
			_overlay_controller.hide_marketing_range_overlay()
		if is_instance_valid(_map_canvas) and _map_canvas.has_method("clear_structure_preview"):
			_map_canvas.call("clear_structure_preview")
		return

	# footprint 预览：hover 到合法 anchor 时展示 marketing board 的占地形状（允许透明）。
	var size := _get_selected_marketing_board_rotated_size()
	if size.x > 0 and size.y > 0:
		var cells: Array[Vector2i] = []
		for dy in range(size.y):
			for dx in range(size.x):
				cells.append(world_pos + Vector2i(dx, dy))
		if is_instance_valid(_map_canvas) and _map_canvas.has_method("set_structure_preview"):
			_map_canvas.call("set_structure_preview", cells, true)

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
	if not is_instance_valid(_map_canvas):
		return
	if _mode != "marketing":
		return

	_marketing_valid_anchors.clear()
	if _map_canvas.has_method("clear_cell_highlights"):
		_map_canvas.call("clear_cell_highlights")

	var mt := str(_payload.get("marketing_type", ""))
	var employee_type := str(_payload.get("employee_type", ""))
	var board_number := int(_payload.get("board_number", 0))
	var rotation := int(_payload.get("rotation", 0))
	if mt.is_empty() or employee_type.is_empty() or board_number <= 0:
		return
	if not rotation in [0, 90, 180, 270]:
		rotation = 0
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
	var restaurant_ids := StructuresClass.get_player_restaurants(state, actor)

	# 选中板件占地（用于高亮可放置 anchor）
	var base_size := Vector2i.ONE
	if MarketingRegistryClass.is_loaded():
		var def = MarketingRegistryClass.get_def(board_number)
		if def != null:
			if def is MarketingDef:
				base_size = (def as MarketingDef).footprint_size
			elif def.has_method("get"):
				var fs = def.get("footprint_size")
				if fs is Vector2i:
					base_size = fs
	if base_size.x <= 0 or base_size.y <= 0:
		return

	var size := base_size
	if rotation == 90 or rotation == 270:
		size = Vector2i(base_size.y, base_size.x)

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
		var rt := range_type
		var rv := range_value
		_call_marketing_panel_method("set_error", ["没有可放置格：你还没有餐厅（距离限制：%s %d）" % [rt, rv]])
		return

	# 统计：是否存在道路 / 空地（用于错误提示）
	for y2 in range(grid_size.y):
		for x2 in range(grid_size.x):
			var wp2 := CoordsClass.index_to_world(state, Vector2i(x2, y2))
			var cell2 := CellsClass.get_cell(state, wp2)
			if cell2.is_empty():
				continue
			if not requires_edge and not has_any_road:
				var rs_val = cell2.get("road_segments", null)
				if rs_val is Array and not (rs_val as Array).is_empty():
					has_any_road = true
			var structure_val = cell2.get("structure", null)
			if structure_val is Dictionary and (structure_val as Dictionary).is_empty():
				empty_structure_cells_total += 1

	# 营销占地：预先构建占用集合（考虑 footprint + rotation），避免每个候选点重复遍历
	var occupied_cells := {}
	if state.map.has("marketing_placements") and (state.map["marketing_placements"] is Dictionary):
		var placements: Dictionary = state.map["marketing_placements"]
		for k in placements.keys():
			var p_val = placements[k]
			if not (p_val is Dictionary):
				continue
			var p: Dictionary = p_val
			var pos_val = p.get("world_pos", null)
			if not (pos_val is Vector2i):
				continue
			var anchor: Vector2i = pos_val

			# footprint_size/rotation 为新增字段；缺失则按 1x1/rotation=0 兜底（兼容旧存档/测试）。
			var p_base_size := Vector2i.ONE
			var fs_val = p.get("footprint_size", null)
			if fs_val is Vector2i:
				p_base_size = Vector2i(fs_val)
			elif fs_val is Array:
				var arr: Array = fs_val
				if arr.size() == 2:
					p_base_size = Vector2i(int(arr[0]), int(arr[1]))

			var p_rot := 0
			var rot_val = p.get("rotation", null)
			if rot_val is int:
				p_rot = int(rot_val)
			elif rot_val is float:
				var f: float = float(rot_val)
				if f == floor(f):
					p_rot = int(f)
			if not p_rot in [0, 90, 180, 270]:
				p_rot = 0

			var p_size := p_base_size
			if p_rot == 90 or p_rot == 270:
				p_size = Vector2i(p_base_size.y, p_base_size.x)

			for dy in range(p_size.y):
				for dx in range(p_size.x):
					occupied_cells[anchor + Vector2i(dx, dy)] = true

	var minp := CoordsClass.get_world_min(state)
	var maxp := CoordsClass.get_world_max(state)

	var valid: Array[Vector2i] = []
	for y in range(grid_size.y):
		for x in range(grid_size.x):
			var anchor_pos := CoordsClass.index_to_world(state, Vector2i(x, y))

			# 占地 cells：top-left anchor + rotated size
			var footprint_cells: Array[Vector2i] = []
			var footprint_ok := true
			for dy2 in range(size.y):
				for dx2 in range(size.x):
					var p2 := anchor_pos + Vector2i(dx2, dy2)
					footprint_cells.append(p2)

					# 越界/占用
					if not CoordsClass.is_world_pos_in_grid(state, p2):
						footprint_ok = false
						break
					if occupied_cells.has(p2):
						footprint_ok = false
						break

					var cell3 := CellsClass.get_cell(state, p2)
					if cell3.is_empty():
						footprint_ok = false
						break

					var structure_val2 = cell3.get("structure", null)
					if not (structure_val2 is Dictionary):
						footprint_ok = false
						break
					if not (structure_val2 as Dictionary).is_empty():
						footprint_ok = false
						break

					# 非边缘营销：占地必须是空地（非道路/非阻塞）
					if not requires_edge:
						var blocked_val2 = cell3.get("blocked", null)
						if not (blocked_val2 is bool) or bool(blocked_val2):
							footprint_ok = false
							break
						var road_segments_val2 = cell3.get("road_segments", null)
						if not (road_segments_val2 is Array):
							footprint_ok = false
							break
						if not (road_segments_val2 as Array).is_empty():
							footprint_ok = false
							break
				if not footprint_ok:
					break

			if not footprint_ok:
				continue

			# 边缘营销：要求“整条边贴边”（不能超出）
			if requires_edge:
				var left := anchor_pos.x
				var right := anchor_pos.x + size.x - 1
				var top := anchor_pos.y
				var bottom := anchor_pos.y + size.y - 1
				var flush := (left == minp.x) or (right == maxp.x) or (top == minp.y) or (bottom == maxp.y)
				if not flush:
					continue
			else:
				# 非边缘营销：占地整体需邻接道路
				var adjacent_roads_r := RangeUtilsClass.get_adjacent_road_cells_for_positions(state, footprint_cells)
				if not adjacent_roads_r.ok:
					continue
				var adjacent_roads: Array[Vector2i] = adjacent_roads_r.value
				if adjacent_roads.is_empty():
					continue

			# 统计：通过“结构/邻路/边缘”等基础约束的候选点数量
			base_candidates += 1

			# 距离校验（对齐 InitiateMarketingAction.validate）
			if range_required:
				if range_type == "road":
					var target_roads_r := RangeUtilsClass.get_adjacent_road_cells_for_positions(state, footprint_cells)
					if not target_roads_r.ok:
						if range_error.is_empty():
							range_error = str(target_roads_r.error)
						continue
					var target_road_cells: Array[Vector2i] = target_roads_r.value
					var ok_r := RangeUtilsClass.is_within_road_range_to_any_road_cells(
						state, actor, restaurant_ids, target_road_cells, range_value
					)
					if not ok_r.ok:
						if range_error.is_empty():
							range_error = str(ok_r.error)
						continue
					if not bool(ok_r.value):
						out_of_range_candidates += 1
						continue
				elif range_type == "air":
					var ok_r := RangeUtilsClass.is_within_air_range_to_any_cells(
						state, actor, restaurant_ids, footprint_cells, range_value
					)
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

			_marketing_valid_anchors[anchor_pos] = true
			valid.append(anchor_pos)

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
				msg = "没有可放置格：该营销必须有一条边完全贴地图边缘"
			elif range_required and out_of_range_candidates >= base_candidates:
				msg = "没有可放置格：全部候选点超出距离范围（%s %d）" % [range_type, range_value]
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
				_call_marketing_panel_method("set_error", [msg])

func _is_airplane_corner(world_pos: Vector2i) -> bool:
	if _scene == null or _scene.game_engine == null:
		return false
	var state: GameState = _scene.game_engine.get_state()
	if state == null:
		return false
	var size := _get_selected_marketing_board_rotated_size()
	if size.x <= 0 or size.y <= 0:
		return false
	var minp := CoordsClass.get_world_min(state)
	var maxp := CoordsClass.get_world_max(state)
	var left := world_pos.x
	var right := world_pos.x + size.x - 1
	var top := world_pos.y
	var bottom := world_pos.y + size.y - 1
	var on_x_edge := left == minp.x or right == maxp.x
	var on_y_edge := top == minp.y or bottom == maxp.y
	return on_x_edge and on_y_edge

func _infer_airplane_axis_for_pos(world_pos: Vector2i) -> String:
	if _scene == null or _scene.game_engine == null:
		return ""
	var state: GameState = _scene.game_engine.get_state()
	if state == null:
		return ""
	var size := _get_selected_marketing_board_rotated_size()
	if size.x <= 0 or size.y <= 0:
		return ""
	var minp := CoordsClass.get_world_min(state)
	var maxp := CoordsClass.get_world_max(state)
	var left := world_pos.x
	var right := world_pos.x + size.x - 1
	var top := world_pos.y
	var bottom := world_pos.y + size.y - 1
	if left == minp.x or right == maxp.x:
		return "row"
	if top == minp.y or bottom == maxp.y:
		return "col"
	return ""

func _get_selected_marketing_board_rotated_size() -> Vector2i:
	var board_number := int(_payload.get("board_number", 0))
	var rotation := int(_payload.get("rotation", 0))
	if not rotation in [0, 90, 180, 270]:
		rotation = 0

	var base_size := Vector2i.ONE
	if MarketingRegistryClass.is_loaded() and board_number > 0:
		var def = MarketingRegistryClass.get_def(board_number)
		if def != null:
			if def is MarketingDef:
				base_size = (def as MarketingDef).footprint_size
			elif def.has_method("get"):
				var fs = def.get("footprint_size")
				if fs is Vector2i:
					base_size = fs

	if base_size.x <= 0 or base_size.y <= 0:
		base_size = Vector2i.ONE

	var size := base_size
	if rotation == 90 or rotation == 270:
		size = Vector2i(base_size.y, base_size.x)
	return size

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

	_call_marketing_panel_method("set_selected_target", [pos, axis])
	if _overlay_controller != null:
		_overlay_controller.preview_marketing_range(pos, 0, mt, {"axis": axis})

func _on_airplane_axis_cancelled() -> void:
	_pending_airplane_corner_pos = Vector2i(-1, -1)
	_call_marketing_panel_method("set_error", ["未选择飞行方向"])

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
