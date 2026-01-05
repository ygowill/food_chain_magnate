# 模块系统 V2：从模块包 content/ 加载每局 ContentCatalog（员工/里程碑/营销板件）
class_name ContentCatalogLoader
extends RefCounted

const ContentCatalogClass = preload("res://core/modules/v2/content_catalog.gd")
const ProductDefClass = preload("res://core/data/product_def.gd")
const EmployeeDefClass = preload("res://core/data/employee_def.gd")
const MarketingDefClass = preload("res://core/data/marketing_def.gd")
const MilestoneDefClass = preload("res://core/data/milestone_def.gd")
const TileDefClass = preload("res://core/map/tile_def.gd")
const MapOptionDefClass = preload("res://core/map/map_option_def.gd")
const PieceDefClass = preload("res://core/map/piece_def.gd")
const ModulePackageLoaderClass = preload("res://core/modules/v2/module_package_loader.gd")

static func load_for_modules(base_dir: String, module_ids: Array[String]) -> Result:
	if base_dir.is_empty():
		return Result.failure("ContentCatalogLoader: base_dir 不能为空")
	return load_for_modules_from_dirs([base_dir], module_ids)

static func load_for_modules_from_dirs(base_dirs: Array, module_ids: Array[String]) -> Result:
	if base_dirs == null or not (base_dirs is Array):
		return Result.failure("ContentCatalogLoader: base_dirs 类型错误（期望 Array[String]）")
	if base_dirs.is_empty():
		return Result.failure("ContentCatalogLoader: base_dirs 不能为空")

	var catalog = ContentCatalogClass.new()

	for i in range(module_ids.size()):
		var mid_val = module_ids[i]
		if not (mid_val is String):
			return Result.failure("module_ids[%d] 类型错误（期望 String）" % i)
		var module_id: String = str(mid_val)
		if module_id.is_empty():
			return Result.failure("module_ids[%d] 不能为空" % i)

		var root_read := ModulePackageLoaderClass.resolve_module_root(base_dirs, module_id)
		if not root_read.ok:
			return root_read
		var module_root: String = root_read.value

		var content_root := module_root.path_join("content")
		var prod_read := _load_products_dir(catalog, content_root.path_join("products"), module_id)
		if not prod_read.ok:
			return prod_read
		var emp_read := _load_employees_dir(catalog, content_root.path_join("employees"), module_id)
		if not emp_read.ok:
			return emp_read
		var ms_read := _load_milestones_dir(catalog, content_root.path_join("milestones"), module_id)
		if not ms_read.ok:
			return ms_read
		var mk_read := _load_marketing_dir(catalog, content_root.path_join("marketing"), module_id)
		if not mk_read.ok:
			return mk_read
		var tiles_read := _load_tiles_dir(catalog, content_root.path_join("tiles"), module_id)
		if not tiles_read.ok:
			return tiles_read
		var maps_read := _load_maps_dir(catalog, content_root.path_join("maps"), module_id)
		if not maps_read.ok:
			return maps_read
		var pieces_read := _load_pieces_dir(catalog, content_root.path_join("pieces"), module_id)
		if not pieces_read.ok:
			return pieces_read

	return Result.success(catalog)

static func _load_products_dir(catalog, dir_path: String, module_id: String) -> Result:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return Result.success()

	var files_read := _list_json_files(dir_path)
	if not files_read.ok:
		return files_read

	for file_name in files_read.value:
		var path := dir_path.path_join(file_name)
		var prod_read := ProductDefClass.load_from_file(path)
		if not prod_read.ok:
			return Result.failure("加载产品定义失败: %s (%s)" % [path, prod_read.error])
		var prod = prod_read.value
		if prod == null:
			return Result.failure("产品定义解析失败: %s" % path)
		var product_id: String = prod.id
		if catalog.products.has(product_id):
			var prev_src: String = str(catalog.product_sources.get(product_id, ""))
			return Result.failure("产品定义重复: %s (modules: %s, %s)" % [product_id, prev_src, module_id])
		catalog.products[product_id] = prod
		catalog.product_sources[product_id] = module_id

	return Result.success()

static func _load_employees_dir(catalog, dir_path: String, module_id: String) -> Result:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return Result.success()

	var files_read := _list_json_files(dir_path)
	if not files_read.ok:
		return files_read

	for file_name in files_read.value:
		var path := dir_path.path_join(file_name)
		var emp_read := EmployeeDefClass.load_from_file(path)
		if not emp_read.ok:
			return Result.failure("加载员工定义失败: %s (%s)" % [path, emp_read.error])
		var emp = emp_read.value
		if emp == null:
			return Result.failure("员工定义解析失败: %s" % path)
		var emp_id: String = emp.id
		if catalog.employees.has(emp_id):
			var prev_src: String = str(catalog.employee_sources.get(emp_id, ""))
			return Result.failure("员工定义重复: %s (modules: %s, %s)" % [emp_id, prev_src, module_id])
		catalog.employees[emp_id] = emp
		catalog.employee_sources[emp_id] = module_id

	return Result.success()

static func _load_milestones_dir(catalog, dir_path: String, module_id: String) -> Result:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return Result.success()

	var files_read := _list_json_files(dir_path)
	if not files_read.ok:
		return files_read

	for file_name in files_read.value:
		var path := dir_path.path_join(file_name)
		var ms_read := MilestoneDefClass.load_from_file(path)
		if not ms_read.ok:
			return Result.failure("加载里程碑定义失败: %s (%s)" % [path, ms_read.error])
		var ms = ms_read.value
		if ms == null:
			return Result.failure("里程碑定义解析失败: %s" % path)
		var ms_id: String = ms.id
		if catalog.milestones.has(ms_id):
			var prev_src: String = str(catalog.milestone_sources.get(ms_id, ""))
			return Result.failure("里程碑定义重复: %s (modules: %s, %s)" % [ms_id, prev_src, module_id])
		catalog.milestones[ms_id] = ms
		catalog.milestone_sources[ms_id] = module_id

	return Result.success()

static func _load_marketing_dir(catalog, dir_path: String, module_id: String) -> Result:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return Result.success()

	var files_read := _list_json_files(dir_path)
	if not files_read.ok:
		return files_read

	for file_name in files_read.value:
		var path := dir_path.path_join(file_name)
		var mk_read := MarketingDefClass.load_from_file(path)
		if not mk_read.ok:
			return Result.failure("加载营销板件定义失败: %s (%s)" % [path, mk_read.error])
		var mk = mk_read.value
		if mk == null:
			return Result.failure("营销板件定义解析失败: %s" % path)

		var board_number: int = int(mk.board_number)
		if board_number <= 0:
			return Result.failure("营销板件 board_number 必须 > 0: %s" % path)
		if catalog.marketing.has(board_number):
			var prev_src: String = str(catalog.marketing_sources.get(board_number, ""))
			return Result.failure("营销板件定义重复: #%d (modules: %s, %s)" % [board_number, prev_src, module_id])

		catalog.marketing[board_number] = mk
		catalog.marketing_sources[board_number] = module_id

	return Result.success()

static func _load_tiles_dir(catalog, dir_path: String, module_id: String) -> Result:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return Result.success()

	var files_read := _list_json_files(dir_path)
	if not files_read.ok:
		return files_read

	for file_name in files_read.value:
		var path := dir_path.path_join(file_name)
		var tile_read := TileDefClass.load_from_file(path)
		if not tile_read.ok:
			return Result.failure("加载板块定义失败: %s (%s)" % [path, tile_read.error])
		var tile = tile_read.value
		if tile == null:
			return Result.failure("板块定义解析失败: %s" % path)
		var tile_id: String = str(tile.id)
		if tile_id.is_empty():
			return Result.failure("板块定义缺少 id: %s" % path)
		if catalog.tiles.has(tile_id):
			var prev_src: String = str(catalog.tile_sources.get(tile_id, ""))
			return Result.failure("板块定义重复: %s (modules: %s, %s)" % [tile_id, prev_src, module_id])
		catalog.tiles[tile_id] = tile
		catalog.tile_sources[tile_id] = module_id

	return Result.success()

static func _load_maps_dir(catalog, dir_path: String, module_id: String) -> Result:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return Result.success()

	var files_read := _list_json_files(dir_path)
	if not files_read.ok:
		return files_read

	for file_name in files_read.value:
		var path := dir_path.path_join(file_name)
		var map_read := MapOptionDefClass.load_from_file(path)
		if not map_read.ok:
			return Result.failure("加载地图定义失败: %s (%s)" % [path, map_read.error])
		var map = map_read.value
		if map == null:
			return Result.failure("地图定义解析失败: %s" % path)
		var map_id: String = str(map.id)
		if map_id.is_empty():
			return Result.failure("地图定义缺少 id: %s" % path)
		if catalog.maps.has(map_id):
			var prev_src: String = str(catalog.map_sources.get(map_id, ""))
			return Result.failure("地图定义重复: %s (modules: %s, %s)" % [map_id, prev_src, module_id])
		catalog.maps[map_id] = map
		catalog.map_sources[map_id] = module_id

	return Result.success()

static func _load_pieces_dir(catalog, dir_path: String, module_id: String) -> Result:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return Result.success()

	var files_read := _list_json_files(dir_path)
	if not files_read.ok:
		return files_read

	for file_name in files_read.value:
		var path := dir_path.path_join(file_name)
		var piece_read := PieceDefClass.load_from_file(path)
		if not piece_read.ok:
			return Result.failure("加载建筑件定义失败: %s (%s)" % [path, piece_read.error])
		var piece = piece_read.value
		if piece == null:
			return Result.failure("建筑件定义解析失败: %s" % path)
		var piece_id: String = str(piece.id)
		if piece_id.is_empty():
			return Result.failure("建筑件定义缺少 id: %s" % path)
		if catalog.pieces.has(piece_id):
			var prev_src: String = str(catalog.piece_sources.get(piece_id, ""))
			return Result.failure("建筑件定义重复: %s (modules: %s, %s)" % [piece_id, prev_src, module_id])
		catalog.pieces[piece_id] = piece
		catalog.piece_sources[piece_id] = module_id

	return Result.success()

static func _list_json_files(dir_path: String) -> Result:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return Result.failure("无法读取目录: %s" % dir_path)

	var json_files: Array[String] = []
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while not file_name.is_empty():
		if not dir.current_is_dir() and file_name.to_lower().ends_with(".json"):
			json_files.append(file_name)
		file_name = dir.get_next()
	dir.list_dir_end()

	json_files.sort()
	return Result.success(json_files)
