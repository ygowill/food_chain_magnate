extends RefCounted

static func to_json_safe(value):
	match typeof(value):
		TYPE_VECTOR2I:
			return [value.x, value.y]
		TYPE_VECTOR2:
			return [value.x, value.y]
		TYPE_COLOR:
			return [value.r, value.g, value.b, value.a]
		TYPE_DICTIONARY:
			var out := {}
			for k in value.keys():
				# JSON object key 必须是字符串；这里保持稳定且兼容反序列化
				out[str(k)] = to_json_safe(value[k])
			return out
		TYPE_ARRAY:
			var out_arr := []
			for item in value:
				out_arr.append(to_json_safe(item))
			return out_arr
		_:
			return value

