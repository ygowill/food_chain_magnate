# Game scene：地图交互控制器 - Rural Marketeers offramp 放置模式
# 负责：高亮合法连接格、hover 预览棋盘外占用、点击选中与校验。
class_name GameMapInteractionRuralMarketeersOfframpMode
extends RefCounted

const CoordsClass = preload("res://core/map/map_runtime/coords.gd")
const MapUtilsClass = preload("res://core/map/map_utils.gd")

const MODE_ID := "rural_marketeers_offramp"
const _PREVIEW_OVERLAY_ID := "rural_marketeers_offramp_preview"
const _SELECTED_OVERLAY_ID := "rural_marketeers_offramp_selected"

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

func get_outside_margin_override() -> int:
	# Offramp occupies 2 cells outside the board.
	return 2

func on_cell_hovered(world_pos: Vector2i) -> void:
	if _controller == null:
		return
	if _controller._mode != MODE_ID:
		return

	if _valid_anchors.is_empty() or not _valid_anchors.has(world_pos):
		_clear_preview_overlay()
		return

	var info = _validate_anchor_and_get_info(world_pos)
	if info == null:
		_clear_preview_overlay()
		return
	_set_preview_overlay(info)

func on_cell_selected(world_pos: Vector2i) -> void:
	if _controller == null:
		return
	if _controller._mode != MODE_ID:
		return

	var overlay = _get_overlay()
	if _valid_anchors.is_empty() or not _valid_anchors.has(world_pos):
		if is_instance_valid(overlay) and overlay is CanvasItem and (overlay as CanvasItem).visible and overlay.has_method("set_validation"):
			overlay.call("set_validation", false, "请选择高亮的可放置边缘格")
		return

	var info = _validate_anchor_and_get_info(world_pos)
	if info == null:
		if is_instance_valid(overlay) and overlay is CanvasItem and (overlay as CanvasItem).visible and overlay.has_method("set_validation"):
			overlay.call("set_validation", false, "该位置不可放置 offramp")
		return

	if is_instance_valid(overlay) and overlay is CanvasItem and (overlay as CanvasItem).visible:
		if overlay.has_method("set_selected_target"):
			overlay.call("set_selected_target", Vector2i(info.connect_pos))
		if overlay.has_method("set_validation"):
			overlay.call("set_validation", true, "")
		_set_selected_overlay(info)
		if _controller.has_method("_maybe_auto_confirm_placement"):
			_controller._maybe_auto_confirm_placement(overlay)

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

	var executor = _controller._scene.game_engine.get_action_registry().get_executor("place_highway_offramp")
	if executor == null:
		_controller._map_canvas.call("set_cell_highlights", [])
		return

	var minp: Vector2i = CoordsClass.get_world_min(state)
	var maxp: Vector2i = CoordsClass.get_world_max(state)
	var cells: Array[Vector2i] = []
	var anchor_set := {}

	# Top & bottom edges
	for x in range(minp.x, maxp.x + 1):
		for y in [minp.y, maxp.y]:
			var pos := Vector2i(x, int(y))
			if _is_valid_anchor(state, executor, actor, pos):
				anchor_set[pos] = true
				cells.append(pos)

	# Left & right edges (excluding corners already handled)
	for y in range(minp.y + 1, maxp.y):
		for x in [minp.x, maxp.x]:
			var pos2 := Vector2i(int(x), y)
			if _is_valid_anchor(state, executor, actor, pos2):
				anchor_set[pos2] = true
				cells.append(pos2)

	_valid_anchors = anchor_set
	_controller._map_canvas.call("set_cell_highlights", cells)

func _is_valid_anchor(state: GameState, executor, actor: int, connect_pos: Vector2i) -> bool:
	var cmd := Command.create("place_highway_offramp", actor, {
		"position": [connect_pos.x, connect_pos.y],
	})
	cmd.phase = state.phase
	cmd.sub_phase = state.sub_phase
	var vr: Result = executor.validate(state, cmd)
	return vr.ok

func _validate_anchor_and_get_info(connect_pos: Vector2i):
	if _controller == null or not is_instance_valid(_controller):
		return null
	if _controller._scene == null or _controller._scene.game_engine == null:
		return null
	var state: GameState = _controller._scene.game_engine.get_state()
	if state == null:
		return null

	var actor := int(state.get_current_player_id())
	if NetContext != null and NetContext.mode == NetContext.Mode.ONLINE_CLIENT and int(NetContext.local_player_id) >= 0:
		actor = int(NetContext.local_player_id)

	var executor = _controller._scene.game_engine.get_action_registry().get_executor("place_highway_offramp")
	if executor == null:
		return null

	var cmd := Command.create("place_highway_offramp", actor, {
		"position": [connect_pos.x, connect_pos.y],
	})
	cmd.phase = state.phase
	cmd.sub_phase = state.sub_phase
	var vr: Result = executor.validate(state, cmd)
	if not vr.ok:
		return null
	if not (vr.value is Dictionary):
		return null
	var info: Dictionary = vr.value
	var side := str(info.get("side", "")).strip_edges()
	if side.is_empty():
		return null
	return {
		"connect_pos": Vector2i(connect_pos),
		"side": side,
		"occupied": _get_external_cells_for_side(connect_pos, side),
	}

func _get_external_cells_for_side(connect_pos: Vector2i, side: String) -> Array[Vector2i]:
	var s := str(side).strip_edges()
	var dir: Vector2i = MapUtilsClass.DIR_OFFSETS.get(s, Vector2i.ZERO)
	var out: Array[Vector2i] = []
	out.append(connect_pos + dir)
	out.append(connect_pos + dir * 2)
	return out

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

func _set_preview_overlay(info: Dictionary) -> void:
	if not is_instance_valid(_controller) or not is_instance_valid(_controller._map_canvas):
		return
	if not _controller._map_canvas.has_method("set_piece_overlay"):
		return
	var cells_val = info.get("occupied", null)
	if not (cells_val is Array):
		return
	var cells_any: Array = cells_val
	var cells: Array[Vector2i] = []
	for v in cells_any:
		if v is Vector2i:
			cells.append(v)
	if cells.is_empty():
		return
	_controller._map_canvas.call("set_piece_overlay", _PREVIEW_OVERLAY_ID, cells, {
		"fill": Color(0.2, 0.65, 1.0, 0.10),
		"border": Color(0.2, 0.65, 1.0, 0.85),
		"border_width": 3.0,
	})

func _set_selected_overlay(info: Dictionary) -> void:
	if not is_instance_valid(_controller) or not is_instance_valid(_controller._map_canvas):
		return
	if not _controller._map_canvas.has_method("set_piece_overlay"):
		return
	var cells_val = info.get("occupied", null)
	if not (cells_val is Array):
		return
	var cells_any: Array = cells_val
	var cells: Array[Vector2i] = []
	for v in cells_any:
		if v is Vector2i:
			cells.append(v)
	if cells.is_empty():
		return
	_controller._map_canvas.call("set_piece_overlay", _SELECTED_OVERLAY_ID, cells, {
		"fill": Color(0.2, 0.85, 0.35, 0.12),
		"border": Color(0.2, 0.85, 0.35, 0.92),
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
	var info = _validate_anchor_and_get_info(p)
	if info == null:
		return
	_set_selected_overlay(info)
