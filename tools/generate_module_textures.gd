# 模块资源：生成地图贴图（开发期辅助 - 顶视图 V4）
# 目标：
# 1. [保持] 道路为柏油材质，直角转弯，立体交叉分层。
# 2. [修改] 房屋、餐厅改为纯顶视图 (Top-Down)。
# 3. [修改] 产品图标改为具象化符号，而非单纯圆点。
# 4. [新增] 公园顶视图 (1x1)。
# 5. [新增] 大花园顶视图 (1x2, 128x256)。
#
# 运行方式同前。

extends SceneTree

const NAME := "GenerateModuleTextures"

# --- 配置 ---
const SIZE_CELL := 64    # 地块/道路单元格大小
const SIZE_PIECE := 128  # 标准建筑大小 (1x1)
const SIZE_ICON := 64    # 图标大小

# --- 调色板 (顶视图风格) ---
# 地面/自然
const C_GRASS_BASE   := Color("4fae60") # 草地基色
const C_GRASS_DARK   := Color("409650") # 草地纹理
const C_DIRT         := Color("8d6e63") # 泥土/田垄
const C_WATER        := Color("3498db") # 水面
const C_PATHWAY      := Color("bdc3c7") # 混凝土小径
const C_TREE_DARK    := Color("2d6a4f") # 树冠深色

# 道路 (保持不变)
const C_ROAD_ASPHALT := Color("34495e")
const C_ROAD_MARKING := Color("f1c40f")
const C_ROAD_SIDEWALK:= Color("95a5a6")
const C_BRIDGE_RAIL  := Color("2c3e50")
const C_SHADOW       := Color(0, 0, 0, 0.4)

# 建筑顶视图
const C_ROOF_RED     := Color("c0392b") # 红瓦屋顶
const C_ROOF_FLAT    := Color("7f8c8d") # 灰色平顶
const C_AC_UNIT      := Color("95a5a6") # 空调外机银灰
const C_CHIMNEY      := Color("795548") # 烟囱砖色

# 图标 (保持不变)
const C_ICON_BG      := Color("ecf0f1")
const C_ICON_OUTLINE := Color("2c3e50")

func _initialize() -> void:
	print("[%s] START (Top-Down V4)" % NAME)
	var errors: Array[String] = []

	_generate_ground_textures(errors)
	_generate_road_textures(errors)
	_generate_piece_textures(errors)
	_generate_product_icons(errors)
	_generate_marketing_icons(errors)

	if errors.is_empty():
		print("[%s] PASS" % NAME)
		quit(0)
		return
	push_error("[%s] FAIL count=%d" % [NAME, errors.size()])
	for i in range(min(errors.size(), 20)): push_error(errors[i])
	quit(1)

# --- 基础工具 & SDF 引擎 ---

static func _write_png(res_path: String, img: Image, errors: Array[String]) -> void:
	if img == null: return
	var abs_path: String = ProjectSettings.globalize_path(res_path)
	var dir_path: String = abs_path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir_path): DirAccess.make_dir_recursive_absolute(dir_path)
	img.save_png(abs_path)

# 更新：支持非正方形
static func _new_image(w: int, h: int) -> Image:
	return Image.create(w, h, false, Image.FORMAT_RGBA8)

static func _blend_pixel(img: Image, x: int, y: int, color: Color) -> void:
	if x < 0 or x >= img.get_width() or y < 0 or y >= img.get_height(): return
	if color.a <= 0.0: return
	if color.a >= 1.0: img.set_pixel(x, y, color)
	else: img.set_pixel(x, y, img.get_pixel(x, y).blend(color))

# 通用 SDF 填充
static func _fill_sdf(img: Image, color: Color, sdf_func: Callable, softness: float = 1.0) -> void:
	var w := img.get_width()
	var h := img.get_height()
	for y in range(h):
		for x in range(w):
			var pos := Vector2(x + 0.5, y + 0.5)
			var d: float = sdf_func.call(pos)
			# 使用 smoothstep 实现抗锯齿边缘
			var alpha_factor := 1.0 - smoothstep(-softness, softness, d)
			if alpha_factor > 0.0:
				var draw_c := color
				draw_c.a *= alpha_factor
				_blend_pixel(img, x, y, draw_c)

# --- SDF 形状函数 ---
# 基础形状
static func _sdf_box(p: Vector2, center: Vector2, half_size: Vector2) -> float:
	var d := (p - center).abs() - half_size
	return maxf(d.x, d.y)

static func _sdf_rounded_box(p: Vector2, center: Vector2, half_size: Vector2, radius: float) -> float:
	var q := (p - center).abs() - half_size + Vector2(radius, radius)
	return Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0) - radius

static func _sdf_circle(pos: Vector2, center: Vector2, radius: float) -> float:
	return pos.distance_to(center) - radius

# 组合操作 (Union/Subtract/Intersect)
static func _sdf_union(d1: float, d2: float) -> float: return minf(d1, d2)
static func _sdf_sub(d_base: float, d_cut: float) -> float: return maxf(d_base, -d_cut)
static func _sdf_intersect(d1: float, d2: float) -> float: return maxf(d1, d2)

# --- 道路生成逻辑 (保持 V4 直角逻辑) ---

	static func _generate_road_textures(errors: Array[String]) -> void:
		var configs = [
			{ "name": "road_default",  "dirs": ["N","S","E","W"], "bridge": false },
			{ "name": "road_end",      "dirs": ["N"],             "bridge": false },
			{ "name": "road_straight", "dirs": ["N","S"],         "bridge": false },
			{ "name": "road_corner",   "dirs": ["W","S"],         "bridge": false },
			{ "name": "road_tee",      "dirs": ["N","W","S"],     "bridge": false },
			{ "name": "road_cross",    "dirs": ["N","S","E","W"], "bridge": false },
			{ "name": "bridge_default",  "dirs": ["N","S","E","W"], "bridge": true },
			{ "name": "bridge_end",      "dirs": ["N"],             "bridge": true },
			{ "name": "bridge_straight", "dirs": ["N","S"],         "bridge": true },
			{ "name": "bridge_corner",   "dirs": ["W","S"],         "bridge": true },
			{ "name": "bridge_tee",      "dirs": ["N","W","S"],     "bridge": true },
		]
	for cfg in configs:
		var img := _make_road_tile_sdf(cfg.dirs, cfg.bridge)
		_write_png("res://modules/base_tiles/assets/map/roads/%s.png" % cfg.name, img, errors)

	# Bridge Cross (立体交叉)
	var img_cross := _new_image(SIZE_CELL, SIZE_CELL)
	var c := Vector2(SIZE_CELL / 2.0, SIZE_CELL / 2.0)
	_draw_single_road_layer(img_cross, ["N", "S"], false) # 下层
	_fill_sdf(img_cross, C_SHADOW, func(p): return _sdf_box(p, c + Vector2(0, 4), Vector2(SIZE_CELL, 14)), 4.0) # 阴影
	_draw_single_road_layer(img_cross, ["E", "W"], true) # 上层
	_write_png("res://modules/base_tiles/assets/map/roads/bridge_cross.png", img_cross, errors)

static func _make_road_tile_sdf(dirs: Array, is_bridge: bool) -> Image:
	var img := _new_image(SIZE_CELL, SIZE_CELL)
	_draw_single_road_layer(img, dirs, is_bridge)
	return img

static func _draw_single_road_layer(img: Image, dirs: Array, is_bridge: bool) -> void:
	var c := Vector2(SIZE_CELL / 2.0, SIZE_CELL / 2.0)
	var r_width := 18.0; var walk_width := 24.0
	_fill_sdf(img, C_ROAD_SIDEWALK, func(p): return _sdf_road_shape(p, c, walk_width, dirs))
	if is_bridge:
		_fill_sdf(img, C_BRIDGE_RAIL, func(p): return _sdf_sub(_sdf_road_shape(p, c, walk_width, dirs), _sdf_road_shape(p, c, r_width + 1.0, dirs)))
	_fill_sdf(img, C_ROAD_ASPHALT, func(p): return _sdf_road_shape(p, c, r_width, dirs))
	_fill_sdf(img, C_ROAD_MARKING, func(p): return _sdf_road_markings(p, c, dirs))

static func _sdf_road_shape(p: Vector2, center: Vector2, half_w: float, dirs: Array) -> float:
	var d := 10000.0
	d = minf(d, _sdf_box(p, center, Vector2(half_w, half_w))) # 中心连接块
	if dirs.has("N"): d = minf(d, _sdf_box(p, Vector2(center.x, 0), Vector2(half_w, center.y)))
	if dirs.has("S"): d = minf(d, _sdf_box(p, Vector2(center.x, SIZE_CELL), Vector2(half_w, center.y)))
	if dirs.has("W"): d = minf(d, _sdf_box(p, Vector2(0, center.y), Vector2(center.x, half_w)))
	if dirs.has("E"): d = minf(d, _sdf_box(p, Vector2(SIZE_CELL, center.y), Vector2(center.x, half_w)))
	return d

# 道路标线逻辑 (90度直角连接)
static func _sdf_road_markings(p: Vector2, center: Vector2, dirs: Array) -> float:
	var line_width := 1.5; var d := 10000.0; var current_dash_val := 1.0; var freq := 0.5
	if dirs.has("N"):
		var dist = _sdf_box(p, Vector2(center.x, center.y/2.0), Vector2(line_width, center.y/2.0))
		if dist < d: d = dist; current_dash_val = sin(p.y * freq)
	if dirs.has("S"):
		var dist = _sdf_box(p, Vector2(center.x, center.y + (SIZE_CELL-center.y)/2.0), Vector2(line_width, (SIZE_CELL-center.y)/2.0))
		if dist < d: d = dist; current_dash_val = sin(p.y * freq)
	if dirs.has("W"):
		var dist = _sdf_box(p, Vector2(center.x/2.0, center.y), Vector2(center.x/2.0, line_width))
		if dist < d: d = dist; current_dash_val = sin(p.x * freq)
	if dirs.has("E"):
		var dist = _sdf_box(p, Vector2(center.x + (SIZE_CELL-center.x)/2.0, center.y), Vector2((SIZE_CELL-center.x)/2.0, line_width))
		if dist < d: d = dist; current_dash_val = sin(p.x * freq)
	if _sdf_box(p, center, Vector2(line_width, line_width)) <= 0.0: current_dash_val = -1.0 # 中心强制实心
	if current_dash_val > 0.1: return maxf(d, 2.0) # 虚线空隙
	return d

# --- 地块与建筑生成 (顶视图重绘) ---

static func _generate_ground_textures(errors: Array[String]) -> void:
	var img := _new_image(SIZE_CELL, SIZE_CELL)
	var noise := FastNoiseLite.new(); noise.seed = 1337; noise.frequency = 0.05
	for y in range(SIZE_CELL): for x in range(SIZE_CELL):
		img.set_pixel(x, y, C_GRASS_BASE.lerp(C_GRASS_DARK, (noise.get_noise_2d(x, y) + 1.0) * 0.3))
	_write_png("res://modules/base_tiles/assets/map/ground/ground.png", img, errors)
	
	var blocked := _new_image(SIZE_CELL, SIZE_CELL)
	_fill_sdf(blocked, Color(0.9, 0.2, 0.2, 0.3), func(p): return _sdf_box(p, Vector2(32,32), Vector2(31,31)))
	_fill_sdf(blocked, Color(0.9, 0.1, 0.1, 0.8), func(p): return absf(_sdf_box(p, Vector2(32,32), Vector2(30,30))) - 2.0)
	_fill_sdf(blocked, Color(0.9, 0.1, 0.1, 0.6), func(p): return minf(absf(p.x - p.y), absf((p.x + p.y) - 64.0)) - 3.0)
	_write_png("res://modules/base_tiles/assets/map/ground/blocked.png", blocked, errors)

static func _generate_piece_textures(errors: Array[String]) -> void:
	var c := Vector2(SIZE_PIECE/2.0, SIZE_PIECE/2.0)
	
	# 1. 房屋 (House) - 顶视图
	# 表现为红色的坡屋顶和一个小烟囱
	var house := _new_image(SIZE_PIECE, SIZE_PIECE)
	# 屋顶主体 (用圆角矩形模拟俯视的坡屋顶边缘)
	_fill_sdf(house, C_ROOF_RED, func(p): return _sdf_rounded_box(p, c, Vector2(45, 35), 4.0))
	# 屋顶脊线 (简单的十字交叉线，表现屋顶结构)
	_fill_sdf(house, C_ROOF_RED.darkened(0.2), func(p):
		var ridge_v = _sdf_box(p, c, Vector2(2, 35))
		var ridge_h = _sdf_box(p, c, Vector2(45, 2))
		return _sdf_union(ridge_v, ridge_h)
	)
	# 烟囱 (小矩形)
	_fill_sdf(house, C_CHIMNEY, func(p): return _sdf_box(p, c + Vector2(25, -15), Vector2(6, 6)))
	_write_png("res://modules/base_pieces/assets/map/pieces/house.png", house, errors)

	# 2. 花园房屋 (House with Garden) - 顶视图复用
	# 在房屋底部增加一片草地
	var garden_house := _new_image(SIZE_PIECE, SIZE_PIECE)
	# 底层草地
	_fill_sdf(garden_house, C_GRASS_BASE, func(p): return _sdf_rounded_box(p, c, Vector2(55, 55), 8.0))
	# 简单的围栏
	_fill_sdf(garden_house, C_DIRT, func(p): return absf(_sdf_rounded_box(p, c, Vector2(52, 52), 8.0)) - 2.0)
	# 将房屋叠加上去
	for y in range(SIZE_PIECE): for x in range(SIZE_PIECE): _blend_pixel(garden_house, x, y, house.get_pixel(x, y))
	_write_png("res://modules/base_pieces/assets/map/pieces/house_with_garden.png", garden_house, errors)

	# 3. 餐厅 (Restaurant) - 顶视图
	# 表现为灰色平顶，带有空调外机和排风口
	var rest := _new_image(SIZE_PIECE, SIZE_PIECE)
	# 平屋顶主体
	_fill_sdf(rest, C_ROOF_FLAT, func(p): return _sdf_rounded_box(p, c, Vector2(50, 40), 2.0))
	# 屋顶边缘女儿墙 (稍微深一点的框)
	_fill_sdf(rest, C_ROOF_FLAT.darkened(0.1), func(p): return absf(_sdf_rounded_box(p, c, Vector2(48, 38), 2.0)) - 3.0)
	# 空调外机 (两个小灰盒子)
	_fill_sdf(rest, C_AC_UNIT, func(p): return _sdf_union(
		_sdf_box(p, c + Vector2(-20, -10), Vector2(8, 5)),
		_sdf_box(p, c + Vector2(-20, 10), Vector2(8, 5))
	))
	# 大型排风扇 (圆形)
	_fill_sdf(rest, C_AC_UNIT.darkened(0.2), func(p): return _sdf_circle(p, c + Vector2(25, 0), 10.0))
	# 排风扇扇叶示意 (十字)
	_fill_sdf(rest, C_AC_UNIT.darkened(0.4), func(p): return _sdf_union(
		_sdf_box(p, c + Vector2(25, 0), Vector2(8, 2)),
		_sdf_box(p, c + Vector2(25, 0), Vector2(2, 8))
	))
	_write_png("res://modules/base_pieces/assets/map/pieces/restaurant.png", rest, errors)

	# 4. [新增] 公园 (Park) - 1x1 顶视图
	var park := _new_image(SIZE_PIECE, SIZE_PIECE)
	# 草地底色
	_fill_sdf(park, C_GRASS_BASE, func(p): return _sdf_box(p, c, Vector2(60, 60)))
	# 环形小径 (灰色混凝土)
	_fill_sdf(park, C_PATHWAY, func(p):
		var outer = _sdf_circle(p, c, 50.0)
		var inner = _sdf_circle(p, c, 30.0)
		return maxf(outer, -inner) # 环形 = 外圆 - 内圆
	)
	# 中心水池/喷泉 (蓝色圆形)
	_fill_sdf(park, C_WATER, func(p): return _sdf_circle(p, c, 15.0))
	# 四角的树木 (深绿色圆)
	var tree_positions = [c+Vector2(-40,-40), c+Vector2(40,-40), c+Vector2(-40,40), c+Vector2(40,40)]
	for pos in tree_positions:
		_fill_sdf(park, C_TREE_DARK, func(p): return _sdf_circle(p, pos, 12.0))
		# 树心高光
		_fill_sdf(park, C_TREE_DARK.lightened(0.2), func(p): return _sdf_circle(p, pos+Vector2(-3,-3), 5.0))

	_write_png("res://modules/base_pieces/assets/map/pieces/park.png", park, errors)

	# 5. [新增] 大花园 (Large Garden) - 1x2 顶视图 (128x256)
	var w := SIZE_PIECE; var h := SIZE_PIECE * 2
	var garden_lg := _new_image(w, h)
	var c_lg := Vector2(w/2.0, h/2.0)
	
	# 泥土底色
	_fill_sdf(garden_lg, C_DIRT, func(p): return _sdf_box(p, c_lg, Vector2(w/2.0-4, h/2.0-4)))
	
	# 种植田垄 (使用 fmod 取模生成重复条纹)
	_fill_sdf(garden_lg, C_GRASS_DARK, func(p):
		# 在 Y 轴上每隔 20 像素生成一条宽 8 像素的垄
		var strip_pattern = absf(fmod(p.y, 20.0) - 10.0) - 4.0
		# 限制田垄在泥土范围内
		var box_mask = _sdf_box(p, c_lg, Vector2(w/2.0-10, h/2.0-10))
		return _sdf_intersect(strip_pattern, box_mask)
	)
	# 中央灌溉水渠
	_fill_sdf(garden_lg, C_WATER, func(p): return _sdf_box(p, c_lg, Vector2(4, h/2.0-4)))

	_write_png("res://modules/base_pieces/assets/map/pieces/garden_large.png", garden_lg, errors)

# --- 图标生成 (具象化符号) ---

# 绘制通用图标背景
static func _draw_icon_bg(img: Image, bg_color: Color) -> void:
	var c := Vector2(SIZE_ICON/2.0, SIZE_ICON/2.0)
	var r := SIZE_ICON/2.0 - 4.0
	_fill_sdf(img, Color(0,0,0,0.15), func(p): return _sdf_circle(p, c + Vector2(2,2), r)) # 阴影
	_fill_sdf(img, C_ICON_BG, func(p): return _sdf_circle(p, c, r)) # 白底
	_fill_sdf(img, C_ICON_OUTLINE, func(p): return absf(_sdf_circle(p, c, r)) - 2.0) # 深色边框
	# 产品背景色圆
	_fill_sdf(img, bg_color, func(p): return _sdf_circle(p, c, r - 6.0))

static func _generate_product_icons(errors: Array[String]) -> void:
	var c := Vector2(SIZE_ICON/2.0, SIZE_ICON/2.0)

	# 1. 啤酒 (Beer) - 黄色背景，酒杯形状
	var img_beer := _new_image(SIZE_ICON, SIZE_ICON)
	_draw_icon_bg(img_beer, Color("f1c40f")) # 黄色
	# 杯身 (梯形近似)
	_fill_sdf(img_beer, Color.WHITE, func(p): return _sdf_rounded_box(p, c + Vector2(0, 2), Vector2(10, 14), 2.0))
	# 杯把手 (右侧半圆环)
	_fill_sdf(img_beer, Color.WHITE, func(p):
		var ring = absf(_sdf_circle(p, c + Vector2(10, 2), 6.0)) - 2.0
		var box_cut = _sdf_box(p, c + Vector2(6, 2), Vector2(4, 10)) # 切掉左半边
		return _sdf_sub(ring, box_cut)
	)
	# 啤酒泡沫 (顶部波浪/云朵)
	_fill_sdf(img_beer, Color.WHITE, func(p): return _sdf_union(
		_sdf_circle(p, c + Vector2(-6, -12), 4.0),
		_sdf_circle(p, c + Vector2( 6, -12), 4.0)
	))
	_write_png("res://modules/base_products/assets/map/icons/beer.png", img_beer, errors)

	# 2. 汉堡 (Burger) - 橙色背景，汉堡形状
	var img_burger := _new_image(SIZE_ICON, SIZE_ICON)
	_draw_icon_bg(img_burger, Color("e67e22")) # 橙色
	var bun_col := Color("f39c12"); var meat_col := Color("c0392b")
	# 下面包胚
	_fill_sdf(img_burger, bun_col, func(p): return _sdf_rounded_box(p, c + Vector2(0, 8), Vector2(14, 5), 3.0))
	# 肉饼
	_fill_sdf(img_burger, meat_col, func(p): return _sdf_rounded_box(p, c + Vector2(0, 0), Vector2(15, 3), 2.0))
	# 上面包胚
	_fill_sdf(img_burger, bun_col, func(p): return _sdf_rounded_box(p, c + Vector2(0, -8), Vector2(14, 6), 5.0))
	_write_png("res://modules/base_products/assets/map/icons/burger.png", img_burger, errors)

	# 3. 披萨 (Pizza) - 红色背景，三角形切片
	var img_pizza := _new_image(SIZE_ICON, SIZE_ICON)
	_draw_icon_bg(img_pizza, Color("c0392b")) # 红色
	# 披萨切片 (用三个半平面相交模拟三角形 SDF)
	_fill_sdf(img_pizza, Color("f1c40f"), func(p):
		# 这是一个简单的三角形距离场近似
		var p_local = p - (c + Vector2(0, 5))
		var d = maxf(absf(p_local.x) * 0.866025 + p_local.y * 0.5, -p_local.y)
		return d - 12.0
	)
	# 披萨饼边 (顶部圆弧)
	_fill_sdf(img_pizza, Color("d35400"), func(p): return _sdf_intersect(
		_sdf_circle(p, c + Vector2(0, -10), 14.0), # 圆弧
		_sdf_box(p, c + Vector2(0, -15), Vector2(16, 5)) # 限制在顶部
	))
	# 辣香肠 (上面的小圆点)
	_fill_sdf(img_pizza, Color("c0392b"), func(p): return _sdf_union(
		_sdf_circle(p, c + Vector2(-4, -2), 3.0),
		_sdf_circle(p, c + Vector2( 5,  4), 2.5)
	))
	_write_png("res://modules/base_products/assets/map/icons/pizza.png", img_pizza, errors)

	# 4. 苏打水 (Soda) - 蓝色背景，易拉罐形状
	var img_soda := _new_image(SIZE_ICON, SIZE_ICON)
	_draw_icon_bg(img_soda, Color("3498db")) # 蓝色
	# 罐身
	_fill_sdf(img_soda, Color.WHITE, func(p): return _sdf_rounded_box(p, c, Vector2(10, 16), 3.0))
	# 罐口拉环 (顶部小结构)
	_fill_sdf(img_soda, Color("bdc3c7"), func(p): return _sdf_box(p, c + Vector2(0, -16), Vector2(6, 2)))
	# 商标条纹 (中间色块)
	_fill_sdf(img_soda, Color("e74c3c"), func(p): return _sdf_box(p, c, Vector2(10, 6)))
	_write_png("res://modules/base_products/assets/map/icons/soda.png", img_soda, errors)

	# 5. 柠檬水 (Lemonade) - 黄色背景，带吸管的杯子
	var img_lemon := _new_image(SIZE_ICON, SIZE_ICON)
	_draw_icon_bg(img_lemon, Color("f1c40f")) # 黄色
	# 杯身
	_fill_sdf(img_lemon, Color.WHITE, func(p): return _sdf_rounded_box(p, c + Vector2(0, 4), Vector2(10, 12), 2.0))
	# 柠檬水液体
	_fill_sdf(img_lemon, Color("f7dc6f"), func(p): return _sdf_rounded_box(p, c + Vector2(0, 8), Vector2(9, 8), 1.0))
	# 吸管 (斜线，用细长矩形旋转模拟，这里简化为直线 SDF)
	_fill_sdf(img_lemon, Color("e74c3c"), func(p):
		# 直线 Ax + By + C = 0 的距离公式。这里模拟一条从左下到右上的线
		var p_rel = p - c
		# 简单近似：一条斜率约 1.5 的线
		var d_line = absf(p_rel.x * 1.5 + p_rel.y + 10.0) / sqrt(1.5*1.5 + 1.0)
		return d_line - 1.5 # 线宽
	)
	_write_png("res://modules/base_products/assets/map/icons/lemonade.png", img_lemon, errors)

# 营销图标保持简单符号 (已符合要求，不再赘述修改)
static func _generate_marketing_icons(errors: Array[String]) -> void:
	var items = ["marketing", "billboard", "radio", "mailbox", "airplane"]
	for item in items:
		var img := _new_image(SIZE_ICON, SIZE_ICON)
		_draw_icon_bg(img, Color("9b59b6")) # 紫色背景
		var c := Vector2(SIZE_ICON/2.0, SIZE_ICON/2.0)
		# 简单白色符号
		_fill_sdf(img, Color.WHITE, func(p): return _sdf_rounded_box(p, c, Vector2(12, 12), 4.0))
		_write_png("res://modules/base_marketing/assets/map/icons/%s.png" % item, img, errors)
