# MapCanvasDrawer：道路绘制下沉
extends RefCounted

const TextureUtilsClass = preload("res://ui/scenes/game/map_canvas_drawer_texture_utils.gd")
const PieceUiHintsRegistryClass = preload("res://core/rules/piece_ui_hints_registry.gd")
const PENDING_ROADS_KEY_SUFFIX := "pending_roads"
const ROADWORK_MARKERS_KEY_SUFFIX := "roadworks_markers"
const ROADWORK_MARKER_PIECE_SUFFIX := "roadworks_marker"

static func draw_roads(canvas, cell_size: int) -> void:
	var pending_extra_dirs := build_pending_road_connection_dirs(canvas)
	for y in range(canvas._grid_size.y):
		for x in range(canvas._grid_size.x):
			var world_pos = canvas._world_origin + Vector2i(x, y)
			var cell: Dictionary = canvas._get_cell_world(world_pos)
			var structure_val = cell.get("structure", null)
			if structure_val is Dictionary:
				var structure: Dictionary = structure_val
				var pid := str(structure.get("piece_id", "")).strip_edges()
				if not pid.is_empty():
					var hints := PieceUiHintsRegistryClass.get_hints(pid)
					if bool(hints.get("blocks_roads_under", false)):
						continue
			var segments_val = cell.get("road_segments", null)
			if not (segments_val is Array):
				continue
			var segments: Array = segments_val
			if segments.is_empty():
				continue

			# Bridge crossing tiles may store multiple independent segments in one cell.
			# For visuals, if a bridge segment exists, only render bridge=True segments to avoid overlapping artifacts.
			var has_bridge := false
			for s_val in segments:
				if s_val is Dictionary and bool(Dictionary(s_val).get("bridge", false)):
					has_bridge = true
					break
			var segments_to_draw: Array = segments
			if has_bridge:
				segments_to_draw = []
				for s_val in segments:
					if s_val is Dictionary and bool(Dictionary(s_val).get("bridge", false)):
						segments_to_draw.append(s_val)

			var rect := Rect2(Vector2(x * cell_size, y * cell_size), Vector2(cell_size, cell_size))
			var center := rect.position + rect.size * 0.5

			for seg_index in range(segments_to_draw.size()):
				var seg_val = segments_to_draw[seg_index]
				if not (seg_val is Dictionary):
					continue
				var seg: Dictionary = seg_val
				var dirs_val = seg.get("dirs", null)
				if not (dirs_val is Array):
					continue
				var dirs: Array = dirs_val
				var extra_val = pending_extra_dirs.get(world_pos, null)
				if extra_val is Dictionary and not (extra_val as Dictionary).is_empty():
					var eff: Array = []
					var seen := {}
					for d in dirs:
						var s := str(d).strip_edges()
						if s.is_empty():
							continue
						if seen.has(s):
							continue
						seen[s] = true
						eff.append(s)
					for d2 in (extra_val as Dictionary).keys():
						var s2 := str(d2).strip_edges()
						if s2.is_empty():
							continue
						if seen.has(s2):
							continue
						seen[s2] = true
						eff.append(s2)
					dirs = eff
				if dirs.is_empty():
					continue
				var is_bridge := bool(seg.get("bridge", false))

				var shape_info := compute_road_shape_info(dirs)
				if shape_info.is_empty():
					continue
				var shape: String = str(shape_info.get("shape", "default"))
				var rot_deg: int = int(shape_info.get("rotation_deg", 0))

				var key := "road_bridge" if is_bridge else shape
				var tex: Texture2D = canvas._skin.get_road_texture(key)

				var margin := 0.0 if seg_index == 0 else 1.0
				var size := rect.size - Vector2(margin * 2.0, margin * 2.0)
				var offset := Vector2.ZERO
				if seg_index > 0:
					offset = Vector2(0.8, 0.8) * float(seg_index)

				canvas.draw_set_transform(center + offset, deg_to_rad(float(rot_deg)), Vector2.ONE)
				canvas.draw_texture_rect(tex, Rect2(-size * 0.5, size), false)
				canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

static func build_pending_road_connection_dirs(canvas) -> Dictionary:
	if canvas == null:
		return {}
	if not (canvas._map_data is Dictionary):
		return {}
	var map_data: Dictionary = canvas._map_data
	var pending: Array = _get_pending_roads_list(map_data)
	if pending.is_empty():
		return {}

	var out := {} # Vector2i -> {dir -> true}

	for e_val in pending:
		if not (e_val is Dictionary):
			continue
		var e: Dictionary = e_val
		var sbp_val = e.get("segments_by_pos", null)
		if not (sbp_val is Dictionary):
			continue
		var segments_by_pos: Dictionary = sbp_val
		for k in segments_by_pos.keys():
			if not (k is String):
				continue
			var parts := str(k).split(",")
			if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
				continue
			var world_pos := Vector2i(int(parts[0]), int(parts[1]))
			var seg_list_val = segments_by_pos.get(k, null)
			if not (seg_list_val is Array):
				continue
			for seg_val in Array(seg_list_val):
				if not (seg_val is Dictionary):
					continue
				var seg: Dictionary = seg_val
				var dirs_val = seg.get("dirs", null)
				if not (dirs_val is Array):
					continue
				for d_val in Array(dirs_val):
					var d := str(d_val).strip_edges()
					if d.is_empty() or not MapUtils.DIR_OFFSETS.has(d):
						continue
					if not out.has(world_pos):
						out[world_pos] = {}
					var m: Dictionary = out[world_pos]
					m[d] = true
					out[world_pos] = m

	return out

static func _get_pending_roads_list(map_data: Dictionary) -> Array:
	if map_data.is_empty():
		return []

	var keys: Array[String] = []
	for k in map_data.keys():
		if not (k is String):
			continue
		var key: String = str(k).strip_edges()
		if key.ends_with(PENDING_ROADS_KEY_SUFFIX):
			keys.append(key)
	keys.sort()

	var out: Array = []
	for key2 in keys:
		var val = map_data.get(key2, null)
		if val is Array:
			out.append_array(Array(val))
	return out

static func compute_road_shape_info(dirs: Array) -> Dictionary:
	if dirs.is_empty():
		return {"shape": "default", "rotation_deg": 0}

	var set := {}
	var unique: Array[String] = []
	for d in dirs:
		var s := str(d).strip_edges()
		if s.is_empty():
			continue
		if set.has(s):
			continue
		set[s] = true
		unique.append(s)

	var n := unique.size()
	if n <= 0:
		return {"shape": "default", "rotation_deg": 0}
	if n == 1:
		var d0 := unique[0]
		match d0:
			"N":
				return {"shape": "end", "rotation_deg": 180}
			"S":
				return {"shape": "end", "rotation_deg": 0}
			"E":
				return {"shape": "end", "rotation_deg": 270}
			"W":
				return {"shape": "end", "rotation_deg": 90}
			_:
				return {"shape": "end", "rotation_deg": 0}

	if n == 2:
		var a := unique[0]
		var b := unique[1]
		var opp := (a == "N" and b == "S") or (a == "S" and b == "N") or (a == "E" and b == "W") or (a == "W" and b == "E")
		if opp:
			if (a == "N" and b == "S") or (a == "S" and b == "N"):
				return {"shape": "straight", "rotation_deg": 0}
			return {"shape": "straight", "rotation_deg": 90}

		# Corner
		if set.has("N") and set.has("E"):
			return {"shape": "corner", "rotation_deg": 180}
		if set.has("E") and set.has("S"):
			return {"shape": "corner", "rotation_deg": 270}
		if set.has("S") and set.has("W"):
			return {"shape": "corner", "rotation_deg": 0}
		if set.has("W") and set.has("N"):
			return {"shape": "corner", "rotation_deg": 90}
		return {"shape": "corner", "rotation_deg": 0}

	if n == 3:
		if not set.has("E"):
			return {"shape": "tee", "rotation_deg": 0}
		if not set.has("S"):
			return {"shape": "tee", "rotation_deg": 90}
		if not set.has("W"):
			return {"shape": "tee", "rotation_deg": 180}
		if not set.has("N"):
			return {"shape": "tee", "rotation_deg": 270}
		return {"shape": "tee", "rotation_deg": 0}

	# n >= 4
	return {"shape": "cross", "rotation_deg": 0}

static func draw_roadworks_markers(canvas, cell_size: int) -> void:
	if canvas == null or canvas._skin == null:
		return
	if not (canvas._map_data is Dictionary):
		return
	var markers: Dictionary = _get_roadworks_markers_dict(canvas._map_data)
	if markers.is_empty():
		return

	var tex: Texture2D = get_roadworks_marker_texture(canvas._skin)
	if tex == null:
		return
	var pad := maxf(2.0, float(cell_size) * 0.08)
	var mod := Color(1, 1, 1, 0.95)

	for k in markers.keys():
		if not (k is String):
			continue
		var parts := str(k).split(",")
		if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
			continue
		var world_pos := Vector2i(int(parts[0]), int(parts[1]))
		if not canvas._is_valid_world_pos(world_pos):
			continue
		var vpos: Vector2i = canvas._world_to_view(world_pos)
		var rect := Rect2(Vector2(vpos.x * cell_size, vpos.y * cell_size), Vector2(cell_size, cell_size)).grow(-pad)
		TextureUtilsClass.draw_texture_aspect_fit(canvas, tex, rect, mod)

static func get_roadworks_marker_texture(skin) -> Texture2D:
	if skin == null:
		return null
	var key := _find_first_piece_id_by_suffix(skin, ROADWORK_MARKER_PIECE_SUFFIX)
	if key.is_empty():
		return null
	return skin.get_piece_texture(key) if skin.has_method("get_piece_texture") else null

static func _find_first_piece_id_by_suffix(skin, suffix: String) -> String:
	if skin == null:
		return ""
	if not skin.has_method("get"):
		return ""
	var dict_val = skin.get("piece_textures")
	if not (dict_val is Dictionary):
		return ""
	var dict: Dictionary = dict_val
	var keys: Array[String] = []
	for k in dict.keys():
		if not (k is String):
			continue
		var s := str(k).strip_edges()
		if s.ends_with(str(suffix)):
			keys.append(s)
	keys.sort()
	return keys[0] if keys.size() > 0 else ""

static func _get_roadworks_markers_dict(map_data: Dictionary) -> Dictionary:
	if map_data.is_empty():
		return {}
	var keys: Array[String] = []
	for k in map_data.keys():
		if not (k is String):
			continue
		var key: String = str(k).strip_edges()
		if key.ends_with(ROADWORK_MARKERS_KEY_SUFFIX):
			keys.append(key)
	keys.sort()

	var out := {}
	for key2 in keys:
		var val = map_data.get(key2, null)
		if not (val is Dictionary):
			continue
		var dict: Dictionary = val
		for pos_key in dict.keys():
			out[pos_key] = dict[pos_key]
	return out
