# Game scene：地图交互控制器 - Coffee shop 放置/移动模式
# 负责：高亮合法格、hover/selected 预览、点击选中与校验。
class_name GameMapInteractionCoffeeShopMode
extends RefCounted

const CoordsClass = preload("res://core/map/map_runtime/coords.gd")

const MODE_ID := "coffee_shop_placement"
const _PREVIEW_OVERLAY_ID := "coffee_shop_preview"
const _SELECTED_OVERLAY_ID := "coffee_shop_selected"

var _controller = null
var _valid_anchors: Dictionary = {} # Vector2i -> true

func _init(controller) -> void:
	_controller = controller

func _get_overlay():
	if _controller == null or not is_instance_valid(_controller):
		return null
	if _controller.has_method("get_custom_mode_overlay"):
		return _controller.get_custom_mode_overlay(MODE_ID)
	return null

func reset() -> void:
	_valid_anchors.clear()
	_clear_overlays()
	if _controller == null:
		return
	if _controller._mode != MODE_ID:
		return
	_recompute_valid_anchors()
	_sync_selected_overlay_from_overlay()

func on_cell_hovered(world_pos: Vector2i) -> void:
	if _controller == null:
		return
	if _controller._mode != MODE_ID:
		return
	if _valid_anchors.is_empty() or not _valid_anchors.has(world_pos):
		_clear_preview_overlay()
		return
	_set_preview_overlay(world_pos)

func on_cell_selected(world_pos: Vector2i) -> void:
	if _controller == null:
		return
	if _controller._mode != MODE_ID:
		return

	var overlay = _get_overlay()
	if _valid_anchors.is_empty() or not _valid_anchors.has(world_pos):
		if is_instance_valid(overlay) and overlay is CanvasItem and (overlay as CanvasItem).visible and overlay.has_method("set_validation"):
			overlay.call("set_validation", false, "请选择高亮的可放置格")
		return

	if is_instance_valid(overlay) and overlay is CanvasItem and (overlay as CanvasItem).visible:
		if overlay.has_method("set_selected_position"):
			overlay.call("set_selected_position", world_pos)
		if overlay.has_method("set_validation"):
			overlay.call("set_validation", true, "")
		_set_selected_overlay(world_pos)
		if _controller.has_method("_maybe_auto_confirm_placement"):
			_controller._maybe_auto_confirm_placement(overlay)

func _get_action_id_for_mode() -> String:
	if _controller == null or not is_instance_valid(_controller):
		return ""
	var aid := str(_controller._payload.get("action_id", "")).strip_edges()
	if not aid.is_empty():
		return aid
	var overlay = _get_overlay()
	if is_instance_valid(overlay) and overlay.has_method("get_action_id"):
		return str(overlay.call("get_action_id")).strip_edges()
	return ""

func _recompute_valid_anchors() -> void:
	if _controller == null or not is_instance_valid(_controller):
		return
	if not is_instance_valid(_controller._map_canvas) or not _controller._map_canvas.has_method("set_cell_highlights"):
		return
	if _controller._scene == null or _controller._scene.game_engine == null:
		return

	var state: GameState = _controller._scene.game_engine.get_state()
	if state == null:
		return

	var actor := int(state.get_current_player_id())
	if NetContext != null and NetContext.mode == NetContext.Mode.ONLINE_CLIENT and int(NetContext.local_player_id) >= 0:
		actor = int(NetContext.local_player_id)

	var action_id := _get_action_id_for_mode()
	if action_id.is_empty():
		_controller._map_canvas.call("set_cell_highlights", [])
		return

	var executor = _controller._scene.game_engine.get_action_registry().get_executor(action_id)
	if executor == null:
		_controller._map_canvas.call("set_cell_highlights", [])
		return

	var overlay = _get_overlay()
	var mode := ""
	var from_shop_id := ""
	if is_instance_valid(overlay):
		if overlay.has_method("get_mode"):
			mode = str(overlay.call("get_mode")).strip_edges()
		if overlay.has_method("get_selected_from_shop_id"):
			from_shop_id = str(overlay.call("get_selected_from_shop_id")).strip_edges()

	if mode != "place" and mode != "move":
		_controller._map_canvas.call("set_cell_highlights", [])
		return
	if mode == "move" and from_shop_id.is_empty():
		_controller._map_canvas.call("set_cell_highlights", [])
		return

	if not (state.map is Dictionary):
		_controller._map_canvas.call("set_cell_highlights", [])
		return
	if not state.map.has("grid_size") or not (state.map["grid_size"] is Vector2i):
		_controller._map_canvas.call("set_cell_highlights", [])
		return
	var grid_size: Vector2i = state.map["grid_size"]
	var map_origin: Vector2i = CoordsClass.get_map_origin(state)

	var cells: Array[Vector2i] = []
	var anchor_set := {}
	for y in range(grid_size.y):
		for x in range(grid_size.x):
			var world_anchor: Vector2i = Vector2i(x, y) - map_origin
			var params := {
				"mode": mode,
				"position": [world_anchor.x, world_anchor.y],
			}
			if mode == "move":
				params["from_shop_id"] = from_shop_id
			var cmd := Command.create(action_id, actor, params)
			cmd.phase = state.phase
			cmd.sub_phase = state.sub_phase
			var vr: Result = executor.validate(state, cmd)
			if not vr.ok:
				continue
			if anchor_set.has(world_anchor):
				continue
			anchor_set[world_anchor] = true
			cells.append(world_anchor)

	_valid_anchors = anchor_set
	_controller._map_canvas.call("set_cell_highlights", cells)

func _clear_overlays() -> void:
	if not is_instance_valid(_controller) or not is_instance_valid(_controller._map_canvas):
		return
	if _controller._map_canvas.has_method("clear_piece_overlay"):
		_controller._map_canvas.call("clear_piece_overlay", _PREVIEW_OVERLAY_ID)
		_controller._map_canvas.call("clear_piece_overlay", _SELECTED_OVERLAY_ID)

func _clear_preview_overlay() -> void:
	if not is_instance_valid(_controller) or not is_instance_valid(_controller._map_canvas):
		return
	if _controller._map_canvas.has_method("clear_piece_overlay"):
		_controller._map_canvas.call("clear_piece_overlay", _PREVIEW_OVERLAY_ID)

func _set_preview_overlay(world_anchor: Vector2i) -> void:
	if not is_instance_valid(_controller) or not is_instance_valid(_controller._map_canvas):
		return
	if not _controller._map_canvas.has_method("set_piece_overlay"):
		return
	var cells: Array[Vector2i] = []
	cells.append(world_anchor)
	_controller._map_canvas.call("set_piece_overlay", _PREVIEW_OVERLAY_ID, cells, {
		"fill": Color(0.2, 0.65, 1.0, 0.08),
		"border": Color(0.2, 0.65, 1.0, 0.80),
		"border_width": 3.0,
	})

func _set_selected_overlay(world_anchor: Vector2i) -> void:
	if not is_instance_valid(_controller) or not is_instance_valid(_controller._map_canvas):
		return
	if not _controller._map_canvas.has_method("set_piece_overlay"):
		return
	var cells: Array[Vector2i] = []
	cells.append(world_anchor)
	_controller._map_canvas.call("set_piece_overlay", _SELECTED_OVERLAY_ID, cells, {
		"fill": Color(0.2, 0.85, 0.35, 0.10),
		"border": Color(0.2, 0.85, 0.35, 0.90),
		"border_width": 3.0,
	})

func _sync_selected_overlay_from_overlay() -> void:
	var overlay = _get_overlay()
	if overlay == null or not is_instance_valid(overlay):
		return
	if not overlay.has_method("get_selected_position"):
		return
	var p_val = overlay.call("get_selected_position")
	if not (p_val is Vector2i):
		return
	var p: Vector2i = p_val
	if p == Vector2i(-1, -1):
		return
	if not _valid_anchors.has(p):
		return
	_set_selected_overlay(p)

