extends RefCounted

const ParseHelpers = preload("res://core/state/serialization/parse_helpers.gd")

static func decode_map(value: Dictionary) -> Result:
	return decode_value(value, "", "GameState.map")

static func decode_value(value, key_hint: String, path: String) -> Result:
	if value is Dictionary:
		var out := {}
		for k in value.keys():
			if not (k is String):
				return Result.failure("%s key 类型错误（期望 String）" % path)
			var ks: String = k
			var v_read := decode_value(value[k], ks, "%s.%s" % [path, ks])
			if not v_read.ok:
				return v_read
			out[ks] = v_read.value
		return Result.success(out)

	if value is Array:
		# 形如 [x, y] 的坐标
		if value.size() == 2 and (value[0] is int or value[0] is float) and (value[1] is int or value[1] is float):
			match key_hint:
				"grid_size", "tile_grid_size", "tile_origin", "anchor_pos", "entrance_pos", "world_pos", "parent_anchor", "board_pos":
					var x_read := ParseHelpers.parse_int(value[0], "%s[0]" % path)
					if not x_read.ok:
						return x_read
					var y_read := ParseHelpers.parse_int(value[1], "%s[1]" % path)
					if not y_read.ok:
						return y_read
					return Result.success(Vector2i(int(x_read.value), int(y_read.value)))

		# 形如 [[x,y], [x,y], ...] 的坐标列表（例如 footprint/path/house cells）
		var all_vec2i := true
		for item in value:
			if not (item is Array and item.size() == 2 and (item[0] is int or item[0] is float) and (item[1] is int or item[1] is float)):
				all_vec2i = false
				break
		if all_vec2i and value.size() > 0:
			var out_vecs: Array[Vector2i] = []
			for i in range(value.size()):
				var item: Array = value[i]
				var x_read := ParseHelpers.parse_int(item[0], "%s[%d][0]" % [path, i])
				if not x_read.ok:
					return x_read
				var y_read := ParseHelpers.parse_int(item[1], "%s[%d][1]" % [path, i])
				if not y_read.ok:
					return y_read
				out_vecs.append(Vector2i(int(x_read.value), int(y_read.value)))
			return Result.success(out_vecs)

		var out_arr := []
		for i in range(value.size()):
			var item = value[i]
			var item_read := decode_value(item, key_hint, "%s[%d]" % [path, i])
			if not item_read.ok:
				return item_read
			out_arr.append(item_read.value)
		return Result.success(out_arr)

	return Result.success(value)

