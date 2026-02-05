# Game scene：地图交互控制器 - Lobbyists 里程碑扩边模式逻辑下沉
# 负责：扩边高亮计算、hover 预览（含 ghost tile）、点击校验与选中预览。
class_name GameMapInteractionLobbyistsExtraTileMode
extends RefCounted

const MapUtilsClass = preload("res://core/map/map_utils.gd")
const LobbyistsTilePreviewClass = preload("res://ui/components/lobbyists_extra_tile/tile_preview.gd")

const _PREVIEW_OVERLAY_ID := "lobbyists_extra_tile_preview"
const _SELECTED_OVERLAY_ID := "lobbyists_extra_tile_selected_preview"

var _controller = null

var _valid_anchors: Dictionary = {} # Vector2i -> true
var _hover_tile_preview: Control = null
var _selected_tile_preview: Control = null
var _preview_tile_id: String = ""
var _preview_rotation: int = 0

func _init(controller) -> void:
	_controller = controller

func reset() -> void:
	_preview_tile_id = ""
	_preview_rotation = 0
	_valid_anchors.clear()
	_hide_tile_previews()
	_clear_overlays()

func get_outside_margin_override() -> int:
	# Allow showing the full 5×5 expansion tile outside current map bounds.
	return int(MapUtilsClass.TILE_SIZE)

func on_highlight_requested(tile_id: String, rotation: int) -> void:
	if _controller == null:
		return
	if _controller._mode != "lobbyists_extra_tile":
		return
	if not is_instance_valid(_controller._map_canvas):
		return
	if _controller._scene == null or _controller._scene.game_engine == null:
		return
	var state: GameState = _controller._scene.game_engine.get_state()
	if state == null:
		return

	var tid := str(tile_id).strip_edges()
	if tid.is_empty():
		reset()
		if _controller._map_canvas.has_method("clear_cell_highlights"):
			_controller._map_canvas.call("clear_cell_highlights")
		return

	var rot := _normalize_rotation(rotation)
	_preview_tile_id = tid
	_preview_rotation = rot
	if is_instance_valid(_hover_tile_preview) and (_hover_tile_preview as CanvasItem).visible:
		if _hover_tile_preview.has_method("set_tile"):
			_hover_tile_preview.call("set_tile", tid, rot)

	var actor := int(state.get_current_player_id())
	if NetContext != null and NetContext.mode == NetContext.Mode.ONLINE_CLIENT and int(NetContext.local_player_id) >= 0:
		actor = int(NetContext.local_player_id)

	var executor = _controller._scene.game_engine.get_action_registry().get_executor("place_lobbyists_extra_map_tile")
	if executor == null:
		_valid_anchors.clear()
		if _controller._map_canvas.has_method("clear_cell_highlights"):
			_controller._map_canvas.call("clear_cell_highlights")
		return

	var occupied := _get_occupied_tile_board_positions(state)

	var cells: Array[Vector2i] = []
	var anchor_set := {}
	for bp in occupied:
		var board_pos: Vector2i = bp
		for side in ["N", "E", "S", "W"]:
			var cmd := Command.create("place_lobbyists_extra_map_tile", actor, {
				"tile_id": tid,
				"attach_to_tile_board_pos": [board_pos.x, board_pos.y],
				"side": str(side),
				"rotation": rot,
			})
			cmd.phase = state.phase
			cmd.sub_phase = state.sub_phase
			var vr: Result = executor.validate(state, cmd)
			if not vr.ok:
				continue
			var edge_cells := _edge_cells_for_tile_side(board_pos, str(side))
			for c in edge_cells:
				if anchor_set.has(c):
					continue
				anchor_set[c] = true
				cells.append(c)

	_valid_anchors = anchor_set
	if _controller._map_canvas.has_method("set_cell_highlights"):
		_controller._map_canvas.call("set_cell_highlights", cells)
	_sync_selected_tile_preview_from_overlay()

func on_cell_hovered(world_pos: Vector2i) -> void:
	if _controller == null:
		return
	if _controller._mode != "lobbyists_extra_tile":
		return
	if not is_instance_valid(_controller._map_canvas):
		return
	if not _controller._map_canvas.has_method("is_cell_highlighted"):
		return

	if not bool(_controller._map_canvas.call("is_cell_highlighted", world_pos)):
		_clear_preview_overlay()
		_hide_hover_tile_preview()
		return

	var info: Dictionary = MapUtilsClass.world_to_tile(world_pos)
	var attach_board_pos: Vector2i = info.get("board_pos", Vector2i.ZERO)
	var local_pos: Vector2i = info.get("local_pos", Vector2i.ZERO)
	var side := _side_from_tile_local_pos(local_pos)
	if side.is_empty():
		_clear_preview_overlay()
		_hide_hover_tile_preview()
		return

	var offset: Vector2i = MapUtilsClass.DIR_OFFSETS.get(side, Vector2i.ZERO)
	var new_board_pos: Vector2i = attach_board_pos + offset

	_set_preview_overlay_for_new_board_pos(new_board_pos)
	_show_hover_tile_preview(new_board_pos)

func on_cell_selected(world_pos: Vector2i) -> void:
	if _controller == null:
		return
	if _controller._mode != "lobbyists_extra_tile":
		return

	# 仅允许点击“高亮的合法边缘格”
	if _valid_anchors.is_empty() or not _valid_anchors.has(world_pos):
		if is_instance_valid(_controller.lobbyists_extra_tile_overlay) and _controller.lobbyists_extra_tile_overlay.visible and _controller.lobbyists_extra_tile_overlay.has_method("set_validation"):
			_controller.lobbyists_extra_tile_overlay.set_validation(false, "请选择高亮的可放置边缘格")
		return

	if _controller._scene == null or _controller._scene.game_engine == null:
		return
	var state2: GameState = _controller._scene.game_engine.get_state()
	if state2 == null:
		return

	var tile_info: Dictionary = MapUtilsClass.world_to_tile(world_pos)
	var attach_board_pos: Vector2i = tile_info.get("board_pos", Vector2i.ZERO)
	var local_pos: Vector2i = tile_info.get("local_pos", Vector2i.ZERO)
	var side := _side_from_tile_local_pos(local_pos)
	if side.is_empty():
		if is_instance_valid(_controller.lobbyists_extra_tile_overlay) and _controller.lobbyists_extra_tile_overlay.visible and _controller.lobbyists_extra_tile_overlay.has_method("set_validation"):
			_controller.lobbyists_extra_tile_overlay.set_validation(false, "请点击板块边缘格（非角落）")
		return

	var tile_id := ""
	var rotation := 0
	if is_instance_valid(_controller.lobbyists_extra_tile_overlay):
		if _controller.lobbyists_extra_tile_overlay.has_method("get_selected_tile_id"):
			tile_id = str(_controller.lobbyists_extra_tile_overlay.get_selected_tile_id()).strip_edges()
		if _controller.lobbyists_extra_tile_overlay.has_method("get_selected_rotation"):
			rotation = int(_controller.lobbyists_extra_tile_overlay.get_selected_rotation())
	if tile_id.is_empty():
		if is_instance_valid(_controller.lobbyists_extra_tile_overlay) and _controller.lobbyists_extra_tile_overlay.visible and _controller.lobbyists_extra_tile_overlay.has_method("set_validation"):
			_controller.lobbyists_extra_tile_overlay.set_validation(false, "tile 未选择")
		return

	var actor := int(state2.get_current_player_id())
	if NetContext != null and NetContext.mode == NetContext.Mode.ONLINE_CLIENT and int(NetContext.local_player_id) >= 0:
		actor = int(NetContext.local_player_id)

	var cmd := Command.create("place_lobbyists_extra_map_tile", actor, {
		"tile_id": tile_id,
		"attach_to_tile_board_pos": [attach_board_pos.x, attach_board_pos.y],
		"side": side,
		"rotation": rotation,
	})
	cmd.phase = state2.phase
	cmd.sub_phase = state2.sub_phase

	var executor = _controller._scene.game_engine.get_action_registry().get_executor("place_lobbyists_extra_map_tile")
	if executor != null:
		var vr: Result = executor.validate(state2, cmd)
		if not vr.ok:
			if is_instance_valid(_controller.lobbyists_extra_tile_overlay) and _controller.lobbyists_extra_tile_overlay.visible and _controller.lobbyists_extra_tile_overlay.has_method("set_validation"):
				_controller.lobbyists_extra_tile_overlay.set_validation(false, vr.error)
			return

	if is_instance_valid(_controller.lobbyists_extra_tile_overlay) and _controller.lobbyists_extra_tile_overlay.visible:
		if _controller.lobbyists_extra_tile_overlay.has_method("set_selected_target"):
			_controller.lobbyists_extra_tile_overlay.set_selected_target(attach_board_pos, side)
		if _controller.lobbyists_extra_tile_overlay.has_method("set_validation"):
			_controller.lobbyists_extra_tile_overlay.set_validation(true, "")
		_set_selected_overlay(attach_board_pos, side)
		if _controller.has_method("_maybe_auto_confirm_placement"):
			_controller._maybe_auto_confirm_placement(_controller.lobbyists_extra_tile_overlay)

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

func _set_preview_overlay_for_new_board_pos(new_board_pos: Vector2i) -> void:
	if not is_instance_valid(_controller) or not is_instance_valid(_controller._map_canvas):
		return
	if not _controller._map_canvas.has_method("set_piece_overlay"):
		return

	var region: Array[Vector2i] = []
	var tile_size := int(MapUtilsClass.TILE_SIZE)
	var origin: Vector2i = new_board_pos * tile_size
	for dy in range(tile_size):
		for dx in range(tile_size):
			region.append(origin + Vector2i(dx, dy))

	_controller._map_canvas.call("set_piece_overlay", _PREVIEW_OVERLAY_ID, region, {
		"fill": Color(0.2, 0.65, 1.0, 0.12),
		"border": Color(0.2, 0.65, 1.0, 0.9),
		"border_width": 3.0,
	})

func _set_selected_overlay(attach_board_pos: Vector2i, side: String) -> void:
	if not is_instance_valid(_controller) or not is_instance_valid(_controller._map_canvas):
		return
	if not _controller._map_canvas.has_method("set_piece_overlay"):
		return

	var s := str(side).strip_edges()
	if s.is_empty():
		return

	var offset: Vector2i = MapUtilsClass.DIR_OFFSETS.get(s, Vector2i.ZERO)
	var new_board_pos: Vector2i = attach_board_pos + offset

	var region: Array[Vector2i] = []
	var tile_size := int(MapUtilsClass.TILE_SIZE)
	var origin: Vector2i = new_board_pos * tile_size
	for dy in range(tile_size):
		for dx in range(tile_size):
			region.append(origin + Vector2i(dx, dy))

	_controller._map_canvas.call("set_piece_overlay", _SELECTED_OVERLAY_ID, region, {
		"fill": Color(0.2, 0.65, 1.0, 0.16),
		"border": Color(0.2, 0.65, 1.0, 0.95),
		"border_width": 3.0,
	})
	_show_selected_tile_preview(new_board_pos)

func _ensure_tile_previews() -> void:
	if not is_instance_valid(_controller) or not is_instance_valid(_controller._map_canvas):
		return

	if not is_instance_valid(_hover_tile_preview):
		var p: Control = LobbyistsTilePreviewClass.new()
		p.name = "LobbyistsExtraTileHoverTilePreview"
		p.set_anchors_preset(Control.PRESET_TOP_LEFT)
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p.visible = false
		p.modulate = Color(1, 1, 1, 0.55)
		p.z_index = 10
		_controller._map_canvas.add_child(p)
		_hover_tile_preview = p

	if not is_instance_valid(_selected_tile_preview):
		var p2: Control = LobbyistsTilePreviewClass.new()
		p2.name = "LobbyistsExtraTileSelectedTilePreview"
		p2.set_anchors_preset(Control.PRESET_TOP_LEFT)
		p2.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p2.visible = false
		p2.modulate = Color(1, 1, 1, 0.75)
		p2.z_index = 11
		_controller._map_canvas.add_child(p2)
		_selected_tile_preview = p2

func _show_hover_tile_preview(new_board_pos: Vector2i) -> void:
	if _preview_tile_id.is_empty():
		_hide_hover_tile_preview()
		return
	_ensure_tile_previews()
	_show_tile_preview_node(_hover_tile_preview, new_board_pos, _preview_tile_id, _preview_rotation)

func _show_selected_tile_preview(new_board_pos: Vector2i) -> void:
	if _preview_tile_id.is_empty():
		_hide_selected_tile_preview()
		return
	_ensure_tile_previews()
	_show_tile_preview_node(_selected_tile_preview, new_board_pos, _preview_tile_id, _preview_rotation)

func _show_tile_preview_node(preview: Control, new_board_pos: Vector2i, tile_id: String, rotation: int) -> void:
	if not is_instance_valid(_controller) or not is_instance_valid(_controller._map_canvas):
		return
	if not is_instance_valid(preview):
		return

	var tid := str(tile_id).strip_edges()
	if tid.is_empty():
		preview.visible = false
		return

	var cell_size := 1
	if _controller._map_canvas.has_method("get_cell_size"):
		cell_size = int(_controller._map_canvas.call("get_cell_size"))
	cell_size = maxi(1, cell_size)

	var world_origin := Vector2i.ZERO
	if _controller._map_canvas.has_method("get_world_origin"):
		var wo_val = _controller._map_canvas.call("get_world_origin")
		if wo_val is Vector2i:
			world_origin = wo_val

	var tile_size := int(MapUtilsClass.TILE_SIZE)
	var world_min := new_board_pos * tile_size
	var view_min := world_min - world_origin

	var px_pos := Vector2(float(view_min.x * cell_size), float(view_min.y * cell_size))
	var px_size := Vector2(float(tile_size * cell_size), float(tile_size * cell_size))

	preview.position = px_pos
	preview.size = px_size
	preview.custom_minimum_size = px_size
	preview.visible = true

	if preview.has_method("set_tile"):
		preview.call("set_tile", tid, _normalize_rotation(rotation))

func _hide_hover_tile_preview() -> void:
	if is_instance_valid(_hover_tile_preview):
		_hover_tile_preview.visible = false

func _hide_selected_tile_preview() -> void:
	if is_instance_valid(_selected_tile_preview):
		_selected_tile_preview.visible = false

func _hide_tile_previews() -> void:
	_hide_hover_tile_preview()
	_hide_selected_tile_preview()

func _sync_selected_tile_preview_from_overlay() -> void:
	if not is_instance_valid(_controller) or not is_instance_valid(_controller.lobbyists_extra_tile_overlay):
		_hide_selected_tile_preview()
		return
	if not _controller.lobbyists_extra_tile_overlay.has_method("get_selected_side"):
		_hide_selected_tile_preview()
		return

	var side := str(_controller.lobbyists_extra_tile_overlay.call("get_selected_side")).strip_edges()
	if side.is_empty():
		_hide_selected_tile_preview()
		return

	var attach_board_pos := Vector2i.ZERO
	if _controller.lobbyists_extra_tile_overlay.has_method("get_selected_attach_board_pos"):
		var bp_val = _controller.lobbyists_extra_tile_overlay.call("get_selected_attach_board_pos")
		if bp_val is Vector2i:
			attach_board_pos = bp_val

	var offset: Vector2i = MapUtilsClass.DIR_OFFSETS.get(side, Vector2i.ZERO)
	var new_board_pos: Vector2i = attach_board_pos + offset
	_show_selected_tile_preview(new_board_pos)

func _get_occupied_tile_board_positions(state: GameState) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if state == null or not (state.map is Dictionary):
		return result

	var placements: Array = []
	if state.map.has("tile_placements") and (state.map["tile_placements"] is Array):
		placements.append_array(state.map["tile_placements"])
	if state.map.has("external_tile_placements") and (state.map["external_tile_placements"] is Array):
		placements.append_array(state.map["external_tile_placements"])

	var seen := {}
	for pv in placements:
		if not (pv is Dictionary):
			continue
		var p: Dictionary = pv
		var bp_val = p.get("board_pos", null)
		if not (bp_val is Vector2i):
			continue
		var bp: Vector2i = bp_val
		if seen.has(bp):
			continue
		seen[bp] = true
		result.append(bp)

	return result

func _edge_cells_for_tile_side(board_pos: Vector2i, side: String) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var tile_size := int(MapUtilsClass.TILE_SIZE)
	var max_idx := tile_size - 1
	var origin: Vector2i = board_pos * tile_size

	match str(side):
		"N":
			for lx in range(1, max_idx):
				cells.append(origin + Vector2i(lx, 0))
		"S":
			for lx in range(1, max_idx):
				cells.append(origin + Vector2i(lx, max_idx))
		"W":
			for ly in range(1, max_idx):
				cells.append(origin + Vector2i(0, ly))
		"E":
			for ly in range(1, max_idx):
				cells.append(origin + Vector2i(max_idx, ly))

	return cells

func _side_from_tile_local_pos(local_pos: Vector2i) -> String:
	var tile_size := int(MapUtilsClass.TILE_SIZE)
	var max_idx := tile_size - 1
	var on_n := local_pos.y == 0
	var on_s := local_pos.y == max_idx
	var on_w := local_pos.x == 0
	var on_e := local_pos.x == max_idx
	var count := int(on_n) + int(on_s) + int(on_w) + int(on_e)
	if count != 1:
		return ""
	if on_n:
		return "N"
	if on_s:
		return "S"
	if on_w:
		return "W"
	return "E"

func _normalize_rotation(rotation: int) -> int:
	var r := int(rotation) % 360
	if r < 0:
		r += 360
	if r != 0 and r != 90 and r != 180 and r != 270:
		r = 0
	return r

