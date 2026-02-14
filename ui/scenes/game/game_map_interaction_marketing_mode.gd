# Game scene：地图交互控制器 - Marketing 模式逻辑下沉
# 负责：marketing 高亮计算、hover 预览、点击映射（含外围营销：airplane 的外圈选择）。
class_name GameMapInteractionMarketingMode
extends RefCounted

const MarketingRegistryClass = preload("res://core/data/marketing_registry.gd")
const MarketingTypeRegistryClass = preload("res://core/rules/marketing_type_registry.gd")
const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")
const CellsClass = preload("res://core/map/map_runtime/cells.gd")
const CoordsClass = preload("res://core/map/map_runtime/coords.gd")
const StructuresClass = preload("res://core/map/map_runtime/structures.gd")
const RangeUtilsClass = preload("res://core/utils/range_utils.gd")

var _controller = null

func _init(controller) -> void:
	_controller = controller

func dispose() -> void:
	_controller = null

func on_cell_selected(world_pos: Vector2i) -> void:
	if _controller == null:
		return
	if _controller._mode != "marketing":
		return

	var mt0 := str(_controller._payload.get("marketing_type", ""))
	var mapped_anchor := world_pos
	var outside_axis := ""
	var outside_attach := ""
	if mt0 == "airplane" and not _controller._marketing_outside_to_anchor.is_empty() and _controller._marketing_outside_to_anchor.has(world_pos):
		var info_val = _controller._marketing_outside_to_anchor.get(world_pos, null)
		if info_val is Dictionary:
			var info: Dictionary = info_val
			var inside_val = info.get("anchor", null)
			if inside_val is Vector2i:
				mapped_anchor = Vector2i(inside_val)
			var axis_val = info.get("axis", null)
			if axis_val is String:
				outside_axis = str(axis_val)
			var attach_val = info.get("attach", null)
			if attach_val is String:
				outside_attach = str(attach_val)

	if not _controller._marketing_valid_anchors.has(world_pos):
		_controller._call_marketing_panel_method("set_error", ["该位置不可放置，请选择高亮的可放置格"])
		return
	var mt := mt0
	if mt.is_empty():
		return

	# Clicking a valid target should "lock" the preview/range at that location.
	# Refresh the preview for this click even if a previous target was already selected.
	_controller._payload.erase("selected_target")
	on_cell_hovered(world_pos)

	if mt == "airplane":
		var axis := outside_axis
		if axis.is_empty():
			axis = _infer_airplane_axis_for_pos(mapped_anchor)
		if axis.is_empty():
			if _controller._overlay_controller != null:
				_controller._overlay_controller.hide_marketing_range_overlay()
			_controller._call_marketing_panel_method("set_error", ["飞机必须有一条边完全贴地图边缘"])
			return

		_controller._payload["axis"] = axis
		_controller._payload["attach"] = outside_attach
		_controller._payload["selected_target"] = mapped_anchor
		_controller._call_marketing_panel_method("set_selected_target", [mapped_anchor, axis])
		if _controller._overlay_controller != null:
			var fs := _get_selected_marketing_board_base_size()
			_controller._overlay_controller.preview_marketing_range(mapped_anchor, 0, mt, {"axis": axis, "footprint_size": fs})
		return

	_controller._payload.erase("axis")
	_controller._payload.erase("attach")
	_controller._payload["selected_target"] = mapped_anchor
	_controller._call_marketing_panel_method("set_selected_target", [mapped_anchor])
	if _controller._overlay_controller != null:
		_controller._overlay_controller.preview_marketing_range(mapped_anchor, 0, mt)

func on_cell_hovered(world_pos: Vector2i) -> void:
	if _controller == null:
		return
	if _controller._mode != "marketing":
		return

	# Once the player has clicked a valid target, keep the preview fixed at that location
	# until confirm/cancel (issue_tracker #43).
	var selected_val = _controller._payload.get("selected_target", null)
	if selected_val is Vector2i and Vector2i(selected_val) != Vector2i(-1, -1):
		return
	if world_pos == Vector2i(-1, -1):
		if _controller._overlay_controller != null:
			_controller._overlay_controller.hide_marketing_range_overlay()
		if is_instance_valid(_controller._map_canvas) and _controller._map_canvas.has_method("clear_structure_preview"):
			_controller._map_canvas.call("clear_structure_preview")
		return

	var mt := str(_controller._payload.get("marketing_type", ""))
	if mt.is_empty():
		if is_instance_valid(_controller._map_canvas) and _controller._map_canvas.has_method("clear_structure_preview"):
			_controller._map_canvas.call("clear_structure_preview")
		return

	if not _controller._marketing_valid_anchors.has(world_pos):
		if _controller._overlay_controller != null:
			_controller._overlay_controller.hide_marketing_range_overlay()
		if is_instance_valid(_controller._map_canvas) and _controller._map_canvas.has_method("clear_structure_preview"):
			_controller._map_canvas.call("clear_structure_preview")
		return

	# footprint 预览：hover 到合法 anchor 时展示 marketing board 的占地形状（允许透明）。
	var preview_anchor := world_pos
	var outside_axis := ""
	var outside_attach := ""
	if mt == "airplane" and not _controller._marketing_outside_to_anchor.is_empty() and _controller._marketing_outside_to_anchor.has(world_pos):
		var info_val = _controller._marketing_outside_to_anchor.get(world_pos, null)
		if info_val is Dictionary:
			var info: Dictionary = info_val
			var inside_val = info.get("anchor", null)
			if inside_val is Vector2i:
				preview_anchor = Vector2i(inside_val)
			var axis_val = info.get("axis", null)
			if axis_val is String:
				outside_axis = str(axis_val)
			var attach_val = info.get("attach", null)
			if attach_val is String:
				outside_attach = str(attach_val)

	var size := _get_selected_marketing_board_rotated_size()
	var offset := Vector2i.ZERO

	if mt == "airplane":
		# 外围营销：rotation 无意义；由贴边位置决定朝向（issue_tracker #40/#42）。
		var base_size := _get_selected_marketing_board_base_size()
		var thickness := 2
		var length := 0
		if base_size.x == 2 and base_size.y != 2:
			length = base_size.y
		elif base_size.y == 2 and base_size.x != 2:
			length = base_size.x
		else:
			thickness = mini(base_size.x, base_size.y)
			length = maxi(base_size.x, base_size.y)
		var axis2 := outside_axis
		if axis2.is_empty():
			axis2 = _infer_airplane_axis_for_pos(preview_anchor)
		var attach2 := outside_attach
		if attach2.is_empty() and _controller._scene != null and _controller._scene.game_engine != null:
			var state2: GameState = _controller._scene.game_engine.get_state()
			if state2 != null:
				var minp2 := CoordsClass.get_world_min(state2)
				var maxp2 := CoordsClass.get_world_max(state2)
				if axis2 == "row":
					attach2 = "left" if preview_anchor.x == minp2.x else "right" if preview_anchor.x == maxp2.x else ""
				elif axis2 == "col":
					attach2 = "top" if preview_anchor.y == minp2.y else "bottom" if preview_anchor.y == maxp2.y else ""

		# Axis determines oriented size (length along edge, thickness outward).
		if axis2 == "row":
			size = Vector2i(maxi(1, thickness), maxi(1, length))
		else:
			size = Vector2i(maxi(1, length), maxi(1, thickness))

		# Offset to outside cells: left/top uses -size, right/bottom starts at +1 from the edge cell.
		match attach2:
			"left":
				offset = Vector2i(-size.x, 0)
			"right":
				offset = Vector2i(1, 0)
			"top":
				offset = Vector2i(0, -size.y)
			"bottom":
				offset = Vector2i(0, 1)

	if size.x > 0 and size.y > 0:
		var cells: Array[Vector2i] = []
		for dy in range(size.y):
			for dx in range(size.x):
				cells.append(preview_anchor + offset + Vector2i(dx, dy))
		if is_instance_valid(_controller._map_canvas) and _controller._map_canvas.has_method("set_structure_preview"):
			var preview_info := {
				"piece_id": "marketing",
				"anchor": preview_anchor,
				"rotation": int(_controller._payload.get("rotation", 0)),
				"type": mt,
				# Hide the default green/red cell overlay; marketing preview should be a semi-transparent piece.
				"highlight_fill": Color(0, 0, 0, 0),
				"highlight_border": Color(0, 0, 0, 0),
				"highlight_border_width": 0.0,
			}
			_controller._map_canvas.call("set_structure_preview", cells, true, preview_info)

	if _controller._overlay_controller != null:
		if mt == "airplane":
			var axis := outside_axis
			if axis.is_empty():
				axis = _infer_airplane_axis_for_pos(preview_anchor)
			if axis.is_empty():
				_controller._overlay_controller.hide_marketing_range_overlay()
				return
			var fs := _get_selected_marketing_board_base_size()
			_controller._overlay_controller.preview_marketing_range(preview_anchor, 0, mt, {"axis": axis, "footprint_size": fs})
		else:
			_controller._overlay_controller.preview_marketing_range(preview_anchor, 0, mt)

func sync_highlights() -> void:
	if _controller == null:
		return
	if not is_instance_valid(_controller._map_canvas):
		return
	if _controller._mode != "marketing":
		return

	_controller._marketing_valid_anchors.clear()
	_controller._marketing_outside_to_anchor.clear()
	if _controller._map_canvas.has_method("clear_cell_highlights"):
		_controller._map_canvas.call("clear_cell_highlights")

	var mt := str(_controller._payload.get("marketing_type", ""))
	var employee_type := str(_controller._payload.get("employee_type", ""))
	var board_number := int(_controller._payload.get("board_number", 0))
	var rotation := int(_controller._payload.get("rotation", 0))
	if mt.is_empty() or employee_type.is_empty() or board_number <= 0:
		return
	# airplane rotation has no meaning (issue_tracker #40). For other types keep existing rotation behaviour.
	if mt == "airplane":
		rotation = 0
	elif not rotation in [0, 90, 180, 270]:
		rotation = 0
	if not MarketingTypeRegistryClass.is_loaded() or not MarketingTypeRegistryClass.has_type(mt):
		return
	if not EmployeeRegistryClass.is_loaded():
		return
	var emp_def_val = EmployeeRegistryClass.get_def(employee_type)
	if emp_def_val == null or not (emp_def_val is EmployeeDef):
		return
	var emp_def: EmployeeDef = emp_def_val

	if _controller._scene == null or _controller._scene.game_engine == null:
		return
	var state: GameState = _controller._scene.game_engine.get_state()
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
	var minp := CoordsClass.get_world_min(state)
	var maxp := CoordsClass.get_world_max(state)

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

	# Airplane marketing is placed outside the board and is not blocked by structures/roads/range.
	# Its available anchors are edge start-cells whose length(1/3/5) stripe stays within the board.
	# (issue_tracker #42)
	if mt == "airplane":
		_sync_airplane_marketing_highlights(state, base_size)
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
		_controller._call_marketing_panel_method("set_error", ["没有可放置格：你还没有餐厅（距离限制：%s %d）" % [rt, rv]])
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

	# 营销占地：预先构建占用集合（考虑 footprint + rotation），避免每个候选点重复遍历。
	# 外围营销放在棋盘外，不应阻塞其它“棋盘内营销”的放置（issue_tracker #42）。
	var occupied_cells := {}
	if state.map.has("marketing_placements") and (state.map["marketing_placements"] is Dictionary):
		var placements: Dictionary = state.map["marketing_placements"]
		for k in placements.keys():
			var p_val = placements[k]
			if not (p_val is Dictionary):
				continue
			var p: Dictionary = p_val
			var p_type := str(p.get("type", ""))
			if p_type == "airplane":
				continue
			var anchor_val = p.get("world_pos", null)
			if not (anchor_val is Vector2i):
				continue
			var anchor: Vector2i = anchor_val

			# footprint_size/rotation 为新增字段；缺失则按 1x1/rotation=0 兜底（兼容旧存档/测试）。
			var p_base_size := Vector2i.ONE
			var fs_val = p.get("footprint_size", null)
			if fs_val is Vector2i:
				p_base_size = Vector2i(fs_val)
			elif fs_val is Array:
				var arr: Array = fs_val
				if arr.size() == 2:
					p_base_size = Vector2i(int(arr[0]), int(arr[1]))
			if p_base_size.x <= 0 or p_base_size.y <= 0:
				p_base_size = Vector2i.ONE

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

	# 饮品进货点集合（用于“营销板件不可覆盖 drink_source”，issue_tracker #35）
	var drink_source_pos_set := {}
	var sources_val = state.map.get("drink_sources", null)
	if sources_val is Array:
		var sources: Array = sources_val
		for s_val in sources:
			if not (s_val is Dictionary):
				continue
			var s: Dictionary = s_val
			var wp_val = s.get("world_pos", null)
			if wp_val is Vector2i:
				drink_source_pos_set[Vector2i(wp_val)] = true

	var valid: Array[Vector2i] = []
	for y in range(grid_size.y):
		for x in range(grid_size.x):
			var anchor_pos := CoordsClass.index_to_world(state, Vector2i(x, y))

			# 占地 cells：top-left anchor + oriented size
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

					# 营销板件不可覆盖饮品进货点（drink_source）
					if not drink_source_pos_set.is_empty() and drink_source_pos_set.has(p2):
						footprint_ok = false
						break
					var ds = cell3.get("drink_source", null)
					if ds != null:
						if ds is Dictionary and (ds as Dictionary).is_empty():
							pass
						else:
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

			_controller._marketing_valid_anchors[anchor_pos] = true
			valid.append(anchor_pos)

	if _controller._map_canvas.has_method("set_cell_highlights"):
		_controller._map_canvas.call("set_cell_highlights", valid)

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
			_controller._call_marketing_panel_method("set_error", [msg])

func _sync_airplane_marketing_highlights(state: GameState, base_size: Vector2i) -> void:
	if not is_instance_valid(_controller._map_canvas):
		return
	if state == null:
		return

	# Airplane footprint: one dimension is outward thickness(=2), the other is edge length(=1/3/5).
	var thickness := 2
	var length := 0
	if base_size.x == 2 and base_size.y != 2:
		length = base_size.y
	elif base_size.y == 2 and base_size.x != 2:
		length = base_size.x
	else:
		thickness = mini(base_size.x, base_size.y)
		length = maxi(base_size.x, base_size.y)
	if length <= 0:
		return

	var minp := CoordsClass.get_world_min(state)
	var maxp := CoordsClass.get_world_max(state)

	# Existing outside segments on each side (to prevent overlap in outside area).
	# side -> Array[Vector2i(start,end)] where start/end are inclusive indexes along the varying axis.
	var occupied := {"N": [], "S": [], "W": [], "E": []}
	var placements_val = state.map.get("marketing_placements", null)
	if placements_val is Dictionary:
		var placements: Dictionary = placements_val
		for k in placements.keys():
			var pv = placements[k]
			if not (pv is Dictionary):
				continue
			var p: Dictionary = pv
			var t := str(p.get("type", ""))
			if t != "airplane":
				continue
			var wp_val = p.get("world_pos", null)
			if not (wp_val is Vector2i):
				continue
			var wp: Vector2i = wp_val

			var axis := str(p.get("axis", "")).strip_edges()
			if axis != "row" and axis != "col":
				# Fallback inference for older data.
				if wp.x == minp.x or wp.x == maxp.x:
					axis = "row"
				elif wp.y == minp.y or wp.y == maxp.y:
					axis = "col"
				else:
					continue

			var fs := Vector2i.ONE
			var fs_val = p.get("footprint_size", null)
			if fs_val is Vector2i:
				fs = Vector2i(fs_val)
			elif fs_val is Array:
				var arr: Array = fs_val
				if arr.size() == 2:
					fs = Vector2i(int(arr[0]), int(arr[1]))
			if fs.x <= 0 or fs.y <= 0:
				fs = Vector2i.ONE

			var thickness2 := 2
			var length2 := 0
			if fs.x == 2 and fs.y != 2:
				thickness2 = 2
				length2 = fs.y
			elif fs.y == 2 and fs.x != 2:
				thickness2 = 2
				length2 = fs.x
			else:
				thickness2 = mini(fs.x, fs.y)
				length2 = maxi(fs.x, fs.y)
			thickness2 = maxi(1, thickness2)
			if length2 <= 0:
				continue

			if axis == "row":
				var side := "W" if wp.x == minp.x else "E" if wp.x == maxp.x or wp.x == (maxp.x - (thickness2 - 1)) else ""
				if side.is_empty():
					continue
				occupied[side].append(Vector2i(wp.y, wp.y + length2 - 1))
			else:
				var side2 := "N" if wp.y == minp.y else "S" if wp.y == maxp.y or wp.y == (maxp.y - (thickness2 - 1)) else ""
				if side2.is_empty():
					continue
				occupied[side2].append(Vector2i(wp.x, wp.x + length2 - 1))

	var overlaps := func(segments: Array, start: int, end: int) -> bool:
		for seg_val in segments:
			if not (seg_val is Vector2i):
				continue
			var seg: Vector2i = seg_val
			if not (end < seg.x or start > seg.y):
				return true
		return false

	var valid: Array[Vector2i] = []

	# Top/Bottom edges: axis=col (flies vertically across the board), segment varies along X.
	var max_start_x := maxp.x - length + 1
	for x in range(minp.x, max_start_x + 1):
		var start_x := x
		var end_x := x + length - 1

		# Top
		if not overlaps.call(occupied["N"], start_x, end_x):
			var anchor_top := Vector2i(x, minp.y)
			var outside_top := anchor_top + Vector2i(0, -1)
			_controller._marketing_outside_to_anchor[outside_top] = {"anchor": anchor_top, "axis": "col", "attach": "top"}
			_controller._marketing_valid_anchors[outside_top] = true
			valid.append(outside_top)

		# Bottom
		if not overlaps.call(occupied["S"], start_x, end_x):
			var anchor_bottom := Vector2i(x, maxp.y)
			var outside_bottom := anchor_bottom + Vector2i(0, 1)
			_controller._marketing_outside_to_anchor[outside_bottom] = {"anchor": anchor_bottom, "axis": "col", "attach": "bottom"}
			_controller._marketing_valid_anchors[outside_bottom] = true
			valid.append(outside_bottom)

	# Left/Right edges: axis=row (flies horizontally across the board), segment varies along Y.
	var max_start_y := maxp.y - length + 1
	for y in range(minp.y, max_start_y + 1):
		var start_y := y
		var end_y := y + length - 1

		# Left
		if not overlaps.call(occupied["W"], start_y, end_y):
			var anchor_left := Vector2i(minp.x, y)
			var outside_left := anchor_left + Vector2i(-1, 0)
			_controller._marketing_outside_to_anchor[outside_left] = {"anchor": anchor_left, "axis": "row", "attach": "left"}
			_controller._marketing_valid_anchors[outside_left] = true
			valid.append(outside_left)

		# Right
		if not overlaps.call(occupied["E"], start_y, end_y):
			var anchor_right := Vector2i(maxp.x, y)
			var outside_right := anchor_right + Vector2i(1, 0)
			_controller._marketing_outside_to_anchor[outside_right] = {"anchor": anchor_right, "axis": "row", "attach": "right"}
			_controller._marketing_valid_anchors[outside_right] = true
			valid.append(outside_right)

	if _controller._map_canvas.has_method("set_cell_highlights"):
		_controller._map_canvas.call("set_cell_highlights", valid)

	if valid.is_empty():
		_controller._call_marketing_panel_method("set_error", ["没有可放置格：飞机必须贴边且不能与已有外围营销重叠"])

func _infer_airplane_axis_for_pos(world_pos: Vector2i) -> String:
	if _controller._scene == null or _controller._scene.game_engine == null:
		return ""
	var state: GameState = _controller._scene.game_engine.get_state()
	if state == null:
		return ""
	var base_size := _get_selected_marketing_board_base_size()
	if base_size.x <= 0 or base_size.y <= 0:
		return ""
	var thickness := 2
	var length := 0
	if base_size.x == 2 and base_size.y != 2:
		length = base_size.y
	elif base_size.y == 2 and base_size.x != 2:
		length = base_size.x
	else:
		thickness = mini(base_size.x, base_size.y)
		length = maxi(base_size.x, base_size.y)
	var horizontal := Vector2i(maxi(1, length), maxi(1, thickness))
	var vertical := Vector2i(maxi(1, thickness), maxi(1, length))
	var minp := CoordsClass.get_world_min(state)
	var maxp := CoordsClass.get_world_max(state)
	var on_x_edge := world_pos.x == minp.x or (world_pos.x + vertical.x - 1) == maxp.x
	var on_y_edge := world_pos.y == minp.y or (world_pos.y + horizontal.y - 1) == maxp.y
	if on_x_edge and not on_y_edge:
		return "row"
	if on_y_edge and not on_x_edge:
		return "col"
	return ""

func _get_selected_marketing_board_rotated_size() -> Vector2i:
	var board_number := int(_controller._payload.get("board_number", 0))
	var rotation := int(_controller._payload.get("rotation", 0))
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

func _get_selected_marketing_board_base_size() -> Vector2i:
	var board_number := int(_controller._payload.get("board_number", 0))
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
		return Vector2i.ONE
	return base_size
