# Game scene：营销范围覆盖层
extends RefCounted

const MarketingRangeOverlayScene = preload("res://ui/overlays/marketing_range_overlay.tscn")

var _scene = null
var _map_canvas = null

var marketing_range_overlay = null

func _init(scene, map_canvas) -> void:
	_scene = scene
	_map_canvas = map_canvas

func show_marketing_range_overlay(campaigns: Array[Dictionary]) -> void:
	_ensure_marketing_range_overlay()
	if not is_instance_valid(marketing_range_overlay):
		return

	if marketing_range_overlay.has_method("set_campaigns"):
		marketing_range_overlay.set_campaigns(campaigns)

	marketing_range_overlay.visible = true

func hide_marketing_range_overlay() -> void:
	if is_instance_valid(marketing_range_overlay):
		marketing_range_overlay.visible = false
		if marketing_range_overlay.has_method("clear_all"):
			marketing_range_overlay.clear_all()

func preview_marketing_range(position: Vector2i, range_val: int, marketing_type: String) -> void:
	if marketing_type.is_empty():
		hide_marketing_range_overlay()
		return

	_ensure_marketing_range_overlay()
	if not is_instance_valid(marketing_range_overlay):
		return

	if marketing_range_overlay.has_method("show_preview"):
		marketing_range_overlay.show_preview(position, range_val, marketing_type)

	marketing_range_overlay.visible = true

func _ensure_marketing_range_overlay() -> void:
	if _scene == null:
		return

	if marketing_range_overlay == null or not is_instance_valid(marketing_range_overlay):
		marketing_range_overlay = MarketingRangeOverlayScene.instantiate()

	var parent: Node = _map_canvas if is_instance_valid(_map_canvas) else _scene
	if is_instance_valid(marketing_range_overlay) and marketing_range_overlay.get_parent() != parent:
		var old_parent = marketing_range_overlay.get_parent()
		if old_parent != null:
			old_parent.remove_child(marketing_range_overlay)
		parent.add_child(marketing_range_overlay)

	_sync_marketing_range_overlay_transform()

func _sync_marketing_range_overlay_transform() -> void:
	if not is_instance_valid(marketing_range_overlay):
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

	if marketing_range_overlay.has_method("set_tile_size"):
		marketing_range_overlay.call("set_tile_size", Vector2(float(cell_size), float(cell_size)))
	if marketing_range_overlay.has_method("set_map_offset"):
		marketing_range_overlay.call("set_map_offset", Vector2(float(-world_origin.x * cell_size), float(-world_origin.y * cell_size)))

