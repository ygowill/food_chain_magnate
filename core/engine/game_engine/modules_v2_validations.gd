# GameEngine：模块系统 V2（Strict Mode）校验辅助
# 目的：把 catalog/config 相关的结构校验从 modules_v2.gd 抽离，降低单文件职责与体积。
extends RefCounted

const ProductRegistryClass = preload("res://core/data/product_registry.gd")

static func validate_starting_inventory_products(cfg) -> Result:
	if cfg == null:
		return Result.failure("GameConfig 为空")

	if not (cfg.player_starting_inventory is Dictionary):
		return Result.failure("GameConfig.player.starting_inventory 类型错误（期望 Dictionary）")
	var inv: Dictionary = cfg.player_starting_inventory

	if not ProductRegistryClass.is_loaded():
		return Result.failure("ProductRegistry 未初始化")
	var product_ids: Array[String] = ProductRegistryClass.get_all_ids()
	if product_ids.is_empty():
		return Result.failure("ProductRegistry.products 为空：必须至少定义 1 个产品")

	var extras: Array[String] = []
	for k in inv.keys():
		if not (k is String):
			return Result.failure("GameConfig.player.starting_inventory key 类型错误（期望 String）")
		var key: String = str(k)
		if not ProductRegistryClass.has(key):
			extras.append(key)

	if not extras.is_empty():
		extras.sort()
		return Result.failure("GameConfig.player.starting_inventory 存在未知产品: %s" % ", ".join(extras))

	return Result.success()

static func validate_employee_train_to_references(catalog) -> Result:
	if catalog == null:
		return Result.failure("ContentCatalog 为空")
	if not (catalog.employees is Dictionary):
		return Result.failure("catalog.employees 类型错误（期望 Dictionary）")

	for emp_id_val in catalog.employees.keys():
		if not (emp_id_val is String):
			return Result.failure("catalog.employees key 类型错误（期望 String）")
		var emp_id: String = str(emp_id_val)
		if emp_id.is_empty():
			return Result.failure("catalog.employees key 不能为空")
		var def_val = catalog.employees.get(emp_id, null)
		if def_val == null:
			return Result.failure("catalog.employees[%s] 为空" % emp_id)
		if not (def_val is EmployeeDef):
			return Result.failure("catalog.employees[%s] 类型错误（期望 EmployeeDef）" % emp_id)
		var def: EmployeeDef = def_val

		for i in range(def.train_to.size()):
			var to_val = def.train_to[i]
			if not (to_val is String):
				return Result.failure("employees[%s].train_to[%d] 类型错误（期望 String）" % [emp_id, i])
			var to_id: String = str(to_val)
			if to_id.is_empty():
				return Result.failure("employees[%s].train_to[%d] 不能为空" % [emp_id, i])
			if not catalog.employees.has(to_id):
				return Result.failure("员工培训链引用不存在: %s.train_to -> %s" % [emp_id, to_id])

	return Result.success()

static func validate_content_product_references(catalog) -> Result:
	if catalog == null:
		return Result.failure("ContentCatalog 为空")

	if not ProductRegistryClass.is_loaded():
		return Result.failure("ProductRegistry 未初始化")

	# === employees.produces.food_type ===
	if not (catalog.employees is Dictionary):
		return Result.failure("catalog.employees 类型错误（期望 Dictionary）")
	for emp_id_val in catalog.employees.keys():
		if not (emp_id_val is String):
			return Result.failure("catalog.employees key 类型错误（期望 String）")
		var emp_id: String = str(emp_id_val)
		var emp_def_val = catalog.employees.get(emp_id, null)
		if emp_def_val == null:
			return Result.failure("catalog.employees[%s] 为空" % emp_id)
		if not (emp_def_val is EmployeeDef):
			return Result.failure("catalog.employees[%s] 类型错误（期望 EmployeeDef）" % emp_id)
		var emp_def: EmployeeDef = emp_def_val
		if emp_def.can_produce():
			var options: Array[String] = emp_def.get_production_food_options()
			for i in range(options.size()):
				var food_type: String = str(options[i])
				var check := _validate_product_reference(food_type, "EmployeeDef[%s].production_food_options[%d]" % [emp_id, i], false, "food")
				if not check.ok:
					return check

	# === tiles.drink_sources[*].type ===
	if not (catalog.tiles is Dictionary):
		return Result.failure("catalog.tiles 类型错误（期望 Dictionary）")
	for tile_id_val in catalog.tiles.keys():
		if not (tile_id_val is String):
			return Result.failure("catalog.tiles key 类型错误（期望 String）")
		var tile_id: String = str(tile_id_val)
		var tile_def_val = catalog.tiles.get(tile_id, null)
		if tile_def_val == null:
			return Result.failure("catalog.tiles[%s] 为空" % tile_id)
		if not (tile_def_val is TileDef):
			return Result.failure("catalog.tiles[%s] 类型错误（期望 TileDef）" % tile_id)
		var tile_def: TileDef = tile_def_val
		for i in range(tile_def.drink_sources.size()):
			var src_val = tile_def.drink_sources[i]
			if not (src_val is Dictionary):
				return Result.failure("TileDef[%s].drink_sources[%d] 类型错误（期望 Dictionary）" % [tile_id, i])
			var src: Dictionary = src_val
			var t_val = src.get("type", null)
			if not (t_val is String):
				return Result.failure("TileDef[%s].drink_sources[%d].type 类型错误（期望 String）" % [tile_id, i])
			var drink_type: String = str(t_val)
			var check2 := _validate_product_reference(drink_type, "TileDef[%s].drink_sources[%d].type" % [tile_id, i], false, "drink")
			if not check2.ok:
				return check2

	# === milestones trigger/effects 中的 product 引用 ===
	if not (catalog.milestones is Dictionary):
		return Result.failure("catalog.milestones 类型错误（期望 Dictionary）")
	for mid_val in catalog.milestones.keys():
		if not (mid_val is String):
			return Result.failure("catalog.milestones key 类型错误（期望 String）")
		var mid: String = str(mid_val)
		var ms_def_val = catalog.milestones.get(mid, null)
		if ms_def_val == null:
			return Result.failure("catalog.milestones[%s] 为空" % mid)
		if not (ms_def_val is MilestoneDef):
			return Result.failure("catalog.milestones[%s] 类型错误（期望 MilestoneDef）" % mid)
		var ms_def: MilestoneDef = ms_def_val

		var filter_check := _validate_product_keys_in_variant(ms_def.trigger_filter, "MilestoneDef[%s].trigger.filter" % mid)
		if not filter_check.ok:
			return filter_check

		for e_i in range(ms_def.effects.size()):
			var eff_val = ms_def.effects[e_i]
			var eff_check := _validate_product_keys_in_variant(eff_val, "MilestoneDef[%s].effects[%d]" % [mid, e_i])
			if not eff_check.ok:
				return eff_check

	return Result.success()

static func _validate_product_keys_in_variant(value, path: String) -> Result:
	if value is Dictionary:
		var d: Dictionary = value
		for k in d.keys():
			var key: String = str(k)
			var child_path := "%s.%s" % [path, key]
			if key == "product":
				var p_val = d.get(k, null)
				if not (p_val is String):
					return Result.failure("%s 类型错误（期望 String）" % child_path)
				var p: String = str(p_val)
				var pr := _validate_product_reference(p, child_path, true, "")
				if not pr.ok:
					return pr
			var nested := _validate_product_keys_in_variant(d.get(k, null), child_path)
			if not nested.ok:
				return nested
		return Result.success()
	if value is Array:
		var a: Array = value
		for i in range(a.size()):
			var nested2 := _validate_product_keys_in_variant(a[i], "%s[%d]" % [path, i])
			if not nested2.ok:
				return nested2
		return Result.success()
	return Result.success()

static func _validate_product_reference(product_id: String, path: String, allow_drink_category: bool, required_tag: String) -> Result:
	if product_id.is_empty():
		return Result.failure("%s 不能为空" % path)
	if allow_drink_category and product_id == "drink":
		return Result.success()
	if product_id == "drink":
		return Result.failure("%s 不允许为保留字: drink" % path)
	if not ProductRegistryClass.has(product_id):
		return Result.failure("%s 未知产品: %s" % [path, product_id])

	if not required_tag.is_empty():
		var def = ProductRegistryClass.get_def(product_id)
		if def == null:
			return Result.failure("%s 未知产品: %s" % [path, product_id])
		if not def.has_method("has_tag") or not def.has_tag(required_tag):
			return Result.failure("%s 必须带 tag=%s，实际: %s" % [path, required_tag, product_id])

	return Result.success()

