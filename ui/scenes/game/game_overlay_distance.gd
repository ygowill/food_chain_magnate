# Game scene：距离覆盖层
extends RefCounted

const DistanceOverlayScene = preload("res://ui/overlays/distance_overlay.tscn")

var _scene = null
var _map_canvas = null

var distance_overlay = null

func _init(scene, map_canvas = null) -> void:
	_scene = scene
	_map_canvas = map_canvas

func show_distance_overlay(from_position: Vector2i, to_positions: Array[Vector2i]) -> void:
	if _scene == null:
		return
	_ensure_distance_overlay()
	if not is_instance_valid(distance_overlay):
		return

	var engine = _scene.game_engine
	if engine != null and distance_overlay.has_method("set_map_data"):
		var state = engine.get_state()
		distance_overlay.set_map_data(state.map)

	_sync_distance_overlay_transform()

	if distance_overlay.has_method("show_distances"):
		distance_overlay.show_distances(from_position, to_positions)

	distance_overlay.visible = true

func hide_distance_overlay() -> void:
	if is_instance_valid(distance_overlay):
		if distance_overlay.has_method("clear_all"):
			distance_overlay.clear_all()
		distance_overlay.visible = false

func _ensure_distance_overlay() -> void:
	if _scene == null:
		return

	if distance_overlay == null or not is_instance_valid(distance_overlay):
		distance_overlay = DistanceOverlayScene.instantiate()

	var parent: Node = _map_canvas if is_instance_valid(_map_canvas) else _scene
	if is_instance_valid(distance_overlay) and distance_overlay.get_parent() != parent:
		var old_parent = distance_overlay.get_parent()
		if old_parent != null:
			old_parent.remove_child(distance_overlay)
		parent.add_child(distance_overlay)

func _sync_distance_overlay_transform() -> void:
	if not is_instance_valid(distance_overlay):
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

	if distance_overlay.has_method("set_tile_size"):
		distance_overlay.call("set_tile_size", Vector2(float(cell_size), float(cell_size)))
	if distance_overlay.has_method("set_map_offset"):
		distance_overlay.call("set_map_offset", Vector2(float(-world_origin.x * cell_size), float(-world_origin.y * cell_size)))
