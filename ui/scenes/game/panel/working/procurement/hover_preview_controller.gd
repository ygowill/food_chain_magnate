# Game scene：Working/Drinks Procurement hover preview 控制器
# 拆分自：`game_panel_working_drinks_procurement_controller.gd`
extends RefCounted

const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")
const StructuresClass = preload("res://core/map/map_runtime/structures.gd")
const RoadHelpersClass = preload("res://ui/scenes/game/panel/working/procurement/road_helpers.gd")

var _controller_ref: WeakRef = null

func setup(controller) -> void:
	_controller_ref = weakref(controller)

func _get_controller():
	if _controller_ref == null:
		return null
	return _controller_ref.get_ref()

func set_hover_start_restaurant_id(state: GameState, restaurant_id: String) -> void:
	var c = _get_controller()
	if c == null:
		return
	var next := str(restaurant_id).strip_edges()
	if str(c._procure_hover_start_restaurant_id) == next:
		return
	c._procure_hover_start_restaurant_id = next
	apply_hover_preview(state, true)

func set_hover_preview_text(text: String) -> void:
	var c = _get_controller()
	if c == null:
		return
	if not is_instance_valid(c.production_panel):
		return
	if c.production_panel.has_method("set_drinks_hover_preview_text"):
		c.production_panel.call("set_drinks_hover_preview_text", str(text))

func sync_hover_restaurant_anchor(state: GameState, restaurant_id: String) -> void:
	var c = _get_controller()
	if c == null:
		return
	var canvas = c._get_map_canvas()
	if canvas == null:
		return
	if state == null:
		return
	var rid := str(restaurant_id).strip_edges()
	if rid.is_empty():
		if canvas.has_method("clear_procure_drinks_hovered_restaurant_anchor"):
			canvas.call("clear_procure_drinks_hovered_restaurant_anchor")
		return

	var restaurants_val = state.map.get("restaurants", null)
	if not (restaurants_val is Dictionary):
		return
	var restaurants: Dictionary = restaurants_val
	if not restaurants.has(rid) or not (restaurants[rid] is Dictionary):
		return
	var rest: Dictionary = restaurants[rid]
	var ep = rest.get("entrance_pos", null)
	if not (ep is Vector2i):
		return
	var anchor: Vector2i = Vector2i(ep)
	if canvas.has_method("set_procure_drinks_hovered_restaurant_anchor"):
		canvas.call("set_procure_drinks_hovered_restaurant_anchor", anchor)

func clear_hover_preview_ui(state: GameState, restore_selected_overlay: bool) -> void:
	var c = _get_controller()
	if c == null:
		return
	set_hover_preview_text("")
	sync_hover_restaurant_anchor(state, "")
	if bool(c._procure_hover_preview_active) and restore_selected_overlay:
		c._procure_hover_preview_active = false
		c._recompute_procurement_plan(state)
	else:
		c._procure_hover_preview_active = false

func apply_hover_preview(state: GameState, restore_selected_overlay_when_clearing: bool) -> void:
	var c = _get_controller()
	if c == null:
		return
	if state == null:
		return
	sync_hover_restaurant_anchor(state, str(c._procure_hover_start_restaurant_id))

	var hover_id := str(c._procure_hover_start_restaurant_id).strip_edges()
	var selected_id := str(c._procure_selected_start_restaurant_id).strip_edges()
	if hover_id.is_empty():
		clear_hover_preview_ui(state, restore_selected_overlay_when_clearing)
		return
	if hover_id == selected_id:
		# Hover 到当前选中起点：不改变 overlay，只显示预览信息；若之前在预览其它餐厅，则先恢复选中路线。
		if bool(c._procure_hover_preview_active) and restore_selected_overlay_when_clearing:
			c._procure_hover_preview_active = false
			c._recompute_procurement_plan(state)
		else:
			c._procure_hover_preview_active = false
		set_hover_preview_text("预览：当前起点（点击餐厅或按 1-9 切换）")
		return

	# 仅对“道路采购”提供悬停预览：起点餐厅会改变自动路径。
	if c._is_air_procure_employee_type(str(c._procure_selected_employee_type)):
		set_hover_preview_text("提示：点击餐厅可选择起点")
		c._procure_hover_preview_active = false
		return
	if (c._procure_selected_sources is Array) and (c._procure_selected_sources as Array).is_empty():
		set_hover_preview_text("预览：请先选择至少 1 个进货点")
		c._procure_hover_preview_active = false
		return

	var emp_def: EmployeeDef = c._get_procure_employee_def(str(c._procure_selected_employee_type))
	if emp_def == null:
		var msg := "EmployeeRegistry 未初始化"
		if EmployeeRegistryClass.is_loaded():
			msg = "未知员工类型: %s" % str(c._procure_selected_employee_type)
		set_hover_preview_text("预览：%s" % msg)
		c._procure_hover_preview_active = false
		return

	var sources: Array[Vector2i] = []
	if c._procure_selected_sources is Array:
		for p in (c._procure_selected_sources as Array):
			if p is Vector2i:
				sources.append(Vector2i(p))

	var preview_r = RoadHelpersClass.build_road_procure_preview_plan(state, emp_def, str(c._procure_selected_employee_type), hover_id, sources)
	if not preview_r.ok:
		set_hover_preview_text("预览：%s" % preview_r.error)
		if bool(c._procure_hover_preview_active) and restore_selected_overlay_when_clearing:
			c._procure_hover_preview_active = false
			c._recompute_procurement_plan(state)
		else:
			c._procure_hover_preview_active = false
		return
	if not (preview_r.value is Dictionary):
		set_hover_preview_text("预览：路线解析失败")
		if bool(c._procure_hover_preview_active) and restore_selected_overlay_when_clearing:
			c._procure_hover_preview_active = false
			c._recompute_procurement_plan(state)
		else:
			c._procure_hover_preview_active = false
		return

	var plan: Dictionary = preview_r.value
	var entrance_pos := Vector2i(-1, -1)
	var ep_val = plan.get("entrance_pos", null)
	if ep_val is Vector2i:
		entrance_pos = Vector2i(ep_val)

	var route: Array[Vector2i] = []
	var route_val = plan.get("route", null)
	if route_val is Array:
		for p in (route_val as Array):
			if p is Vector2i:
				route.append(Vector2i(p))

	var picked_sources_pos: Array[Vector2i] = []
	var picked_val = plan.get("picked_sources", null)
	if picked_val is Array:
		for s_val in (picked_val as Array):
			if not (s_val is Dictionary):
				continue
			var s: Dictionary = s_val
			var wp = s.get("world_pos", null)
			if wp is Vector2i:
				picked_sources_pos.append(Vector2i(wp))

	var used := RoadHelpersClass.count_road_boundary_crossings(route)
	var max_dist := RoadHelpersClass.get_road_procure_max_distance(state, emp_def)
	var hover_idx := 0
	var restaurant_ids := StructuresClass.get_player_restaurants(state, state.get_current_player_id())
	restaurant_ids.sort()
	var find_idx := restaurant_ids.find(hover_id)
	if find_idx >= 0:
		hover_idx = find_idx + 1
	var start_label := ("餐厅 %d" % hover_idx) if hover_idx > 0 else hover_id
	if entrance_pos != Vector2i(-1, -1):
		start_label = "%s @ (%d,%d)" % [start_label, entrance_pos.x, entrance_pos.y]
	set_hover_preview_text("预览：%s，距离=%d/%d（点击餐厅或按 1-9 选择起点）" % [start_label, used, max_dist])

	if c._overlay_controller != null and c._overlay_controller.has_method("show_procurement_route_overlay"):
		var opts := {
			"preview": true,
			"start_restaurant_cells": c._get_restaurant_cells(state, hover_id),
		}
		c._overlay_controller.call("show_procurement_route_overlay", entrance_pos, route, picked_sources_pos, opts)
		c._procure_hover_preview_active = true
	else:
		c._procure_hover_preview_active = false
