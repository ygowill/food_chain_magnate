extends RefCounted

const INVALID_CELL := Vector2i(-2147483648, -2147483648)

static func normalize_cells(cells: Array) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var bounds := get_bounds(cells)
	var min_pos: Vector2i = bounds.get("min", Vector2i.ZERO)
	var seen := {}
	for cell_val in cells:
		if not (cell_val is Vector2i):
			continue
		var local := Vector2i(cell_val) - min_pos
		var key := _cell_key(local)
		if seen.has(key):
			continue
		seen[key] = true
		out.append(local)
	return out

static func get_bounds(cells: Array) -> Dictionary:
	var min_pos := Vector2i(2147483647, 2147483647)
	var max_pos := Vector2i(-2147483648, -2147483648)
	var found := false
	for cell_val in cells:
		if not (cell_val is Vector2i):
			continue
		var cell := Vector2i(cell_val)
		found = true
		min_pos.x = mini(min_pos.x, cell.x)
		min_pos.y = mini(min_pos.y, cell.y)
		max_pos.x = maxi(max_pos.x, cell.x)
		max_pos.y = maxi(max_pos.y, cell.y)
	if not found:
		return {
			"min": Vector2i.ZERO,
			"max": Vector2i.ZERO,
			"size": Vector2i.ZERO,
		}
	return {
		"min": min_pos,
		"max": max_pos,
		"size": (max_pos - min_pos) + Vector2i.ONE,
	}

static func get_road_icon_center(cells: Array) -> Vector2:
	var local := normalize_cells(cells)
	if local.is_empty():
		return Vector2(0.5, 0.5)
	var corner := get_corner_cell(local)
	if corner != INVALID_CELL:
		return Vector2(float(corner.x) + 0.5, float(corner.y) + 0.5)
	var run := get_longest_cell_run(local)
	if run.is_empty():
		return Vector2(0.5, 0.5)
	var bounds := get_bounds(run)
	var min_pos: Vector2i = bounds.get("min", Vector2i.ZERO)
	var size: Vector2i = bounds.get("size", Vector2i.ONE)
	return Vector2(
		float(min_pos.x) + float(size.x) * 0.5,
		float(min_pos.y) + float(size.y) * 0.5
	)

static func get_corner_cell(cells: Array) -> Vector2i:
	var local := normalize_cells(cells)
	if local.is_empty():
		return INVALID_CELL
	var cell_set := _build_cell_set(local)
	for cell in local:
		var has_vertical := _has_cell(cell_set, cell + Vector2i(0, -1)) or _has_cell(cell_set, cell + Vector2i(0, 1))
		var has_horizontal := _has_cell(cell_set, cell + Vector2i(-1, 0)) or _has_cell(cell_set, cell + Vector2i(1, 0))
		if has_vertical and has_horizontal:
			return cell
	return INVALID_CELL

static func get_longest_cell_run(cells: Array) -> Array[Vector2i]:
	var local := normalize_cells(cells)
	var best: Array[Vector2i] = []
	if local.is_empty():
		return best
	var bounds := get_bounds(local)
	var size: Vector2i = bounds.get("size", Vector2i.ZERO)
	var cell_set := _build_cell_set(local)

	for y in range(size.y):
		var x := 0
		while x < size.x:
			var start := Vector2i(x, y)
			if not _has_cell(cell_set, start):
				x += 1
				continue
			var run: Array[Vector2i] = []
			while x < size.x and _has_cell(cell_set, Vector2i(x, y)):
				run.append(Vector2i(x, y))
				x += 1
			if run.size() > best.size():
				best = run

	for x in range(size.x):
		var y := 0
		while y < size.y:
			var start := Vector2i(x, y)
			if not _has_cell(cell_set, start):
				y += 1
				continue
			var run: Array[Vector2i] = []
			while y < size.y and _has_cell(cell_set, Vector2i(x, y)):
				run.append(Vector2i(x, y))
				y += 1
			if run.size() > best.size():
				best = run

	return best

static func is_run_vertical(run: Array) -> bool:
	if run.size() < 2:
		return false
	var first_val = run[0]
	var last_val = run[run.size() - 1]
	if not (first_val is Vector2i) or not (last_val is Vector2i):
		return false
	var first := Vector2i(first_val)
	var last := Vector2i(last_val)
	return first.x == last.x and first.y != last.y

static func get_rect_for_cells(cells: Array, origin: Vector2, cell_size: float) -> Rect2:
	var bounds := get_bounds(cells)
	var min_pos: Vector2i = bounds.get("min", Vector2i.ZERO)
	var size: Vector2i = bounds.get("size", Vector2i.ZERO)
	if size.x <= 0 or size.y <= 0:
		return Rect2()
	return Rect2(
		origin + Vector2(float(min_pos.x), float(min_pos.y)) * cell_size,
		Vector2(float(size.x), float(size.y)) * cell_size
	)

static func get_centered_rect(local_center: Vector2, origin: Vector2, cell_size: float, scale: float = 0.92) -> Rect2:
	var size_px := Vector2(cell_size, cell_size) * maxf(0.01, scale)
	var center_px := origin + local_center * cell_size
	return Rect2(center_px - size_px * 0.5, size_px)

static func _build_cell_set(cells: Array) -> Dictionary:
	var out := {}
	for cell_val in cells:
		if cell_val is Vector2i:
			out[_cell_key(Vector2i(cell_val))] = true
	return out

static func _has_cell(cell_set: Dictionary, cell: Vector2i) -> bool:
	return cell_set.has(_cell_key(cell))

static func _cell_key(cell: Vector2i) -> String:
	return "%d,%d" % [cell.x, cell.y]
