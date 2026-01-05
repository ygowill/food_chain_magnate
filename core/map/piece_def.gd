# 建筑件定义
# 定义可放置的建筑物的属性（房屋、餐厅、营销板件等）
class_name PieceDef
extends RefCounted

# === 基础信息 ===
var id: String = ""
var display_name: String = ""
var category: String = "structure"  # "structure", "marketing", "terrain"

const MapUtilsClass = preload("res://core/map/map_utils.gd")
const _VALID_ROTATIONS = MapUtilsClass.VALID_ROTATIONS

# === 占地定义 ===
# 2D 数组，1 表示占用，0 表示空
# 例如 2x2 房屋: [[1, 1], [1, 1]]
var footprint_mask: Array = [[1]]

# 锚点位置 (相对于 footprint 左上角)
# 放置时锚点对齐到目标世界坐标
var anchor: Vector2i = Vector2i.ZERO

# 允许的旋转角度
var allowed_rotations: Array[int] = Array(MapUtilsClass.VALID_ROTATIONS, TYPE_INT, "", null)

# 是否允许镜像
var mirror_allowed: bool = false

# === 放置规则 ===
var must_be_on_empty: bool = true       # 必须放在空格子上
var must_touch_road: bool = true        # 必须邻接道路
var allowed_on: Array[String] = ["ground"]  # 允许的地形类型
var forbidden_layers: Array[String] = []    # 禁止的图层

# === 入口配置 (用于餐厅/服务) ===
var entrance_type: String = "adjacent_road"  # "adjacent_road" 或 "points"
var entrance_points: Array[Vector2i] = []    # 相对于锚点的入口位置

# === 特殊属性 ===
var is_house: bool = false
var can_have_garden: bool = false
var garden_extension_size: Vector2i = Vector2i(2, 1)  # 花园扩展大小

# === 工厂方法 ===

static func create_simple(piece_id: String, width: int, height: int) -> PieceDef:
	var piece := PieceDef.new()
	piece.id = piece_id
	piece.display_name = piece_id

	# 创建矩形占地
	piece.footprint_mask = []
	for y in height:
		var row := []
		for x in width:
			row.append(1)
		piece.footprint_mask.append(row)

	return piece

# 创建房屋定义
static func create_house() -> PieceDef:
	var piece := create_simple("house", 2, 2)
	piece.display_name = "房屋"
	piece.category = "structure"
	piece.is_house = true
	piece.can_have_garden = true
	return piece

# 创建带花园房屋定义
static func create_house_with_garden() -> PieceDef:
	var piece := create_simple("house_with_garden", 3, 2)
	piece.display_name = "带花园房屋"
	piece.category = "structure"
	piece.is_house = true
	piece.can_have_garden = false  # 已经有花园了
	return piece

# 创建餐厅定义
static func create_restaurant() -> PieceDef:
	var piece := create_simple("restaurant", 2, 2)
	piece.display_name = "餐厅"
	piece.category = "structure"
	piece.entrance_type = "points"
	# 入口在左上角
	piece.entrance_points = [Vector2i(0, 0)]
	return piece

# === 序列化 ===

func to_dict() -> Dictionary:
	var entrance_pts := []
	for pt in entrance_points:
		entrance_pts.append([pt.x, pt.y])

	return {
		"id": id,
		"display_name": display_name,
		"category": category,
		"footprint_mask": footprint_mask,
		"anchor": [anchor.x, anchor.y],
		"allowed_rotations": allowed_rotations,
		"mirror_allowed": mirror_allowed,
		"must_be_on_empty": must_be_on_empty,
		"must_touch_road": must_touch_road,
		"allowed_on": allowed_on,
		"forbidden_layers": forbidden_layers,
		"entrance_type": entrance_type,
		"entrance_points": entrance_pts,
		"is_house": is_house,
		"can_have_garden": can_have_garden,
		"garden_extension_size": [garden_extension_size.x, garden_extension_size.y]
	}

static func from_dict(data: Dictionary) -> Result:
	if not (data is Dictionary):
		return Result.failure("PieceDef.from_dict: data 类型错误（期望 Dictionary）")

	var required_keys := [
		"id",
		"display_name",
		"category",
		"footprint_mask",
		"anchor",
		"allowed_rotations",
		"mirror_allowed",
		"must_be_on_empty",
		"must_touch_road",
		"allowed_on",
		"forbidden_layers",
		"entrance_type",
		"entrance_points",
		"is_house",
		"can_have_garden",
		"garden_extension_size",
	]
	for key in required_keys:
		if not data.has(key):
			return Result.failure("PieceDef 缺少字段: %s" % key)

	var id_val = data.get("id", null)
	if not (id_val is String) or str(id_val).is_empty():
		return Result.failure("PieceDef.id 类型错误或为空（期望非空 String）")
	var display_name_val = data.get("display_name", null)
	if not (display_name_val is String) or str(display_name_val).is_empty():
		return Result.failure("PieceDef.display_name 类型错误或为空（期望非空 String）")
	var category_val = data.get("category", null)
	if not (category_val is String) or str(category_val).is_empty():
		return Result.failure("PieceDef.category 类型错误或为空（期望非空 String）")

	var footprint_val = data.get("footprint_mask", null)
	var footprint_read := _parse_footprint_mask(footprint_val, "PieceDef.footprint_mask")
	if not footprint_read.ok:
		return footprint_read

	var anchor_read := _parse_vec2i(data.get("anchor", null), "PieceDef.anchor")
	if not anchor_read.ok:
		return anchor_read

	var rotations_read := _parse_rotation_array(data.get("allowed_rotations", null), "PieceDef.allowed_rotations")
	if not rotations_read.ok:
		return rotations_read

	var mirror_val = data.get("mirror_allowed", null)
	if not (mirror_val is bool):
		return Result.failure("PieceDef.mirror_allowed 类型错误（期望 bool）")
	var must_be_on_empty_val = data.get("must_be_on_empty", null)
	if not (must_be_on_empty_val is bool):
		return Result.failure("PieceDef.must_be_on_empty 类型错误（期望 bool）")
	var must_touch_road_val = data.get("must_touch_road", null)
	if not (must_touch_road_val is bool):
		return Result.failure("PieceDef.must_touch_road 类型错误（期望 bool）")

	var allowed_on_read := _parse_string_array(data.get("allowed_on", null), "PieceDef.allowed_on", true)
	if not allowed_on_read.ok:
		return allowed_on_read
	var forbidden_layers_read := _parse_string_array(data.get("forbidden_layers", null), "PieceDef.forbidden_layers", false)
	if not forbidden_layers_read.ok:
		return forbidden_layers_read

	var entrance_type_val = data.get("entrance_type", null)
	if not (entrance_type_val is String) or str(entrance_type_val).is_empty():
		return Result.failure("PieceDef.entrance_type 类型错误或为空（期望非空 String）")

	var entrance_points_read := _parse_vec2i_list(data.get("entrance_points", null), "PieceDef.entrance_points")
	if not entrance_points_read.ok:
		return entrance_points_read

	var is_house_val = data.get("is_house", null)
	if not (is_house_val is bool):
		return Result.failure("PieceDef.is_house 类型错误（期望 bool）")
	var can_have_garden_val = data.get("can_have_garden", null)
	if not (can_have_garden_val is bool):
		return Result.failure("PieceDef.can_have_garden 类型错误（期望 bool）")

	var garden_size_read := _parse_vec2i(data.get("garden_extension_size", null), "PieceDef.garden_extension_size")
	if not garden_size_read.ok:
		return garden_size_read

	var piece := PieceDef.new()
	piece.id = str(id_val)
	piece.display_name = str(display_name_val)
	piece.category = str(category_val)
	piece.footprint_mask = footprint_read.value
	piece.anchor = anchor_read.value
	piece.allowed_rotations = rotations_read.value
	piece.mirror_allowed = bool(mirror_val)
	piece.must_be_on_empty = bool(must_be_on_empty_val)
	piece.must_touch_road = bool(must_touch_road_val)
	piece.allowed_on = allowed_on_read.value
	piece.forbidden_layers = forbidden_layers_read.value
	piece.entrance_type = str(entrance_type_val)
	piece.entrance_points = entrance_points_read.value
	piece.is_house = bool(is_house_val)
	piece.can_have_garden = bool(can_have_garden_val)
	piece.garden_extension_size = garden_size_read.value

	return Result.success(piece)

static func from_json(json_string: String) -> Result:
	var data = JSON.parse_string(json_string)
	if data == null or not (data is Dictionary):
		return Result.failure("PieceDef JSON 解析失败")
	return from_dict(data)

static func load_from_file(path: String) -> Result:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return Result.failure("无法打开 PieceDef: %s" % path)
	var json := file.get_as_text()
	file.close()
	return from_json(json)

# === 严格解析辅助 ===

static func _parse_int(value, path: String) -> Result:
	if value is int:
		return Result.success(int(value))
	if value is float:
		var f: float = float(value)
		if f != floor(f):
			return Result.failure("%s 必须为整数，实际: %s" % [path, str(value)])
		return Result.success(int(f))
	return Result.failure("%s 类型错误（期望整数）" % path)

static func _parse_vec2i(value, path: String) -> Result:
	if not (value is Array) or value.size() != 2:
		return Result.failure("%s 类型错误（期望 [x,y]）" % path)
	var x_read := _parse_int(value[0], "%s[0]" % path)
	if not x_read.ok:
		return x_read
	var y_read := _parse_int(value[1], "%s[1]" % path)
	if not y_read.ok:
		return y_read
	return Result.success(Vector2i(int(x_read.value), int(y_read.value)))

static func _parse_rotation_array(value, path: String) -> Result:
	if not (value is Array):
		return Result.failure("%s 类型错误（期望 Array[int]）" % path)
	var out: Array[int] = []
	for i in range(value.size()):
		var v_read := _parse_int(value[i], "%s[%d]" % [path, i])
		if not v_read.ok:
			return v_read
		var rot: int = int(v_read.value)
		if not _VALID_ROTATIONS.has(rot):
			return Result.failure("%s[%d] 旋转角非法: %d" % [path, i, rot])
		out.append(rot)
	if out.is_empty():
		return Result.failure("%s 不能为空" % path)
	return Result.success(out)

static func _parse_string_array(value, path: String, require_non_empty: bool) -> Result:
	if not (value is Array):
		return Result.failure("%s 类型错误（期望 Array[String]）" % path)
	var out: Array[String] = []
	for i in range(value.size()):
		var item = value[i]
		if not (item is String):
			return Result.failure("%s[%d] 类型错误（期望 String）" % [path, i])
		var s := str(item)
		if s.is_empty():
			return Result.failure("%s[%d] 不能为空字符串" % [path, i])
		out.append(s)
	if require_non_empty and out.is_empty():
		return Result.failure("%s 不能为空" % path)
	return Result.success(out)

static func _parse_vec2i_list(value, path: String) -> Result:
	if not (value is Array):
		return Result.failure("%s 类型错误（期望 Array[[x,y],...]）" % path)
	var out: Array[Vector2i] = []
	for i in range(value.size()):
		var v_read := _parse_vec2i(value[i], "%s[%d]" % [path, i])
		if not v_read.ok:
			return v_read
		out.append(v_read.value)
	return Result.success(out)

static func _parse_footprint_mask(value, path: String) -> Result:
	if not (value is Array) or value.is_empty():
		return Result.failure("%s 类型错误或为空（期望二维 Array）" % path)
	var out: Array = []
	var expected_width := -1
	for y in range(value.size()):
		var row = value[y]
		if not (row is Array) or row.is_empty():
			return Result.failure("%s[%d] 类型错误或为空（期望 Array[int]）" % [path, y])
		if expected_width == -1:
			expected_width = row.size()
		elif row.size() != expected_width:
			return Result.failure("%s[%d] 长度不一致（期望 %d，实际 %d）" % [path, y, expected_width, row.size()])
		var out_row: Array = []
		for x in range(row.size()):
			var cell_read := _parse_int(row[x], "%s[%d][%d]" % [path, y, x])
			if not cell_read.ok:
				return cell_read
			var v: int = int(cell_read.value)
			if v != 0 and v != 1:
				return Result.failure("%s[%d][%d] 仅允许 0/1，实际 %d" % [path, y, x, v])
			out_row.append(v)
		out.append(out_row)
	return Result.success(out)

# === 查询方法 ===

# 获取占地尺寸
func get_size() -> Vector2i:
	if footprint_mask.is_empty():
		return Vector2i.ZERO

	var height := footprint_mask.size()
	var width := 0
	for row in footprint_mask:
		width = max(width, row.size())

	return Vector2i(width, height)

# 获取占用的格子数
func get_cell_count() -> int:
	var count := 0
	for row in footprint_mask:
		for cell in row:
			if cell == 1:
				count += 1
	return count

# 获取相对于锚点的所有占用偏移
func get_offsets() -> Array[Vector2i]:
	var offsets: Array[Vector2i] = []
	for y in footprint_mask.size():
		var row: Array = footprint_mask[y]
		for x in row.size():
			if row[x] == 1:
				offsets.append(Vector2i(x, y) - anchor)
	return offsets

# 获取旋转后的占用格子 (世界坐标)
func get_world_cells(world_anchor: Vector2i, rotation: int) -> Array[Vector2i]:
	return MapUtils.get_footprint_cells(footprint_mask, anchor, world_anchor, rotation)

# 获取旋转后的入口点 (世界坐标)
func get_world_entrance_points(world_anchor: Vector2i, rotation: int) -> Array[Vector2i]:
	var points: Array[Vector2i] = []
	for pt in entrance_points:
		var rotated := MapUtils.rotate_offset(pt - anchor, rotation)
		points.append(world_anchor + rotated)
	return points

# 检查旋转是否允许
func is_rotation_allowed(rotation: int) -> bool:
	return allowed_rotations.has(rotation)

# === 验证 ===

func validate() -> Result:
	if id.is_empty():
		return Result.failure("建筑件缺少 ID")

	if footprint_mask.is_empty():
		return Result.failure("建筑件缺少占地定义")

	# 检查占地定义有效性
	var height := footprint_mask.size()
	if height == 0:
		return Result.failure("占地定义为空")

	var width := 0
	for row in footprint_mask:
		width = max(width, row.size())

	# 检查锚点在占地范围内
	if anchor.x < 0 or anchor.x >= width or anchor.y < 0 or anchor.y >= height:
		return Result.failure("锚点超出占地范围: %s (尺寸 %dx%d)" % [str(anchor), width, height])

	# 检查锚点位置是否被占用
	if footprint_mask[anchor.y][anchor.x] != 1:
		return Result.failure("锚点位置未被占用")

	# 检查旋转角度
	for rot in allowed_rotations:
		if rot not in _VALID_ROTATIONS:
			return Result.failure("无效的旋转角度: %d" % rot)

	# 检查入口点
	if entrance_type == "points":
		for pt in entrance_points:
			# 入口点可以在占地外（邻接）
			pass

	return Result.success()

# === 调试 ===

func dump() -> String:
	var output := "=== PieceDef: %s ===\n" % id
	output += "Category: %s\n" % category
	output += "Size: %s\n" % str(get_size())
	output += "Anchor: %s\n" % str(anchor)

	output += "Footprint:\n"
	for y in footprint_mask.size():
		var row: Array = footprint_mask[y]
		var row_str := "  "
		for x in row.size():
			if Vector2i(x, y) == anchor:
				row_str += "A " if row[x] == 1 else ". "
			else:
				row_str += "# " if row[x] == 1 else ". "
		output += row_str + "\n"

	output += "Rotations: %s\n" % str(allowed_rotations)
	output += "Must touch road: %s\n" % str(must_touch_road)
	if entrance_type == "points":
		output += "Entrance points: %s\n" % str(entrance_points)

	return output
