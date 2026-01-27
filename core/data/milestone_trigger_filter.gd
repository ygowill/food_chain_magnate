# 里程碑触发 filter 匹配（从 milestone_def.gd 抽离）
extends RefCounted

static func matches_filter(trigger_filter: Dictionary, context: Dictionary) -> bool:
	if trigger_filter == null or trigger_filter.is_empty():
		return true

	for k in trigger_filter.keys():
		var expected = trigger_filter.get(k, null)
		var actual = context.get(k, null)
		if expected is Dictionary:
			var expected_dict: Dictionary = expected
			# 支持数值比较：{"paid": {"gte": 20}}
			if expected_dict.has("gte"):
				var limit_val = expected_dict.get("gte", null)
				if not ((limit_val is int or limit_val is float) and (actual is int or actual is float)):
					return false
				if float(actual) < float(limit_val):
					return false
				continue
			if expected_dict.has("gt"):
				var limit_val = expected_dict.get("gt", null)
				if not ((limit_val is int or limit_val is float) and (actual is int or actual is float)):
					return false
				if float(actual) <= float(limit_val):
					return false
				continue
			if expected_dict.has("lte"):
				var limit_val = expected_dict.get("lte", null)
				if not ((limit_val is int or limit_val is float) and (actual is int or actual is float)):
					return false
				if float(actual) > float(limit_val):
					return false
				continue
			if expected_dict.has("lt"):
				var limit_val = expected_dict.get("lt", null)
				if not ((limit_val is int or limit_val is float) and (actual is int or actual is float)):
					return false
				if float(actual) >= float(limit_val):
					return false
				continue
			if expected_dict.has("eq"):
				var eq_val = expected_dict.get("eq", null)
				if typeof(actual) != typeof(eq_val):
					return false
				if actual != eq_val:
					return false
				continue
			if expected_dict.has("in"):
				var in_val = expected_dict.get("in", null)
				if not (in_val is Array):
					return false
				var arr: Array = in_val
				if arr.find(actual) == -1 and arr.find(str(actual)) == -1:
					return false
				continue
			# 未知比较器：视为不匹配（Fail Close）
			return false
		match typeof(expected):
			TYPE_INT, TYPE_FLOAT:
				if actual == null:
					return false
				if int(actual) != int(expected):
					return false
			TYPE_BOOL:
				if actual == null:
					return false
				if bool(actual) != bool(expected):
					return false
			_:
				if str(actual) != str(expected):
					return false

	return true

