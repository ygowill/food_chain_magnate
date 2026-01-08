extends RefCounted

static func dump_cells(cells: Array, grid_size: Vector2i) -> String:
	var output := "=== Map Cells (%dx%d) ===\n" % [grid_size.x, grid_size.y]

	# 道路层
	output += "Roads:\n"
	for y in grid_size.y:
			var row_str := ""
			for x in grid_size.x:
				var cell: Dictionary = cells[y][x]
				assert(cell.has("road_segments") and (cell["road_segments"] is Array), "MapBaker.dump_cells: cell.road_segments 缺失或类型错误 (%d,%d)" % [x, y])
				var segments: Array = cell["road_segments"]
				if segments.is_empty():
					row_str += "."
				else:
					# 显示第一个段的方向数
					var seg0 = segments[0]
					assert(seg0 is Dictionary and seg0.has("dirs") and (seg0["dirs"] is Array), "MapBaker.dump_cells: road_segments[0].dirs 缺失或类型错误 (%d,%d)" % [x, y])
					var dirs: Array = seg0["dirs"]
					row_str += str(dirs.size())
			output += "  %s\n" % row_str

	# 建筑层
	output += "Structures:\n"
	for y in grid_size.y:
			var row_str := ""
			for x in grid_size.x:
				var cell: Dictionary = cells[y][x]
				assert(cell.has("structure") and (cell["structure"] is Dictionary), "MapBaker.dump_cells: cell.structure 缺失或类型错误 (%d,%d)" % [x, y])
				var structure: Dictionary = cell["structure"]
				if structure.is_empty():
					row_str += "."
				else:
					assert(structure.has("anchor_cell") and (structure["anchor_cell"] is bool), "MapBaker.dump_cells: structure.anchor_cell 缺失或类型错误 (%d,%d)" % [x, y])
					row_str += "A" if bool(structure["anchor_cell"]) else "#"
			output += "  %s\n" % row_str

	return output

