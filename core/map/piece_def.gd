# 建筑件定义
# 定义可放置的建筑物的属性（房屋、餐厅、营销板件等）
class_name PieceDef
extends RefCounted

# === 基础信息 ===
var id: String = ""
var display_name: String = ""
var category: String = "structure"  # "structure", "marketing", "terrain"

const MapUtilsClass = preload("res://core/map/map_utils.gd")
const PieceDefParserClass = preload("res://core/map/piece_def_parser.gd")
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

static func create_default_registry() -> Dictionary:
	return {
		"restaurant": create_restaurant(),
		"house": create_house(),
		"house_with_garden": create_house_with_garden(),
	}

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
	var read := PieceDefParserClass.parse_piece_def_dict(data)
	if not read.ok:
		return read
	var parsed: Dictionary = read.value

	var piece := PieceDef.new()
	piece.id = str(parsed.get("id", ""))
	piece.display_name = str(parsed.get("display_name", ""))
	piece.category = str(parsed.get("category", ""))
	piece.footprint_mask = parsed.get("footprint_mask", [[1]])
	piece.anchor = parsed.get("anchor", Vector2i.ZERO)
	piece.allowed_rotations = parsed.get("allowed_rotations", Array(_VALID_ROTATIONS, TYPE_INT, "", null))
	piece.mirror_allowed = bool(parsed.get("mirror_allowed", false))
	piece.must_be_on_empty = bool(parsed.get("must_be_on_empty", true))
	piece.must_touch_road = bool(parsed.get("must_touch_road", true))
	piece.allowed_on = parsed.get("allowed_on", ["ground"])
	piece.forbidden_layers = parsed.get("forbidden_layers", [])
	piece.entrance_type = str(parsed.get("entrance_type", ""))
	piece.entrance_points = parsed.get("entrance_points", [])
	piece.is_house = bool(parsed.get("is_house", false))
	piece.can_have_garden = bool(parsed.get("can_have_garden", false))
	piece.garden_extension_size = parsed.get("garden_extension_size", Vector2i(2, 1))

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
