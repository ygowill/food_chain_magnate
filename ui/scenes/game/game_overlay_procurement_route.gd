# Game scene：采购路线覆盖层（GetDrinks）
extends RefCounted

const ProcurementRouteOverlayScene = preload("res://ui/overlays/procurement_route_overlay.tscn")

var _scene = null
var _map_canvas = null

var procurement_route_overlay = null

func _init(scene, map_canvas = null) -> void:
	_scene = scene
	_map_canvas = map_canvas

func show_procurement_route_overlay(entrance_pos: Vector2i, route: Array[Vector2i], picked_sources: Array[Vector2i] = []) -> void:
	if _scene == null:
		return
	if route.is_empty():
		hide_procurement_route_overlay()
		return

	_ensure_procurement_route_overlay()
	if not is_instance_valid(procurement_route_overlay):
		return

	_sync_procurement_route_overlay_transform()

	if procurement_route_overlay.has_method("show_plan"):
		procurement_route_overlay.call("show_plan", entrance_pos, route, picked_sources)

	procurement_route_overlay.visible = true

func hide_procurement_route_overlay() -> void:
	if is_instance_valid(procurement_route_overlay):
		if procurement_route_overlay.has_method("clear_all"):
			procurement_route_overlay.call("clear_all")
		procurement_route_overlay.visible = false

func _ensure_procurement_route_overlay() -> void:
	if _scene == null:
		return

	if procurement_route_overlay == null or not is_instance_valid(procurement_route_overlay):
		procurement_route_overlay = ProcurementRouteOverlayScene.instantiate()

	var parent: Node = _map_canvas if is_instance_valid(_map_canvas) else _scene
	if is_instance_valid(procurement_route_overlay) and procurement_route_overlay.get_parent() != parent:
		var old_parent = procurement_route_overlay.get_parent()
		if old_parent != null:
			old_parent.remove_child(procurement_route_overlay)
		parent.add_child(procurement_route_overlay)

func _sync_procurement_route_overlay_transform() -> void:
	if not is_instance_valid(procurement_route_overlay):
		return
	if not is_instance_valid(_map_canvas):
		return

	var cell_size := 40
	if _map_canvas.has_method("get_cell_size"):
		cell_size = int(_map_canvas.call("get_cell_size"))

	var world_origin := Vector2i.ZERO
	if _map_canvas.has_method("get_world_origin"):
		var wo = _map_canvas.call("get_world_origin")
		if wo is Vector2i:
			world_origin = wo

	if procurement_route_overlay.has_method("set_tile_size"):
		procurement_route_overlay.call("set_tile_size", Vector2(float(cell_size), float(cell_size)))
	if procurement_route_overlay.has_method("set_map_offset"):
		procurement_route_overlay.call("set_map_offset", Vector2(float(-world_origin.x * cell_size), float(-world_origin.y * cell_size)))

