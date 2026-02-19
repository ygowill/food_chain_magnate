# MapCanvas：tooltip 文本格式化下沉
class_name MapCanvasTooltip
extends RefCounted

static func format_cell_tooltip(canvas, pos: Vector2i, cell: Dictionary) -> String:
	if cell.is_empty():
		return "pos=(%d,%d)" % [pos.x, pos.y]

	var lines: Array[String] = []
	lines.append("pos=(%d,%d)" % [pos.x, pos.y])

	var tile_origin: Vector2i = cell.get("tile_origin", Vector2i(-1, -1))
	if tile_origin != Vector2i(-1, -1):
		lines.append("tile_origin=(%d,%d)" % [tile_origin.x, tile_origin.y])

	if bool(cell.get("blocked", false)):
		lines.append("blocked=true")

	var road_segments: Array = cell.get("road_segments", [])
	if not road_segments.is_empty():
		lines.append("road_segments=%d" % road_segments.size())

	var drink_source_val = cell.get("drink_source", null)
	if drink_source_val is Dictionary:
		var drink_source: Dictionary = drink_source_val
		if not drink_source.is_empty():
			lines.append("drink=%s" % str(drink_source.get("type", "")))

	var structure: Dictionary = cell.get("structure", {})
	if not structure.is_empty():
		var piece_id := str(structure.get("piece_id", ""))
		var owner: int = int(structure.get("owner", -1))
		lines.append("structure=%s owner=%d" % [piece_id, owner])
		if structure.has("house_id") and not str(structure.get("house_id", "")).is_empty():
			lines.append("house_id=%s" % str(structure.get("house_id", "")))
		if structure.has("house_number"):
			lines.append("house_number=%s" % str(structure.get("house_number", "")))
		lines.append("rotation=%s" % str(structure.get("rotation", 0)))

		if piece_id == "house":
			var house_id := str(structure.get("house_id", ""))
			var info = canvas._get_house_info(house_id)
			if not info.is_empty():
				lines.append("has_garden=%s" % str(bool(info.get("has_garden", false))))
				var demands_val = info.get("demands", null)
				if demands_val is Array:
					var demands: Array = demands_val
					lines.append("demands=%d" % demands.size())

	if canvas._marketing_by_pos.has(pos):
		var mk: Dictionary = canvas._marketing_by_pos[pos]
		var bn = mk.get("board_number", null)
		var t := str(mk.get("type", ""))
		var product := str(mk.get("product", ""))
		var owner = mk.get("owner", null)
		var rd = mk.get("remaining_duration", null)
		lines.append("marketing=%s type=%s product=%s owner=%s duration=%s" % [
			str(bn), t, product, str(owner), str(rd)
		])

	return "\n".join(lines)
